import Foundation
import WebKit
import os.log

private let logger = Logger(subsystem: "com.claudetokenmonitor", category: "ClaudeAPIClient")

/// File-based debug log (os.log info/debug gets filtered out by macOS)
private func debugLog(_ message: String) {
    let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClaudeTokenMonitor-api.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

// MARK: - API Response Models

struct UsageResponse: Codable {
    let five_hour: WindowResponse
    let seven_day: WindowResponse
    let extra_usage: ExtraUsageResponse
}

struct WindowResponse: Codable {
    let utilization: Double  // 0-100 (Double for robustness — API may return int or float)
    let resets_at: String?   // ISO 8601 date, null when no active window
}

struct ExtraUsageResponse: Codable {
    let is_enabled: Bool
    let used_credits: Int        // cents
    let monthly_limit: Int?      // cents, null if unlimited
}

struct PrepaidCreditsResponse: Codable {
    let amount: Int              // cents
    let currency: String
    let auto_reload_settings: AutoReloadSettings?
}

struct AutoReloadSettings: Codable {
    // Placeholder — fields vary by account type
}

struct OverageSpendResponse: Codable {
    let is_enabled: Bool
    let monthly_credit_limit: Int?  // cents
    let currency: String?
    let used_credits: Int           // cents
    let disabled_reason: String?
    let out_of_credits: Bool?
}

struct ClaudeAPIData {
    let usage: UsageResponse?
    let prepaidCredits: PrepaidCreditsResponse?
    let overage: OverageSpendResponse?
    let fetchedAt: Date
}

// MARK: - ClaudeAPIClient (WKWebView-based)

@MainActor
final class ClaudeAPIClient: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var latestData: ClaudeAPIData?
    @Published var isLoggedIn: Bool = false
    @Published var needsLogin: Bool = false
    @Published var lastError: String?

    private var loginWindow: NSWindow?
    private var loginWebView: WKWebView?
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var navigationContinuation: CheckedContinuation<Void, Never>?
    /// Persistent webView reused across fetch cycles
    private var activeWebView: WKWebView?
    /// Guard against overlapping fetches
    private var isFetching = false

    // Shared data store so login session persists across app launches
    private static let dataStore: WKWebsiteDataStore = .default()

    override init() {
        super.init()
    }

    // MARK: - Public API

    func fetchAll() async {
        // Prevent overlapping fetches (avoids CPU spin from stacked timers)
        guard !isFetching else {
            debugLog("Skipping fetch — previous fetch still in progress")
            return
        }
        isFetching = true
        defer { isFetching = false }

        debugLog("fetchAll() starting...")

        // Reuse a single WKWebView across fetch cycles to keep cookies/session stable
        let wv: WKWebView
        if let existing = activeWebView {
            wv = existing
            debugLog("Reusing existing WKWebView, url=\(wv.url?.absoluteString ?? "nil")")
        } else {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = Self.dataStore
            let newWV = WKWebView(frame: .zero, configuration: config)
            newWV.navigationDelegate = self
            activeWebView = newWV
            wv = newWV
            debugLog("Created new WKWebView")
        }

        // Make sure we're on claude.ai domain first
        if wv.url?.host != "claude.ai" {
            debugLog("Navigating to claude.ai/settings/usage...")
            await loadAndWait(webView: wv, url: URL(string: "https://claude.ai/settings/usage")!)
        }

        let currentURL = wv.url?.absoluteString ?? ""
        let currentPath = wv.url?.path ?? ""
        debugLog("After navigation: url=\(currentURL), path=\(currentPath)")

        // Check if we got redirected to login
        if currentPath.contains("login") || currentPath.contains("oauth") || currentURL.contains("login") {
            debugLog("Redirected to login page — showing login window")
            needsLogin = true
            isLoggedIn = false
            lastError = "Anmeldung bei claude.ai erforderlich"
            await showLoginWindow()
            // After login, retry
            await loadAndWait(webView: wv, url: URL(string: "https://claude.ai/settings/usage")!)
            debugLog("After login, url=\(wv.url?.absoluteString ?? "nil")")
        }

        isLoggedIn = true
        needsLogin = false

        // Get orgId from cookie (simple sync JS, no fetch needed)
        let cookieJS = "document.cookie.split(';').map(c => c.trim()).find(c => c.startsWith('lastActiveOrg='))?.split('=')?.[1] || ''"
        let orgId: String?
        do {
            orgId = try await wv.evaluateJavaScript(cookieJS) as? String
            debugLog("orgId from cookie: \(orgId ?? "<empty>")")
        } catch {
            debugLog("Cookie JS error: \(error.localizedDescription)")
            orgId = nil
        }

        lastError = nil
        guard let orgId, !orgId.isEmpty else {
            // Try extracting from page content instead
            let pageOrgJS = """
            (() => {
                const scripts = document.querySelectorAll('script');
                for (const s of scripts) {
                    const match = s.textContent.match(/"organization":\\s*\\{[^}]*"uuid":\\s*"([^"]+)"/);
                    if (match) return match[1];
                }
                // Try meta or data attributes
                const el = document.querySelector('[data-org-id]');
                if (el) return el.dataset.orgId;
                return '';
            })()
            """
            let fallbackOrgId = try? await wv.evaluateJavaScript(pageOrgJS) as? String
            guard let fallbackOrgId, !fallbackOrgId.isEmpty else {
                debugLog("Could not determine orgId from any source")
                lastError = "Keine orgId gefunden"
                return
            }
            debugLog("orgId from page scan: \(fallbackOrgId)")
            await fetchAPIData(webView: wv, orgId: fallbackOrgId)
            return
        }

        await fetchAPIData(webView: wv, orgId: orgId)
    }

    private func fetchAPIData(webView: WKWebView, orgId: String) async {
        debugLog("fetchAPIData for org: \(orgId)")

        // Fetch all endpoints via async JS fetch (uses WKWebView's cookies)
        // Include status codes and error text for debugging
        let fetchJS = """
        const orgId = orgIdParam;
        const results = {};
        const errors = {};
        const endpoints = {
            usage: `/api/organizations/${orgId}/usage`,
            credits: `/api/organizations/${orgId}/prepaid/credits`,
            overage: `/api/organizations/${orgId}/overage_spend_limit`
        };
        for (const [key, url] of Object.entries(endpoints)) {
            try {
                const resp = await fetch(url);
                if (resp.ok) {
                    results[key] = await resp.json();
                } else {
                    results[key] = null;
                    errors[key] = `HTTP ${resp.status}: ${resp.statusText}`;
                }
            } catch (e) {
                results[key] = null;
                errors[key] = e.message || String(e);
            }
        }
        return JSON.stringify({ results, errors });
        """

        let resultStr: String?
        do {
            let result = try await webView.callAsyncJavaScript(fetchJS, arguments: ["orgIdParam": orgId], contentWorld: .page)
            resultStr = result as? String
        } catch {
            debugLog("JS fetch error: \(error.localizedDescription)")
            lastError = "JS fetch: \(error.localizedDescription)"
            resultStr = nil
        }

        guard let resultStr, let resultData = resultStr.data(using: .utf8) else {
            debugLog("JS fetch returned no data")
            if lastError == nil { lastError = "Keine API-Daten empfangen" }
            return
        }

        debugLog("API response: \(resultStr.prefix(1000))")

        let decoder = JSONDecoder()

        // Parse each response
        var usage: UsageResponse?
        var credits: PrepaidCreditsResponse?
        var overage: OverageSpendResponse?

        if let wrapper = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            // Extract results and errors from the wrapper
            let json = wrapper["results"] as? [String: Any] ?? wrapper
            let errors = wrapper["errors"] as? [String: String] ?? [:]

            // Log any API errors
            for (endpoint, errorMsg) in errors {
                debugLog("API error for \(endpoint): \(errorMsg)")
                lastError = "\(endpoint): \(errorMsg)"
            }

            if let usageJSON = json["usage"], !(usageJSON is NSNull),
               let usageData = try? JSONSerialization.data(withJSONObject: usageJSON) {
                do {
                    usage = try decoder.decode(UsageResponse.self, from: usageData)
                    debugLog("Usage decoded OK: 5h=\(usage!.five_hour.utilization)%, 7d=\(usage!.seven_day.utilization)%")
                } catch {
                    debugLog("Usage decode error: \(error)")
                    if let raw = String(data: usageData, encoding: .utf8) {
                        debugLog("Usage raw JSON: \(raw.prefix(500))")
                    }
                }
            }
            if let creditsJSON = json["credits"], !(creditsJSON is NSNull),
               let creditsData = try? JSONSerialization.data(withJSONObject: creditsJSON) {
                do {
                    credits = try decoder.decode(PrepaidCreditsResponse.self, from: creditsData)
                    debugLog("Credits decoded OK: \(credits!.amount) \(credits!.currency)")
                } catch {
                    debugLog("Credits decode error: \(error)")
                    if let raw = String(data: creditsData, encoding: .utf8) {
                        debugLog("Credits raw JSON: \(raw.prefix(500))")
                    }
                }
            }
            if let overageJSON = json["overage"], !(overageJSON is NSNull),
               let overageData = try? JSONSerialization.data(withJSONObject: overageJSON) {
                do {
                    overage = try decoder.decode(OverageSpendResponse.self, from: overageData)
                    debugLog("Overage decoded OK: enabled=\(overage!.is_enabled), used=\(overage!.used_credits)c")
                } catch {
                    debugLog("Overage decode error: \(error)")
                    if let raw = String(data: overageData, encoding: .utf8) {
                        debugLog("Overage raw JSON: \(raw.prefix(500))")
                    }
                }
            }
        } else {
            debugLog("Failed to parse JSON wrapper")
        }

        if usage != nil || credits != nil || overage != nil {
            lastError = nil
        }

        latestData = ClaudeAPIData(
            usage: usage,
            prepaidCredits: credits,
            overage: overage,
            fetchedAt: Date()
        )
        debugLog("Fetch complete: usage=\(usage != nil), credits=\(credits != nil), overage=\(overage != nil)")

        logger.info("Fetch complete: usage=\(usage != nil), credits=\(credits != nil), overage=\(overage != nil)")
        if let credits {
            logger.info("Credit balance: \(credits.amount) cents (\(credits.currency))")
        }
        if let usage {
            logger.info("5h: \(usage.five_hour.utilization)%, 7d: \(usage.seven_day.utilization)%, extra spent: \(usage.extra_usage.used_credits)c")
        }
    }

    // MARK: - Login Window

    private func showLoginWindow() async {
        if loginWindow != nil { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore
        let lwv = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 600), configuration: config)
        loginWebView = lwv
        lwv.navigationDelegate = self

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bei Claude anmelden"
        window.contentView = lwv
        window.center()
        window.makeKeyAndOrderFront(nil)
        loginWindow = window

        lwv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        // Wait until login completes (detected by navigation to claude.ai main page)
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }

        // Login done — close window and retry fetch
        loginWindow?.close()
        loginWindow = nil
        loginWebView = nil
        needsLogin = false
        isLoggedIn = true
    }

    /// Load a URL in a webView and wait for navigation to finish
    private func loadAndWait(webView: WKWebView, url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
        // Extra buffer for JS framework to initialize
        try? await Task.sleep(for: .seconds(1))
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url else { return }
            logger.info("Page loaded: \(url.absoluteString)")

            // Main webView navigation completed
            if webView === self.activeWebView {
                if let continuation = self.navigationContinuation {
                    self.navigationContinuation = nil
                    continuation.resume()
                }
            }

            // If the login webView navigated to a non-login page, login is complete
            if webView === self.loginWebView,
               url.host == "claude.ai",
               !url.path.contains("login"),
               !url.path.contains("oauth") {
                logger.info("Login completed!")
                if let continuation = self.pendingContinuation {
                    self.pendingContinuation = nil
                    continuation.resume()
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.info("Navigation failed: \(error.localizedDescription)")
            if webView === self.activeWebView {
                if let continuation = self.navigationContinuation {
                    self.navigationContinuation = nil
                    continuation.resume()
                }
            }
        }
    }
}

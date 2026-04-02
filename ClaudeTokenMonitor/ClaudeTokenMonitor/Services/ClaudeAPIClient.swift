import Foundation
import WebKit
import os.log

private let logger = Logger(subsystem: "com.claudetokenmonitor", category: "ClaudeAPIClient")

// MARK: - API Response Models

struct UsageResponse: Codable {
    let five_hour: WindowResponse
    let seven_day: WindowResponse
    let extra_usage: ExtraUsageResponse
}

struct WindowResponse: Codable {
    let utilization: Int  // 0-100 integer
    let resets_at: String // ISO 8601 date
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

    private var loginWindow: NSWindow?
    private var loginWebView: WKWebView?
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var navigationContinuation: CheckedContinuation<Void, Never>?
    /// Temporary webView active only during a fetchAll() call
    private var activeWebView: WKWebView?

    // Shared data store so login session persists across app launches
    private static let dataStore: WKWebsiteDataStore = .default()

    override init() {
        super.init()
    }

    // MARK: - Public API

    func fetchAll() async {
        // Create a temporary WKWebView for this fetch cycle, release it when done
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        activeWebView = wv
        defer {
            wv.navigationDelegate = nil
            activeWebView = nil
        }

        // Make sure we're on claude.ai domain first
        if wv.url?.host != "claude.ai" {
            logger.info("Navigating to claude.ai...")
            await loadAndWait(webView: wv, url: URL(string: "https://claude.ai/settings/usage")!)
        }

        let currentURL = wv.url?.absoluteString ?? ""
        let currentPath = wv.url?.path ?? ""
        logger.info("Page loaded, path contains 'login': \(currentPath.contains("login"))")

        // Check if we got redirected to login
        if currentPath.contains("login") || currentPath.contains("oauth") || currentURL.contains("login") {
            logger.info("Redirected to login page — showing login window")
            needsLogin = true
            isLoggedIn = false
            await showLoginWindow()
            // After login, retry
            await loadAndWait(webView: wv, url: URL(string: "https://claude.ai/settings/usage")!)
        }

        isLoggedIn = true
        needsLogin = false

        // Get orgId from cookie (simple sync JS, no fetch needed)
        let cookieJS = "document.cookie.split(';').map(c => c.trim()).find(c => c.startsWith('lastActiveOrg='))?.split('=')?.[1] || ''"
        let orgId: String?
        do {
            orgId = try await wv.evaluateJavaScript(cookieJS) as? String
            logger.info("orgId from cookie: \(orgId ?? "nil")")
        } catch {
            logger.info("Cookie JS error: \(error.localizedDescription)")
            orgId = nil
        }

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
                logger.info("Could not determine orgId from any source")
                return
            }
            logger.info("orgId from page scan: \(fallbackOrgId)")
            await fetchAPIData(webView: wv, orgId: fallbackOrgId)
            return
        }

        await fetchAPIData(webView: wv, orgId: orgId)
    }

    private func fetchAPIData(webView: WKWebView, orgId: String) async {
        logger.info("Fetching data for org: \(orgId)")

        // Fetch all endpoints via async JS fetch (uses WKWebView's cookies)
        let fetchJS = """
        const orgId = orgIdParam;
        const results = {};
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
                }
            } catch (e) {
                results[key] = null;
            }
        }
        return JSON.stringify(results);
        """

        let resultStr: String?
        do {
            let result = try await webView.callAsyncJavaScript(fetchJS, arguments: ["orgIdParam": orgId], contentWorld: .page)
            resultStr = result as? String
        } catch {
            logger.info("JS fetch error: \(error.localizedDescription)")
            resultStr = nil
        }

        guard let resultStr, let resultData = resultStr.data(using: .utf8) else {
            logger.info("JS fetch returned no data")
            return
        }

        let decoder = JSONDecoder()

        // Parse each response
        var usage: UsageResponse?
        var credits: PrepaidCreditsResponse?
        var overage: OverageSpendResponse?

        if let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            if let usageJSON = json["usage"], !(usageJSON is NSNull),
               let usageData = try? JSONSerialization.data(withJSONObject: usageJSON) {
                usage = try? decoder.decode(UsageResponse.self, from: usageData)
            }
            if let creditsJSON = json["credits"], !(creditsJSON is NSNull),
               let creditsData = try? JSONSerialization.data(withJSONObject: creditsJSON) {
                credits = try? decoder.decode(PrepaidCreditsResponse.self, from: creditsData)
            }
            if let overageJSON = json["overage"], !(overageJSON is NSNull),
               let overageData = try? JSONSerialization.data(withJSONObject: overageJSON) {
                overage = try? decoder.decode(OverageSpendResponse.self, from: overageData)
            }
        }

        latestData = ClaudeAPIData(
            usage: usage,
            prepaidCredits: credits,
            overage: overage,
            fetchedAt: Date()
        )

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

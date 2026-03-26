import SwiftUI

struct MenubarView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Claude Token Monitor")
                .font(.headline)
            Text("Token tracking coming in Phase 2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 320, height: 240)
    }
}

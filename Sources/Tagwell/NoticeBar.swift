import SwiftUI

/// The one place Tagwell reports a problem: a bar above the editor that stays until it is closed.
/// A long list (files that were not saved) scrolls inside the bar instead of pushing the editor away.
struct NoticeBar: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            ViewThatFits(in: .vertical) {
                text
                ScrollView { text }
                    .frame(height: 120)
            }

            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Close this message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Problem")
    }

    private var text: some View {
        Text(message)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

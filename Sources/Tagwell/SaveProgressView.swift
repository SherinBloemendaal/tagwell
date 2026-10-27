import SwiftUI

/// Shown while several files are being saved, so a long save of big DJ sets is visible and can be stopped.
struct SaveProgressView: View {
    let library: Library

    var body: some View {
        if let progress = library.saveProgress {
            VStack(alignment: .leading, spacing: 12) {
                Text(progress.isStopping ? "Stopping after this file…" : "Saving \(min(progress.completed + 1, progress.total)) of \(progress.total) files")
                    .font(.headline)
                    .monospacedDigit()
                ProgressView(value: progress.fraction)
                Text(progress.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Spacer()
                    Button("Stop") { library.stopSaving() }
                        .disabled(progress.isStopping)
                        .help("Finish the file that is being written, then stop. The other files keep their unsaved changes.")
                }
            }
            .padding(20)
            .frame(width: 400)
        }
    }
}

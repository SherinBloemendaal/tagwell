import ID3Kit
import SwiftUI

/// Downloads a YouTube video's thumbnail and uses it as cover art.
struct YouTubeThumbnailSheet: View {
    @Binding var artwork: Artwork?
    @State var link: String
    @State private var cropToSquare = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use a YouTube Thumbnail")
                .font(.headline)
            TextField("YouTube link", text: $link, prompt: Text("https://www.youtube.com/watch?v=…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await useThumbnail() } }
            Toggle("Crop to a square", isOn: $cropToSquare)
                .help("Keep the middle of the 16:9 thumbnail")
            Text("YouTube thumbnails are 16:9. Most music apps show cover art as a square, so cropping keeps the middle of the image.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Thumbnail") { Task { await useThumbnail() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading || YouTube.videoID(from: link) == nil)
                    .help("Download the thumbnail and set it as cover art")
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func useThumbnail() async {
        guard let videoID = YouTube.videoID(from: link) else {
            errorMessage = ArtworkError.notAYouTubeLink.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            artwork = try await Artwork.youTubeThumbnail(videoID: videoID, cropToSquare: cropToSquare)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

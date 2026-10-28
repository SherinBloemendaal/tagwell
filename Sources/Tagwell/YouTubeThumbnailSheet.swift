import ID3Kit
import SwiftUI

/// Picks a YouTube video and uses its thumbnail as cover art: by searching (through yt-dlp)
/// or by pasting a link.
struct YouTubeThumbnailSheet: View {
    @Binding var artwork: Artwork?
    /// A link to a video the file came from, when one was found.
    let suggestedLink: String
    /// What to search for when the sheet opens, usually "Artist - Title".
    let suggestedSearch: String

    @State private var mode: Mode
    @State private var link: String
    @State private var query: String
    @State private var results = YouTubeResults()
    @State private var isSearching = false
    @State private var searchedQuery: String?
    @State private var selection: YouTubeVideo.ID?
    @State private var cropToSquare = true
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable {
        case search, link
    }

    init(artwork: Binding<Artwork?>, suggestedLink: String, suggestedSearch: String) {
        _artwork = artwork
        self.suggestedLink = suggestedLink
        self.suggestedSearch = suggestedSearch
        // A file that came from YouTube already says which video it is.
        _mode = State(initialValue: suggestedLink.isEmpty ? .search : .link)
        _link = State(initialValue: suggestedLink)
        _query = State(initialValue: suggestedSearch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cover Art from YouTube")
                    .font(.headline)
                Spacer()
                Picker("Find the video by", selection: $mode) {
                    Text("Search").tag(Mode.search)
                    Text("Link").tag(Mode.link)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch mode {
            case .search: searchView
            case .link: linkView
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Toggle("Crop to a square", isOn: $cropToSquare)
                    .help("YouTube thumbnails are 16:9; most music apps show cover art as a square, so this keeps the middle")
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Thumbnail") { Task { await useThumbnail() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isDownloading || chosenVideoID == nil)
                    .help("Download the largest version of this thumbnail and set it as cover art")
            }
        }
        .padding(20)
        .frame(width: 720, height: mode == .search ? 600 : nil)
        .onAppear {
            if mode == .search, !query.isEmpty {
                startSearch()
            }
        }
        .onChange(of: mode) {
            errorMessage = nil
            if mode == .search, results.fetched.isEmpty, !query.isEmpty, !isSearching {
                startSearch()
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: Search

    private var searchView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search YouTube", text: $query, prompt: Text("Artist - Title"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startSearch)
                Button("Search", action: startSearch)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                    .help("Search YouTube with yt-dlp")
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 14) {
                    ForEach(results.shown) { video in
                        ResultCell(video: video, isSelected: video.id == selection)
                            .onTapGesture { selection = video.id }
                            .onTapGesture(count: 2) {
                                selection = video.id
                                Task { await useThumbnail() }
                            }
                    }
                }
                .padding(2)

                if isSearching {
                    ProgressView()
                        .padding()
                } else if results.hasMore {
                    Button("Load More", action: loadMore)
                        .help("Show the next \(YouTubeSearch.pageSize) results")
                        .padding(.vertical, 8)
                } else if let searchedQuery, results.fetched.isEmpty, errorMessage == nil {
                    Text("No videos found for \"\(searchedQuery)\".")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func startSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        results = YouTubeResults()
        selection = nil
        searchedQuery = trimmed
        loadMore()
    }

    private func loadMore() {
        guard let count = results.showMore() else { return }
        fetch(count: count)
    }

    private func fetch(count: Int) {
        guard let searchedQuery else { return }
        isSearching = true
        errorMessage = nil
        searchTask = Task {
            do {
                let videos = try await YouTubeSearch.search(searchedQuery, count: count)
                guard !Task.isCancelled else { return }
                results.add(videos, requested: count)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    // MARK: Link

    private var linkView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("YouTube link", text: $link, prompt: Text("https://www.youtube.com/watch?v=…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await useThumbnail() } }
            Text(suggestedLink.isEmpty
                ? "Paste a link to the video, or its 11-character ID."
                : "Filled in from the video ID in the file name or comment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Use

    private var chosenVideoID: String? {
        switch mode {
        case .search: selection
        case .link: YouTube.videoID(from: link)
        }
    }

    private func useThumbnail() async {
        guard let videoID = chosenVideoID else {
            errorMessage = ArtworkError.notAYouTubeLink.localizedDescription
            return
        }
        isDownloading = true
        errorMessage = nil
        defer { isDownloading = false }
        do {
            artwork = try await Artwork.youTubeThumbnail(videoID: videoID, cropToSquare: cropToSquare)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ResultCell: View {
    let video: YouTubeVideo
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: video.previewURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.formattedDuration {
                    Text(duration)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassBadge()
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }

            Text(video.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let channel = video.channel {
                Text(channel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .help(video.title)
    }
}

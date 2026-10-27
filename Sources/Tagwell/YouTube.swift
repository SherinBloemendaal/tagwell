import Foundation

nonisolated enum YouTube {
    /// The video ID in a YouTube link (watch, youtu.be, shorts, live, embed, music.youtube.com) or a bare 11-character ID.
    static func videoID(from text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoID(text) { return text }

        guard let url = URL(string: text.contains("://") ? text : "https://\(text)"),
              let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }

        let candidate: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            candidate = path.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if path.first == "watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if let kind = path.first, ["shorts", "live", "embed", "v"].contains(kind), path.count > 1 {
                candidate = path[1]
            } else {
                candidate = nil
            }
        } else {
            candidate = nil
        }
        return candidate.flatMap { isVideoID($0) ? $0 : nil }
    }

    /// Finds a video ID in a file name or comment: yt-dlp names files "Title [ID].mp3"
    /// and stores the video's link in the comment.
    static func videoID(in fileName: String, comment: String) -> String? {
        if let match = fileName.firstMatch(of: #/\[([A-Za-z0-9_-]{11})\]/#) {
            return String(match.1)
        }
        // Only links count here: a bare 11-letter word in a comment is not an ID.
        return comment.split(whereSeparator: \.isWhitespace).lazy
            .filter { $0.localizedCaseInsensitiveContains("youtu") }
            .compactMap { videoID(from: String($0)) }
            .first
    }

    /// "Title [dQw4w9WgXcQ]" becomes "Title", for searching by file name.
    static func removingVideoID(from name: String) -> String {
        name.replacing(#/\s*\[[A-Za-z0-9_-]{11}\]/#, with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Thumbnail sizes from largest to smallest. Not every video has the larger ones.
    static func thumbnailURLs(for videoID: String) -> [URL] {
        ["maxresdefault", "sddefault", "hqdefault"].compactMap {
            URL(string: "https://i.ytimg.com/vi/\(videoID)/\($0).jpg")
        }
    }

    static func watchURL(for videoID: String) -> String {
        "https://www.youtube.com/watch?v=\(videoID)"
    }

    private static func isVideoID(_ text: String) -> Bool {
        text.wholeMatch(of: #/[A-Za-z0-9_-]{11}/#) != nil
    }
}

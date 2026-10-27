import Foundation
@testable import Tagwell
import Testing

private func ids(_ range: ClosedRange<Int>) -> [String] {
    range.map { String(format: "video%06d", $0) }
}

private func videos(_ range: ClosedRange<Int>) -> [YouTubeVideo] {
    ids(range).map { YouTubeVideo(id: $0, title: $0, channel: nil, duration: nil, viewCount: nil) }
}

struct YouTubeSearchTests {
    @Test func `asks yt-dlp for the first results of a search in one call`() {
        #expect(YouTubeSearch.arguments(query: "Hardwell Ultra", count: 30).last == "ytsearch30:Hardwell Ultra")
    }

    @Test func `load more shows ten at a time from one fetch, then fetches a bigger batch`() {
        var results = YouTubeResults()
        #expect(results.showMore() == 30)
        results.add(videos(1...30), requested: 30)
        #expect(results.shown.map(\.id) == ids(1...10))

        #expect(results.showMore() == nil)
        #expect(results.showMore() == nil)
        #expect(results.shown.count == 30)

        // The next fetch starts from the top again and YouTube shuffled a little: only new ones are added.
        #expect(results.showMore() == 60)
        results.add(videos(1...5) + videos(31...55) + videos(6...30), requested: 60)
        #expect(results.shown.map(\.id) == ids(1...40))
        #expect(results.fetched.count == 55)
        #expect(results.hasMore)
    }

    @Test func `stops offering more when YouTube runs out`() {
        var results = YouTubeResults()
        _ = results.showMore()
        results.add(videos(1...14), requested: 30)

        #expect(results.shown.count == 10)
        #expect(results.hasMore)
        #expect(results.showMore() == nil)
        #expect(results.shown.count == 14)
        #expect(!results.hasMore)
    }

    @Test func `reads one video per line and skips lines that are not a video`() {
        let output = Data("""
        {"id": "8Tk9IERWa2s", "title": "HARDWELL - TOMORROWLAND 2024", "channel": "Hardwell", "duration": 3659.0, "view_count": 1613749}
        WARNING: something yt-dlp printed
        {"id": "Ne-nZA2bZMg", "title": "Mainstage", "uploader": "Hardwell Archive", "duration": null}
        {"id": "aaaaaaaaaaa"}

        """.utf8)

        let videos = YouTubeSearch.parse(output)

        #expect(videos.map(\.id) == ["8Tk9IERWa2s", "Ne-nZA2bZMg", "aaaaaaaaaaa"])
        #expect(videos[0].channel == "Hardwell")
        #expect(videos[1].channel == "Hardwell Archive")
        #expect(videos[2].title == "aaaaaaaaaaa")
    }

    @Test(arguments: [(3659.0, "1:00:59"), (245.0, "4:05"), (59.6, "1:00"), (0.0, nil)] as [(Double, String?)])
    func `formats the duration`(seconds: Double, expected: String?) {
        let video = YouTubeVideo(id: "x", title: "x", channel: nil, duration: seconds, viewCount: nil)
        #expect(video.formattedDuration == expected)
    }

    @Test func `strips the yt-dlp video ID from a file name before searching`() {
        #expect(YouTube.removingVideoID(from: "Hardwell Live at Ultra 2024 [dQw4w9WgXcQ]") == "Hardwell Live at Ultra 2024")
        #expect(YouTube.removingVideoID(from: "No ID here") == "No ID here")
    }

    @Test func `finds yt-dlp on the PATH`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ytdlp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tool = folder.appending(path: "yt-dlp")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        #expect(YouTubeSearch.ytDlpURL(environment: ["PATH": "/nonexistent:\(folder.path)"]) == tool)
    }

    /// Talks to YouTube, so it only runs when asked: TAGWELL_LIVE_YTDLP=1 swift test
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TAGWELL_LIVE_YTDLP"] == "1"))
    func `searches YouTube for real`() async throws {
        let videos = try await YouTubeSearch.search("Hardwell Tomorrowland 2024", count: 30)

        #expect(videos.count == 30)
        #expect(Set(videos.map(\.id)).count == 30)
    }
}

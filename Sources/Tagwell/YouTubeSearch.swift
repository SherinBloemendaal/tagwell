import Foundation
import Synchronization

/// One video from a YouTube search.
nonisolated struct YouTubeVideo: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let title: String
    let channel: String?
    let duration: Double?
    let viewCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, channel, uploader, duration
        case viewCount = "view_count"
    }

    init(id: String, title: String, channel: String?, duration: Double?, viewCount: Int?) {
        self.id = id
        self.title = title
        self.channel = channel
        self.duration = duration
        self.viewCount = viewCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? id
        channel = try container.decodeIfPresent(String.self, forKey: .channel)
            ?? container.decodeIfPresent(String.self, forKey: .uploader)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
    }

    /// A small 16:9 thumbnail for the result grid.
    var previewURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    /// "1:01:23" or "4:05".
    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        let seconds = Int(duration.rounded())
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// The results of one search: what is fetched, how much of it is shown, and whether YouTube has more.
nonisolated struct YouTubeResults {
    private(set) var fetched: [YouTubeVideo] = []
    private(set) var shownCount = 0
    /// The last fetch returned fewer results than asked for.
    private(set) var isExhausted = false

    var shown: ArraySlice<YouTubeVideo> { fetched.prefix(shownCount) }

    var hasMore: Bool {
        shownCount < fetched.count || (!isExhausted && !fetched.isEmpty)
    }

    /// Shows the next ten when they are already fetched and returns nil.
    /// Otherwise returns how many results to fetch; pass them to `add` and they are shown then.
    mutating func showMore() -> Int? {
        if fetched.count >= shownCount + YouTubeSearch.pageSize || isExhausted {
            shownCount = min(shownCount + YouTubeSearch.pageSize, fetched.count)
            return nil
        }
        return fetched.count + YouTubeSearch.batchSize
    }

    /// Adds a fetch of the first `requested` results. A bigger search starts from the top again,
    /// so videos already listed are skipped.
    mutating func add(_ videos: [YouTubeVideo], requested: Int) {
        let known = Set(fetched.map(\.id))
        var seen = known
        fetched += videos.filter { seen.insert($0.id).inserted }
        isExhausted = videos.count < requested
        shownCount = min(shownCount + YouTubeSearch.pageSize, fetched.count)
    }
}

enum YouTubeSearchError: LocalizedError, Equatable {
    case ytDlpMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .ytDlpMissing:
            "Searching YouTube needs yt-dlp. Install it with: brew install yt-dlp"
        case .failed(let message):
            "The YouTube search failed: \(message)"
        }
    }
}

/// Searches YouTube through yt-dlp ("ytsearch"), which needs no API key.
nonisolated enum YouTubeSearch {
    /// Results shown per "Load More".
    static let pageSize = 10
    /// Results fetched per call. YouTube reorders results a little on every request, so asking for
    /// results 11 to 20 separately repeats some of the first ten and skips others. One call for 30
    /// costs about as much time as one for 10, and Load More is then shown from that list.
    static let batchSize = 30

    /// Apps started from Finder do not get the shell's PATH, so the usual install places are checked too.
    static func ytDlpURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/yt-dlp" }
        let candidates = fromPath + [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/local/bin/yt-dlp",
            "\(home)/.local/bin/yt-dlp",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// The arguments for the first `count` results of a search.
    static func arguments(query: String, count: Int) -> [String] {
        ["--flat-playlist", "--dump-json", "--no-warnings", "--ignore-config", "ytsearch\(count):\(query)"]
    }

    /// Parses yt-dlp's output: one JSON object per line. Lines that are not a video are skipped.
    static func parse(_ output: Data) -> [YouTubeVideo] {
        let decoder = JSONDecoder()
        return output.split(separator: UInt8(ascii: "\n")).compactMap { line in
            try? decoder.decode(YouTubeVideo.self, from: Data(line))
        }
    }

    /// The first `count` results. Fewer means YouTube has no more.
    @concurrent
    static func search(_ query: String, count: Int) async throws -> [YouTubeVideo] {
        guard let ytDlp = ytDlpURL() else { throw YouTubeSearchError.ytDlpMissing }
        let result = try await run(ytDlp, arguments: arguments(query: query, count: count))
        guard result.status == 0 else {
            let message = String(decoding: result.error, as: UTF8.self)
                .split(separator: "\n").last.map(String.init) ?? "yt-dlp exited with status \(result.status)"
            throw YouTubeSearchError.failed(message)
        }
        return parse(result.output)
    }

    /// Runs a program and collects its output. Stops it when the task is cancelled (the sheet closes).
    private static func run(_ executable: URL, arguments: [String]) async throws -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Read while the program runs: a full pipe would otherwise block it.
        let output = Buffer()
        let error = Buffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            error.append(handle.availableData)
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            // terminate() raises an exception for a process that has not started yet.
            if process.isRunning {
                process.terminate()
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        // Whatever arrived between the last handler call and the exit.
        output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        error.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        return (status, output.data, error.data)
    }

    /// Output collected from a pipe's handler, which runs on a background queue.
    private final class Buffer: Sendable {
        private let storage = Mutex(Data())

        func append(_ chunk: Data) {
            storage.withLock { $0.append(chunk) }
        }

        var data: Data {
            storage.withLock { $0 }
        }
    }
}

import AppKit
import ID3Kit
@testable import Tagwell
import Testing

private let audio: [UInt8] = [0xFF, 0xFB, 0x90, 0x64] + Array(repeating: 0, count: 2000)

private func makeFile(named name: String, in folder: URL? = nil) throws -> EditableFile {
    let folder = try folder ?? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TagwellRename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    let url = folder.appending(path: name)
    try Data(audio).write(to: url)
    return try EditableFile(url: url)
}

struct RenameTests {
    @Test func `renames after artist and title, together with the tags`() throws {
        let file = try makeFile(named: "track01.mp3")
        file.fields.artist = "Hardwell"
        file.fields.title = "Live at Tomorrowland 2024"
        file.rename = .fromTags

        #expect(file.plannedName == "Hardwell - Live at Tomorrowland 2024.mp3")
        #expect(file.isDirty)
        try file.save()

        #expect(file.name == "Hardwell - Live at Tomorrowland 2024.mp3")
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(try ID3.readFields(from: file.url).artist == "Hardwell")
        #expect(file.rename == .keep)
        #expect(!file.isDirty)
    }

    @Test func `a custom name replaces characters macOS does not allow`() throws {
        let file = try makeFile(named: "a.mp3")
        file.rename = .custom("  .AC/DC: Live  ")

        #expect(file.plannedName == "AC-DC- Live.mp3")
        try file.save()
        #expect(file.name == "AC-DC- Live.mp3")
    }

    @Test func `keeps the extension as it was`() throws {
        let file = try makeFile(named: "loud.MP3")
        file.rename = .custom("quiet")
        #expect(file.plannedName == "quiet.MP3")
    }

    @Test func `turning rename on without a change in name leaves the file clean`() throws {
        let file = try makeFile(named: "Maddix - Ultra.mp3")
        file.fields.artist = "Maddix"
        file.fields.title = "Ultra"
        try file.save()

        file.rename = .fromTags
        #expect(!file.hasPendingRename)
    }

    @Test func `refuses to overwrite another file`() throws {
        let first = try makeFile(named: "one.mp3")
        _ = try makeFile(named: "two.mp3", in: first.url.deletingLastPathComponent())
        first.rename = .custom("two")

        #expect(throws: RenameError.alreadyExists("two.mp3")) { try first.save() }
        #expect(first.name == "one.mp3")
        #expect(first.hasPendingRename)
    }

    @Test func `naming after tags needs a title, and the tags are still saved`() throws {
        let file = try makeFile(named: "x.mp3")
        file.fields.artist = "Armin van Buuren"
        file.rename = .fromTags

        #expect(file.plannedName == nil)
        #expect(throws: RenameError.needsTitle) { try file.save() }
        #expect(try ID3.readFields(from: file.url).artist == "Armin van Buuren")
        #expect(file.name == "x.mp3")
    }

    @Test func `revert also cancels the rename`() throws {
        let file = try makeFile(named: "x.mp3")
        file.rename = .custom("y")
        file.revert()
        #expect(!file.isDirty)
    }
}

struct YouTubeTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=42",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RD",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "  dQw4w9WgXcQ  ",
    ])
    func `finds the video ID in a link`(link: String) {
        #expect(YouTube.videoID(from: link) == "dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "https://vimeo.com/123456789",
        "https://www.youtube.com/channel/UC1234567890",
        "https://www.youtube.com/watch?v=short",
        "not a link",
        "",
    ])
    func `ignores what is not a video`(text: String) {
        #expect(YouTube.videoID(from: text) == nil)
    }

    @Test func `finds the ID in a yt-dlp file name or a comment link`() {
        #expect(YouTube.videoID(in: "Hardwell Live at Ultra 2024 [dQw4w9WgXcQ].mp3", comment: "") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(in: "set.mp3", comment: "Source: https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        // An 11-letter word in a comment is not an ID.
        #expect(YouTube.videoID(in: "set.mp3", comment: "Amsterdam20 is great") == nil)
    }

    @Test func `crops a wide image to a centred square`() throws {
        let png = try #require(NSImage(size: NSSize(width: 160, height: 90), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }.tiffRepresentation)

        let artwork = try Artwork(imageData: png, cropToSquare: true)
        let image = try #require(NSBitmapImageRep(data: artwork.data))

        #expect(artwork.mimeType == "image/jpeg")
        #expect(image.pixelsWide == image.pixelsHigh)
    }
}

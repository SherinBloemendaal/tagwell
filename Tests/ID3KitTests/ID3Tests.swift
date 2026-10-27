import Foundation
@testable import ID3Kit
import Testing

/// A fake MP3 frame header followed by silence. Enough for the tag code, which never decodes audio.
private let audio: [UInt8] = [0xFF, 0xFB, 0x90, 0x64] + Array(repeating: 0, count: 4000)

private func temporaryFile(_ bytes: [UInt8]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
    try Data(bytes).write(to: url)
    return url
}

private func fileBytes(_ url: URL) throws -> [UInt8] {
    [UInt8](try Data(contentsOf: url))
}

private func tag(version: UInt8, frames: [Frame]) throws -> [UInt8] {
    try TagWriter.serialize(ParsedTag(version: version, frames: frames, length: 0))
}

private func latin1Frame(_ id: String, _ text: String) -> Frame {
    Frame(id: id, flags: 0, body: [0] + Array(text.utf8))
}

struct ID3Tests {
    @Test func `writes a new tag into a file without one and keeps the audio`() throws {
        let url = try temporaryFile(audio)
        var fields = TagFields()
        fields.title = "Song"
        fields.artist = "Artist"
        fields.year = "2021"
        fields.track = "3/12"
        fields.comment = "Nice"
        fields.artwork = Artwork(data: Data([1, 2, 3, 4]), mimeType: "image/png")

        try ID3.write(fields, to: url)

        #expect(try ID3.readFields(from: url) == fields)
        #expect(try fileBytes(url).suffix(audio.count) == audio[...])
    }

    @Test func `stores non Latin text as UTF-16 in ID3v2.3`() throws {
        let url = try temporaryFile(audio)
        var fields = TagFields()
        fields.title = "東京 🎵 Ünïcode"

        try ID3.write(fields, to: url)

        let parsed = try TagParser.parse(try fileBytes(url))
        #expect(parsed.version == 3)
        #expect(parsed.frames.first { $0.id == "TIT2" }?.body.first == TextEncoding.utf16.rawValue)
        #expect(try ID3.readFields(from: url).title == fields.title)
    }

    @Test func `keeps unknown frames and untouched fields byte for byte`() throws {
        let custom = Frame(id: "TXXX", flags: 0, body: [0] + Array("MusicBrainz\0abc".utf8))
        let genre = latin1Frame("TCON", "(17)")
        let url = try temporaryFile(try tag(version: 3, frames: [latin1Frame("TIT2", "Old"), custom, genre]) + audio)

        var fields = try ID3.readFields(from: url)
        #expect(fields.genre == "Rock")
        fields.title = "New"
        try ID3.write(fields, to: url)

        let parsed = try TagParser.parse(try fileBytes(url))
        #expect(parsed.frames.contains(custom))
        #expect(parsed.frames.contains(genre))
        #expect(parsed.text("TIT2") == "New")
        #expect(try fileBytes(url).suffix(audio.count) == audio[...])
    }

    @Test func `keeps ID3v2.4 and writes the year as TDRC`() throws {
        let url = try temporaryFile(try tag(version: 4, frames: [latin1Frame("TIT2", "Title")]) + audio)
        var fields = try ID3.readFields(from: url)
        fields.year = "2024-05-31"
        fields.artist = "Björk"

        try ID3.write(fields, to: url)

        let parsed = try TagParser.parse(try fileBytes(url))
        #expect(parsed.version == 4)
        #expect(parsed.text("TDRC") == "2024-05-31")
        #expect(parsed.frames.first { $0.id == "TPE1" }?.body.first == TextEncoding.utf8.rawValue)
        #expect(try ID3.readFields(from: url) == fields)
    }

    @Test func `rejects a full date in ID3v2.3`() throws {
        let url = try temporaryFile(audio)
        var fields = TagFields()
        fields.year = "2024-05-31"

        #expect(throws: ID3Error.invalidYear("2024-05-31", allowsFullDate: false)) {
            try ID3.write(fields, to: url)
        }
        #expect(try fileBytes(url) == audio)
    }

    @Test func `rejects a track that is not a number`() throws {
        let url = try temporaryFile(audio)
        var fields = TagFields()
        fields.track = "three"

        #expect(throws: ID3Error.invalidNumber(field: "track number", value: "three")) {
            try ID3.write(fields, to: url)
        }
    }

    @Test func `leaves comments with a description alone`() throws {
        let itunes = Frame(id: "COMM", flags: 0, body: [0] + Array("engiTunNORM\0 000001".utf8))
        let user = Frame(id: "COMM", flags: 0, body: [0] + Array("eng\0hello".utf8))
        let url = try temporaryFile(try tag(version: 3, frames: [itunes, user]) + audio)

        var fields = try ID3.readFields(from: url)
        #expect(fields.comment == "hello")
        fields.comment = "changed"
        try ID3.write(fields, to: url)

        let parsed = try TagParser.parse(try fileBytes(url))
        #expect(parsed.frames.contains(itunes))
        #expect(!parsed.frames.contains(user))
        #expect(try ID3.readFields(from: url).comment == "changed")
    }

    @Test func `reads ID3v1 when there is no ID3v2 tag and updates it on save`() throws {
        var fields = TagFields()
        fields.title = "Old Title"
        fields.artist = "Old Artist"
        fields.track = "7"
        fields.genre = "Rock"
        let url = try temporaryFile(audio + ID3v1.encode(fields))

        var read = try ID3.readFields(from: url)
        #expect(read == fields)

        read.title = "New Title"
        try ID3.write(read, to: url)

        let bytes = try fileBytes(url)
        #expect(ID3v1.fields(from: bytes)?.title == "New Title")
        #expect(try ID3.readFields(from: url) == read)
        #expect(bytes.dropLast(ID3v1.length).suffix(audio.count) == audio[...])
    }

    @Test func `reads unsynchronised ID3v2.3 tags`() throws {
        // The Latin-1 title "Aÿà" is 41 FF E0. Unsynchronisation stores FF E0 as FF 00 E0,
        // while the frame size still counts the original 4 bytes.
        let frameBody: [UInt8] = [0, 0x41, 0xFF, 0x00, 0xE0]
        let frame = Array("TIT2".utf8) + [0, 0, 0, 4, 0, 0] + frameBody
        let header: [UInt8] = [0x49, 0x44, 0x33, 3, 0, 0x80] + TagWriter.syncsafe(frame.count)
        let url = try temporaryFile(header + frame + audio)

        #expect(try ID3.readFields(from: url).title == "A\u{FF}\u{E0}")
    }

    @Test func `refuses ID3v2.2 instead of damaging it`() throws {
        let url = try temporaryFile([0x49, 0x44, 0x33, 2, 0, 0, 0, 0, 0, 0] + audio)
        #expect(throws: ID3Error.unsupportedVersion(2)) {
            try ID3.readFields(from: url)
        }
    }

    @Test(arguments: [("(17)", "Rock"), ("(17)Indie", "Indie"), ("13", "Pop"), ("(RX)", "Remix"), ("(200)", "(200)"), ("Shoegaze", "Shoegaze")])
    func `normalizes genre references`(raw: String, expected: String) {
        #expect(Genre.normalize(raw) == expected)
    }

    @Test func `genre list has the 80 ID3v1 genres`() {
        #expect(Genre.names.count == 80)
        #expect(Genre.names[79] == "Hard Rock")
    }
}

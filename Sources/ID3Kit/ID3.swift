import Foundation

public enum ID3 {
    /// Reads the tag without loading the audio. Falls back to an ID3v1 tag when there is no ID3v2 tag.
    public static func readFields(from url: URL) throws -> TagFields {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let header = [UInt8](try handle.read(upToCount: 10) ?? Data())
        var tagBytes = header
        if header.count == 10, header.starts(with: [0x49, 0x44, 0x33]), let size = TagParser.syncsafe(header[6..<10]) {
            // The extra 10 bytes cover an ID3v2.4 footer.
            tagBytes += [UInt8](try handle.read(upToCount: size + 10) ?? Data())
        }
        let tag = try TagParser.parse(tagBytes)
        if tag.length > 0 {
            return tag.fields
        }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= UInt64(ID3v1.length) else { return TagFields() }
        try handle.seek(toOffset: fileSize - UInt64(ID3v1.length))
        let tail = [UInt8](try handle.read(upToCount: ID3v1.length) ?? Data())
        return ID3v1.fields(from: tail) ?? TagFields()
    }

    /// Saves the fields into the file. Fields that did not change keep their original frames,
    /// unknown frames are preserved, and the audio data is copied unchanged.
    public static func write(_ fields: TagFields, to url: URL) throws {
        let original = [UInt8](try Data(contentsOf: url))
        var tag = try TagParser.parse(original)
        try tag.apply(fields)

        var audio = original[tag.length...]
        var output = try TagWriter.serialize(tag)
        if ID3v1.isPresent(in: audio) {
            audio = audio.dropLast(ID3v1.length)
            output += audio
            output += ID3v1.encode(fields)
        } else {
            output += audio
        }

        try replaceContents(of: url, with: Data(output))
    }

    /// Writes next to the original and swaps the files, so a failed write never leaves a half-written MP3.
    private static func replaceContents(of url: URL, with data: Data) throws {
        let fileManager = FileManager.default
        let directory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let temporary = directory.appending(path: url.lastPathComponent)
        try data.write(to: temporary)
        _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
    }
}

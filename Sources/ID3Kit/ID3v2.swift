import Foundation

struct Frame: Equatable {
    var id: String
    /// Status and format flags exactly as stored, so untouched frames are written back unchanged.
    var flags: UInt16
    var body: [UInt8]
}

struct ParsedTag {
    /// Major version: 3 or 4. Files without a tag get version 3, the most widely supported one.
    var version: UInt8
    var frames: [Frame]
    /// Bytes the tag (header, body and footer) occupies at the start of the file. 0 when there is no tag.
    var length: Int

    static let empty = ParsedTag(version: 3, frames: [], length: 0)
}

enum TextEncoding: UInt8 {
    case latin1 = 0
    case utf16 = 1
    case utf16BigEndian = 2
    case utf8 = 3

    var terminatorLength: Int {
        switch self {
        case .latin1, .utf8: 1
        case .utf16, .utf16BigEndian: 2
        }
    }

    func decode(_ bytes: ArraySlice<UInt8>) -> String {
        var bytes = Array(bytes)
        if terminatorLength == 2, bytes.count % 2 == 1 {
            bytes.removeLast()
        }
        return switch self {
        case .latin1: String(bytes: bytes, encoding: .isoLatin1) ?? ""
        case .utf8: String(decoding: bytes, as: UTF8.self)
        case .utf16: String(bytes: bytes, encoding: .utf16) ?? ""
        case .utf16BigEndian: String(bytes: bytes, encoding: .utf16BigEndian) ?? ""
        }
    }

    /// Splits off the string that ends at the first terminator. Without a terminator the whole input is the string.
    func splitTerminated(_ bytes: ArraySlice<UInt8>) -> (string: ArraySlice<UInt8>, rest: ArraySlice<UInt8>) {
        var index = bytes.startIndex
        while index + terminatorLength <= bytes.endIndex {
            if bytes[index..<index + terminatorLength].allSatisfy({ $0 == 0 }) {
                return (bytes[bytes.startIndex..<index], bytes[(index + terminatorLength)...])
            }
            index += terminatorLength
        }
        return (bytes, bytes[bytes.endIndex...])
    }

    /// ID3v2.4 always gets UTF-8. ID3v2.3 has no UTF-8, so it gets Latin-1 when that fits and UTF-16 otherwise.
    static func preferred(for text: String, version: UInt8) -> TextEncoding {
        if version == 4 { return .utf8 }
        return text.canBeConverted(to: .isoLatin1) ? .latin1 : .utf16
    }

    func encode(_ text: String) -> [UInt8] {
        switch self {
        case .latin1: Array(text.data(using: .isoLatin1) ?? Data())
        case .utf8: Array(text.utf8)
        case .utf16: [0xFF, 0xFE] + text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        case .utf16BigEndian: text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        }
    }

    var terminator: [UInt8] { Array(repeating: 0, count: terminatorLength) }
}

// MARK: - Reading

enum TagParser {
    static func parse(_ bytes: [UInt8]) throws(ID3Error) -> ParsedTag {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            return .empty
        }
        let version = bytes[3]
        guard version == 3 || version == 4 else { throw .unsupportedVersion(version) }

        let flags = bytes[5]
        guard let size = syncsafe(bytes[6..<10]) else { throw .malformedTag }
        let tagEnd = 10 + size
        guard tagEnd <= bytes.count else { throw .malformedTag }
        let hasFooter = version == 4 && flags & 0x10 != 0
        guard !hasFooter || tagEnd + 10 <= bytes.count else { throw .malformedTag }
        let isUnsynchronised = flags & 0x80 != 0

        // In ID3v2.3 unsynchronisation covers the whole tag body. In ID3v2.4 it is applied per frame.
        var body = Array(bytes[10..<tagEnd])
        if isUnsynchronised, version == 3 {
            body = removeUnsynchronisation(body)
        }

        var position = 0
        if flags & 0x40 != 0 {
            guard body.count >= 4 else { throw .malformedTag }
            let extendedHeaderLength: Int? = version == 3
                ? bigEndian32(body[0..<4]) + 4
                : syncsafe(body[0..<4])
            guard let extendedHeaderLength, extendedHeaderLength <= body.count else { throw .malformedTag }
            position = extendedHeaderLength
        }

        var frames: [Frame] = []
        while position + 10 <= body.count {
            let idBytes = body[position..<position + 4]
            // Anything that is not a frame ID here is padding.
            guard idBytes.allSatisfy({ (0x41...0x5A).contains($0) || (0x30...0x39).contains($0) }) else { break }

            let sizeBytes = body[position + 4..<position + 8]
            let frameSize = version == 4 ? syncsafe(sizeBytes) : bigEndian32(sizeBytes)
            guard let frameSize, position + 10 + frameSize <= body.count else { throw .malformedTag }

            var frameFlags = UInt16(body[position + 8]) << 8 | UInt16(body[position + 9])
            if isUnsynchronised, version == 4 {
                frameFlags |= 0x0002
            }
            let bodyStart = position + 10
            frames.append(Frame(
                id: String(decoding: idBytes, as: UTF8.self),
                flags: frameFlags,
                body: Array(body[bodyStart..<bodyStart + frameSize])
            ))
            position = bodyStart + frameSize
        }

        return ParsedTag(version: version, frames: frames, length: tagEnd + (hasFooter ? 10 : 0))
    }

    static func syncsafe(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        return bytes.reduce(0) { $0 << 7 | Int($1) }
    }

    static func bigEndian32(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 8 | Int($1) }
    }

    static func removeUnsynchronisation(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var previous: UInt8 = 0
        for byte in bytes {
            if !(previous == 0xFF && byte == 0x00) {
                result.append(byte)
            }
            previous = byte
        }
        return result
    }
}

extension Frame {
    /// The frame's payload with grouping, data length and unsynchronisation undone.
    /// Nil for compressed or encrypted frames, which this editor does not decode.
    func content(version: UInt8) -> ArraySlice<UInt8>? {
        if version == 3 {
            if flags & 0x00C0 != 0 { return nil }
            return flags & 0x0020 != 0 ? body.dropFirst() : body[...]
        }
        if flags & 0x000C != 0 { return nil }
        var data = flags & 0x0002 != 0 ? TagParser.removeUnsynchronisation(body)[...] : body[...]
        if flags & 0x0040 != 0 { data = data.dropFirst() }
        if flags & 0x0001 != 0 { data = data.dropFirst(4) }
        return data
    }

    func textValues(version: UInt8) -> [String]? {
        guard let content = content(version: version), let first = content.first,
              let encoding = TextEncoding(rawValue: first) else { return nil }
        var values: [String] = []
        var rest = content.dropFirst()
        while !rest.isEmpty {
            let split = encoding.splitTerminated(rest)
            let value = encoding.decode(split.string)
            if !value.isEmpty {
                values.append(value)
            }
            rest = split.rest
        }
        return values
    }

    func comment(version: UInt8) -> (description: String, text: String)? {
        guard let content = content(version: version), content.count >= 4,
              let encoding = TextEncoding(rawValue: content[content.startIndex]) else { return nil }
        let afterLanguage = content.dropFirst(4)
        let split = encoding.splitTerminated(afterLanguage)
        let text = encoding.splitTerminated(split.rest).string
        return (encoding.decode(split.string), encoding.decode(text))
    }

    func picture(version: UInt8) -> (type: UInt8, artwork: Artwork)? {
        guard let content = content(version: version), let first = content.first,
              let encoding = TextEncoding(rawValue: first) else { return nil }
        let mime = TextEncoding.latin1.splitTerminated(content.dropFirst())
        guard let type = mime.rest.first else { return nil }
        let description = encoding.splitTerminated(mime.rest.dropFirst())
        var mimeType = TextEncoding.latin1.decode(mime.string).lowercased()
        if mimeType.isEmpty || !mimeType.contains("/") {
            mimeType = "image/\(mimeType == "jpg" || mimeType.isEmpty ? "jpeg" : mimeType)"
        }
        return (type, Artwork(data: Data(description.rest), mimeType: mimeType))
    }
}

extension ParsedTag {
    func textValues(_ id: String) -> [String]? {
        frames.lazy.filter { $0.id == id }.compactMap { $0.textValues(version: version) }.first
    }

    func text(_ id: String) -> String? {
        textValues(id)?.joined(separator: "; ")
    }

    /// Frames that hold the user's comment. iTunes and others store machine data in COMM frames
    /// with a description (iTunNORM, iTunSMPB), so only the ones without a description count.
    static func isUserComment(_ frame: Frame, version: UInt8) -> Bool {
        frame.id == "COMM" && frame.comment(version: version)?.description.isEmpty == true
    }

    var fields: TagFields {
        var fields = TagFields()
        for field in TextField.allCases {
            fields[keyPath: field.keyPath] = text(field.frameID) ?? ""
        }
        fields.year = text("TDRC") ?? text("TYER") ?? ""
        fields.genre = (textValues("TCON") ?? []).map(Genre.normalize).joined(separator: "; ")
        fields.comment = frames.first { Self.isUserComment($0, version: version) }?.comment(version: version)?.text ?? ""

        let pictures = frames.filter { $0.id == "APIC" }.compactMap { $0.picture(version: version) }
        fields.artwork = (pictures.first { $0.type == 3 } ?? pictures.first)?.artwork
        return fields
    }
}

/// Plain text fields that map one-to-one onto a text frame.
enum TextField: CaseIterable {
    case title, artist, album, albumArtist, composer, track, disc

    var frameID: String {
        switch self {
        case .title: "TIT2"
        case .artist: "TPE1"
        case .album: "TALB"
        case .albumArtist: "TPE2"
        case .composer: "TCOM"
        case .track: "TRCK"
        case .disc: "TPOS"
        }
    }

    var keyPath: WritableKeyPath<TagFields, String> {
        switch self {
        case .title: \.title
        case .artist: \.artist
        case .album: \.album
        case .albumArtist: \.albumArtist
        case .composer: \.composer
        case .track: \.track
        case .disc: \.disc
        }
    }
}

// MARK: - Editing

extension ParsedTag {
    /// Replaces the frames of every field that differs from what the tag holds now.
    /// Frames of unchanged fields and frames this editor does not know are kept byte for byte.
    mutating func apply(_ new: TagFields) throws(ID3Error) {
        let old = fields
        try Self.validate(new, against: old, version: version)
        var textFrames: [Frame] = []

        for field in TextField.allCases where new[keyPath: field.keyPath] != old[keyPath: field.keyPath] {
            frames.removeAll { $0.id == field.frameID }
            textFrames += textFrame(field.frameID, new[keyPath: field.keyPath])
        }
        if new.year != old.year {
            frames.removeAll { $0.id == "TYER" || $0.id == "TDRC" }
            textFrames += textFrame(version == 4 ? "TDRC" : "TYER", new.year)
        }
        if new.genre != old.genre {
            frames.removeAll { $0.id == "TCON" }
            textFrames += textFrame("TCON", new.genre)
        }
        if new.comment != old.comment {
            let version = version
            frames.removeAll { Self.isUserComment($0, version: version) }
            if !new.comment.isEmpty {
                let encoding = TextEncoding.preferred(for: new.comment, version: version)
                let body = [encoding.rawValue] + Array("eng".utf8) + encoding.terminator + encoding.encode(new.comment)
                textFrames.append(Frame(id: "COMM", flags: 0, body: body))
            }
        }

        var pictureFrames: [Frame] = []
        if new.artwork != old.artwork {
            frames.removeAll { $0.id == "APIC" }
            if let artwork = new.artwork {
                // Latin-1 MIME type, picture type 3 (front cover), empty Latin-1 description.
                let body = [TextEncoding.latin1.rawValue] + Array(artwork.mimeType.utf8) + [0, 3, 0] + Array(artwork.data)
                pictureFrames.append(Frame(id: "APIC", flags: 0, body: body))
            }
        }

        frames = textFrames + frames + pictureFrames
    }

    private func textFrame(_ id: String, _ value: String) -> [Frame] {
        guard !value.isEmpty else { return [] }
        let encoding = TextEncoding.preferred(for: value, version: version)
        return [Frame(id: id, flags: 0, body: [encoding.rawValue] + encoding.encode(value))]
    }

    private static func validate(_ new: TagFields, against old: TagFields, version: UInt8) throws(ID3Error) {
        if new.year != old.year, !new.year.isEmpty {
            let isValid = version == 4
                ? new.year.wholeMatch(of: #/\d{4}(-\d{2}(-\d{2})?)?/#) != nil
                : new.year.wholeMatch(of: #/\d{4}/#) != nil
            guard isValid else {
                throw .invalidYear(new.year, allowsFullDate: version == 4)
            }
        }
        for (name, newValue, oldValue) in [("track number", new.track, old.track), ("disc number", new.disc, old.disc)]
        where newValue != oldValue && !newValue.isEmpty {
            guard newValue.wholeMatch(of: #/\d+(\/\d+)?/#) != nil else {
                throw .invalidNumber(field: name, value: newValue)
            }
        }
    }
}

// MARK: - Writing

enum TagWriter {
    static let padding = 2048

    /// The tag as bytes, without unsynchronisation or an extended header. Empty when there are no frames.
    static func serialize(_ tag: ParsedTag) throws(ID3Error) -> [UInt8] {
        guard !tag.frames.isEmpty else { return [] }

        var body: [UInt8] = []
        for frame in tag.frames {
            guard frame.body.count < 1 << 28 else { throw .tagTooLarge }
            body += Array(frame.id.utf8)
            body += tag.version == 4 ? syncsafe(frame.body.count) : bigEndian32(frame.body.count)
            body += [UInt8(frame.flags >> 8), UInt8(frame.flags & 0xFF)]
            body += frame.body
        }
        body += Array(repeating: 0, count: padding)
        guard body.count < 1 << 28 else { throw .tagTooLarge }

        return [0x49, 0x44, 0x33, tag.version, 0, 0] + syncsafe(body.count) + body
    }

    static func syncsafe(_ value: Int) -> [UInt8] {
        [21, 14, 7, 0].map { UInt8(value >> $0 & 0x7F) }
    }

    static func bigEndian32(_ value: Int) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8(value >> $0 & 0xFF) }
    }
}

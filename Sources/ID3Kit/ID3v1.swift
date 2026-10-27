import Foundation

/// The fixed 128-byte tag at the end of older MP3 files. Read when a file has no ID3v2 tag,
/// and rewritten on save when present so it never contradicts the ID3v2 tag.
enum ID3v1 {
    static let length = 128

    static func isPresent(in tail: some Collection<UInt8>) -> Bool {
        tail.count >= length && tail.suffix(length).starts(with: [0x54, 0x41, 0x47])
    }

    static func fields(from tail: [UInt8]) -> TagFields? {
        guard isPresent(in: tail) else { return nil }
        let tag = Array(tail.suffix(length))

        var fields = TagFields()
        fields.title = string(tag[3..<33])
        fields.artist = string(tag[33..<63])
        fields.album = string(tag[63..<93])
        fields.year = string(tag[93..<97])
        // ID3v1.1 stores the track number in the last comment byte, after a zero byte.
        if tag[125] == 0, tag[126] != 0 {
            fields.comment = string(tag[97..<125])
            fields.track = String(tag[126])
        } else {
            fields.comment = string(tag[97..<127])
        }
        fields.genre = Genre.name(Int(tag[127])) ?? ""
        return fields
    }

    static func encode(_ fields: TagFields) -> [UInt8] {
        var tag: [UInt8] = [0x54, 0x41, 0x47]
        tag += padded(fields.title, 30)
        tag += padded(fields.artist, 30)
        tag += padded(fields.album, 30)
        tag += padded(fields.year, 4)
        if let track = fields.track.split(separator: "/").first.flatMap({ Int($0) }), (1...255).contains(track) {
            tag += padded(fields.comment, 28) + [0, UInt8(track)]
        } else {
            tag += padded(fields.comment, 30)
        }
        tag.append(Genre.index(of: fields.genre).map(UInt8.init) ?? 255)
        return tag
    }

    private static func string(_ bytes: ArraySlice<UInt8>) -> String {
        let text = bytes.prefix { $0 != 0 }
        return (String(bytes: text, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func padded(_ text: String, _ size: Int) -> [UInt8] {
        let bytes = Array((text.data(using: .isoLatin1, allowLossyConversion: true) ?? Data()).prefix(size))
        return bytes + Array(repeating: 0, count: size - bytes.count)
    }
}

enum Genre {
    /// The original ID3v1 genre list. ID3v2 tags may refer to these as "(17)" or "17".
    static let names = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave", "Psychadelic", "Rave", "Showtunes",
        "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
    ]

    static func name(_ index: Int) -> String? {
        names.indices.contains(index) ? names[index] : nil
    }

    static func index(of name: String) -> Int? {
        names.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Turns numeric references ("(17)", "(17)Rock", "17", "(RX)", "(CR)") into readable names.
    /// Unknown numbers stay as they are, so nothing is lost.
    static func normalize(_ raw: String) -> String {
        switch raw {
        case "RX", "(RX)": return "Remix"
        case "CR", "(CR)": return "Cover"
        default: break
        }
        if let match = raw.wholeMatch(of: #/\((\d+)\)(.*)/#) {
            let refinement = String(match.2)
            if !refinement.isEmpty { return refinement }
            return Int(match.1).flatMap(name) ?? raw
        }
        if let number = Int(raw) {
            return name(number) ?? raw
        }
        return raw
    }
}

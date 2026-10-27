import Foundation

public struct Artwork: Equatable, Sendable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// The editable view of a tag. Empty strings mean "not set".
public struct TagFields: Equatable, Sendable {
    public var title = ""
    public var artist = ""
    public var album = ""
    public var albumArtist = ""
    public var composer = ""
    public var genre = ""
    public var year = ""
    public var track = ""
    public var disc = ""
    public var comment = ""
    public var artwork: Artwork?

    public init() {}
}

public enum ID3Error: Error, LocalizedError, Equatable {
    case unsupportedVersion(UInt8)
    case malformedTag
    case tagTooLarge
    case invalidYear(String, allowsFullDate: Bool)
    case invalidNumber(field: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This file has an ID3v2.\(version) tag. Only ID3v2.3 and ID3v2.4 tags can be edited."
        case .malformedTag:
            "The ID3 tag in this file is damaged, so it was left untouched."
        case .tagTooLarge:
            "The tag is too large to save (the limit is 256 MB)."
        case .invalidYear(let value, let allowsFullDate):
            allowsFullDate
                ? "\"\(value)\" is not a valid year. Use a year like 2024, or a date like 2024-05-31."
                : "\"\(value)\" is not a valid year. This file uses ID3v2.3, which only stores a four-digit year like 2024."
        case .invalidNumber(let field, let value):
            "\"\(value)\" is not a valid \(field). Use a number like 3, or 3/12."
        }
    }
}

import AppKit
import ID3Kit
import ImageIO
import UniformTypeIdentifiers

enum ArtworkError: LocalizedError {
    case notAnImage

    var errorDescription: String? {
        "The file is not an image that can be read."
    }
}

extension Artwork {
    /// JPEG and PNG are stored as they are. Other formats (HEIC, TIFF, WebP) are converted to JPEG,
    /// because most players only show JPEG and PNG cover art.
    init(imageFileAt url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier) else {
            throw ArtworkError.notAnImage
        }
        if type.conforms(to: .jpeg) {
            self.init(data: data, mimeType: "image/jpeg")
        } else if type.conforms(to: .png) {
            self.init(data: data, mimeType: "image/png")
        } else {
            guard let bitmap = NSBitmapImageRep(data: data),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw ArtworkError.notAnImage
            }
            self.init(data: jpeg, mimeType: "image/jpeg")
        }
    }
}

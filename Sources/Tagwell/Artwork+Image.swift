import AppKit
import ID3Kit
import ImageIO
import UniformTypeIdentifiers

enum ArtworkError: LocalizedError {
    case notAnImage
    case notAYouTubeLink
    case thumbnailNotFound

    var errorDescription: String? {
        switch self {
        case .notAnImage: "The file is not an image that can be read."
        case .notAYouTubeLink: "That is not a YouTube link or video ID."
        case .thumbnailNotFound: "YouTube has no thumbnail for this video."
        }
    }
}

extension Artwork {
    init(imageFileAt url: URL) throws {
        try self.init(imageData: Data(contentsOf: url))
    }

    /// JPEG and PNG are stored as they are. Other formats (HEIC, TIFF, WebP) are converted to JPEG,
    /// because most players only show JPEG and PNG cover art. Cropping always produces a JPEG.
    init(imageData data: Data, cropToSquare: Bool = false) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier) else {
            throw ArtworkError.notAnImage
        }
        if cropToSquare {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ArtworkError.notAnImage }
            let side = min(image.width, image.height)
            let square = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
            guard let cropped = image.cropping(to: square) else { throw ArtworkError.notAnImage }
            self.init(data: try Self.jpeg(cropped), mimeType: "image/jpeg")
        } else if type.conforms(to: .jpeg) {
            self.init(data: data, mimeType: "image/jpeg")
        } else if type.conforms(to: .png) {
            self.init(data: data, mimeType: "image/png")
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ArtworkError.notAnImage }
            self.init(data: try Self.jpeg(image), mimeType: "image/jpeg")
        }
    }

    /// Downloads the largest thumbnail YouTube has for the video.
    static func youTubeThumbnail(videoID: String, cropToSquare: Bool) async throws -> Artwork {
        for url in YouTube.thumbnailURLs(for: videoID) {
            let (data, response) = try await URLSession.shared.data(from: url)
            // Missing sizes answer 404 with a grey placeholder image, so the status is what counts.
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            return try Artwork(imageData: data, cropToSquare: cropToSquare)
        }
        throw ArtworkError.thumbnailNotFound
    }

    private static func jpeg(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ArtworkError.notAnImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkError.notAnImage }
        return output as Data
    }
}

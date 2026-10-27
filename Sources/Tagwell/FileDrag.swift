import CoreTransferable
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Declared in Info.plist. A private type, so dragging files onto a text field never pastes their IDs.
    static let tagwellFiles = UTType(exportedAs: "io.github.sherinbloemendaal.tagwell.files")
}

/// Files dragged from the file list onto an artist folder.
nonisolated struct FileDrag: Codable, Transferable {
    let ids: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tagwellFiles)
    }
}

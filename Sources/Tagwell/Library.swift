import AppKit
import ID3Kit
import Observation

@Observable
final class EditableFile: Identifiable {
    let id = UUID()
    let url: URL
    private(set) var saved: TagFields
    var fields: TagFields

    var isDirty: Bool { fields != saved }
    var name: String { url.lastPathComponent }

    init(url: URL) throws {
        self.url = url
        let fields = try ID3.readFields(from: url)
        saved = fields
        self.fields = fields
    }

    func save() throws {
        try ID3.write(fields, to: url)
        // Show what is really in the file now, not what we meant to write.
        saved = try ID3.readFields(from: url)
        fields = saved
    }

    func revert() {
        fields = saved
    }

    func matches(_ search: String) -> Bool {
        [name, fields.title, fields.artist, fields.album].contains { $0.localizedCaseInsensitiveContains(search) }
    }
}

/// Which files the file list shows: everything, files without an artist, or one artist's folder.
enum ArtistFilter: Hashable {
    case all
    case noArtist
    case artist(String)
}

@Observable
final class Library {
    private(set) var files: [EditableFile] = []
    var selection: Set<EditableFile.ID> = []
    var artistFilter = ArtistFilter.all
    var searchText = ""
    var isImporting = false
    var errorMessage: String?
    let artistMemory: ArtistMemory

    init(artistMemory: ArtistMemory = ArtistMemory()) {
        self.artistMemory = artistMemory
    }

    // MARK: Visible files and selection

    /// Files in the current artist folder that match the search, in the order they were added.
    var visibleFiles: [EditableFile] {
        let search = searchText.trimmingCharacters(in: .whitespaces)
        return files.filter { file in
            let inFolder = switch artistFilter {
            case .all: true
            case .noArtist: file.fields.artist.isEmpty
            case .artist(let name): file.fields.artist == name
            }
            return inFolder && (search.isEmpty || file.matches(search))
        }
    }

    /// Selected files that are visible. Files hidden by the folder or search are never edited by accident.
    var selectedFiles: [EditableFile] {
        visibleFiles.filter { selection.contains($0.id) }
    }

    var selectionHasUnsavedChanges: Bool {
        selectedFiles.contains { $0.isDirty }
    }

    var hasUnsavedChanges: Bool {
        files.contains { $0.isDirty }
    }

    var unsavedCount: Int {
        files.count { $0.isDirty }
    }

    /// The files a context menu or drag acts on: the whole selection when the file is part of it, otherwise just that file.
    func targets(for file: EditableFile) -> [EditableFile] {
        selection.contains(file.id) ? selectedFiles : [file]
    }

    // MARK: Artists

    /// Remembered artists plus the artists of every open file.
    var artistNames: [String] {
        let names = Set(artistMemory.names).union(files.map(\.fields.artist).filter { !$0.isEmpty })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func fileCount(for filter: ArtistFilter) -> Int {
        switch filter {
        case .all: files.count
        case .noArtist: files.count { $0.fields.artist.isEmpty }
        case .artist(let name): files.count { $0.fields.artist == name }
        }
    }

    func artistSuggestions(for text: String) -> [String] {
        let text = text.trimmingCharacters(in: .whitespaces)
        return Array(
            artistNames
                .filter { $0 != text && (text.isEmpty || $0.localizedCaseInsensitiveContains(text)) }
                .prefix(10)
        )
    }

    /// Sets the artist of the dragged files. An empty name clears it (dropping on "No Artist").
    func assignArtist(_ name: String, to drag: FileDrag) {
        let ids = Set(drag.ids)
        for file in files where ids.contains(file.id) {
            file.fields.artist = name
        }
    }

    func forgetArtist(_ name: String) {
        artistMemory.forget(name)
        if artistFilter == .artist(name), !files.contains(where: { $0.fields.artist == name }) {
            artistFilter = .all
        }
    }

    // MARK: Bulk tools

    /// Numbers the files 1/N, 2/N… in list order.
    func numberTracks(_ files: [EditableFile]) {
        for (index, file) in files.enumerated() {
            file.fields.track = "\(index + 1)/\(files.count)"
        }
    }

    /// Uses each file name, without ".mp3", as the title.
    func useFileNamesAsTitles(_ files: [EditableFile]) {
        for file in files {
            file.fields.title = file.url.deletingPathExtension().lastPathComponent
        }
    }

    // MARK: Opening, saving, removing

    /// Adds MP3 files, and the MP3 files inside any folders, and selects them.
    /// Files already in the list are selected instead of added twice.
    func add(_ urls: [URL]) {
        var failures: [String] = []
        var added: Set<EditableFile.ID> = []
        for url in urls.flatMap(mp3Files) {
            if let existing = files.first(where: { $0.url == url }) {
                added.insert(existing.id)
                continue
            }
            do {
                let file = try EditableFile(url: url)
                files.append(file)
                added.insert(file.id)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !added.isEmpty {
            // Show the new files, even when a folder or search would hide them.
            artistFilter = .all
            searchText = ""
            selection = added
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    func remove(_ filesToRemove: [EditableFile]) {
        let unsaved = filesToRemove.filter(\.isDirty)
        if !unsaved.isEmpty {
            let alert = NSAlert()
            alert.messageText = unsaved.count == 1
                ? "Remove \"\(unsaved[0].name)\" without saving?"
                : "Remove \(unsaved.count) files without saving?"
            alert.informativeText = "Your unsaved changes will be lost."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let ids = Set(filesToRemove.map(\.id))
        files.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func revertSelected() {
        selectedFiles.forEach { $0.revert() }
    }

    @discardableResult
    func saveSelected() -> Bool {
        save(selectedFiles)
    }

    @discardableResult
    func saveAll() -> Bool {
        save(files)
    }

    /// Saves the changed files among `files` and remembers their artists.
    /// Returns false when at least one could not be saved.
    @discardableResult
    func save(_ files: [EditableFile]) -> Bool {
        var failures: [String] = []
        for file in files where file.isDirty {
            do {
                try file.save()
                artistMemory.remember(file.saved.artist)
            } catch {
                failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            errorMessage = "Some files were not saved:\n" + failures.joined(separator: "\n")
            return false
        }
        return true
    }

    private func mp3Files(at url: URL) -> [URL] {
        let url = url.standardizedFileURL
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return url.pathExtension.lowercased() == "mp3" ? [url] : []
        }
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        let found = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .map(\.standardizedFileURL)
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

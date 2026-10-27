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
}

@Observable
final class Library {
    private(set) var files: [EditableFile] = []
    var selection: EditableFile.ID?
    var isImporting = false
    var errorMessage: String?

    var selectedFile: EditableFile? {
        files.first { $0.id == selection }
    }

    var hasUnsavedChanges: Bool {
        files.contains { $0.isDirty }
    }

    /// Adds MP3 files, and the MP3 files inside any folders. Files already in the list are selected instead.
    func add(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls.flatMap(mp3Files) {
            if let existing = files.first(where: { $0.url == url }) {
                selection = existing.id
                continue
            }
            do {
                let file = try EditableFile(url: url)
                files.append(file)
                selection = file.id
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    func remove(_ file: EditableFile) {
        if file.isDirty {
            let alert = NSAlert()
            alert.messageText = "Remove \"\(file.url.lastPathComponent)\" without saving?"
            alert.informativeText = "Your changes to this file will be lost."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        files.removeAll { $0.id == file.id }
        if selection == file.id {
            selection = files.first?.id
        }
    }

    @discardableResult
    func save(_ file: EditableFile) -> Bool {
        do {
            try file.save()
            return true
        } catch {
            errorMessage = "\(file.url.lastPathComponent) was not saved: \(error.localizedDescription)"
            return false
        }
    }

    /// Saves every changed file. Returns false when at least one could not be saved.
    @discardableResult
    func saveAll() -> Bool {
        var failures: [String] = []
        for file in files where file.isDirty {
            do {
                try file.save()
            } catch {
                failures.append("\(file.url.lastPathComponent): \(error.localizedDescription)")
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

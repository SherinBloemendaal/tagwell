import SwiftUI

// The menu bar. Every item calls the same Library method as the button or context menu
// that does the same thing, and is greyed out when it has nothing to act on.

/// File: open, save, revert, and what the file list's context menu offers.
struct FileCommands: Commands {
    let library: Library

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { library.isImporting = true }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { library.saveSelected() }
                .keyboardShortcut("s")
                .disabled(library.isSaving || !library.selectionHasUnsavedChanges)

            Button("Save All") { library.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(library.isSaving || !library.hasUnsavedChanges)

            Button("Revert") { library.revertSelected() }
                .disabled(library.isSaving || !library.selectionHasUnsavedChanges)

            Divider()

            Button("Show in Finder") { library.showSelectedInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(library.selectedFiles.isEmpty)

            // No shortcut: ⌘⌫ deletes to the start of the line while typing in a tag field.
            Button("Remove from List") { library.removeSelected() }
                .disabled(library.isSaving || library.selectedFiles.isEmpty)
        }
    }
}

/// Edit: Find puts the cursor in the search field.
struct FindCommands: Commands {
    let library: Library

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find…") { library.focusSearch() }
                .keyboardShortcut("f")
        }
    }
}

/// View: the two fixed folders of the sidebar.
struct FolderCommands: Commands {
    let library: Library

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("All Files") { library.artistFilter = .all }
                .keyboardShortcut("1")
            Button("No Artist") { library.artistFilter = .noArtist }
                .keyboardShortcut("2")
            Divider()
        }
    }
}

/// Tags: the tools of the editor, for the selected files.
struct TagCommands: Commands {
    @Bindable var library: Library

    var body: some Commands {
        CommandMenu("Tags") {
            let files = library.selectedFiles

            Button("Number Tracks") { library.numberTracks(files) }
                .disabled(files.count < 2)

            Button("Use File Names as Titles") { library.useFileNamesAsTitles(files) }
                .disabled(files.isEmpty)

            Divider()

            Button("Use YouTube Thumbnails as Cover Art") {
                Task { await library.fetchYouTubeThumbnails(for: files) }
            }
            .disabled(files.isEmpty || library.isFetchingThumbnails)

            Toggle("Crop Thumbnails to a Square", isOn: $library.cropsThumbnails)

            Button("Remove Cover Art") { library.removeArtwork(from: files) }
                .disabled(!files.contains { $0.fields.artwork != nil })

            Divider()

            Toggle("Rename to Artist - Title When Saving", isOn: Binding {
                !files.isEmpty && files.allSatisfy { $0.rename == .fromTags }
            } set: { isOn in
                library.renameFromTags(isOn, files: files)
            })
            .disabled(files.isEmpty)
        }
    }
}

/// Artists: the artist folders of the sidebar.
struct ArtistCommands: Commands {
    let library: Library

    var body: some Commands {
        CommandMenu("Artists") {
            Button("Add Artist…") { library.isAddingArtist = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            if let name = library.openArtist {
                if library.artistMemory.contains(name) {
                    Button("Forget \(name)") { library.forgetArtist(name) }
                } else {
                    Button("Remember \(name)") { library.artistMemory.remember(name) }
                }
            } else {
                Button("Forget Artist") {}
                    .disabled(true)
            }
        }
    }
}

/// Help: Tagwell has no help book, so Help opens the pages on GitHub.
struct HelpCommands: Commands {
    private static let repository = URL(string: "https://github.com/SherinBloemendaal/tagwell")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Tagwell Help", destination: Self.repository.appending(path: "blob/main/README.md"))
            Link("Release Notes", destination: Self.repository.appending(path: "releases"))
            Divider()
            Link("Report a Problem", destination: Self.repository.appending(path: "issues/new"))
        }
    }
}

import ID3Kit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var library: Library

    var body: some View {
        NavigationSplitView {
            ArtistSidebar(library: library)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } content: {
            FileList(library: library)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            detail
        }
        .navigationSubtitle(library.unsavedCount == 0 ? "" : "\(library.unsavedCount) unsaved")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert", systemImage: "arrow.uturn.backward") { library.revertSelected() }
                    .disabled(!library.selectionHasUnsavedChanges)
                    .help("Undo the unsaved changes in the selected files")
                Button("Save", systemImage: "square.and.arrow.down") { library.saveSelected() }
                    .disabled(!library.selectionHasUnsavedChanges)
                    .help("Write the changes in the selected files to disk (⌘S)")
                Button("Save All", systemImage: "square.and.arrow.down.on.square") { library.saveAll() }
                    .disabled(!library.hasUnsavedChanges)
                    .help("Write the changes in every edited file to disk (⌥⌘S)")
            }
        }
        .labelStyle(.titleAndIcon)
        .fileImporter(
            isPresented: $library.isImporting,
            allowedContentTypes: [.mp3, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): library.add(urls)
            case .failure(let error): library.errorMessage = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls)
            return true
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        let selected = library.selectedFiles
        switch selected.count {
        case 0:
            ContentUnavailableView(
                "No File Selected",
                systemImage: "music.note",
                description: Text("Open MP3 files, or drop files or folders here. Select several files to edit them together.")
            )
        case 1:
            TagEditorView(file: selected[0], library: library)
                .id(selected[0].id)
        default:
            BulkEditorView(files: selected, library: library)
                .id(Set(selected.map(\.id)))
        }
    }
}

// MARK: - Artist folders

struct ArtistSidebar: View {
    @Bindable var library: Library
    @State private var isAddingArtist = false
    @State private var newArtist = ""

    var body: some View {
        List(selection: Binding(get: { library.artistFilter }, set: { if let filter = $0 { library.artistFilter = filter } })) {
            Section {
                folder("All Files", systemImage: "music.note.list", filter: .all)
                folder("No Artist", systemImage: "questionmark.folder", filter: .noArtist)
                    .dropDestination(for: FileDrag.self) { drags, _ in
                        drags.forEach { library.assignArtist("", to: $0) }
                        return true
                    }
                    .help("Files without an artist. Drop files here to clear their artist.")
            }
            Section("Artists") {
                ForEach(library.artistNames, id: \.self) { name in
                    folder(name, systemImage: "folder", filter: .artist(name))
                        .dropDestination(for: FileDrag.self) { drags, _ in
                            drags.forEach { library.assignArtist(name, to: $0) }
                            return true
                        }
                        .help("Drop files here to set their artist to \(name)")
                        .contextMenu {
                            if library.artistMemory.contains(name) {
                                Button("Forget Artist") { library.forgetArtist(name) }
                            } else {
                                Button("Remember Artist") { library.artistMemory.remember(name) }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Add Artist", systemImage: "plus") {
                    newArtist = ""
                    isAddingArtist = true
                }
                .buttonStyle(.borderless)
                .help("Create an artist folder you can drop files on")
                Spacer()
            }
            .padding(10)
        }
        .alert("Add Artist", isPresented: $isAddingArtist) {
            TextField("Name", text: $newArtist)
            Button("Add") { library.artistMemory.remember(newArtist) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The artist is remembered, so it shows up as a folder and as a suggestion in the Artist field.")
        }
    }

    private func folder(_ title: String, systemImage: String, filter: ArtistFilter) -> some View {
        Label(title, systemImage: systemImage)
            .badge(library.fileCount(for: filter))
            .tag(filter)
    }
}

// MARK: - File list

struct FileList: View {
    @Bindable var library: Library

    var body: some View {
        List(selection: $library.selection) {
            ForEach(library.visibleFiles) { file in
                FileRow(file: file)
                    .draggable(FileDrag(ids: library.targets(for: file).map(\.id)))
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(library.targets(for: file).map(\.url))
                        }
                        Button("Remove from List") { library.remove(library.targets(for: file)) }
                    }
            }
        }
        .searchable(text: $library.searchText, prompt: "Title, artist, album or file")
        .overlay {
            if library.files.isEmpty {
                Text("Drop MP3 files here")
                    .foregroundStyle(.secondary)
            } else if library.visibleFiles.isEmpty {
                ContentUnavailableView.search
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Open", systemImage: "plus") { library.isImporting = true }
                    .help("Open MP3 files or folders (⌘O)")
            }
        }
    }
}

struct FileRow: View {
    let file: EditableFile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fields.title.isEmpty ? file.name : file.fields.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.fields.artist.isEmpty ? file.name : "\(file.fields.artist) · \(file.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if file.isDirty {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            }
        }
    }
}

// MARK: - Single file editor

struct TagEditorView: View {
    @Bindable var file: EditableFile
    let library: Library

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    ArtworkWell(artwork: $file.fields.artwork)
                    VStack(spacing: 10) {
                        TextField("Title", text: $file.fields.title)
                        ArtistField(text: $file.fields.artist, library: library)
                        TextField("Album", text: $file.fields.album)
                        TextField("Album Artist", text: $file.fields.albumArtist)
                    }
                }
            }
            Section {
                TextField("Composer", text: $file.fields.composer)
                TextField("Genre", text: $file.fields.genre)
                TextField("Year", text: $file.fields.year, prompt: Text("2024"))
                TextField("Track", text: $file.fields.track, prompt: Text("3/12"))
                TextField("Disc", text: $file.fields.disc, prompt: Text("1/2"))
            }
            Section("Comment") {
                TextField("Comment", text: $file.fields.comment, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(3...8)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(file.name)
    }
}

/// The Artist field, with the remembered artists as suggestions.
struct ArtistField: View {
    @Binding var text: String
    var prompt: Text?
    let library: Library

    var body: some View {
        TextField("Artist", text: $text, prompt: prompt)
            .textInputSuggestions {
                ForEach(library.artistSuggestions(for: text), id: \.self) { name in
                    Text(name)
                        .textInputCompletion(name)
                }
            }
    }
}

struct ArtworkWell: View {
    @Binding var artwork: Artwork?
    /// The selected files have different cover art.
    var isMixed = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                if let artwork, let image = NSImage(data: artwork.data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if isMixed {
                    Text("Mixed")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                load(url)
                return true
            }
            .help("Drop an image here to use it as cover art")

            HStack {
                Button("Choose…") { isImporting = true }
                    .help("Pick an image file to use as cover art")
                Button("Remove") { artwork = nil }
                    .disabled(artwork == nil && !isMixed)
                    .help("Remove the cover art")
            }
            .controlSize(.small)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert(
            "This image can't be used",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load(_ url: URL) {
        do {
            artwork = try Artwork(imageFileAt: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

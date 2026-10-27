import ID3Kit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var library: Library

    var body: some View {
        NavigationSplitView {
            FileList(library: library)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if let file = library.selectedFile {
                TagEditorView(file: file) { library.save(file) }
                    .id(file.id)
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "music.note",
                    description: Text("Open MP3 files, or drop files or folders here.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Open Files", systemImage: "plus") { library.isImporting = true }
                    .help("Open MP3 files or folders")
            }
        }
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
}

struct FileList: View {
    @Bindable var library: Library

    var body: some View {
        List(selection: $library.selection) {
            ForEach(library.files) { file in
                FileRow(file: file)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                        Button("Remove from List") { library.remove(file) }
                    }
            }
        }
        .overlay {
            if library.files.isEmpty {
                Text("Drop MP3 files here")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FileRow: View {
    let file: EditableFile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !file.saved.artist.isEmpty {
                    Text(file.saved.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if file.isDirty {
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            }
        }
    }
}

struct TagEditorView: View {
    @Bindable var file: EditableFile
    let onSave: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    ArtworkWell(artwork: $file.fields.artwork)
                    VStack(spacing: 10) {
                        TextField("Title", text: $file.fields.title)
                        TextField("Artist", text: $file.fields.artist)
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
        .navigationTitle(file.url.lastPathComponent)
        .navigationSubtitle(file.isDirty ? "Edited" : "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert", systemImage: "arrow.uturn.backward") { file.revert() }
                    .disabled(!file.isDirty)
                    .help("Undo all unsaved changes")
                Button("Save", systemImage: "square.and.arrow.down", action: onSave)
                    .disabled(!file.isDirty)
                    .help("Save changes to the file (⌘S)")
            }
        }
    }
}

struct ArtworkWell: View {
    @Binding var artwork: Artwork?
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
                Button("Remove") { artwork = nil }
                    .disabled(artwork == nil)
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

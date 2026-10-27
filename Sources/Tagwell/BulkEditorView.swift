import ID3Kit
import SwiftUI

/// Edits several files at once. A field shows its value when all files agree and "Mixed" when they don't;
/// typing in a field sets that value on every selected file.
struct BulkEditorView: View {
    let files: [EditableFile]
    let library: Library
    @State private var cropThumbnails = true
    @State private var isFetchingThumbnails = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    ArtworkWell(artwork: artworkBinding, isMixed: !allEqual(\.artwork))
                    VStack(spacing: 10) {
                        ArtistField(text: binding(\.artist), prompt: prompt(\.artist), library: library)
                        TextField("Album", text: binding(\.album), prompt: prompt(\.album))
                        TextField("Album Artist", text: binding(\.albumArtist), prompt: prompt(\.albumArtist))
                        TextField("Genre", text: binding(\.genre), prompt: prompt(\.genre))
                    }
                }
            } header: {
                Text("\(files.count) files selected")
            } footer: {
                Text("Changes apply to every selected file. Nothing is written until you save.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Composer", text: binding(\.composer), prompt: prompt(\.composer))
                TextField("Year", text: binding(\.year), prompt: prompt(\.year))
                TextField("Disc", text: binding(\.disc), prompt: prompt(\.disc))
                TextField("Comment", text: binding(\.comment), prompt: prompt(\.comment))
            }
            Section("Tools") {
                LabeledContent("Track numbers") {
                    Button("Number Tracks") { library.numberTracks(files) }
                        .help("Set the track numbers to 1/\(files.count), 2/\(files.count)… in list order")
                }
                LabeledContent("Titles") {
                    Button("Use File Names") { library.useFileNamesAsTitles(files) }
                        .help("Set each title to its file name, without .mp3")
                }
                LabeledContent("Cover art") {
                    HStack {
                        if isFetchingThumbnails {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Toggle("Square", isOn: $cropThumbnails)
                            .help("Crop each 16:9 thumbnail to a square, keeping the middle")
                        Button("YouTube Thumbnails") {
                            isFetchingThumbnails = true
                            Task {
                                await library.useYouTubeThumbnails(files, cropToSquare: cropThumbnails)
                                isFetchingThumbnails = false
                            }
                        }
                        .disabled(isFetchingThumbnails)
                        .help("Give each file its own video's thumbnail, using the [video ID] in its file name or a YouTube link in its comment")
                    }
                }
            }
            Section("File names") {
                Toggle("Rename the files to Artist - Title when saving", isOn: renamesFromTags)
                    .help("Each file is named after its own artist and title when you save")
                if files.contains(where: { $0.rename == .fromTags }) {
                    let missing = files.count { $0.rename == .fromTags && $0.plannedName == nil }
                    if missing > 0 {
                        Text("\(missing) of these files have no title yet, so they can't be renamed.")
                            .foregroundStyle(.red)
                    } else if let example = files.first?.plannedName {
                        LabeledContent("For example", value: example)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("\(files.count) Files")
    }

    private var renamesFromTags: Binding<Bool> {
        Binding {
            files.allSatisfy { $0.rename == .fromTags }
        } set: { isOn in
            for file in files {
                file.rename = isOn ? .fromTags : .keep
            }
        }
    }

    private func allEqual<Value: Equatable>(_ keyPath: KeyPath<TagFields, Value>) -> Bool {
        guard let first = files.first?.fields[keyPath: keyPath] else { return true }
        return files.allSatisfy { $0.fields[keyPath: keyPath] == first }
    }

    private func binding(_ keyPath: WritableKeyPath<TagFields, String>) -> Binding<String> {
        Binding {
            allEqual(keyPath) ? files.first?.fields[keyPath: keyPath] ?? "" : ""
        } set: { value in
            for file in files {
                file.fields[keyPath: keyPath] = value
            }
        }
    }

    private func prompt(_ keyPath: KeyPath<TagFields, String>) -> Text? {
        allEqual(keyPath) ? nil : Text("Mixed")
    }

    private var artworkBinding: Binding<Artwork?> {
        Binding {
            allEqual(\.artwork) ? files.first?.fields.artwork : nil
        } set: { artwork in
            for file in files {
                file.fields.artwork = artwork
            }
        }
    }
}

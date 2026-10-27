import ID3Kit
import SwiftUI

/// Edits several files at once. A field shows its value when all files agree and "Mixed" when they don't;
/// typing in a field sets that value on every selected file.
struct BulkEditorView: View {
    let files: [EditableFile]
    let library: Library

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
            }
        }
        .formStyle(.grouped)
        .navigationTitle("\(files.count) Files")
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

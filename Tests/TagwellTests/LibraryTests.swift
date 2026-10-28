import Foundation
import ID3Kit
@testable import Tagwell
import Testing

private let audio: [UInt8] = [0xFF, 0xFB, 0x90, 0x64] + Array(repeating: 0, count: 2000)

/// A library with its own defaults, so tests never touch the real remembered artists.
private func makeLibrary() -> (Library, UserDefaults) {
    let defaults = UserDefaults(suiteName: "TagwellTests-\(UUID().uuidString)")!
    return (Library(artistMemory: ArtistMemory(defaults: defaults)), defaults)
}

/// Writes MP3 files with the given artists (empty = no tag) into a new folder.
private func makeFiles(_ artists: [String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "TagwellTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, artist) in artists.enumerated() {
        let url = folder.appending(path: String(format: "Set %02d.mp3", index + 1))
        try Data(audio).write(to: url)
        if !artist.isEmpty {
            var fields = TagFields()
            fields.artist = artist
            try ID3.write(fields, to: url)
        }
    }
    return folder
}

struct LibraryTests {
    @Test func `opening a folder adds and selects its MP3 files in name order`() throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["Hardwell", "", "Maddix"])])

        #expect(library.files.map(\.name) == ["Set 01.mp3", "Set 02.mp3", "Set 03.mp3"])
        #expect(library.selectedFiles.count == 3)
    }

    @Test func `artist folders filter the list and hidden files are not part of the selection`() throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["Hardwell", "", "Maddix", "Hardwell"])])

        library.artistFilter = .artist("Hardwell")
        #expect(library.visibleFiles.map(\.name) == ["Set 01.mp3", "Set 04.mp3"])
        #expect(library.selectedFiles.count == 2)

        library.artistFilter = .noArtist
        #expect(library.visibleFiles.map(\.name) == ["Set 02.mp3"])
        #expect(library.fileCount(for: .artist("Hardwell")) == 2)
    }

    @Test func `search matches title, artist, album and file name`() throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["Armin van Buuren", "Maddix"])])
        library.files[1].fields.album = "Tomorrowland 2024"

        library.searchText = "armin"
        #expect(library.visibleFiles.map(\.name) == ["Set 01.mp3"])
        library.searchText = "tomorrowland"
        #expect(library.visibleFiles.map(\.name) == ["Set 02.mp3"])
        library.searchText = "set 0"
        #expect(library.visibleFiles.count == 2)
    }

    @Test func `search needs every word, in any field and any order, ignoring case and accents`() throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["Hardwell", "Hardwell", "Armin van Buuren"])])
        library.files[0].fields.album = "Tomorrowland 2024"
        library.files[1].fields.album = "Ultra Miami 2024"
        library.files[2].fields.album = "Tomorrowland 2023"
        library.files[2].fields.genre = "Trancé"

        library.searchText = "Tomorrowland Hardwell"
        #expect(library.visibleFiles.map(\.name) == ["Set 01.mp3"])
        library.searchText = "  hardwell   TOMORROWLAND "
        #expect(library.visibleFiles.map(\.name) == ["Set 01.mp3"])
        library.searchText = "2024 hardwell"
        #expect(library.visibleFiles.map(\.name) == ["Set 01.mp3", "Set 02.mp3"])
        library.searchText = "tomorrowland trance"
        #expect(library.visibleFiles.map(\.name) == ["Set 03.mp3"])
        library.searchText = "hardwell maddix"
        #expect(library.visibleFiles.isEmpty)
        library.searchText = "set 03 armin"
        #expect(library.visibleFiles.map(\.name) == ["Set 03.mp3"])
    }

    @Test func `dropping files on an artist folder sets their artist, and on No Artist clears it`() throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["", "", "Maddix"])])
        let first = library.files[0], second = library.files[1]

        library.assignArtist("Hardwell", to: FileDrag(ids: [first.id, second.id]))
        #expect(first.fields.artist == "Hardwell")
        #expect(second.fields.artist == "Hardwell")
        #expect(first.isDirty)

        library.assignArtist("", to: FileDrag(ids: [first.id]))
        #expect(first.fields.artist.isEmpty)
        #expect(!first.isDirty)
    }

    @Test func `saving remembers the artist across launches`() async throws {
        let (library, defaults) = makeLibrary()
        library.add([try makeFiles([""])])
        library.files[0].fields.artist = "Armin van Buuren"

        #expect(await library.save(library.files))
        #expect(try ID3.readFields(from: library.files[0].url).artist == "Armin van Buuren")
        #expect(ArtistMemory(defaults: defaults).names == ["Armin van Buuren"])
    }

    @Test func `saving several files reports progress and clears it when done`() async throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["", "", ""])])
        library.files.forEach { $0.fields.album = "Ultra Europe 2024" }

        let save = Task { await library.save(library.files) }
        // The first file is written off the main thread, so the progress is visible meanwhile.
        while library.saveProgress == nil {
            await Task.yield()
        }
        #expect(library.saveProgress?.total == 3)
        #expect(library.isSaving)

        #expect(await save.value)
        #expect(library.saveProgress == nil)
        #expect(!library.hasUnsavedChanges)
    }

    @Test func `stop finishes the file being written and leaves the rest unsaved`() async throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["", "", "", "", ""])])
        library.files.forEach { $0.fields.album = "Parookaville 2024" }

        let save = Task { await library.save(library.files) }
        while library.saveProgress == nil {
            await Task.yield()
        }
        library.stopSaving()

        #expect(await save.value == false)
        #expect(library.saveProgress == nil)
        let saved = library.files.filter { !$0.isDirty }
        #expect(saved.count >= 1)
        #expect(saved.count < 5)
        // Every file is either fully saved or untouched on disk.
        for file in library.files {
            let onDisk = try ID3.readFields(from: file.url).album
            #expect(onDisk == (file.isDirty ? "" : "Parookaville 2024"))
        }
        #expect(library.errorMessage?.contains("Saving was stopped") == true)
    }

    @Test func `a second save while one runs is refused`() async throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["", ""])])
        library.files.forEach { $0.fields.genre = "Hardstyle" }

        let first = Task { await library.save(library.files) }
        while library.saveProgress == nil {
            await Task.yield()
        }
        #expect(await library.save(library.files) == false)
        #expect(await first.value)
    }

    @Test func `artist suggestions combine remembered and open artists`() throws {
        let (library, _) = makeLibrary()
        library.artistMemory.remember("Hardwell")
        library.add([try makeFiles(["Maddix"])])

        #expect(library.artistNames == ["Hardwell", "Maddix"])
        #expect(library.artistSuggestions(for: "har") == ["Hardwell"])
        #expect(library.artistSuggestions(for: "Hardwell").isEmpty)
    }

    @Test func `forgetting an artist leaves files alone and resets an empty folder`() throws {
        let (library, _) = makeLibrary()
        library.artistMemory.remember("Hardwell")
        library.artistFilter = .artist("Hardwell")

        library.forgetArtist("Hardwell")

        #expect(library.artistMemory.names.isEmpty)
        #expect(library.artistFilter == .all)
    }

    @Test func `bulk tools number tracks and copy file names into titles`() throws {
        let (library, _) = makeLibrary()
        library.add([try makeFiles(["", "", ""])])

        library.numberTracks(library.selectedFiles)
        library.useFileNamesAsTitles(library.selectedFiles)

        #expect(library.files.map(\.fields.track) == ["1/3", "2/3", "3/3"])
        #expect(library.files.map(\.fields.title) == ["Set 01", "Set 02", "Set 03"])
    }
}

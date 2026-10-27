# Tagwell

A small, native macOS app for editing MP3 tags. Drop in some files, change what you need, save. Nothing else in the file is touched.

## What you can edit

Title, artist, album, album artist, composer, genre, year, track, disc, comment and cover art.

## How it treats your files

- **Only what you changed is rewritten.** Every other part of the tag stays exactly as it was, including data Tagwell does not show (MusicBrainz IDs, iTunes data, lyrics, ratings).
- **The audio is never touched.**
- **The tag keeps its version.** ID3v2.3 stays v2.3, ID3v2.4 stays v2.4. Files without a tag get ID3v2.3, which every player reads.
- **An old ID3v1 tag at the end of the file is updated too**, so the two never disagree.
- **Saving is safe.** The new file is written next to the old one and then swapped in, so a failed save never leaves a broken MP3.
- **Damaged tags are refused, not overwritten.** The same goes for the very old ID3v2.2 format.
- **Invalid input is caught before saving**, for example a full date in an ID3v2.3 file (which only stores a year) or a track number that is not a number.

## Using it

- Open files with ⌘O, by dropping MP3 files or whole folders on the window, or with "Open With" in Finder.
- To add cover art, drop an image on the artwork box or click Choose…. JPEG and PNG are stored as they are; other formats such as HEIC are converted to JPEG.
- ⌘S saves the current file, ⌥⌘S saves all files, and Revert undoes your unsaved changes. A dot in the list marks files with unsaved changes, and Tagwell asks before quitting if there are any.

## Building

Requires macOS 14 or later and Xcode 26 (Swift 6.2 or later). There are no dependencies.

```bash
./build-app.sh
open build/Tagwell.app
```

The app is signed for local use only (ad-hoc), so a copy built on one Mac will not open on another without being signed again.

Run the tests with:

```bash
swift test
```

## Layout

- `Sources/ID3Kit`: reading and writing ID3v2.3, ID3v2.4 and ID3v1 tags. No AppKit, so it can be used on its own.
- `Sources/Tagwell`: the SwiftUI app.
- `Tests/ID3KitTests`: tests for the tag code.

## License

MIT. See [LICENSE](LICENSE).

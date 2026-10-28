import AppKit
import SwiftUI

@main
struct TagwellApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Tagwell", id: "main") {
            ContentView(library: appDelegate.library)
        }
        .defaultSize(width: 1100, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: appDelegate.updater.updater)
            }
            LibraryCommands(library: appDelegate.library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = Library()
    let updater = AppUpdater()

    /// Files opened from Finder ("Open With", or dropped on the Dock icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        library.add(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if library.isSaving {
            let alert = NSAlert()
            alert.messageText = "Tagwell is still saving"
            alert.informativeText = "Quit again when saving has finished, or stop the save first."
            alert.runModal()
            return .terminateCancel
        }
        guard library.hasUnsavedChanges else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Save your changes before quitting?"
        alert.informativeText = "\(library.unsavedCount) \(library.unsavedCount == 1 ? "file has" : "files have") changes that are not saved yet."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Save with the progress window showing, then quit. When a file fails or the save
            // is stopped, Tagwell stays open and shows what was not saved.
            Task {
                if await library.save(library.files) {
                    NSApp.terminate(nil)
                }
            }
            return .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

struct LibraryCommands: Commands {
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
        }
    }
}

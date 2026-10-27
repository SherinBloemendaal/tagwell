import AppKit
import SwiftUI

@main
struct TagwellApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Tagwell", id: "main") {
            ContentView(library: appDelegate.library)
        }
        .defaultSize(width: 900, height: 620)
        .commands {
            LibraryCommands(library: appDelegate.library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = Library()

    /// Files opened from Finder ("Open With", or dropped on the Dock icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        library.add(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard library.hasUnsavedChanges else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Save your changes before quitting?"
        alert.informativeText = "Some files have changes that are not saved yet."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return library.saveAll() ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn: return .terminateNow
        default: return .terminateCancel
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
            Button("Save") {
                if let file = library.selectedFile { library.save(file) }
            }
            .keyboardShortcut("s")
            .disabled(library.selectedFile?.isDirty != true)

            Button("Save All") { library.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!library.hasUnsavedChanges)

            Button("Revert") { library.selectedFile?.revert() }
                .disabled(library.selectedFile?.isDirty != true)
        }
    }
}

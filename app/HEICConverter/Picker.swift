import AppKit
import UniformTypeIdentifiers

enum Picker {
    /// Show an NSOpenPanel that accepts any combination of image files and folders.
    /// Returns nil if the user cancels.
    static func chooseFilesOrFolders() -> [URL]? {
        runPanel { panel in
            panel.title = "Choose images or folders"
            panel.prompt = "Convert"
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [UTType.image, UTType.folder]
            panel.treatsFilePackagesAsDirectories = false
        }
    }

    /// Show an NSOpenPanel that lets the user pick a single folder, used for the
    /// optional custom output directory in Settings.
    static func chooseOutputDirectory() -> URL? {
        runPanel { panel in
            panel.title = "Choose output folder"
            panel.prompt = "Use Folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
        }?.first
    }

    private static func runPanel(configure: (NSOpenPanel) -> Void) -> [URL]? {
        let panel = NSOpenPanel()
        configure(panel)
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls : nil
    }
}

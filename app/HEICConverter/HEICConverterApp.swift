import SwiftUI

@main
struct HEICConverterApp: App {
    @StateObject private var runner = ConversionRunner()

    var body: some Scene {
        MenuBarExtra("HEIC Converter", systemImage: "photo.on.rectangle.angled") {
            MenuContentView()
                .environmentObject(runner)
        }
        .menuBarExtraStyle(.menu)
    }
}

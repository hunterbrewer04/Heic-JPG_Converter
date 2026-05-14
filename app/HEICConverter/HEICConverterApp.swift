import SwiftUI

@main
struct HEICConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var runner = ConversionRunner()

    var body: some Scene {
        MenuBarExtra("Loosey Goosey", systemImage: "photo.stack") {
            PanelRootView()
                .environmentObject(runner)
                .frame(width: 340)
                .fixedSize(horizontal: false, vertical: true)
                .onAppear { delegate.runner = runner }
        }
        .menuBarExtraStyle(.window)
    }
}

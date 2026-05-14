import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var runner: ConversionRunner?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runner = runner, runner.hasInflight else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Conversions in progress."
        alert.informativeText = "Quit anyway? Any in-flight conversions will be cancelled."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            runner.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }
}

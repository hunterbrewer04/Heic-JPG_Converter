# Handoff — Fix Cross-App Drag in Loosey Goosey

> **For:** a fresh Claude Code session (or a developer) picking this up cold.
> **Created:** 2026-05-14 by the previous session that built the glass UI.
> **Repo:** `/Users/hunterbrewer/Code/Heic-JPG_Converter`
> **Current branch:** `main` (PR #4 already merged; tip is `382929e`)

---

## Problem

When the user opens the **Loosey Goosey** menu bar panel and tries to drag a HEIC file from Finder onto its drop zone, the panel auto-dismisses the moment focus shifts to Finder. The drag has nowhere to land. The drop never registers.

## Root cause

`HEICConverterApp.swift` uses `MenuBarExtra("…", systemImage: …) { … }.menuBarExtraStyle(.window)`. Under the hood that's an `NSPopover` with `behavior = .transient` — it auto-dismisses on focus change. This is by design for menu-style popovers; it's the wrong primitive for an app that needs to accept drags from other apps.

## Fix (chosen by user)

Replace `MenuBarExtra(.window)` with a custom `NSStatusBar.system.statusItem(…)` + `NSPanel`. The panel uses flags that keep it visible when our app loses focus, and a global mouse-up monitor handles click-outside-to-dismiss without breaking drags. This is the pattern Bartender, Things' quick-entry, IINA's playlist popout, and most polished menu bar apps use.

Effort: ~80–120 LOC change across 3 files.

---

## Repo orientation (read these first)

| File | Role | Current state |
|---|---|---|
| `app/HEICConverter/HEICConverterApp.swift` | `@main` entry. Currently defines `MenuBarExtra(.window)`. **TO BE REWRITTEN.** |
| `app/HEICConverter/AppDelegate.swift` | Quit-confirmation alert. **TO BE EXPANDED** to manage status item + panel. |
| `app/HEICConverter/ConversionRunner.swift` | Conversion engine. Currently sets `panelIsKey` from `NSApplication.didBecomeActive/Resign` observers. Those observers will become stale and should be **removed** (since the new panel is `.nonactivatingPanel` and our app stays inactive). The flag itself stays — it gates the completion notification. |
| `app/HEICConverter/Views/PanelRootView.swift` | The SwiftUI view tree the panel hosts. **UNCHANGED.** |
| `app/project.yml` | XcodeGen spec. **UNCHANGED.** |

Also read `app/HEICConverter/Info.plist` — it has `LSUIElement = true` already (no Dock icon). The new setup preserves this.

---

## Build / test environment (non-negotiable)

The user's `xcode-select` is pointed at Command Line Tools, not full Xcode. **Every `xcodebuild` invocation must be prefixed with:**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Standard build command:
```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | grep -iE "(error|warning|succeed)" | head -20
```

The `.xcodeproj` is gitignored and regenerated from `project.yml`. **After any file create/delete, run `xcodegen generate` before building** or the new file won't be picked up.

## Branch + commit conventions

- Work on a new feature branch: `feat/persistent-panel` or similar (don't push directly to `main`).
- Each logical change = one commit.
- Commit messages **must** end with:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- Open a draft PR with `gh pr create --draft --base main`.
- `gh` is authenticated (`gho_…` token with `repo` scope).

---

## Implementation plan

### Step 1 — Strip `HEICConverterApp.swift` to a minimal App shell

The App struct can't be empty (Swift requires a non-empty scene tree), so use a hidden `Settings` scene. AppDelegate will own everything else.

**Replace the entire contents of `app/HEICConverter/HEICConverterApp.swift` with:**

```swift
import SwiftUI

@main
struct HEICConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // AppDelegate owns the status item, panel, and ConversionRunner.
        // Settings is a placeholder scene that never appears (LSUIElement hides everything).
        Settings { EmptyView() }
    }
}
```

That's it for this file.

### Step 2 — Rewrite `AppDelegate.swift` to own status item + panel

**Replace the entire contents of `app/HEICConverter/AppDelegate.swift` with:**

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Owned objects — set once in applicationDidFinishLaunching
    private(set) var runner: ConversionRunner!
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var clickOutsideMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner = ConversionRunner()
        setupStatusItem()
        setupPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeClickOutsideMonitor()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runner, runner.hasInflight else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Conversions in progress."
        alert.informativeText = "Quit anyway? In-flight conversions will be cancelled."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .warning

        if alert.runModal() == .alertSecondButtonReturn {
            runner.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }

    // MARK: - Status item (menu bar icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "photo.stack",
                accessibilityDescription: "Loosey Goosey"
            )
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    // MARK: - Panel (SwiftUI in NSHostingController, wrapped in NSPanel)

    private func setupPanel() {
        let host = NSHostingController(rootView:
            PanelRootView()
                .environmentObject(runner)
                .frame(width: 340)
                .fixedSize(horizontal: false, vertical: true)
        )

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            // .nonactivatingPanel: don't make our app the active app when shown.
            // .borderless: no title bar / window chrome (we draw our own glass shell).
            // .resizable: needed so the panel can size to its hosted view.
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false           // stay visible when user clicks into Finder
        p.becomesKeyOnlyIfNeeded = true       // don't steal first-responder unnecessarily
        p.level = .floating                   // above regular windows
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel = p
    }

    // MARK: - Show / hide

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Make panel size to its hosted SwiftUI content first.
        panel.layoutIfNeeded()

        // Anchor the panel just below the status item button.
        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height - 6
        )
        panel.setFrameOrigin(clampedToScreen(origin: origin, size: panelSize))
        panel.orderFrontRegardless()

        runner?.panelIsKey = true
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        runner?.panelIsKey = false
        removeClickOutsideMonitor()
    }

    /// Keep panel on-screen if the status item is near the right edge of a small display.
    private func clampedToScreen(origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) })
                ?? NSScreen.main else { return origin }
        let visible = screen.visibleFrame
        let maxX = visible.maxX - size.width - 8
        let minX = visible.minX + 8
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: origin.y
        )
    }

    // MARK: - Click-outside-to-dismiss

    /// Listens for mouse-UP events outside our app. mouseUp (not mouseDown) is the
    /// correct event: a click-and-release outside our app dismisses the panel, but a
    /// drag that *starts* outside and *ends* inside our panel will NOT dismiss
    /// (because the mouseUp happens inside our window and global monitors only fire
    /// for events outside our process).
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
```

### Step 3 — Simplify `ConversionRunner.swift`

The current `init()` registers two `NSApplication.didBecomeActive/Resign` observers to drive `panelIsKey`. With a non-activating panel, those notifications won't fire reliably (our app stays in the background). The flag is now driven directly by `AppDelegate.showPanel()` / `hidePanel()`, so the observers are stale and should be removed.

**Open `app/HEICConverter/ConversionRunner.swift` and:**

1. Find the `init()` block (around lines 14–25):

   ```swift
   init() {
       NotificationCenter.default.addObserver(
           forName: NSApplication.didBecomeActiveNotification,
           object: nil, queue: .main
       ) { [weak self] _ in
           Task { @MainActor in self?.panelIsKey = true }
       }
       NotificationCenter.default.addObserver(
           forName: NSApplication.didResignActiveNotification,
           object: nil, queue: .main
       ) { [weak self] _ in
           Task { @MainActor in self?.panelIsKey = false }
       }
   }
   ```

2. **Delete the entire `init()` block.** The implicit memberwise initializer for the class will be used; nothing needs to replace it.

3. The `panelIsKey` property declaration stays as-is:

   ```swift
   var panelIsKey: Bool = false
   ```

   (Note: change `private var` to `var` since AppDelegate now sets it directly — verify the current visibility and adjust.)

### Step 4 — Verify

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | grep -iE "(error|warning|succeed)" | head -20
```

Expected: `** BUILD SUCCEEDED **`. No `panelIsKey` warnings. No "Cannot find" errors.

Run unit tests:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | grep -iE "(test suite|executed)" | tail -10
```

Expected: `Executed 10 tests, with 0 failures`. (CLI test runs can fail with a Team ID code-signing mismatch — if that happens, the tests will still pass when run from Xcode itself via ⌘U.)

### Step 5 — Manual smoke test (in Xcode)

Open `app/HEICConverter.xcodeproj`, ⌘R. Then:

- [ ] Menu bar shows the `photo.stack` icon.
- [ ] Click icon → glass panel appears below it, positioned correctly.
- [ ] Click icon again → panel hides.
- [ ] Click panel open → click into Finder → **panel stays visible** (this is the fix).
- [ ] From Finder, drag a HEIC onto the drop zone → file converts → "Show" pill appears.
- [ ] Click outside the panel (anywhere in Finder, in Desktop, in another app) → panel hides.
- [ ] Gear icon settings popover still works.
- [ ] Quit confirmation appears if you ⌘Q with a batch running.
- [ ] No Dock icon (LSUIElement honored).

### Step 6 — Commit, push, open PR

```bash
git add app/HEICConverter/HEICConverterApp.swift \
        app/HEICConverter/AppDelegate.swift \
        app/HEICConverter/ConversionRunner.swift
git commit -m "$(cat <<'EOF'
feat: replace MenuBarExtra with NSStatusItem + NSPanel for persistent panel

The MenuBarExtra(.window) popover auto-dismisses on focus change, which
breaks drag-and-drop from other apps (e.g., Finder). Replaces it with a
custom NSStatusItem + NSPanel that keeps the panel visible when our app
loses focus. A global mouseUp monitor handles click-outside-to-dismiss
without breaking incoming drags (mouseDown happens outside, mouseUp
happens inside our panel during a drag, so the monitor doesn't fire).

panelIsKey is now driven by AppDelegate.showPanel/hidePanel directly,
removing the stale NSApplication.didBecomeActive/Resign observers from
ConversionRunner.init (which wouldn't have fired reliably since the new
panel is non-activating).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat/persistent-panel
gh pr create --draft --base main --title "Persistent panel: NSStatusItem + NSPanel for cross-app drag"
```

---

## Things that will trip you up

### SourceKit false positives after `xcodegen generate`

After regenerating the project, SourceKit's live diagnostics will throw errors like:
- "Cannot find type 'QueueItem' in scope"
- "Cannot find 'Theme' in scope"
- "No such module 'XCTest'"

These are **false positives** — the actual `xcodebuild` compiler succeeds. SourceKit's index is just lagging. Trust `xcodebuild` output, not the squiggly underlines.

### Quitting Xcode before regenerating

If Xcode is open and you run `xcodegen generate`, Xcode pops a recovery dialog. Quit Xcode (`osascript -e 'tell application "Xcode" to quit'`) before regenerating to avoid this.

### NSPanel sizing

`NSHostingController` is what makes the panel auto-size to SwiftUI content. If you use `NSHostingView` instead and set it as `contentView`, the panel won't size correctly. Use `contentViewController` (which is `NSHostingController`-friendly).

### Status item button frame

`button.frame` is in window coordinates (the status bar window). Use `buttonWindow.convertToScreen(button.frame)` to get screen coordinates before positioning the panel. This is in the code above; don't skip it.

### `.nonactivatingPanel` interaction with first-responder

With `.nonactivatingPanel`, clicking inside the panel may not give text fields keyboard focus automatically. For our settings popover (the gear menu), the toggles and slider should still work — but if you find that focus is weird, set `becomesKeyOnlyIfNeeded = true` (already in the code) and as a fallback `makeKey()` explicitly inside `showPanel()` once it's positioned. Watch out for `.makeKeyAndOrderFront()` which would activate the app and steal focus from the user's other work.

### Click-outside monitor + nested popovers

When the user clicks the gear inside our panel to open the SwiftUI settings popover, the global monitor doesn't fire (the click is inside our process). But the SwiftUI popover may itself capture and dismiss when clicking outside it within our app. If the settings popover misbehaves (closes too eagerly or doesn't close on outside click), the most likely cause is its `arrowEdge` or `attachmentAnchor` configuration, not the panel system.

---

## What you do NOT need to touch

- `app/HEICConverter/Views/*` — all 7 view files stay as-is.
- `app/HEICConverter/Theme.swift`, `QueueItem.swift`, `VisualEffectView.swift`, `Converter.swift`, `Scanner.swift`, `Picker.swift`, `Settings.swift` — all unchanged.
- `app/HEICConverter/Info.plist` — already has `LSUIElement = true` and `CFBundleDisplayName = "Loosey Goosey"`.
- `app/project.yml` — already correctly configured.
- `app/HEICConverterTests/*` — tests don't exercise the App scene, so they're unaffected.

## Out of scope for this PR

- Adding a "pin" toggle to keep the panel open at a specific position.
- Changing the panel's animation when showing/hiding (default is fine).
- Persisting panel position between launches.
- Right-click status item → context menu (Quit, Settings…). Nice future addition, not needed for the drag fix.

---

## Reference: related session artifacts

- Original design spec: `docs/specs/2026-05-14-loosey-goosey-glass-ui-design.md`
- Original implementation plan: `docs/plans/2026-05-14-loosey-goosey-glass-ui.md` (this fix supersedes the App scene section)
- Manual smoke test checklist: `docs/manual-smoke-test.md` (the "click into Finder → panel stays" item is the new gate)
- Merged PR: https://github.com/hunterbrewer04/Heic-JPG_Converter/pull/4

If anything in this handoff conflicts with the original spec, **this handoff wins** — the spec was written before we knew the drag interaction would matter.

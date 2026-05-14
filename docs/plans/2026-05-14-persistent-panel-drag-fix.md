# Persistent Panel (Drag-Fix) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `MenuBarExtra(.window)` with a hand-built `NSStatusItem` + `NSPanel` so the menu-bar panel stays visible when our app loses focus, restoring cross-app drag-and-drop from Finder into the drop zone.

**Architecture:** Swap the SwiftUI `MenuBarExtra` scene for a custom `NSStatusItem` driven by `AppDelegate`. The popover becomes a `.nonactivatingPanel` `NSPanel` hosting `PanelRootView` inside an `NSHostingController`. A global `mouseUp` event monitor handles click-outside-dismiss without breaking incoming drags. `ConversionRunner.panelIsKey` is now set directly by `AppDelegate.showPanel/hidePanel`, so the stale `NSApplication.didBecomeActive/Resign` observers (and their `Task { @MainActor in … }` workaround from `382929e`) are deleted.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI App, AppKit (`NSStatusItem`, `NSPanel`, `NSHostingController`, `NSEvent` global monitor), XcodeGen.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `app/HEICConverter/HEICConverterApp.swift` | **Rewrite** | Minimal `App` shell with `@NSApplicationDelegateAdaptor` + hidden `Settings` scene. No `MenuBarExtra`. |
| `app/HEICConverter/AppDelegate.swift` | **Rewrite (expand)** | Owns `ConversionRunner`, `NSStatusItem`, `NSPanel`, click-outside global monitor. Keeps the quit-confirmation alert. |
| `app/HEICConverter/ConversionRunner.swift` | **Edit (delete init body)** | Remove the two `NSApplication.didBecomeActive/Resign` observers. `panelIsKey` declaration stays; bump visibility from `private var` → `var` so `AppDelegate` can set it. |
| `app/HEICConverter/Views/PanelRootView.swift` and all other `Views/*` | **Unchanged** | View tree is intentionally untouched. |
| `app/HEICConverterTests/AppDelegatePanelTests.swift` | **Create (optional, Task 5)** | Unit test for `clampedToScreen` math — the one piece of new logic that's testable without AppKit-on-screen. |

**Branch:** `feat/persistent-panel`
**Base:** `main` (tip `382929e`)

---

## Build/test prerequisites

Every `xcodebuild` invocation MUST be prefixed with `DEVELOPER_DIR` because the user's `xcode-select` points at Command Line Tools, not full Xcode:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

After any file create/delete, run `xcodegen generate` in `app/` before building — the `.xcodeproj` is gitignored and regenerated from `app/project.yml`.

If Xcode is open, quit it before regenerating to avoid the project-reload dialog:
```bash
osascript -e 'tell application "Xcode" to quit'
```

---

### Task 1: Create the feature branch

**Files:** none modified.

- [ ] **Step 1: Confirm clean working tree on `main`**

```bash
git -C /Users/hunterbrewer/Code/Heic-JPG_Converter status --short
git -C /Users/hunterbrewer/Code/Heic-JPG_Converter log -1 --oneline
```
Expected: empty `status --short` (apart from the new plan file which is fine), `HEAD` at `382929e`.

- [ ] **Step 2: Branch**

```bash
git -C /Users/hunterbrewer/Code/Heic-JPG_Converter checkout -b feat/persistent-panel
```
Expected: `Switched to a new branch 'feat/persistent-panel'`.

---

### Task 2: Reduce `HEICConverterApp.swift` to an App shell

**Files:**
- Modify: `app/HEICConverter/HEICConverterApp.swift` (entire file)

This file currently declares the `MenuBarExtra` scene and owns `@StateObject runner`. Both move to `AppDelegate`. The `App` body keeps a hidden `Settings` scene so the `App` protocol's non-empty-scene requirement is satisfied; `LSUIElement = true` in `Info.plist` keeps the placeholder from ever appearing.

- [ ] **Step 1: Overwrite the file**

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

- [ ] **Step 2: Commit the skeleton** (build will fail until Task 3 — that's OK; we'll squash-or-roll later)

Skip committing now — wait until Task 3 finishes so the tree compiles between commits.

---

### Task 3: Rewrite `AppDelegate.swift` to own status item + panel

**Files:**
- Modify: `app/HEICConverter/AppDelegate.swift` (entire file)

This is the bulk of the change. Read the comments inline — they encode the *why* for each property setting.

- [ ] **Step 1: Overwrite the file**

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Owned objects — set once in applicationDidFinishLaunching.
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
        panel.setFrameOrigin(Self.clampedToScreen(origin: origin, size: panelSize))
        panel.orderFrontRegardless()

        runner.panelIsKey = true
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        runner.panelIsKey = false
        removeClickOutsideMonitor()
    }

    /// Keep panel on-screen if the status item is near the right edge of a small display.
    /// Static so it's unit-testable without an `AppDelegate` instance.
    static func clampedToScreen(origin: NSPoint, size: NSSize, visibleFrame: NSRect? = nil) -> NSPoint {
        let visible: NSRect
        if let visibleFrame {
            visible = visibleFrame
        } else if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
            visible = screen.visibleFrame
        } else {
            return origin
        }
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

Notes vs. the original draft in `docs/drag-fix.md`:
- `clampedToScreen` is promoted to a `static` method with an optional `visibleFrame` override — this is the **only** new piece of pure logic in this PR, and the override makes it unit-testable without needing a live `NSScreen`.
- `runner?.panelIsKey = …` is replaced with `runner.panelIsKey = …` because `runner` is now a force-unwrapped IUO populated in `applicationDidFinishLaunching` and the codepaths that touch it run strictly after launch.

---

### Task 4: Strip stale observers from `ConversionRunner.swift`

**Files:**
- Modify: `app/HEICConverter/ConversionRunner.swift:10` (visibility change)
- Modify: `app/HEICConverter/ConversionRunner.swift:14-27` (delete init body)

The two `NSApplication.didBecomeActive/Resign` observers (and the `Task { @MainActor in … }` workaround added in commit `382929e`) are now stale: the new panel is `.nonactivatingPanel`, so the app never becomes "active" in the AppKit sense. `panelIsKey` is driven directly by `AppDelegate.showPanel/hidePanel` instead.

Copilot's comment on PR #4 (line 23 of `ConversionRunner.swift`) flagged exactly this — that `panelIsKey` should reflect *panel visibility*, not *app activation*. This task resolves that comment.

- [ ] **Step 1: Bump `panelIsKey` visibility**

Change line 10:
```swift
private var panelIsKey: Bool = false
```
to:
```swift
var panelIsKey: Bool = false
```

- [ ] **Step 2: Delete the entire `init()` block (lines 14-27)**

After deletion, the area between `private var panelIsKey: Bool = false` and `private var processorTask: Task<Void, Never>?` should look like:

```swift
    @Published private(set) var queue: [QueueItem] = []
    var panelIsKey: Bool = false

    private var processorTask: Task<Void, Never>?

    var hasInflight: Bool {
        // … unchanged …
    }
```

No explicit `init()` is declared; Swift's implicit memberwise init for classes covers it.

---

### Task 5: Add a unit test for `clampedToScreen` (optional but recommended)

**Files:**
- Create: `app/HEICConverterTests/AppDelegatePanelTests.swift`

This is the one piece of new logic that's purely deterministic (no AppKit windows on-screen). Adding a small test guards against accidental regression and satisfies the "always have a unit test for new pure-math helpers" instinct.

- [ ] **Step 1: Write the test file**

```swift
import XCTest
import AppKit
@testable import HEICConverter

final class AppDelegatePanelTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    func testOriginInsideScreen_isUnchanged() {
        let origin = NSPoint(x: 600, y: 600)
        let size = NSSize(width: 340, height: 500)
        let result = AppDelegate.clampedToScreen(origin: origin, size: size, visibleFrame: screen)
        XCTAssertEqual(result.x, 600, accuracy: 0.001)
        XCTAssertEqual(result.y, 600, accuracy: 0.001)
    }

    func testOriginPastRightEdge_clampsLeftward() {
        let origin = NSPoint(x: 1400, y: 600)   // panel would overflow right edge
        let size = NSSize(width: 340, height: 500)
        let result = AppDelegate.clampedToScreen(origin: origin, size: size, visibleFrame: screen)
        // maxX = 1440 - 340 - 8 = 1092
        XCTAssertEqual(result.x, 1092, accuracy: 0.001)
    }

    func testOriginPastLeftEdge_clampsRightward() {
        let origin = NSPoint(x: -50, y: 600)
        let size = NSSize(width: 340, height: 500)
        let result = AppDelegate.clampedToScreen(origin: origin, size: size, visibleFrame: screen)
        // minX = 0 + 8 = 8
        XCTAssertEqual(result.x, 8, accuracy: 0.001)
    }

    func testYIsNeverClamped() {
        let origin = NSPoint(x: 600, y: 99_999)
        let size = NSSize(width: 340, height: 500)
        let result = AppDelegate.clampedToScreen(origin: origin, size: size, visibleFrame: screen)
        XCTAssertEqual(result.y, 99_999, accuracy: 0.001,
                       "Y clamping is intentionally not implemented — panel hangs from menu bar at fixed top.")
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the test file is picked up**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodegen generate
```
Expected: `Generated project successfully`.

---

### Task 6: Build and verify

- [ ] **Step 1: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | grep -iE "(error|warning|succeed)" | head -40
```
Expected: `** BUILD SUCCEEDED **`. No `panelIsKey`, `runner`, or "Cannot find" errors.

If SourceKit shows squigglies in editor (e.g. "Cannot find type 'QueueItem' in scope") after running `xcodegen`, ignore them — those are SourceKit index-lag false positives, not compiler errors. Trust `xcodebuild`.

- [ ] **Step 2: Test**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | grep -iE "(test suite|executed|failed)" | tail -15
```
Expected: `Executed N tests, with 0 failures` (N = previous count + 4 from Task 5).

If CLI test runs fail with a Team-ID code-signing mismatch, the tests still pass when run from Xcode itself (⌘U). Note this in the PR description if it happens.

---

### Task 7: Manual smoke test

Open `app/HEICConverter.xcodeproj` in Xcode, ⌘R, then walk this checklist. The cross-app drag test is the gating one — that's what this PR exists to fix.

- [ ] Menu bar shows the `photo.stack` icon (no Dock icon because `LSUIElement = true`).
- [ ] Click icon → glass panel appears below it, positioned correctly.
- [ ] Click icon again → panel hides.
- [ ] Click panel open → click into Finder → **panel stays visible** (THE FIX).
- [ ] From Finder, drag a HEIC onto the drop zone → file converts → "Show" pill appears.
- [ ] Click outside the panel (Finder, Desktop, another app) → panel hides.
- [ ] Gear icon settings popover still works.
- [ ] Quit confirmation appears if ⌘Q while a batch is running.
- [ ] On a multi-monitor setup, status item near right edge of a small display: panel clamps to stay on-screen (covered by unit test, sanity-check visually).
- [ ] No completion notification fires while panel is visible (gated by `panelIsKey`).
- [ ] Quit app, relaunch, click icon: panel opens cleanly. (Verifies no monitor leak on terminate.)

---

### Task 8: Commit + PR

- [ ] **Step 1: Stage and commit**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter
git add app/HEICConverter/HEICConverterApp.swift \
        app/HEICConverter/AppDelegate.swift \
        app/HEICConverter/ConversionRunner.swift \
        app/HEICConverterTests/AppDelegatePanelTests.swift \
        docs/plans/2026-05-14-persistent-panel-drag-fix.md
git commit -m "$(cat <<'EOF'
feat: replace MenuBarExtra with NSStatusItem + NSPanel for persistent panel

MenuBarExtra(.window) renders an NSPopover with .transient behavior, which
auto-dismisses on focus change. That breaks drag-and-drop from Finder into
the panel's drop zone (focus shifts to Finder mid-drag, panel disappears,
drop never lands).

Replace it with NSStatusItem + a .nonactivatingPanel NSPanel that stays
visible when our app loses focus. A global mouseUp monitor handles
click-outside-dismiss without breaking drags: a drag that ends inside our
panel fires mouseUp inside our process, and global monitors don't see
in-process events. So the drag completes, then the next out-of-process
click-and-release dismisses the panel.

panelIsKey is now set directly by AppDelegate.showPanel/hidePanel,
resolving Copilot's PR #4 review note that it should track panel
visibility rather than app activation. The NSApplication.didBecomeActive
and didResignActive observers (and their Task { @MainActor in ... }
Swift 6 workaround from 382929e) are removed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin feat/persistent-panel
gh pr create --draft --base main \
  --title "Persistent panel: NSStatusItem + NSPanel for cross-app drag" \
  --body "$(cat <<'EOF'
## Summary
- Replaces `MenuBarExtra(.window)` (transient `NSPopover`) with a hand-built `NSStatusItem` + `.nonactivatingPanel` `NSPanel`. The panel stays visible when our app loses focus, so drag-and-drop from Finder into the drop zone now lands.
- A global `mouseUp` event monitor handles click-outside-dismiss without breaking incoming drags (mouseUp inside our panel fires inside our process, where global monitors don't see it).
- Drops the `NSApplication.didBecomeActive/Resign` observers from `ConversionRunner.init` (made stale by `.nonactivatingPanel`). `panelIsKey` is now set directly by `AppDelegate.showPanel/hidePanel`, addressing Copilot's PR #4 review feedback.
- Adds unit tests for `AppDelegate.clampedToScreen` — the only new pure-logic helper.

## Test plan
- [ ] `xcodebuild build` succeeds (with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
- [ ] `xcodebuild test` passes (note: CLI runs may fail with code-signing Team ID mismatch; ⌘U inside Xcode is the fallback).
- [ ] Manual smoke test in `docs/plans/2026-05-14-persistent-panel-drag-fix.md` Task 7. Gating item: drag HEIC from Finder → panel does NOT dismiss → file converts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL returned. Leave as draft until the manual smoke test in Task 7 is green.

---

## Self-review notes

- **Spec coverage:** Every step of `docs/drag-fix.md` is mapped to a task here. The only deviation is promoting `clampedToScreen` to a `static` testable helper (additive, not a behavior change).
- **Type/name consistency:** `runner` is `private(set) var runner: ConversionRunner!` everywhere — no `runner?` calls inside `AppDelegate` because the IUO is populated before any showPanel/hidePanel codepath can run.
- **Placeholder scan:** No TBDs, no "add error handling," no "similar to Task N." All code blocks contain the literal code to paste.
- **Out-of-scope reminders:** Right-click context menu on status item, panel-position persistence, animation tuning. None needed for the drag fix.

---

## Pre-existing Copilot comments from PR #4 — separate followups

The following Copilot comments on PR #4 are **not** addressed by this plan and should be triaged separately. They predate the drag bug and need their own PR(s):

| # | File / line | Issue | Severity |
|---|---|---|---|
| 1 | `ConversionRunner.swift:134` | `runOne` runs on `@MainActor`, so the synchronous `converter.convert(source)` blocks the UI and defeats parallelism. Mark `runOne` `nonisolated` and only hop to MainActor for queue mutations. | **High** — defeats the whole parallel-conversion design. |
| 2 | `ConversionRunner.swift:109` | Queue pick/claim isn't atomic — multiple tasks can grab the same `QueueItem` before any marks it `.converting`. Pick + mark in a single `MainActor` transaction. | **High** — can cause duplicate conversions of the same file. |
| 3 | `ConversionRunner.swift:49` | `enqueue` no longer calls `HEICScanner.dedupeByOutput` — two different source HEICs that map to the same target JPG can race. | Medium — `fileExists` precheck not race-safe. |
| 4 | `ConversionRunner.swift:23` | `panelIsKey` tracks app activation rather than panel visibility. | **Resolved by this PR.** |
| 5 | `ConversionRunner.swift:229` | Completion notification doesn't include "skipped" count even though `.skipped` is a meaningful outcome. | Low — UX polish. |
| 6 | `SettingsView.swift:22` | View body calls `OutputDirectoryResolver.resolve` which mutates `UserDefaults` — side effect inside SwiftUI body. | Medium — caused the bug fix in `20eec17`, but the underlying smell remains. |
| 7 | `SettingsFallbackTests.swift:17` (+ #15) | Test won't compile: `String?` compared to `String`. Needs `XCTUnwrap`. | Low — but means tests are likely not running. |
| 8 | `ConversionRunnerTests.swift:33` | `testClearCompleted` doesn't actually verify `clearCompleted` behavior. | Low — false coverage. |
| 9 | `Theme.swift:3` | Uses `NSColor` / `Scanner` without `import AppKit` / `import Foundation`. Relies on transitive imports. | Low — works today, brittle. |
| 10 | `QueueRowView.swift:31` | Uses `NSImage(data:)` without `import AppKit`. | Low — same as #9. |
| 11 | `Settings.swift:50` | `OutputDirectoryResolver.resolve` accepts any writable path without verifying `isDirectory == true`. | Medium — could break conversion with a confusing error. |

**Recommendation:** Land this drag-fix PR on its own (small, surgical, addresses one user-visible bug + clears Copilot comment #4). Open a separate `chore/pr4-followups` branch to batch #1, #2, #3, #6, #11 (the meaningful ones), and #7, #8, #9, #10 (the trivial cleanups). Comments #5 and #6 are arguably product decisions worth checking with the user before fixing.

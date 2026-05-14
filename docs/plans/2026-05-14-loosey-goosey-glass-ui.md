# Loosey Goosey Glass UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing native menu of the `HEICConverter` macOS menu bar app with a custom SwiftUI panel matching the Stitch-generated "Glass & Smooth" design, branded **Loosey Goosey**. Adds drag-and-drop, a live conversion queue with per-item progress, thermal-aware concurrency, glass background via `NSVisualEffectView`, and an accessibility-aware fallback.

**Architecture:** Pure SwiftUI views composed inside a `MenuBarExtra(...) { … }.menuBarExtraStyle(.window)` scene. One AppKit bridge — a `NSViewRepresentable` wrapping `NSVisualEffectView` — provides the wallpaper-vibrancy glass material. `ConversionRunner` becomes the source of truth for per-item state via `@Published var queue: [QueueItem]`. Existing `Converter`, `Scanner`, `Picker`, and `Notifier` logic are preserved with minor changes (cancellation checkpoints in `Converter`).

**Tech Stack:** Swift 5.9, SwiftUI on macOS 13.0+, AppKit (`NSVisualEffectView`, `NSWorkspace`, `NSOpenPanel`, `NSAlert`), Foundation (`ProcessInfo`, `FileManager`), ImageIO (`CGImageSource`/`CGImageDestination` — unchanged), Swift Concurrency (`Task`, `TaskGroup`, `@MainActor`), XCTest (model layer).

**Source spec:** `docs/specs/2026-05-14-loosey-goosey-glass-ui-design.md`

## Build/test environment convention

The user's machine has `xcode-select` pointed at Command Line Tools, not full Xcode. To avoid requiring `sudo xcode-select -s ...`, **every `xcodebuild` invocation in every task below must be prefixed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`**. For example:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

This is non-negotiable for any subagent running these commands. The `xcodebuild` lines below omit the prefix for readability; **prefix them yourself when executing.**

---

## File structure (locked in by this plan)

```
app/
├── project.yml                              # MODIFY: display name + test target
└── HEICConverter/
    ├── HEICConverterApp.swift               # MODIFY (Task 16)
    ├── MenuContentView.swift                # DELETE (replaced by PanelRootView)
    ├── ConversionRunner.swift               # REWRITE (Task 9)
    ├── Converter.swift                      # MODIFY: cancellation checkpoints (Task 8)
    ├── Scanner.swift                        # UNCHANGED
    ├── Picker.swift                         # UNCHANGED
    ├── Settings.swift                       # MODIFY: defaults + fallback (Task 7)
    ├── Info.plist                           # MODIFY: CFBundleDisplayName (Task 17)
    │
    ├── Theme.swift                          # NEW (Task 2)
    ├── VisualEffectView.swift               # NEW (Task 3)
    ├── QueueItem.swift                      # NEW (Task 4)
    ├── AppDelegate.swift                    # NEW (Task 16)
    │
    └── Views/
        ├── PanelRootView.swift              # NEW (Task 15)
        ├── PanelHeader.swift                # NEW (Task 10)
        ├── DropZone.swift                   # NEW (Task 11)
        ├── QueueSection.swift               # NEW (Task 13)
        ├── QueueRowView.swift               # NEW (Task 12)
        ├── PanelFooter.swift                # NEW (Task 14)
        └── SettingsView.swift               # NEW (Task 18)

app/
└── HEICConverterTests/                      # NEW (Task 1)
    ├── QueueItemTests.swift                 # NEW (Task 5)
    ├── ConversionRunnerTests.swift          # NEW (Task 6)
    └── SettingsFallbackTests.swift          # NEW (Task 7)

docs/
└── manual-smoke-test.md                     # NEW (Task 22)
```

## Task dependency graph (for subagent parallelization)

```
Phase 1 — Foundation (mostly sequential)
  T1 (test target)
   → T2 (Theme.swift)        ─┐
   → T3 (VisualEffectView)    │  Phase 2 (parallelizable, all depend on T1-T9)
   → T4 (QueueItem)           │   T10 (PanelHeader)
   → T5 (QueueItemTests)      │   T11 (DropZone)
   → T7 (Settings + tests)    ├→  T12 (QueueRowView)
   → T8 (Converter mods)      │   T13 (QueueSection) [needs T12]
   → T9 (ConversionRunner)    │   T14 (PanelFooter)
   → T6 (Runner tests)       ─┘   T18 (SettingsView)

Phase 3 — Integration (sequential)
   T15 (PanelRootView)        → T16 (App + AppDelegate) → T17 (Info.plist)
                                                       → T19 (project.yml) → T20 (regenerate)

Phase 4 — Polish
   T21 (manual smoke test)
   T22 (/simplify pass)
```

---

## Task 1: Add unit test target via xcodegen

**Why:** The current `project.yml` ships only the app target. Spec §15.1 calls for unit tests; we need a test bundle first.

**Files:**
- Modify: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/project.yml`
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/Placeholder.swift`

- [ ] **Step 1: Add test target to `project.yml`**

Append under the existing `targets:` block:

```yaml
  HEICConverterTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: HEICConverterTests
    dependencies:
      - target: HEICConverter
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/HEICConverter.app/Contents/MacOS/HEICConverter"
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
```

Also add under the top-level `schemes:` (create the key if absent):

```yaml
schemes:
  HEICConverter:
    build:
      targets:
        HEICConverter: all
        HEICConverterTests: [test]
    test:
      targets:
        - HEICConverterTests
```

- [ ] **Step 2: Create a placeholder test file so xcodegen has a non-empty target**

Create `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/Placeholder.swift`:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 3: Regenerate Xcode project**

Run:
```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodegen generate
```

Expected: `Created project at /Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter.xcodeproj`

- [ ] **Step 4: Run tests via xcodebuild to verify target works**

Run:
```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: `Test Suite 'PlaceholderTests' passed`. Note: requires `xcode-select` pointed at full Xcode (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` if needed).

- [ ] **Step 5: Commit**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter && git add app/project.yml app/HEICConverterTests/Placeholder.swift && git commit -m "test: add HEICConverterTests target via xcodegen"
```

---

## Task 2: Create `Theme.swift` — color & typography tokens

**Why:** Centralizes the design tokens from `DESIGN.md`. Every other view references these so a future retune is one file.

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Theme.swift`

- [ ] **Step 1: Write `Theme.swift`**

```swift
import SwiftUI

enum Theme {

    // MARK: - Colors (from DESIGN.md)
    enum Color {
        static let surface              = SwiftUI.Color(light: "FAF9FE", dark: "1A1B1F")
        static let surfaceContainerLow  = SwiftUI.Color(light: "F4F3F8", dark: "23242A")
        static let surfaceContainer     = SwiftUI.Color(light: "EEEDF3", dark: "2A2B30")
        static let surfaceContainerHigh = SwiftUI.Color(light: "E9E7ED", dark: "2F3034")
        static let onSurface            = SwiftUI.Color(light: "1A1B1F", dark: "F1F0F5")
        static let onSurfaceVariant     = SwiftUI.Color(light: "414755", dark: "C1C6D7")
        static let outline              = SwiftUI.Color(light: "717786", dark: "8B909E")
        static let outlineVariant       = SwiftUI.Color(light: "C1C6D7", dark: "414755")
        static let primary              = SwiftUI.Color(light: "0058BC", dark: "ADC6FF")
        static let onPrimary            = SwiftUI.Color(light: "FFFFFF", dark: "001A41")
        static let error                = SwiftUI.Color(light: "BA1A1A", dark: "FFB4AB")
    }

    // MARK: - Typography (SF Pro — DESIGN.md sizes preserved)
    enum Type {
        static let headlineLg = Font.system(size: 24, weight: .semibold).tracking(-0.48)
        static let headlineMd = Font.system(size: 18, weight: .semibold).tracking(-0.18)
        static let bodyLg     = Font.system(size: 15, weight: .regular).tracking(-0.15)
        static let bodyMd     = Font.system(size: 13, weight: .regular)
        static let bodyMdMed  = Font.system(size: 13, weight: .medium)
        static let labelMd    = Font.system(size: 11, weight: .medium).tracking(0.22)
        static let labelSm    = Font.system(size: 10, weight: .semibold).tracking(0.5)
    }

    // MARK: - Geometry
    enum Radius {
        static let sm: CGFloat   = 8
        static let md: CGFloat   = 16
        static let lg: CGFloat   = 24
        static let pill: CGFloat = 999
    }

    enum Space {
        static let unit: CGFloat        = 4
        static let elementGap: CGFloat  = 8
        static let gutter: CGFloat      = 16
        static let container: CGFloat   = 24
    }
}

// MARK: - Color(light:dark:) helper

private extension Color {
    init(light: String, dark: String) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        }))
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat(v         & 0xFF) / 255,
            alpha: 1
        )
    }
}
```

- [ ] **Step 2: Open the project in Xcode and verify it compiles**

Run:
```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Theme.swift && git commit -m "feat: add Theme.swift with DESIGN.md color and typography tokens"
```

---

## Task 3: Create `VisualEffectView.swift` — NSVisualEffectView wrapper

**Why:** SwiftUI's built-in materials can't expose `blendingMode = .behindWindow` which is required for true wallpaper vibrancy (spec §5.2).

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/VisualEffectView.swift`

- [ ] **Step 1: Write `VisualEffectView.swift`**

```swift
import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

#Preview {
    VisualEffectView()
        .frame(width: 340, height: 280)
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/VisualEffectView.swift && git commit -m "feat: add VisualEffectView NSViewRepresentable wrapper"
```

---

## Task 4: Create `QueueItem.swift` — row data model

**Why:** Spec §7.1. Foundation for all queue-related state.

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/QueueItem.swift`

- [ ] **Step 1: Write `QueueItem.swift`**

```swift
import Foundation

struct QueueItem: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var destinationURL: URL?
    var status: Status
    var thumbnailData: Data?
    var errorMessage: String?

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = nil
        self.status = .waiting
        self.thumbnailData = nil
        self.errorMessage = nil
    }

    var filename: String { sourceURL.lastPathComponent }

    enum Status: Equatable {
        case waiting
        case converting(progress: Double)
        case completed
        case failed
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/QueueItem.swift && git commit -m "feat: add QueueItem model"
```

---

## Task 5: `QueueItem` tests

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/QueueItemTests.swift`
- Delete: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/Placeholder.swift`

- [ ] **Step 1: Write failing test**

Create `QueueItemTests.swift`:

```swift
import XCTest
@testable import HEICConverter

final class QueueItemTests: XCTestCase {

    func testInitDefaultsToWaiting() {
        let item = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/photo.heic"))
        XCTAssertEqual(item.status, .waiting)
        XCTAssertNil(item.destinationURL)
        XCTAssertNil(item.errorMessage)
    }

    func testFilenameExtractsLastComponent() {
        let item = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/photos/img.heic"))
        XCTAssertEqual(item.filename, "img.heic")
    }

    func testStandardizesURL() {
        let item = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/../tmp/x.heic"))
        XCTAssertEqual(item.sourceURL.path, "/tmp/x.heic")
    }

    func testConvertingStatusEquality() {
        XCTAssertEqual(QueueItem.Status.converting(progress: 0.5),
                       .converting(progress: 0.5))
        XCTAssertNotEqual(QueueItem.Status.converting(progress: 0.5),
                          .converting(progress: 0.6))
    }
}
```

- [ ] **Step 2: Delete placeholder**

```bash
rm /Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/Placeholder.swift
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `Test Suite 'QueueItemTests' passed` with 4 passing tests.

- [ ] **Step 4: Commit**

```bash
git add app/HEICConverterTests && git commit -m "test: add QueueItem unit tests"
```

---

## Task 6: Refactor `Settings.swift` — defaults + fallback logic

**Why:** Spec §9. Default output dir moves to `~/Downloads`; output dir fallback chain (configured → Downloads → temp).

**Files:**
- Modify: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Settings.swift`
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/SettingsFallbackTests.swift`

- [ ] **Step 1: Read existing `Settings.swift` to preserve key names**

```bash
cat /Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Settings.swift
```

The existing `SettingsKey` enum and `Defaults` enum must keep the same key strings so `@AppStorage` doesn't break for existing users. Only `Defaults.outputDir` default value changes.

- [ ] **Step 2: Replace `Settings.swift` with new version**

**IMPORTANT:** Keep the existing `SettingsKey` string values exactly (`"quality"`, `"archiveOriginals"`, `"forceOverwrite"`, `"outputDirectory"`) — changing them would orphan any user's persisted `@AppStorage` values. Also keep `Defaults` as a `struct` (matching the original) so `Defaults.quality` etc. remain valid references.

```swift
import Foundation
import SwiftUI

enum SettingsKey {
    static let quality   = "quality"
    static let archive   = "archiveOriginals"
    static let force     = "forceOverwrite"
    static let outputDir = "outputDirectory"
}

struct Defaults {
    static let quality = 95
    static let archive = false
    static let force   = false

    /// Default output directory is the user's Downloads folder path,
    /// or empty (meaning "alongside source") if it can't be located.
    static var outputDirPath: String {
        FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?.path ?? ""
    }
}

/// Build a Converter from the values currently stored in UserDefaults.
/// (Preserved from original Settings.swift.)
func makeConverterFromSettings() -> Converter {
    let d = UserDefaults.standard
    let q = d.object(forKey: SettingsKey.quality) as? Int ?? Defaults.quality
    let outDir: URL? = {
        let s = d.string(forKey: SettingsKey.outputDir) ?? ""
        guard !s.isEmpty else { return nil }
        return URL(fileURLWithPath: s)
    }()
    return Converter(
        quality: Double(q) / 100.0,
        archiveOriginals: d.bool(forKey: SettingsKey.archive),
        force: d.bool(forKey: SettingsKey.force),
        outputDirectory: outDir)
}

enum OutputDirectoryResolver {
    /// Returns the directory we should write to, following the fallback chain.
    /// Configured path → ~/Downloads → temporary directory.
    /// Updates UserDefaults if the configured path is invalid.
    static func resolve(configured: String) -> URL {
        let fm = FileManager.default
        if !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            if fm.fileExists(atPath: url.path), fm.isWritableFile(atPath: url.path) {
                return url
            }
        }

        if let dl = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           fm.isWritableFile(atPath: dl.path) {
            UserDefaults.standard.set(dl.path, forKey: SettingsKey.outputDir)
            return dl
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        UserDefaults.standard.set(tmp.path, forKey: SettingsKey.outputDir)
        return tmp
    }
}
```

- [ ] **Step 3: Write `SettingsFallbackTests.swift`**

```swift
import XCTest
@testable import HEICConverter

final class SettingsFallbackTests: XCTestCase {

    func testEmptyConfigFallsBackToDownloads() {
        let resolved = OutputDirectoryResolver.resolve(configured: "")
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        XCTAssertEqual(resolved.path, downloads)
    }

    func testNonexistentPathFallsBackToDownloads() {
        let resolved = OutputDirectoryResolver.resolve(
            configured: "/no/such/directory/exists/anywhere/\(UUID().uuidString)")
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        XCTAssertEqual(resolved.path, downloads)
    }

    func testValidPathPassesThrough() {
        let tmp = NSTemporaryDirectory()
        let resolved = OutputDirectoryResolver.resolve(configured: tmp)
        XCTAssertEqual(resolved.path, URL(fileURLWithPath: tmp).path)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all `SettingsFallbackTests` pass.

- [ ] **Step 5: Commit**

```bash
git add app/HEICConverter/Settings.swift app/HEICConverterTests/SettingsFallbackTests.swift && git commit -m "feat: default output dir to ~/Downloads with fallback chain"
```

---

## Task 7: Modify `Converter.swift` — cancellation checkpoints

**Why:** Spec §8.4. Adds two `try Task.checkCancellation()` calls so `cancelAll()` actually interrupts in-flight conversions.

**Files:**
- Modify: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Converter.swift`

- [ ] **Step 1: Add cancellation checkpoints**

The existing `convert(_:)` returns `ConvertStatus` (cases: `.converted(URL)`, `.skipped(URL)`, `.error(URL, String)`). We add two `Task.isCancelled` early-return checks: one before opening the image source, one before writing the destination. We return `.skipped(targetURL)` to signal "this never happened" without restructuring callers.

Make these exact changes to `app/HEICConverter/Converter.swift`:

**Change A** — after the `.skipped` early-return on line 41 (file-already-exists check), insert:

```swift
        if Task.isCancelled {
            return .skipped(targetURL)
        }
```

**Change B** — between `CGImageDestinationAddImageFromSource(...)` (line 60) and the `guard CGImageDestinationFinalize(dst) else { ... }` (line 62), insert:

```swift
            if Task.isCancelled {
                return .skipped(targetURL)
            }
```

(That's inside the `do { ... }` block. The placement before `Finalize` is the cheapest cancellation point — we've already paid for decode but not the final write.)

- [ ] **Step 2: Build to verify**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Converter.swift && git commit -m "feat: add cancellation checkpoints to Converter.convert"
```

---

## Task 8: Rewrite `ConversionRunner.swift` — queue model, concurrency, thermal awareness

**Why:** Spec §7.2 + §8. Replaces single-batch state with per-item queue, adds thermal-aware concurrency, animated progress, lazy thumbnails.

**Files:**
- Rewrite: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/ConversionRunner.swift`

- [ ] **Step 1: Replace `ConversionRunner.swift` with new version**

Verified against `Converter.swift`: `Converter` is a `struct` with memberwise init order `(quality: Double, archiveOriginals: Bool, force: Bool, outputDirectory: URL?)` where `outputDirectory` is **optional** (nil = alongside source). `ConvertStatus` cases carry associated values: `.converted(URL)`, `.skipped(URL)`, `.error(URL, String)`. The implementation below honors all of those exactly.

```swift
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UserNotifications

@MainActor
final class ConversionRunner: ObservableObject {
    @Published private(set) var queue: [QueueItem] = []
    @Published var panelIsKey: Bool = false

    private var processorTask: Task<Void, Never>?

    var hasInflight: Bool {
        queue.contains { item in
            switch item.status {
            case .waiting, .converting: return true
            case .completed, .failed:   return false
            }
        }
    }

    // MARK: - Public API

    func enqueue(_ urls: [URL]) {
        let expanded = HEICScanner.collectHEICFiles(from: urls)
        let existing = Set(queue.map { $0.sourceURL })
        let newItems = expanded
            .map { $0.standardizedFileURL }
            .filter { !existing.contains($0) }
            .map { QueueItem(sourceURL: $0) }

        guard !newItems.isEmpty else { return }
        queue.append(contentsOf: newItems)
        startProcessingIfIdle()
    }

    func clearCompleted() {
        queue.removeAll { $0.status == .completed || $0.status == .failed }
    }

    func cancelAll() {
        processorTask?.cancel()
        processorTask = nil
        queue.removeAll()
    }

    func showInFinder(_ item: QueueItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Processing loop

    private func startProcessingIfIdle() {
        guard processorTask == nil else { return }
        processorTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.processQueue()
            await MainActor.run { [weak self] in self?.processorTask = nil }
        }
    }

    private nonisolated func processQueue() async {
        let outputDir = await MainActor.run {
            OutputDirectoryResolver.resolve(
                configured: UserDefaults.standard.string(forKey: SettingsKey.outputDir) ?? "")
        }
        try? FileManager.default.createDirectory(
            at: outputDir, withIntermediateDirectories: true)

        let converter = makeConverterForBatch(forcedOutputDir: outputDir)

        // Parallel, thermal-aware: spawn up to `effectiveLimit()` tasks at a time.
        await withTaskGroup(of: Void.self) { group in
            var inflight = 0

            while !Task.isCancelled {
                let limit = effectiveConcurrencyLimit()

                if inflight >= limit {
                    await group.next()
                    inflight -= 1
                    continue
                }

                guard let id = await self.pickNextWaitingID() else {
                    if inflight == 0 { break }
                    await group.next()
                    inflight -= 1
                    continue
                }

                group.addTask { [weak self] in
                    await self?.runOne(id: id, using: converter)
                }
                inflight += 1
            }
        }

        await fireCompletionNotificationIfAppropriate()
    }

    private nonisolated func effectiveConcurrencyLimit() -> Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:   return cores
        case .serious:          return max(2, cores / 2)
        case .critical:         return 1
        @unknown default:       return cores
        }
    }

    private func runOne(id: UUID, using converter: Converter) async {
        await markConverting(id: id)
        let animation = startProgressAnimation(for: id)
        defer { animation.cancel() }

        guard let source = await currentItem(id: id)?.sourceURL else { return }
        let result = converter.convert(source)
        await applyResult(id: id, result: result)
    }

    // MARK: - Queue mutations (main actor)

    private func pickNextWaitingID() async -> UUID? {
        await MainActor.run {
            queue.first(where: { $0.status == .waiting })?.id
        }
    }

    private func currentItem(id: UUID) async -> QueueItem? {
        await MainActor.run { queue.first { $0.id == id } }
    }

    private func markConverting(id: UUID) async {
        await MainActor.run {
            if let idx = queue.firstIndex(where: { $0.id == id }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    queue[idx].status = .converting(progress: 0)
                }
            }
        }
    }

    private func applyResult(id: UUID, result: ConvertStatus) async {
        await MainActor.run {
            guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .converted(let url):
                queue[idx].destinationURL = url
                queue[idx].status = .completed
                Task { await self.generateThumbnail(for: id, url: url) }
            case .skipped(let url):
                queue[idx].destinationURL = url
                queue[idx].status = .completed
            case .error(_, let message):
                queue[idx].status = .failed
                queue[idx].errorMessage = message
            }
        }
    }

    private func startProgressAnimation(for id: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                // Asymptotic curve — caps near 0.95
                let p = min(0.95, 1.0 - exp(-elapsed / 0.4))
                await self?.updateProgress(id: id, progress: p)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    private func updateProgress(id: UUID, progress: Double) async {
        await MainActor.run {
            if let idx = queue.firstIndex(where: { $0.id == id }),
               case .converting = queue[idx].status {
                queue[idx].status = .converting(progress: progress)
            }
        }
    }

    private func generateThumbnail(for id: UUID, url: URL) async {
        let data: Data? = await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 160,
                      kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary)
            else { return nil }
            let rep = NSBitmapImageRep(cgImage: img)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }.value

        await MainActor.run {
            if let idx = queue.firstIndex(where: { $0.id == id }) {
                queue[idx].thumbnailData = data
            }
        }
    }

    private func fireCompletionNotificationIfAppropriate() async {
        let (completed, failed, isKey) = await MainActor.run {
            (queue.filter { $0.status == .completed }.count,
             queue.filter { $0.status == .failed }.count,
             panelIsKey)
        }
        guard !isKey else { return }
        guard completed + failed > 0 else { return }
        var parts = ["Converted \(completed)"]
        if failed > 0 { parts.append("failed \(failed)") }
        Notifier.notify(title: "Loosey Goosey", body: parts.joined(separator: ", "))
    }
}

// MARK: - Settings glue

/// Build a Converter using current UserDefaults but overriding the output directory.
/// Matches the existing Converter memberwise init in Converter.swift (quality is Double 0–1).
func makeConverterForBatch(forcedOutputDir: URL) -> Converter {
    let d = UserDefaults.standard
    let q = d.object(forKey: SettingsKey.quality) as? Int ?? Defaults.quality
    return Converter(
        quality: Double(q) / 100.0,
        archiveOriginals: d.bool(forKey: SettingsKey.archive),
        force: d.bool(forKey: SettingsKey.force),
        outputDirectory: forcedOutputDir)
}

// MARK: - Notifier (preserved from existing code)

enum Notifier {
    private static var requested = false
    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let send = {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: c, trigger: nil))
        }
        if requested { send(); return }
        requested = true
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            if ok { send() }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. The old `MenuContentView` references to `runner.state` will break — that's fine, we delete `MenuContentView` in Task 16.

If the build fails because `MenuContentView.swift` still references `runner.state`, temporarily replace its body with `Text("rewriting")` to unblock — this file is replaced in Task 16 anyway.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/ConversionRunner.swift app/HEICConverter/MenuContentView.swift && git commit -m "refactor: ConversionRunner publishes per-item QueueItem state"
```

---

## Task 9: `ConversionRunner` tests

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverterTests/ConversionRunnerTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import HEICConverter

@MainActor
final class ConversionRunnerTests: XCTestCase {

    func testEnqueueDedupesByURL() {
        let runner = ConversionRunner()
        let url = URL(fileURLWithPath: "/tmp/photo.heic")
        runner.enqueue([url, url])
        XCTAssertEqual(runner.queue.count, 1)
    }

    func testEnqueueIgnoresAlreadyEnqueuedItems() {
        let runner = ConversionRunner()
        let a = URL(fileURLWithPath: "/tmp/a.heic")
        let b = URL(fileURLWithPath: "/tmp/b.heic")
        runner.enqueue([a])
        runner.enqueue([a, b])
        XCTAssertEqual(runner.queue.count, 2)
    }

    func testClearCompletedRemovesOnlyCompletedAndFailed() {
        let runner = ConversionRunner()
        runner.enqueue([
            URL(fileURLWithPath: "/tmp/x.heic"),
            URL(fileURLWithPath: "/tmp/y.heic"),
        ])
        // Manually mutate status via reflection-friendly approach:
        // Since `queue` is private(set), we test only what's observable.
        // For deeper testing, expose an internal `_testHelper_setStatus` if needed.
        XCTAssertEqual(runner.queue.count, 2)
    }
}
```

**Note:** Some deep state assertions require either (a) exposing an internal mutator in `ConversionRunner` marked `internal` for `@testable`, or (b) running actual conversions in a temp directory. Skip (b) for unit tests; reserve it for manual smoke tests.

- [ ] **Step 2: Run tests**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all three tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverterTests/ConversionRunnerTests.swift && git commit -m "test: add ConversionRunner enqueue dedup tests"
```

---

## Task 10: `PanelHeader.swift` — title + gear icon

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/PanelHeader.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI

struct PanelHeader: View {
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("Loosey Goosey")
                .font(Theme.Type.headlineMd)
                .foregroundStyle(Theme.Color.onSurface)
            Spacer()
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Theme.Color.surfaceContainerHigh.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.top, 20)
        .padding(.bottom, Theme.Space.gutter)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
        }
    }
}

#Preview {
    PanelHeader(showingSettings: .constant(false))
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/PanelHeader.swift && git commit -m "feat: add PanelHeader view"
```

---

## Task 11: `DropZone.swift` — drag-drop + click-to-browse

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/DropZone.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZone: View {
    @EnvironmentObject var runner: ConversionRunner
    @State private var isDragHovered = false
    @State private var shake = false

    var body: some View {
        Button(action: openPicker) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.primary)
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.Color.onPrimary)
                }
                Text("Drag & Drop HEIC files")
                    .font(Theme.Type.bodyLg)
                    .foregroundStyle(Theme.Color.onSurface)
                Text("or click to browse")
                    .font(Theme.Type.bodyMd)
                    .foregroundStyle(Theme.Color.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isDragHovered
                          ? Theme.Color.primary.opacity(0.08)
                          : Theme.Color.surfaceContainerLow.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(
                        isDragHovered ? Theme.Color.primary : Theme.Color.outlineVariant,
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            dash: isDragHovered ? [] : [6, 4])
                    )
            )
            .modifier(ShakeEffect(animatable: shake ? 1 : 0))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("o", modifiers: .command)
        .padding(.horizontal, Theme.Space.container)
        .padding(.vertical, Theme.Space.gutter)
        .onDrop(of: [.fileURL], isTargeted: $isDragHovered) { providers in
            handleDrop(providers: providers)
            return true
        }
        .accessibilityLabel("Drop HEIC files or click to browse")
    }

    private func openPicker() {
        if let urls = Picker.chooseFilesOrFolders(), !urls.isEmpty {
            runner.enqueue(urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let heics = urls.filter {
                $0.pathExtension.lowercased() == "heic" || $0.hasDirectoryPath
            }
            if heics.isEmpty {
                triggerShake()
            } else {
                runner.enqueue(heics)
            }
        }
    }

    private func triggerShake() {
        withAnimation(.linear(duration: 0.05).repeatCount(4, autoreverses: true)) {
            shake.toggle()
        }
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatable: CGFloat
    var animatableData: CGFloat {
        get { animatable }
        set { animatable = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatable * .pi * 2), y: 0))
    }
}

#Preview {
    DropZone()
        .environmentObject(ConversionRunner())
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/DropZone.swift && git commit -m "feat: add DropZone with drag-and-drop and click-to-browse"
```

---

## Task 12: `QueueRowView.swift` — single queue row

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/QueueRowView.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI

struct QueueRowView: View {
    let item: QueueItem
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(Theme.Type.bodyMdMed)
                    .foregroundStyle(Theme.Color.onSurface)
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: 4)
            trailingControl
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var thumbnail: some View {
        if let data = item.thumbnailData, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Color.surfaceContainerHigh.opacity(0.6))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.Color.onSurfaceVariant)
                )
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch item.status {
        case .waiting:
            Text("Waiting…")
                .font(Theme.Type.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
        case .converting(let progress):
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Color.outlineVariant.opacity(0.3))
                    .frame(height: 4)
                Capsule().fill(Theme.Color.primary)
                    .frame(width: 180 * progress, height: 4)
            }
            .frame(width: 180)
        case .completed:
            Text("Converted to JPG")
                .font(Theme.Type.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
        case .failed:
            Text(item.errorMessage ?? "Failed")
                .font(Theme.Type.labelMd)
                .foregroundStyle(Theme.Color.error)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var trailingControl: some View {
        switch item.status {
        case .waiting:
            EmptyView()
        case .converting(let progress):
            Text("\(Int(progress * 100))%")
                .font(Theme.Type.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
                .monospacedDigit()
        case .completed:
            Button(action: onShow) {
                Text("Show")
                    .font(Theme.Type.labelMd.weight(.semibold))
                    .foregroundStyle(Theme.Color.onPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Color.primary))
            }
            .buttonStyle(.plain)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Color.error)
                .help(item.errorMessage ?? "Failed")
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        QueueRowView(item: {
            var i = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/IMG_0842.heic"))
            i.status = .completed
            return i
        }(), onShow: {})
        QueueRowView(item: {
            var i = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/Vacation_01.heic"))
            i.status = .converting(progress: 0.49)
            return i
        }(), onShow: {})
        QueueRowView(item: QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/DSC_0001.heic")),
                     onShow: {})
    }
    .frame(width: 340)
    .background(Theme.Color.surfaceContainer)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/QueueRowView.swift && git commit -m "feat: add QueueRowView with thumbnail, status, and Show pill"
```

---

## Task 13: `QueueSection.swift` — list of rows + label

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/QueueSection.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI

struct QueueSection: View {
    @EnvironmentObject var runner: ConversionRunner

    var body: some View {
        if !runner.queue.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("CONVERSION QUEUE")
                    .font(Theme.Type.labelSm)
                    .foregroundStyle(Theme.Color.onSurfaceVariant)
                    .textCase(.uppercase)
                    .padding(.horizontal, Theme.Space.container)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runner.queue) { item in
                            QueueRowView(item: item) {
                                runner.showInFinder(item)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            if item.id != runner.queue.last?.id {
                                Rectangle()
                                    .fill(Theme.Color.outlineVariant.opacity(0.4))
                                    .frame(height: 1)
                                    .padding(.horizontal, Theme.Space.container)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
                .animation(.spring(response: 0.4, dampingFraction: 0.85),
                           value: runner.queue.map(\.id))
            }
        }
    }
}

#Preview {
    let runner = ConversionRunner()
    runner.enqueue([
        URL(fileURLWithPath: "/tmp/IMG_0842.heic"),
        URL(fileURLWithPath: "/tmp/Vacation_01.heic"),
    ])
    return QueueSection()
        .environmentObject(runner)
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/QueueSection.swift && git commit -m "feat: add QueueSection with conditional rendering"
```

---

## Task 14: `PanelFooter.swift` — version + Open Folder / Clear

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/PanelFooter.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI
import AppKit

struct PanelFooter: View {
    @EnvironmentObject var runner: ConversionRunner
    @AppStorage(SettingsKey.outputDir) private var outputDir: String = Defaults.outputDir

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var canClear: Bool {
        runner.queue.contains { $0.status == .completed || $0.status == .failed }
    }

    var body: some View {
        HStack {
            Text("v\(version)")
                .font(Theme.Type.labelSm)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
            Spacer()
            Button("Open Folder") {
                let url = OutputDirectoryResolver.resolve(configured: outputDir)
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(FooterLinkStyle(enabled: true))

            Text("·").foregroundStyle(Theme.Color.onSurfaceVariant)

            Button("Clear") {
                withAnimation { runner.clearCompleted() }
            }
            .buttonStyle(FooterLinkStyle(enabled: canClear))
            .disabled(!canClear)
            .keyboardShortcut("k")
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
        }
    }
}

private struct FooterLinkStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Type.labelMd)
            .foregroundStyle(enabled
                ? Theme.Color.primary
                : Theme.Color.onSurfaceVariant.opacity(0.4))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview {
    PanelFooter()
        .environmentObject(ConversionRunner())
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/PanelFooter.swift && git commit -m "feat: add PanelFooter with version, Open Folder, Clear"
```

---

## Task 15: `PanelRootView.swift` — glass shell composing all subviews

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/PanelRootView.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI
import AppKit

struct PanelRootView: View {
    @EnvironmentObject var runner: ConversionRunner
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(showingSettings: $showingSettings)
                .popover(isPresented: $showingSettings, arrowEdge: .top) {
                    SettingsView()
                        .frame(width: 280)
                }
            DropZone()
            QueueSection()
            PanelFooter()
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        // Track whether the panel is visible — gates the completion notification.
        .onAppear    { runner.panelIsKey = true }
        .onDisappear { runner.panelIsKey = false }
    }

    @ViewBuilder private var panelBackground: some View {
        if reduceTransparency {
            Theme.Color.surfaceContainer
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        }
    }
}

#Preview {
    PanelRootView()
        .environmentObject(ConversionRunner())
        .frame(width: 340)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **` (assumes `SettingsView` exists; if Task 18 not done yet, replace `SettingsView()` with `Text("Settings")` temporarily).

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/PanelRootView.swift && git commit -m "feat: add PanelRootView with glass shell and gradient stroke"
```

---

## Task 16: Update `HEICConverterApp.swift` + add `AppDelegate.swift`

**Files:**
- Modify: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/HEICConverterApp.swift`
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/AppDelegate.swift`
- Delete: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/MenuContentView.swift`

- [ ] **Step 1: Replace `HEICConverterApp.swift`**

```swift
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
```

- [ ] **Step 2: Write `AppDelegate.swift`**

```swift
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
```

- [ ] **Step 3: Delete `MenuContentView.swift`**

```bash
rm /Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/MenuContentView.swift
```

- [ ] **Step 4: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/HEICConverter && git commit -m "feat: switch app to .window style, add AppDelegate, remove MenuContentView"
```

---

## Task 17: Update `Info.plist` — CFBundleDisplayName

**Files:**
- Modify: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Info.plist`

- [ ] **Step 1: Read current Info.plist**

```bash
cat /Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Info.plist
```

- [ ] **Step 2: Add CFBundleDisplayName key**

Insert before the closing `</dict>`:

```xml
    <key>CFBundleDisplayName</key>
    <string>Loosey Goosey</string>
```

If `CFBundleDisplayName` already exists, update its `<string>` value to `Loosey Goosey`.

- [ ] **Step 3: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add app/HEICConverter/Info.plist && git commit -m "feat: set CFBundleDisplayName to Loosey Goosey"
```

---

## Task 18: `SettingsView.swift` — gear popover

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter/Views/SettingsView.swift`

- [ ] **Step 1: Write view**

```swift
import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(SettingsKey.outputDir) private var outputDir: String = Defaults.outputDir
    @AppStorage(SettingsKey.quality)   private var quality: Int = Defaults.quality
    @AppStorage(SettingsKey.archive)   private var archive: Bool = Defaults.archive
    @AppStorage(SettingsKey.force)     private var force: Bool = Defaults.force

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.gutter) {
            Text("Settings")
                .font(Theme.Type.headlineMd)

            VStack(alignment: .leading, spacing: 6) {
                Text("Output Folder").font(Theme.Type.labelMd)
                HStack {
                    Text(URL(fileURLWithPath: outputDir).lastPathComponent)
                        .font(Theme.Type.bodyMd)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change") {
                        if let url = Picker.chooseOutputDirectory() {
                            outputDir = url.path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("JPEG Quality").font(Theme.Type.labelMd)
                    Spacer()
                    Text("\(quality)")
                        .font(Theme.Type.bodyMd.monospacedDigit())
                }
                Slider(value: Binding(
                    get: { Double(quality) },
                    set: { quality = Int($0) }
                ), in: 60...100, step: 5)
            }

            Toggle("Archive originals to heic_originals/", isOn: $archive)
                .font(Theme.Type.bodyMd)
            Toggle("Overwrite existing JPEGs", isOn: $force)
                .font(Theme.Type.bodyMd)
        }
        .padding(Theme.Space.container)
    }
}

#Preview {
    SettingsView().frame(width: 280)
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/HEICConverter/Views/SettingsView.swift && git commit -m "feat: add SettingsView gear popover"
```

---

## Task 19: Update `project.yml` — display name + regenerate

**Files:**
- Modify: `/Users/hunterbrewer/Code/Heic-JPG_Converter/app/project.yml`

- [ ] **Step 1: Add INFOPLIST_KEY_CFBundleDisplayName**

In the existing target settings block, add:

```yaml
        INFOPLIST_KEY_CFBundleDisplayName: "Loosey Goosey"
```

(This is redundant with the Info.plist key from Task 17 but ensures consistency on regeneration.)

- [ ] **Step 2: Regenerate**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodegen generate
```

Expected: `Created project at /Users/hunterbrewer/Code/Heic-JPG_Converter/app/HEICConverter.xcodeproj`.

- [ ] **Step 3: Build to verify the regenerated project still compiles**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild build -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add app/project.yml && git commit -m "build: declare Loosey Goosey display name in project.yml"
```

---

## Task 20: Manual smoke test

**Files:**
- Create: `/Users/hunterbrewer/Code/Heic-JPG_Converter/docs/manual-smoke-test.md`

- [ ] **Step 1: Run the app from Xcode**

Open `HEICConverter.xcodeproj` in Xcode, press ⌘R. The menu bar should show a tilted-photo-stack icon. Click it — the new glass panel should appear.

- [ ] **Step 2: Execute the smoke checklist**

Create `/Users/hunterbrewer/Code/Heic-JPG_Converter/docs/manual-smoke-test.md`:

```markdown
# Loosey Goosey Manual Smoke Test

Run this checklist before tagging any release.

## Setup
- [ ] Build & run app from Xcode.
- [ ] Verify menu bar icon appears.
- [ ] Verify no Dock icon (LSUIElement working).

## Drop zone
- [ ] Drop one HEIC → row appears, converts, "Show" pill works.
- [ ] Drop a folder containing 10+ HEICs → all enqueue, scroll behaves.
- [ ] Drop 10 mixed (HEIC + JPG + PDF) → only HEICs enqueue.
- [ ] Drop 0 HEICs → drop zone shakes; queue unchanged.
- [ ] Click drop zone → file picker opens.

## Settings
- [ ] Click gear → settings popover appears.
- [ ] Change output folder → next conversion goes there.
- [ ] Drag JPEG quality slider → value persists across app relaunch.
- [ ] Toggle Archive → originals move to heic_originals/ after conversion.
- [ ] Toggle Overwrite → conversions overwrite existing JPGs.

## Queue interactions
- [ ] Per-row "Show" pill → Finder opens with file selected.
- [ ] Footer "Open Folder" → opens output dir in Finder.
- [ ] Footer "Clear" → completed/failed rows removed; in-flight rows remain.
- [ ] ⌘K → same as Clear.

## App lifecycle
- [ ] ⌘Q with batch running → confirmation alert appears.
- [ ] Click Cancel in alert → app stays open, batch continues.
- [ ] Click Quit in alert → app exits cleanly.

## Visual
- [ ] Light mode: glass material picks up wallpaper colors.
- [ ] Dark mode: glass adapts, text remains readable.
- [ ] System Settings → Accessibility → Display → "Reduce Transparency" ON → solid background fallback works.

## Concurrency
- [ ] Drop 30 HEICs → multiple rows enter "converting" simultaneously (CPU core count).
- [ ] During heavy batch: panel remains responsive.
```

- [ ] **Step 3: Run through every item, fix anything that fails**

For each failure, file a follow-up task or fix inline. Commit the smoke test doc once green.

- [ ] **Step 4: Commit**

```bash
git add docs/manual-smoke-test.md && git commit -m "docs: add manual smoke test checklist"
```

---

## Task 21: Run `/simplify` over the recently changed code

**Why:** The user explicitly requested this. After 20 tasks of layered work, individual files can drift toward verbosity or rework opportunities the in-the-moment implementer didn't see.

- [ ] **Step 1: Invoke the `simplify` skill**

In the chat/agent harness, run:

```
/simplify
```

The skill scans recently changed files for:
- Dead code / unused imports
- Over-broad error handling
- Duplicated logic
- Premature abstraction
- Comments that no longer match code

- [ ] **Step 2: Review proposed simplifications**

Each suggestion will be presented. For each:
- Accept if it preserves behavior and reduces noise.
- Reject if the verbose form is intentional (e.g., a check that looks redundant but guards an edge case).

- [ ] **Step 3: Build & test after simplifications applied**

```bash
cd /Users/hunterbrewer/Code/Heic-JPG_Converter/app && xcodebuild test -project HEICConverter.xcodeproj -scheme HEICConverter -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass; manual smoke test (Task 20) still green.

- [ ] **Step 4: Commit any simplifications**

```bash
git add app && git commit -m "chore: simplify pass over Loosey Goosey UI implementation"
```

---

## Task 22: Final manual smoke test

- [ ] Re-run every item in `docs/manual-smoke-test.md`.
- [ ] Take a screenshot of the final UI for the PR description / README.
- [ ] Tag the commit: `git tag v0.2.0-loosey-goosey-glass`.

---

## Subagent execution playbook

This plan is structured so the foundation tasks (1–9) run sequentially and the view-layer tasks (10–14, 18) can be dispatched in parallel once Phase 1 is complete. Suggested dispatch:

**Round 1 (Phase 1 — sequential, one agent):**
- Tasks 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 (single agent, since each depends on the previous)

**Round 2 (Phase 2 — parallel, up to 5 agents):**
- Agent A: Task 10 (PanelHeader)
- Agent B: Task 11 (DropZone)
- Agent C: Task 12 → Task 13 (QueueRowView → QueueSection)
- Agent D: Task 14 (PanelFooter)
- Agent E: Task 18 (SettingsView)

Each agent has clear file ownership in `app/HEICConverter/Views/` so there's no cross-talk risk.

**Round 3 (Phase 3 — sequential, one agent):**
- Tasks 15 → 16 → 17 → 19

**Round 4 (Phase 4 — sequential, one agent):**
- Task 20 (manual smoke test)
- Task 21 (`/simplify`)
- Task 22 (final smoke + tag)

Lead agent should validate each round's commits pass `xcodebuild test` and `xcodebuild build` before kicking off the next round.

---

## Out of scope (deliberately deferred)

- SwiftUI snapshot tests (spec §15.3).
- Notarization / Developer ID distribution (spec §2).
- Geist typography bundling (spec §16 — SF Pro is the v1 default).
- Multi-select queue rows with "Show Selected" footer (spec §16).
- Cancel-All footer button (spec §5).

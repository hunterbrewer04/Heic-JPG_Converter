# Loosey Goosey — Glass UI Redesign

**Status:** Approved design, ready for implementation planning
**Date:** 2026-05-14
**Reference:** `stitch_blue_heic_converter/screen.png` + `stitch_blue_heic_converter/DESIGN.md` (Stitch-generated reference)
**Scope:** Replace the existing native menu of the macOS `HEICConverter` menu bar app with a custom SwiftUI panel matching a "Glass & Smooth" design system. App is renamed to **Loosey Goosey** at the user-facing level.

---

## 1. Goals

- Replace native `MenuBarExtra` menu items with a custom SwiftUI panel that has glassmorphism, drag-and-drop file input, a live conversion queue with per-file progress, and a settings popover.
- Match the reference design closely, with intentional substitutions where macOS conventions differ from the (web-derived) reference.
- Preserve all current functionality (EXIF/GPS retention, quality control, archive/overwrite settings, parallel conversion, completion notification).
- Keep the implementation surface small enough to be maintained by one developer.

## 2. Non-goals

- Becoming a standalone windowed app. App remains a menu bar agent (`LSUIElement = YES`).
- Drag-out to other apps, Spotlight-style command palette, batch tagging, EXIF editing, format support beyond HEIC→JPEG.
- Cross-platform support. macOS 13+ only, Apple Silicon and Intel.
- Notarization / distribution. Local-only build for now.
- Premium tier / monetization. The "v1.0.4 Premium" badge in the reference is dropped.

## 3. Branding

- **Display name (`CFBundleDisplayName`):** `Loosey Goosey`
- **Panel header text:** `Loosey Goosey`
- **Menu bar tooltip:** `Loosey Goosey`
- **Bundle identifier:** `com.hunterbrewer.heicconverter` *(unchanged — avoids signing re-trip)*
- **Internal target/scheme name:** `HEICConverter` *(unchanged — avoids Xcode project regeneration)*
- **Menu bar `systemImage`:** `photo.stack` *(replaces current tilted-photo glyph)*

## 4. Architecture

### 4.1 File layout

```
app/HEICConverter/
├── HEICConverterApp.swift         # MODIFIED: .window style, panel size, name
├── MenuContentView.swift          # REPLACED entirely → PanelRootView container
├── ConversionRunner.swift         # MODIFIED: per-item state, thermal-aware concurrency
├── Converter.swift                # MODIFIED: add cooperative cancellation checkpoints
├── Scanner.swift                  # UNCHANGED
├── Picker.swift                   # UNCHANGED (still used by click-to-browse)
├── Settings.swift                 # MODIFIED: default outputDir = ~/Downloads
├── Info.plist                     # MODIFIED: CFBundleDisplayName, accessibility keys
├── Theme.swift                    # NEW: color & typography tokens from DESIGN.md
├── VisualEffectView.swift         # NEW: NSViewRepresentable wrapping NSVisualEffectView
├── QueueItem.swift                # NEW: row model
└── Views/
    ├── PanelRootView.swift        # NEW: top-level VStack composition + glass shell
    ├── PanelHeader.swift          # NEW: title + gear icon
    ├── DropZone.swift             # NEW: dashed area, drop + click handlers
    ├── QueueSection.swift         # NEW: "CONVERSION QUEUE" label + list
    ├── QueueRowView.swift         # NEW: per-file row
    ├── PanelFooter.swift          # NEW: version + Open Folder / Clear
    └── SettingsView.swift         # NEW: gear popover contents
```

### 4.2 Layering

- **Pure SwiftUI** for all views, theming, and the queue list.
- **One AppKit bridge:** `VisualEffectView` wraps `NSVisualEffectView` via `NSViewRepresentable` — the only AppKit dependency in the project. Used for the glass background to get true wallpaper vibrancy via `.behindWindow` blending mode and `.hudWindow` material.
- **Model layer (`ConversionRunner` + `QueueItem`)** is `@MainActor` and `ObservableObject`. UI views observe `runner.queue` and re-render via SwiftUI diffing.

## 5. Container & visual shell

### 5.1 `MenuBarExtra` configuration

```swift
MenuBarExtra("Loosey Goosey", systemImage: "photo.stack") {
    PanelRootView()
        .environmentObject(runner)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
}
.menuBarExtraStyle(.window)
```

- **Width:** fixed at 340pt.
- **Height:** dynamic; grows with queue length up to a max (~520pt) after which the queue list scrolls.
- **Empty-queue height:** ~280pt (header + drop zone + footer only).

### 5.2 Glass background

The panel root applies, in order:

1. Background: `VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)`
2. Clip shape: `RoundedRectangle(cornerRadius: 24)`
3. Overlay: 1pt `LinearGradient` stroke from `white@35%` (top-leading) → `white@5%` (bottom-trailing). This is the "physical glass edge" specified in `DESIGN.md`.

### 5.3 Reduce Transparency fallback

When `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` is `true`, the panel substitutes `VisualEffectView` with `Color(Theme.surfaceContainer)` (solid). All other layout/typography is identical.

## 6. Layout & components

### 6.1 `PanelHeader`

- Padding: 24pt sides, 20pt top, 16pt bottom.
- Title `Loosey Goosey` in `Theme.Type.headlineMd` (SF Pro 18pt, weight `.semibold`, -0.01em tracking).
- Trailing: 28pt circular glass button with `gearshape` SF Symbol. Tapping toggles a SwiftUI `.popover` containing `SettingsView`.
- Bottom edge: 1pt divider, `Theme.Color.outlineVariant` at 50% opacity.

### 6.2 `DropZone`

- Container: `RoundedRectangle(cornerRadius: 16)` filled with `Theme.Color.surfaceContainerLow.opacity(0.5)`.
- Stroke: dashed (`StrokeStyle(lineWidth: 1.5, dash: [6, 4])`) using `Theme.Color.outlineVariant`. On drag-hover or drag-targeted, stroke becomes solid `Theme.Color.primary`.
- Interior (centered VStack, 12pt spacing):
  - 44×44pt `Circle` filled `Theme.Color.primary` containing `Image(systemName: "doc.fill")` in white 18pt.
  - Text "Drag & Drop HEIC files" in `Theme.Type.bodyLg`.
  - Text "or click to browse" in `Theme.Type.bodyMd`, color `Theme.Color.onSurfaceVariant`.
- Tap target: entire container is a `Button` that calls `Picker.chooseFilesOrFolders()` and pipes results to `runner.enqueue(_:)`.
- Drop handler: `.onDrop(of: [.fileURL], isTargeted: $isDragHovered) { providers in … }` — extracts URLs, validates extensions, calls `runner.enqueue(_:)`.

### 6.3 `QueueSection`

- Conditional: renders only when `runner.queue` is non-empty.
- Top: small label "CONVERSION QUEUE" in `Theme.Type.labelSm` (10pt, weight `.semibold`, +0.05em tracking, uppercase), color `Theme.Color.onSurfaceVariant`.
- Body: `ScrollView { LazyVStack { ForEach(queue) { QueueRowView(item: $0) } } }` with a max-height of ~280pt before scrolling.
- Row spacing: rows separated by 1pt dividers, `Theme.Color.outlineVariant.opacity(0.4)`.

### 6.4 `QueueRowView`

Three slots, horizontal layout:

| Slot | Width | Content |
|---|---|---|
| Leading | 40pt | Thumbnail `Image` (when `.completed`, lazily generated from output JPEG at 80×80px @2x), else `Image(systemName: "photo")` in `Theme.Color.onSurfaceVariant`. Clipped to `RoundedRectangle(cornerRadius: 8)`. |
| Center | flex | **Top:** `item.filename` in `Theme.Type.bodyMd` weight `.medium`. **Bottom (varies by status):** `.waiting` → "Waiting…"; `.converting(progress)` → 4pt-tall progress bar (track = `Theme.Color.outlineVariant.opacity(0.3)`, fill = `Theme.Color.primary`, animated); `.completed` → "Converted to JPG"; `.failed` → error message truncated, in `Theme.Color.error`. All in `Theme.Type.labelMd`, color `Theme.Color.onSurfaceVariant` (except failed which uses error red). |
| Trailing | auto | `.waiting` → nothing. `.converting(p)` → `"\(Int(p*100))%"`. `.completed` → "Show" pill button. `.failed` → red ⚠️ icon with `.help(errorMessage)` tooltip. |

"Show" pill: `Capsule()` fill `Theme.Color.primary`, white text "Show" in `Theme.Type.labelMd` weight `.semibold`, 12pt vertical / 14pt horizontal padding. Hover: brightness +8%. Press: scale 0.98 spring. Tap: `NSWorkspace.shared.activateFileViewerSelecting([item.destinationURL])`.

### 6.5 `PanelFooter`

- Padding: 24pt sides, 14pt top/bottom.
- Top edge: 1pt divider, `Theme.Color.outlineVariant.opacity(0.5)`.
- Layout: `HStack` with `Spacer` between groups.
- **Leading:** Version label `"v\(MARKETING_VERSION)"` in `Theme.Type.labelSm`, `Theme.Color.onSurfaceVariant`.
- **Trailing:** Two text-link buttons separated by a middle dot:
  - **Open Folder** — opens `Settings.outputDir` (or fallback) in Finder via `NSWorkspace.shared.open(_:)`. Always enabled.
  - **Clear** — calls `runner.clearCompleted()`. Disabled (40% opacity, non-interactive) when queue contains no `.completed` or `.failed` items.

## 7. State model

### 7.1 `QueueItem`

```swift
struct QueueItem: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var destinationURL: URL?
    var status: Status
    var thumbnailData: Data?
    var errorMessage: String?

    enum Status: Equatable {
        case waiting
        case converting(progress: Double)
        case completed
        case failed
    }

    var filename: String { sourceURL.lastPathComponent }
}
```

`Equatable + Identifiable` enables SwiftUI's per-row diffing animation.

### 7.2 `ConversionRunner` (refactored)

```swift
@MainActor
final class ConversionRunner: ObservableObject {
    @Published private(set) var queue: [QueueItem] = []

    func enqueue(_ urls: [URL])
    func clearCompleted()
    func cancelAll()
    func showInFinder(_ item: QueueItem)
}
```

`enqueue(_:)`:
1. Expand any directories via `HEICScanner.collectHEICFiles(from:)`.
2. Filter to `.heic` extension (case-insensitive).
3. Dedupe against existing queue via `sourceURL.standardizedFileURL`.
4. Append new items with `.waiting` status.
5. Trigger processing loop if not already running.

`clearCompleted()`: removes `.completed` and `.failed` items only; in-flight items remain.

`cancelAll()`: cancels in-flight `Task`s (cooperative cancellation propagates), removes all items, fires no notification.

`showInFinder(_:)`: convenience wrapper for `NSWorkspace.shared.activateFileViewerSelecting([destinationURL])`.

## 8. Concurrency

### 8.1 Base model

- A single `Task.detached(priority: .userInitiated)` drives the queue loop.
- Inside it, `withTaskGroup(of: ConvertResult.self)` runs up to `effectiveConcurrent` conversions in parallel.
- Each spawned task picks a `.waiting` item, marks `.converting(progress: 0)`, runs `Converter.convert(_:progressHandler:)`, marks `.completed` (or `.failed`).

### 8.2 `effectiveConcurrent`

```swift
let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount
let effectiveConcurrent: Int
switch ProcessInfo.processInfo.thermalState {
case .nominal, .fair:   effectiveConcurrent = maxConcurrent
case .serious:          effectiveConcurrent = max(2, maxConcurrent / 2)
case .critical:         effectiveConcurrent = 1
@unknown default:       effectiveConcurrent = maxConcurrent
}
```

Recomputed at the start of each new batch and on `thermalStateDidChangeNotification` (the latter doesn't kill in-flight tasks; it just changes the cap for the next pickup).

### 8.3 Animated progress (Option α)

`Converter.convert(_:progressHandler:)` doesn't actually know its own progress (ImageIO is synchronous). Per-item progress is **animated** rather than measured:

- On `.converting` entry, spawn a `Task` that updates `progress` toward 1.0 via an easing curve calibrated for typical durations (~600ms for ~10MB HEIC).
- Curve asymptotes near 0.95 if conversion takes longer than expected.
- When `Converter.convert` returns successfully, force `progress = 1.0` for one frame, then transition to `.completed`.
- On `.failed`, the animation task is canceled; progress is irrelevant.

### 8.4 Cancellation

`Converter.convert(_:)` adds `try Task.checkCancellation()` between the decode step (`CGImageSourceCreateImageAtIndex`) and the write step (`CGImageDestinationFinalize`). This makes `cancelAll()` responsive within ~one file's conversion time at most.

### 8.5 Memory bounds

`CGImageSource` decoded frames are held in RAM during write. Bounded concurrency caps memory: at most `effectiveConcurrent × decoded_frame_size` is held at any moment.

## 9. Settings

### 9.1 Storage

All `@AppStorage`-backed (existing `Settings.swift` keys preserved):

- `outputDir: String` — default changes from `""` (alongside source) to `FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""`.
- `quality: Int` — default 95.
- `archive: Bool` — default false.
- `force: Bool` — default false.

### 9.2 `SettingsView`

Presented as a SwiftUI `.popover` anchored to the gear button in the header. Width 280pt, dynamic height.

Sections:
1. **Output Folder** — path label + "Change" button. Clicking opens `NSOpenPanel` for directory selection.
2. **JPEG Quality** — `Slider` 60–100, step 5, value label trailing.
3. **Archive originals** — `Toggle`.
4. **Overwrite existing JPEGs** — `Toggle`.

Same glass material as the main panel, slightly smaller corner radius (16pt). Closes on outside click (SwiftUI default popover behavior).

### 9.3 Output dir fallback

At conversion start:
1. If `outputDir` is non-empty and exists and is writable → use it.
2. If empty or missing → fall back to `~/Downloads`, update `outputDir` in `UserDefaults` silently.
3. If `~/Downloads` is also unwritable → fall back to `NSTemporaryDirectory()` and surface a one-time warning in the panel.

## 10. Theme

`Theme.swift` defines two nested enums of static let constants:

```swift
enum Theme {
    enum Color {
        static let surface: SwiftUI.Color = …
        static let primary: SwiftUI.Color = …
        // …all DESIGN.md tokens mapped
    }
    enum Typography {
        static let headlineLg = Font.system(size: 24, weight: .semibold)
            .tracking(-0.02 * 24)
        // …all DESIGN.md sizes mapped using SF Pro (.system)
    }
}
```

Light/dark color variants:
- Most tokens use SwiftUI's automatic light/dark behavior via `Color(NSColor.namedColor)` or semi-transparent overlays.
- Tokens that need explicit dark mode variants (text colors, primary blue) use a small `Color(light:dark:)` initializer (added as a `Color` extension).

## 11. Interactions

| Event | Handler |
|---|---|
| Click drop zone | `Picker.chooseFilesOrFolders()` → `runner.enqueue` |
| Drop files on drop zone | `.onDrop` → URL extraction → `runner.enqueue` |
| Drop folder | Recursive `HEICScanner` discovery → `runner.enqueue` |
| Drop non-HEIC files | Filter to HEIC, brief shake animation if zero remain |
| Click gear | Toggle `SettingsView` popover |
| Click "Show" pill | `runner.showInFinder(item)` |
| Click "Open Folder" | `NSWorkspace.shared.open(outputDirURL)` |
| Click "Clear" | `runner.clearCompleted()` |
| `⌘O` | Equivalent to clicking drop zone |
| `⌘,` | Equivalent to clicking gear |
| `⌘K` | Equivalent to clicking Clear |
| `⌘W` | Dismiss the popover panel (handled implicitly by `MenuBarExtra(.window)`) |
| `⌘Q` | Quit (with confirmation if batch in flight — see §13.3) |

## 12. Animations

- **Item insertion:** slide-in from top-of-list + fade. ~300ms ease-out.
- **Status change:** cross-fade trailing slot content. ~200ms.
- **Item removal (Clear):** slide-up + fade. ~250ms.
- **Panel height resize:** SwiftUI spring (`.spring(response: 0.4, dampingFraction: 0.85)`).
- **Drop hover:** dashed→solid border, background tint. ~150ms ease-in-out.
- **Drop rejection (no HEICs):** ±6pt horizontal keyframe shake over 200ms.
- **Reduce Motion respect:** when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true, all of the above become instant (`.transition(.identity)`, no animation modifiers).

## 13. Error handling

### 13.1 Per-item failures

| Cause | Behavior |
|---|---|
| Unreadable / corrupt HEIC | Item → `.failed` with message from `Converter` |
| Source deleted mid-conversion | Item → `.failed`, queue continues |
| Disk full | Item → `.failed`, queue continues (subsequent items likely also fail) |
| Permission denied (TCC) | Item → `.failed` with text mentioning System Settings. macOS will have already shown its native prompt before this state. |

### 13.2 Output dir issues

Handled per §9.3.

### 13.3 App quit with batch running

The current `HEICConverterApp.swift` uses the pure SwiftUI App lifecycle (no `NSApplicationDelegate`). We add an `NSApplicationDelegateAdaptor` to the App struct and a small `AppDelegate` class. The delegate's `applicationShouldTerminate(_:)` returns `.terminateLater` when `runner` reports in-flight work, presents an `NSAlert` ("Conversions in progress. Quit anyway?" — default "Cancel", alternate "Quit"). On "Quit" → `runner.cancelAll()` → `NSApp.reply(toApplicationShouldTerminate: true)`. On "Cancel" → `reply(toApplicationShouldTerminate: false)`.

### 13.4 Final notification

Fires only when:
1. `queue` has no `.waiting` or `.converting` items, AND
2. The panel is not currently the key window.

Body summarizes outcome: `"Converted N, skipped M, failed K"` (omits zero-count clauses).

## 14. Accessibility

- All buttons: `.accessibilityLabel` text.
- Drop zone: `.accessibilityHint("Drop HEIC files or press Return to open file picker")`.
- Queue rows: `.accessibilityLabel("\(filename), \(statusText)")`.
- **Reduce Transparency** → opaque background fallback (§5.3).
- **Increase Contrast** → divider/stroke opacities raised to 80%.
- **Reduce Motion** → animation modifiers replaced with `.transition(.identity)` (§12).
- Dark mode supported automatically via theme (§10).

## 15. Testing

### 15.1 Unit tests

`HEICConverterTests/` target (new), tests cover:

1. `QueueItem.Status` equality and transitions.
2. `ConversionRunner.enqueue` deduplication by URL.
3. `ConversionRunner.enqueue` folder expansion and HEIC filtering.
4. Settings fallback when `outputDir` is missing → falls back to `~/Downloads`.
5. Settings fallback when `~/Downloads` is unwritable → falls back to `NSTemporaryDirectory()`.

### 15.2 Manual smoke checklist

A markdown checklist committed to `docs/manual-smoke-test.md`, run before each tag:

- Drop 1 HEIC → completes, "Show" pill works.
- Drop folder of 50 HEICs → all complete, queue scrolls correctly.
- Drop 10 mixed (HEIC + JPG + PDF) → only HEICs added.
- Drop 0 HEICs → drop zone shakes, no items added.
- Toggle every setting → quit → relaunch → settings persisted.
- Force a failure (rename source mid-conversion) → row goes red, others continue.
- ⌘Q with batch running → confirmation dialog appears.
- Run in Light mode, Dark mode, and Reduce Transparency mode → all readable.
- Run on machine with `thermalState = .critical` (simulate via `xcrun simctl` or run a CPU stress test) → concurrency drops to 1.

### 15.3 Out of scope

- No SwiftUI snapshot tests in v1 (brittle; visual surface will evolve).
- No UI automation tests (XCUITest); manual checklist is sufficient.

## 16. Open questions / future work

- **Cancel All button:** Not surfaced in footer for v1. Spec section 5 explicitly chose not to add it. If user behavior shows demand, add as a third footer link gated on `runner.hasInflight`.
- **Multi-select reveal in Finder:** Per-row Show is the only reveal in v1. A future v2 may add row checkboxes + "Show Selected" footer action — but the design has converged on a single output folder, which makes multi-select largely redundant.
- **Notarization & distribution:** Out of scope. Add when the app is ready to share beyond the developer's own Mac.
- **Geist typography:** Spec uses SF Pro for v1. Geist remains an option for a follow-up polish pass (`docs/specs/future-geist-typography.md` if ever needed).

## 17. Migration plan

A single feature branch off `main`. Changes are mostly additive (new files); only `MenuContentView.swift` is replaced and `ConversionRunner.swift` is significantly refactored. No DB or persistent-data migration — `@AppStorage` keys are reused with the same names.

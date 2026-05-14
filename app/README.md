# HEIC Converter — macOS Menu Bar App

A native SwiftUI / `MenuBarExtra` rewrite of the Python CLI. Lives in the
macOS top bar; click → pick a folder or some HEIC files → JPEGs land next to
the originals (or in a custom output folder). EXIF, GPS, orientation and ICC
profile carry over.

Requires macOS 13 Ventura or later. Xcode 15+ to build.

No third-party Swift dependencies — everything is system framework
(`SwiftUI`, `AppKit`, `ImageIO`, `UniformTypeIdentifiers`, `UserNotifications`).

---

## Build & run (recommended path: XcodeGen)

The repo ships the source files and a `project.yml`, not a checked-in
`.xcodeproj` (the binary `pbxproj` format isn't friendly to diff or
hand-edit). Use [XcodeGen](https://github.com/yonaskolb/XcodeGen) to
generate the project on demand:

```bash
brew install xcodegen
cd app
xcodegen generate
open HEICConverter.xcodeproj
```

Then in Xcode:

1. Select target **HEICConverter** → **Signing & Capabilities** → pick your
   team (a free personal Apple ID works for running locally).
2. Make sure the run destination is **My Mac**.
3. ⌘R. The menu bar icon (a tilted photo glyph) appears in the top right;
   no Dock icon, no app window. Click it → **Convert files or folder…**.

## Build & run without XcodeGen

If you'd rather not install XcodeGen:

1. In Xcode: **File → New → Project → macOS → App**. Product Name
   `HEICConverter`, Interface **SwiftUI**, Language **Swift**.
2. Delete the auto-generated `ContentView.swift` and the default
   `*App.swift`.
3. Drag every `.swift` file from `app/HEICConverter/` plus
   `Info.plist` into the new project (uncheck *Copy items if needed*,
   add to the `HEICConverter` target).
4. Target → **General** → set **Minimum Deployments** to macOS 13.0.
5. Target → **Info** → ensure `Application is agent (UIElement)` =
   `YES` (this is `LSUIElement` — keeps the app out of the Dock).
6. Build & run (⌘R).

## Ship a `.app`

In Xcode: **Product → Archive** → Organizer → **Distribute App** →
**Copy App** (for local use) or **Developer ID** (requires a paid Apple
Developer account, gets notarized for sharing with other Macs).

Drop `HEICConverter.app` into `/Applications`. Add it under
**System Settings → General → Login Items** to launch on login.

## Source layout

| File | Role | Mirrors in `main.py` |
| --- | --- | --- |
| `HEICConverterApp.swift` | `@main`, `MenuBarExtra` scene | (new) |
| `MenuContentView.swift` | Menu items, settings submenu | (new) |
| `ConversionRunner.swift` | Background `TaskGroup` + notification | `main()` |
| `Converter.swift` | `CGImageSource` → JPEG with metadata | `convert_one()` |
| `Scanner.swift` | Recursive HEIC discovery, output de-dupe | `collect_files`, `dedupe_by_output` |
| `Picker.swift` | `NSOpenPanel` wrappers | (was Automator) |
| `Settings.swift` | `@AppStorage` keys / defaults | argparse defaults |
| `Info.plist` | `LSUIElement = YES`, macOS 13 minimum | (new) |
| `project.yml` | XcodeGen spec | (new) |

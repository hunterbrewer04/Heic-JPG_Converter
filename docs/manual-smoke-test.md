# Loosey Goosey Manual Smoke Test

Run this checklist before tagging any release (and before flipping PR #4 to Ready for Review).

Open `app/HEICConverter.xcodeproj` in Xcode (regenerate with `cd app && xcodegen generate` first if absent), confirm **My Mac** is the run destination, press ⌘R.

## Launch

- [ ] No window pops up. No Dock icon appears. (LSUIElement working.)
- [ ] A `photo.stack` glyph appears in the macOS menu bar (top-right of screen).
- [ ] Click the menu bar icon → the **Loosey Goosey** glass panel drops down attached to the icon.
- [ ] Panel has a translucent material that picks up the wallpaper color behind it (vibrancy working).
- [ ] Panel is 340pt wide with rounded 24pt corners and a subtle inner-stroke gradient.
- [ ] Header shows "Loosey Goosey" on the left and a gear icon on the right.

## Drop zone (empty queue state)

- [ ] Big dashed-border drop zone in the middle says "Drag & Drop HEIC files / or click to browse".
- [ ] Footer shows version (e.g., `v1.0.0`) on left and "Open Folder · Clear" on right.
- [ ] "Clear" is dimmed (queue is empty).
- [ ] Drag a HEIC file from Finder over the drop zone → background tints blue, dashed border becomes solid blue.
- [ ] Release the file → drop zone snaps back; a row appears in a new "CONVERSION QUEUE" section.

## Conversion flow

- [ ] The new row shows: thumbnail placeholder (or photo icon), filename, status text ("Converting…" → progress bar → "Converted to JPG"), and a percentage that animates 0 → ~95% then snaps to 100%.
- [ ] When complete, the trailing slot becomes a blue "Show" pill.
- [ ] Click "Show" → Finder opens with the resulting JPG selected.
- [ ] Verify the JPG actually exists in `~/Downloads` (the default output folder).
- [ ] EXIF/GPS/orientation preserved (open both originals & converted in Preview → ⌘I → compare).

## Bulk conversion

- [ ] Drop a folder containing 30+ HEICs → all enqueue at once, queue scrolls inside the panel.
- [ ] Multiple rows enter "converting" simultaneously (TaskGroup concurrency = CPU core count).
- [ ] Panel remains responsive during heavy batch.

## Mixed / invalid drops

- [ ] Drop 10 files mixing HEIC + JPG + PDF → only HEICs enqueue; the others are silently ignored.
- [ ] Drop a folder with zero HEICs (e.g., a Music folder) → drop zone shakes briefly (±6pt over 200ms); queue unchanged.

## Click-to-browse

- [ ] Click anywhere on the drop zone → standard macOS `NSOpenPanel` appears.
- [ ] Select one or more HEICs → files enqueue and convert.

## Settings popover (gear icon)

- [ ] Click the gear → settings popover appears above the gear, glass-styled.
- [ ] Output Folder row shows current folder; clicking "Change" opens a directory picker; selecting a new folder updates the row.
- [ ] JPEG Quality slider snaps in steps of 5 from 60 to 100; value label updates.
- [ ] Archive originals toggle works.
- [ ] Overwrite existing JPEGs toggle works.
- [ ] Close the panel, reopen → settings persisted (verify by reopening the gear popover).

## Footer interactions

- [ ] "Open Folder" → Finder opens the current output directory.
- [ ] Convert at least one file, then click "Clear" → completed/failed rows disappear; in-progress rows (if any) remain.
- [ ] Clear is disabled (40% opacity) when no completed/failed rows remain.
- [ ] ⌘K → same as Clear.
- [ ] ⌘O while panel open → opens the file picker.
- [ ] ⌘, while panel open → opens the settings popover.

## App lifecycle

- [ ] Drop a big batch (50+ files), close the panel mid-conversion → notification fires when batch completes ("Converted N files").
- [ ] Drop a big batch, keep the panel open → no notification fires when batch completes (UI was visible).
- [ ] ⌘Q while a batch is in flight → `NSAlert` appears: "Conversions in progress. Quit anyway?"
  - [ ] Click Cancel → app stays open, batch continues.
  - [ ] Click Quit → batch cancels, app exits cleanly.
- [ ] ⌘Q with no in-flight work → app exits immediately, no confirmation.

## Visual / accessibility

- [ ] Light mode: glass material picks up wallpaper colors, text remains crisp.
- [ ] Switch to Dark mode (System Settings → Appearance) → panel adapts; text and material darken; no readability regressions.
- [ ] System Settings → Accessibility → Display → enable "Reduce Transparency" → panel uses an opaque `surfaceContainer` background instead of glass; layout otherwise identical.
- [ ] Cycle the menu bar icon click a few times in quick succession — no animation glitches.

## Concurrency / thermal (optional)

- [ ] Drop 50+ large ProRAW HEICs. Activity Monitor → CPU tab → confirm the process uses multiple cores in parallel.
- [ ] (Hard to test without thermal stress) Verify `effectiveConcurrencyLimit` halves on `.serious` and drops to 1 on `.critical` thermal state — code review only.

---

When every box above is ticked, the PR is ready to be marked **Ready for Review** (`gh pr ready 4`).

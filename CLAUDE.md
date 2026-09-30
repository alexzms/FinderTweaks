# FinderTweaks — notes for Claude

Menu bar app (LSUIElement) that enhances Finder. Swift package; the machine has Command Line Tools only, no Xcode.

## Commands
- `make test` — swift-testing unit tests. The Makefile adds the CLT framework flags; plain `swift test` fails without Xcode.
- `make install` — build, sign, copy to ~/Applications, relaunch.
- `make snapshot` — render UI states to build/snapshots/*.png, to check looks without driving Finder.
- `make logs` — ~/Library/Logs/FinderTweaks.log.

## Layout
- `Sources/FinderTweaksCore` — AX wrappers; `FinderTracker` (30 Hz poll of the focused Finder window → `FinderState`); `ToolbarProbe`/`ToolbarInfo` (toolbar geometry, window-relative); `FinderScript` (AppleScript); `FinderPreferences` (com.apple.finder); `Paths`.
- `Sources/FinderTweaks` — `AppDelegate` (menu, permissions, login item), `Feature` protocol, `Features/<Name>/`.

## Gotchas
- Always sign with the "FinderTweaks Local Signing" identity (build.sh does it when present). Ad-hoc builds lose the Accessibility grant on every rebuild.
- AX/CG coordinates put the origin at the top-left of the primary screen with y pointing down. Convert with `Geometry.cocoa`.
- Overlay panels must be non-activating so Finder stays frontmost. While one of them holds keyboard focus, Finder may report no focused window (see `PathBarFeature.update`).
- Log geometry and status only. Never log folder or file names.
- Finder preference changes need `killall Finder`, which interrupts copies. Ask the user before restarting Finder.
- On macOS 26 the window title is the toolbar's flexible item, but the search item takes free room first: it grows from a 38 pt button into a ~290 pt field. Removing other toolbar items mostly widens search, not the title span the path bar uses. Fixed spaces (merged away) and flexible spaces (min width only) do not take room from it. Compact search is the workaround: move SRCH right after BACK, cover title + search field with the bar, and uncover Finder's field while `FinderWindow.isSearching`.
- macOS 26 Finder windows expose no AXDocument; the path comes from the window title (`_FXShowPosixPathInTitle`), with an AppleScript fallback.
- Until the user customizes the toolbar once, Finder stores no item list under "NSToolbar Configuration Browser". Don't write a guessed list.
- Toolbar layout can be checked from the log's `toolbar …` lines without screenshots. A real macOS 26 sample is in `Tests/FinderTweaksCoreTests/ToolbarInfoTests.swift`.

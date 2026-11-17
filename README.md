# tom · top of mind

A tiny plasma orb that holds what you must not forget.

## Run
```sh
just run        # build build/Tom.app and launch it
just install    # copy to ~/Applications and launch
just vfx        # render orb/dissolve frames to build/vfx for shader tweaking
```

## Use
| key | action |
|---|---|
| `⌥ Space` (configurable) | toggle from anywhere |
| `⏎` | add item (or complete selected when input is empty) |
| `↑ ↓` / `⌥↑ ⌥↓` | select / reorder |
| `⌘⏎` | complete selected (or top item) |
| `⌘⌫` | delete selected |
| double-click | edit |
| `esc` / click away | close |
| `⌘,` | settings |

Settings: orb position (menu bar or any of the 4 corners), invisible mode, hotkey, "full at" count, visuals (Candy / Performance), sounds, launch at login.

Data: `~/Library/Application Support/tom/items.json`. Done items clear at midnight.

## Notes
- Shaders live in `Sources/Tom/Metal/Shaders.swift` and compile at runtime, so no Metal toolchain is needed.
- Sounds are synthesized in `SoundFX.swift`, no assets.

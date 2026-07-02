# CustomLineNumbers (macOS port)

Display Notepad++'s line numbers in a **custom format** — **hexadecimal** or
**relative** (Vim-style: distance from the caret line) — instead of plain
decimal, with a configurable starting line number.

macOS port of the Notepad++ plugin **CustomLineNumbers** by Andreas Heim
(GPL v3, 2018–2024). The original is written in Delphi / Object Pascal; this is a
from-scratch C++/Objective-C++ reimplementation of its feature for the Nextpad++
macOS fork — the Delphi source was **not** compiled.

## Menu

- **Off (decimal)** — turn the custom margin off (host's normal decimal numbers).
- **Hexadecimal** — show line numbers in hex.
- **Relative** — Vim-style: the caret's line shows its absolute number; every
  other line shows its distance from the caret.
- **Settings…** — choose the format, the line-number start offset, and optional
  margin text colour / background / bold.
- **About** / **Plugin homepage**.

The active mode is shown with a check mark next to Off / Hexadecimal / Relative,
and is persisted between sessions.

## How it works on macOS — and an important difference from Windows

On **Windows** the plugin takes over the editor's own line-number margin
(margin 0): it converts it to a right-aligned text margin and writes each
visible line's string itself.

On the **macOS fork that is not possible**, because the host *owns* margin 0:
it sets margin-0's type once at editor init and then continuously re-asserts the
margin **width** from the document's line count (on every line-count-changing
edit, on zoom, and on preference/theme/font/language changes). A plugin that
repurposed margin 0 would be fought on every keystroke and would also wipe the
decimal numbers the user still expects.

So this port takes the only clean, host-change-free route: it **adds its own
extra margin** (Scintilla margin index 5 — the host occupies 0–4 and never
raises the margin count) and renders the hex/relative numbers there. **It
supplements, rather than replaces, the host's decimal line-number margin.** If
you want *only* the custom numbers visible, turn off the host's line numbers in
**Preferences ▸ (line numbers)** — the plugin's margin remains.

### Known limitation: status bar

The Windows plugin also reformats the line/column readout in the status bar.
On macOS the host owns and continuously rewrites that readout, so a plugin
**cannot reformat it** (`NPPM_SETSTATUSBAR`, where a host implements it, targets a
dedicated plugin status field — not the line/column readout). That part of the
original feature is therefore not available here. The column-number-offset
setting is likewise inert (it only ever affected the status bar).

> One-line restore if a future host version exposes margin-0 formatting: in
> `src/CustomLineNumbers.mm`, point `kCLNMargin` at `0` and remove the
> `SCI_SETMARGINS` call in `ensureMargin()`.

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Produces a universal (arm64 + x86_64) `CustomLineNumbers.dylib`. Install it at:

```
~/Library/Application Support/Nextpad++/plugins/CustomLineNumbers/CustomLineNumbers.dylib
```

(`cmake --install build` stages it there along with `doc/CustomLineNumbers.txt`.)

## License

GPL v3 — see [LICENSE](LICENSE). Original plugin © Andreas Heim.

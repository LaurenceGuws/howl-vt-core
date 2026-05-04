# Protocol Matrix

## Goal
Drive `howl-vt-core` toward explicit xterm baseline parity and staged kitty protocol adoption.

This file is the source of truth for protocol maturity work in this repo.

## Status
- `supported`: parser, semantic mapping, and grid/input behavior exist with tests.
- `partial`: some layers exist, but behavior is incomplete, dropped, or mode-insensitive.
- `unsupported`: no meaningful handling yet.
- `deferred`: intentionally not in the current tranche.

## Corpus
- Vendored xterm reference: `src/fuzz/assets/xterm-ctlseqs.ms`
- Current deterministic fuzzers:
  - `src/fuzz/scrollback.zig`
  - `src/fuzz/protocol.zig`

## Current Matrix

| Family | Status | Notes |
| --- | --- | --- |
| Printable text + UTF-8 stream decode | supported | Parser emits ASCII slices and UTF-8 codepoints deterministically. |
| Basic C0 controls: `LF`, `CR`, `BS`, `HT` | supported | Mapped in `interpret/semantic.zig` and applied in `grid/model.zig`. |
| Remaining common C0 controls: `BEL`, `VT`, `FF`, `SO`, `SI`, `SUB`, `CAN` | unsupported | Not mapped into semantic behavior today. |
| CSI cursor movement: `CUU`, `CUD`, `CUF`, `CUB`, `CNL`, `CPL`, `CHA`, `VPA`, `CUP`, `HVP` | supported | Covered in semantic and screen behavior tests. |
| CSI tab movement: `CHT`, `CBT` | supported | Fixed 8-column tab-stop model only. |
| Tab-stop management: `HTS`, `TBC`, custom stops | unsupported | No tab-stop state; only computed 8-column jumps. |
| CSI insert/delete/scroll region edits: `IL`, `DL`, `SU`, `SD`, `DECSTBM` | supported | Recent tranche; covered by regression tests. |
| Erase in display/line: `ED`, `EL` | partial | Modes `0-3` implemented, including `ED 3` scrollback erase. Wider erase/query parity work remains. |
| SGR text attributes | partial | Supports reset, bold, underline, blink, reverse, ANSI 16, 256-color, RGB fg/bg, underline color. Missing much of extended xterm attribute surface. |
| DECSTR (`CSI ! p`) | supported | Mapped to `reset_screen`. |
| DEC private modes: `?6`, `?7`, `?25`, `?47`, `?1047`, `?1049` | supported | Origin mode, wrap, cursor visibility, and alt-screen variants implemented. |
| DEC private modes beyond that baseline | partial | High-impact focus/paste/mouse/app-cursor modes exist, and supported DEC modes now answer `DECRQM`. Broader mode families remain unsupported. |
| ANSI modes and mode reports: `SM`, `RM`, `DECRQM`, `DSR`, `DA`, `DA2`, `DECXCPR` | partial | `DSR`, `CPR`, `DA`, `DA2`, and supported DEC-mode `DECRQM` now reply. General ANSI mode reporting is still unsupported. |
| ESC single-byte control finals | partial | Parser and bridge preserve ESC finals; DEC save/restore cursor (`ESC 7`/`ESC 8`) is implemented, broader ESC-final semantics remain unsupported. |
| Charset designation: `ESC (`, `ESC )`, DEC Special Graphics select | partial | Parser tracks G0/G1 designation internally, but bridge/grid do not consume charset state. |
| Shift in/out charset use: `SI`, `SO` | unsupported | No GL switching behavior wired through. |
| OSC transport | partial | Parser transports OSC with BEL/ST terminators and bridge now preserves typed OSC command/payload records. Semantic/host handling is still narrow. |
| OSC window title/icon title | partial | Bridge recognizes title OSC selectors and `latestTitleSet()` exposes them, but no broader host callback surface exists yet. |
| OSC 8 hyperlinks | partial | OSC 8 now drives stable `link_id` cell metadata and `VtCore` URI lookup. Richer host/render integration is still pending. |
| OSC 52 clipboard | partial | OSC 52 now surfaces a pending host clipboard request payload after `apply()`. Policy, decoding, and host integration remain to be defined. |
| OSC color queries/setters (`4`, `10`, `11`, `12`, etc.) | unsupported | No selector parsing or response path. |
| DCS transport | partial | Parser and bridge preserve DCS payloads now; semantics and host integration are still absent. |
| APC transport | partial | Parser and bridge preserve APC payloads now; semantics and host integration are still absent. |
| Kitty keyboard protocol | unsupported | APC/DCS transport now survives the bridge, but no kitty semantic or input encoder support exists yet. |
| Kitty graphics protocol | unsupported | APC/DCS transport now survives the bridge, but no graphics protocol handling or render plumbing exists. |
| Bracketed paste mode (`?2004`) | partial | Mode tracking and paste wrapper emission now exist; full host paste integration path still needs to be threaded through higher layers. |
| Focus in/out (`?1004`) | partial | Mode tracking and focus report emission now exist. |
| Mouse tracking (`1000/1002/1003/1005/1006/1015`) | partial | DECSET mode tracking now exists and SGR (`1006`) mouse encoding works for press/release/motion. Legacy encodings and the rest of the family remain unsupported. |
| Application cursor / keypad modes | partial | `?1` application cursor mode now changes arrow-key encoding; keypad modes and broader key-mode negotiation remain unsupported. |
| modifyOtherKeys / enhanced keyboard reporting | unsupported | No negotiated keyboard-reporting mode surface exists yet. |
| Function/navigation key encoding | partial | Basic xterm-style sequences exist, but not gated by negotiated modes and not extended past current key set. |
| Alt-screen enter/exit and primary scrollback preservation | supported | Explicit tests exist for `1049` save/restore behavior and full-dirty transitions. |
| Snapshot / replay determinism across chunking | supported | Unit/regression/fuzz coverage exists. |

## Layer Notes

### Parser Stronger Than Semantics
- `src/parser/parser.zig` already understands CSI payloads with leaders/intermediates.
- It also transports OSC, APC, DCS, ESC finals, and charset designation state.
- Several gaps are not parser gaps anymore; they are bridge/semantic/host-response gaps.

### Bridge Is Still A Key Boundary
- `src/interpret/bridge.zig` now preserves:
  - typed OSC payloads
  - APC payloads
  - DCS payloads
  - ESC finals
- Remaining gaps are now mostly in semantic interpretation and host/render policy, not raw bridge transport.

### Response Path Exists, But Is Incomplete
- `vt-core` now owns a host-output queue for:
  - DSR/CPR replies
  - DA/DA2 replies
  - supported DEC-mode `DECRQM` replies
  - negotiated focus/paste wrappers
  - negotiated mouse output
- Remaining gaps are broader OSC query replies, richer keyboard negotiation, and more legacy/extended mouse encodings.

## First Tranche

### Tranche 1A: xterm compatibility core
Completed:
1. Explicit non-title OSC event typing in the bridge.
2. Semantic/host-facing support for device and status reports.
3. High-impact DECSET/DECRST modes:
   - focus
   - bracketed paste
   - app cursor
   - initial mouse tracking entry points
4. xterm-correct `ED 3` scrollback erase semantics.
5. DEC mode query replies for supported tracked modes.

### Tranche 1B: modern host interaction
Completed:
1. Mouse reporting encoder path for SGR (`1006`).
2. Mode-aware arrow-key encoding for application cursor mode.
3. OSC 8 hyperlink handling.
4. OSC 52 clipboard handling with explicit host-facing pending request surface.

Next:
1. Legacy and extended mouse protocol families beyond current SGR path.
2. Richer keyboard negotiation and keypad mode support.
3. Broader DEC private mode families and remaining xterm query/setter surfaces.

## Slice Rules
Every protocol slice should land with:
1. parser coverage if new syntax is required
2. bridge event coverage
3. semantic mapping coverage
4. screen/input/response behavior coverage
5. protocol fuzz seed or regression fixture when behavior is stateful

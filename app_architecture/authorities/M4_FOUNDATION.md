# M4 Input and Control Foundation

`M4_FOUNDATION` — frozen as of M4 milestone completion.

This authority captures the stable M4 baseline and the source-of-truth
contract/doc mapping for input/control behavior.

## Scope

M4 owns host-neutral input/control encoding behavior in `howl-terminal`:

- logical key/modifier model
- deterministic keyboard encoding (`encodeKey`)
- placeholder mouse encode surface (`encodeMouse`)
- stable key/modifier constants used by host integrations

M4 does not own host event adapters, platform keycode maps, renderer policy, or
mouse reporting format implementation.

## Stable Contracts

- `app_architecture/contracts/INPUT_CONTROL.md`
- `app_architecture/contracts/RUNTIME_API.md`
- `app_architecture/contracts/MODEL_API.md`

## Frozen Zig Surfaces

- `src/runtime/engine.zig`
- `src/model/types.zig`
- `src/model.zig`
- `src/test/relay.zig` (M4 closeout evidence tests)

## Coverage Baseline

M4 keyboard coverage includes:

- printable ASCII + UTF-8 codepoint pass-through
- special keys: Enter, Escape, Tab, Backspace
- cursor keys: Up/Down/Left/Right
- extended keys: Home/End/Insert/Delete/PageUp/PageDown
- function keys: F1-F12
- modifiers: Shift, Alt, Ctrl and supported combinations

Validation baseline:

- `zig build`
- `zig build test`
- no `compat/fallback/workaround/shim` patterns in `src/**/*.zig`

## Docstring Rule (Frozen Surfaces)

For frozen M4-owned Zig API surfaces:

- each file must retain a top-level `//!` ownership header
- stable public symbols must carry `///` comments aligned to contract semantics
- comments must describe behavior/ownership, not implementation trivia

# Howl Terminal

Howl Terminal is the portable terminal engine for the Howl project family.

The first goal is not to recreate old monolithic app scope. The goal is to
extract, clean, and prove a standalone VT core that can be embedded by multiple hosts:
replay tools, desktop hosts, and Android hosts.

The frozen source repo is reference material only. Code copied from it must be
purpose-checked, renamed into Howl terminology, and kept only when it belongs to
this package.

## Direction

- `howl-terminal` owns VT parser/model/protocol/runtime truth.
- Host-specific UI, JNI, GUI lifecycle, rendering, and packaging belong outside
  this repo.
- No legacy brand strings, legacy ABI names, or compatibility aliases are allowed
  in this repo.
- Public names should use `howl-terminal` for package/binary identity and
  `howl_terminal` only where Zig identifiers require it.

## M1 Runtime Facade

The M1 foundation is composed of `parser`, `pipeline`, `semantic`, and `screen` modules.
For convenience, a `runtime.Engine` facade wraps these components into a single interface
suitable for embedding in hosts. The facade is a transparent wrapper that does not extend
VT semantics; it packages the deterministic parser→pipeline→semantic→screen flow into
a cleaner async feed/apply/read API:

- `init(allocator, rows, cols)` / `initWithCells(allocator, rows, cols)` / `deinit()`
- `feedByte(byte)` / `feedSlice(bytes)` — input
- `apply()` / `clear()` / `reset()` / `resetScreen()` — control
- `screen()` — get const ScreenState reference
- `queuedEventCount()` — introspection

Runtime parity is validated by replay tests that run identical byte streams through
both direct `Pipeline+ScreenState` and `runtime.Engine`, then assert identical
end-state behavior, including split-feed chunking and ignored-event paths
(OSC/APC/DCS/ESC-final and non-mapped controls).
Root-level tests also guard the exported M1 module surface and runtime facade
method shapes.

See `app_architecture/authorities/M1_FOUNDATION.md` and
`app_architecture/contracts/RUNTIME_API.md` for full API details.

## Current Focus

See `docs/engineer/ACTIVE_QUEUE.md`.

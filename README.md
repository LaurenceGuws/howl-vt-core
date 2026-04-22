# Howl Terminal

Howl Terminal is the portable terminal engine for the Howl project family.

The first goal is not to recreate the old monolithic IDE. The goal is to
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

## Current Focus

See `docs/todo/ACTIVE_QUEUE.md`.

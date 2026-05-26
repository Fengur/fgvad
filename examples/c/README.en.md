# fgvad C Demo
> English | [中文](README.md)

A pure C99 + CMake command-line tool demonstrating how to integrate fgvad
without any GUI or platform SDK. Cloud services, Linux background tasks, and
embedded integrators can use this directory as a linking reference.

## Build

Requires macOS + CMake 3.18+ + Rust toolchain only.

```bash
cmake -B build
cmake --build build
```

CMake automatically triggers a top-level `cargo build --release`; the artifact
`libfgvad.dylib` lands at `<repo>/target/release/`. The executable is at
`examples/c/build/fgvad_cli`.

## Run

```bash
# Short Mode — command / query scenario
./build/fgvad_cli short ../../test-data/short/02-normal-utterance.wav

# Long Mode — continuous multi-sentence dictation
./build/fgvad_cli long ../../test-data/long/yixi-zhuzhiwei-typography.wav

# Slice each sentence into a separate WAV
mkdir -p /tmp/fgvad-out
./build/fgvad_cli long input.wav -o /tmp/fgvad-out
```

## Output Format

Event stream (stdout):

```
[mm:ss.mmm] EventName             state=...
[mm:ss.mmm] SentenceEnded         duration=Nms  end_reason=...
```

The final line is a Summary giving sentence count / ForceCut count / final state
/ end reason.

Diagnostic messages ("Read N samples", etc.) go to stderr and can be silenced
with `2>/dev/null`.

## Integrating fgvad Into Your Own Project

The minimum requirements are:

1. Add `<repo>/include/fgvad.h` to your include path
2. Add `libfgvad.dylib` or `libfgvad.a` to your link path

### Using dylib (recommended, zero configuration)

> There are two rpath layers: `my_app` finds `libfgvad.dylib` via `-Wl,-rpath`;
> `libfgvad.dylib` already has an rpath pointing to the ten\_vad framework
> directory (embedded by `build.rs`). The integrator therefore does **not** need
> to add any ten-vad related paths to `my_app`.

```bash
clang -o my_app my_app.c \
    -I<repo>/include \
    -L<repo>/target/release \
    -lfgvad \
    -Wl,-rpath,<repo>/target/release
```

### Using staticlib (handle ten-vad yourself)

`libfgvad.a` carries no link-path information; you must add `-framework ten_vad`
yourself:

> When both `.dylib` and `.a` exist under the `-L` path, macOS clang prefers the
> dylib. To force the static lib, pass the `.a` file's absolute path explicitly
> (or use `-Wl,-search_paths_first` etc.).

```bash
clang -o my_app my_app.c \
    -I<repo>/include \
    <repo>/target/release/libfgvad.a \
    -F<repo>/vendor/ten-vad/macOS -framework ten_vad \
    -Wl,-rpath,<repo>/vendor/ten-vad/macOS
```

## Tests

```bash
ctest --test-dir build -V
```

Runs unit tests for the `wav_io` module.

## IDE Support

`examples/c/.clangd` points to `build/compile_commands.json`. IDEs with clangd
integration (VS Code, Neovim, CLion) will resolve include paths automatically.
Red squiggles disappear after the first build.

## Limitations

- First version is macOS only. Linux support requires vendoring ten-vad Linux
  pre-built binaries and adding a `link_linux()` branch to `build.rs` (tracked
  in the main project roadmap).
- WAV parsing only accepts mono / 16 kHz / i16; other formats are rejected
  immediately with an error.
- Streaming vs. batch: this demo feeds the entire PCM to `fgvad_process` in one
  call (simple and clear). For a real server-side streaming integration, call
  `fgvad_process` chunk-by-chunk as each network frame arrives; the returned
  results are handled identically.

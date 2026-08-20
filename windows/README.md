# Murmur for Windows

The Windows port of Murmur — push-to-talk dictation, on-device.

> **Status: in progress.** The dictionary engine is complete and passes the shared
> behavioural contract. The audio, hotkey, injection and UI layers are specified in detail
> but not yet written. **None of this has ever run on Windows** — see [Honesty](#honesty).

---

## Why this is a rewrite, not a port

Almost every layer of the macOS app is Apple-specific:

| Layer | macOS | Windows |
|---|---|---|
| UI | SwiftUI | Avalonia |
| Audio capture | `AVAudioEngine` | WASAPI via NAudio |
| **Default speech engine** | `SpeechAnalyzer` (ships with macOS 26) | **nothing equivalent exists** |
| Parakeet | FluidAudio → CoreML | sherpa-onnx → ONNX Runtime |
| Hotkey | `CGEventTap` | `SetWindowsHookEx(WH_KEYBOARD_LL)` |
| Text injection | Accessibility API | `SendInput` |

The consequence that shapes everything: **Windows has no counterpart to Apple's
`SpeechAnalyzer`.** On macOS, Parakeet is the optional upgrade. On Windows it is the only
engine, and the app cannot transcribe until the model is downloaded —
see [`docs/PARAKEET-WINDOWS.md`](../docs/PARAKEET-WINDOWS.md).

What *is* genuinely shared is the dictionary's behaviour, and it is shared as a contract
rather than as code: [`shared/dictionary-test-vectors.json`](../shared/dictionary-test-vectors.json).
Both implementations run those vectors in CI. Changing correction semantics starts there.

---

## Decisions, and why

**Avalonia, not WPF or WinUI 3.** WPF cannot be run or UI-tested on macOS, so every mistake
would cost a full CI round-trip. Avalonia's headless test platform runs on macOS in ~100 ms,
including simulated keyboard input and real pixel capture. Win32 interop is unaffected —
hooks, `SendInput` and WASAPI are P/Invoke, not UI-framework code. WinUI 3 was rejected
outright: Microsoft's own docs contradict each other on whether unpackaged single-file
publishing works, with open bugs reporting an exe that won't launch.

**.NET 10, not .NET 8.** .NET 8 reaches end-of-life on **2026-11-10**.

**Right Ctrl is the default hotkey, not Right Alt.** Right Alt is AltGr on German, Polish,
UK, Nordic and most Latin-American layouts — it is how those users type `@`, `€`, `\`, `|`.
Binding push-to-talk there would break basic typing for a large fraction of users. Right
Ctrl produces no character on any layout.

**The hotkey is observed, never swallowed.** The macOS build consumes Right Option because
on macOS that key types characters. On Windows, suppression buys nothing and risks a much
worse failure: if the key-down is swallowed but the key-up escapes — a hook that timed out
mid-gesture, or focus crossing into an elevated window — the target app believes Ctrl is
held down forever.

**CPU-only inference.** sherpa-onnx ships no GPU package; DirectML is five versions behind
and forbids the variable tensor shapes this model requires; CUDA would force every user to
install a toolkit. On CPU with int8 weights, transcription runs ~40× faster than real time.

**Three pinned versions that would break at "latest":**

| Package | Pinned | Why |
|---|---|---|
| `NAudio` | **2.3.0** | 3.x targets .NET 9+ and will not restore |
| `Avalonia.Headless.XUnit` | **11.3.20** | 12.x requires xUnit **v3**, a different package line |
| `org.k2fsa.sherpa.onnx` | 1.13.5 | Bundles ONNX Runtime; never also reference `Microsoft.ML.OnnxRuntime` |

---

## Layout

```
windows/
├─ Directory.Build.props        strict analysis, applied to every project
├─ Directory.Packages.props     central version pinning
├─ global.json                  SDK pin
├─ src/
│  └─ Murmur.Dictionary/        net10.0 — platform-neutral, so CA1416 makes any
│                               Windows-only API call a build error
└─ tests/
   └─ Murmur.Dictionary.Tests/  runs the shared vectors
```

Planned, following the same rule — platform-neutral unless it truly cannot be:

```
   Murmur.Abstractions/      IAudioCapture, IHotkeySource, ITextInjector  (net10.0)
   Murmur.Speech/            sherpa-onnx behind ITranscriber              (net10.0)
   Murmur.Platform.Windows/  the ONLY Win32 code in the repo              (net10.0-windows)
   Murmur.App/               Avalonia UI                                  (net10.0-windows)
```

Keeping the platform layer logic-free is deliberate: anything that lives there is code CI
cannot exercise. Retries, debouncing, device-change handling all belong in the neutral
projects, behind an interface.

---

## Building

```bash
cd windows
dotnet restore Murmur.sln
dotnet build   Murmur.sln --no-incremental -warnaserror
dotnet test    Murmur.sln
```

`--no-incremental` is not optional. Roslyn does not re-emit analyzer warnings on an
incremental build, so `-warnaserror` would pass on cached results and prove nothing.

---

## <a id="honesty"></a>Honesty about what is verified

**Verified:** the dictionary logic passes all 19 shared vectors in Swift on this machine.
The C# implementation is a line-by-line counterpart with the same regex construction,
including `RegexOptions.CultureInvariant` and NFC normalization.

**Not verified:** that the C# code compiles. That is what the CI workflow is for, and its
first green run is the first real evidence.

**Known divergences between the two regex engines**, measured across 30 cases — 9 differed.
The two that affect this code are both handled: culture-sensitive case-insensitive matching
(fixed by `CultureInvariant`) and NFC/NFD mismatch (fixed by normalizing both sides). Two
that are *not* fixable are simply avoided: ICU folds `ß` to `ss` and .NET does not, and
.NET's `.` splits surrogate pairs. Neither is reachable from the patterns this code builds.

**Cannot be verified in CI at all:** text injection into a foreground application. GitHub
runners have an interactive desktop, but foreground activation fails there. That needs a
real Windows machine.

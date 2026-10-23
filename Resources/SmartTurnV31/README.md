# Opt-in Smart Turn v3.1 native candidate

This 16.8 MB compiled graph changes the classification producer's parameters,
without a longer quiet timer, transcript gate, extra inference pass or threshold
change. It is loaded only by the existing explicit Smart Turn opt-in. It does not
change a saved preference or rewrite an existing model cache.

Official v3.2 falsely completes the original unfinished-prefix audio in the
23 October voice-turn report. Official v3.1 holds those same inputs. This is a
measured revision choice for those regressions, not a claim of global superiority
or qualification across languages, devices and conversation conditions.

`Tools/export_smart_turn_v31.py` reproduces the artifact from:

- Official `pipecat-ai/smart-turn-v3`, immutable revision
  `f766f81d3cfdf7737ac64aad813d91bbfd56bf93`: v3.1 and v3.2 GPU ONNX graphs.
- `aufklarer/Smart-Turn-v3.2-CoreML`, revision
  `75f069717f500947195fa1945c46ddb472559cff`: the four-file compiled template.

The exporter verifies all input SHA-256 pins, identical official graph operations
and non-learned constants, and exact native tensor correspondence for all
8,000,386 learned parameters, including two inline scalar biases. It then replaces
every learned tensor with the official v3.1 value, transposing ONNX MatMul weights
and rounding to fp16 exactly as the template does. The float32 normalization/mel
front end, native operations, shapes and precision stay unchanged. No training or
calibration uses the regression fixtures. NumPy/ONNX are export-only dependencies.

The manifest lists every resulting compiled file hash/size. The native loader
independently pins those values. Native parity and the actual endpoint consumer
are tested separately; a successful export alone is not acceptance. The full
source, parity, pause and latency evidence is in
`Tests/Reports/voice-turn-repair-2026-10-23`.

`make app` includes this directory in the signed bundle. The loader reads it in
place after verification. Silero retains its separate pinned downloader and the
ordinary 4 GiB free-space reserve. Bare development binaries require an explicit
owned fixture root; they never run a Python converter or substitute v3.2.

Redistribution is under the adjacent BSD-2-Clause `LICENSE`.

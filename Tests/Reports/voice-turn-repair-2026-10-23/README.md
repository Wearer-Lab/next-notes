# Premature voice turn endings: model producer repair

23 October 2026. The premature-ending regression passes through the actual native
app; the candidate remains **opt-in** because full qualification is incomplete.
The installed app, saved choices, settings, recordings and history are preserved.
All diagnostic children have exited and joined. Component success alone does not
authorize promotion.

## Original failure and cause

The [original production replay](../voice-turn-2026-10-23/native-endpoints.json)
contains 21 trials of seven synthesized WAVs: a complete question and the same
request split by 200/400/600/900/1200/1500 ms pauses. Fifteen trials at 400–1500 ms
commit the unfinished prefix, then commit again. Nine exact final-tail checks
fail. These original inputs and red results are retained unchanged.

The first incorrect decision is produced by Smart Turn v3.2 itself. Its official
ONNX model and native CoreML export both mark the unfinished prefix complete at
the default 0.5 threshold. The earlier source-level decoder/epoch/publication
ordering repairs remain necessary, but do not fix this model decision.

The same PCM and upstream preprocessing were compared with immutable official
v3.0, v3.1 and v3.2 artifacts, one CPU process at a time:

| Official weights | Incomplete-prefix snapshots wrong | Completed snapshots wrong |
|---|---:|---:|
| v3.0 | 0/6 | 0/7 |
| v3.1 | 0/6 | 0/7 |
| v3.2 | 6/6 | 0/7 |

v3.0 is an additional quantized Q/DQ diagnostic; the v3.1/v3.2 GPU graphs have
identical operations and precision and isolate the parameter revision.

These 13 points use the original internal-pause snapshot and 300 ms after each
authored final speech end. They establish a revision regression on these exact
inputs, not global language/model superiority. See [pins](diagnostic-artifact-pins.json),
[v3.0](v3.0.json), [v3.1](v3.1.json), [v3.2](v3.2.json) and
[joined process receipts](version-diagnostic-receipts.json).

## Repair and native parity

The opt-in candidate now uses official **v3.1 parameters**, preserving the existing
raw-PCM float32 normalization/log-mel front end and fp16 native encoder/head.
Threshold 0.5, 200 ms minimum quiet, ASR debounce, decoder watermark, lifecycle,
capture/ASR/output concurrency and effect boundaries remain unchanged. No phrase
filter, extra model pass, conjunction with ASR EOU or longer fixed quiet delay is
introduced. The external v3.2 classification defect remains open; the explicit
revision replacement avoids its observed regression rather than patching model
training here.

`Tools/export_smart_turn_v31.py` verifies all immutable input hashes, identical
official operations/attributes/layouts and non-learned constants, and exact fp16
correspondence of **all 8,000,386 learned elements** in the native v3.2 template.
It replaces all learned tensors from the official v3.1 graph, including two inline
biases. ONNX MatMul weights are transposed into native linear layout. No training
or calibration uses these fixtures. The [export receipt](v31-native-export.json)
lists every mapped tensor and output hash. The signed bundle includes the
reproducible 16.8 MB native artifact and BSD-2 licence in `Resources/SmartTurnV31`;
the runtime independently verifies every compiled file. There is no private model
URL, runtime Python/ONNX dependency, conversion on the turn path or owner cache
migration. Silero's downloader and normal 4 GiB reserve remain unchanged.

The sweep checks each original protected quiet interval every 32 ms from 160 ms
after the prefix through the last protected sample, plus completed snapshots at
200/256/300/400/496 ms. Exact PCM SHA-256 and sample positions match:

- **129/129 protected snapshots stay incomplete** in both official v3.1 and native
  v3.1. The 200 ms fixture's last protected sample is checked as well.
- All **164 complete/incomplete decisions agree** between official ONNX and actual
  production `SmartTurnModel`. Maximum probability difference is 0.032763; this is
  decision parity on the tested corpus, not bitwise parity or a universal error bound.
- Three of 35 completed snapshots are classified incomplete: 400/600 ms cases at
  final+496 ms and 900 ms at final+256 ms. These remain visible. Passing the
  protected snapshots alone does not prove timely production commitment.

See [official sweep](v3.1-quiet-sweep.json), [native sweep](v31-native-sweep.json),
[parity summary](v31-native-parity.json), [native receipt](v31-native-sweep-receipt.json)
and [production source pins](app-source-pins.json). Native model durations in that
diagnostic are not accepted application endpoint or audible timings.

## Rejected ASR conjunction

The actual pinned `StreamingEouAsrManager` was separately fed the exact original
PCM in 160-sample chunks, at debounce 0 and the unchanged 320 ms. This diagnostic
records sample positions, not paced wall latency or raw per-shift decoder output.
The public EOU callback fires during 900–1500 ms pauses at debounce 0, and during
1200/1500 ms pauses at debounce 320. It also arrives late for legitimate short
turns. Requiring that signal would preserve failures and add delay.

The ASR peer confirmed that the public flag is a sticky confirmed/debounced flag,
not raw decoder EOU. Raw EOU can coexist with unfinished words; the debounce is
sample-progress based and suppresses some same-shift new-token events. No SDK
checkout is patched and no public callback is relabelled raw. See
[actual native events](eou-native.json), [probe build pins](eou-probe-build.json)
and [joined receipt](eou-native-receipt.json).

## Production replay and latency

The optimized full application build passes in **922.32 s**, with frozen source
pins unchanged and the final app reporting `TURN_POLICY_OK`. Packaging validates
the framework/rpath, strict signature and all bundled model hashes. The fixture
model copy is absent during replay, proving the actual bundled loading seam.
See [build/signature receipt](app-build.json), [resource samples](build-health.json)
and [native collector receipt](native-endpoints.json.receipt.json).

The same-input **21-trial native replay passes endpoint sequencing**: zero
premature, duplicate or missing commits, versus 15 premature/duplicate trials
originally. Every commit uses the real `smartTurn` consumer. All18 paused-request
final tails survive, versus12/18 originally. Three question-tail checks still
fail with the inherited ASR wording; these are not usable-answer timings.

| Original case | Trials | Early / wrong-count commits | Endpoint median | Endpoint p95 | Final-tail failures |
|---|---:|---:|---:|---:|---:|
| Complete question | 3 | 0 / 0 | 315.232 ms | 323.999 ms | 3 |
| Pause200 ms | 3 | 0 / 0 | 374.597 ms | 383.630 ms | 0 |
| Pause400 ms | 3 | 0 / 0 | 294.730 ms | 298.199 ms | 0 |
| Pause600 ms | 3 | 0 / 0 | 284.251 ms | 311.889 ms | 0 |
| Pause900 ms | 3 | 0 / 0 | 317.860 ms | 372.485 ms | 0 |
| Pause1200 ms | 3 | 0 / 0 | 312.440 ms | 324.664 ms | 0 |
| Pause1500 ms | 3 | 0 / 0 | 300.123 ms | 313.303 ms | 0 |

Boundary: authored final speech end to actual producer `commit.emitted`, from
native monotonic timestamps. p95 uses linear interpolation; n3 per input is
descriptive, not statistical latency qualification. No survivor trials are
discarded. [Exact original/fixed comparison](native-comparison.json),
[raw fixed trace](native-endpoints.json) and [grader receipts](native-grading-receipts.json).
The independent [full scorer](native-score.json) correctly exits1: 25 required
cases are absent, the minimum is30 per case/phase, first-audible stages are absent
and the question's words fail. No threshold or target is changed to obtain green.

The collector opens a fresh capture per trial, uses actual Apple+Parakeet EOU,
Silero, Smart Turn, endpoint tick, commit and reset, and disables replies/tools
through the existing test sink. It never constructs normal app startup/settings
migration or writes owner history. The full roadmap scorer retains missing
audible, provider/phase/route and held-out coverage as failures.

The comparison tool first rejects the original red trace against itself (exit 1);
the [retained red control](comparison-original-red.json) preserves all 15 early
turns. Fixed replay must use the same cases, PCM hashes and repetition counts.
There is no survivor-only endpoint distribution for split, premature or incomplete
case groups. Transcript-tail failures are reported independently and prevent a
usable-answer claim.

139 external libproc samples report peak physical footprint133,858,600 B and
peak RSS409,206,784 B. System swap remains8263.06 MiB during this run; the existing
sampler explicitly reports over its8GiB reference limit. Timing is therefore an
observed endpoint replay under current pressure, not reference-machine resource,
warm/cold residency, M2 or concurrent ASR+TTS acceptance. The serial build's guards
retain4GiB writable reserve and3GiB summed owned RSS; these are development limits,
not live conversation gates or a model-default qualification.

## Diagnostic cache ownership and data preservation

Post-run inspection exposed a harness cleanup bug: a bundled app's CoreML cache
uses **CFBundleIdentifier**, whereas the previous collector assumed executable
basename. The21-trial result remains valid. Its transient shared-ID compiler
outputs disappear after native service teardown; no shared cache is swept without
an admission snapshot. The compact [observation](shared-compiler-cache-observation.json)
retains this scope. Future collection now rejects the shared owner identifier and
requires `ai.pivotstudio.nextnotes.voiceturn.*`, snapshots its real cache before
launch, joins the native child and removes only newly created compiler bundles.
This is diagnostic ownership repair, not a CoreML runtime or endpoint model repair.
See [identity control](compiler-identity-fix.json) and the separate seven-trial
[cache-isolation follow-up](cache-isolation-verdict.json): all seven trials commit
once through Smart Turn, five new compiler bundles are removed after native join,
and the shared owner cache stays identical. Its samples are not pooled into the
paired21-trial result.

[Preservation](preservation-verdict.json) verifies all25 settings/store files,
143 meeting files and the installed app executable unchanged. Each store/meeting
file matches byte count, nanosecond modification time and SHA-256. Latest saved
preferences, including the owner's Phonon choice, survive. The initial post-check
used a different hashed-path namespace for meeting keys; the
[checker correction](preservation-keyspace-correction.json) restores the admission
namespace and confirms identical metadata without writing/restoring any owner file.
The diagnostic uses no owner startup, store migration, history writer, device
change or installation.

## Remaining qualification

The seven split-synthesized English inputs do not replace a held-out human corpus,
continuous natural speech, other languages, provider combinations, physical
microphone/AEC/interruption/audible output, device routes, contention or soak.
Neither source integration nor scoped regression success completes VTD-07/08,
the parent voice roadmap or the 900 ms first-audible target. Keep normal startup
off this candidate until the prescribed gates pass.

## Checks and artifact lifecycle

The actual app policy controls and21 offline scorer controls pass; the original
native trace still fails the regression comparison. The fixed paired trace passes
endpoint sequencing, while the independent full scorer retains all remaining
quality/coverage failures. Catalog render/check validates89 registered runs and84
generated files; all15 catalog tests pass. Seven new records remain private with
`publication.approved:false`. No website publication or installation follows.

[Cleanup](cleanup.json) retires151,593,756 logical bytes of this task's export-only
dependencies, ONNX inputs, linked probes and redundant exported model copy after
all children join. This is logical retired size, not a claim of exact APFS space
reclamation. The current signed diagnostic app/original PCM/Silero fixtures and
useful original failed app remain. The verified build log is compressed; shared
SDK/build/model caches and owner files are preserved. Heavy coordination ownership
is released after native work completes.

## Reproduction

Use `Tools/export_smart_turn_v31.py --help` for the pinned export inputs. Install
export-only ONNX/NumPy into an owned development environment; do not change app
dependencies. `Tools/voice_turn_onnx_reference.py --model <pinned-onnx> --sweep`
and `Tools/VoiceTurnNativeProbe.swift --turn-sweep --turn-smart-only` compare the
same sample endpoints. The maintained fixture collector can copy the packaged
native asset with `Tools/voice_turn_benchmark.py models --root <owned-root>`.

Retain the original WAVs/manifest byte-for-byte. Build the optimized app with the
command recorded in the build receipt, assemble a dedicated signed `VoiceTurn*`
bundle with a dedicated `ai.pivotstudio.nextnotes.voiceturn.*` identifier,
`llama.framework`, the standard Frameworks rpath and SmartTurnV31
resources, then run `Tools/voice_turn_benchmark.py collect`. Its preflight rejects
the earlier malformed framework packaging before launching. `compare --before
<original-trace> --after <fixed-trace> --output <comparison>` checks the paired
endpoint regression; the independent full `benchmark/score.py` remains required.

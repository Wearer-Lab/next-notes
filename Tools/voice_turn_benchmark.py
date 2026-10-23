#!/usr/bin/env python3
"""Owned, synthesized fixtures and pinned assets for the production turn collector.

No owner recordings/defaults are read or changed. Native collection is explicit;
score.py retains the separate unmeasured audible/physical/coverage gates.
"""
import argparse
import array
import hashlib
import json
import math
import plistlib
import shutil
import subprocess
import time
import sys
import urllib.request
import wave
from pathlib import Path

MARKER = '.nextnotes-turn-fixture'
MODELS = [
    ('FluidInference/silero-vad-coreml', 'b419383c55c110e2c9271fa6ee0ea83d03c70d96', 'silero-vad-unified-v6.0.0.mlmodelc'),
]


def owned_root(path):
    root = Path(path).expanduser().resolve()
    # Creating an ownership marker in an existing arbitrary directory isn't ownership.
    if root.exists() and not (root / MARKER).is_file():
        raise ValueError('fixture root already exists without an ownership marker')
    root.mkdir(parents=True, exist_ok=True)
    (root / MARKER).touch()
    return root


def trim(samples):
    voiced = [i for i, x in enumerate(samples) if abs(x) >= 180]
    if not voiced:
        raise ValueError('synthesized fixture has no speech')
    # Preserve 30ms on each edge, independent of the tested VAD.
    return samples[max(0, voiced[0] - 480):min(len(samples), voiced[-1] + 481)]


def synth(root, text, voice, serial):
    aiff, wav = root / f'.part-{serial}.aiff', root / f'.part-{serial}.wav'
    try:
        subprocess.run(['say', '-v', voice, '-r', '175', '-o', str(aiff), text], check=True)
        subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(aiff), str(wav)], check=True)
        with wave.open(str(wav)) as reader:
            if (reader.getnchannels(), reader.getsampwidth(), reader.getframerate()) != (1, 2, 16000):
                raise ValueError('unexpected fixture PCM format')
            samples = array.array('h', reader.readframes(reader.getnframes()))
            if sys.byteorder != 'little':
                samples.byteswap()
        return trim(samples)
    finally:
        aiff.unlink(missing_ok=True)
        wav.unlink(missing_ok=True)


def fixtures(args):
    root = owned_root(args.root)
    silence = lambda n: array.array('h', [0]) * n
    prefix = synth(root, 'I want to book a table for', 'Samantha', 0)
    suffix = synth(root, 'four people tomorrow evening.', 'Samantha', 1)
    complete = synth(root, 'What time is it in Tokyo right now?', 'Samantha', 2)
    recipes = [('complete-question', complete, [], 'right now')]
    lead = 3200
    for pause in (200, 400, 600, 900, 1200, 1500):
        joined = prefix + silence(pause * 16) + suffix
        start = (lead + len(prefix)) / 16
        recipes.append((f'pause-{pause}', joined, [[start, start + pause]], 'tomorrow evening'))
    rows = []
    for identity, speech, intervals, tail in recipes:
        wav = root / (identity + '.wav')
        samples = silence(lead) + speech + silence(8000)
        if sys.byteorder != 'little':
            samples.byteswap()
        with wave.open(str(wav), 'wb') as writer:
            writer.setnchannels(1); writer.setsampwidth(2); writer.setframerate(16000)
            writer.writeframes(samples.tobytes())
        rows.append(dict(id=identity, wav=wav.name, language='en', speechEndMS=(lead + len(speech)) / 16,
                         protectedIntervalsMS=intervals, expectedTail=tail,
                         audioSHA256=hashlib.sha256(wav.read_bytes()).hexdigest()))
    manifest = dict(schema='nextnotes.turn-fixtures.v1', fixtures=rows,
                    provenance='macOS say Samantha175wpm, exact PCM silence, amplitude180/32768 trim with30ms edge retained; synthesized word boundaries, no physical speech',
                    limitations=['Split synthesis changes intonation; human multilingual held-out corpus remains required.'])
    (root / 'fixtures.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'fixtures': len(rows), 'manifest': str(root / 'fixtures.json')}))


def models(args):
    root = owned_root(args.root)
    total_written = 0
    source = Path(__file__).resolve().parent.parent / 'Resources/SmartTurnV31'
    manifest = json.loads((source / 'manifest.json').read_text())
    if shutil.disk_usage(root).free - sum(s['bytes'] for s in manifest['files'].values()) < 4 * 1024 ** 3:
        raise ValueError('native fixture assets deferred: unchanged 4GiB disk reserve')
    for name, spec in manifest['files'].items():
        data = (source / 'smart_turn.mlmodelc' / name).read_bytes()
        if len(data) != spec['bytes'] or hashlib.sha256(data).hexdigest() != spec['sha256']:
            raise ValueError('bundled Smart Turn identity mismatch')
        target = root / 'VoiceTurn' / manifest['revision'] / 'smart_turn.mlmodelc' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        total_written += len(data)
    for repo, revision, bundle in MODELS:
        with urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true') as response:
            listing = json.load(response)
        if listing['sha'] != revision:
            raise ValueError('revision did not resolve immutably')
        files = [s for s in listing['siblings'] if s['rfilename'].startswith(bundle + '/')]
        needed = sum(s['size'] for s in files)
        if shutil.disk_usage(root).free - needed < 4 * 1024 ** 3:
            raise ValueError('native fixture assets deferred: unchanged 4GiB disk reserve')
        for item in files:
            relative = Path(item['rfilename'])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('unsafe remote path')
            target = root / 'VoiceTurn' / revision / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(f'https://huggingface.co/{repo}/resolve/{revision}/{relative.as_posix()}') as response:
                data = response.read(item['size'] + 1)
            if len(data) != item['size']:
                raise ValueError('artifact length mismatch')
            if 'lfs' in item and hashlib.sha256(data).hexdigest() != item['lfs']['sha256']:
                raise ValueError('artifact identity mismatch')
            temporary = target.with_suffix(target.suffix + '.partial')
            temporary.write_bytes(data); temporary.replace(target)
            total_written += len(data)
    print(json.dumps({'bytes': total_written, 'root': str(root),
                      'verification': 'native loader additionally verifies every compiled file against checked-in SHA256 pins'}))


def validate_probe_bundle(binary):
    """Reject the observed dyld packaging failure before launching a child."""
    framework = binary.parent.parent / 'Frameworks/llama.framework/Versions/Current/llama'
    commands = subprocess.check_output(['/usr/bin/otool', '-l', str(binary)], text=True)
    if not framework.is_file() or '@executable_path/../Frameworks' not in commands:
        raise ValueError('Missing bundled llama framework or Frameworks rpath; assemble and sign the dedicated probe bundle before collection')


def compiler_cache_root(binary):
    # Bundled Core ML uses CFBundleIdentifier, not the executable basename.
    # Never adopt/clean the installed app's shared compiler cache.
    info = plistlib.loads((binary.parent.parent / 'Info.plist').read_bytes())
    identity = info.get('CFBundleIdentifier', '')
    if not identity.startswith('ai.pivotstudio.nextnotes.voiceturn.') or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789.-' for c in identity):
        raise ValueError('Use a dedicated ai.pivotstudio.nextnotes.voiceturn.* diagnostic bundle identifier before signing; shared owner compiler caches are protected')
    return Path.home() / 'Library/Caches' / identity / 'com.apple.e5rt.e5bundlecache'


def collect(args):
    import importlib.util
    from tts_asr_workload import compiler_cache_entries, remove_owned_compiler_cache
    from tts_compare import stop_process_group
    spec = importlib.util.spec_from_file_location('nextnotes_model_bench', Path(__file__).resolve().parent.parent / 'Scripts/model-bench.py')
    resources = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(resources)

    class TurnSampler(resources.Sampler):
        # Reuse the maintained libproc accounting. Sample only this explicit child;
        # resource monitoring is external to capture/model/speaker scheduling.
        def __init__(self, pid):
            super().__init__(pid, 1, 8)
            self.pid = pid
            self.timeline = []

        def _descendant_app_pid(self):
            return self.root_pid

        def _rusage(self, pid):
            value = super()._rusage(pid)
            if value is not None:
                self.timeline.append(dict(at=time.time(),footprint_bytes=value[0],rss_bytes=value[1],free_bytes=shutil.disk_usage(root).free))
            return value
    root = owned_root(args.root)
    binary = Path(args.binary).resolve()
    if not binary.name.startswith('VoiceTurn'):
        raise ValueError('use a dedicated VoiceTurn executable basename to isolate its compiler cache')
    validate_probe_bundle(binary)
    if not 1 <= args.repetitions <= 100:
        raise ValueError('repetitions must be1...100')
    if shutil.disk_usage(root).free < 4 * 1024 ** 3 + 512 * 1024 ** 2:
        raise ValueError('native collection deferred:4GiB reserve plus512MiB compiler allowance')
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(binary), '--selftest-turn-benchmark', '--turn-fixtures', str(root / 'fixtures.json'),
               '--turn-model-root', str(root), '--turn-output', str(output),
               '--turn-repetitions', str(args.repetitions), '--voice-feed-10ms']
    cache = compiler_cache_root(binary)
    before = compiler_cache_entries(cache)
    receipt = dict(command=command, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                   started=time.time(), scope='Production endpoint replay; no audible response or tools')
    child = None
    sampler = None
    failure = None
    try:
        with Path(str(output) + '.log').open('w') as log:
            child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            receipt['pid'] = child.pid
            prepared_sampler = TurnSampler(child.pid)
            prepared_sampler.start()
            sampler = prepared_sampler
            deadline = time.monotonic() + args.repetitions * 120 + 180
            while child.poll() is None:
                if time.monotonic() >= deadline:
                    failure = 'native collection timed out'
                elif shutil.disk_usage(root).free < 4 * 1024 ** 3:
                    failure = 'diagnostic4GiB writable reserve reached'
                elif sampler.peak_footprint > 3 * 1024 ** 3:
                    failure = 'diagnostic3GiB child footprint reached'
                if failure:
                    receipt['stopped_reason'] = failure
                    break
                try:
                    child.wait(timeout=.5)
                except subprocess.TimeoutExpired:
                    pass
            receipt['exit'] = child.poll() if failure is None else 'guarded-stop'
    finally:
        if child is not None:
            stop_process_group(child)
            receipt['joined'] = child.poll() is not None
        if sampler is not None:
            sampler.finish()
            sampler.join()
            receipt['resources'] = sampler.result()
            receipt['resource_samples'] = sampler.timeline
        receipt['finished'] = time.time()
        # Persist the child outcome before external compiler cache cleanup.
        Path(str(output) + '.receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        receipt['compiler_cache_removed'] = remove_owned_compiler_cache(cache, before)
        Path(str(output) + '.receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if failure or receipt.get('exit') != 0:
        raise RuntimeError(failure or 'native collector failed; saved receipt/log/partial trace retained')
    print(output)


def compare(args):
    """Compare original/fixed native traces without discarding failures or tails."""
    from collections import Counter
    from statistics import median
    before, after = [json.loads(Path(path).read_text()) for path in (args.before, args.after)]
    for trace in (before, after):
        if trace.get('schema') != 'nextnotes.turn-trace.v1' or trace.get('evidence') != 'native_replay' or trace.get('clock') != 'monotonic':
            raise ValueError('requires actual native monotonic endpoint traces')
    identities = lambda trace: Counter((t['case_id'], t['audio_sha256']) for t in trace['trials'])
    if not before['trials'] or identities(before) != identities(after):
        raise ValueError('original/fixed cases, PCM hashes and trial counts must match')

    def summarize(trace):
        rows = []
        for case in dict.fromkeys(t['case_id'] for t in trace['trials']):
            trials = [t for t in trace['trials'] if t['case_id'] == case]
            early = wrong_count = incomplete = tails = 0
            values = []
            for trial in trials:
                commits = [e['at_ms'] for e in trial['events'] if e['name'] == 'commit']
                if any(not isinstance(x, (int, float)) or isinstance(x, bool) or not math.isfinite(x) for x in commits):
                    raise ValueError('non-finite native commit')
                end = trial['ground_truth']['speech_end_ms']
                early += any(x < end for x in commits)
                wrong_count += len(commits) != 1
                incomplete += trial['status'] != 'measured' or trial.get('failure') is not None
                tails += trial['tail_retained'] is not True
                # No survivor-only latency if any trial is incomplete, split or early.
                if len(commits) == 1 and commits[0] >= end:
                    values.append(commits[0] - end)
            qualified = not (early or wrong_count or incomplete)
            values = values if qualified else []
            ordered = sorted(values)
            position = (len(ordered) - 1) * .95 if ordered else 0
            p95 = (ordered[math.floor(position)] + (ordered[math.ceil(position)] - ordered[math.floor(position)]) * (position % 1)) if ordered else None
            rows.append(dict(case=case, trials=len(trials), premature_trials=early,
                             wrong_commit_count_trials=wrong_count, incomplete_trials=incomplete,
                             endpoint_sources=dict(Counter(t['endpoint_source'] for t in trials)),
                             tail_failures=tails, endpoint_ms=values, median_ms=median(values) if values else None,
                             p95_ms=p95, endpoint_boundary='Authored speech end to actual producer commit; excludes audible response. Tail failures remain separate; these are not usable-answer timings.'))
        return rows

    old, new = summarize(before), summarize(after)
    fixed = all(not (r['premature_trials'] or r['wrong_commit_count_trials'] or r['incomplete_trials']) for r in new)
    result = dict(schema='nextnotes.turn-regression-comparison.v1', before=old, after=new,
                  original_failure_reproduced=any(r['premature_trials'] for r in old),
                  endpoint_sequencing_passed=fixed,
                  semantic_consumer_all_trials=all(t['endpoint_source'] == 'smartTurn' for t in after['trials']),
                  final_tails_passed=all(not r['tail_failures'] for r in new),
                  product_promotion='not_evaluated',
                  scope='Paired exact native fixture regression. Independent full scorer, ASR wording, phase/provider/physical/audible/pressure gates remain required.')
    Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
    if not fixed:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    for action in ('fixtures', 'models', 'collect'):
        child = sub.add_parser(action); child.add_argument('--root', required=True)
        if action == 'collect':
            child.add_argument('--binary', required=True)
            child.add_argument('--output', required=True)
            child.add_argument('--repetitions', type=int, default=3)
        child.set_defaults(func=globals()[action])
    child = sub.add_parser('compare')
    for name in ('before', 'after', 'output'):
        child.add_argument('--' + name, required=True)
    child.set_defaults(func=compare)
    args = parser.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Reweight the pinned Core ML graph with official Smart Turn v3.1 parameters.

Export-only NumPy/ONNX dependencies. No Torch, downloader or application dependency.
This preserves the validated float32 waveform/mel front end and fp16 graph. Before
changing anything, EVERY learned tensor must match the official v3.2 ONNX exactly
after the documented transpose/fp16 conversion, including the two inline biases.
The official graphs must have identical operations, attributes and tensor layouts.
Native probability parity is a separate required validation, not implied here.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

import numpy as np
import onnx

PINS = {
    'v31': 'a32f7445d5076029472b6c9f7a71005df576ea19d5f929021200f535b962af84',
    'v32': 'ab8dc64b88713f90b571c15b714bd1330e6c883cad8763dacf65c9376dc539be',
    'model.mil': '41a6d9ac0f7d01d738e56ecdf4435e55f139591541b7cf1a4dba6b9ce2f1c9ef',
    'weights/weight.bin': 'b6295316741a0149e1fcab7cdf030e1b9bfb0eef778207accee91a2a9703a39c',
    'coremldata.bin': '9245ac99889c9d738cba6c89da9e851fd16488bf8effbc15a109d06b401c9383',
    'analytics/coremldata.bin': '1646746d0029e78d26be065e62602d4f89e51013ec238b653adf7d7d21057f89',
}


def checked(path, pin):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != pin:
        raise ValueError(f'Unexpected immutable input: {path.name}')
    return data


def parameters(model):
    values = {t.name: onnx.numpy_helper.to_array(t) for t in model.graph.initializer}
    result = {name.replace('inner.', 'classifier_', 1).replace('.', '_'): (name, False, v)
              for name, v in values.items() if name.startswith('inner.')}
    # Official ONNX MatMul initializers are transposed linear weights. Infer the
    # semantic name from the associated bias, not from anonymous val_N numbering.
    nodes = {n.output[0]: n for n in model.graph.node}
    for node in model.graph.node:
        if node.op_type != 'Add' or len(node.input) != 2 or not node.input[1].startswith('inner.'):
            continue
        bias = node.input[1]
        matmul = nodes.get(node.input[0])
        if matmul is not None and matmul.op_type == 'MatMul':
            key = bias.replace('inner.', 'classifier_', 1).replace('.', '_').removesuffix('_bias') + '_weight'
            name = matmul.input[1]
            result[key] = (name, True, values[name].T)
    # Whisper's key projections deliberately have no learned bias.
    for layer in range(4):
        suffix = 6 * layer + 1
        node = next(n for n in model.graph.node if n.name == f'node_linear_{suffix}')
        if node.op_type != 'MatMul':
            raise ValueError('Key projection graph changed')
        name = node.input[1]
        result[f'classifier_encoder_layers_{layer}_self_attn_k_proj_weight'] = (name, True, values[name].T)
    if sum(v.size for _, _, v in result.values()) != 8_000_386:
        raise ValueError('Incomplete learned-parameter mapping')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--v31', type=Path, required=True)
    parser.add_argument('--v32', type=Path, required=True)
    parser.add_argument('--template', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output must be a fresh owned directory')
    before = onnx.load_model_from_string(checked(args.v32, PINS['v32']))
    after = onnx.load_model_from_string(checked(args.v31, PINS['v31']))
    def operations(model):
        result = []
        for node in model.graph.node:
            copy = onnx.NodeProto()
            copy.CopyFrom(node)
            copy.ClearField('metadata_props')  # Exporter stack-trace line numbers differ.
            result.append(copy.SerializeToString())
        return result
    if operations(before) != operations(after):
        raise ValueError('Official graph operations differ; cannot reuse native program')
    old, new = parameters(before), parameters(after)
    if old.keys() != new.keys():
        raise ValueError('Parameter names differ')
    learned = {x[0] for x in old.values()}
    for a, b in zip(before.graph.initializer, after.graph.initializer, strict=True):
        if (a.name, a.data_type, list(a.dims)) != (b.name, b.data_type, list(b.dims)):
            raise ValueError('Initializer layout differs')
        if a.name not in learned and a.SerializeToString() != b.SerializeToString():
            raise ValueError('Non-learned constant differs')
    files = {name: checked(args.template / name, pin) for name, pin in PINS.items() if name not in ('v31', 'v32')}
    mil = files['model.mil'].decode()
    blob = bytearray(files['weights/weight.bin'])
    rows = []
    for key, (source, transpose, previous) in old.items():
        target_source, target_transpose, current = new[key]
        if source != target_source or transpose != target_transpose or previous.shape != current.shape:
            raise ValueError('Tensor mapping differs')
        pattern = re.compile(r'(tensor<fp16, \[([^\]]+)\]> ' + re.escape(key) + r'_to_fp16 = const\(\).*?val = tensor<fp16, \[[^\]]+\]>\()(.*?)(\)\];)')
        matches = list(pattern.finditer(mil))
        if len(matches) != 1:
            raise ValueError(f'Expected exactly one native constant: {key}')
        match = matches[0]
        if tuple(map(int, match[2].split(','))) != previous.shape:
            raise ValueError('Native shape differs')
        location = re.search(r'offset = tensor<uint64, \[\]>\((\d+)\)', match[3])
        if location:
            header = int(location[1])
            magic, dtype, size, offset = struct.unpack_from('<IIQQ', blob, header)
            if (magic, dtype, size) != (0xDEADBEEF, 1, previous.size * 2) or offset != header + 64:
                raise ValueError('Unsupported native blob layout')
            if bytes(blob[offset:offset+size]) != previous.astype('<f2').tobytes():
                raise ValueError(f'Native v3.2 tensor does not match upstream: {key}')
            blob[offset:offset+size] = current.astype('<f2').tobytes()
        else:
            if previous.size != 1 or float.fromhex(match[3].strip('[]')) != float(previous.astype('<f2').item()):
                raise ValueError('Unexpected inline native constant')
            replacement = '[' + float(current.astype('<f2').item()).hex() + ']'
            mil = mil[:match.start(3)] + replacement + mil[match.end(3):]
        rows.append(dict(parameter=key, upstream_initializer=source, transpose=transpose,
                         elements=int(previous.size), storage='blob' if location else 'inline'))
    files['weights/weight.bin'] = bytes(blob)
    files['model.mil'] = mil.encode()
    args.output.mkdir(parents=True)
    for name, data in files.items():
        path = args.output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    receipt = dict(schema='nextnotes.smart-turn-reweight.v1', parameters=rows,
                   learned_elements=sum(row['elements'] for row in rows),
                   source_pins=PINS, output={name: dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest()) for name, data in files.items()},
                   scope='All learned tensors verified against official v3.2 then replaced by official v3.1 with identical layouts; unchanged float32 front end/native operations. Native parity required separately.')
    args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt['output'], indent=2))


if __name__ == '__main__':
    main()

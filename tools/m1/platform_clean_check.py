"""Independently compare every dumped cleanup byte using the layout description."""
import argparse
from array import array
import hashlib
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--layout', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    layout = json.loads(args.layout.read_text())
    directory = args.directory
    template = layout['scratch_template_base']
    ranges = [('object.bin', layout['object_bytes'], None)]
    for index, (_, length) in enumerate(layout['scratch_restore']):
        ranges += [(f'scratch-{index}.bin', length, template),
                   (f'template-{index}.bin', length, template)]
        template += length
    result = dict(status='running', scope='Complete physical cleanup dumps, synthetic dirty data; no model numerical validation',
                  layout_sha256=hashlib.sha256(args.layout.read_bytes()).hexdigest(), files=[])
    try:
        for name, length, source_address in ranges:
            path = directory / name
            assert path.stat().st_size == length, (name, path.stat().st_size, length)
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for offset in range(0, length, 1 << 20):
                    count = min(1 << 20, length - offset)
                    actual = stream.read(count)
                    if source_address is None:
                        expected = bytes(count)
                    else:
                        first_word = (source_address + offset) // 8
                        values = array('Q', (0x7fc123457f800000 ^ word
                                             for word in range(first_word, first_word + count // 8)))
                        if sys.byteorder != 'little':
                            values.byteswap()
                        expected = values.tobytes()
                    if actual != expected:
                        index = next(i for i, (a, e) in enumerate(zip(actual, expected)) if a != e)
                        result['first_difference'] = dict(file=name, offset=offset + index,
                                                         actual=actual[index], expected=expected[index])
                        raise AssertionError(result['first_difference'])
                    digest.update(actual)
            result['files'].append(dict(file=name, bytes=length, sha256=digest.hexdigest(), status='all_bytes_matched'))
        result['status'] = 'passed'
    except Exception as exc:
        result.update(status='failed', error=repr(exc))
        raise
    finally:
        (directory / 'numeric-check.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()

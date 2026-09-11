#!/usr/bin/env python3
"""Verify and externally bind the immutable final release ZIP."""
from __future__ import annotations

import argparse
import json
import stat
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.release_acceptance import (POST_SEAL_PLATFORMS, POST_SEAL_SCHEMA, RELEASE_ID, identity,
                                      load, require, validate_identity,
                                      validate_timestamp)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def safe_name(name):
    path = PurePosixPath(name)
    require(name == path.as_posix() and not path.is_absolute() and '..' not in path.parts and
            ':' not in name and '\\' not in name and all(part not in ('', '.') for part in path.parts),
            'Unsafe final ZIP member')
    return path


def inspect_and_extract(archive_path, destination):
    names = set()
    total = 0
    with zipfile.ZipFile(archive_path) as archive:
        require(archive.testzip() is None, 'Final ZIP integrity failure')
        for member in archive.infolist():
            path = safe_name(member.filename)
            require(member.filename not in names, 'Duplicate final ZIP member')
            names.add(member.filename)
            mode = member.external_attr >> 16
            require(not stat.S_ISLNK(mode), 'Final ZIP links are forbidden')
            require(not member.is_dir(), 'Final ZIP directory entries are forbidden')
            target = destination.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as source, target.open('xb') as sink:
                while chunk := source.read(1024 * 1024):
                    sink.write(chunk)
                    total += len(chunk)
    require(names, 'Final ZIP is empty')
    return len(names), total


def verify_archive(archive_path):
    archive_path = Path(archive_path).resolve(strict=True)
    require(archive_path.name == RELEASE_ID + '.zip', 'Final ZIP name differs')
    with tempfile.TemporaryDirectory(prefix='csip post-seal ') as directory:
        extracted = Path(directory)
        file_count, extracted_bytes = inspect_and_extract(archive_path, extracted)
        result = subprocess.run(
            [sys.executable, '-B', str(extracted / 'verify.py'), str(extracted)],
            cwd=extracted, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            encoding='utf-8', errors='replace', check=False)
        require(result.returncode == 0, 'Extracted final delivery verification failed:\n' + result.stdout[-4000:])
        version = load(extracted / 'VERSION.json')
        require(version.get('release_id') == RELEASE_ID, 'Final ZIP release differs')
        return {
            'release_id': version['release_id'],
            'archive_name': archive_path.name,
            'archive': identity(archive_path),
            'acceptance': identity(extracted / 'ACCEPTANCE.json'),
            'payload_manifest': identity(extracted / 'PAYLOAD_MANIFEST.json'),
            'file_count': file_count,
            'extracted_bytes': extracted_bytes,
            'checks': {
                'archive_name': 'PASS',
                'archive_sha256': 'PASS',
                'zip_crc': 'PASS',
                'safe_unique_members': 'PASS',
                'extracted_self_verification': 'PASS',
                'release_identity': 'PASS',
            },
        }


def build_receipt(facts, platform_name, validation_id, validated_at):
    validate_timestamp(validated_at)
    require(platform_name in ('MACOS', 'WINDOWS'), 'Post-seal platform differs')
    require(isinstance(validation_id, str) and validation_id, 'Post-seal validation ID is missing')
    return {
        'schema': POST_SEAL_SCHEMA,
        'status': 'PASS',
        'platform': platform_name,
        'validation_id': validation_id,
        'validated_at_utc': validated_at,
        **facts,
    }


def validate_receipt(value, facts, expected_platform='MACOS'):
    require(isinstance(value, dict), 'Post-seal receipt is missing')
    require(value.get('schema') == POST_SEAL_SCHEMA, 'Post-seal receipt schema differs')
    require(value.get('status') == 'PASS', 'Post-seal receipt did not pass')
    require(value.get('platform') == expected_platform, 'Post-seal receipt platform differs')
    require(isinstance(value.get('validation_id'), str) and value['validation_id'],
            'Post-seal validation ID is missing')
    validate_timestamp(value.get('validated_at_utc'))
    for key in ('release_id', 'archive_name', 'archive', 'acceptance', 'payload_manifest',
                'file_count', 'extracted_bytes', 'checks'):
        require(value.get(key) == facts[key], 'Post-seal receipt differs: ' + key)
    validate_identity(value['archive'], 'Post-seal archive')
    validate_identity(value['acceptance'], 'Post-seal acceptance')
    validate_identity(value['payload_manifest'], 'Post-seal payload manifest')
    require(all(status == 'PASS' for status in value['checks'].values()),
            'Post-seal checks did not all pass')
    return value


def validate_publication_gate(receipts, facts):
    require(isinstance(receipts, list) and len(receipts) == len(POST_SEAL_PLATFORMS),
            'Post-seal publication gate requires one receipt per platform')
    platforms = {value.get('platform') for value in receipts if isinstance(value, dict)}
    require(platforms == POST_SEAL_PLATFORMS, 'Post-seal publication platform set differs')
    for value in receipts:
        validate_receipt(value, facts, value['platform'])
    return receipts


def receipt_name(platform_name):
    return RELEASE_ID + '.' + platform_name.lower() + '-post-seal.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--output', type=Path, help='Write a new external receipt')
    mode.add_argument('--receipt', type=Path, action='append',
                      help='Recheck both external receipts; pass once per platform')
    parser.add_argument('--platform', choices=('MACOS', 'WINDOWS'))
    parser.add_argument('--validation-id')
    parser.add_argument('--validated-at', help='ISO-8601 UTC time; defaults to the current UTC time')
    args = parser.parse_args()
    facts = verify_archive(args.archive)
    if args.receipt:
        require(args.platform is None and args.validation_id is None and args.validated_at is None,
                'Receipt recheck does not accept creation fields')
        receipt_paths = [path.resolve(strict=True) for path in args.receipt]
        receipts = [load(path) for path in receipt_paths]
        for path, receipt in zip(receipt_paths, receipts):
            require(path.name == receipt_name(receipt.get('platform', '')),
                    'Post-seal receipt name differs')
        validate_publication_gate(receipts, facts)
        print(json.dumps({'status': 'PASS', 'publication_gate': 'PASS',
                          'receipts': list(map(str, receipt_paths)),
                          'archive': facts['archive']}))
        return
    require(args.platform is not None and args.validation_id is not None,
            'Receipt creation requires --platform and --validation-id')
    output = args.output.resolve()
    require(not output.exists() and output.name == receipt_name(args.platform),
            'Post-seal receipt output name differs')
    timestamp = args.validated_at or datetime.now(timezone.utc).isoformat()
    receipt = build_receipt(facts, args.platform, args.validation_id, timestamp)
    write_json(output, receipt)
    print(json.dumps({'status': 'PASS', 'receipt': str(output), 'archive': facts['archive']}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('POST_SEAL_VERIFICATION=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)

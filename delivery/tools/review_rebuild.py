#!/usr/bin/env python3
"""Review new physical results against the identified R4 engineering reference."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.source_export import identity, write_json
from tools.verify_windows_board_release import physical_findings, verify


def bit_payload(path):
    data = path.read_bytes()
    offset = 2 + struct.unpack_from('>H', data)[0]
    if data[offset:offset + 3] != b'\x00\x01a':
        raise ValueError('Unsupported BIT header')
    offset += 2
    fields = {}
    for tag in b'abcd':
        if data[offset] != tag:
            raise ValueError('Invalid BIT header field')
        size = struct.unpack_from('>H', data, offset + 1)[0]
        fields[chr(tag)] = data[offset + 3:offset + 3 + size].rstrip(b'\0').decode('ascii')
        offset += 3 + size
    if data[offset] != ord('e'):
        raise ValueError('Missing BIT payload')
    size = struct.unpack_from('>I', data, offset + 1)[0]
    payload = data[offset + 5:]
    if len(payload) != size:
        raise ValueError('BIT payload length differs')
    return {'header': fields, 'payload_bytes': size, 'payload_sha256': hashlib.sha256(payload).hexdigest()}


def hwh_structure(path):
    root = ET.parse(path).getroot()
    timestamp = root.attrib.pop('TIMESTAMP', None)
    if root.tag != 'EDKSYSTEM' or not timestamp:
        raise ValueError('Unexpected HWH root')
    for node in root.iter():
        node.text = (node.text or '').strip()
        node.tail = (node.tail or '').strip()
    canonical = ET.canonicalize(ET.tostring(root, encoding='unicode'))
    return {'timestamp': timestamp, 'structure_sha256': hashlib.sha256(canonical.encode()).hexdigest()}


def detailed_review(build):
    routed = build / 'fifo-routed-audit'
    with (routed / 'fifo_paths.tsv').open(newline='') as stream:
        paths = list(csv.DictReader(stream, delimiter='\t'))
    payload = [row for row in paths if row['crossing'].startswith('payload_word_')]
    gray = [row for row in paths if row['crossing'] in ('wr_gray', 'rd_gray')]
    if len(payload) != 456 or len(gray) != 8 or any(float(row['requirement_ns']) != 8 or float(row['slack_ns']) < 0 for row in paths):
        raise ValueError('FIFO routed coverage/requirements/slack differ')
    transcript = (build / 'fifo-routed-audit.log').read_text()
    if not re.search(r'(?m)^FIFO_ROUTED_AUDIT=PASS\s*$', transcript) or not re.search(r'(?m)^ASYNC_REG_STAGES_CHECKED=16\s*$', transcript):
        raise ValueError('Missing actual FIFO audit completion markers')
    drc_root = build / 'drc-routed-audit-2'
    with (drc_root / 'objects.tsv').open(newline='') as stream:
        objects = list(csv.DictReader(stream, delimiter='\t'))
    unloaded = [row for row in objects if row['violation'] == 'RTSTAT-10#1' and row['object_type'] == 'nets']
    normalized = re.compile(r'^protection_system_i/protection_ip_axi_lite_0/inst/normalized_(?:sample_valid|profile_configured|profile_valid|width_supported|sample_sequence\[(?:[0-9]|[12][0-9]|3[01])\]|sample_ch[12]\[(?:[0-9]|1[0-2])\])$')
    vendor = ('dbg_hub/', 'protection_system_i/smartconnect_0/', 'protection_system_i/system_ila_stage2b_0/',
              'protection_system_i/system_ila_stage2i_b2_source_0/')
    if len(unloaded) != 108 or len({row['object'] for row in unloaded}) != 108:
        raise ValueError('RTSTAT-10 full object inventory differs')
    if any(not (row['object'].startswith(vendor) or normalized.fullmatch(row['object'])) for row in unloaded):
        raise ValueError('Unreviewed no-load net')
    observational = sum(bool(normalized.fullmatch(row['object'])) for row in unloaded)
    if observational != 62:
        raise ValueError('Normalized observational output inventory differs')
    lut = [row for row in objects if row['violation'].startswith('PDCN-1569#')]
    if len(lut) != 6 or any(not row['object'].startswith('dbg_hub/') for row in lut):
        raise ValueError('LUT equation finding escaped debug hub')
    text = (build / 'v/reports/methodology.rpt').read_text()
    blocks = re.findall(r'(?ms)^([A-Z]+-\d+)#\d+ Warning\n(.*?)(?=^[A-Z]+-\d+#\d+ Warning|\Z)', text)
    if len(blocks) != 9:
        raise ValueError('Methodology detailed inventory differs')
    for rule, body in blocks:
        if rule == 'LUTAR-1' and 'LUT cell dbg_hub/' in body:
            continue
        if rule == 'XDCB-5' and '/ila_v6_2/constraints/ila.xdc' in body:
            continue
        if rule == 'TIMING-9' and 'Unknown CDC Logic' in body:
            continue
        raise ValueError('Unreviewed methodology detail: ' + rule)
    return {'status': 'PASS', 'disposition': 'RETAIN_ORIGINAL_SEVERITIES',
        'fifo_payload_paths': 456, 'fifo_gray_paths': 8, 'async_reg_stages': 16,
        'worst_payload_slack_ns': min(float(row['slack_ns']) for row in payload),
        'worst_gray_slack_ns': min(float(row['slack_ns']) for row in gray),
        'rtstat_no_load_nets': len(unloaded), 'normalized_observation_only_nets': observational,
        'rationale': {
            'PDCN-1569': 'Three unused LUT input findings are confined to the AMD debug hub.',
            'RTSTAT-10': '62 MARK_DEBUG normalized observational outputs have no consumers by design; 46 other nets belong to AMD debug/ILA/SmartConnect. Raw protection does not consume the normalized fork.',
            'LUTAR-1': 'Four asynchronous-reset LUT findings are inside AMD debug-hub FIFO reset logic. Debug reliability risk is retained; vendor IP is not edited.',
            'XDCB-5': 'Four inefficient object queries are in generated AMD ILA constraints; runtime efficiency warning retained.',
            'TIMING-9 / CDC-4': 'FIFO payload crossing remains Critical. Current routed path bounds, Gray synchronization and regression substantiate the engineering contract; this is not analog metastability or MTBF proof.'},
        'evidence': {p.relative_to(build).as_posix(): identity(p)
            for directory in (routed, drc_root) for p in sorted(directory.iterdir()) if p.is_file()}}


def cdc_connections(path):
    clocks = []
    rows = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('Source Clock:'):
            clocks = [line.strip()]
        elif line.startswith('Destination Clock:'):
            clocks.append(line.strip())
        elif re.match(r'^\s*\d+\s+CDC-\d+\s+', line):
            normalized = re.sub(r'^\s*\d+\s+', '', line)
            rows.append(' | '.join(clocks) + ' | ' + ' '.join(normalized.split()))
    if not rows:
        raise ValueError('Detailed CDC connection rows are absent')
    return sorted(rows)


def review(build, reference, source):
    reference_verification = verify(reference)
    run = json.loads((build / 'rebuild_receipt.json').read_text())
    reports = build / 'v/reports'
    baseline_reports = reference / 'evidence/physical/vivado-output/reports'
    actual = physical_findings(reports)
    baseline = physical_findings(baseline_reports)
    timing_ok = all(value >= 0 for key, value in actual['timing'].items() if key.endswith('_ns')) and all(
        value == 0 for key, value in actual['timing'].items() if key.endswith('endpoints'))
    constraint_ok = bool(actual['constraint_checks']) and all(v == 0 for v in actual['constraint_checks'].values())
    selected = json.loads((reference / 'EVIDENCE_PROVENANCE.json').read_text())['selected_sources']
    source_check = {}
    for relative, row in selected.items():
        if relative.startswith(('rtl/', 'fpga/vivado/constraints/')):
            observed = identity(source / relative)
            source_check[relative] = observed['sha256'] == row['identity']['sha256']
    connection_match = cdc_connections(reports / 'cdc.rpt') == cdc_connections(baseline_reports / 'cdc.rpt')
    statuses = {'timing': 'PASS' if timing_ok and constraint_ok else 'FAIL'}
    for kind in ('drc', 'cdc', 'methodology'):
        statuses[kind] = 'PASS' if actual[kind] == baseline[kind] else 'BLOCKED'
    if not connection_match or not source_check or not all(source_check.values()):
        statuses['cdc'] = 'BLOCKED'
    result = {'schema': 'csip-rebuild-engineering-review-v1', 'execution_id': run['execution_id'],
        'source_manifest': identity(source / 'SOURCE_MANIFEST.json'),
        'rebuild_receipt': identity(build / 'rebuild_receipt.json'),
        'r4_reference_manifest': reference_verification['manifest'], 'new_findings': actual,
        'r4_findings': baseline, 'checks': statuses,
        'cdc_connection_inventory_equal': connection_match, 'rtl_and_constraints_equal': source_check,
        'comparison_basis': 'Exact rule/severity/count inventory and CDC endpoints; engineering comparison only. DRC and methodology detailed disposition still requires review.',
        'detailed_drc_methodology_review': 'NOT_RUN',
        'board_verified_new_artifacts': 'NOT_RUN', 'formal_acceptance': 'NOT_FORMALLY_ACCEPTED',
        'reports': {p.name: identity(p) for p in sorted(reports.glob('*.rpt'))},
        'artifact_comparison': {}}
    artifacts = build / 'v/artifacts'
    for suffix in ('bit', 'hwh', 'ltx', 'xsa'):
        candidates = list(artifacts.glob('*.' + suffix))
        if len(candidates) != 1:
            raise ValueError('Expected exactly one new ' + suffix + ' artifact')
        original = reference / 'artifacts' / candidates[0].name
        result['artifact_comparison'][suffix] = {'rebuilt': identity(candidates[0]),
            'r4': identity(original) if original.is_file() else None,
            'byte_equal_to_r4': identity(candidates[0]) == identity(original) if original.is_file() else None}
    if (build / 'drc-routed-audit-2/objects.tsv').is_file():
        result['detailed_drc_methodology_review'] = detailed_review(build)
        result['comparison_basis'] = 'Rule/severity/count and exact CDC endpoints, plus current full DRC object and FIFO routed audits. Warnings and CDC-4 Critical remain visible.'
    for suffix, parser in (('bit', bit_payload), ('hwh', hwh_structure)):
        result['artifact_comparison'][suffix]['structure'] = {
            'rebuilt': parser(artifacts / ('protection_system.' + suffix)),
            'r4': parser(reference / 'artifacts' / ('protection_system.' + suffix))}
    result['review_tool'] = identity(Path(__file__))
    write_json(build / 'engineering_review.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    result = review(args.build.resolve(), args.reference.resolve(), args.source.resolve())
    print(json.dumps({'execution_id': result['execution_id'], 'checks': result['checks'],
                      'detailed_review': result['detailed_drc_methodology_review'], 'board': 'NOT_RUN'}))


if __name__ == '__main__':
    main()

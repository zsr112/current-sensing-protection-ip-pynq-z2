"""Target-specific dependency checks. No build, license checkout or hardware access."""
from __future__ import annotations
import os
import platform
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from tools.runtime_config import resolve_tool, resolve_vivado_bin, resolve_directory, load_config
from tools.source_export import verify

TARGETS = ('portable', 'digital', 'vivado', 'all')


def probe(path, flag):
    result = subprocess.run([str(path), flag], capture_output=True, text=True,
                            errors='replace', timeout=60)
    return result.returncode, (result.stdout + result.stderr).strip()


def inventory(root, target='all', options=None):
    options = options or {}
    if target not in TARGETS:
        raise ValueError('Unknown target: ' + target)
    result = {'schema': 'csip-target-preflight-v1', 'requested_target': target,
              'tools': {}, 'missing': [], 'unsupported': [], 'errors': [],
              'source_integrity': 'NOT_RUN', 'license': 'NOT_RUN', 'board_files': 'NOT_REQUIRED',
              'board_verified': 'NOT_RUN', 'formal_acceptance': 'NOT_FORMALLY_ACCEPTED'}
    try:
        source = verify(root)
        result['source_integrity'] = 'PASS'
        result['source_files'] = len(source['files'])
    except Exception as error:
        result['errors'].append('source_integrity: ' + str(error))
        result['source_integrity'] = 'FAIL'
    try:
        load_config(root)
    except Exception as error:
        result['errors'].append(str(error))
    required = {'python'}
    if target in ('portable', 'digital', 'all'):
        required.update(('iverilog', 'vvp'))
    if target in ('digital', 'vivado', 'all'):
        required.update(('vivado', 'pwsh'))
    paths = {}
    for name in ('python', 'iverilog', 'vvp', 'pwsh', 'vivado'):
        row = result['tools'][name] = {'required': name in required, 'path': None, 'status': 'NOT_RUN'}
        try:
            if name == 'python':
                path = Path(sys.executable)
            elif name == 'vivado':
                directory = resolve_vivado_bin(root, options.get('vivado_bin'))
                path = directory / ('vivado.bat' if os.name == 'nt' else 'vivado') if directory else None
            else:
                path = resolve_tool(root, name, options.get(name))
            paths[name] = path
            row['path'] = str(path) if path else None
            if path is None:
                row['status'] = 'MISSING'
                if name in required:
                    result['missing'].append(name)
                continue
            if name not in required:
                row['status'] = 'DETECTED_NOT_PROBED'
                continue
            code, banner = (0, platform.python_version()) if name == 'python' else probe(
                path, '-V' if name in ('iverilog', 'vvp') else '-version' if name == 'vivado' else '--version')
            row.update(version=banner, exit_code=code)
            valid = code == 0
            if name == 'python':
                valid &= sys.version_info >= (3, 10)
            elif name in ('iverilog', 'vvp'):
                valid &= bool(re.search(r'(?:Icarus Verilog(?: runtime)? version) (?:12|13|14)\.', banner))
            elif name == 'pwsh':
                valid &= bool(re.search(r'PowerShell 7\.', banner))
            else:
                valid = code in (0, 1) and 'vivado v2024.1 (64-bit)' in banner and 'SW Build 5076996' in banner and 'ERROR:' not in banner
            row['status'] = 'PASS' if valid else 'UNSUPPORTED'
            if not valid:
                result['unsupported'].append(name)
        except Exception as error:
            row.update(status='CONFIGURATION_ERROR', error=str(error))
            result['errors'].append(name + ': ' + str(error))
    if target != 'portable':
        if os.name != 'nt':
            result['unsupported'].append('vendor execution requires Windows')
        vivado = paths.get('vivado')
        if target in ('digital', 'all') and vivado:
            for name in ('xtclsh.bat', 'xvlog.bat', 'xelab.bat', 'xsim.bat'):
                if not (vivado.parent / name).is_file():
                    result['missing'].append(name)
    try:
        board = resolve_directory(root, 'board_repo', options.get('board_repo'))
        if board is not None and not board.is_dir():
            raise ValueError('Explicit board repository does not exist')
        if target in ('vivado', 'all'):
            vivado = paths.get('vivado')
            board = board or (vivado.parent.parent / 'data/boards/board_files' if vivado else None)
            matches = []
            if board:
                for file in board.rglob('board.xml'):
                    node = ET.parse(file).getroot()
                    if node.get('name') == 'pynq-z2' and node.get('vendor') == 'tul.com.tw' and node.findtext('file_version') == '1.0':
                        part = node.find("./components/component[@name='part0']")
                        if part is None or part.get('part_name') != 'xc7z020clg400-1':
                            raise ValueError('PYNQ-Z2 part0 definition differs')
                        for reference in (node.get('preset_file'), part.get('pin_map_file')):
                            if not reference or not (file.parent / reference).is_file():
                                raise ValueError('Incomplete PYNQ-Z2 board definition: ' + str(file))
                        matches.append(str(file))
            result['board_files'] = {'status': 'PASS' if matches else 'MISSING', 'matches': matches}
            if not matches:
                result['missing'].append('tul.com.tw:pynq-z2:part0:1.0')
    except Exception as error:
        result['errors'].append('board_files: ' + str(error))
    try:
        output = resolve_directory(root, 'build_root', options.get('build_root'))
        result['output'] = {'path': str(output) if output else None, 'status': 'NOT_SELECTED'}
        if output:
            if output.exists() or output.is_relative_to(root.resolve()) or root.resolve().is_relative_to(output):
                raise ValueError('Output must be fresh and disjoint from source')
            ancestor = output.parent
            while not ancestor.exists():
                ancestor = ancestor.parent
            if not ancestor.is_dir() or not os.access(ancestor, os.W_OK):
                raise ValueError('Output ancestor is not writable')
            result['output']['status'] = 'WRITABLE_ANCESTOR'
    except Exception as error:
        result['errors'].append('output: ' + str(error))
    result['target_ready'] = not (result['missing'] or result['unsupported'] or result['errors'])
    result['status'] = 'PASS' if result['target_ready'] else 'BLOCKED'
    return result

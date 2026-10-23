#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

"""Audit source inventory. This is not a legal opinion or similarity detector."""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {'.git', '.build', 'target', 'work', 'local-state', '__pycache__'}
TEXT_SUFFIXES = {'.rs','.toml','.lock','.swift','.h','.sh','.md','.json','.hex','.yml','.yaml','.py','.strings','.rtf','.html','.css','.svg','.xml'}
OWN_ASSETS = {'resources/branding/shark.png', 'resources/branding/Shark.icns'}

def source_files():
    for path in sorted(ROOT.rglob('*')):
        rel=path.relative_to(ROOT)
        if any(p in SKIP_DIRS or p.endswith('.app') for p in rel.parts) or path.name == '.DS_Store': continue
        if path.is_file() and path.suffix not in {'.zip', '.dmg'}: yield path

def audit():
    failures=[]
    inventory=[]
    for path in source_files():
        rel=path.relative_to(ROOT).as_posix()
        if path.is_symlink(): failures.append(f'Symlink is not allowed: {rel}');continue
        data=path.read_bytes()
        if rel not in OWN_ASSETS:
            if path.suffix not in TEXT_SUFFIXES and path.name not in {'LICENSE','.gitignore','.nojekyll'}:
                failures.append(f'Unrecognized source file: {rel}')
            try: text=data.decode('utf-8')
            except UnicodeDecodeError:
                failures.append(f'Unexpected binary file: {rel}');continue
            if re.search(r'^00[4-5][0-9a-f]{5}\s{2}(?:mov|push|call|jmp)\s',text,re.M):
                failures.append(f'Looks like disassembled manufacturer code: {rel}')
            if ('/' + 'Users/') in text:
                failures.append(f'Absolute local user path: {rel}')
        if data.startswith(b'MZ'): failures.append(f'Windows executable: {rel}')
        inventory.append({'path':rel,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    if failures:
        print('\n'.join(failures),file=sys.stderr);return 1
    print(json.dumps({'result':'pass','scope':'source inventory; not a legal guarantee','fileCount':len(inventory),'files':inventory},indent=2))
    return 0

if __name__=='__main__': sys.exit(audit())

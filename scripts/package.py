#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

"""Package the audited sources and the built app without extended attributes."""
from pathlib import Path
import importlib.util
import os
import stat
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('source_audit',ROOT/'scripts/audit_source.py')
audit=importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

def write_archive(destination, paths, prefix):
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for source, relative in paths:
            info=zipfile.ZipInfo((Path(prefix)/relative).as_posix())
            info.date_time=(2026,10,20,0,0,0)
            info.create_system=3
            info.external_attr=(stat.S_IFREG | (0o755 if os.access(source,os.X_OK) else 0o644)) << 16
            info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,source.read_bytes())
    print(destination)

if audit.audit(): sys.exit(1)
destination=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT.parent
destination.mkdir(parents=True,exist_ok=True)
write_archive(destination/'L99-for-Mac-source.zip',[(p,p.relative_to(ROOT)) for p in audit.source_files()],'L99-for-Mac')
app=ROOT/'L99 for Mac.app'
if app.is_dir():
    write_archive(destination/'L99-for-Mac-macOS-arm64.zip',[(p,p.relative_to(app)) for p in sorted(app.rglob('*')) if p.is_file()],'L99 for Mac.app')

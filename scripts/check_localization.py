#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

"""Check catalog coverage, interpolation safety, and localized permission prompts."""
from collections import Counter
from pathlib import Path
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
LANGUAGES=('ru','en','zh-Hans')
NATIVE_NAMES={'Русский'}

def expression(source,index):
    start=index;depth=1
    while index<len(source):
        if source[index]=='"':index,_,_=literal(source,index);continue
        if source[index]=='(':depth+=1
        if source[index]==')':
            depth-=1
            if depth==0:return index+1,source[start:index]
        index+=1
    raise ValueError('Unclosed Swift interpolation')

def literal(source,index):
    index+=1;pieces=[];nested=[];value='';arguments=0
    while index<len(source):
        if source[index]=='"':return index+1,''.join(pieces)+value,nested
        if source[index]=='\\' and index+1<len(source):
            escaped=source[index+1]
            if escaped=='(':
                pieces.extend((value,'{'+str(arguments)+'}'));value='';arguments+=1
                index,code=expression(source,index+2);nested.append(code);continue
            value+={'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\'}.get(escaped,'\\'+escaped);index+=2;continue
        value+=source[index];index+=1
    raise ValueError('Unclosed Swift string')

def messages(source):
    index=0
    while index<len(source):
        if source.startswith('//',index):
            end=source.find('\n',index);index=len(source) if end<0 else end;continue
        if source.startswith('/*',index):
            end=source.find('*/',index+2);index=len(source) if end<0 else end+2;continue
        if source[index]!='"':index+=1;continue
        end,key,nested=literal(source,index)
        if re.search('[А-Яа-яЁё]',key) or re.search(r'\bT\(\s*$',source[max(0,index-20):index]):yield key
        for code in nested:yield from messages(code)
        index=end

def markers(value):
    return Counter(re.findall(r'\{\d+\}|%(?:\d+\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(?:ll|l|z)?[@diuoxXfFeEgGs]',value))

def main():
    catalogs={code:json.loads((ROOT/'resources/localization'/f'{code}.json').read_text()) for code in LANGUAGES}
    base=catalogs['ru'];failures=[]
    for code,catalog in catalogs.items():
        if set(catalog)!=set(base):failures.append(f'{code}: key set differs from Russian')
        for key,value in catalog.items():
            if not value or markers(key)!=markers(value):failures.append(f'{code}: empty value or changed placeholders: {key}')
            if code!='ru' and re.search('[А-Яа-яЁё]',value):failures.append(f'{code}: untranslated Russian: {key}')
        permission=ROOT/'macos/Localizations'/f'{code}.lproj/InfoPlist.strings'
        if not permission.is_file() or 'NSAudioCaptureUsageDescription' not in permission.read_text():failures.append(f'{code}: missing audio permission translation')
    for path in (ROOT/'macos').glob('*.swift'):
        for key in messages(path.read_text()):
            if key not in base and key not in NATIVE_NAMES:failures.append(f'{path.name}: uncatalogued message: {key}')
    if failures:
        print('\n'.join(failures),file=sys.stderr);return 1
    print(f'PASS: {len(base)} messages in {len(catalogs)} languages; source coverage, placeholders, and permission prompts checked')
    return 0

if __name__=='__main__':sys.exit(main())

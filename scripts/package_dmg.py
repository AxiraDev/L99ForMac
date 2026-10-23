#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

"""Build a drag-to-Applications image; no app installation or security changes."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

from ds_store import DSStore
from mac_alias import Alias

ROOT=Path(__file__).resolve().parents[1]
APP=ROOT/'L99 for Mac.app'
BUILD=Path(os.environ.get('L99_BUILD_ROOT',ROOT/'.build')).resolve()
OUTPUT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT.parent/'L99-for-Mac-macOS-arm64.dmg'

def run(*args):
    result=subprocess.run([str(a) for a in args],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    return result.stdout

def copy_file(source,destination):
    shutil.copyfile(source,destination)
    os.chmod(destination,os.stat(source).st_mode & 0o777)
    return destination

def main():
    if not (APP/'Contents/MacOS/L99forMac').is_file():raise RuntimeError('Build the app first.')
    if OUTPUT.suffix.lower()!='.dmg':raise ValueError('Output must be a .dmg file.')
    BUILD.mkdir(parents=True,exist_ok=True);OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='l99-dmg-') as temporary:
        temp=Path(temporary);payload=temp/'payload';payload.mkdir()
        shutil.copytree(APP,payload/APP.name,copy_function=copy_file)
        os.symlink('/Applications',payload/'Applications')
        background=payload/'.background';background.mkdir()
        renderer=temp/'render-background'
        run('swiftc','-module-cache-path',BUILD/'swift-cache',ROOT/'scripts/DMGBackground.swift','-framework','AppKit','-o',renderer)
        run(renderer,background/'Install.png')
        run('codesign','--verify','--deep','--strict',payload/APP.name)
        writable=temp/'writable.dmg'
        run('hdiutil','create','-size','64m','-fs','HFS+','-volname','L99 for Mac','-srcfolder',payload,'-format','UDRW',writable)
        attachment=plistlib.loads(run('hdiutil','attach','-nobrowse','-noautoopen','-readwrite','-plist',writable))
        mount=Path(next(item['mount-point'] for item in attachment['system-entities'] if 'mount-point' in item))
        try:
            alias=Alias.for_file(str(mount/'.background/Install.png')).to_bytes()
            with DSStore.open(str(mount/'.DS_Store'),'w+') as store:
                store['.']['bwsp']={'ShowToolbar':False,'ShowStatusBar':False,'ShowTabView':False,'ShowPathbar':False,'ShowSidebar':False,'WindowBounds':'{{240, 160}, {660, 480}}','ContainerShowSidebar':False}
                store['.']['icvp']={'viewOptionsVersion':1,'backgroundType':2,'backgroundColorRed':1.0,'backgroundColorGreen':1.0,'backgroundColorBlue':1.0,'backgroundImageAlias':alias,'iconSize':112.0,'textSize':14.0,'labelOnBottom':True,'showItemInfo':False,'showIconPreview':False,'arrangeBy':'none','gridOffsetX':0.0,'gridOffsetY':0.0,'gridSpacing':100.0,'scrollPositionX':0.0,'scrollPositionY':0.0}
                store['.']['vSrn']=('long',1)
                store['.']['icvl']=('type',b'icnv')
                store[APP.name]['Iloc']=(170,210)
                store['Applications']['Iloc']=(490,210)
            run('codesign','--verify','--deep','--strict',mount/APP.name)
        finally:
            run('hdiutil','detach',mount)
        compressed=temp/'release.dmg'
        run('hdiutil','convert',writable,'-format','UDZO','-imagekey','zlib-level=9','-o',compressed)
        run('hdiutil','verify',compressed)
        next_file=OUTPUT.with_suffix('.dmg.next')
        shutil.copyfile(compressed,next_file);os.replace(next_file,OUTPUT)
    print(OUTPUT)

if __name__=='__main__':
    try:main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr.decode(errors='replace'));sys.exit(error.returncode)

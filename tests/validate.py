#!/usr/bin/env python3
"""Static release checks and scoped preservation against the identified original."""
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
ADDON=ROOT/'CharacterMemory'
BASELINE='a1b3b249b5d2978815b4f9c02ce1faba8fef00e8'
NS={'ui':'http://www.blizzard.com/wow/ui/'}
lua=LuaRuntime(unpack_returned_tuples=True)
compile_lua=lua.eval('function(s,n) local f,e=loadstring(s,n); return f~=nil,e end')
checks=[]
def check(value,name):
    assert value,name
    checks.append(name)
def original(name):
    return subprocess.run(['git','show',BASELINE+':'+name],cwd=ROOT,check=True,capture_output=True).stdout
for path in sorted(ADDON.glob('*.lua')):
    ok,error=compile_lua(path.read_text(),'@'+str(path))
    check(ok,str(path.relative_to(ROOT))+': '+str(error or 'Lua 5.1 syntax'))
manifest=(ADDON/'CharacterMemory.toc').read_text()
check('## Interface: 16001' in manifest,'Forever Interface 16001')
for name in manifest.splitlines():
    if name.strip().endswith(('.lua','.xml')):
        check((ADDON/name.strip()).is_file(),'TOC file exists: '+name)
for path in ADDON.glob('*.xml'):
    root=ET.parse(path).getroot()
    check(True,path.name+' parses')
    for node in root.iter():
        tag=node.tag.rsplit('}',1)[-1]
        if tag.startswith('On') or tag=='Binding':
            script='return function(self,...) local button,offset=...; '+''.join(node.itertext())+' end'
            ok,error=compile_lua(script,'@'+path.name+':'+tag)
            check(ok,path.name+': '+tag+' syntax '+str(error or ''))
# Every original art file remains byte-identical, with compatible copies added separately.
tracked=subprocess.run(['git','ls-tree','-r','--name-only',BASELINE,'CharacterMemory/Art','CharacterMemory/media'],cwd=ROOT,check=True,text=True,capture_output=True).stdout.splitlines()
for name in tracked:
    check((ROOT/name).read_bytes()==original(name),'Original artwork unchanged: '+name)
for stem in ['cmjournal','CMcompact']:
    source=Image.open(ADDON/'media'/f'{stem}.png').convert('RGBA')
    copy=Image.open(ADDON/'media'/f'{stem}.tga').convert('RGBA')
    check(all(d>0 and d&(d-1)==0 for d in copy.size),stem+' TGA dimensions are powers of two')
    check(copy.crop((0,0,*source.size)).tobytes()==source.tobytes(),stem+' TGA preserves original RGBA pixels')
old=ET.fromstring(original('CharacterMemory/CharacterMemory.xml')); new=ET.parse(ADDON/'CharacterMemory.xml').getroot()
for frame_name in ['CMJ_RootXML','$parentPageL','$parentPageR','$parentTabBar']:
    query=".//ui:Frame[@name='"+frame_name+"']"
    a,b=old.find(query,NS),new.find(query,NS)
    for tag in ['Size','Anchors']:
        x,y=a.find('ui:'+tag,NS),b.find('ui:'+tag,NS)
        check((ET.tostring(x) if x is not None else None)==(ET.tostring(y) if y is not None else None),frame_name+' original '+tag)
for name in ['TabOverview','TabProfile','TabNotes','TabAchievements']:
    query=".//ui:Button[@name='$parent"+name+"']"
    check(old.find(query,NS).get('text')==new.find(query,NS).get('text'),name+' retained')
texture=next(n for n in new.iter() if n.get('file','').endswith('/cmjournal.tga'))
check(texture.find('ui:TexCoords',NS).get('right')=='0.75','Journal XML crops TGA padding')
# Local texture references in shipped declarations must exist with their exact case.
for path in ADDON.glob('*'):
    if path.suffix not in {'.lua','.xml','.toc'}: continue
    text=path.read_text().replace('\\','/')
    for ref in re.findall(r'Interface/AddOns/CharacterMemory/([A-Za-z0-9_./-]+\.(?:png|tga|blp))',text):
        check((ADDON/ref).is_file(),path.name+' texture '+ref)
hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ADDON.rglob('*')) if p.is_file()}
print(json.dumps({'baseline':BASELINE,'checks_passed':len(checks),'checks':checks,'addon_sha256':hashes,'limits':'No in-game rendering/runtime evidence'},indent=2))

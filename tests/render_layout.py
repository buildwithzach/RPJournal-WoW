#!/usr/bin/env python3
"""Source-driven geometry previews. Native skins/font rendering are approximations."""
import argparse
from pathlib import Path
from PIL import Image,ImageDraw
from run import Client
from geometry import Geometry,font_for
ROOT=Path(__file__).resolve().parents[1]

def render(client,root,path,title,book=False):
    geo=Geometry(client);_,_,rw,rh=geo.rect(root);rw,rh=round(rw),round(rh)
    image=Image.new('RGB',(rw+32,rh+64),'#111519');draw=ImageDraw.Draw(image)
    draw.text((16,10),title+' · SOURCE LAYOUT / APPROXIMATE SKIN',font=font_for(12),fill='#e5e8ec')
    if book:
        background=Image.open(ROOT/'CharacterMemory/media/cmjournal.png').convert('RGB').resize((rw,rh))
        image.paste(background,(16,40))
    else:draw.rounded_rectangle((16,40,16+rw,40+rh),radius=4,fill='#232628',outline='#87847a',width=2)
    for f in geo.descendants(root):
        if not geo.shown(f,root):continue
        try:x,y,w,h=geo.relative(f,root)
        except ValueError:continue
        if w<=0 or h<=0:continue
        x,y=round(x+16),round(y+40);w,h=round(w),round(h)
        if x<14 or y<38 or x+w>rw+18 or y+h>rh+42:continue
        # Clip scrolling pages to their viewport. Descendants below the fold are intentional.
        parent=f.parent;clipped=False;bottom_clip=rh+42
        while parent is not None and parent.mockID!=root.mockID:
            if parent.kind=='ScrollFrame':
                if not geo.contains(parent,f,6):clipped=True;break
                _,sy,_,sh=geo.relative(parent,root);bottom_clip=min(bottom_clip,round(sy+40+sh))
            parent=parent.parent
        if clipped:continue
        template=f.template or '';text=geo.text(f);size=geo.font_size(f)
        if f.kind=='Button' and f._cmIsRow:
            if f.selBG and f.selBG.shown:draw.rectangle((x,y,x+w,y+h),fill='#bd9043')
            draw.line((x,y+h,x+w,y+h),fill='#a77932');continue
        if f.kind=='Button':
            draw.rounded_rectangle((x,y,x+w,y+h),radius=2,fill='#641b17' if f.enabled is not False else '#352825',outline='#a28a58')
            font=font_for(11);tw=font.getlength(text);draw.text((x+max(2,(w-tw)/2),y+4),text,font=font,fill='#f5d57a')
            continue
        if 'UIDropDownMenuTemplate' in template:
            draw.rectangle((x+16,y+4,x+w,y+h-4),fill='#141719',outline='#77766f');draw.text((x+24,y+9),f.label or 'Not specified',font=font_for(11),fill='#e7e5df');continue
        if f.kind=='CheckButton':
            draw.rectangle((x+3,y+3,x+20,y+20),fill='#141719',outline='#8f8b7c')
            if f.checked:draw.text((x+6,y+2),'✓',font=font_for(14),fill='#f6d475')
            continue
        if 'InputScrollFrameTemplate' in template or f.kind=='EditBox' and 'InputBoxTemplate' in template:
            fill='#c5994a' if book and (f.frameName or '').endswith('NotesScroll') else '#111516'
            draw.rectangle((x,y,x+w,y+h),fill=fill,outline='#7c796d')
        if f.kind not in ('FontString','EditBox') or not text:continue
        if f.color:color=tuple(round(float(f.color[i])*255) for i in (1,2,3))
        elif isinstance(f.font,str) and 'Disable' in f.font:color='#aeb1b3'
        elif isinstance(f.font,str) and 'Highlight' in f.font:color='#e5e6e5'
        else:color='#f1d379'
        font=font_for(size);lines=[]
        for paragraph in text.split('\n'):
            line=''
            for word in paragraph.split(' '):
                trial=(line+' '+word).strip()
                if font.getlength(trial)>w and line:lines.append(line);line=word
                else:line=trial
            lines.append(line)
        maxlines=int(f.maxLines or (len(lines) if f.kind=='FontString' and not f.height else max(1,h//(size+3))))
        for i,line in enumerate(lines[:maxlines]):
            if y+i*(size+3)+size>bottom_clip:break
            while font.getlength(line)>w and line:line=line[:-1]
            draw.text((x,y+i*(size+3)),line,font=font,fill=color)
    image.save(path)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    c=Client();g=c.g
    g.CharacterMemory_OpenCharacterSheet()
    for name in ['Identity','Appearance','Story','Preferences','Notes']:
        g.RPBioUI.ShowPage(name);render(c,g.RPBioFrame,args.output/('sheet-'+name.lower()+'.png'),'MY CHARACTER / '+name)
    g.RPBioFrame.Hide(g.RPBioFrame);g.CM_OptionsPanel.Show(g.CM_OptionsPanel)
    render(c,g.CM_OptionsPanel,args.output/'settings.png','PREFERENCES')
    g.CM_OptionsPanel.Hide(g.CM_OptionsPanel)
    for i in range(10):
        e=c.entry('Player-1-FRIEND'+str(i));e.name='AlderiantheCartographer-FictionalRealm' if i==0 else ['Elara','Mara','Thalen','Rowan','Rin'][i%5];e.race='Human';e.guildName='The Order of the Silver Quill';e.stats.firstMeets=1
    c.target();g.CMJ.Toggle()
    for page in ['Overview','Notes','Achievements']:
        g.CMUI.TabSwap(page);render(c,g.CMJ.refs.root,args.output/('journal-'+page.lower()+'.png'),'JOURNAL / '+page,True)

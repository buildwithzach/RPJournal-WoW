"""Resolve recorded anchor rectangles. This audits geometry, not WoW rendering."""
import math
from functools import lru_cache
import re
from PIL import ImageFont
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
@lru_cache(maxsize=12)
def font_for(size):
    try: return ImageFont.truetype(FONT,size)
    except OSError:
        try: return ImageFont.truetype("DejaVuSans.ttf",size)
        except OSError: return ImageFont.load_default()
FACTORS={'TOPLEFT':(0,0),'TOP':(.5,0),'TOPRIGHT':(1,0),'LEFT':(0,.5),'CENTER':(.5,.5),'RIGHT':(1,.5),'BOTTOMLEFT':(0,1),'BOTTOM':(.5,1),'BOTTOMRIGHT':(1,1)}
class Geometry:
    def __init__(self, client): self.c=client;self.cache={};self.visiting=set()
    def font_size(self,f):
        font=f.font or f.template or ''
        return 16 if isinstance(font,str) and 'Large' in font else 11 if isinstance(font,str) and 'Small' in font else 12
    def text(self,f): return re.sub(r'\|c[0-9a-fA-F]{8}|\|r','',f.textValue or '')
    def rect(self,f):
        if f is None: return (0,0,0,0)
        key=f.mockID
        if key in self.cache:return self.cache[key]
        if key in self.visiting:raise ValueError('Anchor cycle: '+str(f.frameName))
        self.visiting.add(key)
        font=font_for(self.font_size(f))
        text=self.text(f); default_w=max(1,max((font.getlength(s) for s in text.split('\n')),default=1))
        w,h=f.width or (default_w if f.kind=='FontString' else 0),f.height or (self.font_size(f)+3 if f.kind=='FontString' else 0)
        anchors=[]
        for point in (f.points.values() if f.points else []):
            args=list(point.values());p=args[0];parent=f.parent
            if len(args)>1 and isinstance(args[1],(int,float)):
                relative=parent;rp=p;dx=args[1];dy=args[2] if len(args)>2 else 0
            else:
                relative=args[1] if len(args)>1 and args[1] is not None else parent
                rp=args[2] if len(args)>2 and isinstance(args[2],str) else p
                dx=args[3] if len(args)>3 else 0;dy=args[4] if len(args)>4 else 0
            if isinstance(relative,str):relative=self.c.g[relative]
            rx,ry,rw,rh=self.rect(relative)
            a,b=FACTORS[p],FACTORS[rp]
            anchors.append((a[0],a[1],rx+b[0]*rw+dx,ry+b[1]*rh-dy))
        def axis(index,extent):
            coords=[(a[index],a[index+2]) for a in anchors]
            left=next((v for p,v in reversed(coords) if p==0),None);right=next((v for p,v in reversed(coords) if p==1),None)
            if left is not None and right is not None:return left,right-left
            if not extent and len(coords)>1:
                for ratio,value in reversed(coords):
                    for other_ratio,other_value in coords:
                        if ratio!=other_ratio:
                            inferred=(value-other_value)/(ratio-other_ratio)
                            return value-ratio*inferred,inferred
            if left is not None:return left,extent
            if right is not None:return right-extent,extent
            if coords:return coords[-1][1]-coords[-1][0]*extent,extent
            return 0,extent
        x,w=axis(0,w);y,h=axis(1,h)
        self.visiting.remove(key);self.cache[key]=(x,y,w,h)
        return self.cache[key]
    def relative(self,f,parent):
        x,y,w,h=self.rect(f);px,py,_,_=self.rect(parent);return x-px,y-py,w,h
    def shown(self,f,root=None):
        while f is not None:
            if not f.shown:return False
            if root is not None and f.mockID==root.mockID:return True
            f=f.parent
        return root is None
    def descendants(self,root):
        for f in self.c.g.MOCK.frames.values():
            p=f
            while p is not None:
                if p.mockID==root.mockID:yield f;break
                p=p.parent
    def contains(self,outer,inner,padding=0):
        x,y,w,h=self.rect(outer);a,b,c,d=self.rect(inner)
        return w>0 and h>0 and a>=x-padding and b>=y-padding and a+c<=x+w+padding and b+d<=y+h+padding
    def overlaps(self,a,b):
        x,y,w,h=self.rect(a);i,j,k,l=self.rect(b)
        return min(x+w,i+k)-max(x,i)>.5 and min(y+h,j+l)-max(y,j)>.5

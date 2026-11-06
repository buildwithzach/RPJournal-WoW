"""Extract the complete native widget/style declarations, excluding behavior callbacks."""
import re
STYLE = r'CreateFontString|SetPoint|SetAllPoints|SetSize|SetWidth|SetHeight|SetScale|SetFont|SetFontObject|SetTextColor|SetJustifyH|SetJustifyV|SetMaxLines|SetFrameStrata|SetHighlightTexture|SetTexture|SetTexCoord|SetBackdrop|SetBackdropColor|SetBackdropBorderColor|SetNormalTexture|SetPushedTexture|SetDisabledTexture|SetAlpha'
CALL = re.compile(r'\bCreateFrame\s*\(|:\s*(?:'+STYLE+r')\s*\(')

def protected_source(source,name):
    # Explicitly authorized additions: navigation inside the reader, never the journal pages.
    marker='-- Navigation belongs to the existing reader, not the main journal pages.'
    if name=='CM_Journey.lua' and marker in source:
        a=source.index(marker);b=source.index('-- End reader navigation.',a)+len('-- End reader navigation.')
        source=source[:a]+source[b:].lstrip("\n")
    if name=='CM_ChronicleUI.lua':
        source=source.replace('      U.Open(row.item)','      U.selected = row.item\n      U.Refresh(U.guid)')
    return source

def declarations(source):
    calls=[]
    for match in CALL.finditer(source):
        start=match.start(); pos=match.end(); depth=1; quote=None; escaped=False
        while pos<len(source) and depth:
            ch=source[pos]
            if quote:
                if escaped: escaped=False
                elif ch=='\\': escaped=True
                elif ch==quote: quote=None
            elif ch in '\"\'': quote=ch
            elif ch=='(': depth+=1
            elif ch==')': depth-=1
            pos+=1
        if depth: raise ValueError('Unclosed style declaration')
        calls.append(source[start:pos])
    return {'calls':calls,'font_objects':re.findall(r'\bGameFont\w*',source),'inline_palette':sorted(set(re.findall(r'\|c[0-9a-fA-F]{8}',source)))}

def constructors(source, name):
    source=protected_source(source,name)
    def section(start,end): return source[source.index(start):source.index(end,source.index(start))]
    if name=='CM_ChronicleUI.lua':
        editor=section('local function buildEditor(root)','function U.ResumeDraft(')
        # Save's behavior can evolve; its button, placement, fonts and controls remain fixed.
        start=editor.index('function()',editor.index('  editor.save = button('))+len('function()')
        end=editor.index('\n  end)\n  editor.save:SetPoint',start)
        editor=editor[:start]+'\n    -- Save behavior is checked by integration tests.'+editor[end:]
        return {'helpers':source[:source.index('local function person(')],'editor':editor,
                'pages':section('function U.Build(root)','function U.Refresh('),
                'public_profile':section('function U.ShowProfile(', 'StaticPopupDialogs["CMJ_CONFIRM_REMOVE_PAGE"]')}
    return {'helpers':section('local function label(', 'function J.Read('),
            'reader':section('  if not J.reader then', '  local e, f = entry(guid), J.reader'),
            'notice':section('  if not J.notice then', '  local f = J.notice')}

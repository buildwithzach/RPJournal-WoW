#!/usr/bin/env python3
"""Load the actual TOC/FrameXML scripts under synthetic Lua 5.1 APIs.
Requires: python -m pip install lupa
No rendering, live game, SavedVariables disk-write or network compatibility is implied.
"""
import json
import hashlib
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from lupa.lua51 import LuaRuntime, lua_type
ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'CharacterMemory'
sys.path.insert(0,str(ROOT/'tests'))
from geometry import Geometry
from presentation import declarations, constructors, protected_source
CLIENT_GUARD = 'if not CMCompat or not CMCompat.supported then return end\n'
def presentation_source(path):
    source = path.read_text()
    return source[len(CLIENT_GUARD):] if source.startswith(CLIENT_GUARD) else source

TAG = lambda node: node.tag.rsplit('}', 1)[-1]


def plain(value):
    return {k: plain(v) for k, v in value.items()} if lua_type(value) == 'table' else value


class Client:
    def __init__(self, saved=None, setup=''):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
        self.g = self.lua.globals()
        self.templates = {}
        self.xml_anchors = []
        if saved:
            self.g.CharacterMemoryDB = self.table(saved)
        if setup:
            self.lua.execute(setup)
        for line in (ADDON / 'CharacterMemory.toc').read_text().splitlines():
            name = line.strip()
            if name.endswith('.lua'):
                self.chunk((ADDON / name).read_text(), name)('CharacterMemory')
            elif name.endswith('.xml'):
                for node in ET.parse(ADDON / name).getroot():
                    if node.get('virtual') == 'true':
                        self.templates[node.get('name')] = node
                    else:
                        self.xml_frame(node)
        self.apply_anchors()
        self.emit('ADDON_LOADED', 'CharacterMemory')
        self.emit('PLAYER_LOGIN')

    def table(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k: self.table(v) for k,v in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.table(v) for v in value])
        return value

    def chunk(self, source, name):
        chunk = self.lua.eval('loadstring')(source, '@' + name)
        if isinstance(chunk, tuple):
            raise ValueError(chunk[1])
        return chunk

    def xml_frame(self, node, parent=None):
        kind = TAG(node)
        name = node.get('name')
        if name and '$parent' in name:
            name = name.replace('$parent', parent.GetName(parent) or '')
        if node.get('parent'):
            parent = self.g[node.get('parent')]
        inherits = node.get('inherits', '')
        frame = self.g.CreateFrame(kind, name, parent, inherits)
        if parent is not None and node.get('parentKey'):
            parent[node.get('parentKey')] = frame
        for base in inherits.split(','):
            if base.strip() in self.templates:
                self.xml_contents(self.templates[base.strip()], frame)
        self.xml_contents(node, frame)
        if kind == "FontString": frame.font = inherits
        frame.Run(frame, 'OnLoad')
        return frame

    def xml_contents(self, node, frame):
        if node.get('hidden') is not None:
            frame.shown = node.get('hidden') != 'true'
        if node.get('text') is not None:
            frame.SetText(frame, node.get('text'))
        if node.get('file'):
            frame.SetTexture(frame, node.get('file'))
        for child in node:
            kind = TAG(child)
            if kind == 'Size':
                dim = next(iter(child), child)
                if dim.get('x'):
                    frame.SetWidth(frame, float(dim.get('x')))
                if dim.get('y'):
                    frame.SetHeight(frame, float(dim.get('y')))
            elif kind == 'Anchors':
                for anchor in child: self.xml_anchors.append((frame, anchor))
            elif kind == 'Color':
                frame.SetTextColor(frame, float(child.get('r',1)),float(child.get('g',1)),float(child.get('b',1)))
            elif kind == 'Scripts':
                for script in child:
                    source = ''.join(script.itertext())
                    callback = self.chunk('return function(self, ...) local button, offset = ...; '+source+' end', (frame.GetName(frame) or 'anonymous')+':'+TAG(script))()
                    frame.SetScript(frame, TAG(script), callback)
            elif kind in ('Frames', 'ScrollChild'):
                for item in child:
                    childframe=self.xml_frame(item, frame)
                    if kind=='ScrollChild': frame.SetScrollChild(frame,childframe)
            elif kind == 'Layers':
                for layer in child:
                    for item in layer:
                        self.xml_frame(item, frame)

    def apply_anchors(self):
        for frame,node in self.xml_anchors:
            parent=frame.GetParent(frame)
            relative=parent
            if node.get('relativeTo'):
                name=node.get('relativeTo').replace('$parent',parent.GetName(parent) or '')
                relative=self.g[name]
            elif node.get('relativeKey'):
                relative=parent
                for part in node.get('relativeKey').replace('$parent.','').split('.'):
                    relative=relative[part] if relative is not None else None
            if relative is None: continue
            dim=node
            for child in node:
                dim=next(iter(child),child)
            frame.SetPoint(frame,node.get('point'),relative,node.get('relativePoint',node.get('point')),float(dim.get('x',0)),float(dim.get('y',0)))

    def emit(self, name, *args): self.g.MOCK.Emit(name, *args)
    def advance(self, seconds): self.g.MOCK.Advance(seconds)
    def click(self, frame): self.g.MOCK.Click(frame)
    def target(self): self.emit('PLAYER_TARGET_CHANGED'); return self.g.CharacterMemoryDB.entries['Player-1-ELARA']
    def entry(self, guid): return self.g.CharacterMemory_GetOrCreateEntry(guid)


class JournalTests(unittest.TestCase):
    def setUp(self): self.c=Client(); self.g=self.c.g

    def test_encounters_and_no_transcripts(self):
        e=self.c.target()
        self.assertEqual((e.xp,e.stats.firstMeets,e.metCount),(50,1,1))
        self.c.target(); self.assertEqual(e.metCount,1)
        self.c.emit('CHAT_MSG_WHISPER','PRIVATE CHAT TRANSCRIPT','Elara-OtherRealm')
        self.assertEqual(e.stats.whispers,0)
        self.c.emit('CHAT_MSG_WHISPER','PRIVATE CHAT TRANSCRIPT','Elara-FictionalRealm')
        self.assertEqual(e.stats.whispers,1)
        target=self.g.MOCK.units.target; self.g.MOCK.units.target=None; self.c.emit('PLAYER_TARGET_CHANGED')
        self.c.advance(601); self.g.MOCK.units.target=target; self.c.target()
        self.assertEqual(e.stats.reconnects,1)
        self.assertEqual(e.metCount,2)
        self.assertNotIn('PRIVATE CHAT TRANSCRIPT',json.dumps(plain(self.g.CharacterMemoryDB)))
        self.assertIsNone(self.c.entry('Creature-0-123'))

    def test_rank_gate_cannot_be_skipped(self):
        e=self.c.entry('Player-1-RANK')
        self.g.CharacterMemory_AwardXP(e.guid,400,'probe')
        self.assertEqual(e.level,0)
        e.stats.firstMeets,e.stats.whispers,e.stats.dungeonCompletions=1,10,1
        self.assertEqual(self.g.CharacterMemory_GetAchievementSummary(e.guid).done,3)
        self.g.CharacterMemory_AwardXP(e.guid,1,'probe')
        self.assertEqual(e.level,2)
        e2=self.c.entry('Player-1-RANK2'); e2.stats.firstMeets,e2.stats.whispers,e2.stats.dungeonCompletions=1,10,1
        self.g.CharacterMemory_AwardXP(e2.guid,100,'probe'); self.assertEqual(e2.level,1)
        restored=Client(plain(self.g.CharacterMemoryDB))
        self.assertEqual(restored.g.CharacterMemoryDB.entries[e.guid].level,2)
        e.stats.whispers=0
        self.g.CharacterMemory_AwardXP(e.guid,1,'probe')
        self.assertEqual(e.level,2)  # An earned relationship stays unlocked.

    def test_migration_reload_and_bounded_storage(self):
        c=Client({'version':1,'entries':{'Player-1-OLD':{'notes':'My old note','name':'Old','xp':100}},'settings':{}})
        e=c.g.CharacterMemoryDB.entries['Player-1-OLD']
        self.assertEqual(e.notes,'My old note'); self.assertEqual(e.memories[1].note,e.notes); self.assertTrue(e.memories[1].pinned)
        e2=Client(plain(c.g.CharacterMemoryDB)).g.CharacterMemoryDB.entries['Player-1-OLD']
        self.assertEqual(len(e2.memories),1)
        m=c.g.CMChronicle
        for i in range(99): self.assertTrue(m.Remember(e.guid,None,'words',f'Memory {i}'))
        self.assertFalse(m.Remember(e.guid,None,'words','Overflow')[0]); self.assertEqual(len(e.memories),100)
        for i in range(32): self.assertTrue(m.AddStory(e.guid,f'Story {i}','words'))
        self.assertFalse(m.AddStory(e.guid,'Overflow','words')[0]); self.assertEqual(len(e.stories),32)
        for i in range(12): c.advance(1201); self.assertTrue(m.Offer(e.guid,'conversation','Goldshire'))
        c.advance(1201); self.assertFalse(m.Offer(e.guid,'conversation','Goldshire')); self.assertEqual(len(e.memoryCandidates),12)

    def test_notes_edit_selection_search_and_pages(self):
        e=self.c.target(); self.g.CMJ.Toggle(); self.g.CMUI.Select(e.guid)
        refs=self.g.CMJ.refs
        self.g.MOCK.Type(refs.noteEdit,'A promise about a map.')
        self.assertEqual(e.notes,'A promise about a map.')
        refs.noteEdit.SetFocus(refs.noteEdit)
        self.g.CharacterMemory_AwardXP(e.guid,10,'probe')
        self.assertEqual(refs.noteEdit.GetText(refs.noteEdit),'A promise about a map.')
        for i in range(18): self.c.entry(f'Player-1-{i}').name=f'Friend {i}'
        self.g.CMJ.NotifyDataChanged(); self.g.CMUI.Select('Player-1-9')
        selected=self.g.CMJ.Model.selected; page=self.g.CMJ.Model.page
        self.g.CMJ.Toggle(); self.g.CMJ.Toggle()
        self.assertEqual((self.g.CMJ.Model.selected,self.g.CMJ.Model.page),(selected,page))
        self.g.MOCK.Type(refs.search,'Elara'); self.assertEqual(len(self.g.CMJ.Model.order),1)
        self.assertEqual(self.g.CMJ.Model.selected,e.guid)
        self.g.MOCK.Type(refs.search,'[literal]'); self.assertEqual(len(self.g.CMJ.Model.order),0)
        self.assertEqual(self.g.CMJ.Model.page,1)
        self.assertEqual((refs.root.GetWidth(refs.root),refs.root.GetHeight(refs.root)),(1024,512))

    def test_native_memory_and_story_controls(self):
        e=self.c.target(); self.g.CMJ.Toggle(); self.g.CMUI.Select(e.guid); self.g.CMUI.TabSwap('Notes')
        u=self.g.CMChronicleUI; u.SetMode('memories')
        self.c.click(u.rows[1]); self.assertEqual(u.edit.GetText(u.edit),'Keep')
        self.c.click(u.edit); u.editor.bodyInput.SetText(u.editor.bodyInput,'She asked about the old road.')
        self.c.click(u.editor.save); self.assertEqual(len(e.memories),1); self.assertEqual(len(e.memoryCandidates),0)
        self.c.click(u.rows[1]); self.c.click(u.pin); self.assertTrue(e.memories[1].pinned)
        self.c.click(u.edit); u.editor.titleInput.SetText(u.editor.titleInput,'An old road'); self.c.click(u.editor.save)
        self.assertEqual(e.memories[1].title,'An old road')
        self.c.click(u.remove); self.assertEqual(len(e.memories),1); self.g.MOCK.AcceptPopup(); self.assertEqual(len(e.memories),0)
        u.SetMode('stories'); self.c.click(u.add)
        u.editor.titleInput.SetText(u.editor.titleInput,'Return the map'); self.c.click(u.editor.save)
        self.assertEqual(e.stories[1].state,'open'); self.c.click(u.rows[1]); self.c.click(u.pin)
        self.assertEqual(e.stories[1].state,'resolved'); self.c.click(u.pin); self.assertEqual(e.stories[1].state,'open')
        self.c.click(u.favorite); self.assertTrue(e.favorite)
        self.g.MOCK.tooltip(self.g.GameTooltip); self.assertIn('Return the map',self.g.GameTooltip.lines[2])

    def test_combat_secret_values_and_trade_confirmation(self):
        e=self.c.target(); self.g.CMJ.Toggle(); root=self.g.CMJ.refs.root
        self.g.MOCK.combat=True; self.c.emit('PLAYER_REGEN_DISABLED'); self.assertFalse(root.IsShown(root))
        self.c.target(); self.g.MOCK.combat=False; self.c.emit('PLAYER_REGEN_ENABLED'); self.assertTrue(root.IsShown(root))
        self.g.MOCK.secretGUID=True; self.assertIsNone(self.g.CMCompat.UnitGUID('target')); self.c.target(); self.g.MOCK.secretGUID=False
        self.g.MOCK.units['NPC']=self.g.MOCK.units.target
        self.c.emit('TRADE_SHOW'); self.c.emit('TRADE_CLOSED'); self.assertEqual(e.stats.trades,0)
        self.c.advance(6); self.c.emit('UI_INFO_MESSAGE',0,self.g.ERR_TRADE_COMPLETE); self.assertEqual(e.stats.trades,0)
        self.c.emit('TRADE_SHOW'); self.c.emit('UI_INFO_MESSAGE',0,self.g.ERR_TRADE_COMPLETE)
        self.c.emit('TRADE_CLOSED'); self.c.emit('UI_INFO_MESSAGE',0,self.g.ERR_TRADE_COMPLETE)
        self.assertEqual(e.stats.trades,1)

    def test_optional_api_capability_guards(self):
        c=Client(setup="MOCK.invalidEvents.PVP_MATCH_COMPLETE=true; TooltipDataProcessor=nil; C_EventUtils=nil")
        self.assertTrue(c.g.CMCompat.unsupportedEvents.PVP_MATCH_COMPLETE)
        c.target(); c.g.CMJ.Toggle()
        self.assertTrue(c.g.CMCompat.ClientInfo().forever)
        self.assertEqual(c.g.CMCompat.Text('éé',3),'é')

    def test_dungeon_exit_does_not_count_internal_zone_changes(self):
        self.g.MOCK.grouped=True; self.g.MOCK.units.party1=self.g.MOCK.units.target
        e=self.c.target(); self.g.MOCK.instance=True; self.g.MOCK.instanceType='party'
        self.c.emit('ENCOUNTER_START',1); self.c.emit('ENCOUNTER_END',1,'Boss',1,5,1)
        self.c.emit('ZONE_CHANGED'); self.assertEqual(e.stats.dungeonCompletions,0)
        self.g.MOCK.instance=False; self.g.MOCK.instanceType='none'; self.c.emit('ZONE_CHANGED_NEW_AREA')
        self.assertEqual(e.stats.dungeonCompletions,1)
        self.c.emit('ZONE_CHANGED'); self.assertEqual(e.stats.dungeonCompletions,1)


class JourneyTests(unittest.TestCase):
    def setUp(self):
        self.c=Client(); self.g=self.c.g
        self.target=self.g.MOCK.units.target

    def leave(self):
        self.g.MOCK.units.target=None; self.c.emit('PLAYER_TARGET_CHANGED')

    def return_after(self, seconds):
        self.leave(); self.c.advance(seconds); self.g.MOCK.units.target=self.target; return self.c.target()

    def test_first_meeting_to_written_memory_to_reunion(self):
        e=self.c.target(); self.assertIsNone(self.g.CMJourney.notice)
        self.c.advance(2)
        j=self.g.CMJourney; self.assertTrue(j.notice.IsShown(j.notice))
        self.assertFalse(self.g.CMJ.refs.root.IsShown(self.g.CMJ.refs.root))
        self.assertIsNone(self.g.MOCK.focus)  # The prompt never takes keyboard focus.
        self.assertEqual(j.notice.kind,'meeting'); self.assertIn('Elara',j.notice.person.GetText(j.notice.person))
        self.c.click(j.notice.keep); u=self.g.CMChronicleUI; f=u.editor
        self.assertTrue(f.IsShown(f)); self.assertEqual(f.item.kind,'meeting')
        self.g.MOCK.Type(f.bodyInput,'She shared her last loaf with a stranger.')
        self.g.MOCK.Type(f.followup,'Bring Elara a map of Westfall')
        self.c.click(f.save)
        self.assertEqual(len(e.memories),1); self.assertEqual(len(e.stories),1); self.assertIsNone(e.journalDraft)
        first=e.memories[1]; thread=e.stories[1]
        self.assertEqual(first.nextStoryID,thread.id); self.assertEqual(thread.fromMemoryID,first.id)
        self.assertTrue(j.reader.IsShown(j.reader)); self.assertIn('She shared',j.reader.body.GetText(j.reader.body))
        self.assertIn('Bring Elara',j.reader.body.GetText(j.reader.body))
        self.g.CMJ.Toggle(); self.c.advance(20)
        self.return_after(3601); self.c.advance(2)
        self.assertEqual(j.notice.kind,'reunion'); self.assertIn('Bring Elara',j.notice.words.GetText(j.notice.words))
        self.assertIn('1 hour',j.notice.context.GetText(j.notice.context))
        self.c.click(j.notice.keep); self.assertEqual(f.item.kind,'reunion'); self.assertEqual(f.resolveID,thread.id)
        self.g.MOCK.Type(f.bodyInput,'I kept my promise. We marked the road together.')
        f.resolve.SetChecked(f.resolve,True); f.resolve.Run(f.resolve,'OnClick')
        self.g.MOCK.Type(f.followup,'Meet by the bridge next market day')
        self.c.click(f.save)
        reunion=e.memories[2]
        self.assertEqual(reunion.fromMemoryID,first.id); self.assertEqual(reunion.resolvedStoryID,thread.id)
        self.assertEqual(thread.state,'resolved'); self.assertEqual(e.stories[2].state,'open')
        self.assertIn('marked the road',j.reader.body.GetText(j.reader.body))
        self.assertNotIn('shared her last loaf',str(plain(self.g.MOCK.messages)))

    def test_prompt_dwell_timeout_target_changes_and_no_spam(self):
        e=self.c.target(); self.c.advance(1); self.leave(); self.c.advance(2)
        self.assertTrue(self.g.CMJourney.notice is None or not self.g.CMJourney.notice.IsShown(self.g.CMJourney.notice))
        # A moment is retained even if its discovery prompt never appeared.
        self.assertEqual(len(e.memoryCandidates),1)
        self.g.MOCK.units.target=self.target; self.c.target(); self.c.advance(2)
        self.assertTrue(self.g.CMJourney.notice.IsShown(self.g.CMJourney.notice))
        self.assertEqual(self.g.CMJourney.notice.kind,'meeting')
        self.assertEqual(len(e.memoryCandidates),1)
        self.return_after(1801); self.c.advance(2)
        j=self.g.CMJourney; self.assertTrue(j.notice.IsShown(j.notice))
        self.c.advance(18); self.assertFalse(j.notice.IsShown(j.notice))
        self.leave(); self.g.MOCK.units.target=self.target; self.c.target(); self.c.advance(2)
        self.assertFalse(j.notice.IsShown(j.notice))
        self.assertEqual(len(e.memories),0)  # No automatically authored memories.

    def test_combat_and_preferences_suppress_notices(self):
        self.c.target(); self.c.advance(1); self.g.MOCK.combat=True; self.c.emit('PLAYER_REGEN_DISABLED')
        self.c.advance(3); self.assertIsNone(self.g.CMJourney.notice)
        self.g.MOCK.combat=False; self.c.emit('PLAYER_REGEN_ENABLED')
        self.return_after(1801); self.g.CharacterMemoryDB.settings.showOnTarget=False; self.c.advance(2)
        self.assertIsNone(self.g.CMJourney.notice)
        self.return_after(1801); self.c.advance(2); self.assertIsNone(self.g.CMJourney.notice)
        # The journal's manual path remains available with automatic notices disabled.
        self.g.CMJourney.Write('Player-1-ELARA'); self.assertTrue(self.g.CMChronicleUI.editor.IsShown(self.g.CMChronicleUI.editor))

    def test_holding_a_target_is_not_a_reunion(self):
        e=self.c.target(); self.c.advance(2)
        self.c.advance(7200); self.c.target(); self.c.advance(2)
        self.assertEqual(e.metCount,1); self.assertEqual(e.stats.reconnects,0)
        self.assertFalse(self.g.CMJourney.notice.IsShown(self.g.CMJourney.notice))
        self.return_after(60); self.c.advance(2); self.assertEqual(e.metCount,1)

    def test_pinned_recall_thread_choice_and_same_second_sort(self):
        e=self.c.target(); m=self.g.CMChronicle
        a=m.Remember(e.guid,None,'First words','Earlier meeting'); b=m.Remember(e.guid,None,'Later words','Later meeting')
        self.assertEqual(m.List(e.guid)[1].id,b)
        m.Pin(e.guid,a); memory,story=m.Highlights(e.guid); self.assertEqual(memory.id,a)
        first=m.AddStory(e.guid,'Old plan',''); self.c.advance(1); second=m.AddStory(e.guid,'Current plan','')
        memory,story=m.Highlights(e.guid); self.assertEqual(story.id,second)
        m.UpdateStory(e.guid,second,'Current plan','','resolved')
        self.assertIn('Old plan',m.Recall(e.guid))
        self.g.MOCK.tooltip(self.g.GameTooltip); self.assertIn('Old plan',self.g.GameTooltip.lines[2])

    def test_draft_survives_reload_cancel_and_switching_people(self):
        e=self.c.target(); self.g.CMJourney.Write(e.guid); f=self.g.CMChronicleUI.editor
        self.g.MOCK.Type(f.bodyInput,'PRIVATE unfinished words'); self.g.MOCK.Type(f.followup,'Return with a map')
        self.c.click(f.cancel); self.assertEqual(len(e.memories),0); self.assertEqual(e.journalDraft.note,'PRIVATE unfinished words')
        restored=Client(plain(self.g.CharacterMemoryDB)); g=restored.g
        g.CMJourney.Write(e.guid); f=g.CMChronicleUI.editor
        self.assertEqual(f.bodyInput.GetText(f.bodyInput),'PRIVATE unfinished words')
        other=restored.entry('Player-1-OTHER'); other.name='Other'
        g.CMUI.Select(other.guid); g.CMChronicleUI.Edit('memory')
        g.MOCK.Type(f.bodyInput,'Other private words'); restored.click(f.cancel)
        self.assertEqual(g.CharacterMemoryDB.entries[e.guid].journalDraft.note,'PRIVATE unfinished words')
        self.assertEqual(other.journalDraft.note,'Other private words')
        g.CMJourney.Write(e.guid); f=g.CMChronicleUI.editor; restored.click(f.save)
        self.assertIsNone(g.CharacterMemoryDB.entries[e.guid].journalDraft)
        self.assertEqual(g.CharacterMemoryDB.entries[e.guid].memories[1].note,'PRIVATE unfinished words')
        self.assertEqual(other.journalDraft.note,'Other private words')

    def test_capacity_failure_keeps_draft_and_does_not_half_resolve(self):
        e=self.c.target(); m=self.g.CMChronicle
        for i in range(32): m.AddStory(e.guid,'Plan '+str(i),'')
        self.g.CMJourney.Write(e.guid); f=self.g.CMChronicleUI.editor
        self.g.MOCK.Type(f.bodyInput,'My words must survive this.')
        self.g.MOCK.Type(f.followup,'One more plan')
        resolving=f.resolveID
        f.resolve.SetChecked(f.resolve,True); self.c.click(f.save)
        self.assertTrue(f.IsShown(f)); self.assertEqual(len(e.memories),0)
        self.assertEqual(e.stories[1].state,'open'); self.assertEqual(e.journalDraft.note,'My words must survive this.')
        self.assertIn('full',f.errorText.GetText(f.errorText))
        f.followup.SetText(f.followup,''); self.c.click(f.save)
        self.assertEqual(len(e.memories),1); self.assertEqual(m.Find(e.guid,'stories',resolving).state,'resolved')

    def test_read_and_write_reveal_person_outside_active_filter(self):
        e=self.c.target(); self.g.CMJ.Toggle(); self.g.CMJ.Model.filter='favorites'
        self.g.MOCK.Type(self.g.CMJ.refs.search,'No match'); self.assertEqual(len(self.g.CMJ.Model.order),0)
        self.g.CMJourney.Read(e.guid); self.assertEqual(self.g.CMJ.Model.selected,e.guid)
        self.assertEqual(self.g.CMJ.Model.filter,'all'); self.assertEqual(self.g.CMJ.Model.search,'')
        self.assertIn('Our paths first crossed',self.g.CMJourney.reader.body.GetText(self.g.CMJourney.reader.body))
        self.c.click(self.g.CMJourney.reader.write); self.assertEqual(self.g.CMChronicleUI.editor.guid,e.guid)

    def test_full_suggestions_do_not_attach_a_new_reunion_to_old_facts(self):
        e=self.c.target(); m=self.g.CMChronicle
        for i in range(11): self.c.advance(1201); m.Offer(e.guid,'conversation','An earlier place')
        self.assertEqual(len(e.memoryCandidates),12)
        self.return_after(3601); self.c.advance(2)
        self.assertEqual(e.journey.kind,'reunion'); self.assertIsNone(self.g.CMJourney.Candidate(e.guid))
        self.g.CMJourney.Write(e.guid); f=self.g.CMChronicleUI.editor
        self.assertIsNone(f.item); self.g.MOCK.Type(f.bodyInput,'Today we met again.'); self.c.click(f.save)
        self.assertEqual(e.memories[1].kind,'manual')
        self.assertNotEqual(e.memories[1].where,'An earlier place')

    def test_draft_resolves_the_same_thread_after_another_plan_is_added(self):
        e=self.c.target(); m=self.g.CMChronicle
        first=m.AddStory(e.guid,'Return the map',''); self.g.CMJourney.Write(e.guid); f=self.g.CMChronicleUI.editor
        self.g.MOCK.Type(f.bodyInput,'The map is returned.'); f.resolve.SetChecked(f.resolve,True)
        f.resolve.Run(f.resolve,'OnClick'); self.c.click(f.cancel)
        self.c.advance(1); second=m.AddStory(e.guid,'A new plan','')
        self.g.CMJourney.Write(e.guid); self.assertEqual(f.resolveID,first); self.c.click(f.save)
        self.assertEqual(m.Find(e.guid,'stories',first).state,'resolved')
        self.assertEqual(m.Find(e.guid,'stories',second).state,'open')

    def test_self_target_never_offers_a_first_meeting(self):
        self.g.MOCK.units.target=self.g.MOCK.units.player; self.c.emit('PLAYER_TARGET_CHANGED'); self.c.advance(2)
        self.assertIsNone(self.g.CMJourney.notice)
        e=self.g.CharacterMemoryDB.entries['Player-1-SELF']
        self.assertTrue(e is None or not e.memoryCandidates or len(e.memoryCandidates)==0)

    def test_new_people_do_not_produce_back_to_back_notices(self):
        self.c.target(); self.c.advance(2); j=self.g.CMJourney
        second=self.c.table({'guid':'Player-1-SECOND','name':'Second','realm':'FictionalRealm'})
        self.g.MOCK.units.target=second; self.c.emit('PLAYER_TARGET_CHANGED'); self.c.advance(2)
        self.assertFalse(j.notice.IsShown(j.notice))
        self.assertEqual(len(self.g.CharacterMemoryDB.entries[second.guid].memoryCandidates),1)
        self.c.advance(30)
        third=self.c.table({'guid':'Player-1-THIRD','name':'Third','realm':'FictionalRealm'})
        self.g.MOCK.units.target=third; self.c.emit('PLAYER_TARGET_CHANGED'); self.c.advance(2)
        self.assertTrue(j.notice.IsShown(j.notice)); self.assertEqual(j.notice.guid,third.guid)

    def test_escape_closes_the_page_and_keeps_the_journal_and_draft(self):
        e=self.c.target(); self.g.CMJourney.Write(e.guid); f=self.g.CMChronicleUI.editor; root=self.g.CMJ.refs.root
        self.g.MOCK.Type(f.bodyInput,'An unfinished page'); root.Run(root,'OnKeyDown','ESCAPE')
        self.assertFalse(f.IsShown(f)); self.assertTrue(root.IsShown(root)); self.assertEqual(e.journalDraft.note,'An unfinished page')
        self.g.CMJourney.Read(e.guid); root.Run(root,'OnKeyDown','ESCAPE')
        self.assertFalse(self.g.CMJourney.reader.IsShown(self.g.CMJourney.reader)); self.assertTrue(root.IsShown(root))
        root.Run(root,'OnKeyDown','ESCAPE'); self.assertFalse(root.IsShown(root))

    def test_reload_uses_logout_time_as_last_seen(self):
        e=self.c.target(); self.c.advance(7200); self.c.emit('PLAYER_LOGOUT')
        last_seen=e._lastSeenStamp
        self.assertEqual(last_seen,self.g.MOCK.epoch)
        restored=Client(plain(self.g.CharacterMemoryDB),setup='MOCK.epoch='+str(last_seen+300))
        restored.target(); restored.advance(2)
        self.assertEqual(restored.g.CharacterMemoryDB.entries[e.guid].metCount,1)
        self.assertIsNone(restored.g.CMJourney.notice)

    def test_draft_discard_requires_explicit_product_confirmation(self):
        e=self.c.target(); self.g.CMJourney.Write(e.guid); f=self.g.CMChronicleUI.editor
        self.g.MOCK.Type(f.bodyInput,'Unsaved words'); self.c.click(f.discard)
        self.assertIsNotNone(e.journalDraft); self.g.MOCK.popup=None
        self.c.click(f.discard); self.g.MOCK.AcceptPopup()
        self.assertIsNone(e.journalDraft); self.assertFalse(f.IsShown(f)); self.assertEqual(len(e.memoryCandidates),1)


class PolishTests(unittest.TestCase):
    def setUp(self): self.c=Client(); self.g=self.c.g

    def test_sheet_fields_and_labels_stay_inside_sections_without_overlap(self):
        self.g.CharacterMemory_OpenCharacterSheet(); u=self.g.RPBioUI
        for name,p in u.pages.items():
            u.ShowPage(name); geo=Geometry(self.c)
            fields=[f for f in u.fields.values() if f.parent.mockID==p.content.mockID]
            for field in fields:
                self.assertTrue(geo.contains(p.content,field),str((name,field.frameName,geo.relative(field,p.content))))
                self.assertTrue(geo.contains(p.content,field.caption),name+' label escapes')
                self.assertFalse(geo.overlaps(field,field.caption),name+' label overlaps input')
                for other in fields:
                    if field.mockID==other.mockID:continue
                    self.assertFalse(geo.overlaps(field,other),str((name,field.frameName,other.frameName)))
                    self.assertFalse(geo.overlaps(field,other.caption),str((name,field.frameName,'other label')))
            self.assertEqual(sum(bool(q.scroll.IsShown(q.scroll)) for q in u.pages.values()),1)

    def test_sheet_footer_and_navigation_are_separate_from_content(self):
        self.g.CharacterMemory_OpenCharacterSheet(); geo=Geometry(self.c);u=self.g.RPBioUI;root=self.g.RPBioFrame
        footer=[u.save,u.close,self.g.RPBio_PublicSharing,u.status]
        for field in footer:self.assertTrue(geo.contains(root,field),str(geo.relative(field,root)))
        for a in footer:
            for b in footer:
                if a.mockID!=b.mockID:self.assertFalse(geo.overlaps(a,b),str((a.frameName,b.frameName)))
        for tab in u.tabs.values():
            self.assertTrue(geo.contains(root,tab))
            for p in u.pages.values():self.assertFalse(geo.overlaps(tab,p.scroll))
        self.assertIsNotNone(root.CloseButton)
        self.assertEqual(len([f for f in geo.descendants(root) if f.template and 'UIPanelCloseButton' in f.template]),0)

    def test_settings_changes_never_rewrite_authored_character(self):
        bio=self.g.CMProfile.Ensure();bio.identity.title='Cartographer';bio.lore.shortBio='A road worth remembering.'
        self.g.CMProfile.SyncLegacy();before=json.dumps(plain(self.g.RPJournalDB),sort_keys=True)
        self.g.CM_OptionsPanel.Show(self.g.CM_OptionsPanel)
        bio.lore.shortBio='New bio saved while settings is open';self.g.CMProfile.SyncLegacy()
        before=json.dumps(plain(self.g.RPJournalDB),sort_keys=True)
        toggle=self.g.CMSettings.controls.showOnTarget;toggle.SetChecked(toggle,False);self.c.click(toggle)
        self.g.CharacterMemory_OptionsSave()
        self.assertFalse(self.g.CharacterMemoryDB.settings.showOnTarget)
        self.assertEqual(json.dumps(plain(self.g.RPJournalDB),sort_keys=True),before)
        self.assertIsNone(self.g.CM_BioPanel);self.assertIsNone(self.g.CM_OptionsPanelPublish);self.assertIsNone(self.g.CM_OptionsPanelClearSelected)

    def test_sheet_roundtrip_keeps_every_section_and_relationship_list(self):
        bio=self.g.CMProfile.Ensure()
        bio.identity.title='Cartographer';bio.appearance.eyes='Grey';bio.lore.backstory='A long journey.'
        bio.personality.hooks='Ask about the map';bio.skills.occupation='Scribe'
        bio.relationships.family=self.c.table(['Mara','Toren']);bio.relationships.allies=self.c.table(['Ally A','Ally B'])
        bio.relationships.partner=self.c.table({'character':'Rin','note':'A promise'})
        bio.rpPrefs.oocContact='Private contact';bio.notes.private='Private notes'
        self.g.CharacterMemory_OpenCharacterSheet();self.assertTrue(self.g.RPBio_Save())
        self.assertEqual(list(bio.relationships.family.values()),['Mara','Toren'])
        self.assertEqual(list(bio.relationships.allies.values()),['Ally A','Ally B'])
        self.assertEqual(bio.relationships.partner.character,'Rin');self.assertEqual(bio.relationships.partner.note,'A promise')
        self.assertEqual(bio.rpPrefs.oocContact,'Private contact');self.assertEqual(bio.notes.private,'Private notes')
        self.assertEqual(bio.lore.backstory,'A long journey.');self.assertEqual(bio.personality.hooks,'Ask about the map')
        self.assertEqual(bio.skills.occupation,'Scribe');self.assertEqual(bio.appearance.eyes,'Grey')
        self.assertEqual(bio.lore.alignment,'');self.assertEqual(bio.rpPrefs.availability,'')

    def test_unsaved_sheet_edits_survive_section_changes_and_reopening(self):
        self.g.CharacterMemory_OpenCharacterSheet();self.g.MOCK.Type(self.g.RPBio_Title,'Unfinished title')
        self.g.RPBioUI.ShowPage('Story');self.g.RPBioFrame.Hide(self.g.RPBioFrame);self.g.CharacterMemory_OpenCharacterSheet()
        self.assertEqual(self.g.RPBio_Title.GetText(self.g.RPBio_Title),'Unfinished title')
        self.assertTrue(self.g.RPBioUI.dirty);self.assertEqual(self.g.RPBioUI.active,'Story')
        self.assertTrue(self.g.RPBio_Save());self.assertFalse(self.g.RPBioUI.dirty)

    def test_multibyte_short_bio_error_does_not_partially_save_sheet(self):
        self.g.CharacterMemory_OpenCharacterSheet();self.g.MOCK.Type(self.g.RPBio_Title,'Do not partially save')
        self.g.MOCK.Type(self.g.RPBio_ShortBio.EditBox,'é'*300)
        before=json.dumps(plain(self.g.RPJournalDB),sort_keys=True)
        self.assertFalse(self.g.RPBio_Save());self.assertEqual(self.g.RPBioUI.active,'Story')
        self.assertEqual(json.dumps(plain(self.g.RPJournalDB),sort_keys=True),before)
        self.assertIn('600',self.g.RPBioUI.bioCount.GetText(self.g.RPBioUI.bioCount))
        self.g.MOCK.Type(self.g.RPBio_ShortBio.EditBox,'A short bio');self.assertTrue(self.g.RPBio_Save())



    def test_settings_reflow_keeps_controls_inside_a_narrow_canvas(self):
        root=self.g.CM_OptionsPanel;root.SetSize(root,430,520);root.Show(root)
        geo=Geometry(self.c);scroll=self.g.CMSettingsScroll
        _,_,width,height=geo.rect(scroll)
        scroll.width=width;scroll.height=height;scroll.Run(scroll,'OnSizeChanged')
        geo=Geometry(self.c);content=self.g.CMSettings.content
        for control in self.g.CMSettings.controls.values():self.assertTrue(geo.contains(content,control))
        self.assertTrue(geo.contains(content,self.g.CMSettings.sheet));self.assertTrue(geo.contains(content,self.g.CMSettings.journal))
        self.assertFalse(geo.overlaps(self.g.CMSettings.sheet,self.g.CMSettings.journal))


    def test_people_list_has_no_blank_or_self_rows(self):
        self.g.CMJ.Toggle();self.assertEqual(len(self.g.CMJ.Model.order),0)
        e=self.c.target();self.assertEqual(len(self.g.CMJ.Model.order),1)
        self.g.CharacterMemory_OpenCharacterSheet();self.g.RPBio_Save();self.g.CMJ.NotifyDataChanged()
        self.assertEqual(len(self.g.CMJ.Model.order),1);self.assertEqual(self.g.CMJ.Model.order[1],e.guid)
        self.c.entry('Player-1-UNNAMED');self.g.CMJ.NotifyDataChanged();self.assertEqual(len(self.g.CMJ.Model.order),1)

    def test_settings_navigation_does_not_stack_two_editing_windows(self):
        self.g.SettingsPanel=self.g.CreateFrame('Frame','MockSettingsPanel')
        self.c.click(self.g.CMSettings.sheet)
        self.assertFalse(self.g.SettingsPanel.IsShown(self.g.SettingsPanel))
        self.assertTrue(self.g.RPBioFrame.IsShown(self.g.RPBioFrame))

    def test_sheet_fits_small_viewport_without_appearance_configuration(self):
        self.g.UIParent.SetSize(self.g.UIParent,900,600);self.g.CharacterMemory_OpenCharacterSheet()
        f=self.g.RPBioFrame;self.assertLessEqual(f.GetWidth(f)*f.GetScale(f),860)
        self.assertLessEqual(f.GetHeight(f)*f.GetScale(f),560)



class FlowTests(unittest.TestCase):
    def setUp(self): self.c=Client();self.g=self.c.g

    def test_missed_first_meeting_returns_once_without_focus_or_duplicate_moment(self):
        c,g=self.c,self.g;e=c.target();target=g.MOCK.units.target
        c.advance(1);g.MOCK.units.target=None;c.emit('PLAYER_TARGET_CHANGED');c.advance(10)
        g.MOCK.units.target=target;c.target();c.advance(2)
        self.assertEqual(g.CMJourney.notice.kind,'meeting');self.assertIsNone(g.MOCK.focus)
        self.assertEqual(len(e.memoryCandidates),1);self.assertEqual(len(e.memories),0)
        g.CMJourney.CancelNotice();c.advance(31);c.target();c.advance(2)
        self.assertFalse(g.CMJourney.notice.IsShown(g.CMJourney.notice))

    def test_reunion_notice_writer_and_reader_share_the_same_context(self):
        c,g=self.c,self.g;e=c.target();c.advance(2);m=g.CMChronicle;j=g.CMJourney
        memory=m.Remember(e.guid,None,'We drew the old road together.','A borrowed map')
        thread=m.AddStory(e.guid,'Bring back the map','');j.CancelNotice()
        target=g.MOCK.units.target;g.MOCK.units.target=None;c.emit('PLAYER_TARGET_CHANGED');c.advance(3601)
        g.MOCK.units.target=target;c.target()
        m.AddStory(e.guid,'An unrelated newer plan','');m.Remember(e.guid,None,'A different conversation.','Another road')
        c.advance(2);self.assertIn('Bring back the map',j.notice.words.GetText(j.notice.words))
        self.assertNotIn('unrelated',j.notice.words.GetText(j.notice.words));self.assertIn('We drew the old road together.',j.notice.words.GetText(j.notice.words))
        c.click(j.notice.keep);f=g.CMChronicleUI.editor;self.assertEqual(f.resolveID,thread)
        g.MOCK.Type(f.bodyInput,'I returned it with a new route marked.');c.click(f.save)
        kept=e.memories[len(e.memories)];self.assertEqual(kept.fromMemoryID,memory);self.assertEqual(kept.continuedStoryID,thread)
        self.assertEqual(m.Find(e.guid,'stories',thread).state,'open')
        self.assertIn('Bring back the map',j.reader.body.GetText(j.reader.body));self.assertNotIn('unrelated',j.reader.body.GetText(j.reader.body))

    def test_removed_pending_moment_draft_preserves_encounter_facts_after_reload(self):
        c,g=self.c,self.g;e=c.target();moment=e.memoryCandidates[1];moment_id,stamp,where=moment.id,moment.at,moment.where
        g.CMJourney.Write(e.guid);f=g.CMChronicleUI.editor;g.MOCK.Type(f.bodyInput,'PRIVATE words about the first meeting.')
        g.MOCK.Type(f.followup,'Meet again by the bridge');c.click(f.cancel);g.CMChronicle.Dismiss(e.guid,moment_id)
        restored=Client(plain(g.CharacterMemoryDB),setup='MOCK.epoch='+str(stamp+5000));h=restored.g
        h.CMJourney.Write(e.guid);f=h.CMChronicleUI.editor;restored.click(f.save)
        kept=h.CharacterMemoryDB.entries[e.guid].memories[1]
        self.assertEqual((kept.kind,kept.at,kept.where,kept.fromMomentID),('meeting',stamp,where,moment_id))
        self.assertIn('PRIVATE words',kept.note);self.assertIsNone(h.CharacterMemoryDB.entries[e.guid].journalDraft)
        self.assertEqual(h.CharacterMemoryDB.entries[e.guid].stories[1].title,'Meet again by the bridge')
        self.assertNotIn('PRIVATE words',json.dumps(plain(h.MOCK.messages)))

    def test_already_kept_moment_does_not_duplicate_a_recovered_draft(self):
        c,g=self.c,self.g;e=c.target();moment=e.memoryCandidates[1]
        g.CMJourney.Write(e.guid);f=g.CMChronicleUI.editor;g.MOCK.Type(f.bodyInput,'My unfinished version');c.click(f.cancel)
        g.CMChronicle.Remember(e.guid,moment.id,'A saved version','The same moment')
        g.CMJourney.Write(e.guid);c.click(f.save)
        self.assertEqual(len(e.memories),1);self.assertIn('already',f.errorText.GetText(f.errorText))
        self.assertEqual(e.journalDraft.note,'My unfinished version');self.assertTrue(f.IsShown(f))

    def test_continue_uses_the_chosen_thread_and_only_resolves_that_thread(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle
        older=m.AddStory(e.guid,'Return the map','');c.advance(1);newer=m.AddStory(e.guid,'Ask about the caravan','')
        g.CMJourney.Reveal(e.guid);g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;u.SetMode('stories');c.click(u.rows[2])
        g.SlashCmdList.CHARACTERMEMORY('continue');f=u.editor;self.assertEqual(f.resolveID,older)
        g.MOCK.Type(f.bodyInput,'The map is safely home.');f.resolve.SetChecked(f.resolve,True);c.click(f.save)
        self.assertEqual(m.Find(e.guid,'stories',older).state,'resolved');self.assertEqual(m.Find(e.guid,'stories',newer).state,'open')
        kept=e.memories[1];self.assertEqual(kept.continuedStoryID,older);self.assertEqual(kept.resolvedStoryID,older)
        self.assertIn('full circle',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))

    def test_read_selected_memory_and_browse_history_without_mutating_it(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;m.Dismiss(e.guid,e.memoryCandidates[1].id)
        first=m.Remember(e.guid,None,'We met beside the bridge.','The beginning');c.advance(1)
        second=m.Remember(e.guid,None,'We walked to the mill.','The road');c.advance(1)
        third=m.Remember(e.guid,None,'We returned home.','The return');m.Pin(e.guid,third)
        g.CMJourney.Reveal(e.guid);g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;u.SetMode('memories');c.click(u.rows[3])
        before=json.dumps(plain(e.memories),sort_keys=True);g.SlashCmdList.CHARACTERMEMORY('recall');j=g.CMJourney
        self.assertEqual(j.reader.memoryID,first)
        for direction,expected in [('latest',third),('older',second),('older',first),('older',first),('newer',second),('first',first)]:
            g.SlashCmdList.CHARACTERMEMORY('recall '+direction);self.assertEqual(j.reader.memoryID,expected)
        self.assertEqual(json.dumps(plain(e.memories),sort_keys=True),before)

    def test_explicit_memory_history_does_not_borrow_an_unrelated_selected_thread(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle
        kept=m.Remember(e.guid,None,'A quiet evening without a plan.','The inn')
        m.AddStory(e.guid,'A much later promise','');g.CMJourney.Reveal(e.guid)
        g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;u.SetMode('stories');c.click(u.rows[1])
        g.CMJourney.Read(e.guid,kept)
        self.assertNotIn('later promise',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        self.assertIsNone(g.CMJourney.reader.threadID)

    def test_recall_and_continue_follow_the_open_journal_person_over_world_target(self):
        c,g=self.c,self.g;c.target();other=c.entry('Player-1-OTHER');other.name='Mara';other.isPlayer=True
        g.CMChronicle.Remember(other.guid,None,'A page for Mara','Her garden');thread=g.CMChronicle.AddStory(other.guid,'Bring seeds','')
        g.CMJourney.Reveal(other.guid);g.SlashCmdList.CHARACTERMEMORY('recall')
        self.assertEqual(g.CMJourney.reader.guid,other.guid)
        g.SlashCmdList.CHARACTERMEMORY('continue');f=g.CMChronicleUI.editor
        self.assertEqual(f.guid,other.guid);self.assertEqual(f.resolveID,thread)
        self.assertEqual(g.MOCK.units.target.guid,'Player-1-ELARA')

    def test_removed_or_resolved_thread_never_redirects_a_resumed_draft(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;old=m.AddStory(e.guid,'An old promise','')
        g.CMJourney.Write(e.guid);f=g.CMChronicleUI.editor;g.MOCK.Type(f.bodyInput,'Keep these words.');c.click(f.cancel)
        m.RemoveStory(e.guid,old);fresh=m.AddStory(e.guid,'An unrelated new promise','');g.CMJourney.Write(e.guid)
        self.assertIsNone(f.resolveID);self.assertEqual(f.continueID,old);c.click(f.save)
        self.assertEqual(m.Find(e.guid,'stories',fresh).state,'open');self.assertEqual(e.memories[1].continuedStoryID,old)
        self.assertIsNone(e.memories[1].resolvedStoryID)

    def test_resolved_selection_is_not_replaced_by_a_different_open_thread(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;old=m.AddStory(e.guid,'A finished promise','')
        m.UpdateStory(e.guid,old,'A finished promise','','resolved');m.AddStory(e.guid,'Another plan','')
        g.CMJourney.Reveal(e.guid);g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;u.SetMode('stories');c.click(u.rows[2])
        g.SlashCmdList.CHARACTERMEMORY('continue');self.assertFalse(u.editor.IsShown(u.editor))
        self.assertIn('unfinished story',g.MOCK.chat[len(g.MOCK.chat)].text)


class ClickFlowTests(unittest.TestCase):
    def setUp(self): self.c=Client();self.g=self.c.g

    def open_list(self, guid, mode):
        self.g.CMJourney.Reveal(guid);self.g.CMUI.TabSwap('Notes');self.g.CMChronicleUI.SetMode(mode)
        return self.g.CMChronicleUI

    def test_meeting_memory_reunion_and_resolve_work_with_no_commands(self):
        c,g=self.c,self.g;g.SlashCmdList=c.table({});e=c.target();c.advance(2);j=g.CMJourney
        c.click(j.notice.keep);f=g.CMChronicleUI.editor;g.MOCK.Type(f.bodyInput,'She trusted me with her map.')
        g.MOCK.Type(f.followup,'Return the map');c.click(f.save);thread=e.stories[1]
        self.assertEqual(j.reader.write.GetText(j.reader.write),'Continue story')
        g.CMJ.Toggle();target=g.MOCK.units.target;g.MOCK.units.target=None;c.emit('PLAYER_TARGET_CHANGED');c.advance(3601)
        g.MOCK.units.target=target;c.target();c.advance(2);c.click(j.notice.story)
        self.assertEqual(j.reader.storyID,thread.id);self.assertIn('trusted me',j.reader.body.GetText(j.reader.body))
        c.click(j.reader.write);self.assertEqual(f.resolveID,thread.id)
        g.MOCK.Type(f.bodyInput,'I returned it with the safe route marked.');f.resolve.SetChecked(f.resolve,True);c.click(f.save)
        self.assertEqual(thread.state,'resolved');self.assertEqual(len(e.memories),2)
        self.assertEqual(e.memories[2].resolvedStoryID,thread.id);self.assertIn('full circle',j.reader.body.GetText(j.reader.body))
        self.assertEqual(len(g.SlashCmdList),0)

    def test_click_memory_to_read_browse_and_edit_the_shown_page(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;m.Dismiss(e.guid,e.memoryCandidates[1].id)
        old=m.Remember(e.guid,None,'An old memory','The bridge');new=m.Remember(e.guid,None,'A newer memory','The mill')
        u=self.open_list(e.guid,'memories');c.click(u.rows[1]);r=g.CMJourney.reader
        self.assertEqual(r.memoryID,new);self.assertFalse(r.newer.IsEnabled(r.newer));self.assertTrue(r.older.IsEnabled(r.older))
        c.click(r.older);self.assertEqual(r.memoryID,old);self.assertFalse(r.older.IsEnabled(r.older))
        self.assertEqual(r.pageCount.GetText(r.pageCount),'Memory 1 / 2');self.assertEqual(r.all.GetText(r.all),'Edit memory')
        c.click(r.newer);self.assertEqual(r.memoryID,new);c.click(r.older);c.click(r.all)
        f=u.editor;self.assertEqual(f.item.id,old);g.MOCK.Type(f.bodyInput,'The corrected old memory');c.click(f.save)
        self.assertEqual(m.Find(e.guid,'memories',old).note,'The corrected old memory')
        self.assertEqual(m.Find(e.guid,'memories',new).note,'A newer memory')

    def test_reader_continue_follows_the_browsed_story_not_the_original_list_row(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;old=m.AddStory(e.guid,'Return a book','');new=m.AddStory(e.guid,'Bring a map','')
        u=self.open_list(e.guid,'stories');c.click(u.rows[1]);r=g.CMJourney.reader;self.assertEqual(r.storyID,new)
        c.click(r.older);self.assertEqual(r.storyID,old);self.assertEqual(r.write.GetText(r.write),'Continue story')
        c.click(r.write);self.assertEqual(u.editor.resolveID,old)
        g.MOCK.Type(u.editor.bodyInput,'The book is home.');u.editor.resolve.SetChecked(u.editor.resolve,True);c.click(u.editor.save)
        self.assertEqual(m.Find(e.guid,'stories',old).state,'resolved');self.assertEqual(m.Find(e.guid,'stories',new).state,'open')

    def test_reader_edit_story_and_continue_draft_are_visible_actions(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;old=m.AddStory(e.guid,'A promise','Old details')
        u=self.open_list(e.guid,'stories');c.click(u.rows[1]);r=g.CMJourney.reader;self.assertEqual(r.all.GetText(r.all),'Edit story')
        c.click(r.all);f=u.editor;self.assertEqual(f.item.id,old);g.MOCK.Type(f.bodyInput,'More precise details');c.click(f.save)
        self.assertEqual(m.Find(e.guid,'stories',old).note,'More precise details')
        c.click(u.rows[1]);c.click(r.write);g.MOCK.Type(f.bodyInput,'An unfinished answer.');c.click(f.cancel)
        m.AddStory(e.guid,'A different newer plan','');u.SetMode('stories');c.click(u.rows[1])
        self.assertEqual(r.write.GetText(r.write),'Continue draft');c.click(r.write)
        self.assertEqual(f.resolveID,old);self.assertEqual(f.bodyInput.GetText(f.bodyInput),'An unfinished answer.')

    def test_empty_and_single_memory_reader_have_a_complete_click_path(self):
        c,g=self.c,self.g;e=c.target();g.CMChronicle.Dismiss(e.guid,e.memoryCandidates[1].id)
        g.CMJourney.Read(e.guid);r=g.CMJourney.reader
        self.assertFalse(r.older.IsEnabled(r.older));self.assertFalse(r.newer.IsEnabled(r.newer))
        self.assertEqual(r.all.GetText(r.all),'All memories');c.click(r.all);u=g.CMChronicleUI;c.click(u.add)
        g.MOCK.Type(u.editor.bodyInput,'The first words on this page.');c.click(u.editor.save)
        self.assertEqual(r.pageCount.GetText(r.pageCount),'Memory 1 / 1')
        self.assertFalse(r.older.IsEnabled(r.older));self.assertFalse(r.newer.IsEnabled(r.newer))
        self.assertEqual(len(e.memories),1)

    def test_reader_text_does_not_include_a_lua_substitution_count(self):
        c,g=self.c,self.g;e=c.target();self.assertEqual(g.CMCompat.Display('A|B'),'A||B')
        g.CMJourney.Read(e.guid);words=g.CMJourney.reader.body.GetText(g.CMJourney.reader.body)
        self.assertNotIn('\n0\n',words);self.assertNotIn('\n1\n',words)

    def test_reader_navigation_is_bounded_and_separate_from_body_and_footer(self):
        c,g=self.c,self.g;e=c.target();g.CMChronicle.Remember(e.guid,None,'Words','A page');g.CMJourney.Read(e.guid)
        r=g.CMJourney.reader;geo=Geometry(c);controls=[r.older,r.newer,r.pageCount,r.write,r.all,r.scroll]
        controls += [f for f in geo.descendants(r) if f.kind=='Button' and f.GetText(f)=='Close']
        self.assertEqual((r.GetWidth(r),r.GetHeight(r)),(420,400))
        for a in controls:
            self.assertTrue(geo.contains(r,a),str(geo.relative(a,r)))
            for b in controls:
                if a.mockID!=b.mockID:self.assertFalse(geo.overlaps(a,b),str((geo.relative(a,r),geo.relative(b,r))))
        self.assertEqual(r.body.font,'GameFontHighlightSmall');self.assertEqual(r.pageCount.font,'GameFontDisableSmall')

    def test_candidate_row_opens_writer_and_saved_row_does_not_auto_write(self):
        c,g=self.c,self.g;e=c.target();u=self.open_list(e.guid,'memories');c.click(u.rows[1])
        self.assertTrue(u.editor.IsShown(u.editor));g.MOCK.Type(u.editor.bodyInput,'The meeting mattered.');c.click(u.editor.save)
        before=json.dumps(plain(e.memories),sort_keys=True);c.click(u.rows[1])
        self.assertTrue(g.CMJourney.reader.IsShown(g.CMJourney.reader));self.assertFalse(u.editor.IsShown(u.editor))
        self.assertEqual(json.dumps(plain(e.memories),sort_keys=True),before)


class PersonalLoopTests(unittest.TestCase):
    def setUp(self): self.c=Client();self.g=self.c.g

    def return_after(self, seconds=3601):
        c,g=self.c,self.g;g.CMJ.refs.root.Hide(g.CMJ.refs.root)
        target=g.MOCK.units.target;g.MOCK.units.target=None;c.emit('PLAYER_TARGET_CHANGED');c.advance(seconds)
        g.MOCK.units.target=target;c.target();c.advance(2)

    def test_one_sentence_meeting_to_two_reunions_and_next_promise_by_clicks(self):
        c,g=self.c,self.g;g.SlashCmdList=c.table({});e=c.target();c.advance(2);j=g.CMJourney
        self.assertEqual(j.notice.keep.GetText(j.notice.keep),'Remember them');self.assertEqual(j.notice.story.GetText(j.notice.story),'Not now')
        c.click(j.notice.keep);f=g.CMChronicleUI.editor;self.assertEqual(f.titleInput.GetText(f.titleInput),'');self.assertTrue(f.bodyInput.HasFocus(f.bodyInput))
        g.MOCK.Type(f.bodyInput,'She trusted me with her map. I promised to return it.');g.MOCK.Type(f.followup,'Bring back the map');c.click(f.save)
        first=e.memories[1];thread=e.stories[1];self.assertEqual(first.title,'She trusted me with her map.')
        self.return_after();self.assertEqual(j.notice.keep.GetText(j.notice.keep),'Pick up story');c.click(j.notice.keep)
        self.assertEqual(f.resolveID,thread.id);self.assertIn('Picking up: Bring back the map',f.context.GetText(f.context))
        g.MOCK.Type(f.bodyInput,'We found a safer road together.');c.click(f.save);second=e.memories[2]
        self.assertEqual(thread.latestMemoryID,second.id);self.assertEqual(second.fromMemoryID,first.id)
        unrelated=g.CMChronicle.Remember(e.guid,None,'An unrelated pinned memory.','An older favorite');g.CMChronicle.Pin(e.guid,unrelated)
        self.return_after();self.assertIn('safer road',j.notice.words.GetText(j.notice.words));self.assertNotIn('unrelated',j.notice.words.GetText(j.notice.words))
        c.click(j.notice.keep);self.assertEqual(f.item.fromMemoryID,second.id);g.MOCK.Type(f.bodyInput,'The map is home, with our new road marked.')
        f.resolve.SetChecked(f.resolve,True);g.MOCK.Type(f.followup,'Meet by the bridge at sunset');c.click(f.save)
        last=e.memories[len(e.memories)];self.assertEqual(last.fromMemoryID,second.id);self.assertEqual(thread.state,'resolved')
        body=j.reader.body.GetText(j.reader.body);self.assertIn('full circle',body);self.assertIn('Bring back the map',body);self.assertIn('Meet by the bridge at sunset',body)
        c.click(j.reader.write);self.assertEqual(f.resolveID,e.stories[2].id);self.assertEqual(len(g.SlashCmdList),0)

    def test_empty_memories_are_not_kept_and_titles_are_optional_but_respected(self):
        c,g=self.c,self.g;e=c.target();c.advance(2);c.click(g.CMJourney.notice.keep);f=g.CMChronicleUI.editor
        g.MOCK.Type(f.bodyInput,' \n\t ');before=g.CharacterMemoryDB.nextJournalID;c.click(f.save)
        self.assertEqual(len(e.memories),0);self.assertEqual(len(e.memoryCandidates),1);self.assertEqual(g.CharacterMemoryDB.nextJournalID,before)
        self.assertIn('one detail',f.errorText.GetText(f.errorText));self.assertIsNotNone(e.journalDraft)
        g.MOCK.Type(f.titleInput,'The first kindness');g.MOCK.Type(f.bodyInput,'');c.click(f.save)
        self.assertEqual(e.memories[1].title,'The first kindness');c.click(f.save);self.assertEqual(len(e.memories),1)

    def test_unicode_auto_title_uses_authored_words_and_preserves_the_full_note(self):
        c,g=self.c,self.g;e=c.target();g.CMJourney.Write(e.guid);f=g.CMChronicleUI.editor
        words='Élara shared her last loaf.\nA kindness I want to remember.';g.MOCK.Type(f.bodyInput,words);c.click(f.save)
        self.assertEqual(e.memories[1].title,'Élara shared her last loaf.');self.assertEqual(e.memories[1].note,words)
        self.assertEqual(g.CMJourney.reader.body.GetText(g.CMJourney.reader.body).count('Élara shared her last loaf.'),1)
        g.CMJourney.Write(e.guid);g.MOCK.Type(f.bodyInput,'旅'*80);c.click(f.save)
        title=e.memories[2].title;self.assertLessEqual(len(title.encode()),96);self.assertEqual(title,'旅'*32)

    def test_not_now_stays_quiet_but_the_pending_moment_is_one_click_away(self):
        c,g=self.c,self.g;e=c.target();c.advance(2);c.click(g.CMJourney.notice.story)
        self.assertFalse(g.CMJourney.notice.IsShown(g.CMJourney.notice));self.assertEqual(len(e.memoryCandidates),1);self.assertEqual(len(e.memories),0)
        c.advance(31);c.target();c.advance(2);self.assertFalse(g.CMJourney.notice.IsShown(g.CMJourney.notice))
        g.CMJ.Toggle();g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;c.click(u.tabs.memories);c.click(u.rows[1])
        self.assertTrue(u.editor.IsShown(u.editor));self.assertEqual(u.editor.bodyInput.GetText(u.editor.bodyInput),'')

    def test_recently_continued_promise_wins_a_same_second_tie(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle
        first=m.SaveMoment(e.guid,e.memoryCandidates[1].id,'We met by the bridge.','','Bring a map',None);old=e.stories[1]
        newer=m.AddStory(e.guid,'A different new plan','');g.CMJourney.Reveal(e.guid);g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;u.SetMode('stories');c.click(u.rows[2])
        c.click(g.CMJourney.reader.write);g.MOCK.Type(u.editor.bodyInput,'We worked on our map again.');c.click(u.editor.save)
        memory,story=m.Recollection(e.guid);self.assertEqual(story.id,old.id);self.assertEqual(memory.id,old.latestMemoryID)
        self.assertNotEqual(story.id,newer);self.assertEqual(memory.fromMemoryID,first)
        self.return_after();self.assertEqual(g.CMJourney.Candidate(e.guid).storyID,old.id)

    def test_a_draft_has_one_obvious_action_and_keeps_its_original_encounter(self):
        c,g=self.c,self.g;e=c.target();c.advance(2);c.click(g.CMJourney.notice.keep);f=g.CMChronicleUI.editor
        stamp=f.item.at;g.MOCK.Type(f.bodyInput,'A detail I have not finished writing.');c.click(f.cancel);self.return_after()
        n=g.CMJourney.notice;self.assertEqual(n.keep.GetText(n.keep),'Continue draft');self.assertIn('unfinished page',n.words.GetText(n.words))
        c.click(n.keep);self.assertEqual(f.item.at,stamp);self.assertEqual(f.bodyInput.GetText(f.bodyInput),'A detail I have not finished writing.')
        c.click(f.save);self.assertEqual(e.memories[1].at,stamp);self.assertEqual(e.memories[1].kind,'meeting');self.assertIsNone(e.journalDraft)

    def test_a_new_plan_during_prompt_dwell_is_not_mistaken_for_the_reunion_promise(self):
        c,g=self.c,self.g;e=c.target();g.CMChronicle.Remember(e.guid,None,'We spoke about the road.','The road');g.CMJourney.CancelNotice()
        target=g.MOCK.units.target;g.MOCK.units.target=None;c.emit('PLAYER_TARGET_CHANGED');c.advance(3601);g.MOCK.units.target=target;c.target()
        g.CMChronicle.AddStory(e.guid,'An unrelated plan created after this encounter','');c.advance(2);n=g.CMJourney.notice
        self.assertNotIn('unrelated',n.words.GetText(n.words));self.assertEqual(n.keep.GetText(n.keep),'Keep a memory');c.click(n.keep)
        self.assertIsNone(g.CMChronicleUI.editor.resolveID);self.assertIsNone(g.CMChronicleUI.editor.continueID)

    def test_prompt_excerpt_is_short_and_newlines_do_not_push_the_promise_away(self):
        c,g=self.c,self.g;e=c.target();g.CMChronicle.SaveMoment(e.guid,e.memoryCandidates[1].id,'A detail.\n'*60,'','A promise.\n'*10,None)
        self.return_after();words=g.CMJourney.notice.words.GetText(g.CMJourney.notice.words)
        self.assertTrue(words.startswith('You meant to:'));self.assertEqual(words.count('\n'),1);self.assertLessEqual(len(words.encode()),210)
        self.assertIn('Last time:',words)

    def test_removing_the_latest_chapter_falls_back_to_the_origin_without_self_links(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle
        first=m.SaveMoment(e.guid,e.memoryCandidates[1].id,'We made a promise.','','Return the map',None);story=e.stories[1]
        second=m.SaveMoment(e.guid,None,'A later chapter.','','',None,story.id)
        m.Remove(e.guid,second);memory,active=m.Recollection(e.guid);self.assertEqual(memory.id,first);self.assertEqual(active.id,story.id)
        g.CMJourney.ReadStory(e.guid,story.id);self.assertIn('We made a promise.',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        c.click(g.CMJourney.reader.write);f=g.CMChronicleUI.editor;g.MOCK.Type(f.bodyInput,'The story continues.');c.click(f.save)
        latest=m.Find(e.guid,'memories',story.latestMemoryID);self.assertEqual(latest.fromMemoryID,first);self.assertNotEqual(latest.fromMemoryID,latest.id)

    def test_all_current_journal_and_dialog_presentation_declarations_are_exact(self):
        baseline=json.loads((ROOT/'tests/fixtures/loop-presentation.json').read_text())
        for name,expected in baseline['files'].items():self.assertEqual(hashlib.sha256(presentation_source(ADDON/name).encode()).hexdigest(),expected,name)
        for name,expected in baseline['declarations'].items():self.assertEqual(declarations((ADDON/name).read_text()),expected,name)


class RestoredStyleTests(unittest.TestCase):
    def test_complete_journal_markup_matches_pre_polish_release(self):
        baseline=json.loads((ROOT/'tests/fixtures/journal-style.json').read_text())
        data=(ADDON/'CharacterMemory.xml').read_bytes()
        # The entire template set and root, including every font/color/anchor/achievement row.
        prefix=data[:data.index(b'  <Frame name="CM_OptionsPanel"')]
        self.assertEqual(hashlib.sha256(prefix).hexdigest(),baseline['journal_xml_prefix_sha256'])

    def test_journal_runtime_styling_matches_pre_polish_release(self):
        baseline=json.loads((ROOT/'tests/fixtures/journal-style.json').read_text())
        for name,expected in baseline['lua_sha256'].items():
            source=presentation_source(ADDON/name)
            if name=='CM_Journal.lua':
                # Full file lock: only the existing self/unnamed-record filter is normalized.
                source=source.replace('\n      and id ~= CMCompat.UnitGUID("player") and type(e.name) == "string" and e.name ~= "" then',' then')
                self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),expected,name)
            else:
                # Behavior can evolve; every native widget/font/geometry/color declaration stays fixed.
                self.assertEqual(declarations(protected_source(source,name)),baseline['presentation_declarations'][name],name)
                for section,body in constructors(source,name).items():
                    self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),baseline['constructors_sha256'][name][section],name+':'+section)
        self.assertFalse((ADDON/'CM_Desk.lua').exists())

    def test_class_colors_return_in_list_and_selected_name(self):
        c=Client();e=c.target();c.g.CMJ.Toggle()
        for kind,rgb in [('MAGE',(0.4,0.8,1)),('WARRIOR',(0.8,0.6,0.4)),('PALADIN',(1,0.4,0.8))]:
            c.g.RAID_CLASS_COLORS[kind]=c.table(dict(zip(['r','g','b'],rgb)));e.classFile=kind
            c.g.CMUI.Select(e.guid)
            expected='|cff'+''.join(format(int(v*255),'02x') for v in rgb)+e.name+'|r'
            self.assertEqual(c.g.CMJ.refs.rows[1].name.GetText(c.g.CMJ.refs.rows[1].name),expected)
            self.assertEqual(c.g.CMJ.refs.title.GetText(c.g.CMJ.refs.title),expected)
        c.g.CMUI.TabSwap('Achievements');self.assertEqual(len(c.g.CMJ.refs.achRows),8)

    def test_admin_fixes_are_unchanged_from_polish_build(self):
        baseline=json.loads((ROOT/'tests/fixtures/journal-style.json').read_text())
        for name,expected in baseline['admin_sha256'].items():
            self.assertEqual(hashlib.sha256(presentation_source(ADDON/name).encode()).hexdigest(),expected,name)


class ExperienceTests(unittest.TestCase):
    def setUp(self):
        self.c=Client(); self.g=self.c.g

    def open_achievements(self):
        e=self.c.target(); self.g.CMJ.Toggle()
        self.c.click(self.g.CMJ_RootXMLPageRTabBarTabAchievements)
        return e

    def test_legacy_meeting_chatter_is_reset_once_and_can_be_opted_into(self):
        c=Client({'settings':{'shareEnabled':True},'entries':{}})
        self.assertFalse(c.g.CharacterMemoryDB.settings.shareEnabled)
        c.target();self.assertEqual(len(c.g.MOCK.chat),0)
        c.g.CharacterMemoryDB.settings.shareEnabled=True
        restored=Client(plain(c.g.CharacterMemoryDB))
        self.assertTrue(restored.g.CharacterMemoryDB.settings.shareEnabled)

    def test_normal_startup_progress_and_claims_do_not_write_chat(self):
        self.assertEqual(len(self.g.MOCK.chat),0)
        e=self.open_achievements()
        for _ in range(10): self.g.CharacterMemory_AwardXP(e.guid,100,'test')
        self.c.click(self.g.CMJ.refs.achRows[1].claim)
        self.assertEqual(len(self.g.MOCK.chat),0)
        self.assertIn('claimed',self.g.CMExperience.hint.GetText(self.g.CMExperience.hint))
        self.assertEqual(self.g.CMJ.refs.achRows[1].claim.GetText(self.g.CMJ.refs.achRows[1].claim),'Claimed')

    def test_switching_people_cannot_claim_for_previous_person(self):
        first=self.open_achievements(); old_click=self.g.CMJ.refs.achRows[1].claim.GetScript(self.g.CMJ.refs.achRows[1].claim,'OnClick')
        second=self.c.entry('Player-1-SECOND');second.name='Second'
        self.g.CMUI.Select(second.guid)
        self.assertFalse(self.g.CMJ.refs.achRows[1].claim.IsEnabled(self.g.CMJ.refs.achRows[1].claim))
        old_click()
        self.assertIsNone(first.ach.claimed.first_meet)
        self.assertIn('Second',self.g.CMExperience.title.GetText(self.g.CMExperience.title))

    def test_all_twelve_achievements_are_accessible_and_fit_page(self):
        self.open_achievements(); names=[]; geo=Geometry(self.c)
        for page in range(3):
            for row in self.g.CMJ.refs.achRows.values():
                if row.shown:
                    names.append(row.title.GetText(row.title))
                    self.assertTrue(geo.contains(self.g.CMJ.refs.achievements,row))
            if page<2:self.c.click(self.g.CMExperience.next)
        self.assertEqual(len(set(names)),12)
        self.assertFalse(self.g.CMExperience.next.IsEnabled(self.g.CMExperience.next))
        self.assertTrue(geo.contains(self.g.CMJ.refs.achievements,self.g.CMExperience.next))
        self.c.click(self.g.CMExperience.previous)
        self.assertEqual(self.g.CMExperience.page,2)

    def test_empty_and_filtered_journal_give_guidance(self):
        self.g.CMJ.Toggle();self.c.click(self.g.CMJ_RootXMLPageRTabBarTabAchievements)
        self.assertTrue(self.g.CMExperience.empty.shown)
        self.assertIn('Target another player',self.g.CMExperience.empty.GetText(self.g.CMExperience.empty))
        self.c.target();self.g.CMUI.Select('Player-1-ELARA')
        self.assertFalse(self.g.CMExperience.empty.shown)
        self.g.CMJ.refs.search.SetText(self.g.CMJ.refs.search,'no such person')
        self.assertTrue(self.g.CMExperience.empty.shown)
        self.assertFalse(any(r.shown for r in self.g.CMJ.refs.achRows.values()))

    def test_emote_completion_refreshes_visible_progress_and_rank_immediately(self):
        e=self.open_achievements();self.g.CharacterMemory_AwardXP(e.guid,400,'test')
        self.c.emit('CHAT_MSG_TEXT_EMOTE','Elara kisses you.','Elara-FictionalRealm')
        self.c.emit('CHAT_MSG_TEXT_EMOTE','Elara loves you.','Elara-FictionalRealm')
        self.assertTrue(e.relationshipUnlocked)
        self.assertEqual(self.g.CharacterMemory_GetAchievementSummary(e.guid).done,3)
        self.assertTrue(self.g.CMJ.refs.achRows[3].claim.IsEnabled(self.g.CMJ.refs.achRows[3].claim))
        self.assertEqual(len(self.g.MOCK.chat),0)

    def test_claim_is_once_only_and_persists_after_reload(self):
        e=self.open_achievements();xp=e.xp
        self.assertTrue(self.g.CharacterMemory_ClaimAchievement(e.guid,'first_meet'))
        self.assertIsNone(self.g.CharacterMemory_ClaimAchievement(e.guid,'first_meet'))
        self.assertEqual(e.xp,xp+50)
        restored=Client(plain(self.g.CharacterMemoryDB))
        self.assertFalse(restored.g.CharacterMemory_GetAchievements(e.guid)[1].claimable)
        self.assertEqual(restored.g.CharacterMemoryDB.entries[e.guid].xp,xp+50)

    def test_lifetime_emote_milestones_survive_weekly_history_pruning(self):
        e=self.open_achievements();self.g.CM_LogEmoteForAchievements(e.guid,'kiss')
        self.g.MOCK.epoch += 8*86400
        self.assertTrue(self.g.CharacterMemory_GetAchievements(e.guid)[2].done)
        self.g.CharacterMemory_ClaimAchievement(e.guid,'first_kiss')
        self.assertTrue(self.g.CharacterMemory_GetAchievements(e.guid)[2].done)

    def test_weekly_emotes_are_bounded_and_repeatable(self):
        e=self.open_achievements()
        for _ in range(1000):self.g.CM_LogEmoteForAchievements(e.guid,'hug')
        self.assertEqual(len(e.ach.history.emotes.hug),10)
        self.assertTrue(self.g.CharacterMemory_ClaimAchievement(e.guid,'hug_weekly_10'))
        self.assertFalse(self.g.CharacterMemory_GetAchievements(e.guid)[4].claimable)
        self.g.MOCK.epoch += 8*86400
        self.assertFalse(self.g.CharacterMemory_GetAchievements(e.guid)[4].done)
        for _ in range(10):self.g.CM_LogEmoteForAchievements(e.guid,'hug')
        self.assertTrue(self.g.CharacterMemory_ClaimAchievement(e.guid,'hug_weekly_10'))

    def test_status_uses_loaded_addon_metadata(self):
        self.g.C_AddOns=self.c.table({'GetAddOnMetadata':self.g.loadstring('return function() return "9.8.7" end')()})
        self.g.SlashCmdList.CHARACTERMEMORY('status')
        self.assertIn('9.8.7',self.g.MOCK.chat[1].text)

    def test_delete_command_requires_confirmation_and_hide_closes_journal(self):
        e=self.open_achievements();self.g.SlashCmdList.CHARACTERMEMORY('delete')
        self.assertIsNotNone(self.g.CharacterMemoryDB.entries[e.guid])
        self.g.MOCK.AcceptPopup()
        self.assertIsNone(self.g.CharacterMemoryDB.entries[e.guid])
        self.g.SlashCmdList.CHARACTERMEMORY('hide')
        self.assertFalse(self.g.CMJ.refs.root.shown)

    def test_public_summary_requires_preview_and_never_sends_private_writing(self):
        e=self.open_achievements();e.notes='PRIVATE NOTE'
        self.g.CharacterMemory_Share(e.guid)
        self.assertEqual(len(self.g.MOCK.chat),0)
        self.g.MOCK.AcceptPopup()
        self.assertEqual(len(self.g.MOCK.chat),1)
        self.assertEqual(self.g.MOCK.chat[1].channel,'SAY')
        self.assertNotIn('PRIVATE',self.g.MOCK.chat[1].text)

    def test_summary_is_not_posted_to_a_changed_channel(self):
        e=self.open_achievements();self.g.CharacterMemory_Share(e.guid)
        self.g.MOCK.grouped=True;self.g.MOCK.AcceptPopup()
        self.assertEqual(len(self.g.MOCK.chat),0)

    def test_inspection_reads_current_target_and_rejects_stale_responses(self):
        e=self.c.target()
        self.c.lua.execute('C_PaperDollInfo={GetInspectItemLevel=function(unit) assert(unit=="target"); return 42 end}')
        self.c.emit('INSPECT_READY',e.guid);self.assertEqual(e.itemLevel,42)
        other=self.c.entry('Player-1-OLD')
        self.c.emit('INSPECT_READY',other.guid);self.assertIsNone(other.itemLevel)

    def test_plain_cm_opens_journal_and_explicit_help_is_available(self):
        self.g.SlashCmdList.CHARACTERMEMORY('')
        self.assertTrue(self.g.CMJ.refs.root.shown)
        self.assertEqual(len(self.g.MOCK.chat),0)
        self.g.SlashCmdList.CHARACTERMEMORY('help')
        self.assertGreater(len(self.g.MOCK.chat),0)

    def test_activity_events_reach_the_catalogue_goals(self):
        e=self.c.target();g=self.g;c=self.c
        g.MOCK.grouped=True;g.MOCK.units.party1=g.MOCK.units.target
        for _ in range(3):c.emit('DUEL_FINISHED')
        for _ in range(10):
            c.emit('CHAT_MSG_WHISPER','not retained','Elara-FictionalRealm');c.advance(61)
        g.MOCK.resting=True;c.lua.execute('CheckInteractDistance=function() return true end');c.advance(1800)
        g.MOCK.instance=True;g.MOCK.instanceType='raid';c.emit('ENCOUNTER_END',123,'Boss',1,5,1)
        g.MOCK.instanceType='party';c.emit('LFG_COMPLETION_REWARD')
        g.MOCK.instanceType='pvp'
        for _ in range(5):c.emit('PVP_MATCH_COMPLETE')
        g.MOCK.instanceType='arena'
        for _ in range(3):c.emit('PVP_MATCH_COMPLETE')
        for emote in ['kiss','love']+['hug']*10:g.CM_LogEmoteForAchievements(e.guid,emote)
        achieved=list(g.CharacterMemory_GetAchievements(e.guid).values())
        self.assertEqual(len(achieved),12)
        self.assertTrue(all(a.done for a in achieved),[(a.id,a.cur) for a in achieved if not a.done])
        self.assertNotIn('not retained',json.dumps(plain(g.CharacterMemoryDB)))

    def test_invalid_manual_xp_cannot_corrupt_entry(self):
        e=self.c.target();xp=e.xp
        self.g.SlashCmdList.CHARACTERMEMORY('reladd 1e999')
        self.assertEqual(e.xp,xp)


class ReleaseBoundaryTests(unittest.TestCase):
    def test_unsupported_clients_preserve_data_and_do_not_start_modules(self):
        for version, interface in [('12.0.0', 120000), ('1.15.8', 11508),
                                   ('1.60.2', 16002), ('other', 16001), ('1.60.1', 16000)]:
            with self.subTest(version=version, interface=interface):
                saved={'version': 1, 'entries': {'Player-1-OLD': {'notes': 'Keep me'}}}
                c=Client(saved=saved, setup=f"GetBuildInfo=function() return '{version}','1','date',{interface} end")
                self.assertFalse(c.g.CMCompat.supported)
                self.assertEqual(plain(c.g.CharacterMemoryDB), saved)
                self.assertIsNone(c.g.RPJournalDB)
                self.assertIsNone(c.g.CMProtocol)
                self.assertIsNone(c.g.CMJ)
                self.assertEqual(len(c.g.MOCK.timers), 0)
                self.assertEqual(len(c.g.MOCK.messages), 0)
                c.g.CharacterMemory_OpenJournal()
                c.g.CharacterMemory_RememberTarget()
                self.assertIn('Addon disabled', c.g.MOCK.chat[1].text)

    def test_missing_build_api_fails_closed(self):
        c=Client(setup='GetBuildInfo=nil')
        self.assertFalse(c.g.CMCompat.supported)
        self.assertIsNone(c.g.CharacterMemoryDB)

    def test_every_loaded_module_has_client_guard(self):
        for line in (ADDON/'CharacterMemory.toc').read_text().splitlines():
            if line.endswith('.lua') and line != 'CM_Compat.lua':
                self.assertTrue((ADDON/line).read_text().startswith(CLIENT_GUARD), line)

    def test_stopping_transport_cancels_old_pump_and_allows_restart(self):
        c=Client(); c.target(); p=c.g.CMProtocol
        c.g.MOCK.sendResult=3
        p.Request('Elara-FictionalRealm','Player-1-ELARA')
        p.Stop(); c.advance(5)
        self.assertEqual(len(c.g.MOCK.messages), 1)
        c.advance(31); c.g.MOCK.sendResult=0
        self.assertTrue(p.Request('Elara-FictionalRealm','Player-1-ELARA'))
        self.assertEqual(len(c.g.MOCK.messages), 2)

    def test_profile_sharing_requires_boolean_opt_in(self):
        c=Client(); c.g.CharacterMemoryDB.settings.bioSharing='false'
        self.assertFalse(c.g.CMProtocol.Receive('RPJ2','REQ|abc','WHISPER','Other-FictionalRealm'))
        self.assertEqual(len(c.g.MOCK.messages), 0)


class ProtocolTests(unittest.TestCase):
    def test_two_peers_opt_in_chunking_and_private_projection(self):
        a,b=Client(),Client(setup="MOCK.units.player,MOCK.units.target=MOCK.units.target,MOCK.units.player")
        a.target(); b.target()
        bio=b.g.CMProfile.Ensure(); bio.lore.shortBio='é|map:maker\n'+('B'*480)
        bio.notes.private='PRIVATE SECRET'; bio.lore.backstory='PRIVATE BACKSTORY'; bio.rpPrefs.oocContact='PRIVATE CONTACT'
        b.g.RPBioFrame.Show(b.g.RPBioFrame); b.g.RPBio_PublicSharing.SetChecked(b.g.RPBio_PublicSharing,True); b.g.RPBio_Save()
        b.entry('Player-1-ELARA').journalDraft=b.table({'note':'PRIVATE DRAFT WORDS','kind':'memory'})
        expected=b.g.CMProfile.PublicFields()[1]
        self.assertTrue(expected.startswith('é|map:maker\n'))
        self.assertEqual(bio.lore.backstory,'PRIVATE BACKSTORY')
        self.assertEqual(bio.notes.private,'PRIVATE SECRET')
        self.assertIsNone(b.g.RPBio_ShortBioEditBox)  # Forever exposes an anonymous .EditBox.
        self.assertTrue(a.g.CMProtocol.Request('Elara-FictionalRealm','Player-1-ELARA'))
        req=a.g.MOCK.messages[1]
        self.assertTrue(b.g.CMProtocol.Receive(req.prefix,req.message,'WHISPER','Rowan-FictionalRealm'))
        b.advance(10)
        packets=list(b.g.MOCK.messages.values()); self.assertGreater(len(packets),1)
        for p in packets: self.assertLessEqual(len(p.message.encode()),250)
        for p in reversed(packets): a.g.CMProtocol.Receive(p.prefix,p.message,'WHISPER','Elara-FictionalRealm')
        received=a.g.CharacterMemoryDB.entries['Player-1-ELARA'].publicProfile
        self.assertEqual(received[1],expected)
        self.assertNotIn('PRIVATE',json.dumps(plain(received)))
        self.assertFalse(a.g.CMProtocol.Receive(req.prefix,packets[0].message,'WHISPER','Elara-FictionalRealm'))
        self.assertFalse(a.g.CMProtocol.Request('Elara-FictionalRealm','Player-1-ELARA'))

    def test_unsolicited_wrong_sender_guid_token_expiry_and_bad_payload(self):
        c=Client(); c.target(); p=c.g.CMProtocol
        fields=c.table(['A bio']+['']*16); encoded=p.Encode(fields)
        self.assertEqual(p.Decode(encoded)[1],'A bio')
        self.assertIsNone(p.Decode('ff')); self.assertIsNone(p.Decode('GG'))
        self.assertFalse(p.Receive(p.PREFIX,'REQ|abc','WHISPER','Other-FictionalRealm'))
        self.assertEqual(len(c.g.MOCK.messages),0)
        p.Request('Elara-FictionalRealm','Player-1-ELARA')
        token=p.pending['elara-fictionalrealm'].token
        packet=f'BIO|{token}|1|1|Player-1-ELARA|{encoded}'
        self.assertFalse(p.Receive(p.PREFIX,packet,'WHISPER','Other-FictionalRealm'))
        self.assertFalse(p.Receive(p.PREFIX,packet.replace(token,'bad'),'WHISPER','Elara-FictionalRealm'))
        self.assertFalse(p.Receive(p.PREFIX,packet.replace('Player-1-ELARA','Player-1-FAKE'),'WHISPER','Elara-FictionalRealm'))
        c.advance(31); self.assertFalse(p.Receive(p.PREFIX,packet,'WHISPER','Elara-FictionalRealm'))
        self.assertIsNone(c.g.CharacterMemoryDB.entries['Player-1-ELARA'].publicProfile)

    def test_transport_failure_retries_are_bounded(self):
        c=Client(); c.target(); c.g.MOCK.sendResult=3
        self.assertTrue(c.g.CMProtocol.Request('Elara-FictionalRealm','Player-1-ELARA'))
        c.advance(5); self.assertEqual(len(c.g.MOCK.messages),3); self.assertEqual(len(c.g.CMProtocol.queue),0)


class StorybookTests(unittest.TestCase):
    def setUp(self): self.c=Client();self.g=self.c.g

    def arc(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle
        first=m.SaveMoment(e.guid,e.memoryCandidates[1].id,'She gave me the map.','','Return the map',None)
        story=e.stories[1]
        second=m.SaveMoment(e.guid,None,'We found a safer road.','','',None,story.id)
        unrelated=m.SaveMoment(e.guid,None,'A different evening.','','',None)
        third=m.SaveMoment(e.guid,None,'The map is home.','','Meet at sunset',story.id,story.id)
        return e,story,first,second,third,unrelated

    def choose(self, caption):
        for item in self.g.MOCK.menu.values():
            if item.text==caption:
                self.assertFalse(item.disabled,caption);item.func();return
        self.fail('Missing menu action: '+caption+' in '+str([x.text for x in self.g.MOCK.menu.values()]))

    def test_chapters_preserve_order_and_a_shared_ending_belongs_to_both_threads(self):
        e,s,first,second,third,other=self.arc();m=self.g.CMChronicle
        self.assertEqual([x.id for x in m.Chapters(e.guid,s.id).values()],[third,second,first])
        self.assertEqual([x.id for x in m.Chapters(e.guid,e.stories[2].id).values()],[third])
        self.assertEqual(len(m.Chapters(e.guid,'missing')),0)

    def test_deleting_origin_and_latest_retains_middle_chapter_for_reunion(self):
        e,s,first,second,third,other=self.arc();m=self.g.CMChronicle
        m.Remove(e.guid,first);m.Remove(e.guid,third)
        self.assertEqual(m.StoryMemory(e.guid,s).id,second)
        self.assertEqual([x.id for x in m.Chapters(e.guid,s.id).values()],[second])

    def test_chapter_reader_stays_in_one_thread_and_edits_the_visible_chapter(self):
        e,s,first,second,third,other=self.arc();g=self.g;c=self.c;g.SlashCmdList=c.table({})
        g.CMJourney.ReadChapters(e.guid,s.id);r=g.CMJourney.reader
        self.assertEqual(r.memoryID,third);self.assertEqual(r.pageCount.GetText(r.pageCount),'Chapter 3 / 3')
        c.click(r.older);self.assertEqual(r.memoryID,second);c.click(r.older);self.assertEqual(r.memoryID,first)
        self.assertFalse(r.older.IsEnabled(r.older));c.click(r.newer);self.assertEqual(r.memoryID,second)
        c.click(r.all);f=g.CMChronicleUI.editor;self.assertEqual(f.item.id,second)
        g.MOCK.Type(f.bodyInput,'The road was safer together.');c.click(f.save)
        self.assertEqual(g.CMChronicle.Find(e.guid,'memories',second).note,'The road was safer together.')
        self.assertEqual(g.CMChronicle.Find(e.guid,'memories',other).note,'A different evening.');self.assertEqual(len(g.SlashCmdList),0)

    def test_writing_from_an_unthreaded_memory_does_not_borrow_a_later_promise(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle
        page=m.Remember(e.guid,None,'A memory without a promise.','The inn')
        unrelated=m.AddStory(e.guid,'A different plan','');g.CMJourney.Read(e.guid,page)
        self.assertIsNone(g.CMJourney.reader.threadID);c.click(g.CMJourney.reader.write)
        self.assertIsNone(g.CMChronicleUI.editor.continueID);self.assertIsNone(g.CMChronicleUI.editor.resolveID)
        g.MOCK.Type(g.CMChronicleUI.editor.bodyInput,'Another quiet evening.');c.click(g.CMChronicleUI.editor.save)
        self.assertIsNone(e.memories[len(e.memories)].continuedStoryID)
        self.assertEqual(m.Find(e.guid,'stories',unrelated).state,'open')

    def test_reading_a_finished_thread_does_not_attach_its_next_page_to_another_plan(self):
        e,s,*_=self.arc();g=self.g;g.CMJourney.ReadChapters(e.guid,s.id);self.c.click(g.CMJourney.reader.write)
        self.assertIsNone(g.CMChronicleUI.editor.continueID);self.assertIsNone(g.CMChronicleUI.editor.resolveID)

    def test_open_thread_continuation_keeps_its_scope_when_another_promise_exists(self):
        e,s,*_=self.arc();g=self.g;m=g.CMChronicle;m.UpdateStory(e.guid,s.id,s.title,s.note,'open')
        g.CMJourney.ReadChapters(e.guid,s.id);self.c.click(g.CMJourney.reader.write)
        self.assertEqual(g.CMChronicleUI.editor.continueID,s.id)

    def test_existing_overview_control_opens_native_menu_and_every_core_action_is_clickable(self):
        e,s,*_=self.arc();g=self.g;c=self.c;g.SlashCmdList=c.table({});g.CMJourney.Reveal(e.guid)
        c.click(g.CMChronicleUI.ourStory);self.choose('Finished stories');self.choose(s.title);self.choose('Read chapters')
        self.assertEqual(g.CMJourney.reader.chapterStoryID,s.id);self.assertEqual(len(g.SlashCmdList),0)

    def test_search_matches_authored_words_places_keepsakes_and_threads_without_lua_patterns(self):
        e,s,first,*_=self.arc();g=self.g;m=g.CMChronicle
        m.SetKeepsake(e.guid,first,'A ribbon [blue]');s.note='Our secret signal at dusk'
        for term,expected in [('ribbon [blue]',first),('safer road',None),('Goldshire',None),('secret signal',s.id)]:
            rows=list(m.Search(e.guid,term).values());self.assertGreater(len(rows),0,term)
            if expected:self.assertIn(expected,[x.id for x in rows])
        self.assertEqual(len(m.Search(e.guid,'[.*%')),0);self.assertEqual(len(m.Search(e.guid,'   ')),0)

    def test_search_popup_returns_clickable_results_and_never_writes_journal_text(self):
        e,s,first,*_=self.arc();g=self.g;c=self.c;before=json.dumps(plain(e.memories),sort_keys=True)
        g.CMStorybook.Open(e.guid);self.choose('Find a memory or story...');p=g.MOCK.popup
        g.MOCK.Type(p.editBox,'safer road');g.MOCK.AcceptPopup();self.choose('We found a safer road.')
        self.choose('Read memory');self.assertIn('safer road',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        self.assertEqual(json.dumps(plain(e.memories),sort_keys=True),before)

    def test_paged_menus_can_reach_all_100_memories_and_places_without_truncation(self):
        c,g=self.c,self.g;e=c.target();m=g.CMChronicle;m.Dismiss(e.guid,e.memoryCandidates[1].id)
        for n in range(100):m.Remember(e.guid,None,'Page '+str(n),'Memory '+str(n),'Place '+str(n))
        g.CMStorybook.Open(e.guid,'memories');seen=[]
        while True:
            rows=[x for x in g.MOCK.menu.values() if x.text.startswith('Memory ')];seen.extend(x.text for x in rows)
            if any(x.text=='Next page >' for x in g.MOCK.menu.values()):self.choose('Next page >')
            else:break
        self.assertEqual(len(seen),100);self.assertEqual(len(set(seen)),100)
        self.assertEqual(len(m.Places(e.guid)),100)

    def test_keepsakes_are_bounded_private_references_and_never_fake_inventory(self):
        e,s,first,*_=self.arc();g=self.g;m=g.CMChronicle
        link='|cffffffff|Hitem:6948::::::::1:::::::::|h[Hearthstone]|h|r'
        self.assertTrue(m.SetKeepsake(e.guid,first,link));kept=m.Find(e.guid,'memories',first)
        self.assertEqual(kept.keepsake.itemID,6948);self.assertEqual(kept.keepsake.label,'[Hearthstone]')
        g.CMJourney.Read(e.guid,first);self.assertIn('A keepsake',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        self.assertIn('[Hearthstone]',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        before=json.dumps(plain(kept.keepsake),sort_keys=True)
        for bad in ['|Hspell:123|h[Spell]|h','|Tbad:300|t','|Hitem:0|h[No item]|h','x'*161,'line\none','|Hitem:12|h[bad|t]|h','|cffffffff|Hitem:12|h[x]|h','|Hitem:12:--3|h[x]|h','|Hitem:12|h[x]|h|r']:
            result=m.SetKeepsake(e.guid,first,bad);self.assertFalse(result[0] if isinstance(result,tuple) else result,bad)
            self.assertEqual(json.dumps(plain(kept.keepsake),sort_keys=True),before)
        self.assertTrue(m.SetKeepsake(e.guid,first,'The blue ribbon'));self.assertIsNone(kept.keepsake.itemID)
        self.assertTrue(m.SetKeepsake(e.guid,first,''));self.assertIsNone(kept.keepsake)
        self.assertNotIn('Hearthstone',json.dumps(plain(g.CMProfile.PublicFields())))

    def test_keepsake_popup_retains_invalid_input_then_saves_to_its_original_person(self):
        e,s,first,*_=self.arc();g=self.g;c=self.c;g.CMStorybook.Open(e.guid,'memory',1,first);self.choose('Keep a keepsake...')
        p=g.MOCK.popup;g.MOCK.Type(p.editBox,'|Tbad|t');g.MOCK.AcceptPopup();self.assertIsNotNone(g.MOCK.popup)
        other=c.entry('Player-1-OTHER');other.name='Mara';other.isPlayer=True;g.CMJourney.Reveal(other.guid)
        g.MOCK.Type(p.editBox,'A blue ribbon');g.MOCK.AcceptPopup();self.assertIsNone(g.MOCK.popup)
        self.assertEqual(g.CMChronicle.Find(e.guid,'memories',first).keepsake.label,'A blue ribbon')
        self.assertEqual(len(other.memories),0)

    def test_copy_preview_includes_only_the_selected_memory_and_sends_nothing(self):
        e,s,first,*_=self.arc();g=self.g;c=self.c;e.notes='PRIVATE NOTES';e.journalDraft=c.table({'note':'PRIVATE DRAFT'})
        g.CMChronicle.SetKeepsake(e.guid,first,'A ribbon');before=len(g.MOCK.messages);before_chat=len(g.MOCK.chat)
        g.CMStorybook.Open(e.guid,'memory',1,first);self.choose('Copy this memory...');f=g.CMStorybook.copyFrame
        words=f.input.GetText(f.input);self.assertIn('She gave me the map.',words);self.assertIn('A ribbon',words)
        for private in ['PRIVATE','safer road','Meet at sunset','Return the map']:self.assertNotIn(private,words)
        self.assertEqual(len(g.MOCK.messages),before);self.assertEqual(len(g.MOCK.chat),before_chat)
        g.MOCK.Type(f.input,'Edited only for sharing');self.assertEqual(e.memories[1].note,'She gave me the map.')

    def test_stale_menu_ids_and_combat_cannot_write_the_wrong_page(self):
        e,s,first,*_=self.arc();g=self.g;c=self.c;g.CMStorybook.Open(e.guid,'memory',1,first)
        g.CMChronicle.Remove(e.guid,first);self.choose('Keep a keepsake...');self.assertIsNone(g.MOCK.popup)
        g.MOCK.combat=True;self.assertFalse(g.CMStorybook.Open(e.guid));self.assertFalse(g.CMJourney.ReadChapters(e.guid,s.id))

    def test_right_click_uses_the_clicked_row_while_left_click_still_reads_it(self):
        e,s,first,second,third,_=self.arc();g=self.g;c=self.c;g.CMJourney.Reveal(e.guid)
        g.CMUI.TabSwap('Notes');u=g.CMChronicleUI;u.SetMode('memories');rows=list(u.rows.values())
        saved=[row for row in rows if row.item and row.item.type=='memory']
        for row in saved:
            c.click(row);self.assertEqual(g.CMJourney.reader.memoryID,row.item.id)
            row.Run(row,'OnClick','RightButton');self.choose('Copy this memory...')
            self.assertIn(row.item.note,g.CMStorybook.copyFrame.input.GetText(g.CMStorybook.copyFrame.input))

    def test_places_pinned_and_keepsake_lists_open_the_exact_memory(self):
        e,s,first,second,third,_=self.arc();g=self.g;m=g.CMChronicle;m.Pin(e.guid,second);m.SetKeepsake(e.guid,first,'A ribbon')
        for view,title,expected in [('pinned','We found a safer road.',second),('keepsakes','She gave me the map.',first)]:
            g.CMStorybook.Open(e.guid,view);self.choose(title);self.choose('Read memory');self.assertEqual(g.CMJourney.reader.memoryID,expected)
        g.CMStorybook.Open(e.guid,'places');self.choose(m.Find(e.guid,'memories',first).where);self.choose('She gave me the map.');self.choose('Read memory')
        self.assertEqual(g.CMJourney.reader.memoryID,first)

    def test_pin_keepsake_and_thread_changes_refresh_the_open_reader(self):
        e,s,first,second,third,_=self.arc();g=self.g;c=self.c;g.CMJourney.ReadChapters(e.guid,s.id,first)
        g.CMStorybook.Open(e.guid,'memory',1,first);self.choose('Pin memory')
        self.assertIn('you pinned',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        g.CMStorybook.Open(e.guid,'memory',1,first);self.choose('Keep a keepsake...')
        g.MOCK.Type(g.MOCK.popup.editBox,'A ribbon');g.MOCK.AcceptPopup();self.assertIn('A ribbon',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        g.CMStorybook.Open(e.guid,'memory',1,first);self.choose('Remove keepsake');self.assertNotIn('A keepsake',g.CMJourney.reader.body.GetText(g.CMJourney.reader.body))
        self.assertEqual(g.CMJourney.reader.chapterStoryID,s.id)
        g.CMStorybook.Open(e.guid,'story',1,s.id);self.choose('Reopen thread');self.assertEqual(g.CMJourney.reader.threadID,s.id)
        self.assertEqual(g.CMJourney.reader.write.GetText(g.CMJourney.reader.write),'Continue story')

    def test_copy_dialog_has_a_bounded_scroll_area_and_native_fonts(self):
        e,s,first,*_=self.arc();g=self.g;c=self.c;g.CMStorybook.Copy(e.guid,first);f=g.CMStorybook.copyFrame;geo=Geometry(c)
        self.assertEqual((f.GetWidth(f),f.GetHeight(f)),(460,360));self.assertTrue(f.input.highlightedText)
        self.assertEqual(f.input.GetText(f.input).count('She gave me the map.'),1)
        for child in geo.descendants(f):
            if child.kind in ('Button','ScrollFrame','EditBox') or child.font:
                self.assertTrue(geo.contains(f,child,6),str(geo.relative(child,f)))
        g.MOCK.Emit('PLAYER_REGEN_DISABLED');self.assertFalse(f.IsShown(f));self.assertFalse(f.input.HasFocus(f.input))

    def test_reloading_preserves_keepsakes_links_and_chapter_order(self):
        e,s,first,second,third,_=self.arc();g=self.g;g.CMChronicle.SetKeepsake(e.guid,second,'A ribbon')
        saved=plain(g.CharacterMemoryDB);fresh=Client(saved);m=fresh.g.CMChronicle
        self.assertEqual([x.id for x in m.Chapters(e.guid,s.id).values()],[third,second,first])
        self.assertEqual(m.Find(e.guid,'memories',second).keepsake.label,'A ribbon')


if __name__=='__main__':
    unittest.main(verbosity=2)

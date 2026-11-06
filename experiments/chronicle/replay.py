#!/usr/bin/env python3
"""Historical baseline/prototype replay, pinned to a1b3b249.
Current integration tests live in tests/run.py. Replay real addon Lua against fictional WoW APIs. Requires lupa's Lua 5.1 runtime.

Run with: /Users/zchester/Downloads/WoWAddon/.venv/bin/python experiments/chronicle/replay.py
This does not render FrameXML, emulate the client, or contact the game/network.
"""
import argparse
import json
import subprocess
from pathlib import Path

from lupa.lua51 import LuaRuntime, lua_type

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BASELINE = "a1b3b249b5d2978815b4f9c02ce1faba8fef00e8"

def baseline_file(name):
    return subprocess.run(["git", "show", BASELINE + ":CharacterMemory/" + name],
                          cwd=ROOT, check=True, text=True, capture_output=True).stdout



def load_addon():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / "wow_mock.lua").read_text())
    manifest = baseline_file("CharacterMemory.toc")
    for name in manifest.splitlines():
        if name.strip().endswith(".lua"):
            path = ROOT / "CharacterMemory" / name.strip()
            chunk = lua.eval("loadstring")(baseline_file(name.strip()), "@baseline/" + name.strip())
            if isinstance(chunk, tuple):
                raise RuntimeError(chunk[1])
            chunk("CharacterMemory")
    lua.globals().MOCK.Emit("ADDON_LOADED", "CharacterMemory")
    return lua


def run(mode):
    lua = load_addon()
    g = lua.globals()
    g.MOCK.Emit("PLAYER_TARGET_CHANGED")
    entry = g.CharacterMemoryDB.entries["Player-1-ELARA"]
    assert entry.firstMetWhere == "Elwynn Forest - Goldshire"
    assert entry.xp == 50 and entry.stats.firstMeets == 1
    g.MOCK.Emit("CHAT_MSG_TEXT_EMOTE", "Elara waves at Rowan.", "Elara-FictionalRealm")
    g.MOCK.Emit("CHAT_MSG_WHISPER", "SYNTHETIC CHAT BODY", "Elara-FictionalRealm")
    assert entry.xp == 70 and entry.stats.emotes == 1 and entry.stats.whispers == 1
    g.MOCK.Advance(601)
    g.MOCK.Emit("PLAYER_TARGET_CHANGED")
    assert entry.stats.reconnects == 1 and entry.xp == 80
    g.SlashCmdList.CHARACTERMEMORY("note Promised to return with a map.")
    g.SlashCmdList.CHARACTERMEMORY("note A second recollection.")
    assert entry.notes == "A second recollection."
    baseline = {"xp": entry.xp, "encounters": entry.metCount,
                "notes": entry.notes, "timeline_stored": entry.timeline is not None}

    # Reproduce current issues without modifying the addon or calling game APIs.
    g.CharacterMemoryDB.entries["Player-1-RANK"] = None
    ranked = g.CharacterMemory_GetOrCreateEntry("Player-1-RANK")
    ranked.stats.firstMeets, ranked.stats.whispers, ranked.stats.dungeonCompletions = 1, 10, 1
    completed = g.CharacterMemory_GetAchievementSummary("Player-1-RANK").done
    g.CharacterMemory_AwardXP("Player-1-RANK", 100, "synthetic rank probe")
    blocked = ranked.level
    g.CharacterMemory_AwardXP("Player-1-RANK", 300, "synthetic rank probe")
    bypass = ranked.level
    assert completed == 3 and blocked == 0 and bypass == 2
    g.RPBio_ShortBioEditBox = g.CreateFrame("EditBox")
    g.RPBio_ShortBioEditBox.text = "A cartographer seeking old roads."
    g.RPBio_Save()
    g.MOCK.Emit("CHAT_MSG_ADDON", "CM1", "REQBIO|Player-1-ELARA", "WHISPER", "Elara-FictionalRealm")
    outgoing = g.MOCK.messages[len(g.MOCK.messages)].message
    assert g.RPJournalDB.bio.lore.shortBio == "A cartographer seeking old roads."
    assert "A cartographer seeking old roads." not in outgoing
    findings = {"rank_gate": {"completed_achievements": completed, "level_at_100_xp": blocked,
                             "level_at_400_xp": bypass},
                "character_sheet_bio_missing_from_outgoing_packet": True,
                "npc_entry_rejected": g.CharacterMemory_GetOrCreateEntry("Creature-0-123") is None}
    result = {"mode": mode, "boundary": "fictional Lua 5.1 replay, no game client", "baseline": baseline,
              "reproduced_observations": findings}
    if mode == "chronicle":
        chronicle = lua.execute((HERE / "MemoryChronicle.lua").read_text())
        saved = chronicle.Open(lua.table())

        def offer(event_id, kind, at, **extra):
            return chronicle.Offer(saved, lua.table_from({"id": event_id, "guid": "Player-1-ELARA",
                "name": "Elara", "where": "Elwynn Forest - Goldshire", "kind": kind, "at": at, **extra}))

        checks = 0

        def check(condition):
            nonlocal checks
            assert condition
            checks += 1

        check(offer("meeting-1", "meeting", 1000))
        check(len(chronicle.Timeline(saved, "Player-1-ELARA")) == 0)  # A cue isn't an accepted memory.
        check(chronicle.Remember(saved, "meeting-1", "She asked about the road to Westfall."))
        check(not offer("meeting-1", "meeting", 1000))
        offer("conversation-1", "conversation", 1020, chat_body="SYNTHETIC CHAT BODY")
        check(saved.candidates["conversation-1"].chat_body is None)
        check(chronicle.Dismiss(saved, "conversation-1"))
        check(not chronicle.Remember(saved, "conversation-1"))
        # Insert out of order, as can happen when separate observers report facts.
        offer("reunion-1", "reunion", 1700)
        chronicle.Remember(saved, "reunion-1", "We still owe each other that map.")
        offer("rest-1", "shared_rest", 1400)
        chronicle.Remember(saved, "rest-1", "A quiet pause before the road.")
        check(chronicle.Pin(saved, "rest-1"))
        timeline = chronicle.Timeline(saved, "Player-1-ELARA")
        check([row.kind for row in timeline.values()] == ["meeting", "shared_rest", "reunion"])
        check(timeline[2].pinned)
        timeline[1].note = "Attempt to edit a presentation copy"
        check(saved.memories["meeting-1"].note == "She asked about the road to Westfall.")
        def plain(value):
            return {key: plain(item) for key, item in value.items()} if lua_type(value) == "table" else value

        def restored(value):
            return lua.table_from({key: restored(item) for key, item in value.items()}) if isinstance(value, dict) else value

        # A serialized table round trip, not a claim about a live client's disk saves.
        serialized = json.dumps(plain(saved))
        check("SYNTHETIC CHAT BODY" not in serialized)
        reloaded_module = lua.execute((HERE / "MemoryChronicle.lua").read_text())
        reopened = reloaded_module.Open(restored(json.loads(serialized)))
        check(len(chronicle.Timeline(reopened, "Player-1-ELARA")) == 3)
        check(reopened.candidates["conversation-1"].status == "dismissed")
        check(not chronicle.Offer(reopened, lua.table_from({"id": "conversation-1", "guid": "Player-1-ELARA",
              "name": "Elara", "kind": "conversation", "at": 1020})))
        check(len(chronicle.Timeline(saved, "Player-1-OTHER")) == 0)
        recall = chronicle.Recall(reopened, "Player-1-ELARA")
        check(recall.id == "reunion-1" and recall.note == "We still owe each other that map.")
        check(chronicle.Recall(saved, "Player-1-OTHER") is None)
        result["experiment"] = {"checks_passed": checks,
            "memories": [{key: value for key, value in row.items()} for row in chronicle.Timeline(saved, "Player-1-ELARA").values()],
            "reunion_recall": {key: value for key, value in recall.items()}}
    print(json.dumps(result, sort_keys=True, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["baseline", "chronicle"], default="chronicle")
    run(parser.parse_args().mode)

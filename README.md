# RP Journal for WoW Forever

Version **0.4.3**, targeting **Forever 1.60.1 / Interface 16001**. Remember the people you meet, keep the small details, and give your characters a reason to cross paths again.

**PC gameplay testing is still pending.** This is an installable test build; offline checks cannot establish actual game rendering, protected API behavior, network delivery or SavedVariables disk writes.

## A quieter, clearer journal — 0.4.2

- **Achievements belong to the selected person.** Five rows per page keep all 12
  milestones accessible. Previous / Next, completed counts, Claim / Claimed / Locked
  states, reward tooltips and a clear three-achievement rank requirement explain what
  to do next. Empty searches and new journals show guidance.
- **Progress stays in the journal.** Startup, rank-gate and achievement-claim chatter
  is removed. Legacy first-meeting chat reminders are reset off once on upgrade;
  they remain an explicit opt-in in Settings. `/cm help` and `/cm status` answer only
  when requested. `/cm` opens the journal directly.
- **Sharing has a preview.** Post… and `/cm share` show the encounter summary and
  destination. Only Post summary sends it. Notes, memories, keepsakes and stories
  remain private. Changing groups while the preview is open cancels the send.
- **Earned milestones persist.** One-time emote achievements survive the weekly
  history cleanup. Weekly hug progress stays bounded and can be earned again.
- **Safer shortcuts.** `/cm hide` closes the journal; `/cm delete` asks before removal;
  `/cm profile` opens the selected character sheet. `/cm status` reads the loaded
  addon's version instead of a hard-coded string.

## Use it by clicking

1. **Meet someone.** Target another player for two seconds. The quiet native prompt offers **Remember them**. Write one detail, optionally leave a **Next time…** promise, and keep the memory. A title is optional.
2. **Find your history.** Select the person in your journal and click **Our story** on Overview. Its native menu leads to your unfinished and finished stories, memories, pinned pages, keepsakes, familiar places and search.
3. **Read a whole story.** Choose a story and **Read chapters**. **Older / Newer** follows only that thread. A page that finishes one promise and begins another belongs to both stories. Chapter counts show your position.
4. **Make it personal.** Under Notes, clicking a memory or story reads it; right-clicking opens page actions. **Keep a keepsake…** attaches a short description or one native item-link reference to a saved memory. The reader shows it with your words.
5. **Meet again.** After at least 30 minutes away from that person, a reunion can recall your promise and its latest chapter. **Pick up story** opens the right continuation. Write what happened, explicitly tick **Finish** if you kept the promise, and optionally leave the next one.

**Continue draft** resumes your unfinished words before opening a fresh page. **Later** keeps a draft; **Discard draft** asks for confirmation. **Edit memory / Edit story** edits the visible page. The core flow requires no slash commands.

## A history you can return to — 0.4.0

- **Connected chapters:** browse the beginning, intermediate reunions and ending of one thread without unrelated memories interrupting it. Removing a chapter leaves the other retained pages readable. If the latest and original pages are gone, the latest remaining chapter supplies the recollection.
- **One native menu:** the existing Our story control provides unfinished/finished threads, all memories, pinned pages, keepsakes and places. Long lists page through all retained entries. Hover hints explain page actions.
- **Find your own words:** search this person's memory/story titles, full notes, recorded places and keepsake labels. Queries are literal; basic Latin case is ignored, and other UTF-8 text is matched as entered. Search results lead to the exact page.
- **Private keepsakes:** a ribbon, a pressed flower, a meaningful item reference—your description, attached deliberately. An item link is a reference, never an inventory item created by the addon. One keepsake per memory; change or remove it through page actions.
- **A copy you control:** **Copy this memory…** opens an editable native preview of that single saved page, its date/place and keepsake label. Use your normal copy shortcut and decide where it goes. Editing the preview never edits the journal. No message is sent by this feature.
- **Context stays attached:** continuing an open thread follows that thread; writing from a finished story does not silently attach the new page to an unrelated open promise. Pin/keepsake/thread changes refresh the visible reader.

The original journal Lua/XML, artwork, fonts, class colors and tabs remain in place. The 0.4.2 experience module adds a paginated achievement view using the existing native rows. Existing memory/reunion controls retain their widget, font, color and geometry declarations. The new menus, keepsake/search popups and copy dialog use native Blizzard controls; no themes or appearance setup are added. The admin/settings cleanup remains in place.

## Meeting, memory, reunion

Prompts never take keyboard focus. They disappear on target changes, time out after 18 seconds, stay quiet in combat, and are spaced at least 30 seconds apart globally and 30 minutes per person. A first-meeting prompt interrupted before its dwell can wait for your next look; deliberately passing it does not nag you again. The existing targeting preference controls automatic prompts, while the journal remains available manually.

Absence is measured from leaving the target, so holding one target does not create a reunion. A reunion and its draft keep that encounter's time, place and thread even if another plan is added later. No chat transcripts are recorded and no memories are automatically authored. The player supplies the meaning.

## Your journal and public profile

Memories, keepsakes, stories, drafts and private notes stay local to your character. Public-profile sharing is separate, explicitly enabled on your character sheet, and projects only the bounded public fields. Private notes, backstory, contact details, limits, memories, stories and drafts are excluded. Both peers need a compatible RP Journal version. Shared/coauthored chapters are not included in this release.

Limits per person are **100 memories, 12 pending suggestions and 32 story threads**. Saved pages are never automatically evicted. Existing notes remain in place and are copied into a pinned Earlier notes memory once. Existing 0.3.0 chapter links work without a destructive migration. SavedVariables remain per character.

## Character sheet and settings

**Settings** has immediate-saving preferences and links to **My character** and the journal. **My character** has Identity, Appearance, Story, Personality, Skills, Relationships, Preferences and Notes sections. Switching pages or reopening retains unsaved edits during the session; **Save** persists them across reload/logout. Blank choices remain unspecified. An oversized public short bio is rejected before any sheet data is saved. Preferences cannot rewrite your authored bio.

## Install and test

Extract the ZIP and put **CharacterMemory** in your Forever client's **Interface/AddOns** directory. The manifest must be `Interface/AddOns/CharacterMemory/CharacterMemory.toc`. Back up your previous addon and per-character SavedVariables before upgrading.

See [INSTALL-FOREVER.txt](INSTALL-FOREVER.txt) for the PC checklist, error reporting and rollback. The new features particularly need real-client checks for native popup focus, menu placement, item-link editing, copying and longer story trails at your normal resolution.

Native Key Bindings include **Open your journal** and **Remember the current target** under **RP Journal**. The addon-compartment entry also opens the journal. Alt-drag moves it.

## Optional command shortcuts

| Command | Action |
| --- | --- |
| `/cm journal`, `/cmjournal` | Toggle the journal |
| `/rpbio` | Open your character sheet |
| `/cm remember <text>` | Keep a private memory for the current target |
| `/cm recall [older\|newer\|first\|latest]` | Read/browse memories |
| `/cm continue` | Continue a selected or latest open thread |
| `/cm story <title>` | Start a private thread |
| `/cm status` | Show addon/client versions |
| `/cm help` | List the remaining compatibility commands |

While the journal is open, recall/continue follow its selected person; otherwise they use the current player target. The explicit `/cm share` action previews an encounter summary and its destination before Post summary sends it; the new copy preview does not invoke it.

## Release boundary

Only client version **1.60.1 with Interface 16001** is accepted. Other versions
(including unknown builds and future patches) stop before Lua modules register
hooks, timers, network handlers or migrate journal data. The existing project
specification supplies this target; an interface number alone does not authenticate
a game distribution. Client identity and real gameplay still need confirmation.

Release archives include a SHA-256 sidecar and use deterministic timestamps and
permissions. Publish as a prerelease until the checklist in INSTALL-FOREVER.txt has
passed on the intended client. CurseForge uploads require the author's project ID,
an API token and a matching Forever game-version entry; do not label this as Retail
or Classic just to make an upload succeed.

## Development and verification

The addon needs no runtime libraries or external services.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
.venv/bin/python scripts/check.py
```

The tests load actual TOC files, Lua 5.1 and FrameXML scripts against a synthetic API boundary. Presentation fixtures compare the protected journal/dialog declarations with immutable historical ZIPs, plus byte hashes for the main journal and admin files (excluding the exact client-guard prefix). Original art and compatible TGA pixels are checked separately. Source-layout renders approximate native skins and fonts; they are not game screenshots.

## Uploading to CurseForge

Run `python scripts/check.py` with the test dependencies installed. Upload the
resulting **dist/RPJournal-Forever-0.4.3.zip**, not GitHub's source-code ZIP.
The archive must contain only `CharacterMemory/` at its root. The manifest is
`CharacterMemory/CharacterMemory.toc`; README, changelog and install instructions
are also inside `CharacterMemory/`. No loose files, wrapper directory or macOS metadata.

In CurseForge project **1324293 → Files → Add File**, select that ZIP, select only
**WoW Forever → 1.60.1**, choose **Beta**, paste the release notes, and submit.
The file is uploaded when its new file record exists. **Processing / Under Review
is not approval**; verify **Approved** before calling the CurseForge release live.
This release remains beta until the in-game checklist passes.

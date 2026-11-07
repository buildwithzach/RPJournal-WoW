# Changelog

All notable changes to the Character Memory WoW addon will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.4] - 2026-11-06

- Left-align achievement names and descriptions on the journal right page.
- Keep progress right-aligned; gameplay and saved data are unchanged.

## [0.4.3] - 2026-11-06

Packaging correction for CurseForge's rejection of loose files at the ZIP root.

- Put README.md, CHANGELOG.md and INSTALL-FOREVER.txt inside CharacterMemory/.
- Independently validate every archive member, manifest reference and install root.
- Add regression tests that reject the exact previous top-level documentation error,
  additional roots, traversal paths and hidden macOS metadata.
- Gameplay Lua/XML is unchanged from 0.4.2. This remains a beta.

## [0.4.2] - 2026-11-06

Quiet gameplay and clearer achievement flows; Forever gameplay validation remains pending.

- Replace achievement scrolling with five-row pages, Previous / Next, completion
  counts, rank guidance, empty states, visible claim states and reward tooltips.
- Fix stale achievement claims after selecting a different person and row overflow.
- Refresh achievements and relationship ranks after the current stat/emote is recorded.
- Preserve one-time emote milestones and bound weekly emote histories to ten timestamps.
- Remove startup, rank-gate and reward chat spam; show claim feedback in the journal.
  Reset legacy meeting reminders off once, preserving future explicit opt-in.
- Preview public summaries and destinations before posting; cancel if the group changes.
- Make bare /cm open the journal, implement /cm hide, confirm /cm delete, open sheets
  from /cm profile, and read the installed version for /cm status.
- Pass the target unit into equipment inspection and ignore stale inspection results.
- Reject non-finite manual XP values. Add end-to-end regression coverage for these flows.

## [0.4.1] - 2026-11-06

Release hardening prerelease; actual Forever-client validation remains pending.

- Fail closed unless the client reports version 1.60.1 and Interface 16001. All
  runtime Lua modules stop before registration or saved-data migration otherwise.
- Cancel stale queued transport callbacks on shutdown and allow clean restarts.
- Bound outbound request cooldown records to 64 peers per 30-second window.
- Require explicit boolean opt-in before replying with a public profile.
- Exclude unused source artwork from downloads while retaining original art in Git.
- Reproducible release ZIP, SHA-256 sidecar and a single release-check command.
- Add regression coverage for unsupported clients, data preservation and transport lifecycle.

## [0.4.0] - 2026-10-17

Story trails, private keepsakes and click-based discovery around the existing journal.

### Added
- Read chapters of one story, including its opening, intermediate reunions and ending, with the existing reader navigation. Pages can belong to a finished and a newly opened thread.
- Native Our story menu for unfinished/finished threads, memories, pinned pages, keepsakes, familiar places and literal full-text search. Lists page through every retained entry.
- Right-click memory/story page actions, with hover hints; left-click reading is retained.
- One deliberately chosen keepsake per memory: an authored description or a bounded native item-link reference. No inventory objects are created.
- Editable copy preview of one selected memory, date/place and keepsake label. No automatic sharing or messages; journal data is unaffected by preview edits.

### Fixed
- Story recollection now finds the latest retained chapter when the stored latest and origin pages have both been removed.
- Writing from an unthreaded memory reader no longer silently borrows an unrelated open thread.
- Pin, keepsake and thread-state actions refresh the currently visible reader.

### Preserved and validation limits
- Main journal Lua/XML and admin/settings files remain byte-identical to 0.2.4. Existing journal/memory/reunion widget, font, color and geometry declarations remain exact; new auxiliary controls use native templates.
- Private journal fields remain excluded from public profiles. No new commands, automatic authorship, chat capture or coauthored network chapters.
- Tests cover chapter isolation/order/removal/reload, click paths, search, pagination, keepsake validation, copy isolation and protected presentation. Actual Forever gameplay, native menu/popup rendering and player appeal remain unverified until PC playtesting.

## [0.3.0] - 2026-10-17

First phase of the reimagining: personal meeting/memory/reunion continuity, entirely through clicks.

### Changed
- First meeting offers Remember them and Not now. Reunion offers Pick up story, Continue draft, or Keep a memory as appropriate.
- The writer starts in the words field for new memories. Title is optional; a blank title becomes a short heading from the player's own first sentence. Empty generic memories are not saved.
- The existing Finish checkbox clearly marks completion of the displayed promise. Reader text celebrates that completed thread while retaining the next reason to meet, without repeating an auto-title as duplicate prose.
- Short prompt excerpts prioritize the promise and latest chapter, or the private unfinished draft. Full stored words remain unchanged.

### Fixed
- Reunions returning to an origin or unrelated pinned memory instead of the most recent chapter of the active promise.
- Same-second activity choosing a different newer plan after continuing an older promise.
- Manual continuation of a selected thread linking to the current encounter's unrelated memory.
- A new plan created during prompt dwell being mistaken for a promise already captured at reunion.
- Duplicate Save callbacks after a completed commit. Removed latest chapters fall back to a retained origin without self-referencing links.

### Preserved
- Main journal Lua/XML and admin/settings files are byte-identical to 0.2.4.
- Every journal/memory/reunion widget, font, color and geometry declaration matches 0.2.4, including the existing reader navigation. No new panels, controls or commands.
- Private notes/drafts and public-profile isolation retained. Actual Forever gameplay and subjective enjoyment still require PC playtesting.

## [0.2.4] - 2026-10-17

The meeting/memory/reunion flow is now driven by visible clicks.

### Changed
- Clicking a pending moment opens its writer. Clicking a kept memory or story opens its reader.
- Native Older/Newer controls and a page counter browse memories in the existing reader; stories use Previous/Next.
- Reader actions become Continue story, Continue draft, Edit memory or Edit story for the page on screen. Existing commands remain optional shortcuts.
- Reunion Our story opens the encounter's captured thread, and continuing a browsed thread follows the reader rather than a stale list selection.
- Story ordering is deterministic when two pages share a timestamp.

### Fixed
- A Lua string substitution count appearing as a stray numeric paragraph in reader text.

### Preserved
- Main journal Lua/XML, original fonts, class colors, tabs, achievement layout and page positions unchanged from 0.2.3.
- Reader stays 420x400 with its existing fonts and native skin. Only navigation controls and space above its footer are added.
- Existing private drafts, context links and admin/settings cleanup retained. Actual Forever game testing remains pending.

## [0.2.3] - 2026-10-17

Meeting/memory/reunion behavior improvements with the journal presentation unchanged.

### Added
- Deferred first-meeting prompts after an interrupted dwell, retaining the same pending moment and existing cooldown/focus/combat rules.
- `/cm recall older|newer|first|latest` for memory history in the existing reader; plain recall follows a selected memory.
- `/cm continue` picks up the selected open story, with the existing draft taking priority. Recall/continue follow the journal's selected person while open.
- Encounter snapshots in new memory drafts preserve time, place, kind and links if a pending suggestion is removed. Duplicate moment saves are rejected without losing the draft.

### Fixed
- Reunion notices and writing pages referring to different threads after a newer plan was added.
- Continuing a thread without resolving it losing the continuation link.
- Reading older memories displaying an unrelated current plan instead of their own linked thread.
- Removed/resolved draft threads redirecting to a different open promise.

### Preserved and verified
- Full main journal Lua and XML presentation retained from 0.2.2; original fonts, class colors and achievement layout unchanged.
- Existing memory/reunion widget constructors and font/geometry/color declarations compared to the immutable 0.2.2 ZIP. No controls added or rearranged.
- Admin/settings files remain identical to 0.2.2. Offline tests do not certify actual game rendering or live message/disk behavior.

## [0.2.2] - 2026-10-17

Restore the original journal appearance following explicit user feedback.

### Restored
- Complete journal XML templates and root from 0.2.0, identical to 0.1.0: fonts, original text colors, class-colored names, alignment, headings, Notes and achievements.
- Original journal Lua presentation and original memory/reunion dialogs. Removed the parchment ink overrides and cancelled the unshipped opening-page redesign.
- Original achievement rows and scrolling behavior rather than the rejected 0.2.1 arrangement.

### Retained
- 0.2.1 admin Settings and eight-section character editor, including bio isolation, field bounds, relationship editors, blank dropdowns and short-bio preflight.
- Existing memory/reunion behavior, private-profile projection and Forever compatibility work. Self/unnamed stored records remain out of the people list.

### Verification
- Exact journal markup comparison to the immutable pre-polish release, runtime file comparison with one explicit non-style filter exception, class-color regression checks and unchanged admin-file hashes.
- Offline checks do not certify actual WoW rendering.

## [0.2.1] - 2026-10-17

UI polish pass following PC feedback on 0.1.0. Actual Forever rendering still needs confirmation.

### Changed
- One compact Settings page with immediate preference saving, instead of a crowded action footer and duplicated profile editor.
- My character now has eight bounded sections, aligned rows, independent scrolling content and a fixed Save/Close area.
- Dark ink on parchment, bounded character names and dialog titles, and consistent toolbar/Overview/footer spacing.
- Native multiline journal notes, with explicit private-note guidance and Share encounter labeling.
- Six achievement rows with bounded descriptions and consistent 52px scrolling.
- Automatic viewport fitting and screen clamping for the journal and character sheet.

### Fixed
- Sheet inputs extending beyond their content area and labels overlapping notes editors.
- Duplicate close controls and missing relationship editors.
- Blank and self entries appearing in the Friendships list; stored records are retained.
- A stale Settings save overwriting a newer character-sheet bio.
- Blank dropdowns inventing an alignment/availability before a player chose one.
- Losing unsaved sheet input when switching sections or reopening during the same session.
- Overview subtitle/header collisions, zero-height summary column and row heights exceeding their containers.
- Achievement clipping and incorrect scrolling increments.
- Oversized multibyte short bios now leave all authored sheet data untouched until corrected.

### Verification
- Added geometry checks, source-layout renders and regression tests for settings/profile isolation, field alignment, footer separation, viewports and complete sheet round trips.
- Reproduced five clipped fields, overlapping notes labels, an over-wide settings footer and the stale-bio overwrite using the exact 0.1.0 ZIP under synthetic APIs.
- Native skins/fonts remain approximate in offline renders. In-game verification remains pending.

## [0.2.0] - 2026-10-17

First meeting → memory → reunion pass. Forever client testing remains pending.

### Added
- A small native encounter prompt after a two-second target dwell, with Keep a memory and Our story actions. It does not steal focus or automatically open the journal.
- A memory-writing flow with contextual prompts and an optional Next time… thread.
- Reunion prompts after 30 minutes away, recalling pinned/newest memories and the latest open thread.
- Explicit resolution of an existing thread while keeping a reunion memory, with links between memories and follow-up threads.
- A native reading page after saving, an Our story action on Overview, and `/cm recall`.
- One private draft per person, persisted while writing and resumable after closing/reloading. Explicit confirmation before discarding.
- End-to-end flow tests for encounter prompts, authoring, reunion recall/resolution, draft recovery, filters, and full-capacity failures.

### Fixed
- Holding a target for a long time no longer counts as leaving and meeting again; departure updates the last-seen timestamp.
- Self-targeting no longer creates first-meeting credit or prompts.
- Recall prioritizes pinned memories and the most recently updated unfinished thread, with deterministic ties.
- Same-second memories sort by numeric sequence instead of lexical IDs.
- Native unit tooltips show your own recollection excerpt and Next time… thread.

### Behavior
- Prompts time out after 18 seconds, cancel on target changes/combat/logout, and respect the existing automatic-target preference. Global/per-person cooldowns suppress repeated prompts.
- No automatic journal writing, chat transcripts or broadcasts. Drafts remain excluded from public profiles.
- Existing artwork and journal/page/tab geometry remain intact. All added UI uses native controls and fonts.

## [0.1.0] - 2026-10-17

WoW Forever test build; actual client validation is pending.

### Added
- Private memories with encounter suggestions, authoring, editing, pinning and removal.
- Per-person story threads with resolve/reopen actions and local tooltip recollections.
- Favorites, search, recent/open-story filters and native journal key bindings.
- Versioned RPJ2 public profiles with opt-in sharing, solicited replies, bounded chunking and throttling.
- Lua 5.1 integration tests, asset/manifest validation, release packaging and a PC test checklist.

### Fixed
- Notes typing persistence and selection/page retention when reopening the journal.
- Achievement GUID lookup and rank-gate bypass at higher XP; earned unlocks now persist.
- Character-sheet public bio consistency and Forever's anonymous multiline EditBox access.
- Cancelled-trade credit and premature completion on internal dungeon zone transitions.
- Forward-declaration scope errors, optional event registration and unit identity reads.
- Compatible TGA journal/icon copies retain the original image pixels.

### Changed
- Target Interface 16001 / Forever 1.60.1.
- Preserve original journal artwork/layout; added UI uses native Blizzard controls.
- The first-meeting option is a private reminder. Manual encounter-summary sharing remains explicit.
- Migration preserves original notes and adds one pinned legacy memory. No automatic page eviction.
- Public profile transport excludes personal notes/stories, backstory, limits and contact details;
  peers must both run this build. Legacy CM1 profile exchange is retired.

## [0.0.5a] - 2025-01-15

### Fixed
- **Critical Bug Fix**: Fixed function scope issue causing "attempt to call global 'awardToAllGroupmates' (a nil value)" error
- **Dungeon Completion Tracking**: Resolved issue where dungeon completion rewards were not being awarded to group members
- **Event Handler Scope**: Added forward declarations for functions called from event handlers to prevent nil value errors

### Technical
- **Hotfix**: Emergency fix for critical Lua scope issues
- **Code Organization**: Added forward declarations for `awardToAllGroupmates`, `incStatForAllGroupmates`, and related functions

## [0.0.5] - 2025-01-15

### Fixed
- **Critical Bug Fix**: Fixed function scope issue causing "attempt to call global 'awardToAllGroupmates' (a nil value)" error
- **Dungeon Completion Tracking**: Resolved issue where dungeon completion rewards were not being awarded to group members
- **Function Order**: Moved `awardToAllGroupmates` and `incStatForAllGroupmates` functions before `maybeCreditDungeonOnExit` to fix Lua scope issues

### Technical
- **Hotfix**: Emergency fix for WoW update compatibility issues
- **Code Organization**: Improved function ordering to prevent nil value errors

## [0.0.4] - 2024-12-19

### Added
- **Character Memory System**: Core relationship tracking functionality for players and NPCs
- **XP-Based Relationship Levels**: Automatic XP gain through interactions and activities
- **Journal Interface**: Parchment-style UI for viewing and managing relationship data
- **Achievement System**: Trackable achievements with XP rewards
- **Bio Sharing**: Cross-user bio sharing functionality via addon messages
- **Slash Commands**: Complete command system for addon interaction

### Changed
- **UI Framework**: Implemented movable UI panels with proper combat handling
- **Data Persistence**: Enhanced SavedVariables structure for per-character data storage
- **Settings Integration**: Modern settings panel with RP Bio configuration

### Technical
- **Performance Optimization**: Hoisted hot globals to locals for reduced CPU usage
- **Error Handling**: Added defensive guards for WoW API calls
- **Memory Management**: Efficient data structures for relationship tracking

## [0.0.3] - Previous Release

### Added
- **RP Character Sheet**: Added RPBio.xml/RPBio.lua scrollable character sheet with nested schema (RPJournalDB)
- **Settings Integration**: Settings button to open character sheet above settings (DIALOG strata)
- **UI Improvements**: Tightened RP Bio settings layout and aligned RP Preferences
- **Icon Support**: Added compact addon icon via TOC IconTexture

### Changed
- **Settings Layout**: Removed Relationships section from settings panel
- **UI Positioning**: Improved label positioning with labels above inputs
- **Input Sizing**: Adjusted input widths and spacings for better fit within Settings

## [0.0.2] - Previous Release

### Added
- **RP Bio Settings**: Added RP Bio settings subpage
- **Journal Request Bio**: Implemented bio request functionality in journal
- **Payload Hydration**: Added payload hydration system
- **Layout Polish**: General UI layout improvements

### Changed
- **UI Overhaul**: Complete label positioning overhaul for settings panel
- **Input Layout**: Labels positioned above inputs with proper spacing
- **Icon Integration**: Added compact addon icon support

---

## Version History Notes

- **v0.0.5a**: Current hotfix version - Critical function scope bug fix
- **v0.0.5**: Previous stable version - Hotfix for critical function scope bug
- **v0.0.4**: Previous development version - Early alpha with basic functionality
- **v0.0.3**: Previous stable release with RP Character Sheet features
- **v0.0.2**: Initial stable release with core journal functionality

## Future Plans

### Planned for v0.1.0
- Bug fixes and stability improvements
- Enhanced UI responsiveness
- Additional relationship tracking features
- Performance optimizations

### Planned for v0.2.0
- Achievement system improvements
- Enhanced bio sharing functionality
- Additional customization options
- Cross-realm compatibility improvements

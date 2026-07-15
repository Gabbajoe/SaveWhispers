# SaveWhispers (SW) — V1.1

**[Download on CurseForge](https://www.curseforge.com/wow/addons/savewhispers)**

SaveWhispers is a persistent WhatsApp-style whisper inbox for WoW Classic. Incoming and outgoing whispers, plus Guild, Party, Raid and manually added channel chat, are stored locally until you remove the conversation. The window uses the game's own Blizzard dialog art, so it looks and feels like a native part of the UI.

## Installation

Grab the latest release from [CurseForge](https://www.curseforge.com/wow/addons/savewhispers) or the [Releases page](../../releases), and extract the `SaveWhispers` folder into `World of Warcraft/_classic_era_/Interface/AddOns`.

Open it with `/sw` or the movable minimap button.

## Features

- Stores incoming and outgoing whisper histories with a timestamp on every line and "Today"/"Yesterday" day separators.
- Conversation list, scrollable chat view and message composer for DMs.
- Guild Chat history, with your guild name shown as a subtitle.
- Raid and Party Chat get their own history per session: a new conversation starts each time you join a group, with the member list captured at join time. If a party is promoted to a raid (or a raid drops to a party) mid-session, the existing conversation is relabeled in place — same history, no split — with a synthetic note marking when the switch happened.
- Manually added World/other channel-chat histories, with a member popup for group and channel conversations.
- Item and quest links in saved messages are clickable, show the real tooltip and are colored correctly — including quest references posted by the Questie addon, which aren't real hyperlinks but get recognized and converted.
- Class-colored sender names, resolved from the message's sender GUID.
- A personal watchlist (star icon) for important players, plus pinning any conversation to the top of the list.
- Conversations sort alphabetically by default, or by most recent activity if you turn that on in Settings — either way, Guild/Party/Raid/channel chat always stays above your DMs.
- Filter pills (All / DMs / Guild / Group) above the conversation list to quickly narrow it down instead of scrolling through everything mixed together.
- Settings > Danger Zone: delete all DMs, Guild Chat history, all Party/Raid sessions, or everything at once, each behind a confirmation popup.
- Settings > UI Style: WoW Classic (default), an ElvUI-inspired flat theme, Modern SaveWhispers, or a Dragonflight-inspired theme — takes effect after a UI reload.
- Select DMs mode to delete multiple conversations at once, or cancel the selection.
- "Copy name" and "Export chat" popups with pre-selected text (WoW addons can't write to the OS clipboard directly, so these give you selectable text to Ctrl+C).
- Combined suggestion dropdown + Tab-complete when typing a player or channel name.
- Unread chat counters and Online / Busy / Offline status beside the DM contact's name.
- Movable minimap icon with a hide/restore setting.
- Configurable limits: how many DM conversations, how many messages per Guild/Party/channel, and how many Party/Raid sessions to keep — the oldest non-favorited entry is replaced automatically once a limit is hit.
- Interface and chat-text scale sliders.
- Resizable, draggable window using the game's own Blizzard window art; behaves like a normal Blizzard frame (can be covered by other windows, click to bring to front).

## Changelog

### V1.1 (Co-Author: Gabbajoe)

- Native Blizzard window look (parchment/gold), pixel-perfect resizing and dragging.
- Raid Chat support, and Party/Raid history split into per-session conversations with a captured member list; switching between party and raid mid-session relabels it in place with a note instead of splitting the log.
- Clickable, tooltip-enabled, correctly colored item and quest links in saved messages - including quest references posted by Questie.
- Timestamps and Today/Yesterday day separators on every message; class-colored sender names; Guild Chat shows your guild name.
- Export chat and Copy name popups (Guild/Party/Raid/Channel chat is read-only, so those windows no longer show a message box).
- Combined suggestion-dropdown + Tab-complete for player/channel name fields.
- Configurable limits for saved DMs, group chat messages and kept Party/Raid sessions.
- Choice of sorting conversations alphabetically or by most recent activity, within Guild/Party/Raid and within DMs.
- Fixed: window always staying on top of other Blizzard windows; a crash from unbounded frame growth; duplicate empty DM conversations from adding a name without its realm.
- Fixed: pinning/unpinning Guild/Party/Raid chat could jump it below DMs in the list.
- Fixed: deleting a DM always jumped selection to Guild Chat instead of the conversation next to it.
- Fixed: a stray leading space in Party/Raid session subtitles like "( 14.07.2026 15:52)".
- Fixed: a message box left focused could keep eating keystrokes (e.g. WASD) after closing the window or switching tabs.
- Fixed: opening a busy Guild/Party/Raid chat could stutter - only the most recent messages are rendered now, and an existing conversation that was already over its message limit is trimmed back down immediately instead of over hundreds of new messages.
- Conversation list filter pills (All / DMs / Guild / Group) to untangle Guild Chat and Party/Raid sessions from the DM list.
- Settings > Danger Zone: buttons to delete all DMs, Guild Chat history, all Party/Raid sessions, or everything at once - each behind a confirmation popup.
- Settings > UI Style: choose between WoW Classic (default), an ElvUI-inspired flat theme, a Modern SaveWhispers theme, or a Dragonflight-inspired theme (applies after a UI reload).
- The close button and scrollbars are now themed too on the flat UI Styles, instead of staying the default Blizzard look.
- A book icon next to the Changelog tab's heading.
- Renamed "Select DMs" to "Select", since it now correctly deletes whatever conversation type you check off (Guild/Party/Raid/channel included, not just DMs).
- Fixed: on the flat UI Styles, buttons could double-fire per click (a toggle like "Select" would flip back to itself instantly) and rows built from them (e.g. the filter pills) didn't line up with fixed-width elements like the Player/Channel field.
- Fixed: Select mode's "Delete selected" silently skipped any checked Guild/Party/Raid/channel conversation instead of deleting it.
- Fixed: overlapping text in Settings under "Limits" (a heading/hint insertion had shifted everything below it down, but not the fields themselves).
- Fixed: "+ Add channel" floated with whatever width "Select"/"Done" happened to be, instead of staying flush with the Player/Channel field and list below it.
- Fixed: the Members popup could list yourself twice (once bare, once as "Name-Realm") - now deduped by base name, shown as "Name (Realm)" like everywhere else.

### V1.0 (Author: Femboybaddie)

- Persistent private, Guild, Party and selected channel histories.
- Chat colors, pins, member windows and a movable minimap button.
- Resizable SaveWhispers window.

## License

MIT — see [LICENSE.txt](LICENSE.txt).

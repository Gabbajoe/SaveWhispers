# SaveWhispers (SW) — V1.4

SaveWhispers is a persistent WhatsApp-style whisper inbox for WoW Classic. Incoming and outgoing whispers, plus Guild, Party, Raid and manually added channel chat, are stored locally until you remove the conversation. The window uses the game's own Blizzard dialog art, so it looks and feels like a native part of the UI.

## Installation

Copy this folder to `World of Warcraft/_classic_era_/Interface/AddOns/SaveWhispers` and enable **SaveWhispers** in the AddOns list.

Open it with `/sw` or the movable minimap button.

## Features

- Stores incoming and outgoing whisper histories with a timestamp on every line and "Today"/"Yesterday" day separators.
- Conversation list, scrollable chat view and message composer for DMs.
- Star any message to bookmark it - bookmarked messages are exempt from the per-category message cap, and a Bookmarks tab lists every one of them across every conversation with a Jump button.
- Search chat text within the open conversation, or across every saved conversation at once ("All Chats"); jumping to a result scrolls to and briefly highlights that exact message.
- Chat history loads more as you scroll up instead of stopping at a fixed recent window, for both normal browsing and search results. New messages only pull the view down to the bottom if you were already there - otherwise a small "N new messages" button appears so you can jump down when ready.
- Guild Chat history, with your guild name shown as a subtitle.
- Raid and Party Chat get their own history per session: a new conversation starts each time you join a group, with the member list captured at join time. If a party is promoted to a raid (or a raid drops to a party) mid-session, the existing conversation is relabeled in place — same history, no split — with a synthetic note marking when the switch happened.
- Manually added World/other channel-chat histories, with a member popup for group and channel conversations - it sizes itself to the group, scrolls past 20 members, and each name is individually clickable to copy just that one.
- Item and quest links in saved messages are clickable, show the real tooltip and are colored correctly — including quest references posted by the Questie addon, which aren't real hyperlinks but get recognized and converted. Shift-clicking an item or quest links it straight into the message box, same as the default chat box.
- Class-colored sender names, resolved from the message's sender GUID - right-click a name to copy it or invite them if they aren't already in your party/raid.
- Right-click a conversation (in the list or the open chat's own name) for Watchlist/Pin/Copy Name/Export Chat/Delete, scoped to whichever actions make sense for that conversation's type.
- Guild Chat and your currently active Party/Raid session can be replied to directly, not just read - older saved sessions stay read-only history.
- Recognizes DM contacts who also have SaveWhispers installed (a lightweight presence ping) and uses that for a more accurate online status, shown with a small icon once confirmed.
- A personal watchlist (star icon) for important players, plus pinning any conversation to the top of the list.
- Conversations sort alphabetically by default, or by most recent activity if you turn that on in Settings — either way, Guild/Party/Raid/channel chat always stays above your DMs.
- Filter pills (All / DMs / Guild / Group / Channels) above the conversation list to quickly narrow it down instead of scrolling through everything mixed together.
- Settings > Danger Zone: delete all DMs, Guild Chat history, all Party/Raid sessions, or everything at once, each behind a confirmation popup.
- Settings > UI Style: WoW Classic (default), an ElvUI-inspired flat theme, Modern SaveWhispers, or a Dragonflight-inspired theme — takes effect after a UI reload. The window/minimap logo and the scrollbar arrows and resize grip are drawn to match whichever style is active.
- Select mode to bulk-delete multiple conversations of any type at once, or cancel the selection.
- "Copy name" and "Export chat" popups with pre-selected text (WoW addons can't write to the OS clipboard directly, so these give you selectable text to Ctrl+C).
- Combined suggestion dropdown + Tab-complete when typing a player or channel name.
- Unread chat counters and Online / Busy / Offline status beside the DM contact's name.
- Movable minimap icon with a hide/restore setting.
- Configurable limits: how many DM conversations, how many messages per Guild/Party/channel, and how many Party/Raid sessions to keep — the oldest non-favorited entry is replaced automatically once a limit is hit.
- Interface and chat-text scale sliders.
- Resizable, draggable window using the game's own Blizzard window art; behaves like a normal Blizzard frame (can be covered by other windows, click to bring to front, closes with Escape).

## Changelog

### V1.4 (Developer: Gabbajoe)

- Right-click a conversation (in the list or the open chat's name) for Watchlist/Pin/Copy Name/Export Chat/Delete, instead of a row of buttons above every chat - shows only the actions that make sense for that conversation's type.
- Sender names in the chat log are clickable - right-click for Copy Name, and Invite when they aren't already in your party/raid.
- Shift-clicking an item or quest now links it into the SaveWhispers message box, the same as the default chat box.
- Guild Chat and your currently active Party/Raid session can be replied to directly from SaveWhispers, not just read - old saved sessions stay read-only.
- SaveWhispers now recognizes DM contacts who also have it installed and uses that to show a more accurate online status, with a small icon next to their name once confirmed.

### V1.3 (Developer: Gabbajoe)

- Bookmarks: star any message, exempt from the per-category message cap, new Bookmarks tab lists them all across every conversation with a Jump button.
- Search: per-conversation and global "All Chats" search, jump-to-result scrolls to and briefly highlights the exact message.
- Chat history loads more as you scroll up instead of hard-stopping at the last 200 messages, for both normal browsing and search results. Sticky-bottom scrolling: new messages only pull the view down if you were already at the bottom; otherwise a "N new messages" button appears.
- Members popup (Party/Raid): smaller, sizes itself to the group, scrolls past 20 members, names individually clickable to copy just that one.
- Settings tab reorganized into a compact two-column layout.
- Theme-aware logo (window title + minimap) and custom scrollbar arrows/resize grip per UI Style, instead of tinted Classic Blizzard art on the flat themes.
- Escape now closes the SaveWhispers window and its Members/Copy popups.
- Button labels made consistent (Title Case) throughout.
- Fixed: window couldn't be resized to fully fill the screen.
- Fixed: Party/Raid chat could occasionally sort out of chronological order against other conversations.
- Fixed: switching characters mid-session could keep writing into the previous character's Party/Raid log.
- Fixed: ElvUI theme's window border was a flat gray instead of its own accent color.

### V1.2 (Developer: Gabbajoe)

- Settings reorganized: "Conversations & Sessions to Keep" (DMs/Party-Raid/Channels) and "Messages to Keep per Conversation" (DMs/Guild/Party-Raid/Channels) are now separate, consistently named sections, each message limit has its own "No limit" option, sort-by-recent-activity is on by default, and changing a value shows a brief "Saved" confirmation.
- Choose which categories (DMs/Guild/Group/Channels) count toward the minimap button's unread badge.
- Messages tab: added a Channels filter pill (All/DM/Guild/Group/Chan), and the conversation counter now shows the count/limit for whichever filter is active instead of always DMs.
- Guild Chat: removed the Pin and Members buttons - Guild Chat is always a single conversation, so pinning did nothing, and Members just duplicated the default Guild Roster window.
- Party/Raid session Members popups no longer show online/offline status - it was checking the player's currently grouped units, which for an old session showed whoever they happen to be grouped with today rather than who was actually in that session.
- Fixed: chat text looked slightly blurry compared to the default chat frame at every Chat text scale setting.
- Fixed: the Interface scale and Chat text scale sliders made the window visibly jump around while dragging, and at any Interface Scale other than 100% the window would land far short of wherever it was actually dragged to.
- Fixed: a Party/Raid session could get silently split into multiple fragments mid-conversation if the client briefly misreported being in a party right after a loading screen or raid conversion, orphaning the original session.

### V1.1 (Developer: Gabbajoe)

- Native Blizzard window look (parchment/gold), pixel-perfect resizing and dragging.
- Raid Chat support, and Party/Raid history split into per-session conversations with a captured member list; switching between party and raid mid-session relabels it in place with a note instead of splitting the log.
- Clickable, tooltip-enabled, correctly colored item and quest links in saved messages - including quest references posted by Questie.
- Timestamps and Today/Yesterday day separators on every message; class-colored sender names; Guild Chat shows your guild name.
- Export chat and Copy name popups (Guild/Party/Raid/Channel chat is read-only, so those windows no longer show a message box).
- Combined suggestion-dropdown + Tab-complete for player/channel name fields.
- Configurable limits for saved DMs, group chat messages and kept Party/Raid sessions.
- Choice of sorting conversations alphabetically or by most recent activity, within Guild/Party/Raid and within DMs.
- Conversation list filter pills (All / DMs / Guild / Group) to untangle Guild Chat and Party/Raid sessions from the DM list.
- Settings > Danger Zone: delete all DMs, Guild Chat history, all Party/Raid sessions, or everything at once, each behind a confirmation popup. Select mode can now bulk-delete any conversation type, not just DMs.
- Settings > UI Style: choose between WoW Classic (default), an ElvUI-inspired flat theme, a Modern SaveWhispers theme, or a Dragonflight-inspired theme (applies after a UI reload).
- Minimap button gets a gold border ring like every other addon's minimap icon, plus a small unread-count badge.
- Fixed: window always staying on top of other Blizzard windows.
- Fixed: a crash from unbounded frame growth.
- Fixed: duplicate empty DM conversations from adding a name without its realm.
- Fixed: a message box left focused could keep eating keystrokes (e.g. WASD) after closing the window or switching tabs.
- Fixed: the Members popup could list yourself twice (once bare, once as "Name-Realm") - now deduped by base name, shown as "Name (Realm)" like everywhere else.

### V1.0 (Developer: Femboybaddie)

- Persistent private, Guild, Party and selected channel histories.
- Chat colors, pins, member windows and a movable minimap button.
- Resizable SaveWhispers window.

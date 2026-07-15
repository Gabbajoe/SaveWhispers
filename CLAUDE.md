# SaveWhispers

A WoW Classic Era addon: a persistent, WhatsApp-style chat log for private whispers, Guild, Party/Raid and manually added channel chat. Native Blizzard dialog look (parchment/gold), not a custom-themed window.

## File layout (load order matters, see the .toc)

- `Core.lua` — `SW` table setup, event frame, DB init, slash commands. All `CHAT_MSG_*` and `GROUP_*` events are wired here and routed into `Whispers.lua` storage functions.
- `Database.lua` — `SW.Database.defaults`, the one source of truth for saved-variable shape and setting defaults.
- `Whispers.lua` — all data/storage logic: conversations, group chat sessions, watchlist, sorting, eviction. No UI code.
- `UI.lua` — the entire window (by far the largest file): widget helpers at the top, then per-tab `BuildXPanel`/`RefreshXPanel` pairs (Messages, Watchlist, Settings, Changelog).
- `Minimap.lua` — minimap button only.
- Two `.toc` files (`SaveWhispers.toc`, `SaveWhispers_Vanilla.toc`) — keep versions/authors in sync in both when bumping.

## Conversation model

- `SW.DB.conversations[key]` — DM conversations, keyed by lowercased player name (see `GetPlayerBaseKey`/`FindConversationByBaseName` for the realm-suffix dedup fix).
- `SW.DB.groupChats[key]` — Guild Chat (fixed key `"guild"`) plus Party/Raid *sessions* (key `kind .. ":" .. joinTimestamp`) plus manually-added channels. All of these have `conversation.system = true` and an `order` field (guild=1, party=2, raid=3, channel=4) that keeps them grouped and always above DMs in the list — see `SW:GetSortedConversations` for the exact sort rules (system-before-DM is a hard partition, never crossed by pinning).
- A new Party/Raid session starts on `GROUP_JOINED` (or on load if already grouped) and captures the member list at that moment. Converting party↔raid mid-session (`GROUP_ROSTER_UPDATE` self-correction) relabels the *same* conversation via `SW:ConvertGroupSession` and appends a `{system=true, text=...}` synthetic marker message — it must never split into two conversations.
- Limits (`maxConversations`, `maxGroupMessages`, `maxGroupSessions`) are all in `DB.settings`, user-configurable in the Settings tab, enforced by eviction functions in `Whispers.lua`.

## Hard-won gotchas (don't re-derive these)

- **No live WoW client in this environment.** Verification is `luac -p *.lua` (syntax only) after every edit — always run it before reporting a change done. Actual in-game testing is done by the user; ask them to `/reload` and report back rather than assuming.
- **Frame pooling required.** Never `CreateFrame` per refresh in a loop — leaks frames and caused a stack-overflow crash before pooling (`poolStart`/`poolRow`/`poolFinish` in `UI.lua`) was introduced. Reuse via the pool helpers for any per-row/per-message UI.
- **Hyperlinks**: `SetItemRef(link, ...)` and `GameTooltip:SetHyperlink(link)` want the *bare* inner payload (`quest:8929:60`), not the full `|Hquest:...|h[Text]|h` wrapped form.
- **Clickable custom Buttons**: `CreateFrame("Button", nil, parent)` without a template does **not** register for any click by default — `OnEnter`/`OnLeave` fire fine, but `OnClick` silently never does unless you call `RegisterForClicks(...)` explicitly. Bit us once with quest links that had hover tooltips but weren't clickable.
- **Questie quest text isn't a real hyperlink.** Questie posts plain text it pattern-matches itself in the default chat frame: either `[[level] Name (questID)]` (from its own tracker) or `[Name (questID)]` (no level, from shift-clicking the *default* Blizzard quest log). Verified by reading the raw SavedVariables file — zero `|H` markup. `synthesizeQuestieLinks()` in `UI.lua` detects both and wraps them in a synthesized `|Hquest:id:level|h` so they flow through the normal click/tooltip/color pipeline. If a "link doesn't work" report comes in, check the raw saved text first (see below) before assuming the hyperlink pipeline is broken.
- **Frame strata**: this window uses `"MEDIUM"` + `SetToplevel(true)` — matching Blizzard's own windows (bags/spellbook/character/quest log never call `SetFrameStrata`, so they default to `MEDIUM`). Anything higher (`HIGH`/`DIALOG`) makes the window permanently cover those regardless of click order. Popups (Members, Copy) use `FULLSCREEN_DIALOG` so they always stay above the main window.
- **EditBox focus leaks.** Hiding a frame does not clear keyboard focus from an `EditBox` inside it — it keeps eating keystrokes (WASD etc.) until `ClearFocus()` is called explicitly. `SW:ClearInputFocus()` is called on tab switch and on window hide/close; extend it if a new EditBox is added anywhere.
- **WoW's clipboard silently strips `|c`/`|H` markup** from EditBox copies — there is no addon-side way around this. Don't build a "copy raw" debug feature relying on clipboard; it was tried and removed.
- **Dynamic width text**: don't hardcode a pixel `SetWidth` for word-wrapped text in a resizable window — it overflows past the border when the window is resized narrower than that constant. Compute width from the actual container (`panel.xxx:GetWidth()`) at refresh time instead (see `RefreshChangelogPanel`, `RefreshChatPanel`).
- **`splitRealm`** trims whitespace around the `-` split on purpose — group session names look like `"Party Chat - 14.07.2026 15:52"` (spaces around the dash), unlike player names (`"Name-Realm"`, no spaces). Don't revert to a strict `[^%-]+` match.
- Debugging message content: the SavedVariables file is directly readable at `WTF/Account/<ACCOUNT>/SavedVariables/SaveWhispers.lua` (only written on `/reload` or logout) — prefer reading it directly over asking the user to copy/paste chat text, which is unreliable (clipboard markup stripping, screenshots miss exact bytes).

## Conventions

- German is the working language with this user in conversation; code comments and commit-style content stay in English.
- Ask before implementing on ambiguous/large features (the user has explicitly pushed back on jumping straight to code); small, unambiguous bug fixes can be done directly.
- Keep both `.toc` files and `Core.lua`'s `SW.version` in sync when bumping version. Update `UI.lua`'s in-addon Changelog panel (`CHANGELOG` table) and `README.md`'s Changelog section together — they're meant to mirror each other.

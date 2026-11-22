local frame = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }
CreateFrame = function() return frame end
SlashCmdList = {}
time = function() return 123456 end
date = os.date
UnitName = function() return 'Tester' end
GetRealmName = function() return 'Realm' end
local SW = {}
local base = './'
for _, file in ipairs({'Core.lua', 'Database.lua', 'Whispers.lua'}) do
    assert(loadfile(base .. file))('SaveWhispers', SW)
end
frame.onEvent(frame, 'ADDON_LOADED', 'SaveWhispers')
SW.initialized = true
local function whisper(event, text)
    frame.onEvent(frame, event, text, 'Friend-Realm')
end
whisper('CHAT_MSG_WHISPER', 'incoming')
whisper('CHAT_MSG_WHISPER_INFORM', 'outgoing')
local conversation = assert(SW.DB.conversations['friend-realm'])
assert(#conversation.messages == 2)
assert(conversation.messages[1].text == 'incoming')
assert(conversation.messages[2].outgoing)
local secret = {}
issecretvalue = function(value) return rawequal(value, secret) end
whisper('CHAT_MSG_WHISPER', secret)
assert(#conversation.messages == 2)
assert(SW:Trim(secret) == '')
local sent
C_ChatInfo = {SendChatMessage = function(...) sent = {...} end}
assert(SW:SendWhisper('Friend-Realm', 'hello'))
assert(sent[1] == 'hello' and sent[2] == 'WHISPER' and sent[4] == 'Friend-Realm')
assert(SW:SendConversationMessage(SW.DB.groupChats.guild, 'guild hello'))
assert(sent[2] == 'GUILD')
C_ChatInfo = nil
SendChatMessage = function(...) sent = {...} end
assert(SW:SendWhisper('Friend-Realm', 'legacy'))
assert(sent[1] == 'legacy')
SendChatMessage = nil
assert(not SW:SendWhisper('Friend-Realm', 'unavailable'))
C_FriendList = {GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return {name='Friend-Realm', connected=true, afk=true} end}
assert(SW:GetContactStatus('Friend-Realm') == 'busy')
local saved = SaveWhispersDB
SW:InitDatabase()
assert(SaveWhispersDB == saved and #conversation.messages == 2)
print('PASS: incoming/outgoing storage, restricted payloads, modern/legacy sending, guild sending, friend status, database reload')

dofile('Minimap.lua')
SW:RegisterAddonCompartment() -- Classic clients without the menu remain supported.
local registrations, entry = 0
AddonCompartmentFrame = {RegisterAddon = function(_, value) registrations = registrations + 1; entry = value end}
SW.BrandIconPath = function() return 'icon' end
local toggles = 0
SW.ToggleMainFrame = function() toggles = toggles + 1 end
SW:RegisterAddonCompartment()
SW:RegisterAddonCompartment()
assert(registrations == 1 and entry.text == 'SaveWhispers')
SW.DB.settings.showMinimap = false
entry.func()
assert(toggles == 1)
print('PASS: optional compartment, duplicate prevention, opening with hidden minimap button')

conversation.unread = 3
local messages = conversation.messages
for _, kind in ipairs({'guild', 'party', 'raid', 'channel'}) do
    SW.DB.groupChats[kind] = {unread=4, messages={}}
end
local notifications = 0
SW.NotifyDataChanged = function() notifications = notifications + 1 end
SW.DB.settings.showMinimap = true
SW:MarkAllMessagesRead()
assert(conversation.unread == 0 and conversation.messages == messages and #messages == 2)
for _, item in pairs(SW.DB.groupChats) do assert(item.unread == 0) end
assert(SW.DB.settings.showMinimap == true and notifications == 1)
print('PASS: mark all categories read, preserve history and minimap visibility, notify UI')

local shown, badges = false, 0
SW.ui = {frame={IsShown=function() return shown end}, activeTab="Messages", selectedKey="guild", panels={Messages={}}}
SW.UpdateMinimapBadge = function() badges = badges + 1 end
local guild = SW.DB.groupChats.guild
guild.unread = 5
SW:MarkVisibleConversationRead()
assert(guild.unread == 5) -- Background refresh must preserve unread messages.
shown = true
SW.ui.activeTab = "Settings"
SW:MarkVisibleConversationRead()
assert(guild.unread == 5)
SW.ui.activeTab = "Messages"
SW.ui.panels.Messages.searchAllChats = true
SW.ui.panels.Messages.chatSearchText = "hello"
SW:MarkVisibleConversationRead()
assert(guild.unread == 5) -- Search results are not the selected chat.
SW.ui.panels.Messages.chatSearchText = ""
conversation.unread = 2
SW:MarkVisibleConversationRead()
assert(guild.unread == 0 and conversation.unread == 2 and badges == 1)
SW.ui.selectedKey = conversation.key
SW:MarkVisibleConversationRead()
assert(conversation.unread == 0 and badges == 2)
SW:MarkVisibleConversationRead()
assert(badges == 2)
print('PASS: opening selected guild/DM clears unread and badge; hidden window, other tabs and global search preserve unread')

SW.DB.groupChats.guild = nil
local guildChat = SW:EnsureGroupConversation("guild")
shown = false
guildChat.unread = 3
conversation.unread = 7
local changes = 0
SW.NotifyDataChanged = function(_, change)
    assert(change.conversation == guildChat)
    changes = changes + 1
end
SW:StoreGroupMessage("guild", "Someone-Realm", "incoming")
assert(guildChat.unread == 4)
SW:StoreGroupMessage("guild", "Tester-Realm", "my reply")
assert(guildChat.unread == 0 and conversation.unread == 7)
assert(#guildChat.messages == 2 and guildChat.messages[2].outgoing and changes == 2)
SW:StoreGroupMessage("guild", "Someone-Realm", "next unread")
assert(guildChat.unread == 1)
print('PASS: own guild echo clears unread with window closed, preserves other chats, next incoming counts again')

-- Reproduce Forever's actual short UnitName / full chat display-name mismatch
-- through the event handler, as sent by Blizzard's normal chat window.
UnitName = function() return "Gabbaliator" end
UnitGUID = function() return "Player-6855-00402769" end
shown = false
guildChat.unread = 5
local function guildEvent(name, guid)
    frame.onEvent(frame, "CHAT_MSG_GUILD", "test", name, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
end
guildEvent("Gabbaliator Gabbenstein", "Player-6855-00402769")
assert(guildChat.unread == 0 and guildChat.messages[#guildChat.messages].outgoing)
guildEvent("Gabbaliator Gabbenstein", "Player-6855-00402769")
assert(guildChat.unread == 0)
guildEvent("Gabbaliator", "Player-OTHER")
assert(guildChat.unread == 1 and not guildChat.messages[#guildChat.messages].outgoing)
guildEvent("Gabbaliator-Realm", nil)
assert(guildChat.unread == 0) -- Legacy fallback without a sender GUID.
print('PASS: normal guild chat event with full Forever name, repeated own messages, different GUID, legacy fallback')

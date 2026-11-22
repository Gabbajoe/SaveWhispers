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

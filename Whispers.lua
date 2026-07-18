local SW = _G.SaveWhispers

local MAX_MESSAGE_LENGTH = 1000

local function messageText(value)
    value = SW:Trim(value)
    if value == "" then return nil end
    return string.sub(value, 1, MAX_MESSAGE_LENGTH)
end

-- Every category (DM/Guild/Party-Raid/Channel) has its own configurable
-- per-conversation message cap, each with a "no limit" toggle - returns nil
-- for "don't trim", which appendMessage already treats as unbounded. Kept
-- as a table method (not a file-local function) so Core.lua's InitDatabase
-- can reuse the exact same logic for its immediate-trim-on-load pass.
function SW:MessageLimitFor(kind)
    local settings = self.DB.settings
    local unlimitedKey, valueKey
    if kind == "dm" then
        unlimitedKey, valueKey = "dmMessagesUnlimited", "maxDMMessages"
    elseif kind == "guild" then
        unlimitedKey, valueKey = "guildMessagesUnlimited", "maxGuildMessages"
    elseif kind == "party" or kind == "raid" then
        unlimitedKey, valueKey = "partyRaidMessagesUnlimited", "maxPartyRaidMessages"
    elseif kind == "channel" then
        unlimitedKey, valueKey = "channelMessagesUnlimited", "maxChannelMessages"
    else
        return nil
    end
    if settings[unlimitedKey] then return nil end
    return math.max(50, math.floor(tonumber(settings[valueKey]) or 1500))
end

-- A loop, not a single trim: if the cap was only just lowered (or a
-- conversation grew past it before this limit existed), a single
-- table.remove only ever peels off one message per incoming message, so it
-- can take hundreds of new messages to actually shrink back down. Skips
-- bookmarked messages rather than assuming index 1 is always safe to drop -
-- a bookmark means "never auto-delete this", mirroring how
-- SW:RemoveOldestConversation already skips favorited conversations. If
-- everything left is bookmarked the cap simply can't be honored - breaks
-- out instead of spinning forever.
function SW:TrimMessages(messages, cap)
    if not cap then return end
    while #messages > cap do
        local removeIndex = 1
        while messages[removeIndex] and messages[removeIndex].bookmarked do
            removeIndex = removeIndex + 1
        end
        if not messages[removeIndex] then break end
        table.remove(messages, removeIndex)
    end
end

local function appendMessage(conversation, message, cap)
    local messages = conversation.messages
    messages[#messages + 1] = message
    SW:TrimMessages(messages, cap)
end

function SW:GetConversation(key)
    if not self.DB then return nil end
    return (self.DB.conversations and self.DB.conversations[key]) or (self.DB.groupChats and self.DB.groupChats[key]) or nil
end

function SW:GetSortedConversations(favoritesOnly)
    local list = {}
    if not favoritesOnly then
        for _, conversation in pairs(self.DB and self.DB.groupChats or {}) do list[#list + 1] = conversation end
    end
    for key, conversation in pairs(self.DB and self.DB.conversations or {}) do
        if not favoritesOnly or conversation.favorite then
            conversation.key = conversation.key or key
            list[#list + 1] = conversation
        end
    end
    local byActivity = self.DB and self.DB.settings and self.DB.settings.sortByActivity
    table.sort(list, function(a, b)
        -- Guild/Party/Raid/Channel chat always sits above player DMs, full
        -- stop - checking "pinned" before this let pinning/unpinning one of
        -- them jump across that boundary, which looked like the list
        -- reordering at random.
        if a.system ~= b.system then return a.system and true or false end
        if a.system then
            local aOrder, bOrder = a.order or 4, b.order or 4
            if aOrder ~= bOrder then return aOrder < bOrder end
        end
        if a.pinned ~= b.pinned then return a.pinned and true or false end
        -- Both within a Guild/Party/Raid/Channel group and within the DM
        -- list, the user can choose activity (most recent first) or a
        -- stable alphabetical order instead.
        if byActivity and (a.lastActivity or 0) ~= (b.lastActivity or 0) then
            return (a.lastActivity or 0) > (b.lastActivity or 0)
        end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return list
end

function SW:RemoveOldestConversation()
    local oldestKey, oldestTime
    for key, conversation in pairs(self.DB.conversations) do
        if not conversation.favorite and (not oldestTime or conversation.lastActivity < oldestTime) then
            oldestKey, oldestTime = key, conversation.lastActivity
        end
    end
    if oldestKey then
        self.DB.conversations[oldestKey] = nil
        if self.ui and self.ui.selectedKey == oldestKey then self.ui.selectedKey = nil end
        return true
    end
    return false
end

-- Whispers arrive with a "-Realm" suffix on the player name, but a player
-- typing into the "Player / channel" or watchlist box usually leaves the
-- realm off. Without this, a manually added name silently created a second,
-- empty conversation instead of finding the real one with saved messages.
function SW:FindConversationByBaseName(key)
    local baseKey = self:GetPlayerBaseKey(key)
    if not baseKey then return nil end
    if baseKey == key then
        local found
        for existingKey, existing in pairs(self.DB.conversations) do
            if self:GetPlayerBaseKey(existingKey) == baseKey then
                if found then return nil end
                found = existing
            end
        end
        return found
    end
    return self.DB.conversations[baseKey]
end

function SW:EnsureConversation(name)
    name = self:NormalizePlayerName(name)
    local key = self:GetPlayerKey(name)
    if not key then return nil, "Enter a player name first." end
    local conversation = self.DB.conversations[key]
    if conversation then
        if conversation.name ~= name then conversation.name = name end
        return conversation
    end
    -- Found via base-name match (e.g. typed "Femboybaddie" for an existing
    -- "Femboybaddie-Soulseeker"): reuse it, but keep its realm-qualified name
    -- since that's what whispering/matching future messages relies on.
    conversation = self:FindConversationByBaseName(key)
    if conversation then return conversation end

    local maximum = math.max(1, math.floor(tonumber(self.DB.settings.maxConversations) or 200))
    local count = 0
    for _ in pairs(self.DB.conversations) do count = count + 1 end
    if count >= maximum and not self:RemoveOldestConversation() then
        return nil, "The " .. maximum .. " DM limit has been reached. Remove a conversation or watchlist player first."
    end

    conversation = { key = key, name = name, messages = {}, favorite = false, lastActivity = self:Now(), unread = 0 }
    self.DB.conversations[key] = conversation
    return conversation
end

-- Party and Raid share the same order tier on purpose: the sort compares
-- order BEFORE lastActivity (see GetSortedConversations), so giving raid
-- a higher number than party used to force every party session above every
-- raid session regardless of which was actually more recent - "sort by
-- activity" only applied within each of those two groups separately,
-- not across them, which looked like a mis-sorted list once someone had
-- both kinds of sessions going.
local GROUP_DEFAULTS = {
    guild = { name = "Guild Chat", order = 1 },
    party = { name = "Party Chat", order = 2 },
    raid = { name = "Raid Chat", order = 2 },
}

function SW:EnsureGroupConversation(key, displayName, chatType, order)
    if not self.DB then return nil end
    self.DB.groupChats = type(self.DB.groupChats) == "table" and self.DB.groupChats or {}
    local conversation = self.DB.groupChats[key]
    if conversation then return conversation end
    local defaults = GROUP_DEFAULTS[key]
    conversation = {
        key = key,
        name = displayName or (defaults and defaults.name) or "Channel Chat",
        system = true,
        order = order or (defaults and defaults.order) or 4,
        channel = chatType or key,
        messages = {},
        lastActivity = 0,
        unread = 0,
    }
    self.DB.groupChats[key] = conversation
    return conversation
end

local function addUniqueName(list, name)
    name = SW:NormalizePlayerName(name)
    if not name then return end
    for _, existing in ipairs(list) do
        if existing == name then return end
    end
    list[#list + 1] = name
end

-- Party/raid chat is split into one conversation per group session instead
-- of a single ever-growing history: a new session starts when you join a
-- group and simply stops collecting once you leave (the conversation itself
-- stays, so old sessions remain browsable). self.DB.openPartySessionKey /
-- openRaidSessionKey track which session is currently live.
function SW:StartGroupSession(kind)
    if not self.DB then return nil end
    local dbKey = kind == "raid" and "openRaidSessionKey" or "openPartySessionKey"
    local existingKey = self.DB[dbKey]
    if existingKey and self.DB.groupChats[existingKey] then
        return self.DB.groupChats[existingKey]
    end
    -- The player is only ever really in ONE group chat at a time - if the
    -- OTHER kind already has a session open, this call is almost certainly
    -- IsInRaid()/IsInParty() briefly misreporting right after a loading
    -- screen or raid conversion (GROUP_JOINED firing again while the same
    -- group session is still genuinely ongoing), not an actual new group.
    -- Reuse the existing session instead of starting a competing one -
    -- GROUP_ROSTER_UPDATE's ConvertGroupSession will relabel it if the kind
    -- genuinely changes. Starting a second session here used to orphan the
    -- first one mid-conversation the moment the new one got converted and
    -- claimed the openRaidSessionKey/openPartySessionKey slot out from
    -- under it, silently splitting one continuous raid's chat into
    -- multiple fragments that all end at the same moment.
    local otherDbKey = kind == "raid" and "openPartySessionKey" or "openRaidSessionKey"
    local otherKey = self.DB[otherDbKey]
    if otherKey and self.DB.groupChats[otherKey] then
        return self.DB.groupChats[otherKey]
    end
    local timestamp = self:Now()
    local key = kind .. ":" .. timestamp
    local label = (kind == "raid" and "Raid Chat - " or "Party Chat - ") .. date("%d.%m.%Y %H:%M", timestamp)
    local order = 2 -- party and raid share a tier; see GROUP_DEFAULTS comment
    local conversation = self:EnsureGroupConversation(key, label, kind, order)
    conversation.lastActivity = timestamp
    local members = {}
    addUniqueName(members, UnitName and UnitName("player"))
    if kind == "raid" then
        for index = 1, 40 do
            local unit = "raid" .. index
            if UnitExists and UnitExists(unit) then addUniqueName(members, UnitName(unit)) end
        end
    else
        for index = 1, 4 do
            local unit = "party" .. index
            if UnitExists and UnitExists(unit) then addUniqueName(members, UnitName(unit)) end
        end
    end
    conversation.members = members
    self.DB[dbKey] = key
    self:TrimGroupSessions()
    self:NotifyDataChanged()
    return conversation
end

function SW:EndGroupSession(kind)
    if not self.DB then return end
    local dbKey = kind == "raid" and "openRaidSessionKey" or "openPartySessionKey"
    local hadSession = self.DB[dbKey] ~= nil
    self.DB[dbKey] = nil
    -- The send row is shown only for the current Party/Raid session. Refresh
    -- immediately when leaving so an old session becomes read-only at once.
    if hadSession then self:NotifyDataChanged() end
end

-- A party converted to a raid (or back) is still the same group of people
-- continuing the same session, not a new one - relabel the conversation in
-- place (keeping its history) instead of splitting into two, and drop a
-- synthetic marker message so the switch is visible when reading back.
function SW:ConvertGroupSession(fromKind, toKind)
    if not self.DB then return end
    local fromDbKey = fromKind == "raid" and "openRaidSessionKey" or "openPartySessionKey"
    local toDbKey = toKind == "raid" and "openRaidSessionKey" or "openPartySessionKey"
    local key = self.DB[fromDbKey]
    local conversation = key and self.DB.groupChats[key]
    if not conversation then return end
    conversation.channel = toKind
    conversation.order = 2 -- party and raid share a tier; see GROUP_DEFAULTS comment
    local suffix = string.match(conversation.name, "%-%s*(.+)$") or date("%d.%m.%Y %H:%M", self:Now())
    conversation.name = (toKind == "raid" and "Raid Chat - " or "Party Chat - ") .. suffix
    appendMessage(conversation, {
        system = true,
        text = toKind == "raid" and "Group was converted to a raid." or "Raid was converted to a group.",
        timestamp = self:Now(),
    }, self:MessageLimitFor(toKind))
    conversation.lastActivity = self:Now()
    self.DB[fromDbKey] = nil
    self.DB[toDbKey] = key
    self:NotifyDataChanged()
end

-- Guild Chat stays a single permanent conversation; only party/raid session
-- conversations are capped, since those are the ones that multiply.
function SW:TrimGroupSessions()
    local cap = math.max(1, math.floor(tonumber(self.DB.settings.maxGroupSessions) or 200))
    local sessions = {}
    for _, conversation in pairs(self.DB.groupChats or {}) do
        if conversation.channel == "party" or conversation.channel == "raid" then
            sessions[#sessions + 1] = conversation
        end
    end
    if #sessions <= cap then return end
    table.sort(sessions, function(a, b) return (a.lastActivity or 0) < (b.lastActivity or 0) end)
    for i = 1, #sessions - cap do
        local conversation = sessions[i]
        if self.DB.openPartySessionKey ~= conversation.key and self.DB.openRaidSessionKey ~= conversation.key then
            self.DB.groupChats[conversation.key] = nil
        end
    end
end

-- Same pattern as TrimGroupSessions: manually-added channels had no cap on
-- how many could pile up at all.
function SW:TrimChannels()
    local cap = math.max(1, math.floor(tonumber(self.DB.settings.maxChannels) or 50))
    local channels = {}
    for _, conversation in pairs(self.DB.groupChats or {}) do
        if conversation.channel == "channel" then
            channels[#channels + 1] = conversation
        end
    end
    if #channels <= cap then return end
    table.sort(channels, function(a, b) return (a.lastActivity or 0) < (b.lastActivity or 0) end)
    for i = 1, #channels - cap do
        self.DB.groupChats[channels[i].key] = nil
    end
end

function SW:TogglePinned(key)
    local conversation = self:GetConversation(key)
    if not conversation then return false, "Conversation not found." end
    if conversation.pinned then
        conversation.pinned = false
        self:NotifyDataChanged()
        return true
    end
    local pinned = 0
    for _, item in ipairs(self:GetSortedConversations(false)) do
        if item.pinned then pinned = pinned + 1 end
    end
    if pinned >= 3 then return false, "You can pin a maximum of 3 chats." end
    conversation.pinned = true
    self:NotifyDataChanged()
    return true
end

function SW:StoreWhisper(player, text, outgoing, guid)
    if not self.DB or not self.DB.settings.enabled then return end
    text = messageText(text)
    local conversation, err = self:EnsureConversation(player)
    if not text or not conversation then
        if err then self:Print(err) end
        return
    end
    appendMessage(conversation, {
        text = text,
        timestamp = self:Now(),
        outgoing = outgoing and true or false,
        guid = guid,
    }, self:MessageLimitFor("dm"))
    conversation.lastActivity = self:Now()
    -- CHAT_MSG_WHISPER_INFORM (an outgoing whisper's delivery echo) only
    -- fires when the target is actually online and reachable, same as them
    -- whispering us - both are equally valid "seen online" signals.
    conversation.lastSeen = self:Now()
    if not outgoing and (not self.ui or not self.ui.frame:IsShown() or self.ui.activeTab ~= "Messages" or self.ui.selectedKey ~= conversation.key) then
        conversation.unread = (tonumber(conversation.unread) or 0) + 1
    end
    self:NotifyDataChanged()
end

function SW:StoreGroupMessage(channel, player, text, guid)
    if not self.DB or not self.DB.settings.enabled then return end
    text = messageText(text)
    if not text then return end
    local conversation
    if channel == "party" or channel == "raid" then
        -- Defensive fallback: normally StartGroupSession already ran from
        -- the GROUP_JOINED handler, but if a message somehow arrives with
        -- no session open (e.g. addon just loaded mid-group), open one now
        -- instead of dropping the message.
        conversation = self:StartGroupSession(channel)
    else
        conversation = self:EnsureGroupConversation(channel)
    end
    if not conversation then return end
    local ownName = UnitName and UnitName("player") or ""
    local ownKey = self:GetPlayerKey(ownName)
    local senderKey = self:GetPlayerKey(player)
    local ownBase = ownKey and (string.match(ownKey, "^([^%-]+)") or ownKey)
    local senderBase = senderKey and (string.match(senderKey, "^([^%-]+)") or senderKey)
    local outgoing = ownBase and senderBase and ownBase == senderBase
    appendMessage(conversation, {
        text = text,
        sender = self:NormalizePlayerName(player) or "Unknown",
        timestamp = self:Now(),
        outgoing = outgoing and true or false,
        guid = guid,
    -- conversation.channel (not the "channel" param) is always the
    -- canonical kind ("guild"/"party"/"raid"/"channel") - the param itself
    -- is a composite key like "channel:tradechat" for custom channels,
    -- since StoreChannelMessage delegates here with that as the lookup key.
    }, self:MessageLimitFor(conversation.channel))
    conversation.lastActivity = self:Now()
    if not outgoing and (not self.ui or not self.ui.frame:IsShown() or self.ui.activeTab ~= "Messages" or self.ui.selectedKey ~= conversation.key) then
        conversation.unread = (tonumber(conversation.unread) or 0) + 1
    end
    self:NotifyDataChanged()
end

function SW:StoreChannelMessage(channelName, player, text, guid)
    channelName = self:Trim(channelName)
    if channelName == "" then return end
    local key = "channel:" .. string.lower(channelName)
    local conversation = self.DB and self.DB.groupChats and self.DB.groupChats[key]
    if not conversation then return end
    self:StoreGroupMessage(key, player, text, guid)
end

function SW:AddChannelChat(channelName)
    channelName = self:Trim(channelName)
    if channelName == "" then return false, "Enter a channel name first." end
    local key = "channel:" .. string.lower(channelName)
    local conversation = self:EnsureGroupConversation(key, channelName, "channel")
    conversation.manual = true
    conversation.lastActivity = conversation.lastActivity or 0
    self:TrimChannels()
    self:NotifyDataChanged()
    return true, conversation
end

local function samePlayer(left, right)
    local leftKey = SW:GetPlayerKey(left)
    local rightKey = SW:GetPlayerKey(right)
    if not leftKey or not rightKey then return false end
    local leftBase = string.match(leftKey, "^([^%-]+)") or leftKey
    local rightBase = string.match(rightKey, "^([^%-]+)") or rightKey
    return leftBase == rightBase
end

local function statusForUnit(unit, player)
    if not UnitExists or not UnitExists(unit) then return nil end
    local unitName = UnitName and UnitName(unit)
    if not samePlayer(unitName, player) then return nil end
    if UnitIsConnected and not UnitIsConnected(unit) then return "offline" end
    if (UnitIsAFK and UnitIsAFK(unit)) or (UnitIsDND and UnitIsDND(unit)) then return "busy" end
    return "online"
end

function SW:GetContactStatus(player)
    for _, unit in ipairs({ "target", "focus", "player", "party1", "party2", "party3", "party4" }) do
        local status = statusForUnit(unit, player)
        if status then return status end
    end
    for index = 1, 40 do
        local status = statusForUnit("raid" .. index, player)
        if status then return status end
    end
    if GetNumFriends and GetFriendInfo then
        for index = 1, GetNumFriends() do
            local name, _, _, _, connected, status = GetFriendInfo(index)
            if samePlayer(name, player) then
                if not connected then return "offline" end
                if status == "AFK" or status == "DND" then return "busy" end
                return "online"
            end
        end
    end
    local conversation = self:GetConversation(self:GetPlayerKey(player))
    if conversation and conversation.lastSeen and self:Now() - conversation.lastSeen < 900 then
        return "online"
    end
    return "offline"
end

function SW:SendWhisper(player, text)
    player = self:NormalizePlayerName(player)
    text = messageText(text)
    if not player or not text then return false, "Select a player and enter a message." end
    if not SendChatMessage then return false, "Whispers are unavailable in this game client." end
    SendChatMessage(text, "WHISPER", nil, player)
    return true
end

-- Guild Chat is one permanent conversation and may always receive a message
-- from SaveWhispers. Party/Raid conversations are historical sessions, so
-- only the session currently open in the database is allowed to send; this
-- keeps an old log from accidentally sending into a new, unrelated group.
function SW:CanSendToConversation(conversation)
    if not conversation then return false end
    if not conversation.system then return true end
    if conversation.channel == "guild" then return true end
    if conversation.channel == "party" then
        return self.DB and self.DB.openPartySessionKey == conversation.key
            and IsInGroup and IsInGroup()
            and not (IsInRaid and IsInRaid())
    elseif conversation.channel == "raid" then
        return self.DB and self.DB.openRaidSessionKey == conversation.key
            and IsInRaid and IsInRaid()
    end
    return false
end

function SW:SendConversationMessage(conversation, text)
    if not conversation then return false, "Select a conversation first." end
    if not conversation.system then return self:SendWhisper(conversation.name, text) end

    text = messageText(text)
    if not text then return false, "Enter a message first." end
    if not SendChatMessage then return false, "Chat is unavailable in this game client." end

    local chatType
    if conversation.channel == "guild" then
        if GetGuildInfo and not GetGuildInfo("player") then
            return false, "You are not in a guild."
        end
        chatType = "GUILD"
    elseif conversation.channel == "party" and self:CanSendToConversation(conversation) then
        chatType = "PARTY"
    elseif conversation.channel == "raid" and self:CanSendToConversation(conversation) then
        chatType = "RAID"
    else
        return false, "Only the current Party/Raid session can send messages."
    end

    -- Do not add the outgoing message here: the normal CHAT_MSG_* echo is
    -- what records it, just like a message sent through Blizzard's chat box.
    SendChatMessage(text, chatType)
    return true
end

function SW:AddToWatchlist(name)
    local conversation, err = self:EnsureConversation(name)
    if not conversation then return false, err end
    conversation.favorite = true
    conversation.lastActivity = self:Now()
    self:NotifyDataChanged()
    return true
end

function SW:ToggleFavorite(key)
    local conversation = self:GetConversation(key)
    if not conversation then return end
    conversation.favorite = not conversation.favorite
    self:NotifyDataChanged()
end

-- Takes the conversation/message objects directly rather than a key+index
-- lookup - every call site already has both in hand when the user clicks
-- the bookmark icon on a specific rendered message.
function SW:ToggleMessageBookmark(conversation, message)
    if not conversation or not message then return end
    message.bookmarked = not message.bookmarked
    self:NotifyDataChanged()
end

-- Shared by the Bookmarks tab and global search - walks every conversation
-- (DMs + Guild/Party/Raid/channel sessions) and every message in each,
-- calling match(conversation, message) for each one. Collects whatever
-- match() returns into a flat list, sorted newest-first.
local function collectMatchingMessages(self, match)
    local results = {}
    for _, conversation in pairs(self.DB.conversations or {}) do
        if type(conversation) == "table" and type(conversation.messages) == "table" then
            for _, message in ipairs(conversation.messages) do
                local entry = match(conversation, message)
                if entry then results[#results + 1] = entry end
            end
        end
    end
    for _, conversation in pairs(self.DB.groupChats or {}) do
        if type(conversation) == "table" and type(conversation.messages) == "table" then
            for _, message in ipairs(conversation.messages) do
                local entry = match(conversation, message)
                if entry then results[#results + 1] = entry end
            end
        end
    end
    table.sort(results, function(a, b) return (a.message.timestamp or 0) > (b.message.timestamp or 0) end)
    return results
end

function SW:GetBookmarkedMessages()
    return collectMatchingMessages(self, function(conversation, message)
        if message.bookmarked then
            return { conversation = conversation, message = message }
        end
        return nil
    end)
end

-- Case-insensitive substring match on message text - system notes are
-- excluded, searching your own "-- Group was converted to a raid. --"
-- style markers isn't useful.
function SW:SearchAllMessages(searchText)
    searchText = string.lower(SW:Trim(searchText or ""))
    if searchText == "" then return {} end
    return collectMatchingMessages(self, function(conversation, message)
        if not message.system and message.text and string.find(string.lower(message.text), searchText, 1, true) then
            return { conversation = conversation, message = message }
        end
        return nil
    end)
end

function SW:DeleteConversation(key)
    local conversation = self:GetConversation(key)
    if not conversation then return end
    -- Land on whichever conversation was sitting directly above the
    -- deleted one in the visible list (or below, if it was the first
    -- entry), instead of always resetting to nil - which RefreshMessagesPanel
    -- then always re-picks as conversations[1], i.e. always Guild Chat.
    local neighborKey
    if self.ui and self.ui.selectedKey == key then
        local list = self:GetSortedConversations(false)
        for index, item in ipairs(list) do
            if item.key == key then
                local neighbor = list[index - 1] or list[index + 1]
                neighborKey = neighbor and neighbor.key
                break
            end
        end
    end
    if conversation.system then
        -- Guild Chat is the one permanent system conversation; custom
        -- channels and individual party/raid sessions can be removed.
        if conversation.channel ~= "channel" and conversation.channel ~= "party" and conversation.channel ~= "raid" then
            return
        end
        self.DB.groupChats[key] = nil
        if self.DB.openPartySessionKey == key then self.DB.openPartySessionKey = nil end
        if self.DB.openRaidSessionKey == key then self.DB.openRaidSessionKey = nil end
    else
        self.DB.conversations[key] = nil
    end
    if self.ui and self.ui.selectedKey == key then self.ui.selectedKey = neighborKey end
    self:NotifyDataChanged()
end

-- Bulk-delete actions for the Settings "Danger Zone" - each is meant to be
-- called only after a native confirmation popup (see StaticPopupDialogs in
-- UI.lua), since none of these can be undone.
function SW:DeleteAllDMs()
    self.DB.conversations = {}
    if self.ui then self.ui.selectedKey = nil end
    self:NotifyDataChanged()
end

function SW:DeleteGuildHistory()
    local guild = self.DB.groupChats and self.DB.groupChats.guild
    if not guild then return end
    guild.messages = {}
    guild.lastActivity = 0
    if self.ui and self.ui.selectedKey == "guild" then self.ui.selectedKey = nil end
    self:NotifyDataChanged()
end

function SW:DeleteAllGroupSessions()
    for key, conversation in pairs(self.DB.groupChats or {}) do
        if type(conversation) == "table" and (conversation.channel == "party" or conversation.channel == "raid") then
            self.DB.groupChats[key] = nil
        end
    end
    self.DB.openPartySessionKey = nil
    self.DB.openRaidSessionKey = nil
    if self.ui then self.ui.selectedKey = nil end
    self:NotifyDataChanged()
end

-- Wipes everything (DMs, Guild history, every Party/Raid session, every
-- manually added channel), then restores the one permanent conversation
-- InitDatabase always guarantees on load.
function SW:DeleteAllChats()
    self.DB.conversations = {}
    self.DB.groupChats = {}
    self.DB.openPartySessionKey = nil
    self.DB.openRaidSessionKey = nil
    if self.ui then self.ui.selectedKey = nil end
    self:EnsureGroupConversation("guild")
    self:NotifyDataChanged()
end

-- Name suggestions for the "Player / channel" and watchlist add-player
-- fields: saved DMs plus current guild/party/raid rosters, deduplicated and
-- filtered to whatever prefix the player has typed so far.
function SW:GetNameSuggestions(prefix)
    prefix = string.lower(self:Trim(prefix or ""))
    if prefix == "" then return {} end
    local seen, names = {}, {}
    local function add(name)
        name = self:NormalizePlayerName(name)
        if not name then return end
        local key = string.lower(name)
        if seen[key] then return end
        if string.sub(key, 1, #prefix) ~= prefix then return end
        seen[key] = true
        names[#names + 1] = name
    end
    for _, conversation in pairs(self.DB and self.DB.conversations or {}) do
        add(conversation.name)
    end
    if GetNumGuildMembers then
        for index = 1, GetNumGuildMembers() do
            add((GetGuildRosterInfo(index)))
        end
    end
    for _, unit in ipairs({ "party1", "party2", "party3", "party4" }) do
        if UnitExists and UnitExists(unit) then add(UnitName(unit)) end
    end
    for index = 1, 40 do
        local unit = "raid" .. index
        if UnitExists and UnitExists(unit) then add(UnitName(unit)) end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    while #names > 8 do table.remove(names) end
    return names
end

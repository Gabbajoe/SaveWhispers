local ADDON_NAME, Addon = ...

local SW = Addon or {}
_G.SaveWhispers = SW

SW.name = "SaveWhispers"
SW.shortName = "SW"
SW.version = "1.4.1"
SW.addonName = ADDON_NAME or "SaveWhispers"
SW.BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
SW.initialized = false
-- Presence ping/pong (see PingContact/OnAddonMessage in Whispers.lua) -
-- versioned in case the wire format ever needs to change without old and
-- new SaveWhispers versions misreading each other's messages.
SW.ADDON_MESSAGE_PREFIX = "SaveWhispers1"

function SW:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffef4f91SaveWhispers|r: " .. tostring(message))
    end
end

function SW:Trim(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    return string.gsub(value, "%s+$", "")
end

function SW:NormalizePlayerName(name)
    name = self:Trim(name)
    if name == "" then return nil end
    return name
end

function SW:GetPlayerKey(name)
    name = self:NormalizePlayerName(name)
    return name and string.lower(name) or nil
end

function SW:GetPlayerBaseKey(key)
    return key and (string.match(key, "^([^%-]+)") or key) or nil
end

function SW:Now()
    return time and time() or 0
end

function SW:MergeDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for key, value in pairs(defaults or {}) do
        if type(value) == "table" then
            target[key] = self:MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function SW:InitDatabase()
    _G.SaveWhispersDB = _G.SaveWhispersDB or {}
    self.DB = _G.SaveWhispersDB
    self:MergeDefaults(self.DB, self.Database.defaults)
    self.DB.conversations = type(self.DB.conversations) == "table" and self.DB.conversations or {}
    self.DB.groupChats = type(self.DB.groupChats) == "table" and self.DB.groupChats or {}
    for key, conversation in pairs(self.DB.groupChats) do
        if type(conversation) == "table" and conversation.channel == "channel" and not conversation.manual then
            self.DB.groupChats[key] = nil
        end
    end
    self.DB.settings = self:MergeDefaults(self.DB.settings, self.Database.defaults.settings)
    self.DB.minimap = self:MergeDefaults(self.DB.minimap, self.Database.defaults.minimap)

    -- One-time migration from the old shared maxGroupMessages (pre-split):
    -- carry its value into Guild/Party-Raid/Channel so nobody's existing
    -- customization silently resets to the new default. DMs previously had
    -- no limit at all - preserve that as "unlimited" for existing installs
    -- instead of suddenly trimming someone's long DM history down to 1500.
    if self.DB.settings.maxGroupMessages and not self.DB.settings.migratedGroupMessageLimit then
        local oldValue = tonumber(self.DB.settings.maxGroupMessages)
        if oldValue then
            self.DB.settings.maxGuildMessages = oldValue
            self.DB.settings.maxPartyRaidMessages = oldValue
            self.DB.settings.maxChannelMessages = oldValue
        end
        self.DB.settings.dmMessagesUnlimited = true
        self.DB.settings.migratedGroupMessageLimit = true
    end
    if self.EnsureGroupConversation then
        self:EnsureGroupConversation("guild")
    end

    -- Party/Raid Chat used to be one permanent conversation each; now every
    -- group joined gets its own session instead. Fold any old-style history
    -- into a closed session labeled with when it was last active, rather
    -- than discarding it.
    for _, kind in ipairs({ "party", "raid" }) do
        local old = self.DB.groupChats[kind]
        if type(old) == "table" then
            if type(old.messages) == "table" and #old.messages > 0 then
                local timestamp = (old.lastActivity and old.lastActivity > 0) and old.lastActivity or self:Now()
                local newKey = kind .. ":" .. timestamp
                old.key = newKey
                old.name = (kind == "raid" and "Raid Chat - " or "Party Chat - ") .. date("%d.%m.%Y %H:%M", timestamp)
                self.DB.groupChats[newKey] = old
            end
            self.DB.groupChats[kind] = nil
        end
    end

    -- Old development versions used numeric tables. Keep their saved variables harmless.
    for key, conversation in pairs(self.DB.conversations) do
        if type(conversation) ~= "table" then
            self.DB.conversations[key] = nil
        else
            conversation.messages = type(conversation.messages) == "table" and conversation.messages or {}
            conversation.favorite = conversation.favorite and true or false
            conversation.lastActivity = tonumber(conversation.lastActivity) or 0
            if not conversation.lastSeen and conversation.lastIncoming then
                conversation.lastSeen = conversation.lastIncoming
            end
        end
    end

    -- Heal duplicate empty conversations created (before this was fixed) by
    -- manually adding a name without its "-Realm" suffix: fold them into the
    -- real, realm-qualified conversation instead of leaving a dead entry.
    for key, conversation in pairs(self.DB.conversations) do
        if self:GetPlayerBaseKey(key) == key and #conversation.messages == 0 then
            local real = self:FindConversationByBaseName(key)
            if real and real ~= conversation then
                real.favorite = real.favorite or conversation.favorite
                real.pinned = real.pinned or conversation.pinned
                self.DB.conversations[key] = nil
            end
        end
    end

    -- A conversation that grew past its current per-category limit (e.g.
    -- from before the limit existed, or after lowering it in Settings)
    -- would otherwise only shrink by one message per new incoming message -
    -- taking potentially hundreds of messages to actually catch up, all the
    -- while making every window refresh render far more than it needs to.
    -- SW:MessageLimitFor is defined in Whispers.lua, already loaded by the
    -- time this actually runs (PLAYER_LOGIN, not file-load order).
    for _, conversation in pairs(self.DB.groupChats) do
        if type(conversation) == "table" and type(conversation.messages) == "table" then
            self:TrimMessages(conversation.messages, self:MessageLimitFor(conversation.channel))
        end
    end
    local dmCap = self:MessageLimitFor("dm")
    for _, conversation in pairs(self.DB.conversations) do
        if type(conversation) == "table" and type(conversation.messages) == "table" then
            self:TrimMessages(conversation.messages, dmCap)
        end
    end
end

function SW:SetSetting(key, value)
    if not self.DB or not self.DB.settings then return end
    self.DB.settings[key] = value
    if key == "showMinimap" and self.UpdateMinimapButton then self:UpdateMinimapButton() end
    if self.RefreshUI then self:RefreshUI() end
end

function SW:NotifyDataChanged()
    if self.RefreshUI then self:RefreshUI() end
    if self.UpdateMinimapBadge then self:UpdateMinimapBadge() end
end

function SW:ToggleMainFrame(show)
    if not self.ui or not self.ui.frame then return end
    if show == nil then show = not self.ui.frame:IsShown() end
    if show then
        self.ui.frame:Show()
        self:RefreshUI()
    else
        if self.ClearInputFocus then self:ClearInputFocus() end
        self.ui.frame:Hide()
    end
end

function SW:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:InitDatabase()
    -- SavedVariables here are account-wide (shared by every character on
    -- the account), but an "open" Party/Raid session is inherently
    -- per-character - logging out mid-session on one character and then
    -- logging into a different one left openPartySessionKey/
    -- openRaidSessionKey still pointing at the first character's session,
    -- silently grafting the second character's unrelated group chat onto
    -- the end of it. Clear them whenever the logged-in character doesn't
    -- match whoever had them open last.
    local currentCharacter = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    if self.DB.lastActiveCharacter ~= currentCharacter then
        self.DB.openPartySessionKey = nil
        self.DB.openRaidSessionKey = nil
        self.DB.lastActiveCharacter = currentCharacter
    end
    local ok, err = pcall(function() self:CreateUI() end)
    if not ok then
        self:Print("|cffff4444The window failed to load:|r " .. tostring(err))
    end
    self:CreateMinimapButton()
    self:InstallSlashCommands()
    -- Lets other SaveWhispers installs answer a presence ping (see
    -- PingContact/OnAddonMessage in Whispers.lua) - unregistered prefixes
    -- are silently dropped on receipt, so this has to happen before any
    -- CHAT_MSG_ADDON we care about could arrive.
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(SW.ADDON_MESSAGE_PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(SW.ADDON_MESSAGE_PREFIX)
    end
    -- If already grouped when the addon loads (e.g. /reload mid-dungeon),
    -- GROUP_JOINED won't fire again, so start the session here instead.
    if self.DB.settings.enabled and IsInGroup and IsInGroup() then
        self:StartGroupSession(IsInRaid and IsInRaid() and "raid" or "party")
    end
    self:Print("Ready. Use |cffffff00/sw|r to open your whisper inbox.")
end

function SW:InstallSlashCommands()
    SLASH_SAVEWHISPERS1 = "/savewhispers"
    SLASH_SAVEWHISPERS2 = "/sw"
    SlashCmdList.SAVEWHISPERS = function(message)
        message = SW:Trim(message):lower()
        if message == "" or message == "open" then
            SW:ToggleMainFrame(true)
        elseif message == "close" then
            SW:ToggleMainFrame(false)
        elseif message == "hide" then
            SW:SetSetting("showMinimap", false)
        elseif message == "reset" then
            SW.DB.window = nil
            SW:Print("Window position reset.")
        else
            SW:Print("Commands: /sw, /sw open, /sw close, /sw hide")
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("CHAT_MSG_PARTY")
eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("GROUP_JOINED")
eventFrame:RegisterEvent("GROUP_LEFT")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == SW.addonName then SW:InitDatabase() end
    elseif event == "PLAYER_LOGIN" then
        SW:Initialize()
    elseif SW.initialized and SW.DB.settings.enabled and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM") then
        local text, player = ...
        local guid = select(12, ...)
        if event == "CHAT_MSG_WHISPER" then
            SW:StoreWhisper(player, text, false, guid)
        elseif event == "CHAT_MSG_WHISPER_INFORM" then
            SW:StoreWhisper(player, text, true, guid)
        end
    elseif SW.initialized and SW.DB.settings.enabled and (event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER") then
        local text, player = ...
        local guid = select(12, ...)
        local channel = "party"
        if event == "CHAT_MSG_GUILD" then channel = "guild"
        elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then channel = "raid" end
        SW:StoreGroupMessage(channel, player, text, guid)
    elseif SW.initialized and SW.DB.settings.enabled and event == "CHAT_MSG_CHANNEL" then
        local text, player, _, channelName = ...
        local guid = select(12, ...)
        SW:StoreChannelMessage(channelName, player, text, guid)
    elseif SW.initialized and SW.DB.settings.enabled and event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        SW:OnAddonMessage(prefix, message, channel, sender)
    elseif SW.initialized and SW.DB.settings.enabled and event == "GROUP_JOINED" then
        SW:StartGroupSession(IsInRaid and IsInRaid() and "raid" or "party")
    elseif SW.initialized and SW.DB.settings.enabled and event == "GROUP_LEFT" then
        SW:EndGroupSession("party")
        SW:EndGroupSession("raid")
    elseif SW.initialized and SW.DB.settings.enabled and event == "GROUP_ROSTER_UPDATE" then
        -- Self-correcting fallback for a party promoted to a raid (or vice
        -- versa) without a clean GROUP_LEFT/GROUP_JOINED pair: relabel
        -- whichever session doesn't match the current group type in place
        -- (same conversation, same history) rather than splitting it.
        if IsInGroup and IsInGroup() then
            local kind = IsInRaid and IsInRaid() and "raid" or "party"
            local otherKind = kind == "party" and "raid" or "party"
            local otherDbKey = otherKind == "raid" and "openRaidSessionKey" or "openPartySessionKey"
            if SW.DB[otherDbKey] then
                SW:ConvertGroupSession(otherKind, kind)
            else
                SW:StartGroupSession(kind)
            end
        end
    end
end)

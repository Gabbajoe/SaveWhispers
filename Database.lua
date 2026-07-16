local SW = _G.SaveWhispers

SW.Database = {
    defaults = {
        settings = {
            enabled = true,
            showMinimap = true,
            -- Conversations/sessions to keep, per category.
            maxConversations = 200,
            maxGroupSessions = 200,
            maxChannels = 50,
            -- Messages to keep per conversation, per category. maxGroupMessages
            -- is the pre-split legacy field - InitDatabase migrates it into
            -- these once, then leaves it in place unused.
            maxDMMessages = 1500,
            dmMessagesUnlimited = false,
            maxGuildMessages = 1500,
            guildMessagesUnlimited = false,
            maxPartyRaidMessages = 1500,
            partyRaidMessagesUnlimited = false,
            maxChannelMessages = 1500,
            channelMessagesUnlimited = false,
            sortByActivity = true,
            -- Which categories count toward the minimap unread badge.
            badgeCountsDM = true,
            badgeCountsGuild = true,
            badgeCountsGroup = true,
            badgeCountsChannel = true,
            uiTheme = "classic",
            uiScale = 1,
            chatScale = 1,
        },
        conversations = {},
        groupChats = {},
        minimap = { minimapPos = 220, hide = false },
        window = {},
    },
}

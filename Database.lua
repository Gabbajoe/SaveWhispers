local SW = _G.SaveWhispers

SW.Database = {
    defaults = {
        settings = {
            enabled = true,
            showMinimap = true,
            maxConversations = 200,
            maxGroupMessages = 1500,
            maxGroupSessions = 200,
            sortByActivity = false,
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

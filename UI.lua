local SW = _G.SaveWhispers
local BACKDROP = SW.BackdropTemplate

-- The logo follows the selected UI Style: a painted parchment envelope
-- with wax seal for classic, a flat envelope in the theme's own palette
-- for each flat theme. Shared with Minimap.lua as a method so both the
-- window title and the minimap button pick the same variant.
local BRAND_ICON_VARIANTS = { classic = true, elvui = true, modern = true, dragonflight = true }
function SW:BrandIconPath(kind)
    local theme = self.DB and self.DB.settings and self.DB.settings.uiTheme
    local variant = BRAND_ICON_VARIANTS[theme] and theme or "classic"
    return "Interface\\AddOns\\SaveWhispers\\assets\\savewhispers_" .. (kind or "icon") .. "_" .. variant
end

-- How many of a conversation's most recent messages actually get rendered
-- as widgets per refresh. Stored history can be far larger (up to
-- maxGroupMessages, e.g. 1500 for a busy Guild Chat) - rendering all of it
-- every time is what caused the window-open stutter. Full history is still
-- available in full via "Export Chat".
local MAX_RENDERED_MESSAGES = 200

-- Chat text scale used to call SetTextHeight(px), which scales the glyphs
-- of whatever size the font was already rendered at rather than asking the
-- font engine to re-rasterize at that size - it looked visibly blurrier
-- than the real chat frame, which resizes its font via SetFont. Resolving
-- the chat font's path/flags once and using SetFont everywhere instead
-- fixes that.
local CHAT_FONT_PATH, _, CHAT_FONT_FLAGS = GameFontHighlightSmall:GetFont()

-- The classic parchment/gold "dialog box" look used by StaticPopup and most
-- native Blizzard windows. Using the real art (instead of a hand-rolled
-- flat-color backdrop) is what makes the addon look like part of the game.
local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- Four selectable looks (Settings > UI Style). "classic" keeps every
-- Blizzard template as-is (DIALOG_BACKDROP, UIPanelButtonTemplate,
-- InsetFrameTemplate, InputBoxTemplate - unchanged from before this
-- existed). "elvui"/"modern"/"dragonflight" are custom flat themes
-- inspired by those aesthetics, built from plain WHITE8X8 backdrops rather
-- than real integration with the actual ElvUI addon's skin API (that only
-- works if ElvUI itself is installed) or real Dragonflight art (which
-- isn't guaranteed to exist in the Classic Era client's data files) - both
-- are a much larger, separate undertaking than a same-layout re-skin.
-- A theme change only takes effect after /reload, since Blizzard templates
-- are chosen once at CreateFrame time and can't be swapped on an
-- already-built widget - see the "Reload UI" button in Settings.
local THEMES = {
    classic = {
        useNativeWidgets = true,
        textColor = { 0.92, 0.92, 0.92 },
        mutedColor = { 0.62, 0.62, 0.62 },
        accentColor = { 1, 0.82, 0, 0.35 },
    },
    elvui = {
        useNativeWidgets = false,
        windowBackdropColor = { 0.045, 0.045, 0.045, 0.98 },
        -- ElvUI's own orange accent (same hue as accentColor below), not a
        -- flat gray - Modern and Dragonflight both border the window in
        -- their own theme color, gray here read as an unstyled leftover
        -- edge rather than a deliberate border.
        windowBorderColor = { 0.85, 0.55, 0.1, 1 },
        insetBackdropColor = { 0.07, 0.07, 0.07, 0.9 },
        insetBorderColor = { 0.16, 0.16, 0.16, 1 },
        buttonColor = { 0.09, 0.09, 0.09, 1 },
        buttonBorderColor = { 0.2, 0.2, 0.2, 1 },
        editBackdropColor = { 0.05, 0.05, 0.05, 1 },
        editBorderColor = { 0.2, 0.2, 0.2, 1 },
        accentColor = { 0.85, 0.55, 0.1, 0.45 },
        textColor = { 0.9, 0.9, 0.9 },
        mutedColor = { 0.55, 0.55, 0.55 },
    },
    modern = {
        useNativeWidgets = false,
        -- Reuses the addon's own existing pink brand accent (#ef4f91,
        -- already used in the title bar/minimap tooltip) instead of an
        -- unrelated new color.
        windowBackdropColor = { 0.07, 0.08, 0.10, 0.98 },
        windowBorderColor = { 0.933, 0.31, 0.569, 1 },
        insetBackdropColor = { 0.10, 0.11, 0.14, 0.9 },
        insetBorderColor = { 0.933, 0.31, 0.569, 0.6 },
        buttonColor = { 0.12, 0.13, 0.16, 1 },
        buttonBorderColor = { 0.933, 0.31, 0.569, 0.5 },
        editBackdropColor = { 0.10, 0.11, 0.14, 1 },
        editBorderColor = { 0.933, 0.31, 0.569, 0.5 },
        accentColor = { 0.933, 0.31, 0.569, 0.45 },
        textColor = { 0.92, 0.92, 0.94 },
        mutedColor = { 0.58, 0.58, 0.62 },
    },
    dragonflight = {
        useNativeWidgets = false,
        -- Deep teal-blue with warm gold trim, evoking Dragonflight's
        -- expedition/dracthyr palette instead of Classic's parchment.
        windowBackdropColor = { 0.055, 0.095, 0.125, 0.98 },
        windowBorderColor = { 0.78, 0.62, 0.32, 1 },
        insetBackdropColor = { 0.08, 0.12, 0.16, 0.9 },
        insetBorderColor = { 0.78, 0.62, 0.32, 0.55 },
        buttonColor = { 0.09, 0.14, 0.18, 1 },
        buttonBorderColor = { 0.78, 0.62, 0.32, 0.55 },
        editBackdropColor = { 0.08, 0.12, 0.16, 1 },
        editBorderColor = { 0.78, 0.62, 0.32, 0.55 },
        accentColor = { 0.78, 0.62, 0.32, 0.45 },
        textColor = { 0.93, 0.93, 0.90 },
        mutedColor = { 0.60, 0.62, 0.58 },
    },
}

local function currentTheme()
    return THEMES[SW.DB and SW.DB.settings and SW.DB.settings.uiTheme] or THEMES.classic
end

-- Shared by the main window and the popup frames (Copy/Members), which all
-- used to hardcode DIALOG_BACKDROP directly.
local function applyWindowBackdrop(frame, theme)
    theme = theme or currentTheme()
    if theme.useNativeWidgets then
        frame:SetBackdrop(DIALOG_BACKDROP)
    else
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        frame:SetBackdropColor(unpack(theme.windowBackdropColor))
        frame:SetBackdropBorderColor(unpack(theme.windowBorderColor))
    end
end

-- "classic" keeps Blizzard's own red round "X" (UIPanelCloseButton); the
-- flat themes get a small themed square button instead, so the close
-- button doesn't stick out as the one unstyled native element.
local function closeButton(parent, name)
    local theme = currentTheme()
    if theme.useNativeWidgets then
        return CreateFrame("Button", name, parent, "UIPanelCloseButton")
    end
    local control = CreateFrame("Button", name, parent, BACKDROP)
    control:SetSize(24, 24)
    control:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    control:SetBackdropColor(unpack(theme.buttonColor))
    control:SetBackdropBorderColor(unpack(theme.buttonBorderColor))
    control:RegisterForClicks("LeftButtonUp")
    local label = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("x")
    label:SetTextColor(unpack(theme.textColor))
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(theme.accentColor[1], theme.accentColor[2], theme.accentColor[3], theme.accentColor[4] or 0.35)
    highlight:SetBlendMode("ADD")
    control:SetHighlightTexture(highlight)
    return control
end

local function text(parent, value, fontObject, r, g, b)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetText(value or "")
    if r then label:SetTextColor(r, g or r, b or r) end
    return label
end

-- Gives a template-less Button the same SetText/GetFontString/LockHighlight
-- contract a templated one has, so every other call site (fitButton,
-- active-pill LockHighlight, etc.) works unchanged regardless of theme.
local function skinFlatButton(control, theme)
    control:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    control:SetBackdropColor(unpack(theme.buttonColor))
    control:SetBackdropBorderColor(unpack(theme.buttonBorderColor))
    -- Registering both up and down would fire the click handler twice per
    -- physical click - harmless for idempotent handlers, but a toggle
    -- (e.g. "Select") would flip twice and visibly snap right back.
    control:RegisterForClicks("LeftButtonUp")
    -- Same font object UIPanelButtonTemplate itself uses for its label
    -- (GameFontNormal, not GameFontHighlightSmall) - using a different,
    -- narrower font here made fitButton() measure these buttons narrower
    -- than their classic-theme counterparts, throwing off every
    -- right-anchored row (flowRight) that mixes them with fixed-width
    -- elements like the "Player/Channel" field above.
    local fontString = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint("CENTER")
    fontString:SetTextColor(unpack(theme.textColor))
    control:SetFontString(fontString)
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(theme.accentColor[1], theme.accentColor[2], theme.accentColor[3], theme.accentColor[4] or 0.35)
    highlight:SetBlendMode("ADD")
    control:SetHighlightTexture(highlight)
    control.SW_disabledColor = { 0.45, 0.45, 0.45 }
    control.SW_enabledColor = theme.textColor
    control:HookScript("OnDisable", function(self) fontString:SetTextColor(unpack(self.SW_disabledColor)) end)
    control:HookScript("OnEnable", function(self) fontString:SetTextColor(unpack(self.SW_enabledColor)) end)
end

-- CheckButton is a native widget type: SetCheckedTexture/SetHighlightTexture
-- are built into it regardless of template, so no OnClick/SetChecked
-- hooking is needed - the widget itself shows/hides the checked texture.
local function checkButton(parent)
    local theme = currentTheme()
    if theme.useNativeWidgets then
        return CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    end
    local control = CreateFrame("CheckButton", nil, parent, BACKDROP)
    control:SetSize(24, 24)
    -- Same gotcha as plain Buttons: a template-less widget doesn't
    -- register for any click by default, so OnClick silently never fired -
    -- clicking any checkbox on the flat themes (e.g. "Show minimap
    -- button") did nothing at all.
    control:RegisterForClicks("LeftButtonUp")
    control:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    control:SetBackdropColor(unpack(theme.buttonColor))
    control:SetBackdropBorderColor(unpack(theme.buttonBorderColor))
    local checked = control:CreateTexture(nil, "OVERLAY")
    checked:SetPoint("TOPLEFT", 3, -3)
    checked:SetPoint("BOTTOMRIGHT", -3, 3)
    checked:SetColorTexture(theme.accentColor[1], theme.accentColor[2], theme.accentColor[3], 1)
    control:SetCheckedTexture(checked)
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(theme.accentColor[1], theme.accentColor[2], theme.accentColor[3], theme.accentColor[4] or 0.35)
    highlight:SetBlendMode("ADD")
    control:SetHighlightTexture(highlight)
    return control
end

-- Standard Blizzard button/edit box/inset templates for the "classic" theme;
-- "elvui"/"modern" build the same widget without a template instead, using
-- flat WHITE8X8 backdrops colored per-theme (see THEMES/skinFlatButton).
local function button(parent, label, width, height)
    local theme = currentTheme()
    local control = CreateFrame("Button", nil, parent, theme.useNativeWidgets and "UIPanelButtonTemplate" or BACKDROP)
    control:SetSize(width, height)
    if not theme.useNativeWidgets then skinFlatButton(control, theme) end
    control:SetText(label or "")
    return control
end

-- Shrinks a button to fit its own label instead of an arbitrary fixed width,
-- so it doesn't sit inside a wide box with empty padding on both sides.
local function fitButton(control, extra)
    local fontString = control:GetFontString()
    control:SetWidth((fontString and fontString:GetStringWidth() or 40) + (extra or 24))
    return control
end

-- A square button showing just an icon (pin/star), with the active state
-- shown via the button's own highlight lock instead of swapping text labels.
local function iconButton(parent, texture, tooltipText)
    local theme = currentTheme()
    local control = CreateFrame("Button", nil, parent, theme.useNativeWidgets and "UIPanelButtonTemplate" or BACKDROP)
    control:SetSize(28, 24)
    if not theme.useNativeWidgets then skinFlatButton(control, theme) end
    control.icon = control:CreateTexture(nil, "ARTWORK")
    control.icon:SetSize(14, 14)
    control.icon:SetPoint("CENTER", 0, 1)
    control.icon:SetTexture(texture)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltipText)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return control
end

-- Optional getSuggestions(text) -> {name, ...} attaches a filtered dropdown
-- (click to pick) plus Tab-complete (accepts the top match), like the
-- default chat edit box's player-name completion.
local function edit(parent, width, height, hint, getSuggestions)
    local theme = currentTheme()
    local field = CreateFrame("EditBox", nil, parent, theme.useNativeWidgets and "InputBoxTemplate" or BACKDROP)
    if not theme.useNativeWidgets then
        field:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        field:SetBackdropColor(unpack(theme.editBackdropColor))
        field:SetBackdropBorderColor(unpack(theme.editBorderColor))
        field:SetTextInsets(5, 5, 2, 2)
        field:SetTextColor(unpack(theme.textColor))
    end
    field:SetSize(width, height)
    field:SetFontObject("ChatFontNormal")
    field:SetAutoFocus(false)
    field.hint = hint
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    field:SetScript("OnEditFocusGained", function(self) if self:GetText() == self.hint then self:SetText("") end end)
    field:SetScript("OnEditFocusLost", function(self)
        if SW:Trim(self:GetText()) == "" then self:SetText(self.hint or "") end
        if self.dropdown then
            local dropdown = self.dropdown
            C_Timer.After(0.15, function() dropdown:Hide() end)
        end
    end)
    field:SetText(hint or "")

    if getSuggestions then
        -- A plain flat box, not the big window's decorative parchment
        -- border: that border art is sized for a ~600px window and looks
        -- broken (text spilling past it) squeezed into a small dropdown.
        local dropdownWidth = math.max(width, 190)
        local dropdown = CreateFrame("Frame", nil, field, BACKDROP)
        dropdown:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -2)
        dropdown:SetWidth(dropdownWidth)
        dropdown:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        dropdown:SetBackdropColor(0, 0, 0, 0.95)
        dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        dropdown:SetFrameStrata("TOOLTIP")
        dropdown:Hide()
        dropdown.rows = {}
        field.dropdown = dropdown
        field.suggestions = {}
        local ROW_H = 18

        local function pick(name)
            field:SetText(name)
            field:SetCursorPosition(#name)
            dropdown:Hide()
        end

        local function refresh()
            local value = field:GetText()
            local suggestions = (value ~= "" and value ~= field.hint) and getSuggestions(value) or {}
            field.suggestions = suggestions
            for _, row in ipairs(dropdown.rows) do row:Hide() end
            if #suggestions == 0 then dropdown:Hide(); return end
            for i, name in ipairs(suggestions) do
                local row = dropdown.rows[i]
                if not row then
                    row = CreateFrame("Button", nil, dropdown)
                    -- Same theme-aware hover treatment as the conversation
                    -- list rows - gold gradient only on the classic theme.
                    local rowTheme = currentTheme()
                    if rowTheme.useNativeWidgets then
                        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                    else
                        local a = rowTheme.accentColor
                        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
                        local hover = row:GetHighlightTexture()
                        if hover then hover:SetVertexColor(a[1], a[2], a[3], 0.14) end
                    end
                    row.label = text(row, "", "GameFontHighlightSmall")
                    row.label:SetPoint("LEFT", 6, 0)
                    row.label:SetWidth(dropdownWidth - 12)
                    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
                    dropdown.rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
                row:SetHeight(ROW_H)
                row.label:SetText(name)
                row:SetScript("OnClick", function() pick(name) end)
                row:Show()
            end
            dropdown:SetHeight(#suggestions * ROW_H + 4)
            dropdown:Show()
        end

        field:SetScript("OnTextChanged", function(self, userInput) if userInput then refresh() end end)
        field:SetScript("OnTabPressed", function(self)
            if self.suggestions[1] then pick(self.suggestions[1]) end
        end)
    end

    return field
end

local INSET_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- InsetFrameTemplate gives the authentic recessed content-box look used
-- inside most Blizzard windows. Fall back to a manual backdrop if that
-- template name isn't present on this client, so a naming mismatch can
-- never break the whole window from loading.
local function numberField(parent, width, height)
    local theme = currentTheme()
    local field = CreateFrame("EditBox", nil, parent, theme.useNativeWidgets and "InputBoxTemplate" or BACKDROP)
    if not theme.useNativeWidgets then
        field:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        field:SetBackdropColor(unpack(theme.editBackdropColor))
        field:SetBackdropBorderColor(unpack(theme.editBorderColor))
        field:SetTextInsets(5, 5, 2, 2)
        field:SetTextColor(unpack(theme.textColor))
    end
    field:SetSize(width, height)
    field:SetFontObject("ChatFontNormal")
    field:SetAutoFocus(false)
    field:SetNumeric(true)
    field:SetJustifyH("RIGHT")
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return field
end

-- "classic" uses InsetFrameTemplate for the authentic recessed
-- content-box look; "elvui"/"modern" (and, defensively, a client where the
-- template name doesn't exist) use a themed flat backdrop instead.
local function inset(parent)
    local theme = currentTheme()
    local frame
    if theme.useNativeWidgets then
        local ok, templated = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
        if ok and templated then frame = templated end
    end
    if not frame then
        frame = CreateFrame("Frame", nil, parent, BACKDROP)
        frame:SetBackdrop(INSET_BACKDROP)
        if theme.useNativeWidgets then
            frame:SetBackdropColor(0, 0, 0, 0.4)
            frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        else
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            frame:SetBackdropColor(unpack(theme.insetBackdropColor))
            frame:SetBackdropBorderColor(unpack(theme.insetBorderColor))
        end
    end
    return frame
end

local function fieldValue(field)
    local value = field:GetText()
    return value == field.hint and "" or value
end

-- Player names arrive as "Name-Realm". Showing that inline reads badly, so
-- callers split it and render the realm as a small subtitle instead.
local function splitRealm(name)
    name = name or ""
    -- Player names have no spaces around the "-" ("Name-Realm"), but a
    -- session name does ("Party Chat - 14.07.2026 15:52") - trimming
    -- whitespace on both sides of the split avoids a stray leading space
    -- ending up inside the "(...)" subtitle for those.
    local base, realm = string.match(name, "^(.-)%s*%-%s*(.+)$")
    if base and base ~= "" then return base, realm end
    return name, nil
end

-- Fallback name color for when the sender's class isn't resolvable yet
-- (e.g. the very first message from a brand new player).
local function chatColor(outgoing)
    if outgoing then return 1, 1, 1 end
    return 1, 0.30, 0.62
end

-- Resolves a message's sender to their class color (e.g. from the GUID
-- captured off the chat event), falling back to nil - the caller then keeps
-- the plain chat color - when the class can't be determined (very first
-- sighting of a player the client hasn't cached info for yet).
local function classColorHex(guid)
    if not guid or not GetPlayerInfoByGUID then return nil end
    local _, englishClass = GetPlayerInfoByGUID(guid)
    local color = englishClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass]
    if not color then return nil end
    return string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

-- The raw chat text really does just contain the literal "{rt1}"/"{star}"
-- etc - the real ChatFrame widget substitutes the raid-icon texture for
-- display only, it isn't part of the transmitted message. Replicate that
-- here since our lines aren't real ChatFrame message lines.
local RAID_ICON_NAMES = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local RAID_ICON_INDEX_BY_NAME = {}
for index, name in ipairs(RAID_ICON_NAMES) do RAID_ICON_INDEX_BY_NAME[name] = index end

local function replaceIconExpressions(value)
    value = string.gsub(value, "%{rt(%d)%}", function(digit)
        local index = tonumber(digit)
        return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
    end)
    value = string.gsub(value, "%{(%a+)%}", function(word)
        local index = RAID_ICON_INDEX_BY_NAME[string.lower(word)]
        if not index then return "{" .. word .. "}" end
        return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
    end)
    return value
end

-- Quest links carry no color of their own in the raw message text - the
-- green/yellow/orange/red difficulty color depends on the *viewer's* own
-- level relative to the quest, which can't be baked into a message shared
-- with everyone. The real chat frame computes it locally on display; do the
-- same here via GetQuestDifficultyColor, or the link just renders as plain
-- text like the rest of the message.
local function questDifficultyColor(level)
    if not GetQuestDifficultyColor then return 1, 1, 0.2 end
    local a, b, c = GetQuestDifficultyColor(level)
    if type(a) == "table" then return a.r, a.g, a.b end
    return a or 1, b or 1, c or 0.2
end

-- Questie posts its own quest references as plain text (confirmed via the
-- raw saved message - no |H markup at all) and makes them clickable in the
-- default chat by hooking that frame directly and pattern-matching its own
-- formats, not through a real hyperlink. It uses two different formats:
-- its own tracker/log gives "[[level] Name (id)]", while shift-clicking a
-- quest from the default Blizzard quest log gets reformatted by the same
-- hook down to "[Name (id)]" with no level. We can't hook Questie's
-- internals, but since the quest ID is right there in the text either way,
-- we can build our own real "quest:id:level" link from it and run it
-- through the same click/tooltip/color handling as a native one.
local function synthesizeQuestieLinks(value)
    value = string.gsub(value, "(%[%[(%d+)%] .- %(%d+%)%])", function(whole, level)
        local questID = string.match(whole, "%((%d+)%)%]$")
        if not questID then return whole end
        return "|Hquest:" .. questID .. ":" .. level .. "|h" .. whole .. "|h"
    end)
    -- No level is present in this shorter form, so approximate the
    -- difficulty color using the reader's own level.
    value = string.gsub(value, "(%[[^%[%]]-%(%d+%)%])", function(whole)
        local questID = string.match(whole, "%((%d+)%)%]$")
        if not questID then return whole end
        local level = (UnitLevel and UnitLevel("player")) or 1
        return "|Hquest:" .. questID .. ":" .. level .. "|h" .. whole .. "|h"
    end)
    return value
end

local function colorizeQuestLinks(value)
    -- Classic quest links carry more colon-separated fields than just
    -- "quest:id:level" (e.g. "quest:8929:60:1:1:1:1:0"), so match everything
    -- up to the next "|h" rather than assuming exactly two numbers - that
    -- stricter pattern silently matched nothing at all.
    return string.gsub(value, "(|Hquest:([^|]+)|h%[.-%]|h)", function(linkPart, params)
        local level = string.match(params, "^%d+:(%d+)")
        local r, g, b = questDifficultyColor(tonumber(level) or 0)
        return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, linkPart)
    end)
end

-- Collapses item/spell/etc links down to their bracketed display name and
-- drops color codes, for plain-text export/copy where WoW's markup would
-- otherwise show up as unreadable escape sequences.
local function plainText(value)
    value = value or ""
    value = string.gsub(value, "|H.-|h(.-)|h", "%1")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    return value
end

-- Rounding a frame's saved/restored screen position and size to whole
-- pixels (via PixelUtil when available) avoids the blurry text you get once
-- a window has been freely dragged/resized to a fractional-pixel position.
local function setPixelPoint(frame, point, relativeTo, relativePoint, x, y)
    x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(frame, point, relativeTo, relativePoint, x, y)
    else
        frame:SetPoint(point, relativeTo, relativePoint, x, y)
    end
end

local function setPixelSize(frame, width, height)
    width, height = math.floor(width + 0.5), math.floor(height + 0.5)
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(frame, width, height)
    else
        frame:SetSize(width, height)
    end
end

-- After a drag, GetPoint() reports whichever corner ended up closest to a
-- screen edge - not necessarily TOPLEFT. The resize grip always calls
-- StartSizing("BOTTOMRIGHT"), which assumes a TOPLEFT-anchored frame; if the
-- frame's actual anchor had become e.g. BOTTOMRIGHT (dragged near that edge
-- of the screen), the anchor and the resize corner conflict and the frame's
-- size computation goes haywire (reported: window jumps to full screen size
-- and behaves erratically on resize). Re-anchoring to a known TOPLEFT point
-- after every move keeps StartSizing's assumption valid.
-- The `* scale / parentScale` conversion this used to have is only correct
-- when REPARENTING to a frame with a different scale ancestry than before -
-- it's the standard idiom for that, but this frame is already a direct
-- child of UIParent both before and after this call (only the anchor POINT
-- changes, not the parent), so frame:GetLeft()/GetTop() are already exactly
-- the offsets UIParent's BOTTOMLEFT needs, with no conversion. Since
-- scale/parentScale reduces to frame:GetScale() (the frame's own uiScale
-- setting) here, the old formula silently multiplied the offset by uiScale
-- - invisible at the default uiScale=1 (factor of 1, a no-op), but at any
-- other Interface Scale it shrank the offset toward UIParent's corner,
-- making the window land far short of wherever it was actually dropped.
local function normalizeTopLeft(frame)
    local x = frame:GetLeft()
    local y = frame:GetTop()
    frame:ClearAllPoints()
    setPixelPoint(frame, "TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    return x, y
end

-- Reusable frame pool: refresh loops reuse existing rows instead of creating
-- new ones every call, which previously leaked frames on every chat event
-- (list rebuild ran on every incoming whisper/guild/party message) and
-- eventually overflowed Lua's stack when GetChildren() had to return them all.
local function poolStart(content)
    content.pool = content.pool or { items = {}, count = 0 }
    content.pool.count = 0
end

local function poolRow(content, factory)
    local pool = content.pool
    pool.count = pool.count + 1
    local row = pool.items[pool.count]
    if not row then
        row = factory(content)
        pool.items[pool.count] = row
    end
    row:Show()
    return row
end

local function poolFinish(content)
    local pool = content.pool
    if not pool then return end
    for i = pool.count + 1, #pool.items do
        pool.items[i]:Hide()
    end
end

-- Each scroll frame needs a real (unique, if only for internal lookup)
-- name so its template-created "$parentScrollBar" children resolve to
-- discoverable globals - otherwise there's no way to reach the scrollbar
-- at all to theme it.
local scrollFrameCounter = 0

local function scroll(parent)
    scrollFrameCounter = scrollFrameCounter + 1
    local name = "SaveWhispersScroll" .. scrollFrameCounter
    local frame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, frame)
    content:SetSize(1, 1)
    frame:SetScrollChild(content)
    frame.content = content
    local theme = currentTheme()
    if not theme.useNativeWidgets then
        local scrollBar = _G[name .. "ScrollBar"]
        if scrollBar then
            local thumb = scrollBar:GetThumbTexture()
            if thumb then
                thumb:SetColorTexture(theme.buttonBorderColor[1], theme.buttonBorderColor[2], theme.buttonBorderColor[3], 1)
                thumb:SetWidth(10)
            end
            -- The up/down arrow buttons are unmistakably Classic art -
            -- recoloring them still read as "old icons, tinted" against
            -- the flat themes. Strip the template's four state textures
            -- entirely (they size/anchor inconsistently between the up and
            -- down buttons - resizing them still rendered the two arrows
            -- at different sizes) and draw one owned glyph per button
            -- instead, with the state handling (hover/disabled tint) done
            -- by hand via hooks.
            local arrowTexture = "Interface\\AddOns\\SaveWhispers\\assets\\savewhispers_arrow"
            local c = theme.buttonBorderColor
            for _, buttonName in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
                local scrollButton = _G[name .. "ScrollBar" .. buttonName]
                if scrollButton then
                    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
                        local tex = scrollButton[getter] and scrollButton[getter](scrollButton)
                        if tex then
                            tex:SetTexture(nil)
                        end
                    end
                    local glyph = scrollButton:CreateTexture(nil, "OVERLAY")
                    glyph:SetTexture(arrowTexture)
                    glyph:SetSize(13, 13)
                    glyph:SetPoint("CENTER")
                    if buttonName == "ScrollDownButton" then glyph:SetTexCoord(0, 1, 1, 0) end
                    local function applyState()
                        if not scrollButton:IsEnabled() then
                            glyph:SetVertexColor(c[1], c[2], c[3], 0.25)
                        elseif scrollButton.swHover then
                            glyph:SetVertexColor(math.min(1, c[1] * 1.4), math.min(1, c[2] * 1.4), math.min(1, c[3] * 1.4), 1)
                        else
                            glyph:SetVertexColor(c[1], c[2], c[3], 0.9)
                        end
                    end
                    scrollButton:HookScript("OnEnter", function(self) self.swHover = true; applyState() end)
                    scrollButton:HookScript("OnLeave", function(self) self.swHover = nil; applyState() end)
                    scrollButton:HookScript("OnDisable", applyState)
                    scrollButton:HookScript("OnEnable", applyState)
                    applyState()
                end
            end
        end
    end
    return frame
end

function SW:CreateUI()
    if self.ui and self.ui.frame then return end
    -- Snapshot of the theme this window was actually built with - a theme
    -- change in Settings only takes effect after /reload (see THEMES below),
    -- so Settings compares against this to know whether to show "Reload UI".
    local appliedTheme = self.DB.settings.uiTheme or "classic"
    self.ui = { panels = {}, activeTab = "Messages", selectedKey = nil, listFilter = "all", appliedTheme = appliedTheme }
    local frame = CreateFrame("Frame", "SaveWhispersFrame", UIParent, BACKDROP)
    setPixelSize(frame, 900, 620)
    -- "MEDIUM" is the strata Blizzard's own windows use by default
    -- (bags, spellbook, character, quest log never call SetFrameStrata,
    -- so they stay on CreateFrame's default of "MEDIUM"). Anything above
    -- that ("HIGH", "DIALOG", ...) would always render on top of them
    -- regardless of click order. SetToplevel gives normal click-to-raise
    -- behavior within that shared strata instead.
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    -- Resize bounds are in the frame's OWN coordinate space, but the frame
    -- is scaled by the Interface scale setting (SetScale in RefreshUI) - a
    -- fixed "parentHeight - 40" bound left a scale-dependent dead margin
    -- the window could never grow into (reported as "can't maximize, a
    -- strip of screen always stays uncovered"). Dividing by the current
    -- scale converts screen space to frame space, and recomputing on every
    -- scale change (RefreshUI calls this) keeps it correct after the
    -- Interface scale slider moves.
    local function updateResizeBounds()
        local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
        if not parentWidth or parentWidth < 700 then parentWidth = 1200 end
        if not parentHeight or parentHeight < 500 then parentHeight = 900 end
        local scale = frame:GetScale() or 1
        if scale <= 0 then scale = 1 end
        frame.maxResizeWidth = math.max(700, parentWidth / scale)
        frame.maxResizeHeight = math.max(480, parentHeight / scale)
        if frame.SetResizeBounds then
            frame:SetResizeBounds(700, 480, frame.maxResizeWidth, frame.maxResizeHeight)
        elseif frame.SetMinResize then
            frame:SetMinResize(700, 480)
        end
    end
    frame.UpdateResizeBounds = updateResizeBounds
    updateResizeBounds()
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    local saved = self.DB.window or {}
    if saved.width and saved.height then
        setPixelSize(frame, math.min(frame.maxResizeWidth, math.max(700, saved.width)), math.min(frame.maxResizeHeight, math.max(480, saved.height)))
    end
    -- Applied after the saved size is restored, not before - the backdrop's
    -- tiled background didn't reliably refresh on its own for a size change
    -- this large (see the resize-grip OnMouseUp handler below for the same
    -- fix), so applying it at whatever the frame's default pre-resize size
    -- happened to be could leave the bottom of a large restored window
    -- with no background at all until something else forced a redraw.
    applyWindowBackdrop(frame)
    -- Always normalized to a TOPLEFT anchor (see normalizeTopLeft) - old
    -- saved positions from before this fix get normalized on load too.
    if saved.point then
        setPixelPoint(frame, saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        setPixelPoint(frame, "CENTER", UIParent, "CENTER", 0, 30)
    end
    normalizeTopLeft(frame)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = normalizeTopLeft(self)
        local window = SW.DB.window or {}
        window.point, window.relativePoint = "TOPLEFT", "BOTTOMLEFT"
        window.x, window.y = math.floor(x + 0.5), math.floor(y + 0.5)
        SW.DB.window = window
    end)
    frame:Hide()
    self.ui.frame = frame
    -- Lets Escape close this window like every other Blizzard/addon frame -
    -- without being listed here, Escape falls through to WoW's own "open
    -- the game menu" default instead of closing the topmost UI panel.
    tinsert(UISpecialFrames, "SaveWhispersFrame")

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(18, 18)
    resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    local resizeTheme = currentTheme()
    if resizeTheme.useNativeWidgets then
        resize.texture = resize:CreateTexture(nil, "ARTWORK")
        resize.texture:SetAllPoints()
        resize.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resize:SetScript("OnEnter", function(self) self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down") end)
        resize:SetScript("OnLeave", function(self) self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)
    else
        -- The Classic size-grabber art read as "old icon, tinted" on the
        -- flat themes - use the addon's own grip glyph instead (three
        -- diagonal lines, white-on-transparent, tinted to the theme).
        -- A pre-drawn texture, NOT SetRotation on a solid-color bar:
        -- SetRotation only rotates texture coordinates within the same
        -- axis-aligned quad, which is invisible on a solid color - the
        -- first attempt at this rendered as a plain horizontal streak.
        local c = resizeTheme.buttonBorderColor
        resize.texture = resize:CreateTexture(nil, "ARTWORK")
        resize.texture:SetAllPoints()
        resize.texture:SetTexture("Interface\\AddOns\\SaveWhispers\\assets\\savewhispers_grip")
        resize.texture:SetVertexColor(c[1], c[2], c[3], 0.9)
        resize:SetScript("OnEnter", function(self)
            self.texture:SetVertexColor(math.min(1, c[1] * 1.4), math.min(1, c[2] * 1.4), math.min(1, c[3] * 1.4), 1)
        end)
        resize:SetScript("OnLeave", function(self)
            self.texture:SetVertexColor(c[1], c[2], c[3], 0.9)
        end)
    end
    -- NOT calling frame.UpdateResizeBounds() here (a previous fix attempt
    -- did) - SetResizeBounds turns out to immediately re-clamp the frame's
    -- CURRENT size into the [min,max] range as a side effect of being
    -- called, and calling it fresh on every single click was snapping the
    -- window down to the minimum (700x480) right away, confirmed via a
    -- debug print showing the frame already at exactly 700x480 before
    -- StartSizing even ran. Bounds are still kept fresh via CreateUI and
    -- every RefreshUI (uiScale changes, UIParent resizing) - just not
    -- re-applied on every mouse click.
    resize:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local newWidth = math.min(frame:GetWidth(), frame.maxResizeWidth or math.huge)
        local newHeight = math.min(frame:GetHeight(), frame.maxResizeHeight or math.huge)
        setPixelSize(frame, newWidth, newHeight)
        -- BackdropTemplateMixin is supposed to redraw its tiled background
        -- automatically on every size change, but that didn't reliably keep
        -- up with a large native drag-resize in practice - the tiled center
        -- fill stopped covering the frame partway down while the border
        -- itself kept stretching fine, leaving a "void" showing the game
        -- world through the bottom of the window. Explicitly reapplying the
        -- backdrop after the resize settles forces a full redraw at the
        -- frame's actual current size.
        applyWindowBackdrop(frame)
        local x, y = normalizeTopLeft(frame)
        local window = SW.DB.window or {}
        window.width, window.height = math.floor(newWidth + 0.5), math.floor(newHeight + 0.5)
        window.point, window.relativePoint = "TOPLEFT", "BOTTOMLEFT"
        window.x, window.y = math.floor(x + 0.5), math.floor(y + 0.5)
        SW.DB.window = window
        SW:RefreshUI()
    end)

    local close = closeButton(frame, "SaveWhispersFrameCloseButton")
    close:SetPoint("TOPRIGHT", -6, -7)
    close:SetScript("OnClick", function() SW:ToggleMainFrame(false) end)
    -- Belt-and-suspenders: whatever hides this frame, an EditBox inside it
    -- (message box, name field, ...) must not keep keyboard focus while
    -- invisible, or it silently keeps eating every keystroke.
    frame:SetScript("OnHide", function() SW:ClearInputFocus() end)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 18, -14)
    icon:SetSize(36, 36)
    icon:SetTexture(SW:BrandIconPath("icon"))
    local title = text(frame, "SaveWhispers", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -4)
    local subtitle = text(frame, "Your saved private messages", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)

    -- Right-aligned, text-width tabs sitting level with the title instead of
    -- their own oversized row: uses the empty space next to "SaveWhispers"
    -- instead of wasting a whole extra row of padded, fixed-width buttons.
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -22)
    tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -46, -22)
    tabBar:SetHeight(20)
    self.ui.tabs = {}
    local tabNames = { "Messages", "Watchlist", "Bookmarks", "Settings", "Changelog" }
    local previous
    for i = #tabNames, 1, -1 do
        local tabName = tabNames[i]
        local tab = button(tabBar, tabName, 10, 20)
        local fontString = tab:GetFontString()
        tab:SetWidth((fontString and fontString:GetStringWidth() or 40) + 20)
        if previous then tab:SetPoint("RIGHT", previous, "LEFT", -4, 0) else tab:SetPoint("RIGHT", tabBar, "RIGHT", 0, 0) end
        tab:SetScript("OnClick", function() SW:SwitchTab(tabName) end)
        self.ui.tabs[tabName] = tab
        previous = tab
    end

    -- 12px, not the old 18px sides/62px top - roughly halves the dead
    -- margin around the tab content. 12 is the floor for the classic
    -- theme: the parchment dialog border art's insets are 11-12px, any
    -- tighter and the content boxes slide under the border.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -54)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    self.ui.content = content
    self:BuildMessagesPanel()
    self:BuildWatchlistPanel()
    self:BuildBookmarksPanel()
    self:BuildSettingsPanel()
    self:BuildChangelogPanel()
    self:SwitchTab("Messages")
end

function SW:NewPanel(name)
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints()
    panel:Hide()
    self.ui.panels[name] = panel
    return panel
end

-- Hiding a panel (switching tabs, closing the window) doesn't clear
-- keyboard focus from an EditBox inside it - the now-invisible box quietly
-- keeps eating every keystroke (WASD etc. type into it instead of moving)
-- until something explicitly calls ClearFocus.
function SW:ClearInputFocus()
    local messages = self.ui and self.ui.panels and self.ui.panels.Messages
    if messages then
        if messages.message then messages.message:ClearFocus() end
        if messages.target then messages.target:ClearFocus() end
        if messages.chatSearch then messages.chatSearch:ClearFocus() end
    end
    local watchlist = self.ui and self.ui.panels and self.ui.panels.Watchlist
    if watchlist and watchlist.addName then watchlist.addName:ClearFocus() end
end

function SW:SwitchTab(name)
    if not self.ui then return end
    self:ClearInputFocus()
    self.ui.activeTab = name
    for key, panel in pairs(self.ui.panels) do
        if key == name then panel:Show() else panel:Hide() end
    end
    for key, tab in pairs(self.ui.tabs) do
        if key == name then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    self:RefreshUI()
end

function SW:BuildMessagesPanel()
    local panel = self:NewPanel("Messages")
    panel.left = inset(panel)
    panel.left:SetPoint("TOPLEFT", 0, 0)
    panel.left:SetPoint("BOTTOMLEFT", 0, 0)
    panel.left:SetWidth(242)
    -- One compact heading line ("Conversations  73/200") instead of two,
    -- freeing a whole row so "+ Add channel" can share a row with
    -- "Select" rather than sitting on its own line below.
    panel.counter = text(panel.left, "Conversations", "GameFontDisableSmall")
    panel.counter:SetPoint("TOPLEFT", 14, -12)
    panel.select = fitButton(button(panel.left, "Select", 10, 22))
    -- -30, not -12: flush with the list's right edge below, which is inset
    -- further to leave room for its scrollbar.
    panel.select:SetPoint("TOPRIGHT", -30, -34)
    panel.select:SetScript("OnClick", function()
        SW.ui.selectMode = not SW.ui.selectMode
        SW.ui.selectedDMs = {}
        SW:RefreshUI()
    end)
    -- Anchored to the fixed left edge (matching the Player/Channel field
    -- and list below), not chained off "Select"'s left side - otherwise
    -- the whole row's left extent drifted with "Select"/"Done"'s width,
    -- landing it out of line with everything else in the column.
    panel.addChannel = fitButton(button(panel.left, "Add Channel", 10, 22))
    panel.addChannel:SetPoint("TOPLEFT", 12, -34)
    -- "Open" is pinned to the same -30 right edge as "Select"/the list
    -- below, instead of floating off the input field's width - otherwise
    -- its edge drifts depending on how wide the button's own label renders,
    -- landing it out of line with everything else in the column.
    panel.add = fitButton(button(panel.left, "Open", 10, 22))
    panel.add:SetPoint("TOPRIGHT", -30, -62)
    panel.target = edit(panel.left, 140, 22, "Player/Channel", function(value) return SW:GetNameSuggestions(value) end)
    panel.target:SetPoint("TOPLEFT", 12, -62)
    panel.target:SetPoint("RIGHT", panel.add, "LEFT", -6, 0)
    -- "Select" and "Open" auto-fit to different label widths, which put
    -- the right edge of "Add Channel" (stretched to Select) and of the
    -- Player/Channel field (stretched to Open) on different X positions -
    -- the two rows visibly out of line with each other. One shared width
    -- (the wider of the two) keeps both rows' columns flush.
    local rightColumnWidth = math.max(panel.select:GetWidth(), panel.add:GetWidth())
    panel.select:SetWidth(rightColumnWidth)
    panel.add:SetWidth(rightColumnWidth)
    panel.addChannel:SetPoint("RIGHT", panel.select, "LEFT", -6, 0)
    panel.add:SetScript("OnClick", function()
        local conversation, err = SW:EnsureConversation(fieldValue(panel.target))
        if conversation then SW.ui.selectedKey = conversation.key; conversation.unread = 0; SW.ui.selectMode = false; SW.ui.listFilter = "all"; SW:RefreshUI() else SW:Print(err) end
    end)
    panel.addChannel:SetScript("OnClick", function()
        local ok, result = SW:AddChannelChat(fieldValue(panel.target))
        if ok then
            SW.ui.selectedKey = result.key
            panel.target:SetText(panel.target.hint)
            SW:RefreshUI()
        else
            SW:Print(result)
        end
    end)
    -- Guild Chat and every individual Party/Raid session all lived in one
    -- long mixed-together list with DMs, making it hard to find anything -
    -- these filter pills narrow the same list down instead of duplicating
    -- it into a separate tab.
    local function filterPill(filterKey, label)
        local pill = fitButton(button(panel.left, label, 10, 20), 12)
        pill:SetScript("OnClick", function()
            SW.ui.listFilter = filterKey
            SW:RefreshUI()
        end)
        return pill
    end
    panel.filterAll = filterPill("all", "All")
    panel.filterDM = filterPill("dm", "DM")
    panel.filterGuild = filterPill("guild", "Guild")
    panel.filterGroup = filterPill("group", "Group")
    panel.filterChannel = filterPill("channel", "Chan")
    -- Spread across the full width (x=12 to -30, matching every other
    -- flush row in this column) with the leftover space divided evenly
    -- between the pills, instead of a fixed small gap chained from the
    -- right - that left the row's total width (and so its left edge)
    -- wherever the pills' own text happened to add up to.
    do
        local pills = { panel.filterAll, panel.filterDM, panel.filterGuild, panel.filterGroup, panel.filterChannel }
        local totalWidth = 0
        for _, pill in ipairs(pills) do totalWidth = totalWidth + pill:GetWidth() end
        local available = 242 - 12 - 30
        local gap = (available - totalWidth) / (#pills - 1)
        local x = 12
        for _, pill in ipairs(pills) do
            pill:ClearAllPoints()
            pill:SetPoint("TOPLEFT", panel.left, "TOPLEFT", x, -88)
            x = x + pill:GetWidth() + gap
        end
    end
    panel.list = scroll(panel.left)
    panel.list:SetPoint("TOPLEFT", 12, -114)
    panel.list:SetPoint("BOTTOMRIGHT", -30, 48)
    panel.deleteSelected = button(panel.left, "Delete Selected", 122, 22)
    panel.deleteSelected:SetPoint("BOTTOMLEFT", 12, 12)
    panel.deleteSelected:SetScript("OnClick", function()
        -- Select mode lets you check off any conversation, not just DMs -
        -- deleting used to only ever touch DB.conversations directly, so a
        -- checked Guild/Party/Raid/channel entry silently stayed put while
        -- still counting as "removed". SW:DeleteConversation already knows
        -- how to handle every conversation type correctly (and that Guild
        -- Chat itself can't be removed), so reuse it instead.
        local keys = {}
        for key in pairs(SW.ui.selectedDMs or {}) do keys[#keys + 1] = key end
        if #keys == 0 then SW:Print("Select at least one chat first."); return end
        for _, key in ipairs(keys) do SW:DeleteConversation(key) end
        SW.ui.selectedDMs = {}; SW.ui.selectMode = false
        SW:NotifyDataChanged()
    end)
    panel.cancelSelected = button(panel.left, "Cancel", 64, 22)
    panel.cancelSelected:SetPoint("LEFT", panel.deleteSelected, "RIGHT", 6, 0)
    panel.cancelSelected:SetScript("OnClick", function() SW.ui.selectedDMs = {}; SW.ui.selectMode = false; SW:RefreshUI() end)

    panel.right = inset(panel)
    panel.right:SetPoint("TOPLEFT", panel.left, "TOPRIGHT", 6, 0)
    panel.right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.contactFavoriteIcon = panel.right:CreateTexture(nil, "ARTWORK")
    panel.contactFavoriteIcon:SetSize(16, 16)
    panel.contactFavoriteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    panel.contactFavoriteIcon:Hide()
    panel.contact = text(panel.right, "Select a conversation", "GameFontNormalLarge")
    panel.contact:SetPoint("TOPLEFT", 16, -12)
    -- Right-click the contact name for Watchlist/Pin/Copy Name/Export/
    -- Delete instead of a row of buttons above the chat (see
    -- ShowContextMenu/ContextMenuItemsFor) - repositioned to cover
    -- panel.contact's current bounds every refresh, since its width
    -- changes with the name.
    panel.contactMenu = CreateFrame("Button", nil, panel.right)
    panel.contactMenu:RegisterForClicks("RightButtonUp")
    panel.contactMenu:SetScript("OnClick", function()
        local conversation = SW:GetConversation(SW.ui.selectedKey)
        if conversation then SW:ShowContextMenu(SW:ContextMenuItemsFor(conversation), panel.contactMenu) end
    end)
    panel.contactRealm = text(panel.right, "", "GameFontDisableSmall")
    panel.contactRealm:SetPoint("TOPLEFT", panel.contact, "BOTTOMLEFT", 1, -3)
    panel.statusDot = panel.right:CreateTexture(nil, "OVERLAY")
    panel.statusDot:SetSize(14, 14)
    panel.statusDot:SetPoint("LEFT", panel.contact, "RIGHT", 6, 3)
    panel.statusText = text(panel.right, "(Offline)", "GameFontDisableSmall")
    panel.statusText:SetPoint("LEFT", panel.statusDot, "RIGHT", 4, 0)
    -- Set once a PING/PONG exchange (see PingContact/OnAddonMessage in
    -- Whispers.lua) confirms this contact also has SaveWhispers loaded -
    -- separate from the online/busy/offline dot, which only reflects
    -- whether they're currently reachable, not which addons they run.
    panel.hasAddonIcon = panel.right:CreateTexture(nil, "OVERLAY")
    panel.hasAddonIcon:SetSize(14, 14)
    panel.hasAddonIcon:SetPoint("LEFT", panel.statusText, "RIGHT", 4, 0)
    panel.hasAddonIcon:SetTexture(SW:BrandIconPath("icon"))
    panel.hasAddonIcon:Hide()
    local hasAddonHit = CreateFrame("Frame", nil, panel.right)
    hasAddonHit:SetAllPoints(panel.hasAddonIcon)
    hasAddonHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("This player also has SaveWhispers")
        GameTooltip:Show()
    end)
    hasAddonHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.members = fitButton(button(panel.right, "Members", 10, 24))
    panel.members:SetPoint("TOPRIGHT", panel.right, "TOPRIGHT", -12, -10)
    panel.members:SetScript("OnClick", function()
        local conversation = SW:GetConversation(SW.ui.selectedKey)
        if conversation then SW:ShowMembers(conversation) end
    end)
    -- One row below Members (whether or not Members is actually shown for
    -- this conversation type) instead of stacking behind two rows of
    -- buttons that no longer exist.
    panel.chatSearch = edit(panel.right, 220, 22, "Search this chat...")
    panel.chatSearch:SetPoint("TOPRIGHT", panel.right, "TOPRIGHT", -12, -40)
    -- userInput only: programmatic SetText (clearing the box on Jump or
    -- on conversation switch) also fires OnTextChanged - reacting to that
    -- re-entered RefreshChatPanel mid-render, and the outer pass then
    -- re-rendered with the jump target already consumed, which is why the
    -- jump highlight never showed up.
    panel.chatSearch:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        panel.chatSearchText = fieldValue(self)
        SW:RefreshChatPanel()
    end)
    panel.chatSearchAll = checkButton(panel.right)
    panel.chatSearchAll:SetPoint("RIGHT", panel.chatSearch, "LEFT", -6, 0)
    panel.chatSearchAllLabel = text(panel.right, "All Chats", "GameFontHighlightSmall")
    panel.chatSearchAllLabel:SetPoint("RIGHT", panel.chatSearchAll, "LEFT", -2, 0)
    panel.chatSearchAll:SetScript("OnClick", function(self)
        panel.searchAllChats = self:GetChecked() and true or false
        SW:RefreshMessagesPanel()
    end)
    panel.chat = scroll(panel.right)
    panel.message = edit(panel.right, 1, 24, "Write a message...")
    panel.message:SetPoint("BOTTOMLEFT", 16, 12)
    panel.message:SetPoint("BOTTOMRIGHT", -96, 12)
    panel.send = button(panel.right, "Send", 72, 24)
    panel.send:SetPoint("BOTTOMRIGHT", -14, 12)
    panel.chat:SetPoint("TOPLEFT", 16, -66)
    panel.chat:SetPoint("TOPRIGHT", -32, -66)
    -- Bottom anchor is redone per-refresh in RefreshChatPanel, since it
    -- depends on whether the message row is currently sendable.

    -- Shift-clicking an item/spell/quest links it into whichever chat edit
    -- box the game considers "active" - that's normally only the default
    -- ChatFrame boxes, since ChatEdit_InsertLink is what Shift-click
    -- actually calls. Hooking it (not overwriting - falls through to the
    -- original for every other edit box) is the standard way a custom
    -- EditBox opts into that, same technique WeakAuras/most addons with
    -- their own text inputs use.
    if not SW.originalChatEditInsertLink then
        SW.originalChatEditInsertLink = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(text)
            if panel.message:IsVisible() and panel.message:HasFocus() then
                panel.message:Insert(text)
                return true
            end
            return SW.originalChatEditInsertLink(text)
        end
    end
    -- Items shift-click straight into ChatEdit_InsertLink, but the Quest
    -- Tracker checks ChatEdit_GetActiveWindow() first to decide whether any
    -- chat box is "active" at all before it bothers linking - since that
    -- only knows about the default ChatFrame boxes, it saw none focused and
    -- fell back to its other Shift-click behavior (untracking the quest)
    -- instead of ever calling ChatEdit_InsertLink. Hooking this one too so
    -- it reports our EditBox as active while it's focused fixes that.
    if not SW.originalChatEditGetActiveWindow then
        SW.originalChatEditGetActiveWindow = ChatEdit_GetActiveWindow
        ChatEdit_GetActiveWindow = function()
            if panel.message:IsVisible() and panel.message:HasFocus() then
                return panel.message
            end
            return SW.originalChatEditGetActiveWindow()
        end
    end

    -- Floating pill, shown only while scrolled up and unseen messages have
    -- arrived below (see RefreshChatPanel) - click jumps to the bottom.
    -- Anchored to panel.right (not panel.message, which moves/hides
    -- depending on conversation type) so its position stays predictable.
    panel.newMessagesPill = fitButton(button(panel.right, "", 10, 22), 16)
    panel.newMessagesPill:SetPoint("BOTTOM", panel.right, "BOTTOM", 0, 48)
    -- Sibling of panel.chat (the scroll frame) at the same base frame
    -- level - without its own strata the chat's own token widgets
    -- (individually created, one per word/link) ended up drawn on top of
    -- it instead of the other way around.
    panel.newMessagesPill:SetFrameStrata("HIGH")
    panel.newMessagesPill:Hide()
    panel.newMessagesPill:SetScript("OnClick", function()
        panel.newMessagesWhileScrolled = 0
        panel.chatSyncingScroll = true
        panel.chat:SetVerticalScroll(panel.chat:GetVerticalScrollRange())
        panel.chatSyncingScroll = false
        panel.newMessagesPill:Hide()
    end)
    -- Two independent jobs: (1) scrolling within MAX_RENDERED_MESSAGES
    -- pixels of the top grows the render window and reloads (see
    -- panel.renderLimit in RefreshChatPanel), and (2) scrolling back to the
    -- bottom manually dismisses the new-messages pill without waiting for
    -- another refresh. chatSyncingScroll skips both while a refresh's own
    -- SetVerticalScroll call is what triggered this event, not the user.
    panel.chat:HookScript("OnVerticalScroll", function(self, offset)
        if panel.chatSyncingScroll then return end
        local range = self:GetVerticalScrollRange()
        if offset >= range - 40 then
            panel.newMessagesWhileScrolled = 0
            if panel.newMessagesPill then panel.newMessagesPill:Hide() end
        end
        if offset <= 40 and panel.chatRenderStart and panel.chatRenderStart > 1 then
            panel.renderLimit = (panel.renderLimit or MAX_RENDERED_MESSAGES) + MAX_RENDERED_MESSAGES
            panel.chatLoadingMore = true
            SW:RefreshChatPanel()
        end
    end)
    local function send()
        local conversation = SW:GetConversation(SW.ui.selectedKey)
        if not conversation then SW:Print("Select a conversation first."); return end
        local ok, err = SW:SendConversationMessage(conversation, fieldValue(panel.message))
        if ok then
            panel.message:SetText("")
            panel.message:SetFocus()
        else
            SW:Print(err)
        end
    end
    panel.send:SetScript("OnClick", send)
    panel.message:SetScript("OnEnterPressed", function() send() end)
end

local ROW_HEIGHT = 22

-- One compact line per conversation: icons, name, realm and unread count all
-- share a single row instead of a 3-line card with a message preview.
local function createConversationRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- The gold quest-log gradient (hover AND selection) belongs to the
    -- parchment look - on the flat themes it clashed with their own
    -- palettes, so those get flat fills in the theme's accent color
    -- instead (hover fainter than selection).
    local rowTheme = currentTheme()
    if rowTheme.useNativeWidgets then
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    else
        local a = rowTheme.accentColor
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        local hover = row:GetHighlightTexture()
        if hover then hover:SetVertexColor(a[1], a[2], a[3], 0.14) end
    end
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    if rowTheme.useNativeWidgets then
        row.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected:SetBlendMode("ADD")
    else
        local a = rowTheme.accentColor
        row.selected:SetColorTexture(a[1], a[2], a[3], 0.30)
    end
    row.selected:Hide()
    row.pinIcon = row:CreateTexture(nil, "ARTWORK")
    row.pinIcon:SetSize(13, 13)
    row.pinIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
    row.favoriteIcon = row:CreateTexture(nil, "ARTWORK")
    row.favoriteIcon:SetSize(13, 13)
    row.favoriteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    row.name = text(row, "", "GameFontHighlightSmall")
    row.realm = text(row, "", "GameFontDisableSmall")
    row.realm:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
    row.unread = text(row, "", "GameFontNormalSmall", 1, 0.39, 0.66)
    row.unread:SetPoint("RIGHT", -8, 0)
    return row
end

function SW:RefreshMessagesPanel()
    local panel = self.ui.panels.Messages
    if not panel then return end
    local conversations = self:GetSortedConversations(false)
    local listFilter = self.ui.listFilter or "all"
    if listFilter ~= "all" then
        local filtered = {}
        for _, conversation in ipairs(conversations) do
            local include
            if listFilter == "dm" then include = not conversation.system
            elseif listFilter == "guild" then include = conversation.system and conversation.channel == "guild"
            elseif listFilter == "group" then include = conversation.system and (conversation.channel == "party" or conversation.channel == "raid")
            elseif listFilter == "channel" then include = conversation.system and conversation.channel == "channel"
            end
            if include then filtered[#filtered + 1] = conversation end
        end
        conversations = filtered
    end
    for _, pill in ipairs({ panel.filterAll, panel.filterDM, panel.filterGuild, panel.filterGroup, panel.filterChannel }) do
        pill:UnlockHighlight()
    end
    local activePill = ({ all = panel.filterAll, dm = panel.filterDM, guild = panel.filterGuild, group = panel.filterGroup, channel = panel.filterChannel })[listFilter]
    if activePill then activePill:LockHighlight() end
    if self.ui.selectedKey and not self:GetConversation(self.ui.selectedKey) then self.ui.selectedKey = nil end
    -- Switching filter pills should switch the right-hand view to
    -- something the filter actually shows, rather than keep displaying a
    -- conversation (e.g. a DM) that's no longer part of the filtered list.
    local selectedInView = false
    for _, conversation in ipairs(conversations) do
        if conversation.key == self.ui.selectedKey then selectedInView = true; break end
    end
    if not selectedInView and conversations[1] then self.ui.selectedKey = conversations[1].key end
    -- The count/limit shown here matches whichever filter pill is active -
    -- each category has its own separate "to keep" limit, so a single
    -- fixed "Conversations X/200" that never changed with the filter was
    -- showing the DM number even while looking at Guild/Group/Channels. On
    -- "All", where no single limit applies, show all three at once instead.
    local dmMax = math.max(1, math.floor(tonumber(self.DB.settings.maxConversations) or 200))
    local dmCount = 0
    for _ in pairs(self.DB.conversations or {}) do dmCount = dmCount + 1 end
    local groupMax = math.max(1, math.floor(tonumber(self.DB.settings.maxGroupSessions) or 200))
    local groupCount = 0
    local channelMax = math.max(1, math.floor(tonumber(self.DB.settings.maxChannels) or 50))
    local channelCount = 0
    for _, c in pairs(self.DB.groupChats or {}) do
        if type(c) == "table" then
            if c.channel == "party" or c.channel == "raid" then groupCount = groupCount + 1
            elseif c.channel == "channel" then channelCount = channelCount + 1 end
        end
    end
    local counterText
    if listFilter == "dm" then
        counterText = "DM conversations  " .. dmCount .. "/" .. dmMax
    elseif listFilter == "group" then
        counterText = "Party/Raid sessions  " .. groupCount .. "/" .. groupMax
    elseif listFilter == "channel" then
        counterText = "Channels  " .. channelCount .. "/" .. channelMax
    elseif listFilter == "guild" then
        -- Guild Chat is a single fixed conversation, not a "keep N of
        -- these" category - there's no limit to show a count against.
        counterText = "Guild Chat"
    else
        counterText = string.format("DM %d/%d   Grp %d/%d   Chan %d/%d", dmCount, dmMax, groupCount, groupMax, channelCount, channelMax)
    end
    panel.counter:SetText(self.ui.selectMode and "Select chats" or counterText)
    panel.select:SetText(self.ui.selectMode and "Done" or "Select")
    fitButton(panel.select)
    -- Re-equalize after the label change ("Select"/"Done" refit above) so
    -- both rows' right-column buttons keep one shared width - see the
    -- matching alignment comment in BuildMessagesPanel.
    panel.select:SetWidth(math.max(panel.select:GetWidth(), panel.add:GetWidth()))
    panel.addChannel:SetPoint("RIGHT", panel.select, "LEFT", -6, 0)
    if self.ui.selectMode then panel.deleteSelected:Show(); panel.cancelSelected:Show() else panel.deleteSelected:Hide(); panel.cancelSelected:Hide() end
    -- The list only needs to leave room at the bottom for the delete/cancel
    -- buttons while they're actually visible; otherwise it should reach all
    -- the way down instead of leaving a dead gap above the panel border.
    panel.list:ClearAllPoints()
    panel.list:SetPoint("TOPLEFT", panel.left, "TOPLEFT", 12, -114)
    panel.list:SetPoint("BOTTOMRIGHT", panel.left, "BOTTOMRIGHT", -30, self.ui.selectMode and 48 or 12)
    local content = panel.list.content
    poolStart(content)
    local listWidth = math.max(180, panel.list:GetWidth() - 4)
    local y = 0
    for _, conversation in ipairs(conversations) do
        local row = poolRow(content, createConversationRow)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:SetSize(listWidth, ROW_HEIGHT)
        local selected = conversation.key == self.ui.selectedKey
        local marked = self.ui.selectedDMs and self.ui.selectedDMs[conversation.key]
        row.selected:SetShown(selected or marked)
        local marker = self.ui.selectMode and (marked and "[x] " or "[ ] ") or ""
        local base, realm = splitRealm(conversation.name)
        if conversation.system and conversation.channel == "guild" and GetGuildInfo then
            realm = GetGuildInfo("player")
        end
        row.name:SetText(marker .. base)
        row.realm:SetText(realm and ("(" .. realm .. ")") or "")
        row.realm:SetShown(realm ~= nil)
        -- Only icons that are actually shown reserve space, so a row with
        -- neither pin nor favorite hugs the left edge instead of leaving a
        -- gap where a hidden icon would have been.
        local iconX = 8
        row.pinIcon:ClearAllPoints()
        if conversation.pinned then
            row.pinIcon:SetPoint("LEFT", iconX, 0)
            row.pinIcon:Show()
            iconX = iconX + 16
        else
            row.pinIcon:Hide()
        end
        row.favoriteIcon:ClearAllPoints()
        if conversation.favorite then
            row.favoriteIcon:SetPoint("LEFT", iconX, 0)
            row.favoriteIcon:Show()
            iconX = iconX + 16
        else
            row.favoriteIcon:Hide()
        end
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", iconX, 0)
        if conversation.unread and conversation.unread > 0 then
            row.unread:SetText("[" .. (conversation.unread > 99 and "99+" or tostring(conversation.unread)) .. "]")
            row.unread:Show()
        else
            row.unread:Hide()
        end
        row:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                SW:ShowContextMenu(SW:ContextMenuItemsFor(conversation), self)
                return
            end
            if SW.ui.selectMode then
                SW.ui.selectedDMs = SW.ui.selectedDMs or {}
                SW.ui.selectedDMs[conversation.key] = not SW.ui.selectedDMs[conversation.key] or nil
            else
                SW.ui.selectedKey = conversation.key
                conversation.unread = 0
            end
            SW:RefreshUI()
        end)
        y = y - (ROW_HEIGHT + 2)
    end
    poolFinish(content)
    content:SetSize(listWidth, math.max(panel.list:GetHeight(), -y + 4))
    self:RefreshChatPanel()
end

-- A Button wrapping the line's FontString, rather than relying on
-- FontString:SetHyperlinksEnabled (a newer API that isn't reliably present
-- on this client - it silently no-ops instead of erroring). Used both as a
-- whole-line widget (date separators, system notes, the members line) and,
-- via poolLinkToken below, as the widget for a single link token within a
-- word-wrapped message.
local function createChatLine(parent)
    local line = CreateFrame("Button", nil, parent)
    -- A Button created without a template doesn't register for any click
    -- type by default, so OnClick silently never fired - only OnEnter/
    -- OnLeave (hover tooltip) worked, which is why links looked "almost"
    -- clickable.
    line:EnableMouse(true)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    line.text = text(line, "", "GameFontHighlightSmall")
    line.text:SetPoint("TOPLEFT", 0, 0)
    line.text:SetJustifyV("TOP")
    if line.text.SetWordWrap then line.text:SetWordWrap(true) end
    -- A sender name is tokenized as a "player:Name" link (see the speaker
    -- construction in RefreshChatPanel) purely to reuse this widget/pool -
    -- it's not a real WoW hyperlink, so it's handled entirely by hand
    -- instead of being routed through Blizzard's own hyperlink API:
    -- GameTooltip:SetHyperlink doesn't recognize "player:" links on
    -- Classic Era ("Unknown link type" spam), and worse, SetItemRef's own
    -- native right-click menu LOOKS like it works but silently fails on
    -- "Copy Character Name" - CopyToClipboard is a protected function, and
    -- the click chain is tainted by having passed through an addon-created
    -- button, so Blizzard's own secure code refuses the call too.
    line:SetScript("OnEnter", function(self)
        if self.link and not string.match(self.link, "^player:") then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    line:SetScript("OnClick", function(self, mouseButton)
        if not self.link then return end
        local playerName = string.match(self.link, "^player:(.+)$")
        if playerName then
            if mouseButton == "RightButton" then SW:ShowNameContextMenu(playerName, self) end
            return
        end
        if SetItemRef then SetItemRef(self.link, "", mouseButton, self) end
    end)
    return line
end

-- Shared row template for "flat list of messages from anywhere" views -
-- global search results and the Bookmarks tab both show the same shape
-- (source conversation, sender, snippet, a way to jump there, a way to
-- toggle the bookmark) so one factory covers both instead of two
-- near-duplicates.
local function createMessageResultRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.jump = fitButton(button(row, "Jump", 10, 20))
    row.jump:SetPoint("RIGHT", -12, 0)
    row.bookmark = iconButton(row, "Interface\\Icons\\INV_Misc_Note_01", "Toggle bookmark")
    row.bookmark:SetPoint("RIGHT", row.jump, "LEFT", -6, 0)
    -- Crop the icon's built-in dark border edge - inside a themed button
    -- frame it doubled up and looked muddy.
    row.bookmark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Both text lines end BEFORE the buttons instead of running underneath
    -- them, truncated to one line each.
    row.label = text(row, "", "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", 12, -6)
    row.label:SetPoint("RIGHT", row.bookmark, "LEFT", -10, 0)
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    row.meta = text(row, "", "GameFontDisableSmall")
    row.meta:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.meta:SetPoint("RIGHT", row.bookmark, "LEFT", -10, 0)
    if row.meta.SetWordWrap then row.meta:SetWordWrap(false) end
    return row
end

-- Splits a fully-processed message (colors/icons/synthesized quest links
-- already applied) into an ordered list of tokens: {kind="word", text=...}
-- for a single space-free run of plain text, or {kind="link", link=...,
-- text=...} for one whole "|cAARRGGBB|Hdata|h[Display]|h|r" hyperlink,
-- kept atomic (never split mid-link). This lets each hyperlink in a
-- message get laid out as its own widget with its own hit-box, instead of
-- one FontString/Button per whole line only ever exposing the first link
-- it happened to contain.
local function tokenizeMessage(value)
    local tokens = {}
    local pos, len = 1, #value
    while pos <= len do
        local linkStart, linkEnd, colorCode, linkData, display =
            string.find(value, "(|c%x%x%x%x%x%x%x%x)|H(.-)|h(.-)|h|r", pos)
        local plainEnd = linkStart and (linkStart - 1) or len
        if plainEnd >= pos then
            for word in string.gmatch(string.sub(value, pos, plainEnd), "%S+") do
                tokens[#tokens + 1] = { kind = "word", text = word }
            end
        end
        if not linkStart then break end
        tokens[#tokens + 1] = {
            kind = "link",
            link = linkData,
            text = colorCode .. "|H" .. linkData .. "|h" .. display .. "|h|r",
        }
        pos = linkEnd + 1
    end
    return tokens
end

-- Separate pools from the generic poolStart/poolRow/poolFinish above (which
-- stay untouched for every other list in this file): a chat message needs a
-- variable number of word/link widgets, not one widget per row.
local function poolWordToken(content)
    content.wordPool = content.wordPool or { items = {}, count = 0 }
    local pool = content.wordPool
    pool.count = pool.count + 1
    local item = pool.items[pool.count]
    if not item then
        item = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        item:SetJustifyH("LEFT")
        item:SetJustifyV("TOP")
        pool.items[pool.count] = item
    end
    item:Show()
    return item
end

local function poolLinkToken(content)
    content.linkPool = content.linkPool or { items = {}, count = 0 }
    local pool = content.linkPool
    pool.count = pool.count + 1
    local item = pool.items[pool.count]
    if not item then
        item = createChatLine(content)
        pool.items[pool.count] = item
    end
    item:Show()
    return item
end

-- One small star button per rendered real message, right-aligned. There's
-- no single "row frame" per message (see the word/link token pools above -
-- a message is N+1 independently-positioned widgets, not one container),
-- so this is anchored directly to content at the Y the message started at
-- (captured before the token loop advances it), independent of the
-- word-wrap math rather than threaded through it.
local function poolBookmarkIcon(content)
    content.bookmarkPool = content.bookmarkPool or { items = {}, count = 0 }
    local pool = content.bookmarkPool
    pool.count = pool.count + 1
    local icon = pool.items[pool.count]
    if not icon then
        icon = CreateFrame("Button", nil, content)
        icon:SetSize(14, 14)
        icon.texture = icon:CreateTexture(nil, "OVERLAY")
        icon.texture:SetAllPoints()
        icon.texture:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        icon:RegisterForClicks("LeftButtonUp")
        pool.items[pool.count] = icon
    end
    icon:Show()
    return icon
end

-- Global search results use their own pool (createMessageResultRow), not
-- the generic content.pool used for chat-line widgets (separators/system
-- notes/members line via createChatLine) - the generic pool assumes one
-- consistent widget shape for the lifetime of a content frame, and this
-- content frame (panel.chat.content) is shared between the normal
-- per-conversation chat view and the "all conversations" search-results
-- view, which need very differently-shaped rows. Folded into
-- resetTokenPools/finishTokenPools (despite the name) so every refresh -
-- regardless of which of those two views it renders - always resets and
-- hides leftovers from *both*, or switching between them would leave
-- stale widgets from whichever view didn't run that pass still visible.
-- Shared by RenderGlobalSearchResults and RefreshBookmarksPanel - fills in
-- the label/meta/bookmark-star bits both use identically, leaving only the
-- "what does Jump actually do" behavior (which differs slightly between
-- the two) to the caller.
local function populateMessageResultRow(row, conversation, message, onJump)
    local speaker = message.outgoing and "You" or (message.sender or splitRealm(conversation.name))
    row.label:SetText(speaker .. ": " .. plainText(message.text))
    row.meta:SetText(splitRealm(conversation.name) .. " - " .. date("%d.%m.%Y %H:%M", message.timestamp or 0))
    row.jump:SetScript("OnClick", onJump)
    -- Desaturation instead of a color tint - tinting a painted icon
    -- gold/grey just made it muddy; grey-and-dim vs. full-color reads
    -- clearly as off/on.
    if message.bookmarked then
        row.bookmark.icon:SetDesaturated(false)
        row.bookmark.icon:SetVertexColor(1, 1, 1, 1)
    else
        row.bookmark.icon:SetDesaturated(true)
        row.bookmark.icon:SetVertexColor(1, 1, 1, 0.5)
    end
    row.bookmark:SetScript("OnClick", function()
        SW:ToggleMessageBookmark(conversation, message)
        SW:RefreshUI()
    end)
end

local function poolResultRow(content)
    content.resultPool = content.resultPool or { items = {}, count = 0 }
    local pool = content.resultPool
    pool.count = pool.count + 1
    local row = pool.items[pool.count]
    if not row then
        row = createMessageResultRow(content)
        pool.items[pool.count] = row
    end
    row:Show()
    return row
end

local function resetTokenPools(content)
    if content.wordPool then content.wordPool.count = 0 end
    if content.linkPool then content.linkPool.count = 0 end
    if content.bookmarkPool then content.bookmarkPool.count = 0 end
    if content.resultPool then content.resultPool.count = 0 end
end

local function finishTokenPools(content)
    if content.wordPool then
        for i = content.wordPool.count + 1, #content.wordPool.items do content.wordPool.items[i]:Hide() end
    end
    if content.linkPool then
        for i = content.linkPool.count + 1, #content.linkPool.items do content.linkPool.items[i]:Hide() end
    end
    if content.bookmarkPool then
        for i = content.bookmarkPool.count + 1, #content.bookmarkPool.items do content.bookmarkPool.items[i]:Hide() end
    end
    if content.resultPool then
        for i = content.resultPool.count + 1, #content.resultPool.items do content.resultPool.items[i]:Hide() end
    end
end

-- The "All Chats" search mode swaps the normal per-conversation chat view
-- for a flat, scrollable list of matches from every conversation (not
-- rendered through the token/word-wrap pipeline - each match is a single
-- summary row, same shape as the Bookmarks tab, via createMessageResultRow/
-- poolResultRow). Hides all the conversation-specific chrome (name, status,
-- star/pin/members/delete, message box) since none of it applies here.
function SW:RenderGlobalSearchResults(panel, content)
    panel.chatSearch:Show(); panel.chatSearchAll:Show(); panel.chatSearchAllLabel:Show()
    panel.contact:SetText("Search results")
    panel.contact:ClearAllPoints()
    panel.contact:SetPoint("TOPLEFT", 16, -12)
    panel.contactFavoriteIcon:Hide()
    panel.contactRealm:Hide()
    panel.statusDot:Hide(); panel.statusText:Hide(); panel.hasAddonIcon:Hide()
    panel.members:Hide(); panel.contactMenu:Hide()
    panel.message:Hide(); panel.send:Hide()
    panel.chat:ClearAllPoints()
    panel.chat:SetPoint("TOPLEFT", 16, -66)
    panel.chat:SetPoint("TOPRIGHT", -32, -66)
    panel.chat:SetPoint("BOTTOMLEFT", panel.right, "BOTTOMLEFT", 16, 12)
    panel.chat:SetPoint("BOTTOMRIGHT", panel.right, "BOTTOMRIGHT", -32, 12)
    local results = self:SearchAllMessages(panel.chatSearchText)
    local width = math.max(340, panel.chat:GetWidth() - 5)
    local y = 0
    if #results == 0 then
        local empty = poolRow(content, createChatLine)
        empty.link = nil
        empty.text:SetText("No messages match \"" .. panel.chatSearchText .. "\".")
        empty.text:SetTextColor(0.62, 0.62, 0.62)
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", 10, -12)
        empty.text:SetWidth(width - 20)
        empty:SetSize(width - 20, 20)
        y = -40
    else
        for i = 1, math.min(#results, MAX_RENDERED_MESSAGES) do
            local entry = results[i]
            local conversation, message = entry.conversation, entry.message
            local row = poolResultRow(content)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(width, 44)
            populateMessageResultRow(row, conversation, message, function()
                panel.searchAllChats = false
                panel.chatSearchAll:SetChecked(false)
                -- Explicitly cleared here rather than relying on the
                -- "conversation changed" auto-clear in RefreshChatPanel -
                -- that check compares against whatever conversation was
                -- selected before global search was ever turned on, which
                -- could happen to already equal the jump target, silently
                -- skipping the clear and leaving stale search text (and
                -- focus/cursor) behind in the box.
                panel.chatSearchText = nil
                panel.chatSearch:ClearFocus()
                panel.chatSearch:SetText(panel.chatSearch.hint or "")
                panel.scrollToMessage = message
                SW.ui.selectedKey = conversation.key
                -- A jump target outside the active list filter (e.g. "DM"
                -- while jumping to a Guild Chat result) got silently
                -- overridden right back by RefreshMessagesPanel's "keep
                -- selection valid" check, since the target conversation
                -- wasn't even in the filtered list to begin with.
                SW.ui.listFilter = "all"
                SW:RefreshUI()
            end)
            y = y - 48
        end
    end
    content:SetSize(width, math.max(panel.chat:GetHeight(), -y + 8))
    panel.chat:UpdateScrollChildRect()
    panel.chat:SetVerticalScroll(0)
end

function SW:RefreshChatPanel()
    local panel = self.ui.panels.Messages
    if panel.searchAllChats and panel.chatSearchText and panel.chatSearchText ~= "" then
        local content = panel.chat.content
        poolStart(content)
        resetTokenPools(content)
        self:RenderGlobalSearchResults(panel, content)
        poolFinish(content)
        finishTokenPools(content)
        -- This view doesn't have a growable render window (see
        -- panel.renderLimit below) - without resetting this, the
        -- OnVerticalScroll hook could still see a >1 value left over from
        -- the last normal conversation and trigger a pointless extra
        -- refresh when scrolling to the top of this list.
        panel.chatRenderStart = 1
        return
    end
    local conversation = self:GetConversation(self.ui.selectedKey)
    -- A search filter left over from a different conversation would
    -- silently hide messages in whatever's newly selected without any
    -- indication why - clear it the moment the selected conversation
    -- actually changes (not on every refresh, or typing would never work).
    local keyChanged = panel.lastSearchedKey ~= self.ui.selectedKey
    if keyChanged then
        panel.lastSearchedKey = self.ui.selectedKey
        panel.chatSearchText = nil
        if panel.chatSearch then panel.chatSearch:SetText(panel.chatSearch.hint or "") end
        -- See PingContact (Whispers.lua) - own cooldown, so opening the
        -- same DM repeatedly doesn't spam a ping every time.
        if conversation then self:PingContact(conversation) end
    end
    -- The rendered window grows by MAX_RENDERED_MESSAGES each time the user
    -- scrolls near the top (see the OnVerticalScroll hook in
    -- BuildMessagesPanel) instead of only ever showing the last 200 - but
    -- only within the same conversation and search filter; switching
    -- either one means a completely different message set, so the window
    -- resets back down to the normal starting size rather than staying
    -- artificially large.
    if keyChanged or panel.lastRenderedSearchText ~= panel.chatSearchText then
        panel.renderLimit = MAX_RENDERED_MESSAGES
    end
    panel.lastRenderedSearchText = panel.chatSearchText
    panel.renderLimit = panel.renderLimit or MAX_RENDERED_MESSAGES
    -- A refresh doesn't always mean "new message arrived" - toggling a
    -- bookmark, or a pin/favorite elsewhere, also calls NotifyDataChanged
    -- and re-runs this. Snapping back to the bottom every time that
    -- happens while the user is scrolled up reading old messages (e.g. to
    -- bookmark one) was disorienting - only genuinely new messages (the
    -- stored count actually grew) while already at the bottom, or
    -- switching conversations, should jump to the bottom; anything else
    -- preserves wherever they'd scrolled to.
    local previousScroll = panel.chat:GetVerticalScroll()
    local previousScrollRange = panel.chat:GetVerticalScrollRange()
    local wasNearBottom = previousScrollRange <= 0 or previousScroll >= previousScrollRange - 40
    local sameConversationAsLastRender = panel.lastRenderKey == self.ui.selectedKey
    local sameMessageCountAsLastRender = sameConversationAsLastRender
        and panel.lastRenderCount == #(conversation and conversation.messages or {})
    -- When a scroll-near-the-top gesture just grew the render window (see
    -- the OnVerticalScroll hook), find whichever message was sitting at
    -- the top of the viewport before older messages get inserted above it,
    -- using last render's message->Y map - so the view can be re-anchored
    -- on that same message afterward instead of visibly jumping around.
    local anchorMessage
    if panel.chatLoadingMore and panel.messageYPositions then
        local bestDelta
        for message, msgY in pairs(panel.messageYPositions) do
            local delta = -msgY - previousScroll
            if delta >= -2 and (not bestDelta or delta < bestDelta) then
                bestDelta = delta
                anchorMessage = message
            end
        end
    end
    local content = panel.chat.content
    poolStart(content)
    resetTokenPools(content)
    if not conversation then
        panel.contact:SetText("Select a conversation")
        panel.contact:ClearAllPoints()
        panel.contact:SetPoint("TOPLEFT", 16, -12)
        panel.contactFavoriteIcon:Hide()
        panel.contactRealm:Hide()
        panel.statusDot:Hide(); panel.statusText:Hide(); panel.hasAddonIcon:Hide()
        panel.members:Hide(); panel.contactMenu:Hide()
        panel.message:Hide(); panel.send:Hide()
        panel.chatSearch:Hide(); panel.chatSearchAll:Hide(); panel.chatSearchAllLabel:Hide()
        panel.chat:ClearAllPoints()
        panel.chat:SetPoint("TOPLEFT", 16, -66)
        panel.chat:SetPoint("TOPRIGHT", -32, -66)
        panel.chat:SetPoint("BOTTOMLEFT", panel.right, "BOTTOMLEFT", 16, 12)
        panel.chat:SetPoint("BOTTOMRIGHT", panel.right, "BOTTOMRIGHT", -32, 12)
        poolFinish(content)
        finishTokenPools(content)
        return
    end
    panel.chatSearch:Show(); panel.chatSearchAll:Show(); panel.chatSearchAllLabel:Show()
    local base, realm = splitRealm(conversation.name)
    if conversation.system and conversation.channel == "guild" and GetGuildInfo then
        realm = GetGuildInfo("player")
    end
    panel.contact:SetText(base)
    panel.contact:ClearAllPoints()
    if conversation.favorite then
        panel.contactFavoriteIcon:SetPoint("TOPLEFT", 16, -13)
        panel.contactFavoriteIcon:Show()
        panel.contact:SetPoint("TOPLEFT", panel.contactFavoriteIcon, "TOPRIGHT", 6, 1)
    else
        panel.contactFavoriteIcon:Hide()
        panel.contact:SetPoint("TOPLEFT", 16, -12)
    end
    panel.contactRealm:SetText(realm and ("(" .. realm .. ")") or "")
    panel.contactRealm:SetShown(realm ~= nil)
    -- Right-click hit-region over the contact name for the Watchlist/Pin/
    -- Copy Name/Export/Delete context menu - repositioned every refresh
    -- since the name's width changes.
    panel.contactMenu:ClearAllPoints()
    panel.contactMenu:SetPoint("TOPLEFT", panel.contact, "TOPLEFT", -4, 4)
    panel.contactMenu:SetPoint("BOTTOMRIGHT", panel.contact, "BOTTOMRIGHT", 4, -4)
    panel.contactMenu:Show()
    if conversation.system then
        panel.statusDot:Hide(); panel.statusText:Hide(); panel.hasAddonIcon:Hide()
        -- Guild Chat is the one system conversation that's a fixed, single
        -- entry rather than one of several (sessions, channels) - a
        -- members list here would just duplicate the default Guild Roster
        -- window.
        panel.members:SetShown(conversation.channel ~= "guild")
        -- Guild Chat can always be used here. Party/Raid sessions get the
        -- same chat row only while they are the active group; old saved
        -- sessions and manually added channels intentionally stay read-only.
        local canSend = self:CanSendToConversation(conversation)
        panel.message:SetShown(canSend); panel.send:SetShown(canSend)
        if canSend then panel.message:Enable(); panel.send:Enable() else panel.message:ClearFocus() end
        panel.chat:ClearAllPoints()
        panel.chat:SetPoint("TOPLEFT", 16, -66)
        panel.chat:SetPoint("TOPRIGHT", -32, -66)
        panel.chat:SetPoint("BOTTOMLEFT", panel.right, "BOTTOMLEFT", 16, canSend and 44 or 12)
        panel.chat:SetPoint("BOTTOMRIGHT", panel.right, "BOTTOMRIGHT", -32, canSend and 44 or 12)
    else
        panel.members:Hide(); panel.message:Show(); panel.send:Show(); panel.message:Enable(); panel.send:Enable()
        panel.chat:ClearAllPoints()
        panel.chat:SetPoint("TOPLEFT", 16, -66)
        panel.chat:SetPoint("TOPRIGHT", -32, -66)
        panel.chat:SetPoint("BOTTOMLEFT", panel.right, "BOTTOMLEFT", 16, 44)
        panel.chat:SetPoint("BOTTOMRIGHT", panel.right, "BOTTOMRIGHT", -32, 44)
        local state = self:GetContactStatus(conversation.name)
        local indicator = state == "online" and "Green" or (state == "busy" and "Yellow" or "Gray")
        local stateLabel = state == "online" and "Online" or (state == "busy" and "Busy" or "Offline")
        panel.statusDot:ClearAllPoints()
        panel.statusDot:SetPoint("LEFT", panel.contact, "LEFT", panel.contact:GetStringWidth() + 8, 3)
        panel.statusDot:SetTexture("Interface\\COMMON\\Indicator-" .. indicator)
        panel.statusDot:Show()
        panel.statusText:SetText("(" .. stateLabel .. ")")
        if state == "online" then panel.statusText:SetTextColor(0.20, 0.80, 0.38)
        elseif state == "busy" then panel.statusText:SetTextColor(0.95, 0.75, 0.18)
        else panel.statusText:SetTextColor(0.62, 0.62, 0.62) end
        panel.statusText:Show()
        panel.hasAddonIcon:SetShown(conversation.hasAddon and true or false)
    end
    local width = math.max(340, panel.chat:GetWidth() - 5)
    local y = 0
    if conversation.members and #conversation.members > 0 then
        local membersLine = poolRow(content, createChatLine)
        membersLine.link = nil
        membersLine.text:SetJustifyH("LEFT")
        membersLine.text:SetText("|cffffd100Members:|r " .. table.concat(conversation.members, ", "))
        membersLine.text:SetTextColor(0.75, 0.75, 0.75)
        membersLine:ClearAllPoints()
        membersLine:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
        membersLine.text:SetWidth(width - 16)
        local membersHeight = membersLine.text:GetStringHeight() or 14
        membersLine:SetSize(width - 16, membersHeight)
        y = y - membersHeight - 10
    end
    local todayKey = date("%Y-%m-%d")
    local yesterdayKey = date("%Y-%m-%d", time() - 86400)
    local lastDayKey = nil
    local allMessages = conversation.messages or {}
    -- Rendering builds several word/link widgets per message (see
    -- tokenizeMessage above) - doing that for the entire stored history
    -- (up to maxGroupMessages, e.g. 1500 in a busy Guild Chat) on every
    -- single refresh is what caused the noticeable stutter opening the
    -- window. The full history is still there for Export chat; only the
    -- rendered window is capped - normally to the last 200 raw messages,
    -- but while a chat search is active, to the last 200 *matches* instead
    -- (found by scanning the full history, not just that tail), otherwise
    -- searching for something older than the 200 most recent messages
    -- would silently find nothing.
    local searchText = panel.chatSearchText and panel.chatSearchText ~= "" and string.lower(panel.chatSearchText) or nil
    local renderMessages
    if searchText then
        local matches = {}
        for _, message in ipairs(allMessages) do
            if not message.system and message.text and string.find(string.lower(message.text), searchText, 1, true) then
                matches[#matches + 1] = message
            end
        end
        renderMessages = matches
    else
        renderMessages = allMessages
    end
    local renderStart = math.max(1, #renderMessages - panel.renderLimit + 1)
    -- A bookmark can easily be older than the last 200 messages (that's
    -- the whole point of bookmarking it) - if the Jump target isn't in the
    -- normal tail window, re-anchor the window around it instead, so it's
    -- actually rendered (and therefore something the scroll-to below can
    -- find at all) rather than always showing just the most recent tail.
    if panel.scrollToMessage then
        for i, m in ipairs(renderMessages) do
            if m == panel.scrollToMessage then
                if i < renderStart then
                    renderStart = math.max(1, i - math.floor(MAX_RENDERED_MESSAGES / 2))
                end
                break
            end
        end
    end
    -- Published so the OnVerticalScroll hook (BuildMessagesPanel) knows
    -- whether scrolling to the top should grow the window further.
    panel.chatRenderStart = renderStart
    -- Set by a Jump button (Bookmarks tab / global search results) - when
    -- present, scrolls to that specific message instead of the bottom.
    -- Found by reference (message tables have no stable id), captured at
    -- the same Y the bookmark icon uses so it lines up with the message's
    -- first line.
    local scrollToY
    -- Every real message's top Y this render, keyed by the message table
    -- itself - published as panel.messageYPositions at the end so the next
    -- render (if it's a load-more) can find the same message again after
    -- older ones get inserted above it and shift everything's Y.
    local messageYPositions = {}
    -- Subtle gold wash behind the jumped-to message so the eye lands on
    -- the right line after the scroll - naturally disappears on the next
    -- refresh (scrollToMessage is one-shot, see the bottom of this
    -- function), no timer needed.
    if not content.jumpHighlight then
        content.jumpHighlight = content:CreateTexture(nil, "BACKGROUND")
        -- Theme accent, not a fixed gold - gold clashed on the flat themes.
        local a = currentTheme().accentColor or { 1, 0.82, 0 }
        content.jumpHighlight:SetColorTexture(a[1], a[2], a[3], 0.16)
    end
    content.jumpHighlight:Hide()
    for index = renderStart, #renderMessages do
        local message = renderMessages[index]
        local dayKey = date("%Y-%m-%d", message.timestamp or 0)
        if dayKey ~= lastDayKey then
            local label
            if dayKey == todayKey then label = "Today"
            elseif dayKey == yesterdayKey then label = "Yesterday"
            else label = date("%B %d, %Y", message.timestamp or 0) end
            local separator = poolRow(content, createChatLine)
            separator.link = nil
            separator.text:SetJustifyH("CENTER")
            separator.text:SetText("---- " .. label .. " ----")
            separator.text:SetTextColor(0.62, 0.62, 0.62)
            separator:ClearAllPoints()
            separator:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
            separator.text:SetWidth(width - 16)
            if separator.text.SetFont then separator.text:SetFont(CHAT_FONT_PATH, 12, CHAT_FONT_FLAGS) end
            separator:SetSize(width - 16, 16)
            y = y - 20
            lastDayKey = dayKey
        end
        local chatScale = tonumber(self.DB.settings.chatScale) or 1
        local fontHeight = math.max(12, math.floor(13 * chatScale))
        if message.system then
            -- A synthetic marker (e.g. "Group was converted to a raid"),
            -- not a real chat message - render like the date separators.
            local note = poolRow(content, createChatLine)
            note.link = nil
            note.text:SetJustifyH("CENTER")
            note.text:SetText("-- " .. message.text .. " --")
            note.text:SetTextColor(0.95, 0.75, 0.18)
            note:ClearAllPoints()
            note:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
            note.text:SetWidth(width - 16)
            if note.text.SetFont then note.text:SetFont(CHAT_FONT_PATH, 12, CHAT_FONT_FLAGS) end
            note:SetSize(width - 16, 16)
            y = y - 20
        else
            -- Captured before the token loop below mutates y - the icon
            -- lines up with the message's first line regardless of how
            -- many lines it wraps to.
            local messageStartY = y
            messageYPositions[message] = messageStartY
            if panel.scrollToMessage == message then scrollToY = messageStartY end
            local bookmarkIcon = poolBookmarkIcon(content)
            bookmarkIcon:ClearAllPoints()
            bookmarkIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 4, messageStartY)
            if message.bookmarked then
                bookmarkIcon.texture:SetVertexColor(1, 0.82, 0, 1)
            else
                bookmarkIcon.texture:SetVertexColor(0.5, 0.5, 0.5, 0.6)
            end
            bookmarkIcon:SetScript("OnClick", function()
                SW:ToggleMessageBookmark(conversation, message)
                SW:RefreshUI()
            end)
            local r, g, b = chatColor(message.outgoing)
            local speaker, nameColor, linkName
            if message.outgoing then
                speaker = "You"
                linkName = UnitName and UnitName("player") or nil
                if UnitClass then
                    local _, englishClass = UnitClass("player")
                    local color = englishClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass]
                    if color then nameColor = string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) end
                end
            else
                linkName = message.sender or conversation.name
                speaker = splitRealm(linkName)
                nameColor = classColorHex(message.guid)
            end
            -- Class color when known; otherwise fall back to the
            -- configurable chat color from Settings instead of leaving the
            -- name uncolored.
            if not nameColor then nameColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255) end
            -- A real |Hplayer:...|h link, not plain colored text - lets a
            -- right-click open WoW's own player dropdown (Whisper/Invite/
            -- Copy Character Name, automatically enabled or greyed out
            -- based on current group membership) via the same SetItemRef
            -- path item/quest links already use below, instead of building
            -- a separate menu for it. The colon lives inside the link's
            -- display text (not appended after) so it stays part of the
            -- same clickable token rather than becoming its own stray word.
            local speakerText = linkName
                and ("|cff" .. nameColor .. "|Hplayer:" .. linkName .. "|h" .. speaker .. ":|h|r")
                or ("|cff" .. nameColor .. speaker .. ":|r")
            local timeColor = message.bookmarked and "ffe066" or "808080"
            local timePrefix = "|cff" .. timeColor .. "[" .. date("%H:%M:%S", message.timestamp or 0) .. "]|r "
            -- SetItemRef/GameTooltip:SetHyperlink both want just the inner
            -- payload (e.g. "quest:2937:60"), not the |H...|h markup around
            -- it. Passing the raw wrapped form is why quest links didn't
            -- open the quest tooltip even though item links mostly worked.
            local processedText = replaceIconExpressions(colorizeQuestLinks(synthesizeQuestieLinks(message.text)))
            local fullText = timePrefix .. speakerText .. " " .. processedText
            -- A message can contain several item/quest links. One
            -- FontString/Button per whole line only ever exposed the FIRST
            -- link it found, so hovering anywhere reacted to that one link
            -- regardless of which item the cursor was actually over. Break
            -- the line into word/link tokens and lay them out by hand
            -- (word-wrapping like real text) so every link gets its own
            -- precise hover/click hit-box.
            local tokens = tokenizeMessage(fullText)
            local lineHeight = fontHeight + 4
            local spaceWidth = math.max(4, math.floor(fontHeight * 0.3))
            -- Reserves room for the bookmark star sitting to the left of
            -- the timestamp (see messageStartY/bookmarkIcon above) - text
            -- (including wrapped continuation lines) starts past it
            -- instead of running underneath.
            local textIndent = 18
            local availableWidth = width - 16 - textIndent
            local x, first = 0, true
            for _, token in ipairs(tokens) do
                local widget, tokenWidth
                if token.kind == "link" then
                    widget = poolLinkToken(content)
                    widget.text:SetText(token.text)
                    widget.link = token.link
                    if widget.text.SetFont then widget.text:SetFont(CHAT_FONT_PATH, fontHeight, CHAT_FONT_FLAGS) end
                    tokenWidth = widget.text:GetStringWidth() or 10
                else
                    widget = poolWordToken(content)
                    widget:SetText(token.text)
                    widget:SetTextColor(0.92, 0.92, 0.92)
                    if widget.SetFont then widget:SetFont(CHAT_FONT_PATH, fontHeight, CHAT_FONT_FLAGS) end
                    tokenWidth = widget:GetStringWidth() or 10
                end
                if not first and x + spaceWidth + tokenWidth > availableWidth then
                    x = 0
                    y = y - lineHeight
                    first = true
                end
                if not first then x = x + spaceWidth end
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + textIndent + x, y)
                if token.kind == "link" then widget:SetSize(tokenWidth, lineHeight - 4) end
                x = x + tokenWidth
                first = false
            end
            y = y - lineHeight - 4
            if panel.scrollToMessage == message then
                content.jumpHighlight:ClearAllPoints()
                content.jumpHighlight:SetPoint("TOPLEFT", content, "TOPLEFT", 2, messageStartY + 2)
                content.jumpHighlight:SetSize(width - 4, (messageStartY - y) - 2)
                content.jumpHighlight:Show()
            end
        end
    end
    if #conversation.messages == 0 then
        local empty = poolRow(content, createChatLine)
        empty.link = nil
        empty.text:SetText("No saved messages yet. Send a whisper or wait for one.")
        empty.text:SetTextColor(0.62, 0.62, 0.62)
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", 10, -12)
        empty.text:SetWidth(width - 20)
        empty:SetSize(width - 20, 20)
        y = -45
    end
    poolFinish(content)
    finishTokenPools(content)
    content:SetSize(width, math.max(panel.chat:GetHeight(), -y + 8))
    -- GetVerticalScrollRange() reflects the scroll frame's own recalculated
    -- child rect; manually subtracting GetHeight() values could read stale
    -- numbers from before the SetSize above took effect, which is why this
    -- sometimes failed to reach the bottom after sending/receiving a message.
    panel.chat:UpdateScrollChildRect()
    panel.messageYPositions = messageYPositions
    -- Guards every SetVerticalScroll below against re-triggering the
    -- OnVerticalScroll hook in BuildMessagesPanel on its own resulting
    -- scroll change - without this, a programmatic scroll near the top or
    -- bottom could re-fire the load-more/pill-dismiss logic right back.
    local function setScroll(offset)
        panel.chatSyncingScroll = true
        panel.chat:SetVerticalScroll(offset)
        panel.chatSyncingScroll = false
    end
    -- Shared by every branch that doesn't explicitly clear the counter -
    -- a load-more (scrolling up for older history) shouldn't silently
    -- dismiss a pill that was already up for genuinely unseen new messages
    -- further down.
    local function refreshPill()
        if not panel.newMessagesPill then return end
        if (panel.newMessagesWhileScrolled or 0) <= 0 then
            panel.newMessagesPill:Hide()
            return
        end
        -- No arrow glyph in the label - the button font (GameFont*) doesn't
        -- have U+2193 and rendered it as a missing-glyph box.
        panel.newMessagesPill:SetText(panel.newMessagesWhileScrolled == 1
            and "1 new message - click to jump" or (panel.newMessagesWhileScrolled .. " new messages - click to jump"))
        fitButton(panel.newMessagesPill, 16)
        panel.newMessagesPill:Show()
    end
    if scrollToY then
        -- Roughly centers the target message in the visible area instead
        -- of pinning it to the very top edge, clamped to the actual
        -- scrollable range.
        local offset = math.max(0, math.min(panel.chat:GetVerticalScrollRange(), -scrollToY - panel.chat:GetHeight() / 2))
        setScroll(offset)
        panel.newMessagesWhileScrolled = 0
        refreshPill()
    elseif anchorMessage and messageYPositions[anchorMessage] then
        -- Older messages were just inserted above what was visible - keep
        -- that same message in view instead of the log jumping around.
        local offset = math.max(0, math.min(panel.chat:GetVerticalScrollRange(), -messageYPositions[anchorMessage]))
        setScroll(offset)
        refreshPill()
    elseif not sameConversationAsLastRender then
        setScroll(panel.chat:GetVerticalScrollRange())
        panel.newMessagesWhileScrolled = 0
        refreshPill()
    elseif sameMessageCountAsLastRender then
        setScroll(math.min(previousScroll, panel.chat:GetVerticalScrollRange()))
        refreshPill()
    elseif wasNearBottom then
        -- New message(s) arrived while already following the bottom of the
        -- log - keep following.
        setScroll(panel.chat:GetVerticalScrollRange())
        panel.newMessagesWhileScrolled = 0
        refreshPill()
    else
        -- New message(s) arrived while scrolled up reading history - stay
        -- put instead of yanking the view down, and surface the pill.
        setScroll(math.min(previousScroll, panel.chat:GetVerticalScrollRange()))
        local newCount = #conversation.messages - (panel.lastRenderCount or #conversation.messages)
        panel.newMessagesWhileScrolled = (panel.newMessagesWhileScrolled or 0) + math.max(0, newCount)
        refreshPill()
    end
    -- One-shot - only the refresh right after a Jump click or a load-more
    -- scroll should act here, not every subsequent refresh (a new incoming
    -- message, etc.) while that conversation happens to stay open.
    panel.scrollToMessage = nil
    panel.chatLoadingMore = nil
    panel.lastRenderKey = self.ui.selectedKey
    panel.lastRenderCount = #(conversation.messages or {})
end

-- Watchlist/Pin/Delete/Copy Name/Export Chat used to be a row of buttons
-- above every open chat - built here as a small themed popup instead of
-- Blizzard's UIDropDownMenu template, which (like the checkboxes/scrollbar
-- arrows reworked earlier this session) is awkward to reskin across the
-- three flat themes. Reused for both the conversation-list row right-click
-- and the open chat's contact-name right-click.
function SW:ShowContextMenu(items, anchorFrame)
    if not self.ui.contextMenu then
        -- Spans the whole screen, one strata below the menu itself, so any
        -- click outside the menu's own rows closes it - the menu frame
        -- (mouse-enabled, on top) swallows clicks landing on itself first.
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        catcher:Hide()
        local menu = CreateFrame("Frame", nil, UIParent, BACKDROP)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        -- A plain flat box, not full button widgets per row (that looked
        -- like a stack of separate buttons rather than one menu) - same
        -- style as the player-name suggestion dropdown in edit() above,
        -- which has the same "small popup list" shape.
        menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        menu:SetBackdropColor(0, 0, 0, 0.95)
        menu:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        menu:Hide()
        catcher:SetScript("OnClick", function() menu:Hide(); catcher:Hide() end)
        menu.catcher = catcher
        menu.rows = {}
        self.ui.contextMenu = menu
    end
    local menu = self.ui.contextMenu
    local rowHeight, padding = 20, 4
    local width = 60
    -- Measured up front so every row shares one width instead of each
    -- being sized to its own label.
    for _, item in ipairs(items) do
        local probe = text(menu, item.label, "GameFontHighlightSmall")
        width = math.max(width, probe:GetStringWidth() + 20)
        probe:Hide()
    end
    for i, item in ipairs(items) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            -- Same theme-aware hover treatment as the conversation list
            -- rows and the suggestion dropdown - gold gradient only on the
            -- classic theme, a flat accent tint on the others.
            local rowTheme = currentTheme()
            if rowTheme.useNativeWidgets then
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            else
                local a = rowTheme.accentColor
                row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
                local hover = row:GetHighlightTexture()
                if hover then hover:SetVertexColor(a[1], a[2], a[3], 0.14) end
            end
            row.label = text(row, "", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 8, 0)
            menu.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", padding, -padding - (i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -padding, -padding - (i - 1) * rowHeight)
        row:SetHeight(rowHeight)
        row.label:SetText(item.label)
        row:SetScript("OnClick", function()
            menu:Hide()
            menu.catcher:Hide()
            item.onClick()
        end)
        row:Show()
    end
    for i = #items + 1, #menu.rows do
        menu.rows[i]:Hide()
    end
    menu:SetSize(width + padding * 2, padding * 2 + #items * rowHeight)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    menu.catcher:Show()
    menu:Show()
end

-- Whether name (a "Name" or "Name-Realm" string) is already in the
-- player's current party/raid - checked against the live roster (party1..N/
-- raid1..N) rather than UnitInParty/UnitInRaid, which want a unit token
-- and don't reliably resolve from a bare name string.
local function isInMyGroup(name)
    local base = string.match(name, "^([^%-]+)") or name
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            if UnitName("raid" .. i) == base then return true end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1 do
            if UnitName("party" .. i) == base then return true end
        end
    end
    return false
end

-- Invite is only offered for someone who isn't already grouped with you.
-- Raid rosters include yourself as one of the numbered units (party
-- rosters don't), so isInMyGroup(ownName) only reliably catches "that's
-- me" while in a raid - check the name directly too so a party doesn't
-- offer to invite yourself.
local function canInvite(name)
    local ownName = UnitName and UnitName("player")
    local isSelf = ownName and string.match(name, "^([^%-]+)") == ownName
    return not isSelf and not isInMyGroup(name)
end

local function inviteItem(name)
    return {
        label = "Invite",
        onClick = function()
            if InviteUnit then InviteUnit(name)
            elseif C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) end
        end,
    }
end

-- The subset of actions that make sense for this conversation's type -
-- Guild Chat is always a single fixed conversation (no Watchlist/Pin/
-- Delete), Party/Raid/Channel are sessions you can delete but not pin or
-- rename, and only a real DM has a player name worth copying, starring, or
-- inviting.
function SW:ContextMenuItemsFor(conversation)
    local items = {}
    if not conversation.system then
        items[#items + 1] = {
            label = conversation.favorite and "Remove from Watchlist" or "Add to Watchlist",
            onClick = function() SW:ToggleFavorite(conversation.key) end,
        }
        items[#items + 1] = {
            label = conversation.pinned and "Unpin" or "Pin to Top",
            onClick = function()
                local ok, err = SW:TogglePinned(conversation.key)
                if not ok then SW:Print(err) end
            end,
        }
        items[#items + 1] = {
            label = "Copy Name",
            onClick = function() SW:ShowCopyPopup("Copy Name", conversation.name) end,
        }
        if canInvite(conversation.name) then
            items[#items + 1] = inviteItem(conversation.name)
        end
    end
    items[#items + 1] = {
        label = "Export Chat",
        onClick = function()
            local lines = {}
            for _, message in ipairs(conversation.messages or {}) do
                local speaker = message.outgoing and "You" or (message.sender or conversation.name)
                lines[#lines + 1] = "[" .. date("%Y-%m-%d %H:%M:%S", message.timestamp or 0) .. "] " .. speaker .. ": " .. plainText(message.text)
            end
            SW:ShowCopyPopup("Export - " .. conversation.name, table.concat(lines, "\n"))
        end,
    }
    if not conversation.system then
        items[#items + 1] = { label = "Delete DM", onClick = function() SW:DeleteConversation(conversation.key) end }
    elseif conversation.channel == "channel" then
        items[#items + 1] = { label = "Remove", onClick = function() SW:DeleteConversation(conversation.key) end }
    elseif conversation.channel == "party" or conversation.channel == "raid" then
        items[#items + 1] = { label = "Delete Session", onClick = function() SW:DeleteConversation(conversation.key) end }
    end
    return items
end

-- Right-click on a sender name in the chat log (see createChatLine) - a
-- lighter menu than ContextMenuItemsFor since a name isn't a conversation:
-- just Copy Name (same ShowCopyPopup every other Copy Name/Export Chat
-- action already uses - CopyToClipboard is a protected function addons
-- can't call, confirmed by testing, not just a theoretical restriction)
-- and Invite, shown only when they aren't already in the group.
function SW:ShowNameContextMenu(name, anchorFrame)
    local items = {
        { label = "Copy Name", onClick = function() SW:ShowCopyPopup("Copy Name", name) end },
    }
    if canInvite(name) then items[#items + 1] = inviteItem(name) end
    self:ShowContextMenu(items, anchorFrame)
end

-- WoW addons can't touch the OS clipboard directly. The standard workaround
-- (used by WeakAuras export strings etc.) is a focused, fully-selected edit
-- box the player copies out themselves with Ctrl+C.
function SW:ShowCopyPopup(title, content)
    if not self.ui.copyFrame then
        local frame = CreateFrame("Frame", "SaveWhispersCopyFrame", UIParent, BACKDROP)
        -- Same reasoning as the main window - without this, Escape either
        -- does nothing (if the main window is hidden behind this popup) or
        -- closes the main window instead of this one on top of it.
        tinsert(UISpecialFrames, "SaveWhispersCopyFrame")
        frame:SetSize(520, 420)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        -- Above DIALOG (same strata as the main window) so it reliably
        -- shows in front instead of possibly landing behind it.
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        applyWindowBackdrop(frame)
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        frame.title = text(frame, "", "GameFontNormalLarge")
        frame.title:SetPoint("TOPLEFT", 18, -16)
        frame.close = closeButton(frame)
        frame.close:SetPoint("TOPRIGHT", -4, -5)
        frame.close:SetScript("OnClick", function() frame:Hide() end)
        frame.hint = text(frame, "Ctrl+C to copy, then close this window.", "GameFontDisableSmall")
        frame.hint:SetPoint("TOPLEFT", 18, -42)
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 16, -64)
        scrollFrame:SetPoint("BOTTOMRIGHT", -32, 16)
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetAutoFocus(true)
        editBox:SetWidth(450)
        editBox:SetHeight(2000)
        editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        frame.editBox = editBox
        self.ui.copyFrame = frame
    end
    local frame = self.ui.copyFrame
    frame.title:SetText(title)
    frame.editBox:SetText(content)
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
    -- A single name doesn't need the full export-sized window, and a short
    -- multi-line list (Copy names on a 6-person party) doesn't need the
    -- same size (width AND height) as a 1000-line Export chat either -
    -- scale with the actual content instead of one fixed "multi-line"
    -- size, capped at the old fixed size for anything long.
    local lineCount, longestLine = 1, 0
    for line in string.gmatch(content .. "\n", "(.-)\n") do
        lineCount = lineCount + 1
        longestLine = math.max(longestLine, #line)
    end
    if lineCount <= 1 then
        frame:SetSize(420, 130)
    else
        local width = math.min(560, math.max(300, 80 + longestLine * 7))
        local height = math.min(440, math.max(160, 100 + math.min(lineCount, 20) * 16))
        frame:SetSize(width, height)
    end
    -- Same FULLSCREEN_DIALOG strata as the Members popup this can be
    -- opened from ("Copy Names") - Raise() alone didn't reliably win
    -- against it, so this pins an explicit, always-higher frame level
    -- instead of relying on raise-ordering.
    local membersFrame = self.ui.membersFrame
    frame:SetFrameLevel((membersFrame and membersFrame:IsShown() and membersFrame:GetFrameLevel() or 0) + 10)
    frame:Show()
end

-- Width is fixed (narrower than the old 360 - rows are just names now that
-- online/offline status was dropped, they never needed that much room).
-- Height is NOT fixed here - ShowMembers resizes the frame every time it's
-- opened, to fit however many members there actually are (capped, beyond
-- which the scroll frame already inside takes over).
local MEMBERS_FRAME_WIDTH = 300
function SW:CreateMembersFrame()
    if self.ui.membersFrame then return self.ui.membersFrame end
    local frame = CreateFrame("Frame", "SaveWhispersMembersFrame", UIParent, BACKDROP)
    -- Same reasoning as the main window - see SaveWhispersCopyFrame above.
    tinsert(UISpecialFrames, "SaveWhispersMembersFrame")
    frame:SetSize(MEMBERS_FRAME_WIDTH, 300)
    frame:SetPoint("CENTER", UIParent, "CENTER", 260, 10)
    -- Above DIALOG (same strata as the main window) so it reliably shows in
    -- front instead of possibly landing behind it, same issue as the copy
    -- popup had.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    applyWindowBackdrop(frame)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame.title = text(frame, "Chat Members", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 18, -16)
    frame.close = closeButton(frame)
    frame.close:SetPoint("TOPRIGHT", -4, -5)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    -- WoW addons can't write to the OS clipboard directly - same pattern as
    -- "Copy Name"/"Export Chat" elsewhere, a popup with pre-selected text.
    frame.copyNames = fitButton(button(frame, "Copy Names", 10, 22))
    frame.copyNames:SetPoint("TOPRIGHT", -8, -44)
    frame.copyNames:SetScript("OnClick", function()
        local lines = {}
        for _, name in ipairs(frame.memberNames or {}) do lines[#lines + 1] = name end
        SW:ShowCopyPopup(frame.title:GetText() or "Members", table.concat(lines, "\n"))
    end)
    frame.scroll = scroll(frame)
    frame.scroll:SetPoint("TOPLEFT", 16, -76)
    frame.scroll:SetPoint("BOTTOMRIGHT", -30, 16)
    frame:Hide()
    self.ui.membersFrame = frame
    return frame
end

local function createMemberRow(parent)
    -- A Button, not a plain Frame - clicking a name opens a small Copy
    -- popup with just that one name, a quicker path than "Copy Names"
    -- (which dumps every member at once) when you only want one.
    local row = CreateFrame("Button", nil, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.label = text(row, "", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 8, 0)
    return row
end

-- Dedupe by base name, not the full "Name-Realm" string - the player's own
-- unit (UnitName("player")) never carries a realm suffix, while the same
-- person showing up as a chat message sender usually does, so keying on
-- the full name listed the same person twice. Realm shows as "(Realm)"
-- like everywhere else in the UI, not the raw "-Realm" suffix.
local function addMember(members, names, name, state)
    name = SW:NormalizePlayerName(name)
    if not name then return end
    local base, realm = splitRealm(name)
    local key = string.lower(base)
    local entry = members[key]
    if not entry then
        entry = {
            name = realm and (base .. " (" .. realm .. ")") or base,
            -- Raw "Name-Realm" form (no parens/space) for Copy names - the
            -- display format reads better on screen, but it's not what a
            -- whisper/invite command actually accepts if you paste it.
            rawName = realm and (base .. "-" .. realm) or base,
            sortName = base,
            hasRealm = realm ~= nil,
            state = state or "Offline",
        }
        members[key] = entry
        names[#names + 1] = entry
    elseif realm and not entry.hasRealm then
        -- Upgrade a bare name seen first to the realm-qualified display
        -- once a mention with the realm turns up, instead of duplicating.
        entry.name = base .. " (" .. realm .. ")"
        entry.rawName = base .. "-" .. realm
        entry.hasRealm = true
    end
end

function SW:ShowMembers(conversation)
    if not conversation or not conversation.system then return end
    local frame = self:CreateMembersFrame()
    local members, names = {}, {}
    -- Guild Chat's roster is always the player's actual current guild, so a
    -- live online/offline check means something. A Party/Raid session's
    -- member list is a roster captured back when that group existed - for
    -- an old/closed session, querying the player's CURRENT group units
    -- would show whoever they happen to be grouped with today (or nobody),
    -- not the people who were actually in that session. Online/offline
    -- doesn't mean anything for that, so this just lists the names.
    local showState = conversation.channel == "guild"
    if conversation.channel == "guild" then
        if GuildRoster then GuildRoster() end
        local count = GetNumGuildMembers and GetNumGuildMembers() or 0
        for index = 1, count do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
            addMember(members, names, name, online and "Online" or "Offline")
        end
    end
    if conversation.channel == "party" or conversation.channel == "raid" then
        for _, name in ipairs(conversation.members or {}) do
            addMember(members, names, name, nil)
        end
    end
    for _, message in ipairs(conversation.messages or {}) do addMember(members, names, message.sender, nil) end
    table.sort(names, function(a, b) return string.lower(a.sortName) < string.lower(b.sortName) end)
    -- Session conversations are named e.g. "Party Chat - 14.07.2026 15:52";
    -- appending " Members (11)" to the full thing overflowed this narrow
    -- window. Drop the " - <date>" part, the title bar doesn't need it.
    local shortName = string.match(conversation.name, "^(.-) %- .+$") or conversation.name
    frame.title:SetText(shortName .. " Members (" .. #names .. ")")
    frame.memberNames = {}
    for _, member in ipairs(names) do frame.memberNames[#frame.memberNames + 1] = member.rawName or member.name end
    -- Grows/shrinks with the member count instead of a fixed size - a
    -- 3-person party session no longer wastes most of the window on empty
    -- space, and a 40-person raid still gets capped at a sane height with
    -- the scroll frame (already there regardless) taking over past that.
    local ROW_H = 32
    local MAX_VISIBLE_ROWS = 20
    local visibleRows = math.max(1, math.min(#names, MAX_VISIBLE_ROWS))
    setPixelSize(frame, MEMBERS_FRAME_WIDTH, 76 + visibleRows * ROW_H + 20)
    local content = frame.scroll.content
    content.emptyLabel = content.emptyLabel or text(content, "", "GameFontDisableSmall")
    poolStart(content)
    local width = math.max(250, frame.scroll:GetWidth() - 4)
    local y = 0
    if #names == 0 then
        content.emptyLabel:SetText("No members have been seen yet.")
        content.emptyLabel:ClearAllPoints()
        content.emptyLabel:SetPoint("TOPLEFT", 8, -8)
        content.emptyLabel:Show()
        y = -30
    else
        content.emptyLabel:Hide()
    end
    for _, member in ipairs(names) do
        local row = poolRow(content, createMemberRow)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:SetSize(width, 28)
        if showState then
            local stateColor = member.state == "Online" and { 0.20, 0.80, 0.38 } or (member.state == "Busy" and { 0.95, 0.75, 0.18 } or { 0.58, 0.60, 0.65 })
            row.label:SetText(member.name .. "  (" .. member.state .. ")")
            row.label:SetTextColor(unpack(stateColor))
        else
            -- Rows are pooled/reused - explicitly reset the color instead
            -- of leaving whatever a previous (Guild) popup left behind.
            row.label:SetText(member.name)
            row.label:SetTextColor(0.9, 0.9, 0.9)
        end
        row:SetScript("OnClick", function()
            SW:ShowCopyPopup("Copy Name", member.rawName or member.name)
        end)
        y = y - 32
    end
    poolFinish(content)
    content:SetSize(width, math.max(frame.scroll:GetHeight(), -y + 4))
    frame:Show()
end

function SW:BuildWatchlistPanel()
    local panel = self:NewPanel("Watchlist")
    -- Same inset content box the Messages tab's two columns sit in - the
    -- other tabs floating their content directly on the window background
    -- made the UI read as inconsistent next to it. Everything is parented
    -- to the box (not the panel) so the box's backdrop renders underneath.
    panel.box = inset(panel)
    panel.box:SetAllPoints()
    local icon = panel.box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
    local heading = text(panel.box, "Watchlist", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 6, 1)
    local hint = text(panel.box, "Mark important players. Starred conversations are never removed automatically.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -39)
    panel.addName = edit(panel.box, 250, 22, "Enter player name", function(value) return SW:GetNameSuggestions(value) end)
    panel.addName:SetPoint("TOPLEFT", 12, -68)
    panel.addButton = button(panel.box, "Add Player", 96, 24)
    panel.addButton:SetPoint("LEFT", panel.addName, "RIGHT", 8, 0)
    panel.addButton:SetScript("OnClick", function()
        local ok, err = SW:AddToWatchlist(fieldValue(panel.addName))
        if ok then panel.addName:SetText(panel.addName.hint) else SW:Print(err) end
    end)
    panel.list = scroll(panel.box)
    panel.list:SetPoint("TOPLEFT", 12, -112)
    panel.list:SetPoint("BOTTOMRIGHT", -28, 10)
end

-- Matches the icon-button style used in the chat header instead of the
-- older plain "*"/"X" text buttons.
local function createWatchlistRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.favoriteIcon = row:CreateTexture(nil, "ARTWORK")
    row.favoriteIcon:SetSize(13, 13)
    row.favoriteIcon:SetPoint("LEFT", 12, 0)
    row.favoriteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    row.label = text(row, "", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.favoriteIcon, "RIGHT", 6, 0)
    row.realm = text(row, "", "GameFontDisableSmall")
    row.realm:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
    row.delete = iconButton(row, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", "Delete DM")
    row.delete:SetPoint("RIGHT", -12, 0)
    row.remove = iconButton(row, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", "Remove from watchlist")
    row.remove:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.open = fitButton(button(row, "Open Chat", 10, 22))
    row.open:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    return row
end

function SW:RefreshWatchlistPanel()
    local panel = self.ui.panels.Watchlist
    local list = self:GetSortedConversations(true)
    local content = panel.list.content
    content.emptyLabel = content.emptyLabel or text(content, "", "GameFontDisableSmall")
    poolStart(content)
    local width = math.max(450, panel.list:GetWidth() - 4)
    local y = 0
    if #list == 0 then
        content.emptyLabel:SetText("Your watchlist is empty.")
        content.emptyLabel:ClearAllPoints()
        content.emptyLabel:SetPoint("TOPLEFT", 8, -8)
        content.emptyLabel:Show()
        y = -32
    else
        content.emptyLabel:Hide()
    end
    for _, conversation in ipairs(list) do
        local row = poolRow(content, createWatchlistRow)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y); row:SetSize(width, 42)
        local base, realm = splitRealm(conversation.name)
        row.label:SetText(base)
        row.realm:SetText(realm and ("(" .. realm .. ")") or "")
        -- listFilter reset to "all" for the same reason as the Bookmarks/
        -- global-search Jump buttons - a Watchlist entry can be excluded
        -- by whatever filter pill happened to be active on the Messages
        -- tab, silently overriding this selection right back.
        row.open:SetScript("OnClick", function() SW.ui.selectedKey = conversation.key; conversation.unread = 0; SW.ui.listFilter = "all"; SW:SwitchTab("Messages") end)
        row.remove:SetScript("OnClick", function() SW:ToggleFavorite(conversation.key) end)
        row.delete:SetScript("OnClick", function() SW:DeleteConversation(conversation.key) end)
        y = y - 48
    end
    poolFinish(content)
    content:SetSize(width, math.max(panel.list:GetHeight(), -y + 5))
end

function SW:BuildBookmarksPanel()
    local panel = self:NewPanel("Bookmarks")
    -- Same inset content box as the other tabs - see BuildWatchlistPanel.
    panel.box = inset(panel)
    panel.box:SetAllPoints()
    local icon = panel.box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    local heading = text(panel.box, "Bookmarks", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 6, 1)
    local hint = text(panel.box, "Every message you've starred, across every conversation.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -39)
    panel.list = scroll(panel.box)
    panel.list:SetPoint("TOPLEFT", 12, -68)
    panel.list:SetPoint("BOTTOMRIGHT", -28, 10)
end

-- Same flat row-per-message shape as global search results
-- (RenderGlobalSearchResults/populateMessageResultRow/poolResultRow) - a
-- bookmark is conceptually just a standing, saved search.
function SW:RefreshBookmarksPanel()
    local panel = self.ui.panels.Bookmarks
    local results = self:GetBookmarkedMessages()
    local content = panel.list.content
    content.emptyLabel = content.emptyLabel or text(content, "", "GameFontDisableSmall")
    content.resultPool = content.resultPool or { items = {}, count = 0 }
    content.resultPool.count = 0
    local width = math.max(450, panel.list:GetWidth() - 4)
    local y = 0
    if #results == 0 then
        content.emptyLabel:SetText("No bookmarked messages yet - click the star next to any message to bookmark it.")
        content.emptyLabel:ClearAllPoints()
        content.emptyLabel:SetPoint("TOPLEFT", 8, -8)
        content.emptyLabel:Show()
        y = -32
    else
        content.emptyLabel:Hide()
        for _, entry in ipairs(results) do
            local conversation, message = entry.conversation, entry.message
            local row = poolResultRow(content)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(width, 44)
            populateMessageResultRow(row, conversation, message, function()
                local messagesPanel = SW.ui.panels.Messages
                if messagesPanel then
                    messagesPanel.scrollToMessage = message
                    messagesPanel.searchAllChats = false
                    if messagesPanel.chatSearchAll then messagesPanel.chatSearchAll:SetChecked(false) end
                    messagesPanel.chatSearchText = nil
                    if messagesPanel.chatSearch then
                        messagesPanel.chatSearch:ClearFocus()
                        messagesPanel.chatSearch:SetText(messagesPanel.chatSearch.hint or "")
                    end
                end
                SW.ui.selectedKey = conversation.key
                -- Same fix as the global-search Jump button - a bookmarked
                -- message can be from any conversation type, and an active
                -- list filter (e.g. "DM") excluding that type let
                -- RefreshMessagesPanel's "keep selection valid" check
                -- silently override the jump target right back.
                SW.ui.listFilter = "all"
                SW:SwitchTab("Messages")
            end)
            y = y - 48
        end
    end
    for i = content.resultPool.count + 1, #content.resultPool.items do content.resultPool.items[i]:Hide() end
    content:SetSize(width, math.max(panel.list:GetHeight(), -y + 5))
end

-- Native Blizzard confirmation popups for the Settings "Danger Zone" -
-- fits the rest of the addon's Blizzard-native look far better than a
-- custom-built popup, and is the idiomatic way to gate a destructive,
-- irreversible action in WoW addons.
StaticPopupDialogs["SAVEWHISPERS_CONFIRM_DELETE_ALL"] = {
    text = "Delete ALL SaveWhispers history? This removes every DM, the Guild Chat history, every Party/Raid session and every added channel. This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function() SW:DeleteAllChats() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
StaticPopupDialogs["SAVEWHISPERS_CONFIRM_DELETE_DMS"] = {
    text = "Delete all DM conversations? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function() SW:DeleteAllDMs() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
StaticPopupDialogs["SAVEWHISPERS_CONFIRM_DELETE_GUILD"] = {
    text = "Delete Guild Chat history? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function() SW:DeleteGuildHistory() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
StaticPopupDialogs["SAVEWHISPERS_CONFIRM_DELETE_GROUP"] = {
    text = "Delete all Party/Raid chat sessions? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function() SW:DeleteAllGroupSessions() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Theme-independent "value saved" flash for a Settings field -
-- InputBoxTemplate's (classic theme) border is texture art with no
-- recolorable backdrop, so this uses its own overlay frame rather than
-- trying to recolor the field's own border. No fade - shows/hides
-- instantly, matching that nothing else in this addon animates.
-- anchorWidget lets a caller put the "Saved" text somewhere other than
-- directly right of the field itself - the message-limit rows also have a
-- "No limit" checkbox+label sitting right there, and the text used to land
-- on top of/behind them. Pass anchorWidget = false to skip the text
-- entirely and flash only the border - some rows (the two-per-row count
-- fields) have no free space on any side: a sibling field's caption sits
-- immediately right with no gap, and directly below is the next row.
local function flashSaved(field, anchorWidget)
    if not field.savedText then
        field.savedText = text(field:GetParent(), "Saved", "GameFontDisableSmall", 0.35, 0.85, 0.35)
        field.savedText:Hide()
        field.savedBorder = CreateFrame("Frame", nil, field:GetParent(), BACKDROP)
        field.savedBorder:SetPoint("TOPLEFT", field, "TOPLEFT", -3, 3)
        field.savedBorder:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 3, -3)
        field.savedBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        field.savedBorder:SetBackdropBorderColor(0.35, 0.85, 0.35, 1)
        field.savedBorder:Hide()
    end
    if anchorWidget == false then
        field.savedText:Hide()
    else
        field.savedText:ClearAllPoints()
        field.savedText:SetPoint("LEFT", anchorWidget or field, "RIGHT", 8, 0)
        field.savedText:Show()
    end
    field.savedBorder:Show()
    C_Timer.After(1.5, function()
        if field.savedText then field.savedText:Hide() end
        if field.savedBorder then field.savedBorder:Hide() end
    end)
end

function SW:BuildSettingsPanel()
    local panel = self:NewPanel("Settings")
    -- Same inset content box as the other tabs - see BuildWatchlistPanel.
    panel.box = inset(panel)
    panel.box:SetAllPoints()

    -- Fixed header outside the scroll content, like every other tab (see
    -- BuildWatchlistPanel) - it used to live inside the scrolled area,
    -- which put its icon out of alignment with Watchlist/Bookmarks/
    -- Changelog's headers and made it scroll out of view with everything
    -- else instead of staying put.
    local icon = panel.box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
    local heading = text(panel.box, "Settings", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 6, 1)

    panel.scroll = scroll(panel.box)
    -- The scrollbar renders to the right of the scroll frame's own edge, not
    -- inside it - SetAllPoints() let it hang off the box's right border.
    panel.scroll:SetPoint("TOPLEFT", 8, -44)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    local content = panel.scroll.content
    panel.content = content

    -- Every section below anchors its Y to the bottom of the previous
    -- widget, so inserting or resizing one row can never again silently
    -- overlap the ones below it (see the "Limits" overlap bug from earlier
    -- this session). X is anchored separately, always relative to `content`
    -- (a fixed reference) rather than to `prev` - anchoring X to prev too
    -- was the actual bug that shipped: every small per-widget nudge (e.g.
    -- the -2 used throughout for optical alignment) compounded across the
    -- whole chain since each widget's already-drifted X became the next
    -- one's reference, and rows whose `prev` became a widget positioned far
    -- to the right (a field/checkbox anchored right of its own caption)
    -- dragged every following section rightward with it. Two independent
    -- SetPoint calls - one constrains Y only, the other X only - is the
    -- standard WoW pattern for this and keeps the two fully decoupled.
    -- `content` sits flush against the scroll frame's own clip edge with no
    -- inherent padding - several call sites below use a small negative x
    -- (e.g. -6 for "Danger Zone") as a purely relative optical nudge, which
    -- used to be safe when x was measured from a widget with its own
    -- margin. Anchored straight to content's edge, those went negative
    -- enough to visibly clip the first letter. A fixed left margin absorbs
    -- that instead of having to rework every call site's nudge value.
    local MARGIN = 10
    -- Number fields ("DM conversations to keep" etc.) only ever hold 3-4
    -- digit values - the old 60px width with left-justified text left a lot
    -- of dead space in front of short numbers and looked odd.
    local FIELD_WIDTH = 40
    -- Measures a caption's actual rendered width instead of guessing a
    -- pixel value by eye - guessed offsets either left a visible gap (too
    -- generous) or, tuned per-row instead of per-column, left same-column
    -- fields at different X on different rows (a caption-length-dependent
    -- offset makes a short caption's field sit further left than a long
    -- caption's field right below it).
    local function labelWidth(str)
        local probe = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        probe:SetText(str)
        local w = probe:GetStringWidth() or 100
        probe:Hide()
        return w
    end
    local topAnchor = CreateFrame("Frame", nil, content)
    topAnchor:SetSize(1, 1)
    topAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local prev = topAnchor
    local function belowPrev(widget, x, gap)
        widget:ClearAllPoints()
        widget:SetPoint("TOP", prev, "BOTTOM", 0, -(gap or 10))
        widget:SetPoint("LEFT", content, "LEFT", MARGIN + (x or 0), 0)
        prev = widget
        return widget
    end

    -- General: three checkboxes in one row instead of stacked - each
    -- anchors off the previous one's own label (not a fixed pixel step),
    -- since the three labels are different lengths.
    local generalHeading = text(content, "General", "GameFontNormal")
    belowPrev(generalHeading, 0, 6)
    local function addInlineCheckbox(label, setting, anchorTo)
        local box = checkButton(content)
        if anchorTo then
            box:SetPoint("LEFT", anchorTo.label, "RIGHT", 26, 0)
            box:SetPoint("TOP", anchorTo, "TOP", 0, 0)
        else
            box:SetPoint("TOP", generalHeading, "BOTTOM", 0, -10)
            box:SetPoint("LEFT", content, "LEFT", MARGIN, 0)
        end
        box.label = text(content, label, "GameFontHighlightSmall")
        box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box:SetScript("OnClick", function(self) SW:SetSetting(setting, self:GetChecked() and true or false) end)
        return box
    end
    panel.enabled = addInlineCheckbox("Enable SaveWhispers", "enabled")
    panel.minimap = addInlineCheckbox("Show minimap button", "showMinimap", panel.enabled)
    panel.sortByActivity = addInlineCheckbox("Sort by recent activity", "sortByActivity", panel.minimap)
    -- The full explanation used to run inline as part of the checkbox
    -- label, which was the widest thing in the row by far - a tooltip
    -- keeps the row compact without losing the explanation.
    panel.sortByActivity:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Unchecked: alphabetical order instead.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.sortByActivity:SetScript("OnLeave", function() GameTooltip:Hide() end)
    prev = panel.enabled

    -- Two columns sharing the same top edge: Minimap Badge Counts (left)
    -- and Display Scale (right). Each column tracks its own bottom via its
    -- own `place` closure so one column's height never affects the other's
    -- layout; a zero-size spacer below whichever column is actually taller
    -- becomes the anchor for everything that follows.
    local columnTop = prev
    -- Tight enough to clear the left column's widest row (the "Guild"
    -- badge checkbox+label) while leaving the whole layout narrower than
    -- the window's default width - 380 ran past the visible scroll area at
    -- the window's normal (not manually widened) size.
    local COLUMN_X = 300
    local function makeColumn(x)
        local col = { prev = columnTop }
        function col.place(widget, gap)
            widget:ClearAllPoints()
            widget:SetPoint("TOP", col.prev, "BOTTOM", 0, -(gap or 10))
            widget:SetPoint("LEFT", content, "LEFT", MARGIN + x, 0)
            col.prev = widget
            return widget
        end
        return col
    end
    local leftCol = makeColumn(0)
    local rightCol = makeColumn(COLUMN_X)

    -- Left column: minimap badge category toggles.
    local badgeHeading = text(content, "Minimap Badge Counts", "GameFontNormal")
    leftCol.place(badgeHeading, 20)
    local badgeHint = text(content, "Which categories add to the unread-count badge.", "GameFontDisableSmall")
    leftCol.place(badgeHint, 4)
    panel.badgeChecks = {}
    local function addBadgeCheckbox(label, setting, anchorTo, xOffset)
        local box = checkButton(content)
        if anchorTo then
            box:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", xOffset, 0)
        else
            leftCol.place(box, 10)
        end
        box.label = text(content, label, "GameFontHighlightSmall")
        box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box:SetScript("OnClick", function(self) SW:SetSetting(setting, self:GetChecked() and true or false) end)
        panel.badgeChecks[#panel.badgeChecks + 1] = { box = box, setting = setting }
        return box
    end
    local badgeDM = addBadgeCheckbox("DMs", "badgeCountsDM")
    addBadgeCheckbox("Guild", "badgeCountsGuild", badgeDM, 110)
    local badgeGroup = addBadgeCheckbox("Group", "badgeCountsGroup")
    addBadgeCheckbox("Channels", "badgeCountsChannel", badgeGroup, 110)

    -- Right column: the two scale sliders, now under their own heading -
    -- they used to just trail after Messages to Keep with nothing labeling
    -- them as a section.
    local scaleHeading = text(content, "Display Scale", "GameFontNormal")
    rightCol.place(scaleHeading, 20)
    local scaleHint = text(content, "Adjust the window and chat text size.", "GameFontDisableSmall")
    rightCol.place(scaleHint, 4)

    panel.sliders = {}
    local function addSlider(id, setting, channel, label, minimum, maximum, step, place)
        place = place or belowPrev
        local slider = CreateFrame("Slider", "SaveWhispers" .. id, content, "OptionsSliderTemplate")
        -- 26, not the checkbox column's 10 - the slider's own label sits
        -- above the slider itself and needs the extra headroom, but 40 left
        -- a visibly bigger gap under this column's hint text than the left
        -- column's checkboxes get under theirs.
        place(slider, 26)
        slider:SetWidth(250); slider:SetHeight(18)
        slider:SetMinMaxValues(minimum or 0, maximum or 1); slider:SetValueStep(step or 0.05)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local theme = currentTheme()
        if not theme.useNativeWidgets then
            local thumb = slider:GetThumbTexture()
            if thumb then
                thumb:SetColorTexture(theme.accentColor[1], theme.accentColor[2], theme.accentColor[3], 1)
                thumb:SetSize(14, 18)
            end
        end
        slider.label = text(content, label, "GameFontHighlightSmall")
        slider.label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", -7, 3)
        slider.valueText = text(content, "", "GameFontHighlightSmall")
        slider.valueText:SetPoint("LEFT", slider.label, "RIGHT", 6, 0)
        local function updateValueText(value)
            slider.valueText:SetText(math.floor((value or 0) * 100 + 0.5) .. "%")
        end
        -- Only write the value while dragging - applying it live (uiScale
        -- calls self.ui.frame:SetScale, which changes the effective scale
        -- of the very frame this slider lives in, and NotifyDataChanged's
        -- RefreshSettingsPanel calls SetValue back on this same slider) both
        -- fight the drag's own mouse-to-value tracking while the button is
        -- still down - the frame visibly "sprang" back and forth. Applying
        -- (SetScale/refresh) only happens once, on release.
        slider:SetScript("OnValueChanged", function(self, value)
            updateValueText(value)
            if panel.loading then return end
            if channel then SW.DB.settings[setting][channel] = value else SW.DB.settings[setting] = value end
        end)
        slider:SetScript("OnMouseUp", function(self)
            if panel.loading then return end
            SW:NotifyDataChanged()
        end)
        -- A ruler of small step notches along the track, plus a taller gold
        -- tick at 100% (dead center now that callers pass a symmetric
        -- min/max around 1.0) - purely visual, not interactive, so they
        -- never get in the way of grabbing the thumb itself.
        local trackWidth = 250
        local totalSteps = math.floor(((maximum or 1) - (minimum or 0)) / (step or 0.05) + 0.5)
        for i = 0, totalSteps do
            local notch = slider:CreateTexture(nil, "ARTWORK")
            notch:SetColorTexture(1, 1, 1, 0.3)
            notch:SetSize(1, 6)
            notch:SetPoint("CENTER", slider, "LEFT", trackWidth * (i / totalSteps), -8)
        end
        local tickFraction = (1 - (minimum or 0)) / ((maximum or 1) - (minimum or 0))
        local tick = slider:CreateTexture(nil, "OVERLAY")
        tick:SetColorTexture(1, 0.82, 0, 0.9)
        tick:SetSize(2, 16)
        tick:SetPoint("CENTER", slider, "LEFT", trackWidth * tickFraction, -1)
        -- A real button beside the track instead of a hit-region sitting on
        -- top of it - that made it hard to grab the thumb with the mouse
        -- anywhere near the 100% mark.
        local resetButton = fitButton(button(content, "Reset", 10, 20), 10)
        resetButton:SetPoint("LEFT", slider, "RIGHT", 16, 0)
        resetButton:SetScript("OnClick", function()
            slider:SetValue(1)
            SW:NotifyDataChanged()
        end)
        resetButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Reset to 100%")
            GameTooltip:Show()
        end)
        resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.sliders[#panel.sliders + 1] = { slider = slider, resetButton = resetButton, setting = setting, channel = channel }
    end
    addSlider("UIScale", "uiScale", nil, "Interface scale", 0.70, 1.30, 0.05, rightCol.place)
    addSlider("ChatScale", "chatScale", nil, "Chat text scale", 0.70, 1.30, 0.05, rightCol.place)

    -- Whichever of the two columns ended up taller determines where the
    -- rest of the panel picks back up - a zero-size spacer anchored below
    -- that column's last widget keeps the single-column `belowPrev` chain
    -- below working exactly as before.
    local leftBottom = leftCol.prev:GetBottom() or 0
    local rightBottom = rightCol.prev:GetBottom() or 0
    local columnsEnd = CreateFrame("Frame", nil, content)
    columnsEnd:SetSize(1, 1)
    columnsEnd:SetPoint("TOP", (leftBottom <= rightBottom) and leftCol.prev or rightCol.prev, "BOTTOM", 0, 0)
    columnsEnd:SetPoint("LEFT", content, "LEFT", MARGIN, 0)
    prev = columnsEnd

    -- Conversations & Sessions to Keep (count limits - no "unlimited"
    -- option here, unlike the message caps below: an unbounded number of
    -- conversations directly grows the always-rendered list, a real
    -- performance cost rather than just storage). All three fields share
    -- one row instead of 2-then-1.
    local keepHeading = text(content, "Conversations & Sessions to Keep", "GameFontNormal")
    belowPrev(keepHeading, 0, 20)
    local keepHint = text(content, "The oldest entry is dropped once a limit is reached.", "GameFontDisableSmall")
    belowPrev(keepHint, 0, 4)
    panel.limitFields = {}
    local function addLimitField(label, setting, minimum, default, anchorTo, xOffset)
        local caption = text(content, label, "GameFontHighlightSmall")
        if anchorTo then
            caption:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", xOffset, 0)
        else
            belowPrev(caption, 0, 10)
        end
        local field = numberField(content, FIELD_WIDTH, 20)
        -- Anchored to caption's actual (unfixed) text width, not a fixed
        -- 190px box - a fixed-width caption box left a big gap in front of
        -- every field shorter than "Party/Raid sessions to keep", the
        -- longest label. TOP/LEFT set separately (not a single "LEFT"
        -- point, which centers vertically on the target) - caption's
        -- font-string height is much smaller than the field's, so a center
        -- anchor let the field bleed upward into the row above as well as
        -- downward into the row below.
        field:SetPoint("TOP", caption, "TOP", 0, 3)
        field:SetPoint("LEFT", caption, "RIGHT", 6, 0)
        local function apply()
            local value = tonumber(field:GetText())
            if not value or value < minimum then value = SW.DB.settings[setting] or default end
            value = math.floor(value)
            SW.DB.settings[setting] = value
            field:ClearFocus()
            -- Border flash only, no text - these fields sit three-per-row
            -- with no free space on any side, so any text placement landed
            -- on top of something.
            flashSaved(field, false)
            SW:RefreshSettingsPanel()
        end
        field:SetScript("OnEnterPressed", apply)
        field:SetScript("OnEditFocusLost", apply)
        panel.limitFields[#panel.limitFields + 1] = { field = field, setting = setting, minimum = minimum, default = default }
        -- Only the first field of a row should advance the shared anchor -
        -- a sibling placed via anchorTo shares that same row and must not
        -- push the next section down twice.
        if not anchorTo then prev = field end
        return caption
    end
    -- Column offsets computed from the actual caption widths plus a small
    -- fixed gap, instead of guessed pixel values - guarantees the tightest
    -- gap that still can't overlap regardless of the client's font metrics.
    local keepGap = 16
    local keepCol2 = labelWidth("DM conversations to keep") + 6 + FIELD_WIDTH + keepGap
    local keepCol3 = keepCol2 + labelWidth("Party/Raid sessions to keep") + 6 + FIELD_WIDTH + keepGap
    local dmKeepCaption = addLimitField("DM conversations to keep", "maxConversations", 10, 200)
    addLimitField("Party/Raid sessions to keep", "maxGroupSessions", 10, 200, dmKeepCaption, keepCol2)
    addLimitField("Channels to keep", "maxChannels", 5, 50, dmKeepCaption, keepCol3)

    -- Messages to Keep per Conversation (per-category message caps, each
    -- with a "No limit" toggle - safe to uncap now that chat rendering is
    -- capped to the last 200 messages regardless of how many are stored).
    -- 2x2 grid (DM/Guild, then Party-Raid/Channel) instead of 4 stacked
    -- rows - halves the vertical space this section needs.
    local msgHeading = text(content, "Messages to Keep per Conversation", "GameFontNormal")
    belowPrev(msgHeading, 0, 20)
    local msgHint = text(content, "Applies per conversation - e.g. per DM, or per Party/Raid session.", "GameFontDisableSmall")
    belowPrev(msgHint, 0, 4)
    panel.messageLimitFields = {}
    -- Both rows of a column share one fieldOffset (the wider of the two
    -- captions in that column + a gap), not each row's own caption width -
    -- "DM messages" is much shorter than "Party/Raid session messages"
    -- right below it, and anchoring each field to its own caption's width
    -- left the two fields (and the whole row after them) at different X,
    -- a ragged left edge instead of a lined-up column of boxes.
    local col1FieldOffset = math.max(labelWidth("DM messages"), labelWidth("Party/Raid session messages")) + 6
    local col2FieldOffset = math.max(labelWidth("Guild Chat messages"), labelWidth("Channel messages")) + 6
    -- Measured, not a hardcoded 24 - the native WoW Classic theme's
    -- checkButton() is 32px (UICheckButtonTemplate's default), not the
    -- flat themes' 24px, and a hardcoded value here only ever got tested
    -- against ElvUI, silently running column 2 too close to column 1 on
    -- the Classic theme specifically.
    local checkboxWidthProbe = checkButton(content)
    local CHECKBOX_WIDTH = checkboxWidthProbe:GetWidth() or 24
    checkboxWidthProbe:Hide()
    local MSG_COLUMN_X = col1FieldOffset + FIELD_WIDTH + 14 + CHECKBOX_WIDTH + 2 + labelWidth("No limit") + 16
    local function addMessageLimitField(label, setting, unlimitedSetting, minimum, default, anchorTo, xOffset, fieldOffset)
        local caption = text(content, label, "GameFontHighlightSmall")
        if anchorTo then
            caption:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", xOffset, 0)
        else
            -- 14, not 10 - the checkbox below is centered on the field and can
            -- be taller than it (32px native vs. field's 20px), so it needs a
            -- bit more headroom above to clear the row above without bleeding
            -- into it (see the centering comment below).
            belowPrev(caption, 0, 14)
        end
        local field = numberField(content, FIELD_WIDTH, 20)
        -- Anchored to the shared per-column offset (see col1FieldOffset/
        -- col2FieldOffset above), not this caption's own width - keeps
        -- every field in a column at the same X regardless of which row's
        -- caption happens to be shorter.
        field:SetPoint("TOP", caption, "TOP", 0, 3)
        field:SetPoint("LEFT", caption, "LEFT", fieldOffset, 0)
        local unlimitedBox = checkButton(content)
        -- Centered on the field's own height, not just nudged down a fixed
        -- amount - the checkbox is a different size per theme (32px native
        -- UICheckButtonTemplate vs. 24px on the flat themes), and a fixed
        -- offset left it visibly lower than the field on every theme.
        local boxHeight = unlimitedBox:GetHeight() or 24
        unlimitedBox:SetPoint("TOPLEFT", field, "TOPRIGHT", 14, (boxHeight - 20) / 2)
        local unlimitedLabel = text(content, "No limit", "GameFontHighlightSmall")
        unlimitedLabel:SetPoint("LEFT", unlimitedBox, "RIGHT", 2, 0)
        local function apply()
            local value = tonumber(field:GetText())
            if not value or value < minimum then value = SW.DB.settings[setting] or default end
            value = math.floor(value)
            SW.DB.settings[setting] = value
            field:ClearFocus()
            flashSaved(field, unlimitedLabel)
            SW:RefreshSettingsPanel()
        end
        field:SetScript("OnEnterPressed", apply)
        field:SetScript("OnEditFocusLost", apply)
        unlimitedBox:SetScript("OnClick", function(self)
            SW.DB.settings[unlimitedSetting] = self:GetChecked() and true or false
            flashSaved(field, unlimitedLabel)
            SW:RefreshSettingsPanel()
        end)
        panel.messageLimitFields[#panel.messageLimitFields + 1] = {
            field = field, unlimitedBox = unlimitedBox, unlimitedLabel = unlimitedLabel, setting = setting,
            unlimitedSetting = unlimitedSetting, minimum = minimum, default = default,
        }
        -- Only the first field of a row should advance the shared anchor -
        -- a sibling placed via anchorTo shares that same row and must not
        -- push the next section down twice.
        if not anchorTo then prev = unlimitedBox end
        return caption
    end
    local dmMsgCaption = addMessageLimitField("DM messages", "maxDMMessages", "dmMessagesUnlimited", 50, 1500, nil, nil, col1FieldOffset)
    addMessageLimitField("Guild Chat messages", "maxGuildMessages", "guildMessagesUnlimited", 50, 1500, dmMsgCaption, MSG_COLUMN_X, col2FieldOffset)
    local partyMsgCaption = addMessageLimitField("Party/Raid session messages", "maxPartyRaidMessages", "partyRaidMessagesUnlimited", 50, 1500, nil, nil, col1FieldOffset)
    addMessageLimitField("Channel messages", "maxChannelMessages", "channelMessagesUnlimited", 50, 1500, partyMsgCaption, MSG_COLUMN_X, col2FieldOffset)

    local styleHeading = text(content, "UI Style", "GameFontNormal")
    belowPrev(styleHeading, 0, 30)
    local styleHint = text(content, "Changing this applies after a UI reload.", "GameFontDisableSmall")
    belowPrev(styleHint, 0, 4)
    local function themePill(themeKey, label)
        local pill = fitButton(button(content, label, 10, 22), 16)
        pill:SetScript("OnClick", function()
            SW.DB.settings.uiTheme = themeKey
            SW:RefreshSettingsPanel()
        end)
        return pill
    end
    panel.themeClassic = themePill("classic", "WoW Classic")
    belowPrev(panel.themeClassic, 0, 10)
    panel.themeElvui = themePill("elvui", "ElvUI")
    panel.themeElvui:SetPoint("LEFT", panel.themeClassic, "RIGHT", 6, 0)
    panel.themeModern = themePill("modern", "Modern SaveWhispers")
    panel.themeModern:SetPoint("LEFT", panel.themeElvui, "RIGHT", 6, 0)
    panel.themeDragonflight = themePill("dragonflight", "Dragonflight")
    panel.themeDragonflight:SetPoint("LEFT", panel.themeModern, "RIGHT", 6, 0)
    panel.reloadUI = fitButton(button(content, "Reload UI", 10, 22))
    panel.reloadUI:SetPoint("LEFT", panel.themeDragonflight, "RIGHT", 16, 0)
    panel.reloadUI:SetScript("OnClick", function() ReloadUI() end)

    local dangerHeading = text(content, "Danger Zone", "GameFontNormal", 0.9, 0.3, 0.3)
    belowPrev(dangerHeading, 0, 24)
    local dangerHint = text(content, "These permanently delete saved history - each asks for confirmation first.", "GameFontDisableSmall")
    belowPrev(dangerHint, 0, 4)
    panel.deleteDMs = fitButton(button(content, "Delete All DMs", 10, 22))
    belowPrev(panel.deleteDMs, 0, 14)
    panel.deleteDMs:SetScript("OnClick", function() StaticPopup_Show("SAVEWHISPERS_CONFIRM_DELETE_DMS") end)
    panel.deleteGuild = fitButton(button(content, "Delete Guild Chat", 10, 22))
    panel.deleteGuild:SetPoint("LEFT", panel.deleteDMs, "RIGHT", 6, 0)
    panel.deleteGuild:SetScript("OnClick", function() StaticPopup_Show("SAVEWHISPERS_CONFIRM_DELETE_GUILD") end)
    panel.deleteGroup = fitButton(button(content, "Delete Party/Raid Sessions", 10, 22))
    panel.deleteGroup:SetPoint("LEFT", panel.deleteGuild, "RIGHT", 6, 0)
    panel.deleteGroup:SetScript("OnClick", function() StaticPopup_Show("SAVEWHISPERS_CONFIRM_DELETE_GROUP") end)
    panel.deleteAll = fitButton(button(content, "Delete All Chats", 10, 22))
    belowPrev(panel.deleteAll, 0, 8)
    panel.deleteAll:SetScript("OnClick", function() StaticPopup_Show("SAVEWHISPERS_CONFIRM_DELETE_ALL") end)

    -- Measured from the actual placed widgets, not a hardcoded guess - a
    -- fixed height here doesn't match every theme (native checkboxes are
    -- taller than the flat themes', sliders/buttons differ in size too),
    -- so whichever theme actually needed less than the guessed height left
    -- a permanently empty gap in the scroll area below the real content -
    -- visible as the game world showing through, since nothing in this
    -- addon puts an opaque background behind the scroll content itself
    -- (only the outer window's own backdrop is behind all of this).
    -- content and panel.deleteAll share the same effective scale (no
    -- SetScale between them), so a plain GetTop()/GetBottom() difference is
    -- already in the right units for SetSize - safe here, unlike the scale
    -- conversion normalizeTopLeft needed for crossing a SetScale boundary.
    local usedHeight = 1150
    local top, bottom = content:GetTop(), panel.deleteAll:GetBottom()
    if top and bottom then usedHeight = math.max(top - bottom + 20, 400) end
    -- Width measured the same way as height, from the actual widgets
    -- placed - a hardcoded guess here (previously a flat 800, then 900) is
    -- exactly what caused both the "wasted empty space" complaint and later
    -- the opposite "columns run off the edge" complaint: neither number
    -- actually matched what the two-column/grid sections above need.
    local contentLeft = content:GetLeft()
    local rightEdge = 0
    for _, entry in ipairs(panel.limitFields) do
        local r = entry.field:GetRight()
        if r and r > rightEdge then rightEdge = r end
    end
    for _, entry in ipairs(panel.messageLimitFields) do
        local r = entry.unlimitedLabel:GetRight()
        if r and r > rightEdge then rightEdge = r end
    end
    for _, widget in ipairs({ panel.reloadUI, panel.deleteGroup }) do
        local r = widget:GetRight()
        if r and r > rightEdge then rightEdge = r end
    end
    for _, entry in ipairs(panel.sliders) do
        local r = entry.resetButton:GetRight()
        if r and r > rightEdge then rightEdge = r end
    end
    local usedWidth = 700
    if contentLeft and rightEdge > 0 then usedWidth = math.max(rightEdge - contentLeft + 16, 700) end
    content:SetSize(usedWidth, usedHeight)
end

function SW:RefreshSettingsPanel()
    local panel = self.ui.panels.Settings
    panel.loading = true
    panel.enabled:SetChecked(self.DB.settings.enabled and true or false)
    panel.minimap:SetChecked(self.DB.settings.showMinimap and true or false)
    panel.sortByActivity:SetChecked(self.DB.settings.sortByActivity and true or false)
    for _, entry in ipairs(panel.badgeChecks or {}) do
        entry.box:SetChecked(self.DB.settings[entry.setting] and true or false)
    end
    for _, entry in ipairs(panel.sliders) do
        local value = entry.channel and self.DB.settings[entry.setting][entry.channel] or self.DB.settings[entry.setting]
        entry.slider:SetValue(value or 0)
    end
    for _, entry in ipairs(panel.limitFields or {}) do
        local value = tonumber(self.DB.settings[entry.setting]) or entry.default
        if not entry.field:HasFocus() then entry.field:SetText(tostring(value)) end
    end
    for _, entry in ipairs(panel.messageLimitFields or {}) do
        local unlimited = self.DB.settings[entry.unlimitedSetting] and true or false
        entry.unlimitedBox:SetChecked(unlimited)
        local value = tonumber(self.DB.settings[entry.setting]) or entry.default
        if not entry.field:HasFocus() then entry.field:SetText(tostring(value)) end
        -- Disable() alone doesn't change how either theme's field looks -
        -- native InputBoxTemplate and the flat themes' own backdrop colors
        -- both stay fully lit regardless of enabled state, and EditBox text
        -- doesn't reliably dim from frame-level SetAlpha the way a plain
        -- FontString would. Setting the text color directly is the only
        -- thing that visibly shows on every theme.
        if unlimited then
            entry.field:Disable()
            entry.field:SetTextColor(0.5, 0.5, 0.5)
        else
            entry.field:Enable()
            entry.field:SetTextColor(unpack(currentTheme().textColor))
        end
    end
    local currentTheme = self.DB.settings.uiTheme or "classic"
    for _, pill in ipairs({ panel.themeClassic, panel.themeElvui, panel.themeModern, panel.themeDragonflight }) do
        pill:UnlockHighlight()
    end
    local activeThemePill = ({ classic = panel.themeClassic, elvui = panel.themeElvui, modern = panel.themeModern, dragonflight = panel.themeDragonflight })[currentTheme]
    if activeThemePill then activeThemePill:LockHighlight() end
    panel.reloadUI:SetShown(currentTheme ~= self.ui.appliedTheme)
    panel.loading = false
end

local CHANGELOG = {
    {
        version = "V1.4",
        credit = "Developer: Gabbajoe",
        entries = {
            "Right-click a conversation (in the list or the open chat's name) for Watchlist/Pin/Copy Name/Export Chat/Delete, instead of a row of buttons above every chat - shows only the actions that make sense for that conversation's type.",
            "Sender names in the chat log are clickable - right-click for Copy Name, and Invite when they aren't already in your party/raid.",
            "Shift-clicking an item or quest now links it into the SaveWhispers message box, the same as the default chat box.",
            "Guild Chat and your currently active Party/Raid session can be replied to directly from SaveWhispers, not just read - old saved sessions stay read-only.",
            "SaveWhispers now recognizes DM contacts who also have it installed and uses that to show a more accurate online status, with a small icon next to their name once confirmed.",
        },
    },
    {
        version = "V1.3",
        credit = "Developer: Gabbajoe",
        entries = {
            "Bookmark any message with the star icon next to it - bookmarked messages are exempt from the per-category message cap, and a new Bookmarks tab lists all of them across every conversation with a Jump button.",
            "Search chat text, either within the open conversation or across everything at once (\"All Chats\"); jumping to a result scrolls to and briefly highlights that exact message.",
            "Chat history now loads more as you scroll up instead of stopping hard at the last 200 messages - applies to normal browsing and search alike.",
            "New messages that arrive while you're scrolled up reading history no longer yank the view down to the bottom - a small \"N new messages\" button appears instead, click to jump down.",
            "Members popup (Party/Raid) is smaller, sizes itself to the group and scrolls past 20 members, and names are individually clickable to copy just that one.",
            "Settings tab reorganized into a more compact two-column layout so most of it fits without scrolling.",
            "Theme-aware logo (window title + minimap button) and custom scrollbar arrows/resize grip per UI Style, instead of tinted Classic Blizzard art on the flat themes.",
            "Escape now closes the SaveWhispers window and its Members/Copy popups, like any other Blizzard window.",
            "Button labels made consistent (Title Case) throughout the addon.",
            "Fixed: the window couldn't be resized to fully fill the screen, always leaving a margin.",
            "Fixed: Party/Raid chat could occasionally sort out of chronological order against other conversations.",
            "Fixed: switching characters mid-session (e.g. logging out of one character straight into a group on another) could keep writing into the previous character's Party/Raid log.",
            "Fixed: the ElvUI theme's window border was a flat, unstyled gray instead of ElvUI's own accent color.",
        },
    },
    {
        version = "V1.2",
        credit = "Developer: Gabbajoe",
        entries = {
            "Settings reorganized: \"Conversations & Sessions to Keep\" (DMs/Party-Raid/Channels) and \"Messages to Keep per Conversation\" (DMs/Guild/Party-Raid/Channels) are now separate, consistently named sections, each message limit has its own \"No limit\" option, sort-by-recent-activity is on by default, and changing a value shows a brief \"Saved\" confirmation.",
            "Choose which categories (DMs/Guild/Group/Channels) count toward the minimap button's unread badge.",
            "Messages tab: added a Channels filter pill (All/DM/Guild/Group/Chan), and the conversation counter now shows the count/limit for whichever filter is active instead of always DMs.",
            "Guild Chat: removed the Pin and Members buttons - Guild Chat is always a single conversation, so pinning did nothing, and Members just duplicated the default Guild Roster window.",
            "Party/Raid session Members popups no longer show online/offline status - it was checking the player's currently grouped units, which for an old session showed whoever they happen to be grouped with today rather than who was actually in that session.",
            "Fixed: chat text looked slightly blurry compared to the default chat frame at every Chat text scale setting.",
            "Fixed: the Interface scale and Chat text scale sliders made the window visibly jump around while dragging, and at any Interface Scale other than 100% the window would land far short of wherever it was actually dragged to.",
            "Fixed: a Party/Raid session could get silently split into multiple fragments mid-conversation if the client briefly misreported being in a party right after a loading screen or raid conversion, orphaning the original session.",
        },
    },
    {
        version = "V1.1",
        credit = "Developer: Gabbajoe",
        entries = {
            "Native Blizzard window look (parchment/gold), pixel-perfect resizing and dragging.",
            "Raid Chat support, and Party/Raid history split into per-session conversations with a captured member list; switching between party and raid mid-session relabels it in place with a note instead of splitting the log.",
            "Clickable, tooltip-enabled, correctly colored item and quest links in saved messages - including quest references posted by Questie.",
            "Timestamps and Today/Yesterday day separators on every message; class-colored sender names; Guild Chat shows your guild name.",
            "Export chat and Copy name popups (Guild/Party/Raid/Channel chat is read-only, so those windows no longer show a message box).",
            "Combined suggestion-dropdown + Tab-complete for player/channel name fields.",
            "Configurable limits for saved DMs, group chat messages and kept Party/Raid sessions.",
            "Choice of sorting conversations alphabetically or by most recent activity, within Guild/Party/Raid and within DMs.",
            "Conversation list filter pills (All / DMs / Guild / Group) to untangle Guild Chat and Party/Raid sessions from the DM list.",
            "Settings > Danger Zone: delete all DMs, Guild Chat history, all Party/Raid sessions, or everything at once, each behind a confirmation popup. Select mode can now bulk-delete any conversation type, not just DMs.",
            "Settings > UI Style: choose between WoW Classic (default), an ElvUI-inspired flat theme, a Modern SaveWhispers theme, or a Dragonflight-inspired theme (applies after a UI reload).",
            "Minimap button gets a gold border ring like every other addon's minimap icon, plus a small unread-count badge.",
            "Fixed: window always staying on top of other Blizzard windows.",
            "Fixed: a crash from unbounded frame growth.",
            "Fixed: duplicate empty DM conversations from adding a name without its realm.",
            "Fixed: a message box left focused could keep eating keystrokes (e.g. WASD) after closing the window or switching tabs.",
            "Fixed: the Members popup could list yourself twice (once bare, once as \"Name-Realm\") - now deduped by base name, shown as \"Name (Realm)\" like everywhere else.",
        },
    },
    {
        version = "V1.0",
        credit = "Developer: Femboybaddie",
        entries = {
            "Persistent private, Guild, Party and selected channel histories.",
            "Chat colors, pins, member windows and a movable minimap button.",
            "Resizable SaveWhispers window.",
        },
    },
}

local function changelogRow(parent)
    return parent:CreateFontString(nil, "OVERLAY")
end

function SW:BuildChangelogPanel()
    local panel = self:NewPanel("Changelog")
    -- Same inset content box as the other tabs - see BuildWatchlistPanel.
    panel.box = inset(panel)
    panel.box:SetAllPoints()
    local icon = panel.box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local heading = text(panel.box, "Changelog", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 6, 1)
    panel.list = scroll(panel.box)
    panel.list:SetPoint("TOPLEFT", 12, -44)
    panel.list:SetPoint("BOTTOMRIGHT", -28, 10)
end

-- Each version gets its own heading line (not buried mid-paragraph) with
-- its bullets indented as sub-items below it, and the wrap width is read
-- from the scroll frame's actual current size instead of a hardcoded pixel
-- value - a fixed width overflowed past the window's edge whenever the
-- window was resized narrower than that constant.
function SW:RefreshChangelogPanel()
    local panel = self.ui.panels.Changelog
    if not panel then return end
    local content = panel.list.content
    poolStart(content)
    local width = math.max(300, panel.list:GetWidth() - 8)
    local y = 0
    for _, entry in ipairs(CHANGELOG) do
        local versionLabel = entry.version .. (entry.credit and (" (" .. entry.credit .. ")") or "")
        local header = poolRow(content, changelogRow)
        header:SetFontObject("GameFontNormal")
        header:SetTextColor(1, 0.82, 0)
        header:SetJustifyH("LEFT")
        header:SetText(versionLabel)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
        header:SetWidth(width)
        y = y - header:GetStringHeight() - 8
        for _, line in ipairs(entry.entries) do
            local bullet = poolRow(content, changelogRow)
            bullet:SetFontObject("GameFontHighlightSmall")
            bullet:SetTextColor(0.85, 0.85, 0.85)
            bullet:SetJustifyH("LEFT")
            bullet:SetJustifyV("TOP")
            if bullet.SetWordWrap then bullet:SetWordWrap(true) end
            bullet:SetText("- " .. line)
            bullet:ClearAllPoints()
            bullet:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y)
            bullet:SetWidth(width - 14)
            y = y - bullet:GetStringHeight() - 4
        end
        y = y - 14
    end
    content:SetSize(width, math.max(panel.list:GetHeight(), -y + 4))
    poolFinish(content)
end

function SW:RefreshUI()
    if not self.ui or not self.ui.frame then return end
    -- Opening/selecting a conversation clears its unread count directly
    -- and calls RefreshUI (or SwitchTab, which calls it) rather than
    -- NotifyDataChanged - the minimap badge needs updating here too, or it
    -- keeps showing a stale count until something else happens to trigger
    -- NotifyDataChanged.
    if self.UpdateMinimapBadge then self:UpdateMinimapBadge() end
    -- Skip the (expensive) panel rebuild while the window is closed; it runs
    -- again from ToggleMainFrame/SwitchTab once the window is shown, so
    -- nothing is lost, but background chat spam no longer rebuilds hidden UI.
    if not self.ui.frame:IsShown() then return end
    self.ui.frame:SetScale(self.DB.settings.uiScale or 1)
    if self.ui.frame.UpdateResizeBounds then self.ui.frame.UpdateResizeBounds() end
    local active = self.ui.activeTab
    if active == "Messages" then self:RefreshMessagesPanel()
    elseif active == "Watchlist" then self:RefreshWatchlistPanel()
    elseif active == "Bookmarks" then self:RefreshBookmarksPanel()
    elseif active == "Settings" then self:RefreshSettingsPanel()
    elseif active == "Changelog" then self:RefreshChangelogPanel()
    end
end

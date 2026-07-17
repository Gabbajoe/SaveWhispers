local SW = _G.SaveWhispers

local function place(button)
    local angle = math.rad(SW.DB.minimap.minimapPos or 220)
    local radius = 82
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function updateDrag(button)
    local scale = Minimap:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local centerX, centerY = Minimap:GetCenter()
    local atan2 = math.atan2 or atan2
    if not atan2 then return end
    local angle = math.deg(atan2(y - centerY, x - centerX))
    if angle < 0 then angle = angle + 360 end
    SW.DB.minimap.minimapPos = angle
    place(button)
end

function SW:CreateMinimapButton()
    if not Minimap then return end
    -- Standard LibDBIcon-style layout (31x31 button, 20x20 icon inset at a
    -- fixed TOPLEFT offset, 54x54 ring anchored at the button's own
    -- TOPLEFT) - the exact sizes/offsets countless other minimap addon
    -- buttons already use, since MiniMap-TrackingBorder's circular cutout
    -- isn't centered in its own texture bounds; a plain CENTER anchor on
    -- the icon left it visibly off-center inside the ring.
    local button = _G.SaveWhispersMinimapButton or CreateFrame("Button", "SaveWhispersMinimapButton", Minimap)
    button:SetParent(Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(20, 20)
        button.icon:SetPoint("TOPLEFT", 7, -6)
    end
    -- Theme-matched logo (classic envelope vs. flat bubble) - see
    -- SW:BrandIconPath in UI.lua, shared with the window title icon.
    button.icon:SetTexture(SW:BrandIconPath("minimap"))
    button.icon:SetTexCoord(0, 1, 0, 1)
    if not button.border then
        -- The gold ring every other minimap button has (Blizzard's own
        -- tracking icons included) - without it this looked like a plain
        -- floating icon instead of a proper minimap button.
        button.border = button:CreateTexture(nil, "OVERLAY")
        button.border:SetSize(54, 54)
        button.border:SetPoint("TOPLEFT", 0, 0)
        button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    end
    if not button.highlight then
        -- UI-Minimap-ZoomButton-Highlight is a cross/starburst shape meant
        -- for the +/- zoom buttons, not a plain icon - looked out of place
        -- here. A plain square glow reads as a normal button highlight.
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetPoint("TOPLEFT", button.icon, "TOPLEFT")
        button.highlight:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT")
        button.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        button.highlight:SetBlendMode("ADD")
    end
    button:SetScript("OnClick", function(self, clicked)
        if self.dragged then self.dragged = nil; return end
        if clicked == "RightButton" then
            SW:SetSetting("showMinimap", false)
            SW:Print("Minimap button hidden. Re-enable it in Settings or with /sw.")
        else
            SW:ToggleMainFrame()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:SetScript("OnUpdate", function(frame) updateDrag(frame) end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        updateDrag(self)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SaveWhispers (SW)")
        GameTooltip:AddLine("Left-click: Open / close", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move button", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Hide", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.ui.minimapButton = button
    place(button)
    self:UpdateMinimapButton()
    self:UpdateMinimapBadge()
end

function SW:UpdateMinimapButton()
    local button = self.ui and self.ui.minimapButton
    if not button then return end
    if self.DB.settings.showMinimap == false then button:Hide() else button:Show(); place(button) end
end

function SW:UpdateMinimapBadge()
    local button = self.ui and self.ui.minimapButton
    if not button then return end
    if not button.badge then
        button.badge = CreateFrame("Frame", nil, button)
        button.badge:SetSize(18, 18)
        -- Bottom-left (roughly 8 o'clock), like most addons' minimap
        -- count badges - was top-right, and a flat-color square instead of
        -- a proper round badge.
        button.badge:SetPoint("BOTTOMLEFT", -2, -2)
        button.badge.bg = button.badge:CreateTexture(nil, "OVERLAY")
        button.badge.bg:SetAllPoints()
        button.badge.bg:SetTexture("Interface\\COMMON\\Indicator-Red")
        button.badge.text = button.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- A plain CENTER anchor reads slightly high (font metrics assume
        -- room for a descender that a 1-3 digit number never uses) - a
        -- small downward nudge optically centers it in the round badge.
        button.badge.text:SetPoint("CENTER", 0, -0.5)
        button.badge.text:SetJustifyH("CENTER")
        button.badge.text:SetJustifyV("MIDDLE")
        button.badge.text:SetTextColor(1, 1, 1)
        if button.badge.text.SetTextHeight then button.badge.text:SetTextHeight(11) end
    end
    local settings = self.DB.settings
    local total = 0
    if settings.badgeCountsDM then
        for _, conversation in pairs(self.DB.conversations or {}) do
            total = total + (tonumber(conversation.unread) or 0)
        end
    end
    for _, conversation in pairs(self.DB.groupChats or {}) do
        if type(conversation) == "table" then
            local include = (conversation.channel == "guild" and settings.badgeCountsGuild)
                or ((conversation.channel == "party" or conversation.channel == "raid") and settings.badgeCountsGroup)
                or (conversation.channel == "channel" and settings.badgeCountsChannel)
            if include then total = total + (tonumber(conversation.unread) or 0) end
        end
    end
    if total > 0 then
        button.badge.text:SetText(total > 99 and "99+" or tostring(total))
        button.badge:Show()
    else
        button.badge:Hide()
    end
end

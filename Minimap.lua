local SW = _G.SaveWhispers
local ICON = "Interface\\AddOns\\SaveWhispers\\assets\\savewhispers_minimap"

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
    local button = _G.SaveWhispersMinimapButton or CreateFrame("Button", "SaveWhispersMinimapButton", Minimap)
    button:SetParent(Minimap)
    button:SetSize(26, 26)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("CENTER")
        button.icon:SetSize(24, 24)
    end
    button.icon:SetTexture(ICON)
    button.icon:SetTexCoord(0, 1, 0, 1)
    if not button.highlight then
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetPoint("CENTER")
        button.highlight:SetSize(28, 28)
        button.highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
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
end

function SW:UpdateMinimapButton()
    local button = self.ui and self.ui.minimapButton
    if not button then return end
    if self.DB.settings.showMinimap == false then button:Hide() else button:Show(); place(button) end
end

function SW:UpdateMinimapBadge()
    -- Reserved for unread-count support.
end

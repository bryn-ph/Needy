-- Minimap icon: left-click opens settings, right-click the roll history; drag it round the edge.
-- Hand-rolled in the style of LibDBIcon (same approach as Jest; no libraries).
local _, ns = ...

local Button = {}
ns.MinimapButton = Button

local EDGE_OFFSET = 5 -- how far outside the minimap's edge the button's centre sits

local button

local function place()
	local a = math.rad(ns.settings.minimapAngle)
	local r = (Minimap:GetWidth() or 140) / 2 + EDGE_OFFSET
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- While dragging: follow the cursor round the edge.
local function followCursor()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local scale = Minimap:GetEffectiveScale()
	local x, y = GetCursorPosition()
	ns.settings.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx)) % 360
	place()
end

local function create()
	button = CreateFrame("Button", "NeedyMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(19, 19)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture(ns.Widgets.LOGO)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT") -- the border art has its ring offset inside the texture
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ns.HistoryWindow.Toggle()
		else
			ns.SettingsWindow.Toggle()
		end
	end)
	button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, 0) end)
	button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 1) end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", followCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Needy", 1, 0.78, 0.28)
		GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
		GameTooltip:AddLine("Right-click: roll history", 1, 1, 1)
		GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Show or hide the button to match the setting (creating it the first time it's shown).
function Button.Update()
	if not Minimap then return end
	if not ns.settings.minimapShow then
		if button then button:Hide() end
		return
	end
	if not button then create() end
	place()
	button:Show()
end

function Button.Init()
	Button.Update()
end

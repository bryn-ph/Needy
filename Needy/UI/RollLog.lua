-- The Roll Log: a small dice tab on screen during a run. Click it to slide out this run's drops
-- (item, winner, roll); click again to tuck it away. Drag the tab to move it. Optional (showLog).
local _, ns = ...

local RollLog = {}
ns.RollLog = RollLog

local W = ns.Widgets
local C = W.C

local TAB_SIZE = 38
local PANEL_WIDTH = 290
local HEADER_HEIGHT = 30
local ROW_HEIGHT = 24

local tab, panel
local rows = {}
local lastCount = 0

-- The run the log follows: a test run while one is going, otherwise the real one.
local function currentSession()
	return ns.Tracker.testSession or ns.Tracker.session
end

local function winnerText(drop)
	if drop.allPassed then
		return ("|c%spassed|r"):format(W.MUTED_HEX)
	end
	if not drop.winner then
		return ("|c%srolling...|r"):format(W.MUTED_HEX)
	end
	local r = drop.rolls[drop.winner] or {}
	local text = ns.ColorName(drop.winner, drop.winnerClass or r.class)
	if r.roll then
		text = text .. ("  |c%s%d|r"):format(W.ACCENT_HEX, r.roll)
	end
	return text
end

-- Position ------------------------------------------------------------------------------------

local function savePosition()
	local point, _, relPoint, x, y = tab:GetPoint(1)
	ns.settings.logPosition = { point, relPoint, x, y }
end

local function placeTab()
	tab:ClearAllPoints()
	local p = ns.settings.logPosition
	if p then
		tab:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		tab:SetPoint("LEFT", UIParent, "LEFT", 24, 140)
	end
end

-- The panel opens on whichever side of the tab has more room.
local function placePanel()
	panel:ClearAllPoints()
	local x = tab:GetCenter()
	local screen = UIParent:GetWidth() or 0
	if x and x > screen / 2 then
		panel:SetPoint("TOPRIGHT", tab, "TOPLEFT", -4, 0)
		panel.growLeft = true
	else
		panel:SetPoint("TOPLEFT", tab, "TOPRIGHT", 4, 0)
		panel.growLeft = false
	end
end

-- Rows ------------------------------------------------------------------------------------------

local function createRow(i)
	local row = CreateFrame("Button", nil, panel)
	row:SetSize(PANEL_WIDTH - 2, ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.06)

	row.stripe = row:CreateTexture(nil, "ARTWORK")
	row.stripe:SetPoint("TOPLEFT", 0, 0)
	row.stripe:SetPoint("BOTTOMLEFT", 0, 0)
	row.stripe:SetWidth(2)

	row.iconBorder = row:CreateTexture(nil, "ARTWORK")
	row.iconBorder:SetSize(18, 18)
	row.iconBorder:SetPoint("LEFT", 9, 0)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetPoint("TOPLEFT", row.iconBorder, "TOPLEFT", 1, -1)
	row.icon:SetPoint("BOTTOMRIGHT", row.iconBorder, "BOTTOMRIGHT", -1, 1)
	ns.CropIcon(row.icon)

	row.winner = W.Text(row, "small")
	row.winner:SetPoint("RIGHT", -10, 0)
	row.winner:SetJustifyH("RIGHT")
	row.winner:SetWordWrap(false)

	row.item = W.Text(row, "small")
	row.item:SetPoint("LEFT", row.iconBorder, "RIGHT", 7, 0)
	row.item:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		if self.drop then
			W.DropTooltip(self, self.drop, self.drop.link, true)
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self)
		local link = self.drop and self.drop.link
		if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			HandleModifiedItemClick(link)
		else
			ns.HistoryWindow.Show(currentSession())
		end
	end)
	return row
end

local function setRow(row, drop)
	row.drop = drop
	local r, g, b = ns.QualityColor(W.DropQuality(drop))
	row.stripe:SetColorTexture(r, g, b, 0.9)
	row.iconBorder:SetColorTexture(r, g, b, 1)
	row.icon:SetTexture(W.DropIcon(drop))
	row.item:SetText(drop.name or (drop.link and drop.link:match("%[(.-)%]")) or "?")
	row.item:SetTextColor(r, g, b)
	row.winner:SetText(winnerText(drop))
	-- Winner always shows in full; the item name gets what's left and is cut off with "...".
	local winnerWidth = math.min(W.StringWidth(row.winner) + 2, PANEL_WIDTH * 0.5)
	row.winner:SetWidth(winnerWidth)
	row.item:SetWidth(math.max(20, PANEL_WIDTH - 2 - 9 - 18 - 7 - winnerWidth - 10 - 8))
end

-- Frames ----------------------------------------------------------------------------------------

local function createTab()
	tab = CreateFrame("Button", "NeedyLogTab", UIParent, "BackdropTemplate")
	tab:SetSize(TAB_SIZE, TAB_SIZE)
	tab:SetFrameStrata("MEDIUM")
	tab:SetClampedToScreen(true)
	tab:SetMovable(true)
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tab:RegisterForDrag("LeftButton")
	W.Skin(tab)
	W.Shadow(tab, 3)
	W.Sheen(tab, 18, 0.05)

	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetSize(24, 24)
	tab.icon:SetPoint("CENTER")
	tab.icon:SetTexture(W.LOGO)

	tab.edge = tab:CreateTexture(nil, "OVERLAY")
	tab.edge:SetPoint("BOTTOMLEFT", 1, 1)
	tab.edge:SetPoint("BOTTOMRIGHT", -1, 1)
	tab.edge:SetHeight(2)
	tab.edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)

	tab.badge = W.Badge(tab)
	tab.badge:SetPoint("CENTER", tab, "TOPRIGHT", -3, -3)
	tab.badge:SetFrameLevel(tab:GetFrameLevel() + 3)

	-- A gold pulse when something new drops while the log is tucked away.
	tab.glow = tab:CreateTexture(nil, "OVERLAY", nil, 2)
	tab.glow:SetPoint("TOPLEFT", -1, 1)
	tab.glow:SetPoint("BOTTOMRIGHT", 1, -1)
	tab.glow:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	tab.glow:SetBlendMode("ADD")
	tab.glow:SetAlpha(0)
	tab.pulse = tab.glow:CreateAnimationGroup()
	tab.pulse:SetLooping("BOUNCE")
	local a = tab.pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(0.3)
	a:SetDuration(0.6)
	a:SetSmoothing("IN_OUT")

	tab:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:StartMoving()
	end)
	tab:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
		placePanel()
	end)
	tab:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			ns.HistoryWindow.Show(currentSession())
		else
			RollLog.Toggle()
		end
	end)
	tab:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Roll Log", 1, 1, 1)
		local s = currentSession()
		if s then
			GameTooltip:AddLine(ns.HistoryWindow.SessionLabel(s), C.muted[1], C.muted[2], C.muted[3])
		end
		GameTooltip:AddLine("Click to " .. (ns.settings.logCollapsed and "open" or "close") .. "   Drag to move", 1, 1, 1)
		GameTooltip:AddLine("Right-click for the full history", C.muted[1], C.muted[2], C.muted[3])
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0, 0, 0, 1)
		GameTooltip:Hide()
	end)
	placeTab()
end

local function createPanel()
	panel = CreateFrame("Frame", "NeedyLog", tab, "BackdropTemplate")
	panel:SetWidth(PANEL_WIDTH)
	W.Skin(panel)
	W.Shadow(panel, 4)
	panel:EnableMouse(true)
	panel:Hide()

	local header = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(HEADER_HEIGHT - 1)
	header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	header:SetBackdropColor(C.raised[1], C.raised[2], C.raised[3], 1)
	W.Sheen(header, HEADER_HEIGHT, 0.04)
	local line = W.Hairline(header)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")

	header.title = W.Text(header, "heading")
	header.title:SetPoint("TOPLEFT", 10, -4)
	header.title:SetText("Roll Log")
	header.sub = W.Text(header, "tiny")
	header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -1)
	header.sub:SetWidth(PANEL_WIDTH - 60)
	header.sub:SetWordWrap(false)
	header.close = W.CloseButton(header, function() RollLog.Toggle() end)
	header.close:SetPoint("RIGHT", -4, 0)
	panel.header = header

	panel.empty = W.Text(panel, "muted")
	panel.empty:SetPoint("TOP", 0, -HEADER_HEIGHT - 12)
	panel.empty:SetText("Nothing has dropped yet.")

	panel.more = W.Text(panel, "tiny")
	panel.more:SetPoint("BOTTOM", 0, 6)

	local g = panel:CreateAnimationGroup()
	local fade = g:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.15)
	panel.grow = g:CreateAnimation("Scale")
	panel.grow:SetScaleFrom(0.94, 0.94)
	panel.grow:SetScaleTo(1, 1)
	panel.grow:SetDuration(0.18)
	panel.grow:SetSmoothing("OUT")
	panel.open = g
end

-- Public ---------------------------------------------------------------------------------------------

function RollLog.Refresh()
	if not tab then return end
	local s = currentSession()
	if not ns.settings.showLog or not s then
		tab:Hide()
		return
	end
	tab:SetScale(ns.settings.scale)
	tab:Show()

	local count = #s.drops
	tab.badge:SetValue(count)
	tab.badge:SetShown(count > 0)
	if count > lastCount and ns.settings.logCollapsed and ns.settings.animations then
		tab.pulse:Play()
	end
	lastCount = count

	if ns.settings.logCollapsed then
		panel:Hide()
		return
	end
	tab.pulse:Stop()
	tab.glow:SetAlpha(0)

	panel.header.sub:SetText(ns.HistoryWindow.SessionLabel(s))
	for _, row in ipairs(rows) do row:Hide() end
	local limit = math.min(ns.settings.logRows, count)
	for i = 1, limit do
		local drop = s.drops[count - i + 1] -- newest first
		local row = rows[i]
		if not row then
			row = createRow(i)
			rows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 1, -(HEADER_HEIGHT + 2 + (i - 1) * ROW_HEIGHT))
		setRow(row, drop)
		row:Show()
	end
	panel.empty:SetShown(count == 0)
	local hidden = count - limit
	panel.more:SetShown(hidden > 0)
	panel.more:SetText(("+%d more  -  right-click the tab for all"):format(hidden))
	local height = HEADER_HEIGHT + 4 + (count == 0 and 34 or limit * ROW_HEIGHT) + (hidden > 0 and 18 or 2)
	panel:SetHeight(height)
	if not panel:IsShown() then
		placePanel()
		panel:Show()
		if ns.settings.animations then
			-- grow out of the tab's side
			panel.grow:SetOrigin(panel.growLeft and "TOPRIGHT" or "TOPLEFT", 0, 0)
			panel.open:Play()
		end
	end
end

function RollLog.Toggle()
	ns.settings.logCollapsed = not ns.settings.logCollapsed
	RollLog.Refresh()
end

function RollLog.ResetPosition()
	ns.settings.logPosition = nil
	if tab then
		placeTab()
		placePanel()
	end
end

function RollLog.Init()
	createTab()
	createPanel()
	local function refresh() RollLog.Refresh() end
	ns.Listen("DROP_UPDATE", refresh)
	ns.Listen("SESSION_START", function()
		lastCount = 0
		RollLog.Refresh()
	end)
	ns.Listen("SESSION_END", refresh)
	RollLog.Refresh()
end

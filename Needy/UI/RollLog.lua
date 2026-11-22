-- The Roll Log: a small button on screen during a run. Click it to open a list of this run's drops
-- (item, winner, roll); click again to tuck it away. Drag the button to move it. Optional (showLog).
local _, ns = ...

local RollLog = {}
ns.RollLog = RollLog

local W = ns.Widgets
local GOLD = W.GOLD

local TAB_SIZE = 40
local PANEL_WIDTH = 300
local HEADER_HEIGHT = 34
local ROW_HEIGHT = 22

local tab, panel
local rows = {}
local lastCount = 0

-- The run the log follows: a test run while one is going, otherwise the real one.
local function currentSession()
	return ns.Tracker.testSession or ns.Tracker.session
end

local function winnerText(drop)
	if drop.allPassed then
		return ("|c%spassed|r"):format(W.GREY_HEX)
	end
	if not drop.winner then
		return ("|c%srolling...|r"):format(W.GREY_HEX)
	end
	local r = drop.rolls[drop.winner] or {}
	local text = ns.ColorName(drop.winner, drop.winnerClass or r.class)
	if r.roll then
		text = text .. ("  |cffffffff%d|r"):format(r.roll)
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

-- The list opens on whichever side of the button has more room.
local function placePanel()
	panel:ClearAllPoints()
	local x = tab:GetCenter()
	local screen = UIParent:GetWidth() or 0
	if x and x > screen / 2 then
		panel:SetPoint("TOPRIGHT", tab, "TOPLEFT", -2, 4)
		panel.growLeft = true
	else
		panel:SetPoint("TOPLEFT", tab, "TOPRIGHT", 2, 4)
		panel.growLeft = false
	end
end

-- Rows ------------------------------------------------------------------------------------------

local function createRow()
	local row = CreateFrame("Button", nil, panel)
	row:SetSize(PANEL_WIDTH - 16, ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)

	row.icon = W.ItemIcon(row, 18)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:EnableMouse(false)

	row.winner = W.Text(row, "GameFontHighlightSmall")
	row.winner:SetPoint("RIGHT", -4, 0)
	row.winner:SetJustifyH("RIGHT")
	row.winner:SetWordWrap(false)

	row.item = W.Text(row, "GameFontHighlightSmall")
	row.item:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
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
	local quality = W.DropQuality(drop)
	row.icon:SetItem(W.DropIcon(drop), quality)
	row.item:SetText(W.DropName(drop))
	row.item:SetTextColor(ns.QualityColor(quality))
	row.winner:SetText(winnerText(drop))
	-- Winner always shows in full; the item name gets what's left and is cut off with "...".
	local rowWidth = PANEL_WIDTH - 16
	local winnerWidth = math.min(W.StringWidth(row.winner) + 2, rowWidth * 0.5)
	row.winner:SetWidth(winnerWidth)
	row.item:SetWidth(math.max(20, rowWidth - 2 - 18 - 6 - winnerWidth - 4 - 8))
end

-- Frames ----------------------------------------------------------------------------------------

local function createTab()
	tab = CreateFrame("Button", "NeedyLogTab", UIParent)
	tab:SetSize(TAB_SIZE, TAB_SIZE)
	tab:SetFrameStrata("MEDIUM")
	tab:SetClampedToScreen(true)
	tab:SetMovable(true)
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tab:RegisterForDrag("LeftButton")

	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetAllPoints()
	tab.icon:SetTexture(W.ICON)
	tab.border = tab:CreateTexture(nil, "OVERLAY")
	tab.border:SetAllPoints()
	tab.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	tab.border:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	-- Number of drops this run, in the corner like an item stack count.
	tab.count = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	tab.count:SetPoint("BOTTOMRIGHT", -2, 2)

	-- A gold pulse when something new drops while the log is tucked away.
	tab.glow = tab:CreateTexture(nil, "OVERLAY", nil, 2)
	tab.glow:SetPoint("CENTER")
	tab.glow:SetSize(TAB_SIZE * 1.7, TAB_SIZE * 1.7)
	tab.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	tab.glow:SetBlendMode("ADD")
	tab.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	tab.glow:SetAlpha(0)
	tab.pulse = tab.glow:CreateAnimationGroup()
	tab.pulse:SetLooping("BOUNCE")
	local a = tab.pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(0.9)
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
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Roll Log", 1, 1, 1)
		local s = currentSession()
		if s then
			GameTooltip:AddLine(ns.HistoryWindow.SessionLabel(s), GOLD[1], GOLD[2], GOLD[3])
		end
		GameTooltip:AddLine("Click to " .. (ns.settings.logCollapsed and "open" or "close") .. ". Drag to move.", 1, 1, 1)
		GameTooltip:AddLine("Right-click for the full history.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	placeTab()
end

local function createPanel()
	panel = CreateFrame("Frame", "NeedyLog", tab, "BackdropTemplate")
	panel:SetWidth(PANEL_WIDTH)
	W.NativeBox(panel, 0.85)
	panel:EnableMouse(true)
	panel:Hide()

	panel.title = W.Text(panel, "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 10, -8)
	panel.title:SetText("Roll Log")
	panel.sub = W.Text(panel, "GameFontDisableSmall")
	panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -2)
	panel.sub:SetWidth(PANEL_WIDTH - 50)
	panel.sub:SetWordWrap(false)
	panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	panel.close:SetPoint("TOPRIGHT", 0, 0)
	panel.close:SetScript("OnClick", function() RollLog.Toggle() end)
	local line = W.Hairline(panel)
	line:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT)
	line:SetPoint("TOPRIGHT", -8, -HEADER_HEIGHT)

	panel.empty = W.Text(panel, "GameFontDisable")
	panel.empty:SetPoint("TOP", 0, -HEADER_HEIGHT - 12)
	panel.empty:SetText("Nothing has dropped yet.")

	panel.more = W.Text(panel, "GameFontDisableSmall")
	panel.more:SetPoint("BOTTOM", 0, 8)

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
	tab.count:SetText(count > 0 and count or "")
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

	panel.sub:SetText(ns.HistoryWindow.SessionLabel(s))
	for _, row in ipairs(rows) do row:Hide() end
	local limit = math.min(ns.settings.logRows, count)
	for i = 1, limit do
		local drop = s.drops[count - i + 1] -- newest first
		local row = rows[i]
		if not row then
			row = createRow()
			rows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 8, -(HEADER_HEIGHT + 4 + (i - 1) * ROW_HEIGHT))
		setRow(row, drop)
		row:Show()
	end
	panel.empty:SetShown(count == 0)
	local hidden = count - limit
	panel.more:SetShown(hidden > 0)
	panel.more:SetText(("+%d more - right-click the button for all"):format(hidden))
	local height = HEADER_HEIGHT + 8 + (count == 0 and 34 or limit * ROW_HEIGHT) + (hidden > 0 and 20 or 4)
	panel:SetHeight(height)
	if not panel:IsShown() then
		placePanel()
		panel:Show()
		if ns.settings.animations then
			-- grow out of the button's side
			panel.grow:SetOrigin(panel.growLeft and "TOPRIGHT" or "TOPLEFT", 0, 0)
			panel.open:Play()
		end
	end
end

function RollLog.Toggle()
	ns.settings.logCollapsed = not ns.settings.logCollapsed
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
		PlaySound(ns.settings.logCollapsed and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
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

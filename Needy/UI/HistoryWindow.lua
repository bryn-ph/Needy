-- Every drop of the current run (and of saved runs), with who chose what.
local _, ns = ...

local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow

local W = ns.Widgets
local C = W.C

local WIDTH, HEIGHT = 580, 540
local ROW_HEIGHT = 50
local ROW_GAP = 4

local win
local rows = {}
local index = 1 -- position in HistoryWindow.List()

-- Live sessions first, then saved ones, newest first.
function HistoryWindow.List()
	local list = {}
	if ns.Tracker.session then table.insert(list, ns.Tracker.session) end
	if ns.Tracker.testSession then table.insert(list, ns.Tracker.testSession) end
	if ns.Tracker.lastTest then table.insert(list, ns.Tracker.lastTest) end
	for _, s in ipairs(ns.DB.Sessions()) do
		local dup = false
		for _, l in ipairs(list) do
			if l == s then dup = true end
		end
		if not dup then table.insert(list, s) end
	end
	return list
end

function HistoryWindow.SessionLabel(s)
	local name = s.instanceName or "Unknown"
	if s.difficultyName and s.difficultyName ~= "" then
		name = name .. " (" .. s.difficultyName .. ")"
	end
	return name
end

local function duration(s)
	local secs = (s.endTime or time()) - s.startTime
	return ("%d min"):format(math.max(1, math.floor(secs / 60 + 0.5)))
end

local function playerCount(s)
	local seen, n = {}, 0
	for _, d in ipairs(s.drops) do
		for name in pairs(d.rolls or {}) do
			if not seen[name] then
				seen[name] = true
				n = n + 1
			end
		end
	end
	return n
end

-- Rows -------------------------------------------------------------------------------------------

local function createRow(parent)
	local row = W.Card(parent)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(true)

	row.stripe = row:CreateTexture(nil, "ARTWORK")
	row.stripe:SetPoint("TOPLEFT", 1, -1)
	row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	row.stripe:SetWidth(3)
	row.tint = row:CreateTexture(nil, "BORDER")
	row.tint:SetPoint("TOPLEFT", 4, -1)
	row.tint:SetPoint("BOTTOMLEFT", 4, 1)
	row.tint:SetWidth(120)

	row.iconBorder = row:CreateTexture(nil, "ARTWORK")
	row.iconBorder:SetSize(34, 34)
	row.iconBorder:SetPoint("LEFT", 12, 0)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetPoint("TOPLEFT", row.iconBorder, "TOPLEFT", 1, -1)
	row.icon:SetPoint("BOTTOMRIGHT", row.iconBorder, "BOTTOMRIGHT", -1, 1)
	ns.CropIcon(row.icon)

	row.itemButton = CreateFrame("Button", nil, row)
	row.itemButton:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 10, -1)
	row.itemButton:SetHeight(16)
	row.item = W.Text(row.itemButton, "body")
	row.item:SetPoint("LEFT")
	row.item:SetWordWrap(false)
	row.itemButton:SetScript("OnEnter", function(self) W.ItemTooltip(self, row.drop and row.drop.link) end)
	row.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.itemButton:SetScript("OnClick", function()
		local link = row.drop and row.drop.link
		if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
	end)

	row.meta = W.Text(row, "tiny")
	row.meta:SetPoint("TOPLEFT", row.itemButton, "BOTTOMLEFT", 0, -4)
	row.meta:SetWordWrap(false)

	-- Winner block on the right: name, and how they won.
	row.winner = W.Text(row, "body")
	row.winner:SetPoint("TOPRIGHT", -12, -9)
	row.winner:SetJustifyH("RIGHT")
	row.how = W.Text(row, "tiny")
	row.how:SetPoint("TOPRIGHT", row.winner, "BOTTOMRIGHT", 0, -4)
	row.how:SetJustifyH("RIGHT")

	row:SetScript("OnEnter", function(self)
		if self.drop then W.DropTooltip(self, self.drop, self.drop.link, false) end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function setRow(row, drop, width)
	row.drop = drop
	local r, g, b = ns.QualityColor(W.DropQuality(drop))
	row.stripe:SetColorTexture(r, g, b, 1)
	W.SetFade(row.tint, r, g, b, 0.12)
	row.iconBorder:SetColorTexture(r, g, b, 1)
	row.icon:SetTexture(W.DropIcon(drop))
	row.item:SetText(drop.name or (drop.link and drop.link:match("%[(.-)%]")) or "?")
	row.item:SetTextColor(r, g, b)

	if drop.allPassed then
		row.winner:SetText(("|c%sEveryone passed|r"):format(W.MUTED_HEX))
		row.how:SetText("")
	elseif drop.winner then
		local wr = drop.rolls[drop.winner] or {}
		row.winner:SetText(ns.ColorName(drop.winner, drop.winnerClass or wr.class))
		local how = wr.choice and ns.Choices[wr.choice] and ns.Choices[wr.choice].label or "Won"
		row.how:SetText(ns.ChoiceIcon(wr.choice, 11) .. " " .. how .. (wr.roll and ("  |c%s%d|r"):format(W.ACCENT_HEX, wr.roll) or ""))
	else
		row.winner:SetText(("|c%srolling...|r"):format(W.MUTED_HEX))
		row.how:SetText("")
	end

	local rightWidth = math.max(row.winner:GetStringWidth() or 0, row.how:GetStringWidth() or 0) + 24
	local textWidth = math.max(40, width - 12 - 34 - 10 - rightWidth - 8)
	row.itemButton:SetWidth(textWidth)
	row.item:SetWidth(textWidth)
	row.meta:SetWidth(textWidth)

	-- Boss and time, then everyone but the winner, fitted to the line.
	local when = drop.time and date("%H:%M", drop.time) or ""
	local boss = drop.encounterName and (drop.encounterName .. "  -  ") or ""
	W.FitRoster(row.meta, drop, textWidth, { prefix = ("|c%s%s%s|r     "):format(W.MUTED_HEX, boss, when), exclude = drop.winner })
end

-- Window ------------------------------------------------------------------------------------------

local function create()
	win = W.Window("NeedyHistory", "Roll History", WIDTH, HEIGHT)
	win:SetPoint("CENTER", -150, 30)
	local c = win.content

	-- Session switcher
	win.prev = W.ArrowButton(c, "left", function() HistoryWindow.Step(-1) end)
	win.prev:SetPoint("TOPLEFT", 14, -14)
	win.next = W.ArrowButton(c, "right", function() HistoryWindow.Step(1) end)
	win.next:SetPoint("LEFT", win.prev, "RIGHT", 4, 0)

	win.heading = W.Text(c, "big")
	win.heading:SetPoint("TOPLEFT", win.next, "TOPRIGHT", 12, 2)
	win.heading:SetPoint("RIGHT", c, "RIGHT", -150, 0)
	win.heading:SetWordWrap(false)
	win.position = W.Text(c, "tiny")
	win.position:SetPoint("TOPLEFT", win.heading, "BOTTOMLEFT", 0, -3)

	win.awards = W.Button(c, "Run Awards", 120, 26, "accent")
	win.awards:SetPoint("TOPRIGHT", -14, -13)
	win.awards:SetScript("OnClick", function()
		local s = HistoryWindow.List()[index]
		if s then ns.SummaryWindow.Show(s) end
	end)

	-- Chips: drops, players, duration, state
	win.chips = {}
	local prevChip
	for i = 1, 4 do
		local chip = W.Chip(c)
		if prevChip then
			chip:SetPoint("LEFT", prevChip, "RIGHT", 6, 0)
		else
			chip:SetPoint("TOPLEFT", 14, -54)
		end
		win.chips[i] = chip
		prevChip = chip
	end

	local line = W.Hairline(c)
	line:SetPoint("TOPLEFT", 1, -82)
	line:SetPoint("TOPRIGHT", -1, -82)

	win.scroll, win.list = W.ScrollArea(c)
	win.scroll:SetPoint("TOPLEFT", 14, -92)
	win.scroll:SetPoint("BOTTOMRIGHT", -20, 50)

	win.empty = W.Text(c, "muted")
	win.empty:SetPoint("CENTER", 0, 0)
	win.empty:SetJustifyH("CENTER")
	win.empty:SetWidth(380)

	local footer = W.Hairline(c)
	footer:SetPoint("BOTTOMLEFT", 1, 40)
	footer:SetPoint("BOTTOMRIGHT", -1, 40)
	win.hint = W.Text(c, "tiny")
	win.hint:SetPoint("BOTTOMLEFT", 14, 15)
	win.hint:SetText("Hover a row for everyone's rolls. Shift-click an item to link it.")

	win.endRun = W.Button(c, "End run now", 110, 24)
	win.endRun:SetPoint("BOTTOMRIGHT", -14, 9)
	win.endRun:SetScript("OnClick", function()
		local s = HistoryWindow.List()[index]
		if s == ns.Tracker.testSession then
			ns.TestMode.End()
		elseif s == ns.Tracker.session then
			ns.Tracker.End()
		end
		HistoryWindow.Refresh()
	end)
	win.settings = W.Button(c, "Settings", 90, 24)
	win.settings:SetPoint("BOTTOMRIGHT", -130, 9)
	win.settings:SetScript("OnClick", function() ns.SettingsWindow.Show() end)

	local function refreshIfShown()
		if win:IsShown() then HistoryWindow.Refresh() end
	end
	ns.Listen("DROP_UPDATE", refreshIfShown)
	ns.Listen("SESSION_START", refreshIfShown)
	ns.Listen("SESSION_END", refreshIfShown)
end

function HistoryWindow.Step(delta)
	local count = #HistoryWindow.List()
	index = math.max(1, math.min(count, index + delta))
	win.scroll:SetVerticalScroll(0)
	HistoryWindow.Refresh()
end

function HistoryWindow.Refresh()
	local list = HistoryWindow.List()
	if index > #list then index = math.max(1, #list) end
	local s = list[index]
	win.prev:SetEnabled(index > 1)
	win.next:SetEnabled(index < #list)
	win.awards:SetEnabled(s ~= nil and #s.drops > 0)
	win.endRun:SetShown(s ~= nil and not s.endTime)

	for _, row in ipairs(rows) do row:Hide() end
	if not s then
		win.heading:SetText("No runs yet")
		win.position:SetText("")
		for _, chip in ipairs(win.chips) do chip:Hide() end
		win.empty:SetText("Rolls are recorded while you're in a dungeon or raid.\n\nTry |cffffc747/needy test|r to see Needy in action.")
		win.empty:Show()
		return
	end

	win.heading:SetText(HistoryWindow.SessionLabel(s))
	win.position:SetText(("%s   -   run %d of %d"):format(date("%a %d %b, %H:%M", s.startTime), index, #list))
	local chipText = {
		("%d drops"):format(#s.drops),
		("%d players"):format(playerCount(s)),
		duration(s),
		s.isTest and "|cffff9933test run|r" or (s.endTime and "finished" or "|cff59e673in progress|r"),
	}
	for i, chip in ipairs(win.chips) do
		chip:SetValue(chipText[i])
		chip:Show()
	end
	win.empty:SetShown(#s.drops == 0)
	win.empty:SetText("Nothing has dropped yet.")

	-- Newest drop on top.
	local width = win.scroll:GetWidth() or 0
	if width < 10 then width = WIDTH - 36 end
	local y = 0
	for i = #s.drops, 1, -1 do
		local n = #s.drops - i + 1
		local row = rows[n]
		if not row then
			row = createRow(win.list)
			rows[n] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
		setRow(row, s.drops[i], width)
		row:Show()
		y = y + ROW_HEIGHT + ROW_GAP
	end
	win.list:SetHeight(math.max(1, y))
	win.scroll.UpdateThumb()
end

function HistoryWindow.Show(session)
	if not win then create() end
	index = 1
	if session then
		for i, s in ipairs(HistoryWindow.List()) do
			if s == session then index = i end
		end
	end
	win:Show()
	win:Raise()
	win.scroll:SetVerticalScroll(0)
	HistoryWindow.Refresh()
end

function HistoryWindow.Toggle()
	if win and win:IsShown() then
		win:Hide()
	else
		HistoryWindow.Show()
	end
end

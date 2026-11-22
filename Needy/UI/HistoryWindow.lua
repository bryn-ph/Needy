-- Every drop of the current run (and of saved runs), with who chose what.
local _, ns = ...

local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow

local W = ns.Widgets

local WIDTH, HEIGHT = 600, 540
local ROW_HEIGHT = 46
local ROW_GAP = 3

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

local function summaryLine(s)
	local mins = math.max(1, math.floor(((s.endTime or time()) - s.startTime) / 60 + 0.5))
	local state
	if s.isTest then
		state = "|cffff9933test run|r"
	elseif s.endTime then
		state = "finished"
	else
		state = "|cff33ff33in progress|r"
	end
	return ("%s  -  %d drops, %d players, %d min  -  %s"):format(
		date("%a %d %b %H:%M", s.startTime), #s.drops, playerCount(s), mins, state)
end

-- "Older run (2 of 5)" on the arrow buttons, instead of crowding the header.
local function arrowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.label, 1, 1, 1)
	GameTooltip:AddLine(("Showing run %d of %d"):format(index, #HistoryWindow.List()), 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

-- Rows -------------------------------------------------------------------------------------------

local function createRow(parent)
	local row = W.Card(parent)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(true)

	row.icon = W.ItemIcon(row, 34)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetScript("OnEnter", function(self) W.ItemTooltip(self, row.drop and row.drop.link) end)
	row.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.icon:SetScript("OnClick", function()
		local link = row.drop and row.drop.link
		if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
	end)

	row.item = W.Text(row, "GameFontNormal")
	row.item:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
	row.item:SetWordWrap(false)

	row.tag = W.WishTag(row)
	row.tag:SetPoint("LEFT", row.item, "RIGHT", 6, 0)

	row.meta = W.Text(row, "GameFontHighlightSmall")
	row.meta:SetPoint("TOPLEFT", row.item, "BOTTOMLEFT", 0, -5)
	row.meta:SetWordWrap(false)

	-- Winner block on the right: name, and how they won.
	row.winner = W.Text(row, "GameFontHighlight")
	row.winner:SetPoint("TOPRIGHT", -10, -8)
	row.winner:SetJustifyH("RIGHT")
	row.how = W.Text(row, "GameFontHighlightSmall")
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
	local quality = W.DropQuality(drop)
	row.icon:SetItem(W.DropIcon(drop), quality)
	row.item:SetText(W.DropName(drop))
	row.item:SetTextColor(ns.QualityColor(quality))

	if drop.allPassed then
		row.winner:SetText(("|c%sEveryone passed|r"):format(W.GREY_HEX))
		row.how:SetText("")
	elseif drop.winner then
		local wr = drop.rolls[drop.winner] or {}
		row.winner:SetText(ns.ColorName(drop.winner, drop.winnerClass or wr.class))
		local how = wr.choice and ns.Choices[wr.choice] and ns.Choices[wr.choice].label or "Won"
		row.how:SetText(ns.ChoiceIcon(wr.choice, 12) .. " " .. how .. (wr.roll and (" |cffffffff" .. wr.roll .. "|r") or ""))
	else
		row.winner:SetText(("|c%srolling...|r"):format(W.GREY_HEX))
		row.how:SetText("")
	end

	local rightWidth = math.max(W.StringWidth(row.winner), W.StringWidth(row.how)) + 20
	local textWidth = math.max(40, width - 6 - 34 - 8 - rightWidth - 8)
	local wished = ns.Wishlist.Matches(drop)
	row.tag:SetShown(wished)
	if wished then
		-- just wide enough for the name, so the tag sits beside it
		local room = textWidth - row.tag.fullWidth - 6
		row.item:SetWidth(math.max(40, math.min(W.StringWidth(row.item) + 2, room)))
	else
		row.item:SetWidth(textWidth)
	end
	row.meta:SetWidth(textWidth)

	-- Boss and time, then everyone but the winner, fitted to the line.
	local when = drop.time and date("%H:%M", drop.time) or ""
	local boss = drop.encounterName and (drop.encounterName .. ", ") or ""
	W.FitRoster(row.meta, drop, textWidth, { prefix = ("|c%s%s%s|r    "):format(W.GREY_HEX, boss, when), exclude = drop.winner })
end

-- Window ------------------------------------------------------------------------------------------

local function create()
	win = W.Window("NeedyHistory", "Needy - Roll History", WIDTH, HEIGHT)
	win:SetPoint("CENTER", -150, 30)

	-- Session switcher, to the right of the portrait
	win.prev = W.PageButton(win, "prev", function() HistoryWindow.Step(-1) end)
	win.prev:SetPoint("TOPLEFT", 60, -26)
	win.next = W.PageButton(win, "next", function() HistoryWindow.Step(1) end)
	win.next:SetPoint("LEFT", win.prev, "RIGHT", 0, 0)
	win.prev.label, win.next.label = "Newer run", "Older run"
	for _, b in ipairs({ win.prev, win.next }) do
		b:SetMotionScriptsWhileDisabled(true)
		b:SetScript("OnEnter", arrowTooltip)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	win.awards = W.Button(win, "Run Report", 110, 22)
	win.awards:SetPoint("TOPRIGHT", -10, -28)

	-- Heading and summary stop short of the button and cut off with "..." if they're long.
	win.heading = W.Text(win, "GameFontNormalLarge")
	win.heading:SetPoint("TOPLEFT", win.next, "TOPRIGHT", 6, -1)
	win.heading:SetPoint("RIGHT", win.awards, "LEFT", -10, 0)
	win.heading:SetWordWrap(false)
	win.sub = W.Text(win, "GameFontHighlightSmall")
	win.sub:SetPoint("TOPLEFT", win.heading, "BOTTOMLEFT", 0, -3)
	win.sub:SetPoint("RIGHT", win.awards, "LEFT", -10, 0)
	win.sub:SetWordWrap(false)

	win.awards:SetScript("OnClick", function()
		local s = HistoryWindow.List()[index]
		if s then ns.SummaryWindow.Show(s) end
	end)

	local inset = W.Inset(win)
	inset:SetPoint("TOPLEFT", 8, -66)
	inset:SetPoint("BOTTOMRIGHT", -8, 32)

	win.scroll, win.list = W.ScrollArea(inset)
	win.scroll:SetPoint("TOPLEFT", 6, -6)
	win.scroll:SetPoint("BOTTOMRIGHT", -14, 6)

	win.empty = W.Text(inset, "GameFontDisable")
	win.empty:SetPoint("CENTER", 0, 0)
	win.empty:SetJustifyH("CENTER")
	win.empty:SetWidth(380)

	win.hint = W.Text(win, "GameFontDisableSmall")
	win.hint:SetPoint("BOTTOMLEFT", 14, 12)
	win.hint:SetText("Hover a row for everyone's rolls. Shift-click an item to link it.")

	win.endRun = W.Button(win, "End run now", 110, 22)
	win.endRun:SetPoint("BOTTOMRIGHT", -8, 6)
	win.endRun:SetScript("OnClick", function()
		local s = HistoryWindow.List()[index]
		if s == ns.Tracker.testSession then
			ns.TestMode.End()
		elseif s == ns.Tracker.session then
			ns.Tracker.End()
		end
		HistoryWindow.Refresh()
	end)
	win.settings = W.Button(win, SETTINGS or "Settings", 90, 22)
	win.settings:SetPoint("BOTTOMRIGHT", -120, 6)
	win.settings:SetScript("OnClick", function() ns.SettingsWindow.Show() end)

	local function refreshIfShown()
		if win:IsShown() then HistoryWindow.Refresh() end
	end
	ns.Listen("DROP_UPDATE", refreshIfShown)
	ns.Listen("SESSION_START", refreshIfShown)
	ns.Listen("SESSION_END", refreshIfShown)
	ns.Listen("WISHLIST_CHANGED", refreshIfShown)
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
		win.sub:SetText("")
		win.empty:SetText("Rolls are recorded while you're in a dungeon or raid.\n\nTry |cffffd100/needy test|r to see Needy in action.")
		win.empty:Show()
		return
	end

	win.heading:SetText(HistoryWindow.SessionLabel(s))
	win.sub:SetText(summaryLine(s))
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

-- The Stats page of the Run Report: totals for the run, then a line per player. Just the numbers, no jokes.
-- Luck is explained in Core/Titles.lua (countLuck).
local _, ns = ...

local StatsPage = {}
ns.StatsPage = StatsPage

local W = ns.Widgets
local GOLD = W.GOLD

local TILE_HEIGHT = 40
local TILE_GAP = 4
local TILES_PER_LINE = 4
local ROW_HEIGHT = 20
local LUCK_TOP = 8 + (TILE_HEIGHT + TILE_GAP) * 2 + 6
local TABLE_TOP = LUCK_TOP + 22
local EVEN = 0.05 -- luck nearer zero than this shows as 0.0
local DASH = "-"

local TILES = {
	{ key = "items", label = "Items rolled" },
	{ key = "needWins", label = "Won by " .. ns.Choices.need.label },
	{ key = "greedWins", label = "Won by " .. ns.Choices.greed.label },
	{ key = "allPassed", label = "All passed" },
	{ key = "rolls", label = "Rolls made" },
	{ key = "average", label = "Average roll" },
	{ key = "high", label = "Highest roll" },
	{ key = "low", label = "Lowest roll" },
}

-- The player's name gets whatever width these leave.
local COLUMNS = {
	{ key = "wins", label = "Won", width = 36 },
	{ key = "luck", label = "Luck", width = 44 },
	{ key = "needs", label = ns.Choices.need.label, width = 38 },
	{ key = "greeds", label = ns.Choices.greed.label, width = 42 },
	{ key = "passes", label = ns.Choices.pass.label, width = 38 },
	{ key = "noRolls", label = "Missed", width = 48 },
	{ key = "average", label = "Avg", width = 38 },
	{ key = "high", label = "High", width = 38 },
	{ key = "low", label = "Low", width = 36 },
}

local function rounded(v)
	return v and tostring(math.floor(v + 0.5)) or DASH
end

-- "+1.2" and its colour.
local function luckText(luck)
	if not luck then return DASH, 0.45, 0.45, 0.45 end
	if math.abs(luck) < EVEN then return "0.0", 0.7, 0.7, 0.7 end
	if luck > 0 then return ("+%.1f"):format(luck), 0.2, 1, 0.2 end
	return ("%.1f"):format(luck), 1, 0.35, 0.35
end

local function yourLuckText(s)
	local luck = s and ns.Titles.Luck(s)
	if not luck then return ("|c%sYour luck: no contested rolls yet.|r"):format(W.GREY_HEX) end
	local text, r, g, b = luckText(luck)
	return ("|c%sYour luck:|r won %d, expected %.1f  |cff%02x%02x%02x%s|r"):format(
		W.GOLD_HEX, s.contestWins, s.expected, r * 255, g * 255, b * 255, text)
end

local function luckTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local s = self.player and self.player.stats
	if s then
		GameTooltip:SetText(ns.ColorName(self.player.name, s.class), 1, 1, 1)
		if s.contests > 0 then
			local text, r, g, b = luckText(ns.Titles.Luck(s))
			GameTooltip:AddDoubleLine("Won", tostring(s.contestWins))
			GameTooltip:AddDoubleLine("Expected", ("%.1f"):format(s.expected))
			GameTooltip:AddDoubleLine("Luck", text, nil, nil, nil, r, g, b)
		else
			GameTooltip:AddLine("Never in with a chance, so no luck to judge.", nil, nil, nil, true)
		end
	else
		GameTooltip:SetText("Luck", 1, 1, 1)
		GameTooltip:AddLine("Items won, compared with what even odds would give. One of three people needing "
			.. "expects a third of the item. Greeding on something another player needed doesn't count against you.",
			nil, nil, nil, true)
	end
	GameTooltip:Show()
end

local function createTile(page, label, i, width)
	local tile = W.Card(page)
	tile:SetSize(width, TILE_HEIGHT)
	local col, line = (i - 1) % TILES_PER_LINE, math.floor((i - 1) / TILES_PER_LINE)
	tile:SetPoint("TOPLEFT", 6 + col * (width + TILE_GAP), -8 - line * (TILE_HEIGHT + TILE_GAP))
	tile.value = W.Text(tile, "GameFontHighlightLarge")
	tile.value:SetPoint("TOP", 0, -5)
	tile.label = W.Text(tile, "GameFontNormalSmall")
	tile.label:SetPoint("BOTTOM", 0, 5)
	tile.label:SetWidth(width - 6)
	tile.label:SetJustifyH("CENTER")
	tile.label:SetWordWrap(false)
	tile.label:SetText(label)
	return tile
end

-- A line of the table, also used for its header.
local function createLine(parent, width, font)
	local line = CreateFrame("Frame", nil, parent)
	line:SetSize(width, ROW_HEIGHT)
	line.cells = {}
	local x = width
	for i = #COLUMNS, 1, -1 do
		local col = COLUMNS[i]
		x = x - col.width
		local cell = W.Text(line, font)
		cell:SetPoint("LEFT", x, 0)
		cell:SetWidth(col.width)
		cell:SetJustifyH("CENTER")
		cell:SetWordWrap(false)
		line.cells[i] = cell
	end
	line.name = W.Text(line, font)
	line.name:SetPoint("LEFT", 4, 0)
	line.name:SetWidth(x - 6)
	line.name:SetWordWrap(false)
	line:EnableMouse(true)
	line:SetScript("OnEnter", luckTooltip)
	line:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return line
end

-- Most wins first, then most needs, then most greeds.
local function sortedPlayers(stats)
	local list = {}
	for name, s in pairs(stats) do
		table.insert(list, { name = name, stats = s })
	end
	table.sort(list, function(a, b)
		local x, y = a.stats, b.stats
		if x.wins ~= y.wins then return x.wins > y.wins end
		if x.needs ~= y.needs then return x.needs > y.needs end
		if x.greeds ~= y.greeds then return x.greeds > y.greeds end
		return a.name < b.name
	end)
	return list
end

local function setRow(row, player, i)
	local s = player.stats
	row.player = player
	row.name:SetText(ns.ColorName(player.name, s.class))
	for c, col in ipairs(COLUMNS) do
		local cell = row.cells[c]
		if col.key == "luck" then
			local text, r, g, b = luckText(ns.Titles.Luck(s))
			cell:SetText(text)
			cell:SetTextColor(r, g, b)
		else
			local v
			if col.key == "average" then
				v = s.rollCount > 0 and s.rollSum / s.rollCount or nil
			else
				v = s[col.key]
			end
			cell:SetText(rounded(v))
			if v == nil or v == 0 then
				cell:SetTextColor(0.45, 0.45, 0.45) -- fade the blanks so the numbers stand out
			else
				cell:SetTextColor(1, 1, 1)
			end
		end
	end
	if s.isSelf then
		row.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
	else
		row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
	end
end

-- Builds the page inside `parent`; `width` is the room for its content.
function StatsPage.Create(parent, width)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()

	page.tiles = {}
	local tileWidth = (width - (TILES_PER_LINE - 1) * TILE_GAP) / TILES_PER_LINE
	for i, def in ipairs(TILES) do
		page.tiles[def.key] = createTile(page, def.label, i, tileWidth)
	end

	page.yourLuck = W.Text(page, "GameFontHighlightSmall")
	page.yourLuck:SetPoint("TOPLEFT", 10, -LUCK_TOP)
	page.yourLuck:SetWidth(width - 8)
	page.yourLuck:SetWordWrap(false)

	local head = createLine(page, width, "GameFontNormalSmall")
	head:SetPoint("TOPLEFT", 6, -TABLE_TOP)
	head.name:SetText(PLAYER or "Player")
	for i, col in ipairs(COLUMNS) do head.cells[i]:SetText(col.label) end
	local rule = W.Hairline(head)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")

	page.scroll, page.list = W.ScrollArea(page)
	page.scroll:SetPoint("TOPLEFT", 6, -(TABLE_TOP + ROW_HEIGHT + 2))
	page.scroll:SetPoint("BOTTOMRIGHT", -14, 22)

	page.empty = W.Text(page, "GameFontDisable")
	page.empty:SetPoint("CENTER", page.scroll, "CENTER")
	page.empty:SetText("No finished rolls yet.")

	page.note = W.Text(page, "GameFontDisableSmall")
	page.note:SetPoint("BOTTOMLEFT", 10, 7)

	page.rows = {}
	function page:SetSession(session)
		local totals, stats = ns.Titles.Totals(session)
		for key, tile in pairs(self.tiles) do
			tile.value:SetText(rounded(totals[key]))
		end

		local mine
		for _, s in pairs(stats) do
			if s.isSelf then mine = s end
		end
		self.yourLuck:SetText(yourLuckText(mine))
		for _, row in ipairs(self.rows) do row:Hide() end
		local players = sortedPlayers(stats)
		for i, player in ipairs(players) do
			local row = self.rows[i]
			if not row then
				row = createLine(self.list, width, "GameFontHighlightSmall")
				row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
				row.bg = row:CreateTexture(nil, "BACKGROUND")
				row.bg:SetAllPoints()
				self.rows[i] = row
			end
			setRow(row, player, i)
			row:Show()
		end
		self.list:SetSize(width, math.max(1, #players * ROW_HEIGHT))
		self.empty:SetShown(#players == 0)

		local open = totals.unfinished
		self.note:SetText(open > 0 and ("%d unfinished %s not counted."):format(open, open == 1 and "roll" or "rolls") or "")
		self.scroll.UpdateThumb()
	end

	return page
end

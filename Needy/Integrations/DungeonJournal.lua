-- Optional hook into DungeonJournal (folder ForeverDungeonJournal, by Exehn): a Needy Wishlist entry on the
-- right-click menu of its loot, and a mark on items that are on the list.
-- Written against DungeonJournal 2.1.3. It only post-hooks functions on that addon's shared table, and does
-- nothing if they aren't there.
--   ShowItemFavouriteMenu(owner, item, dungeon, boss, quest) opens the menu; item = { id, name, slot,
--     quality }, with item.from = { { id, name, boss }, ... } for an item combined from drops.
--   UpdateFavouriteIndicator(row, itemID) runs whenever an item row is filled in.
--   Its item tooltip is the game's (SetHyperlink on GameTooltip), so the game's item-tooltip callback adds
--     who else wants the item, on its loot rows only.
--   DB[dungeon].bosses[i] = { name, recipeTab, loot = { item, ... } }, with ORDER listing the dungeons; read
--     to say where an item on the list drops.
local _, ns = ...

local DungeonJournal = {}
ns.DungeonJournal = DungeonJournal

local W = ns.Widgets

-- Its menu is one 22px button with 4px round it.
local BUTTON_HEIGHT = 22
local MENU_PAD = 4
local MENU_WIDTH = 190
local MARK_SIZE = 14
local MAX_NAMES = 6 -- per line; the rest are counted

local hooked -- its table, once hooked
local sources -- itemID -> where it drops, built on first use
local entry -- our button on its menu
local marked = setmetatable({}, { __mode = "k" }) -- row -> itemID

local function createEntry(menu, theirs)
	local b = CreateFrame("Button", nil, menu)
	b:SetHeight(BUTTON_HEIGHT)
	b:SetPoint("TOPLEFT", theirs, "BOTTOMLEFT", 0, -MENU_PAD)
	b:SetPoint("TOPRIGHT", theirs, "BOTTOMRIGHT", 0, -MENU_PAD)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b.mark = b:CreateTexture(nil, "ARTWORK")
	b.mark:SetTexture(ns.Wishlist.MARK)
	b.mark:SetSize(MARK_SIZE, MARK_SIZE)
	b.mark:SetPoint("LEFT", 8, 0)
	b.text = W.Text(b, "GameFontHighlight")
	b.text:SetPoint("LEFT", b.mark, "RIGHT", 5, 0)
	b.text:SetWordWrap(false)
	return b
end

local function partsOf(item)
	if type(item.from) ~= "table" then return nil end
	local parts = {}
	for _, part in ipairs(item.from) do
		local id = type(part) == "table" and tonumber(part[1])
		if id and id > 0 then table.insert(parts, id) end
	end
	return parts
end

-- Runs after the menu has opened. It's one shared menu, so it's laid out afresh each time.
local function extendMenu(journal, item, quest)
	local menu = journal.favouriteContextMenu
	local theirs = menu and menu.button
	if not theirs or not menu:IsShown() or type(item) ~= "table" then return end
	local id = tonumber(item[1])
	local offer = id ~= nil and id > 0 and quest == nil -- quest rewards are never rolled for
	if not offer then
		if entry then
			entry:Hide()
			menu:SetSize(MENU_WIDTH, BUTTON_HEIGHT + 2 * MENU_PAD)
		end
		return
	end

	entry = entry or createEntry(menu, theirs)
	entry.text:SetText(ns.Wishlist.Has(id) and "Remove from Needy Wishlist" or "Add to Needy Wishlist")
	entry:SetScript("OnClick", function()
		ns.Wishlist.Toggle(id, type(item[2]) == "string" and item[2] or nil, partsOf(item))
		if journal.HideItemFavouriteMenu then journal.HideItemFavouriteMenu() else menu:Hide() end
	end)
	entry:Show()

	-- Grow the menu itself rather than hang below it: it closes on clicks outside its own rectangle.
	theirs:ClearAllPoints()
	theirs:SetPoint("TOPLEFT", MENU_PAD, -MENU_PAD)
	theirs:SetPoint("TOPRIGHT", -MENU_PAD, -MENU_PAD)
	theirs:SetHeight(BUTTON_HEIGHT)
	menu:SetSize(math.max(MENU_WIDTH, W.StringWidth(entry.text) + MARK_SIZE + 32), 2 * BUTTON_HEIGHT + 3 * MENU_PAD)
end

local function showMark(row)
	if row.needyMark then row.needyMark:SetShown(ns.Wishlist.Has(marked[row])) end
end

local function markRow(row, itemID)
	if not row or not row.CreateTexture then return end
	if not row.needyMark then
		local mark = row:CreateTexture(nil, "OVERLAY", nil, 7)
		mark:SetTexture(ns.Wishlist.MARK)
		mark:SetSize(MARK_SIZE, MARK_SIZE)
		mark:SetPoint("CENTER", row.icon or row, "TOPLEFT", 3, -3)
		row.needyMark = mark
	end
	marked[row] = tonumber(itemID) or 0
	showMark(row)
end

local function localDungeon(name)
	if type(hooked.LocalizeDungeonName) == "function" then
		local ok, text = pcall(hooked.LocalizeDungeonName, name)
		if ok and type(text) == "string" then return text end
	end
	return name
end

local function addSource(item, dungeon, boss)
	local id = tonumber(item[1])
	if not id or id <= 0 then return end
	local s = sources[id]
	-- An item's boss counts for more than the Recipes & Patterns page that lists it again.
	local recipePage = boss.recipeTab and true or false
	if not s or (s.recipePage and not recipePage) then
		s = { dungeon = dungeon, boss = boss.name, recipePage = recipePage, quality = tonumber(item[4]), seen = {}, count = 0 }
		sources[id] = s
	elseif recipePage ~= s.recipePage then
		return
	end
	local key = dungeon .. "/" .. boss.name
	if not s.seen[key] then
		s.seen[key] = true
		s.count = s.count + 1
	end
end

local function addDungeon(name, data)
	if type(name) ~= "string" or type(data) ~= "table" or type(data.bosses) ~= "table" then return end
	for _, boss in ipairs(data.bosses) do
		if type(boss) == "table" and type(boss.name) == "string" and type(boss.loot) == "table" then
			for _, item in ipairs(boss.loot) do
				if type(item) == "table" then
					addSource(item, name, boss)
					if type(item.makes) == "table" then addSource(item.makes, name, boss) end
				end
			end
		end
	end
end

local function buildSources()
	sources = {}
	local db = hooked.DB
	if type(db) ~= "table" then return end
	local done = {}
	-- Its own order first, so the source named for an item is the same every time.
	for _, name in ipairs(type(hooked.ORDER) == "table" and hooked.ORDER or {}) do
		done[name] = true
		addDungeon(name, db[name])
	end
	for name, data in pairs(db) do
		if not done[name] then addDungeon(name, data) end
	end
end

function DungeonJournal.IsHooked()
	return hooked ~= nil
end

-- Where an item drops, as { text, quality }; nil if DungeonJournal can't say.
function DungeonJournal.Source(id)
	if not hooked then return nil end
	if not sources then buildSources() end
	local s = sources[id]
	if not s then return nil end
	local text = ("%s - %s"):format(localDungeon(s.dungeon), s.boss)
	if s.count > 1 then text = ("%s (+%d more)"):format(text, s.count - 1) end
	return { text = text, quality = s.quality }
end

local function nameList(people)
	local names = {}
	for i = 1, math.min(#people, MAX_NAMES) do
		names[i] = ns.ColorName(people[i].name, people[i].class)
	end
	local text = table.concat(names, ", ")
	if #people > MAX_NAMES then
		text = text .. ("  |c%s+%d more|r"):format(W.GREY_HEX, #people - MAX_NAMES)
	end
	return text
end

-- Group members and guildmates (with Needy) who have the hovered loot row's item on their wishlist.
local function addWanters(tooltip)
	local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
	local id = owner and marked[owner]
	if not id or id <= 0 then return end
	local who = ns.Sharing.WhoWants(id)
	if #who.group == 0 and #who.guild == 0 then return end
	tooltip:AddLine(" ")
	tooltip:AddLine(("|T%s:12:12|t Wanted by"):format(ns.Wishlist.MARK), W.GOLD[1], W.GOLD[2], W.GOLD[3])
	if #who.group > 0 then
		tooltip:AddLine(("|c%sGroup:|r %s"):format(W.GREY_HEX, nameList(who.group)), 1, 1, 1, true)
	end
	if #who.guild > 0 then
		tooltip:AddLine(("|c%sGuild:|r %s"):format(W.GREY_HEX, nameList(who.guild)), 1, 1, 1, true)
	end
end

local function hookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addWanters)
	elseif GameTooltip then
		hooksecurefunc(GameTooltip, "SetHyperlink", addWanters)
	end
end

-- Called at login, when every addon has loaded. Returns whether the hook went in.
function DungeonJournal.Init()
	local journal = _G.ForeverDungeonJournal_NS
	if type(journal) ~= "table" or not hooksecurefunc then return false end
	if type(journal.ShowItemFavouriteMenu) ~= "function" then
		ns.Debug("DungeonJournal found, but not the menu Needy hooks")
		return false
	end
	hooksecurefunc(journal, "ShowItemFavouriteMenu", function(_, item, _, _, quest)
		extendMenu(journal, item, quest)
	end)
	hooked = journal
	if type(journal.UpdateFavouriteIndicator) == "function" then
		hooksecurefunc(journal, "UpdateFavouriteIndicator", markRow)
		ns.Listen("WISHLIST_CHANGED", function()
			for row in pairs(marked) do showMark(row) end
		end)
		hookTooltips()
	end
	return true
end

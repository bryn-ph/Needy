-- The items this character wants. Integrations add to it (see Integrations/DungeonJournal.lua); roll bars
-- light up and a fanfare plays when one comes up for a roll. Getting one during a run (winning its roll, or
-- looting it outright) takes it off, unless the removeOnLoot setting is off. Test rolls never do.
local _, ns = ...

local Wishlist = {}
ns.Wishlist = Wishlist

-- A crimson heart with a gold rim, in the logo's colours (tools/gen_icon.py). Not dice: those mean Need.
Wishlist.MARK = "Interface\\AddOns\\" .. ns.name .. "\\Media\\mark"
-- The heart's red and gold, for tags and badges that go with it.
Wishlist.RED = { 0.62, 0.1, 0.12 }
Wishlist.RIM = { 0.86, 0.66, 0.22 }

local SOUND_GAP = 1 -- seconds: items dropping together get one fanfare

local items -- itemID -> { name, parts = { itemID, ... } for an item that's combined from drops }
local lastSound

local function validID(id)
	return type(id) == "number" and id > 0
end

local function cleanItems(saved)
	local out = {}
	if type(saved) ~= "table" then return out end
	for id, entry in pairs(saved) do
		if validID(id) and type(entry) == "table" then
			local parts
			if type(entry.parts) == "table" then
				for _, part in ipairs(entry.parts) do
					if validID(part) then
						parts = parts or {}
						table.insert(parts, part)
					end
				end
			end
			out[id] = { name = type(entry.name) == "string" and entry.name or nil, parts = parts }
		end
	end
	return out
end

-- When the list last changed. Never goes backwards, and moves on every change.
local function touch()
	NeedyCharDB.wishlistRev = math.max(time(), Wishlist.Rev() + 1)
end

function Wishlist.Rev()
	local rev = NeedyCharDB and NeedyCharDB.wishlistRev
	return type(rev) == "number" and rev or 0
end

-- Something about what we share changed without the list changing (the share setting).
function Wishlist.Touch()
	touch()
	ns.Fire("WISHLIST_CHANGED")
end

function Wishlist.Has(id)
	return validID(id) and items[id] ~= nil
end

-- Adds the item, or takes it off. parts: for an item that's combined, the drops it's made from.
function Wishlist.Toggle(id, name, parts)
	if not validID(id) then return end
	if items[id] then
		items[id] = nil
	else
		items[id] = { name = name, parts = parts and #parts > 0 and parts or nil }
	end
	touch()
	ns.Fire("WISHLIST_CHANGED")
end

function Wishlist.Clear()
	for id in pairs(items) do items[id] = nil end
	touch()
	ns.Fire("WISHLIST_CHANGED")
end

-- { { id, name, parts }, ... } by name.
function Wishlist.List()
	local list = {}
	for id, entry in pairs(items) do
		table.insert(list, { id = id, name = entry.name or ("Item " .. id), parts = entry.parts })
	end
	table.sort(list, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return list
end

-- Is this roll or recorded drop for a wanted item, or a piece of one? (.wishlisted forces it.)
function Wishlist.Matches(roll)
	if roll.wishlisted then return true end
	local id = ns.ItemIDFromLink(roll.link)
	if not id then return false end
	if items[id] then return true end
	for _, entry in pairs(items) do
		for _, part in ipairs(entry.parts or {}) do
			if part == id then return true end
		end
	end
	return false
end

-- You got an item: off the list it comes, if it's on it. link is for the message.
function Wishlist.Got(id, link)
	if not ns.settings.removeOnLoot or not validID(id) or not items[id] then return end
	items[id] = nil
	touch()
	ns.Print(("Got %s, so it's off your wishlist."):format(link or ("item " .. id)))
	ns.Fire("WISHLIST_CHANGED")
end

-- You won a real roll in a run.
local function onDrop(drop)
	if drop.isTest or not ns.Tracker.session or not drop.winner or ns.IsSecret(drop.winner) then return end
	if ns.IsMe(drop.winner, drop.rolls and drop.rolls[drop.winner]) then
		Wishlist.Got(ns.ItemIDFromLink(drop.link), drop.link)
	end
end

-- The game's own "You receive loot: [item]" lines, as patterns, for items looted without a roll.
local function selfLootPatterns()
	local out = {}
	for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
		local fmt = _G[key]
		if type(fmt) == "string" then
			local p = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
			table.insert(out, "^" .. p .. "$")
		end
	end
	return out
end

local lootPatterns

local function onLoot(_, msg)
	if not ns.Tracker.session or type(msg) ~= "string" or ns.IsSecret(msg) then return end
	lootPatterns = lootPatterns or selfLootPatterns()
	for _, p in ipairs(lootPatterns) do
		if msg:match(p) then
			local link = msg:match("(|c[^|]*|Hitem:.-|h.-|h|r)") or msg:match("(|Hitem:.-|h.-|h)")
			Wishlist.Got(ns.ItemIDFromLink(link), link)
			return
		end
	end
end

local function playFanfare()
	if not (PlaySound and SOUNDKIT) then return end
	local now = GetTime()
	if lastSound and now - lastSound < SOUND_GAP then return end
	lastSound = now
	-- Master channel, so it's heard with sound effects turned down.
	local sound = SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.RAID_WARNING
	if sound then PlaySound(sound, "Master") end
end

function Wishlist.Init()
	if type(NeedyCharDB) ~= "table" then NeedyCharDB = {} end
	items = cleanItems(NeedyCharDB.wishlist)
	NeedyCharDB.wishlist = items
	ns.Listen("ROLL_START", function(roll)
		if ns.settings.wishlistSound and Wishlist.Matches(roll) then playFanfare() end
	end)
	ns.Listen("DROP_UPDATE", onDrop)
	ns.On("CHAT_MSG_LOOT", onLoot)
end

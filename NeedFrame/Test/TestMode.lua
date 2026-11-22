-- Fake rolls and a fake party, so the whole addon can be tried out of an instance.
-- Everything goes through the same messages as real loot (ROLL_START, DROP_UPDATE, ...).
local _, ns = ...

local TestMode = {}
ns.TestMode = TestMode

local ROLL_SECONDS = 30

-- Well-known items that exist in the retail item database; loaded on demand so links/tooltips are real.
local ITEMS = {
	19019, 17182, 18832, 19137, 18814, 19347, 13340, 22691, 32837, 13335, 12640, 11815, 2589, 3577,
}

local NAMES = {
	"Grimbolt", "Lunaria", "Thistlewick", "Brakka", "Sundrel", "Mossjaw", "Velith", "Pipwhistle",
	"Korvash", "Elowyn", "Dribbles", "Hammerjaw", "Saffi", "Nyxie", "Tumblebrew", "Orrik",
}

local CLASSES = {
	"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
	"DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER",
}

-- Choice weights. rollMax < 100 makes someone reliably unlucky.
local PROFILES = {
	normal = { need = 35, greed = 40, pass = 20, none = 5 },
	hoarder = { need = 85, greed = 5, pass = 10 },
	saint = { pass = 85, greed = 15 },
	goblin = { greed = 80, need = 10, pass = 10, rollMax = 45 },
	sleepy = { none = 55, greed = 25, pass = 20 },
}

local nextID = -1
local drops = {} -- fake rollID -> drop
local party = nil -- { {name, class, profile}, ... } including the player

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function makeParty(profiles)
	local names, classes = shuffle({ unpack(NAMES) }), shuffle({ unpack(CLASSES) })
	local p = { { name = ns.PlayerName(), class = ns.PlayerClass(), profile = "normal", isSelf = true } }
	for i, profile in ipairs(profiles) do
		table.insert(p, { name = names[i], class = classes[i], profile = profile })
	end
	return p
end

local function pickChoice(member, canNeed)
	local weights = PROFILES[member.profile] or PROFILES.normal
	local options = {}
	local total = 0
	for _, c in ipairs({ "need", "greed", "pass", "none" }) do
		local w = weights[c] or 0
		if c == "need" and not canNeed then w = 0 end
		if w > 0 then
			total = total + w
			table.insert(options, { c, total })
		end
	end
	local x = math.random() * total
	for _, o in ipairs(options) do
		if x <= o[2] then return o[1] end
	end
	return "pass"
end

local function rollFor(member)
	local weights = PROFILES[member.profile] or PROFILES.normal
	return math.random(1, weights.rollMax or 100)
end

local function memberByName(name)
	for _, m in ipairs(party or {}) do
		if m.name == name then return m end
	end
end

-- Decide rolls and a winner, like the server does when everyone has chosen.
local function resolveDrop(drop)
	local best
	for name, r in pairs(drop.rolls) do
		if ns.IsRollChoice(r.choice) then
			r.roll = rollFor(memberByName(name) or {})
			local tier = ns.CHOICE_TIER[r.choice]
			if not best or tier > best.tier or (tier == best.tier and r.roll > best.roll) then
				best = { name = name, tier = tier, roll = r.roll, class = r.class }
			end
		end
	end
	if best then
		drop.winner, drop.winnerClass = best.name, best.class
	else
		drop.allPassed = true
	end
	drop.done = true
end

-- Items -------------------------------------------------------------------------------------------

local function fallbackInfo(itemID)
	return { itemID = itemID, name = "Suspiciously Shiny Test Item", quality = 4, texture = ns.FALLBACK_ICON }
end

-- callback(info) once the item is loaded (or after 3s with a stand-in).
local function loadItem(itemID, callback)
	local done = false
	local function finish(info)
		if done then return end
		done = true
		callback(info)
	end
	if not (Item and Item.CreateFromItemID) then
		finish(fallbackInfo(itemID))
		return
	end
	local item = Item:CreateFromItemID(itemID)
	if item:IsItemEmpty() then
		finish(fallbackInfo(itemID))
		return
	end
	item:ContinueOnItemLoad(function()
		local equipLoc = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(itemID))
		finish({
			itemID = itemID,
			name = item:GetItemName(),
			link = item:GetItemLink(),
			quality = item:GetItemQuality(),
			texture = item:GetItemIcon(),
			equippable = equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE",
		})
	end)
	C_Timer.After(3, function() finish(fallbackInfo(itemID)) end)
end

local function loadItems(count, callback)
	local ids = shuffle({ unpack(ITEMS) })
	local infos, pending = {}, count
	for i = 1, count do
		local id = ids[((i - 1) % #ids) + 1]
		loadItem(id, function(info)
			infos[i] = info
			pending = pending - 1
			if pending == 0 then callback(infos) end
		end)
	end
end

-- Live test rolls -------------------------------------------------------------------------------

local function fire(drop)
	ns.Fire("DROP_UPDATE", drop)
end

local function maybeResolve(drop)
	if drop.done then return end
	for _, r in pairs(drop.rolls) do
		if r.choice == "none" then return end
	end
	resolveDrop(drop)
	fire(drop)
end

local function timeout(drop)
	if drop.done then return end
	local roll = ns.LootSource.Get(drop.rollID)
	if roll and not roll.closed then
		ns.LootSource.Close(drop.rollID)
	end
	resolveDrop(drop)
	fire(drop)
end

local function startRoll(info)
	local id = nextID
	nextID = nextID - 1
	local canNeed = math.random() < 0.8
	local roll = {
		id = id, isTest = true,
		rollTime = ROLL_SECONDS * 1000, endsAt = GetTime() + ROLL_SECONDS,
		texture = info.texture, name = info.name, count = 1, quality = info.quality,
		bop = (info.quality or 0) >= 4, canNeed = canNeed, canGreed = true,
		reasonNeed = not canNeed and 1 or nil,
		link = info.link,
	}
	local drop = {
		key = "test:" .. id, rollID = id, isTest = true,
		link = info.link, name = info.name, texture = info.texture, quality = info.quality,
		encounterName = "Test Boss",
		rolls = {},
	}
	for _, m in ipairs(party) do
		drop.rolls[m.name] = { choice = "none", class = m.class }
	end
	drops[id] = drop

	ns.LootSource.AddFake(roll)
	fire(drop)

	for _, m in ipairs(party) do
		if not m.isSelf then
			C_Timer.After(1 + math.random() * 5, function()
				if drop.done then return end
				local c = pickChoice(m, true)
				-- "none" here means they let it time out; leave it unset until the timer runs out.
				if c == "none" then return end
				drop.rolls[m.name].choice = c
				fire(drop)
				maybeResolve(drop)
			end)
		end
	end
	C_Timer.After(ROLL_SECONDS, function() timeout(drop) end)
end

-- /nf test: start (or add to) a live test run with a fake party.
function TestMode.Start(count)
	if not ns.Tracker.testSession then
		party = makeParty({ "normal", "hoarder", "saint", "goblin" })
		ns.Tracker.testSession = ns.Tracker.NewSession({
			isTest = true, instanceName = "Test Run", difficultyName = "Fake party",
		})
		ns.Fire("SESSION_START", ns.Tracker.testSession)
		local names = {}
		for _, m in ipairs(party) do
			if not m.isSelf then table.insert(names, ns.ColorName(m.name, m.class)) end
		end
		ns.Print("Test run started with " .. table.concat(names, ", ") .. ". Roll away, then |cffffd100/nf test end|r.")
	end
	loadItems(count or 3, function(infos)
		for _, info in ipairs(infos) do
			startRoll(info)
		end
	end)
end

-- The player clicked a button on a fake roll (via LootSource.Choose).
function TestMode.Choose(roll, choice)
	local drop = drops[roll.id]
	if not drop or drop.done then return end
	drop.rolls[ns.PlayerName()].choice = choice
	ns.LootSource.Close(roll.id)
	fire(drop)
	maybeResolve(drop)
end

-- /nf test end
function TestMode.End()
	local s = ns.Tracker.testSession
	if not s then
		ns.Print("No test run in progress. |cffffd100/nf test|r starts one.")
		return
	end
	for id, drop in pairs(drops) do
		if not drop.done then timeout(drop) end
		drops[id] = nil
	end
	ns.Tracker.testSession = nil
	party = nil
	ns.Tracker.Finish(s)
end

-- /nf test run: a whole fake dungeon in one go, with a party built to earn every title.
function TestMode.Run(dropCount)
	dropCount = dropCount or 12
	local runParty = makeParty({ "hoarder", "saint", "goblin", "sleepy", "normal" })
	ns.Print("Simulating a run...")
	loadItems(dropCount, function(infos)
		local prevParty = party
		party = runParty
		local s = ns.Tracker.NewSession({
			isTest = true, instanceName = "Test Run: Simulated Dungeon", difficultyName = "Heroic",
		})
		local t = time() - dropCount * 150
		s.startTime = t
		for i, info in ipairs(infos) do
			local drop = {
				key = "testrun:" .. i, isTest = true, link = info.link, name = info.name,
				texture = info.texture, quality = info.quality, rolls = {},
			}
			local canNeed = math.random() < 0.85
			for _, m in ipairs(runParty) do
				drop.rolls[m.name] = { choice = pickChoice(m, canNeed), class = m.class }
			end
			resolveDrop(drop)
			local d = ns.Tracker.RecordDrop(s, drop)
			d.time = t + i * 150
		end
		party = prevParty
		ns.Tracker.Finish(s)
	end)
end

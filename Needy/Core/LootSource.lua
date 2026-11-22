-- Turns the game's loot roll API + C_LootHistory into Needy messages (see Core/Init.lua).
-- Checked against Gethe/wow-ui-source "forever": Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua
-- and Blizzard_APIDocumentationGenerated/LootHistoryDocumentation.lua.
local _, ns = ...

local LootSource = {}
ns.LootSource = LootSource

local rolls = {} -- rollID -> roll

-- Enum.EncounterLootDropRollState: NeedMainSpec=0, NeedOffSpec=1, Transmog=2, Greed=3, NoRoll=4, Pass=5
-- WoW: Forever has no transmog rolls; should the state ever turn up, count it as greed.
local STATE_CHOICE = { [0] = "need", [1] = "need", [2] = "greed", [3] = "greed", [4] = "none", [5] = "pass" }

local function choiceForState(state)
	local e = Enum and Enum.EncounterLootDropRollState
	if e then
		if state == e.NeedMainSpec or state == e.NeedOffSpec then return "need" end
		if state == e.Greed or state == e.Transmog then return "greed" end
		if state == e.Pass then return "pass" end
		if state == e.NoRoll then return "none" end
	end
	return STATE_CHOICE[state] or "none"
end

function LootSource.Get(rollID)
	return rolls[rollID]
end

function LootSource.All()
	return rolls
end

-- Live rolls --------------------------------------------------------------------------

local function readRoll(rollID, rollTime)
	if not GetLootRollItemInfo then return nil end
	local ok, texture, name, count, quality, bindOnPickUp, canNeed, canGreed, _canDisenchant,
		reasonNeed, reasonGreed = pcall(GetLootRollItemInfo, rollID)
	if not ok or name == nil or ns.IsSecret(name) then return nil end
	local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
	if ns.IsSecret(link) then link = nil end
	if not rollTime and C_Loot and C_Loot.GetLootRollDuration then
		rollTime = C_Loot.GetLootRollDuration(rollID)
	end
	return {
		id = rollID,
		rollTime = rollTime or 60000, -- milliseconds, like GetLootRollTimeLeft
		texture = texture, name = name, count = count or 1, quality = quality,
		bop = bindOnPickUp, canNeed = canNeed, canGreed = canGreed,
		reasonNeed = reasonNeed, reasonGreed = reasonGreed,
		link = link,
	}
end

local function startRoll(rollID, rollTime, attempt)
	if rolls[rollID] then return end
	local roll = readRoll(rollID, rollTime)
	if not roll then
		-- Item data can lag a frame behind the event; try a couple more times.
		attempt = (attempt or 0) + 1
		if attempt <= 5 then
			C_Timer.After(0.2, function() startRoll(rollID, rollTime, attempt) end)
		end
		return
	end
	rolls[rollID] = roll
	ns.Debug("roll start", rollID, roll.link or roll.name)
	ns.Fire("ROLL_START", roll)
end

function LootSource.TimeLeft(roll)
	if roll.isTest then
		return math.max(0, (roll.endsAt - GetTime()) * 1000)
	end
	return GetLootRollTimeLeft and GetLootRollTimeLeft(roll.id) or 0
end

-- The player clicked one of the roll buttons.
function LootSource.Choose(roll, choice)
	roll.myChoice = choice
	ns.Fire("ROLL_CHOSEN", roll, choice)
	if roll.isTest then
		ns.TestMode.Choose(roll, choice)
	else
		-- Bind-on-pickup items open Blizzard's CONFIRM_LOOT_ROLL popup; that still works.
		RollOnLoot(roll.id, ns.ROLL_TYPE[choice])
	end
end

-- Test mode registers its fake rolls through here so they follow the same path.
function LootSource.AddFake(roll)
	rolls[roll.id] = roll
	ns.Fire("ROLL_START", roll)
end

function LootSource.Close(rollID)
	if rolls[rollID] then
		rolls[rollID].closed = true
		ns.Fire("ROLL_CLOSED", rollID)
	end
end

function LootSource.Forget(rollID)
	rolls[rollID] = nil
end

-- Loot history (everyone's choices, rolls and the winner) --------------------------------

local encounterNames = {}

local function encounterName(encounterID)
	if encounterNames[encounterID] then return encounterNames[encounterID] end
	local ok, info = pcall(C_LootHistory.GetInfoForEncounter, encounterID)
	if ok and info and info.encounterName and not ns.IsSecret(info.encounterName) then
		encounterNames[encounterID] = info.encounterName
		return info.encounterName
	end
end

-- Normalise one EncounterLootDropInfo into a Needy drop.
function LootSource.NormalizeDrop(encounterID, info)
	if not info or ns.IsSecret(info.itemHyperlink) then return nil end
	local drop = {
		key = ("%s:%s"):format(tostring(encounterID), tostring(info.lootListKey)),
		encounterID = encounterID,
		encounterName = encounterName(encounterID),
		link = info.itemHyperlink,
		allPassed = info.allPassed == true,
		isTied = info.isTied == true,
		rolls = {},
	}
	for _, r in ipairs(info.rollInfos or {}) do
		local name = r.playerName
		if name and not ns.IsSecret(name) then
			local roll = r.roll
			if ns.IsSecret(roll) then roll = nil end
			drop.rolls[name] = {
				choice = choiceForState(r.state),
				roll = type(roll) == "number" and roll or nil,
				class = r.playerClass,
				isSelf = r.isSelf == true,
			}
			if r.isWinner then
				drop.winner = name
				drop.winnerClass = r.playerClass
			end
		end
	end
	if not drop.winner and info.winner and info.winner.playerName and not ns.IsSecret(info.winner.playerName) then
		drop.winner = info.winner.playerName
		drop.winnerClass = info.winner.playerClass
	end
	return drop
end

local function updateDrop(encounterID, lootListKey)
	if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
	if ns.IsSecret(encounterID) or ns.IsSecret(lootListKey) then return end
	local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListKey)
	if not ok then return end
	local drop = LootSource.NormalizeDrop(encounterID, info)
	if drop then
		ns.Fire("DROP_UPDATE", drop)
	end
end

local function updateEncounter(encounterID)
	if not (C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) then return end
	if ns.IsSecret(encounterID) then return end
	local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, encounterID)
	if not ok or type(drops) ~= "table" then return end
	for _, info in ipairs(drops) do
		local drop = LootSource.NormalizeDrop(encounterID, info)
		if drop then
			ns.Fire("DROP_UPDATE", drop)
		end
	end
end

-- Re-read everything the game still remembers (used when resuming after /reload).
function LootSource.Rescan()
	if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then return end
	local ok, infos = pcall(C_LootHistory.GetAllEncounterInfos)
	if not ok or type(infos) ~= "table" then return end
	for _, e in ipairs(infos) do
		updateEncounter(e.encounterID)
	end
end

function LootSource.Init()
	ns.On("START_LOOT_ROLL", function(_, rollID, rollTime)
		startRoll(rollID, rollTime)
	end)
	ns.On("CANCEL_LOOT_ROLL", function(_, rollID)
		LootSource.Close(rollID)
	end)
	ns.On("CANCEL_ALL_LOOT_ROLLS", function()
		for id, roll in pairs(rolls) do
			if not roll.isTest then
				LootSource.Close(id)
			end
		end
	end)
	ns.On("MAIN_SPEC_NEED_ROLL", function(_, rollID, roll, isWinning)
		if ns.IsSecret(roll) then return end
		ns.Fire("ROLL_SELF_RESULT", rollID, roll, isWinning)
	end)
	if C_LootHistory then
		ns.On("LOOT_HISTORY_UPDATE_DROP", function(_, encounterID, lootListKey)
			updateDrop(encounterID, lootListKey)
		end)
		ns.On("LOOT_HISTORY_UPDATE_ENCOUNTER", function(_, encounterID)
			updateEncounter(encounterID)
		end)
	end
	-- Rolls already open when we loaded (e.g. /reload mid-roll).
	ns.On("PLAYER_LOGIN", function()
		if not GetActiveLootRollIDs then return end
		local ok, ids = pcall(GetActiveLootRollIDs)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do
				startRoll(id, nil)
			end
		end
	end)
end

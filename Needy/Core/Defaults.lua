local _, ns = ...

ns.Defaults = {
	replaceBlizzard = true, -- hide Blizzard's roll popups and use ours
	showSummary = true, -- open the awards window when a run ends
	growUp = false, -- stack roll bars upwards from the anchor
	locked = true,
	scale = 1,
	barWidth = 360,
	animations = true, -- dice spin + reveal flash on results, pop-in for new bars
	showLog = true, -- small on-screen list of this run's drops
	logRows = 8,
	logCollapsed = true, -- the Roll Log starts as just its tab
	minimapShow = true,
	minimapAngle = 215,
	keepTestSessions = false, -- save test runs into history
	historyLimit = 20,
}

ns.Limits = {
	scale = { 0.5, 2 },
	barWidth = { 280, 560 },
	historyLimit = { 1, 100 },
	logRows = { 3, 20 },
	minimapAngle = { 0, 360 },
}

-- Roll choices ------------------------------------------------------------------------

-- RollOnLoot roll types (Blizzard GroupLootFrame.xml: Pass id=0, Need id=1, Greed id=2).
-- The client also has Transmog (id=4), but WoW: Forever never offers transmog rolls.
ns.ROLL_TYPE = { pass = 0, need = 1, greed = 2 }

-- Priority when deciding a winner: need beats greed.
ns.CHOICE_TIER = { need = 2, greed = 1 }

ns.Choices = {
	need = { label = NEED or "Need", atlas = "lootroll-icon-need", button = "lootroll-toast-icon-need" },
	greed = { label = GREED or "Greed", atlas = "lootroll-icon-greed", button = "lootroll-toast-icon-greed" },
	pass = { label = PASS or "Pass", atlas = "lootroll-icon-pass", button = "lootroll-toast-icon-pass" },
	none = { label = "No roll" },
}

function ns.IsRollChoice(choice)
	return ns.CHOICE_TIER[choice] ~= nil
end

function ns.ChoiceIcon(choice, size)
	local info = ns.Choices[choice]
	if not (info and info.atlas) then return "" end
	size = size or 14
	return ("|A:%s:%d:%d|a"):format(info.atlas, size, size)
end

-- Colours ---------------------------------------------------------------------------

function ns.QualityColor(quality)
	quality = quality or 1
	local data = ColorManager and ColorManager.GetColorDataForItemQuality and ColorManager.GetColorDataForItemQuality(quality)
	if data then
		return data.r, data.g, data.b
	end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

function ns.ClassHex(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.colorStr then
		return c.colorStr
	end
	return "ffcccccc"
end

-- "Name-Realm" -> "Name" for display.
function ns.ShortName(name)
	if not name then return "?" end
	if Ambiguate then
		return Ambiguate(name, "short")
	end
	return (name:gsub("%-.*$", ""))
end

function ns.ColorName(name, classFile)
	return ("|c%s%s|r"):format(ns.ClassHex(classFile), ns.ShortName(name))
end

-- Misc ------------------------------------------------------------------------------

ns.FALLBACK_ICON = 134400 -- question mark

function ns.CropIcon(tex)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

function ns.ItemIDFromLink(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

function ns.PlayerName()
	local name = UnitName("player")
	return name
end

function ns.PlayerClass()
	local _, classFile = UnitClass("player")
	return classFile
end

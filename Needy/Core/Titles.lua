-- End-of-run awards. Pure data + maths over a session, no UI, so it's easy to tweak and to test offline.
local _, ns = ...

local Titles = {}
ns.Titles = Titles

local function icon(name)
	return "Interface\\Icons\\" .. name
end

-- Each title: value(stats) returns a number (or nil if the player doesn't qualify), pick = "max"/"min",
-- min/max thresholds on that number, and text(value, stats) for the blurb.
-- title may be a function(value) so one award can change name at the extremes.
Titles.List = {
	{
		key = "hoarder", title = "Loot Hoarder", icon = icon("INV_Misc_Bag_08"),
		value = function(s) return s.needs end, pick = "max", min = 2,
		text = function(v) return ("Needed %d times"):format(v) end,
	},
	{
		key = "unlucky", title = "Unlucky", icon = icon("Spell_Shadow_GatherShadows"),
		value = function(s) return s.losses end, pick = "max", min = 2,
		text = function(v) return ("Lost %d rolls"):format(v) end,
	},
	{
		key = "golden", title = "Golden Hands", icon = icon("INV_Misc_Coin_02"),
		value = function(s) return s.wins end, pick = "max", min = 2,
		text = function(v) return ("Walked away with %d items"):format(v) end,
	},
	{
		key = "saint", title = "The Saint", icon = icon("Spell_Holy_HolyBolt"),
		value = function(s) return s.passes end, pick = "max", min = 3,
		text = function(v) return ("Passed %d times"):format(v) end,
	},
	{
		key = "goblin", title = "Greedy Goblin", icon = icon("INV_Misc_Coin_17"),
		value = function(s) return s.greeds end, pick = "max", min = 3,
		text = function(v) return ("Greeded %d times"):format(v) end,
	},
	{
		key = "bridesmaid", title = "Always the Bridesmaid", icon = icon("INV_Misc_Flower_02"),
		value = function(s) return s.seconds end, pick = "max", min = 2,
		text = function(v) return ("Came second %d times"):format(v) end,
	},
	{
		key = "asleep", title = "Asleep at the Wheel", icon = icon("Spell_Nature_Sleep"),
		value = function(s) return s.noRolls end, pick = "max", min = 2,
		text = function(v) return ("Let %d rolls time out"):format(v) end,
	},
	{
		key = "high", icon = icon("INV_Misc_Dice_01"),
		title = function(v) return v == 100 and "Natural 100" or "High Roller" end,
		value = function(s) return s.high end, pick = "max", min = 90,
		text = function(v) return ("Rolled a %d"):format(v) end,
	},
	{
		key = "low", icon = icon("INV_Misc_Dice_02"),
		title = function(v) return v == 1 and "Critical Fail" or "Snake Eyes" end,
		value = function(s) return s.low end, pick = "min", max = 10,
		text = function(v) return ("Rolled a %d"):format(v) end,
	},
	{
		key = "average", title = "Perfectly Average", icon = icon("INV_Misc_Note_01"),
		value = function(s)
			if s.rollCount < 3 then return nil end
			return math.abs(s.rollSum / s.rollCount - 50.5)
		end,
		pick = "min", max = 8,
		text = function(_, s) return ("Averaged %.1f over %d rolls"):format(s.rollSum / s.rollCount, s.rollCount) end,
	},
}

Titles.Fallback = {
	key = "background", title = "Background Character", icon = icon("INV_Misc_QuestionMark"),
	text = function() return "Was also there" end,
}

local function newStats(class)
	return {
		class = class, drops = 0,
		needs = 0, greeds = 0, passes = 0, noRolls = 0,
		wins = 0, losses = 0, seconds = 0,
		rollCount = 0, rollSum = 0, high = nil, low = nil,
	}
end

local CHOICE_FIELD = { need = "needs", greed = "greeds", pass = "passes", none = "noRolls" }

function Titles.IsResolved(drop)
	return drop.winner ~= nil or drop.allPassed == true
end

-- Per-player numbers for a session. Only resolved drops count, so a run that ends mid-roll
-- doesn't hand out "Asleep at the Wheel" for rolls still in progress.
function Titles.Stats(session)
	local stats = {}
	for _, drop in ipairs(session.drops or {}) do
		if Titles.IsResolved(drop) then
			local ranked = {}
			for name, r in pairs(drop.rolls or {}) do
				local s = stats[name]
				if not s then
					s = newStats(r.class)
					stats[name] = s
				end
				s.class = s.class or r.class
				s.drops = s.drops + 1
				local field = CHOICE_FIELD[r.choice] or "noRolls"
				s[field] = s[field] + 1
				if ns.IsRollChoice(r.choice) then
					if name ~= drop.winner then
						s.losses = s.losses + 1
					end
					if type(r.roll) == "number" then
						s.rollCount = s.rollCount + 1
						s.rollSum = s.rollSum + r.roll
						s.high = math.max(s.high or r.roll, r.roll)
						s.low = math.min(s.low or r.roll, r.roll)
						table.insert(ranked, { name = name, tier = ns.CHOICE_TIER[r.choice], roll = r.roll })
					end
				end
			end
			if drop.winner then
				local w = stats[drop.winner]
				if not w then
					w = newStats(drop.winnerClass)
					stats[drop.winner] = w
				end
				w.wins = w.wins + 1
			end
			table.sort(ranked, function(a, b)
				if a.tier ~= b.tier then return a.tier > b.tier end
				return a.roll > b.roll
			end)
			if drop.winner and ranked[1] and ranked[1].name == drop.winner and ranked[2] then
				local s = stats[ranked[2].name]
				s.seconds = s.seconds + 1
			end
		end
	end
	return stats
end

local function qualifies(def, v)
	if v == nil then return false end
	if def.min and v < def.min then return false end
	if def.max and v > def.max then return false end
	return true
end

-- Returns a list of awards: { key, title, icon, text, players = { {name, class}, ... } }.
-- Tied players share an award. Anyone who took part but won nothing becomes a Background Character.
function Titles.Compute(session)
	local stats = Titles.Stats(session)
	local awards = {}
	local awarded = {}

	for _, def in ipairs(Titles.List) do
		local best, winners = nil, {}
		for name, s in pairs(stats) do
			local v = def.value(s)
			if qualifies(def, v) then
				local better = best == nil
					or (def.pick == "min" and v < best)
					or (def.pick ~= "min" and v > best)
				if better then
					best, winners = v, { name }
				elseif v == best then
					table.insert(winners, name)
				end
			end
		end
		if best ~= nil then
			table.sort(winners)
			local players = {}
			for _, name in ipairs(winners) do
				table.insert(players, { name = name, class = stats[name].class })
				awarded[name] = true
			end
			local title = type(def.title) == "function" and def.title(best) or def.title
			table.insert(awards, {
				key = def.key, title = title, icon = def.icon, players = players,
				text = def.text(best, stats[winners[1]]),
			})
		end
	end

	local leftovers = {}
	for name, s in pairs(stats) do
		if not awarded[name] then
			table.insert(leftovers, { name = name, class = s.class })
		end
	end
	if #leftovers > 0 then
		table.sort(leftovers, function(a, b) return a.name < b.name end)
		local f = Titles.Fallback
		table.insert(awards, { key = f.key, title = f.title, icon = f.icon, players = leftovers, text = f.text() })
	end
	return awards, stats
end

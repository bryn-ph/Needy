-- End-of-run awards. Pure data and maths over a session, no UI, so it's easy to tweak and to test offline.
--
-- Awards are meant to land, not to hand everyone a participation trophy:
--   * a "most" award needs a clear winner whose count clears a minimum, leads the next player by at least
--     `lead` (1 if unset, so ties never count) and, where set, is a big enough share of the items they saw
--     (share) or of the whole run (runShare);
--   * an "exact" award is a rare moment (a roll of 100 or of 1) and can be shared. It only counts in runs
--     with at most maxRolls rolls: across a whole raid somebody nearly always rolls a 100;
--   * each player gets at most one award, their most impressive, and a run shows at most MAX_AWARDS.
-- A quiet run can end with no awards at all.
local _, ns = ...

local Titles = {}
ns.Titles = Titles

local MAX_AWARDS = 5
local EXACT_SCORE = 1.5 -- how a rare roll ranks against "most" awards (which score count / minimum)

local function icon(name)
	return "Interface\\Icons\\" .. name
end

Titles.List = {
	{
		key = "hoarder", title = "Loot Hoarder", icon = icon("INV_Misc_Bag_08"),
		most = "needs", min = 3, share = 0.5, lead = 2,
		text = function(v, s) return ("Needed %d of %d items"):format(v, s.drops) end,
	},
	{
		key = "golden", title = "Golden Hands", icon = icon("INV_Misc_Coin_02"),
		most = "wins", min = 3, runShare = 0.25, lead = 2,
		text = function(v) return ("Walked away with %d items"):format(v) end,
	},
	{
		key = "unlucky", title = "Unlucky", icon = icon("Spell_Shadow_GatherShadows"),
		most = "losses", min = 4, qualify = function(s) return s.wins == 0 end,
		text = function(v) return ("Rolled %d times and won nothing"):format(v) end,
	},
	{
		key = "saint", title = "The Saint", icon = icon("Spell_Holy_HolyBolt"),
		most = "passes", min = 4, share = 0.65,
		text = function(v, s) return ("Passed on %d of %d items"):format(v, s.drops) end,
	},
	{
		key = "bridesmaid", title = "Always the Bridesmaid", icon = icon("INV_Misc_Flower_02"),
		most = "seconds", min = 3, lead = 2,
		text = function(v) return ("Came second %d times"):format(v) end,
	},
	{
		key = "asleep", title = "Asleep at the Wheel", icon = icon("Spell_Nature_Sleep"),
		most = "noRolls", min = 3, share = 0.33,
		text = function(v, s) return ("Let %d of %d rolls time out"):format(v, s.drops) end,
	},
	{
		key = "natural100", title = "Natural 100", icon = icon("INV_Misc_Dice_01"),
		exact = "high", equals = 100, maxRolls = 80,
		text = function() return "Rolled a perfect 100" end,
	},
	{
		key = "critfail", title = "Critical Fail", icon = icon("INV_Misc_Dice_02"),
		exact = "low", equals = 1, maxRolls = 80,
		text = function() return "Rolled a 1" end,
	},
}

local function newStats(class)
	return {
		class = class, drops = 0,
		needs = 0, greeds = 0, passes = 0, noRolls = 0,
		wins = 0, losses = 0, seconds = 0,
		rollCount = 0, high = nil, low = nil,
	}
end

local CHOICE_FIELD = { need = "needs", greed = "greeds", pass = "passes", none = "noRolls" }

function Titles.IsResolved(drop)
	return drop.winner ~= nil or drop.allPassed == true
end

-- Per-player numbers for a session, plus the number of finished drops. Only resolved drops count, so a
-- run that ends mid-roll doesn't count rolls still in progress as timed out.
function Titles.Stats(session)
	local stats, resolved = {}, 0
	for _, drop in ipairs(session.drops or {}) do
		if Titles.IsResolved(drop) then
			resolved = resolved + 1
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
	return stats, resolved
end

-- Who (if anyone) earns `def`, and how strongly. Returns names, value, score.
local function candidates(def, stats, resolved)
	if def.exact then
		local rolls = 0
		for _, s in pairs(stats) do rolls = rolls + s.rollCount end
		if def.maxRolls and rolls > def.maxRolls then return {}, nil, 0 end
		local names = {}
		for name, s in pairs(stats) do
			if s[def.exact] == def.equals then table.insert(names, name) end
		end
		return names, def.equals, EXACT_SCORE
	end

	local best, bestName, runnerUp = nil, nil, nil
	for name, s in pairs(stats) do
		local v = s[def.most] or 0
		if best == nil or v > best then
			runnerUp = best
			best, bestName = v, name
		elseif runnerUp == nil or v > runnerUp then
			runnerUp = v
		end
	end
	if not bestName then return {}, nil, 0 end
	if runnerUp and best - runnerUp < (def.lead or 1) then return {}, nil, 0 end -- a tie, or too close to call
	local s = stats[bestName]
	if best < def.min then return {}, nil, 0 end
	if def.share and best < def.share * s.drops then return {}, nil, 0 end
	if def.runShare and best < def.runShare * resolved then return {}, nil, 0 end
	if def.qualify and not def.qualify(s) then return {}, nil, 0 end
	return { bestName }, best, best / def.min
end

-- Returns a list of awards: { key, title, icon, text, players = { {name, class}, ... } }, most impressive
-- first, and the per-player stats.
function Titles.Compute(session)
	local stats, resolved = Titles.Stats(session)
	local found = {}
	for i, def in ipairs(Titles.List) do
		local names, value, score = candidates(def, stats, resolved)
		if #names > 0 then
			table.insert(found, { def = def, names = names, value = value, score = score, order = i })
		end
	end
	table.sort(found, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.order < b.order
	end)

	local awards, taken = {}, {}
	for _, f in ipairs(found) do
		if #awards >= MAX_AWARDS then break end
		local players = {}
		for _, name in ipairs(f.names) do
			if not taken[name] then
				table.insert(players, { name = name, class = stats[name].class })
			end
		end
		if #players > 0 then
			table.sort(players, function(a, b) return a.name < b.name end)
			for _, p in ipairs(players) do taken[p.name] = true end
			table.insert(awards, {
				key = f.def.key, title = f.def.title, icon = f.def.icon, players = players,
				text = f.def.text(f.value, stats[players[1].name]),
			})
		end
	end
	return awards, stats
end

-- One session per dungeon/raid run: starts on entering the instance, ends on leaving it.
local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local RESUME_WINDOW = 30 * 60 -- seconds: a /reload or quick relog inside this keeps the same session

Tracker.session = nil -- the real run in progress
Tracker.testSession = nil -- the /needy test run in progress

function Tracker.NewSession(fields)
	local s = {
		instanceName = "Unknown",
		startTime = time(),
		lastSeen = time(),
		drops = {},
		players = {},
	}
	for k, v in pairs(fields or {}) do
		s[k] = v
	end
	return s
end

local function findDrop(session, key)
	for _, d in ipairs(session.drops) do
		if d.key == key then return d end
	end
end

-- Insert or update a drop. Choices and rolls arrive piecemeal, so later updates overwrite earlier ones,
-- but a player who's dropped out of a later update keeps what we last saw.
function Tracker.RecordDrop(session, drop)
	local d = findDrop(session, drop.key)
	if not d then
		d = { key = drop.key, time = time(), rolls = {} }
		table.insert(session.drops, d)
	end
	d.link = drop.link or d.link
	d.name = drop.name or d.name
	d.texture = drop.texture or d.texture
	d.quality = drop.quality or d.quality
	d.encounterName = drop.encounterName or d.encounterName
	d.winner = drop.winner or d.winner
	d.winnerClass = drop.winnerClass or d.winnerClass
	d.allPassed = drop.allPassed or nil
	d.isTied = drop.isTied or nil
	for name, r in pairs(drop.rolls or {}) do
		d.rolls[name] = { choice = r.choice, roll = r.roll, class = r.class }
		if r.class then
			session.players[name] = r.class
		end
	end
	session.lastSeen = time()
	return d
end

local function currentInstance()
	local inInstance, instanceType = IsInInstance()
	if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
		return nil
	end
	local name, _, _, difficultyName, _, _, _, instanceID = GetInstanceInfo()
	return { instanceName = name, difficultyName = difficultyName, instanceID = instanceID, instanceType = instanceType }
end

local function start(inst)
	local active = ns.DB.Active()
	if active and active.instanceID == inst.instanceID and not active.endTime
		and time() - (active.lastSeen or active.startTime) < RESUME_WINDOW then
		Tracker.session = active
		ns.Debug("resumed session", inst.instanceName)
		ns.LootSource.Rescan()
	else
		Tracker.session = Tracker.NewSession(inst)
		ns.DB.SetActive(Tracker.session)
		ns.Debug("new session", inst.instanceName)
	end
	ns.Fire("SESSION_START", Tracker.session)
end

-- Finish a session: save it, then open the awards window if that's switched on.
-- opts.silent skips the window.
function Tracker.Finish(session, opts)
	opts = opts or {}
	session.endTime = time()
	local hasDrops = #session.drops > 0
	if hasDrops and (not session.isTest or ns.settings.keepTestSessions) then
		ns.DB.SaveSession(session)
	elseif session.isTest then
		Tracker.lastTest = session -- not saved, but still browsable until /reload
	end
	ns.Fire("SESSION_END", session)
	if opts.silent or not hasDrops then return end
	-- Test runs always show the window; real ones only when it's switched on and someone earned a title.
	if session.isTest or (ns.settings.showSummary and #ns.Titles.Compute(session) > 0) then
		ns.SummaryWindow.Show(session)
	end
end

function Tracker.End(opts)
	local s = Tracker.session
	if not s then return false end
	Tracker.session = nil
	ns.DB.SetActive(nil)
	Tracker.Finish(s, opts)
	return true
end

local function check()
	local inst = currentInstance()
	local s = Tracker.session
	if inst then
		if s and s.instanceID == inst.instanceID then return end
		if s then Tracker.End() end
		start(inst)
	elseif s then
		Tracker.End()
	elseif ns.DB.Active() then
		-- A run left unfinished last time (logged out inside, then logged in elsewhere): file it quietly.
		local stale = ns.DB.Active()
		ns.DB.SetActive(nil)
		Tracker.Finish(stale, { silent = true })
	end
end

function Tracker.Reset()
	Tracker.session = nil
	Tracker.testSession = nil
	check()
end

function Tracker.Init()
	ns.On("PLAYER_ENTERING_WORLD", check)
	ns.On("ZONE_CHANGED_NEW_AREA", check)
	ns.On("PLAYER_LOGOUT", function()
		if Tracker.session then Tracker.session.lastSeen = time() end
	end)
	ns.Listen("DROP_UPDATE", function(drop)
		local target = drop.isTest and Tracker.testSession or Tracker.session
		if target then
			Tracker.RecordDrop(target, drop)
		end
	end)
end

-- One session per dungeon/raid run: starts on entering the instance, ends on leaving it.
-- Except after a wipe: releasing puts you at a graveyard outside as a ghost, so leaving dead doesn't end the
-- run. It's kept "away" until you run back in (it carries on), go into a different instance (it ends and the
-- new one starts), or have been back on your feet outside for AWAY_GRACE without returning (it ends then).
local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local RESUME_WINDOW = 30 * 60 -- seconds: a /reload or quick relog inside this keeps the same session
local AWAY_GRACE = 5 * 60 -- seconds alive outside, after leaving as a ghost, before the run is over
local ALIVE_SETTLE = 2 -- seconds after coming back to life, so a ghost entering the instance is inside by then

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
	d.wishlisted = drop.wishlisted or d.wishlisted
	for name, r in pairs(drop.rolls or {}) do
		d.rolls[name] = { choice = r.choice, offSpec = r.offSpec, roll = r.roll, class = r.class, isSelf = r.isSelf or nil }
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

local function isGhost()
	if not UnitIsDeadOrGhost then return false end
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	return ok and not ns.IsSecret(dead) and dead == true
end

local check

-- Alive outside after leaving as a ghost: the run ends if you're not back inside within AWAY_GRACE.
local function startGrace(s)
	if s.graceUntil then return end
	s.graceUntil = time() + AWAY_GRACE
	ns.Debug("back on your feet outside; the run ends in", AWAY_GRACE, "s unless you go back in")
	C_Timer.After(AWAY_GRACE + 1, check)
end

-- Out of the instance, the run carries on if you left as a ghost (or already had and haven't been back).
local function keepAway(s)
	if not (s.away or isGhost()) then return false end
	if not s.away then
		s.away = true
		ns.Debug("left as a ghost; keeping the run", s.instanceName)
	end
	s.lastSeen = time()
	if isGhost() then
		s.graceUntil = nil -- died again on the way back: wait for this life
		return true
	end
	if s.graceUntil and time() >= s.graceUntil then return false end
	startGrace(s)
	return true
end

function check()
	local inst = currentInstance()
	local s = Tracker.session
	if inst then
		if s and s.instanceID == inst.instanceID then
			if s.away then ns.Debug("back inside", s.instanceName) end
			s.away, s.graceUntil = nil, nil
			return
		end
		if s then Tracker.End() end
		start(inst)
	elseif s then
		if not keepAway(s) then Tracker.End() end
	elseif ns.DB.Active() then
		local active = ns.DB.Active()
		if active.away and not active.endTime and time() - (active.lastSeen or active.startTime) < RESUME_WINDOW then
			-- A /reload while out between wipe and run back: still away.
			Tracker.session = active
			if active.graceUntil then
				C_Timer.After(math.max(1, active.graceUntil - time() + 1), check) -- the reload lost its timer
			end
			if keepAway(active) then
				ns.Fire("SESSION_START", active)
				return
			end
			Tracker.End({ silent = true })
			return
		end
		-- A run left unfinished last time (logged out inside, then logged in elsewhere): file it quietly.
		ns.DB.SetActive(nil)
		Tracker.Finish(active, { silent = true })
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
	-- Back on your feet: a ghost running back in is inside by the time this looks.
	local function settle() C_Timer.After(ALIVE_SETTLE, check) end
	ns.On("PLAYER_UNGHOST", settle)
	ns.On("PLAYER_ALIVE", settle)
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

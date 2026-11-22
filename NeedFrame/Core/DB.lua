-- SavedVariables: settings, finished sessions and the session in progress (so /reload resumes it).
local _, ns = ...

local DB = {}
ns.DB = DB

local CURRENT_VERSION = 1

local function clamp(key, v)
	local lim = ns.Limits[key]
	if not lim then return v end
	if v < lim[1] then return lim[1] end
	if v > lim[2] then return lim[2] end
	return v
end

local function cleanSettings(saved)
	saved = type(saved) == "table" and saved or {}
	local out = {}
	for key, default in pairs(ns.Defaults) do
		local v = saved[key]
		if type(v) == type(default) and not (type(v) == "number" and v ~= v) then
			out[key] = type(v) == "number" and clamp(key, v) or v
		else
			out[key] = default
		end
	end
	for _, key in ipairs({ "position", "logPosition" }) do
		local pos = saved[key]
		if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
			and type(pos[3]) == "number" and type(pos[4]) == "number" then
			out[key] = { pos[1], pos[2], pos[3], pos[4] }
		end
	end
	return out
end

local function validSession(s)
	return type(s) == "table" and type(s.drops) == "table" and type(s.startTime) == "number"
end

function DB.Init()
	if type(NeedFrameDB) ~= "table" then
		NeedFrameDB = {}
	end
	local db = NeedFrameDB
	db.version = CURRENT_VERSION
	db.settings = cleanSettings(db.settings)

	local sessions = {}
	if type(db.sessions) == "table" then
		for _, s in ipairs(db.sessions) do
			if validSession(s) then
				table.insert(sessions, s)
			end
		end
	end
	db.sessions = sessions
	if not validSession(db.active) then
		db.active = nil
	end

	ns.db = db
	ns.settings = db.settings
end

function DB.SaveSession(session)
	table.insert(ns.db.sessions, 1, session)
	while #ns.db.sessions > ns.settings.historyLimit do
		table.remove(ns.db.sessions)
	end
end

function DB.Sessions()
	return ns.db.sessions
end

function DB.SetActive(session)
	ns.db.active = session
end

function DB.Active()
	return ns.db.active
end

function DB.Reset()
	ns.db.sessions = {}
	ns.db.active = nil
	ns.db.settings = cleanSettings(nil)
	ns.settings = ns.db.settings
end

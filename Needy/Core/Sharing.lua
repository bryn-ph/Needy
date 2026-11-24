-- Wishlists shared with your guild and group over addon messages (hidden, never shown in chat), so you can
-- see who else wants an item. Lists are item IDs only.
--
-- Messages (prefix "Needy"):
--   H:1                                   hello: please send me your list
--   L:1:<rev>:<class>:<part>:<parts>:<ids> one part of a list; ids comma-separated, rev = when it last changed
-- A list goes out at login (guild), on joining a group (group), a few seconds after it changes (both), and
-- in answer to a hello, unless that channel has just had the same list.
local _, ns = ...

local Sharing = {}
ns.Sharing = Sharing

local PREFIX = "Needy"
local PROTOCOL = "1"
local MAX_ITEMS = 200
local IDS_PER_PART = 28 -- keeps each message well under the 255-byte limit
local MAX_PARTS = math.ceil(MAX_ITEMS / IDS_PER_PART)
local SEND_GAP = 1.2 -- seconds between our messages
local RETRY = 15 -- seconds to wait when the game won't let us send (throttle or lockdown)
local CHANGE_DELAY = 5 -- after an edit, so a run of clicks goes out once
local GROUP_DELAY = 3
local LOGIN_DELAY = 10
local REPLY_MIN, REPLY_MAX = 2, 8 -- spread answers to a hello so a guild doesn't answer at once
local LIST_COOLDOWN = 60 -- don't send the same list to the same channel again sooner than this
local PART_TIMEOUT = 60
local KEEP_DAYS = 30
local MAX_PEOPLE = 1000

local SUCCESS = 0
local RETRY_RESULTS = { [3] = true, [8] = true, [11] = true } -- throttles, lockdown
local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

local people -- full name -> { rev, class, items = { [id] = true }, seen, guild }
local partial = {} -- full name -> { rev, class, parts, got, count, at }
local queue = {}
local pumping = false
local lastSent = {} -- channel -> { rev, at }
local replyPending = {}
local changePending = false
local groupSize = 0
-- What's happened this session, for /needy share.
local diag = { registered = "not tried", sent = 0, failed = 0, heard = 0, echoes = 0 }

-- Names ------------------------------------------------------------------------------------------

local function realm()
	return GetNormalizedRealmName and GetNormalizedRealmName() or nil
end

-- A last part of a name that names a server, not the person: your own realm (retail), or the
-- "camwow...realm..." label Forever can put after an addon message's sender.
local function serverLabel(part)
	if part:lower():match("^camwow%a*%d+realm%d+%a*$") then return true end
	local r = realm()
	return type(r) == "string" and r ~= "" and not ns.IsSecret(r) and part == r
end

-- One key per person, however their name is spelt, which is also how it's shown. On Forever a character
-- is "First Surname": UnitName gives the surname where retail gives the realm, the realm's name is "",
-- and a sender can arrive as "First-Surname", "First Surname" or either with a server label after.
-- Retail's "Name-YourRealm" becomes "Name".
local function nameKey(name)
	if type(name) ~= "string" or ns.IsSecret(name) or name == "" then return nil end
	local parts = {}
	for part in name:gmatch("[^%s%-]+") do parts[#parts + 1] = part end
	if #parts > 1 and serverLabel(parts[#parts]) then parts[#parts] = nil end
	if #parts == 0 then return nil end
	return table.concat(parts, " ", 1, math.min(#parts, 2))
end

local function unitKey(unit)
	if not UnitName then return nil end
	local name, second = UnitName(unit)
	if ns.IsSecret(name) or ns.IsSecret(second) or type(name) ~= "string" then return nil end
	if type(second) == "string" and second ~= "" then name = name .. "-" .. second end
	return nameKey(name)
end

local function myGuild()
	if not (IsInGuild and IsInGuild() and GetGuildInfo) then return nil end
	local name = GetGuildInfo("player")
	if type(name) ~= "string" or ns.IsSecret(name) then return nil end
	return name
end

local function groupChannel()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end

-- Full name -> true, for everyone in your group (not you).
local function groupMembers()
	local members = {}
	local raid = IsInRaid and IsInRaid()
	local count = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4
	for i = 1, count do
		local unit = (raid and "raid" or "party") .. i
		if UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
			local name = unitKey(unit)
			if name then members[name] = true end
		end
	end
	return members
end

-- Sending -------------------------------------------------------------------------------------------

-- Why the game won't let addon messages out right now, or nil. Only the chat lockdown (encounters and
-- the like) counts. Not C_ChatInfo.AreOutgoingAddonChatMessagesRestricted: that's a realm-wide flag,
-- true everywhere but tournament realms, for Blizzard's cooldown broadcaster; ordinary addon messages
-- still go out (and a real block comes back as result 11, which is retried).
local function locked()
	local chat = C_ChatInfo
	if chat.InChatMessagingLockdown and chat.InChatMessagingLockdown() then return "chat lockdown" end
	return nil
end

local pump
local function pumpLater(delay)
	pumping = true
	C_Timer.After(delay, pump)
end

function pump()
	pumping = false
	local msg = queue[1]
	if not msg then return end
	local why = locked()
	if why then
		diag.waiting = why
		ns.Debug("share: can't send yet,", why)
		return pumpLater(RETRY)
	end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg.text, msg.channel)
	diag.lastResult = ok and tostring(result) or ("error: " .. tostring(result))
	if ok and RETRY_RESULTS[result] then
		diag.waiting = "throttled (" .. tostring(result) .. ")"
		ns.Debug("share: throttled, trying again soon", msg.channel, result)
		return pumpLater(RETRY)
	end
	diag.waiting = nil
	table.remove(queue, 1)
	-- Retail returns a result code (0 is sent); older clients return true or nothing.
	if ok and (result == nil or result == SUCCESS or result == true) then
		diag.sent = diag.sent + 1
		ns.Debug("share: sent to", msg.channel, msg.text)
	else
		diag.failed = diag.failed + 1
		ns.Debug("share: NOT sent to", msg.channel, msg.text, "result", diag.lastResult)
	end
	if queue[1] then pumpLater(SEND_GAP) end
end

local function enqueue(channel, text, kind)
	table.insert(queue, { channel = channel, text = text, kind = kind })
	if not pumping then pumpLater(0) end
end

-- What we tell others: the wishlist, or nothing at all when sharing is off.
local function sharedIDs()
	local ids = {}
	if not ns.settings.shareWishlist then return ids end
	for _, item in ipairs(ns.Wishlist.List()) do
		if #ids >= MAX_ITEMS then break end
		table.insert(ids, item.id)
	end
	table.sort(ids)
	return ids
end

local function sendList(channel, force)
	if not channel then return end
	local rev = ns.Wishlist.Rev()
	local last = lastSent[channel]
	if not force and last and last.rev == rev and GetTime() - last.at < LIST_COOLDOWN then
		ns.Debug("share: list already sent to", channel, "just now")
		return
	end
	lastSent[channel] = { rev = rev, at = GetTime() }
	-- A newer copy of the list replaces one still waiting to go to the same channel.
	for i = #queue, 1, -1 do
		if queue[i].kind == "list" and queue[i].channel == channel then table.remove(queue, i) end
	end
	local ids = sharedIDs()
	local parts = math.max(1, math.ceil(#ids / IDS_PER_PART))
	local class = ns.PlayerClass() or ""
	for part = 1, parts do
		local chunk = {}
		for i = (part - 1) * IDS_PER_PART + 1, math.min(#ids, part * IDS_PER_PART) do
			table.insert(chunk, ids[i])
		end
		enqueue(channel, ("L:%s:%d:%s:%d:%d:%s"):format(PROTOCOL, rev, class, part, parts, table.concat(chunk, ",")), "list")
	end
end

local function hello(channel)
	if channel then enqueue(channel, "H:" .. PROTOCOL, "hello") end
end

-- Receiving -----------------------------------------------------------------------------------------

local function store(sender, msg, channel)
	local person = people[sender]
	if person and person.rev > msg.rev then return end
	local items = {}
	for _, ids in ipairs(msg.parts) do
		for id in ids:gmatch("%d+") do
			id = tonumber(id)
			if id and id > 0 then items[id] = true end
		end
	end
	person = { rev = msg.rev, class = msg.class ~= "" and msg.class or (person and person.class), items = items,
		seen = time(), guild = channel == "GUILD" and myGuild() or (person and person.guild) }
	people[sender] = person
	local n = 0
	for _ in pairs(items) do n = n + 1 end
	ns.Debug("share: got", sender .. "'s list,", n, "items")
	ns.Fire("SHARED_WISHLISTS_CHANGED")
end

local function onList(sender, channel, rev, class, part, parts, ids)
	rev, part, parts = tonumber(rev), tonumber(part), tonumber(parts)
	if not (rev and part and parts) or parts < 1 or parts > MAX_PARTS or part < 1 or part > parts then
		ns.Debug("share: ignored a malformed list from", sender)
		return
	end
	local known = people[sender]
	if known and known.rev == rev then
		known.seen = time()
		if channel == "GUILD" then known.guild = myGuild() end
		return
	end
	local msg = partial[sender]
	if not msg or msg.rev ~= rev or msg.count ~= parts or GetTime() - msg.at > PART_TIMEOUT then
		msg = { rev = rev, class = class, parts = {}, got = 0, count = parts, at = GetTime() }
		partial[sender] = msg
	end
	if not msg.parts[part] then
		msg.parts[part] = ids
		msg.got = msg.got + 1
	end
	if msg.got == msg.count then
		partial[sender] = nil
		store(sender, msg, channel)
	end
end

local function onHello(channel)
	if replyPending[channel] then return end
	replyPending[channel] = true
	C_Timer.After(REPLY_MIN + math.random() * (REPLY_MAX - REPLY_MIN), function()
		replyPending[channel] = nil
		sendList(channel, false)
	end)
end

function Sharing.Receive(prefix, text, channel, sender)
	if prefix ~= PREFIX then return end
	if ns.IsSecret(text) or ns.IsSecret(sender) or ns.IsSecret(channel) or type(text) ~= "string" then
		ns.Debug("share: ignored a hidden (secret) message")
		return
	end
	local from = nameKey(sender)
	if from and from == unitKey("player") then
		diag.echoes = diag.echoes + 1 -- the guild and group send your own messages back to you
		return
	end
	diag.heard = diag.heard + 1
	diag.lastHeard = ("%s on %s: %s"):format(tostring(sender), tostring(channel), text:sub(1, 48))
	ns.Debug("share: heard", diag.lastHeard)
	if not CHANNELS[channel] then return ns.Debug("share: ignored, not guild or group:", channel) end
	if not from then return ns.Debug("share: ignored, no sender name") end
	sender = from
	if text == "H:" .. PROTOCOL then
		onHello(channel)
		return
	end
	local rev, class, part, parts, ids = text:match("^L:" .. PROTOCOL .. ":(%d+):(%u*):(%d+):(%d+):([%d,]*)$")
	if rev then
		onList(sender, channel, rev, class, part, parts, ids)
	else
		ns.Debug("share: ignored a message it didn't understand from", sender)
	end
end

-- Reading ----------------------------------------------------------------------------------------

-- Who else wants an item: { group = { { name, class }, ... }, guild = { ... } }, each sorted by name.
-- Group members come first; guildmates are anyone whose list came over your current guild's channel.
function Sharing.WhoWants(itemID)
	local result = { group = {}, guild = {} }
	if not itemID then return result end
	local members = groupMembers()
	local guild = myGuild()
	for name, person in pairs(people) do
		if person.items[itemID] then
			local entry = { name = name, class = person.class }
			if members[name] then
				table.insert(result.group, entry)
			elseif guild and person.guild == guild then
				table.insert(result.guild, entry)
			end
		end
	end
	local byName = function(a, b) return a.name < b.name end
	table.sort(result.group, byName)
	table.sort(result.guild, byName)
	return result
end

-- Setup --------------------------------------------------------------------------------------------

local function clean(saved)
	local out, count = {}, 0
	local oldest = time() - KEEP_DAYS * 24 * 3600
	if type(saved) ~= "table" then return out end
	local me = unitKey("player")
	for saved_name, p in pairs(saved) do
		if count >= MAX_PEOPLE then break end
		local name = nameKey(saved_name) -- older copies keyed people differently
		if name and name ~= me and type(p) == "table" and type(p.rev) == "number" and type(p.items) == "table"
			and type(p.seen) == "number" and p.seen >= oldest then
			local items = {}
			for id, v in pairs(p.items) do
				if type(id) == "number" and id > 0 and v == true then items[id] = true end
			end
			out[name] = {
				rev = p.rev, items = items, seen = p.seen,
				class = type(p.class) == "string" and p.class:match("^%u+$") and p.class or nil,
				guild = type(p.guild) == "string" and p.guild or nil,
			}
			count = count + 1
		end
	end
	return out
end

local function onRoster()
	local size = GetNumGroupMembers and GetNumGroupMembers() or 0
	local grew = size > groupSize
	groupSize = size
	if not grew or size < 2 then return end
	C_Timer.After(GROUP_DELAY, function()
		local channel = groupChannel()
		hello(channel)
		sendList(channel, false)
	end)
end

local function onChange()
	if changePending then return end
	changePending = true
	C_Timer.After(CHANGE_DELAY, function()
		changePending = false
		if myGuild() then sendList("GUILD", true) end
		sendList(groupChannel(), true)
	end)
end

-- /needy share: what sharing is doing, to find out why lists aren't arriving.
function Sharing.Status()
	local row = "  |cffffd100%s|r %s"
	ns.Print("wishlist sharing " .. (ns.settings.shareWishlist and "on" or "off (others get an empty list)"))
	print(row:format("Prefix registered:", diag.registered .. "  (0 or true is fine)"))
	print(row:format("Guild:", myGuild() or "none"))
	print(row:format("Group:", groupChannel() or "none"))
	print(row:format("Can send:", locked() or "yes"))
	print(row:format("Sent:", ("%d, failed %d, waiting %d%s; last result %s"):format(diag.sent, diag.failed, #queue,
		diag.waiting and (" (" .. diag.waiting .. ")") or "", diag.lastResult or "none")))
	print(row:format("Your own messages echoed back:", tostring(diag.echoes) .. "  (more than 0 means sending works)"))
	print(row:format("Heard from others:", tostring(diag.heard) .. (diag.lastHeard and ("; last " .. diag.lastHeard) or "")))
	print(row:format("Your list:", ("%d items, revision %d"):format(#sharedIDs(), ns.Wishlist.Rev())))
	local names = {}
	for name in pairs(people) do table.insert(names, name) end
	table.sort(names)
	print(row:format("Others' lists:", tostring(#names)))
	for i = 1, math.min(#names, 10) do
		local p, n = people[names[i]], 0
		for _ in pairs(p.items) do n = n + 1 end
		print(("    %s: %d items%s"):format(names[i], n, p.guild and (", guild " .. p.guild) or ""))
	end
end

-- /needy share send: say hello and send your list to your guild and group now.
function Sharing.SendNow()
	local guild, channel = myGuild(), groupChannel()
	if not guild and not channel then
		ns.Print("You're not in a guild or group, so there's nobody to share with.")
		return
	end
	if guild then
		hello("GUILD")
		sendList("GUILD", true)
	end
	hello(channel)
	sendList(channel, true)
	ns.Print(("Sent your wishlist to %s. Anyone with Needy there answers within about 10 seconds; check with |cffffd100/needy share|r.")
		:format(guild and channel and ("your guild and " .. channel:lower()) or guild and "your guild" or channel:lower()))
end

function Sharing.Forget()
	for name in pairs(people) do people[name] = nil end
	ns.Fire("SHARED_WISHLISTS_CHANGED")
end

-- The share setting changed: others need to hear (an empty list, if it's now off).
function Sharing.SettingChanged()
	ns.Wishlist.Touch()
end

function Sharing.Init()
	people = clean(ns.db.shared)
	ns.db.shared = people
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage and C_ChatInfo.RegisterAddonMessagePrefix) then
		diag.registered = "no addon message API"
		return
	end
	local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	diag.registered = ok and tostring(result) or "error"
	ns.Debug("share: prefix registered", diag.registered)
	ns.On("CHAT_MSG_ADDON", function(_, ...) Sharing.Receive(...) end)
	ns.On("GROUP_ROSTER_UPDATE", onRoster)
	ns.Listen("WISHLIST_CHANGED", onChange)
	ns.On("PLAYER_LOGIN", function()
		groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
		C_Timer.After(LOGIN_DELAY, function()
			if myGuild() then
				hello("GUILD")
				sendList("GUILD", false)
			end
			local channel = groupChannel()
			hello(channel)
			sendList(channel, false)
		end)
	end)
end

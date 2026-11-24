local addonName, ns = ...

ns.name = addonName
ns.debug = false

function ns.Print(...)
	print("|cffffd100Needy|r", ...)
end

function ns.Debug(...)
	if ns.debug then
		print("|cff888888Needy debug|r", ...)
	end
end

-- Midnight-style secret values: can be passed along but not compared, indexed or concatenated.
function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Game events -----------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

function ns.Off(event)
	handlers[event] = nil
	eventFrame:UnregisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end)

-- Internal messages -------------------------------------------------------------
-- LootSource and TestMode raise the same messages, so the UI and Tracker never care
-- whether a roll is real or simulated:
--   ROLL_START(roll)          a roll window opened
--   ROLL_CHOSEN(roll, choice) the player clicked a button
--   ROLL_CLOSED(rollID)       the roll window closed for us (chose, timed out, cancelled)
--   ROLL_SELF_RESULT(rollID, roll, isWinning)
--   DROP_UPDATE(drop)         someone's choice/roll/winner changed for a drop
--   SESSION_START(session) / SESSION_END(session)
--   WISHLIST_CHANGED()
--   SHARED_WISHLISTS_CHANGED()   someone else's list arrived

local listeners = {}

function ns.Listen(message, fn)
	listeners[message] = listeners[message] or {}
	table.insert(listeners[message], fn)
end

function ns.Fire(message, ...)
	local list = listeners[message]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Startup -------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	ns.Off("ADDON_LOADED")
	ns.DB.Init()
	ns.LootSource.Init()
	ns.Tracker.Init()
	ns.Wishlist.Init()
	ns.Sharing.Init()
	ns.RollFrame.Init()
	ns.RollLog.Init()
	ns.SettingsWindow.Register()
	ns.MinimapButton.Init()
	ns.On("PLAYER_LOGIN", ns.DungeonJournal.Init) -- by then every addon has loaded
end)

-- Referenced by the TOC's AddonCompartmentFunc.
function Needy_OnAddonCompartmentClick()
	ns.SettingsWindow.Toggle()
end

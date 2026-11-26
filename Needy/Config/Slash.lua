local _, ns = ...

local commands = {}
local order = {}

local function add(name, usage, fn)
	commands[name] = fn
	table.insert(order, { name = name, usage = usage })
end

local function help()
	ns.Print("commands:")
	for _, c in ipairs(order) do
		print(("  |cffffd100/needy %s|r - %s"):format(c.name, c.usage))
	end
end

add("history", "show the roll history (also just /needy)", function()
	ns.HistoryWindow.Toggle()
end)

add("summary", "show the awards and stats for the current or last run", function()
	local s = ns.Tracker.session or ns.Tracker.testSession or ns.Tracker.lastTest or ns.DB.Sessions()[1]
	ns.SummaryWindow.Show(s)
end)

add("end", "end the current run now and hand out the awards", function()
	if not ns.Tracker.End() then
		ns.Print("You're not in a run. (Runs start when you enter a dungeon or raid.)")
	end
end)

add("test", "[more | wish | share | end | run | keep] try it out with a fake party", function(arg)
	if arg == "" or arg == "start" then
		ns.TestMode.Start(3)
	elseif arg == "more" then
		ns.TestMode.Start(2)
	elseif arg == "wish" then
		ns.TestMode.Wish()
	elseif arg == "share" then
		ns.TestMode.Share()
	elseif arg == "end" or arg == "stop" then
		ns.TestMode.End()
	elseif arg == "run" then
		ns.TestMode.Run()
	elseif arg == "keep" then
		ns.settings.keepTestSessions = not ns.settings.keepTestSessions
		ns.Print("Test runs will " .. (ns.settings.keepTestSessions and "be saved to" or "not be saved to") .. " history.")
	else
		ns.Print("/needy test, /needy test more, /needy test wish, /needy test share, /needy test end, /needy test run, /needy test keep")
	end
end)

add("wishlist", "show this character's wishlist", function()
	ns.SettingsWindow.Show("wishlist")
end)

add("log", "show or hide the on-screen roll log", function()
	ns.settings.showLog = not ns.settings.showLog
	ns.RollLog.Refresh()
	ns.Print("Roll log " .. (ns.settings.showLog and "on (it shows once something drops)." or "off."))
end)

add("anim", "turn roll animations on or off", function()
	ns.settings.animations = not ns.settings.animations
	ns.Print("Animations " .. (ns.settings.animations and "on." or "off."))
end)

add("unlock", "move the roll bars", function()
	ns.settings.locked = false
	ns.RollFrame.ApplySettings()
	ns.Print("Drag the gold handle (it snaps to the centre of the screen), then click Done.")
end)

add("lock", "lock the roll bars in place", function()
	ns.settings.locked = true
	ns.RollFrame.ApplySettings()
end)

add("blizzard", "switch between Needy's and Blizzard's roll frames", function()
	ns.settings.replaceBlizzard = not ns.settings.replaceBlizzard
	ns.RollFrame.ApplySettings()
	ns.Print(ns.settings.replaceBlizzard and "Blizzard's roll frames are hidden." or
		"Blizzard's roll frames are back (Needy's bars still show too).")
end)

add("options", "open the settings (also: left-click the minimap icon)", function()
	ns.SettingsWindow.Toggle()
end)

add("minimap", "show or hide the minimap icon", function()
	ns.settings.minimapShow = not ns.settings.minimapShow
	ns.MinimapButton.Update()
	ns.Print("Minimap icon " .. (ns.settings.minimapShow and "shown." or "hidden. /needy minimap brings it back."))
end)

add("share", "[send] what wishlist sharing has sent and heard; send sends your list now", function(arg)
	if arg == "send" then
		ns.Sharing.SendNow()
	else
		ns.Sharing.Status()
	end
end)

add("debug", "toggle debug output", function()
	ns.debug = not ns.debug
	ns.Print("debug " .. (ns.debug and "on" or "off"))
end)

add("reset", "forget saved runs, settings, this character's wishlist and others' shared lists", function(arg)
	if arg ~= "confirm" then
		ns.Print("This deletes every saved run and this character's wishlist, and resets settings. Type |cffffd100/needy reset confirm|r to go ahead.")
		return
	end
	ns.DB.Reset()
	ns.Tracker.Reset()
	ns.Wishlist.Clear()
	ns.Sharing.Forget()
	ns.RollFrame.ResetPosition()
	ns.RollLog.ResetPosition()
	ns.RollFrame.ApplySettings()
	ns.MinimapButton.Update()
	ns.Print("Reset done.")
end)

add("help", "this list", help)

SLASH_NEEDY1 = "/needy"
SlashCmdList.NEEDY = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.HistoryWindow.Toggle()
		return
	end
	local fn = commands[cmd]
	if fn then
		fn(rest:lower())
	else
		help()
	end
end

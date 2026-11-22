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
		print(("  |cffffd100/nf %s|r - %s"):format(c.name, c.usage))
	end
end

add("history", "show the roll history (also just /nf)", function()
	ns.HistoryWindow.Toggle()
end)

add("summary", "show the awards for the current or last run", function()
	local s = ns.Tracker.session or ns.Tracker.testSession or ns.Tracker.lastTest or ns.DB.Sessions()[1]
	ns.SummaryWindow.Show(s)
end)

add("end", "end the current run now and hand out the awards", function()
	if not ns.Tracker.End() then
		ns.Print("You're not in a run. (Runs start when you enter a dungeon or raid.)")
	end
end)

add("test", "[more | end | run | keep] try it out with a fake party", function(arg)
	if arg == "" or arg == "start" then
		ns.TestMode.Start(3)
	elseif arg == "more" then
		ns.TestMode.Start(2)
	elseif arg == "end" or arg == "stop" then
		ns.TestMode.End()
	elseif arg == "run" then
		ns.TestMode.Run()
	elseif arg == "keep" then
		ns.settings.keepTestSessions = not ns.settings.keepTestSessions
		ns.Print("Test runs will " .. (ns.settings.keepTestSessions and "be saved to" or "not be saved to") .. " history.")
	else
		ns.Print("/nf test, /nf test more, /nf test end, /nf test run, /nf test keep")
	end
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

add("blizzard", "switch between NeedFrame's and Blizzard's roll frames", function()
	ns.settings.replaceBlizzard = not ns.settings.replaceBlizzard
	ns.RollFrame.ApplySettings()
	ns.Print(ns.settings.replaceBlizzard and "Blizzard's roll frames are hidden." or
		"Blizzard's roll frames are back (NeedFrame's bars still show too).")
end)

add("options", "open the settings (also: left-click the minimap icon)", function()
	ns.SettingsWindow.Toggle()
end)

add("minimap", "show or hide the minimap icon", function()
	ns.settings.minimapShow = not ns.settings.minimapShow
	ns.MinimapButton.Update()
	ns.Print("Minimap icon " .. (ns.settings.minimapShow and "shown." or "hidden. /nf minimap brings it back."))
end)

add("debug", "toggle debug output", function()
	ns.debug = not ns.debug
	ns.Print("debug " .. (ns.debug and "on" or "off"))
end)

add("reset", "forget all saved runs and settings", function(arg)
	if arg ~= "confirm" then
		ns.Print("This deletes every saved run and resets settings. Type |cffffd100/nf reset confirm|r to go ahead.")
		return
	end
	ns.DB.Reset()
	ns.Tracker.Reset()
	ns.RollFrame.ResetPosition()
	ns.RollLog.ResetPosition()
	ns.RollFrame.ApplySettings()
	ns.MinimapButton.Update()
	ns.Print("Reset done.")
end)

add("help", "this list", help)

SLASH_NEEDFRAME1 = "/needframe"
SLASH_NEEDFRAME2 = "/nf"
SlashCmdList.NEEDFRAME = function(msg)
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

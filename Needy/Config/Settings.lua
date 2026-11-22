-- Needy's settings window: a standard game window with a tab per section along the bottom (as in Jest).
-- Opened from the minimap icon, /needy options, or the launcher in the game's Settings > AddOns.
local _, ns = ...

local SettingsWindow = {}
ns.SettingsWindow = SettingsWindow

local W = ns.Widgets

local WIDTH, HEIGHT = 500, 450
local PAD = 18
local PAGE_WIDTH = WIDTH - PAD * 2 - 16

local win
local pages = {}
local current

local function setting(key, after)
	return function() return ns.settings[key] end, function(v)
		ns.settings[key] = v
		ns.RollFrame.ApplySettings()
		if after then after(v) end
	end
end

-- Page building --------------------------------------------------------------------------------

-- A page lays its controls out top to bottom; each helper adds one and moves the cursor down.
local function newPage(key, title, blurb)
	local page = CreateFrame("Frame", nil, win.inset)
	page:SetPoint("TOPLEFT", PAD - 8, -12)
	page:SetPoint("BOTTOMRIGHT", -(PAD - 8), 8)
	page:Hide()
	page.controls = {}
	page.y = 0

	local heading = W.Text(page, "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", 0, 0)
	heading:SetText(title)
	page.y = -24
	if blurb then
		local b = W.Text(page, "GameFontHighlightSmall")
		b:SetPoint("TOPLEFT", 0, page.y)
		b:SetWidth(PAGE_WIDTH)
		b:SetTextColor(0.75, 0.75, 0.75)
		b:SetText(blurb)
		page.y = page.y - (b:GetStringHeight() or 12) - 14
	else
		page.y = page.y - 8
	end

	function page:Add(control, height, gap)
		control:SetPoint("TOPLEFT", 0, self.y)
		self.y = self.y - (height or control:GetHeight()) - (gap or 6)
		if control.Refresh then table.insert(self.controls, control) end
		return control
	end
	function page:Header(text)
		self.y = self.y - 6
		local h = W.Header(self, text)
		h:SetPoint("TOPLEFT", 0, self.y)
		h.line:SetPoint("RIGHT", self, "RIGHT", 0, 0)
		self.y = self.y - 22
	end
	function page:Check(label, tip, key, after)
		local get, set = setting(key, after)
		return self:Add(W.Check(self, label, tip, get, set), 26, 2)
	end
	function page:Slider(label, key, minV, maxV, step, fmt)
		local get, set = setting(key)
		return self:Add(W.Slider(self, label, minV, maxV, step, fmt, get, set), 26, 8)
	end
	function page:Segmented(label, items, get, set)
		local row = CreateFrame("Frame", nil, self)
		row:SetSize(PAGE_WIDTH, 24)
		local l = W.Text(row, "GameFontHighlight")
		l:SetPoint("LEFT")
		l:SetText(label)
		local seg = W.Segmented(row, items, 230, set)
		seg:SetPoint("LEFT", 154, 0)
		function row:Refresh() seg:SetValue(get()) end
		return self:Add(row, 24, 10)
	end
	function page:Buttons(list)
		local row = CreateFrame("Frame", nil, self)
		row:SetSize(PAGE_WIDTH, 22)
		local x = 0
		for _, def in ipairs(list) do
			local b = W.Button(row, def[1], def[3] or 130, 22)
			b:SetPoint("LEFT", x, 0)
			b:SetScript("OnClick", def[2])
			x = x + (def[3] or 130) + 4
		end
		return self:Add(row, 22, 8)
	end
	function page:Refresh()
		for _, c in ipairs(self.controls) do c:Refresh() end
	end
	pages[key] = page
	return page
end

local function buildPages()
	-- Roll frame ---------------------------------------------------------------
	local p = newPage("rolls", "Roll Frame", "The bars that pop up when an item is up for need, greed or pass.")
	p:Check("Replace Blizzard's roll frames", "Hide the default loot roll popups and use Needy's bars.", "replaceBlizzard")
	p:Check("Animations", "Bars pop in, and results play the game's own dice roll animation.", "animations")
	p:Check("Lock position", "Untick to get a handle you can drag the bars with. They snap to the centre of the screen, like Edit Mode.", "locked")
	p:Segmented("New bars stack", { { value = false, text = "Downwards" }, { value = true, text = "Upwards" } },
		function() return ns.settings.growUp end,
		function(v) ns.settings.growUp = v; ns.RollFrame.ApplySettings() end)
	p:Slider("Scale", "scale", ns.Limits.scale[1], ns.Limits.scale[2], 0.05, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Slider("Bar width", "barWidth", ns.Limits.barWidth[1], ns.Limits.barWidth[2], 10, function(v) return tostring(v) end)
	p:Buttons({
		{ "Reset position", function() ns.RollFrame.ResetPosition() end, 120 },
	})

	-- Roll log -----------------------------------------------------------------
	p = newPage("log", "Roll Log", "A button on screen during a run. Click it to open a list of everything that's dropped, who won it and with what roll.")
	p:Check("Show the Roll Log", "Appears while you're in a dungeon or raid (or a test run).", "showLog")
	p:Slider("Rows shown", "logRows", ns.Limits.logRows[1], ns.Limits.logRows[2], 1, function(v) return tostring(v) end)
	p:Buttons({
		{ "Reset position", function() ns.RollLog.ResetPosition() end, 120 },
		{ "Open history", function() ns.HistoryWindow.Show() end, 120 },
	})

	-- End of run ---------------------------------------------------------------
	p = newPage("awards", "End of Run", "When you leave the instance, Needy hands out titles: Loot Hoarder, Unlucky, The Saint and friends.")
	p:Check("Show the awards window", "Opens the Run Awards when the run ends. You can post them to group chat from there.", "showSummary")
	p:Buttons({
		{ "Preview awards", function() ns.TestMode.Run() end, 130 },
	})

	-- General ------------------------------------------------------------------
	p = newPage("general", "General")
	p:Check("Minimap icon", "Left-click opens settings, right-click opens the roll history.", "minimapShow",
		function() ns.MinimapButton.Update() end)
	p:Check("Keep test runs in history", "Save /needy test runs alongside real ones.", "keepTestSessions")
	p:Slider("Runs kept", "historyLimit", ns.Limits.historyLimit[1], ns.Limits.historyLimit[2], 1, function(v) return tostring(v) end)
	p:Header("Testing")
	p:Buttons({
		{ "Test rolls", function() ns.TestMode.Start(3) end, 100 },
		{ "More rolls", function() ns.TestMode.Start(2) end, 100 },
		{ "End test run", function() ns.TestMode.End() end, 100 },
		{ "Simulate run", function() ns.TestMode.Run() end, 110 },
	})
	p:Header("Data")
	local armed = false
	p:Buttons({
		{ "Reset all data", function(self)
			if not armed then
				armed = true
				self:SetText("Click to confirm")
				C_Timer.After(4, function()
					armed = false
					self:SetText("Reset all data")
				end)
				return
			end
			armed = false
			self:SetText("Reset all data")
			SlashCmdList.NEEDY("reset confirm")
			SettingsWindow.Refresh()
		end, 140 },
	})
end

local TABS = {
	{ "rolls", "Roll Frame" },
	{ "log", "Roll Log" },
	{ "awards", "End of Run" },
	{ "general", "General" },
}

local function selectPage(key)
	current = key
	for k, page in pairs(pages) do
		page:SetShown(k == key)
	end
	for i, def in ipairs(TABS) do
		if def[1] == key and PanelTemplates_SetTab then PanelTemplates_SetTab(win, i) end
	end
	pages[key]:Refresh()
end

local function create()
	win = W.Window("NeedySettings", "Needy - Settings", WIDTH, HEIGHT)
	win:SetPoint("CENTER")

	local version = W.Text(win, "GameFontDisableSmall")
	version:SetPoint("TOPRIGHT", -12, -34)
	version:SetText("Needy " .. W.Version() .. "   |cff8c8c8c/needy help for commands|r")
	version:SetJustifyH("RIGHT")

	win.inset = W.Inset(win)
	win.inset:SetPoint("TOPLEFT", 8, -60)
	win.inset:SetPoint("BOTTOMRIGHT", -8, 8)

	buildPages()

	win.Tabs = {}
	for i, def in ipairs(TABS) do
		local tab = CreateFrame("Button", "NeedySettingsTab" .. i, win, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(def[2])
		if i == 1 then
			tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 11, 2)
		else
			tab:SetPoint("LEFT", win.Tabs[i - 1], "RIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function()
			selectPage(def[1])
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
				PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			end
		end)
		win.Tabs[i] = tab
	end
	if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(win, #TABS) end

	selectPage("rolls")
	win:HookScript("OnShow", function() SettingsWindow.Refresh() end)
end

function SettingsWindow.Refresh()
	if win and current then pages[current]:Refresh() end
end

function SettingsWindow.Show(page)
	if not win then create() end
	if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
		HideUIPanel(SettingsPanel)
	end
	if page and pages[page] then selectPage(page) end
	win:Show()
	win:Raise()
	SettingsWindow.Refresh()
end

function SettingsWindow.Toggle()
	if win and win:IsShown() then win:Hide() else SettingsWindow.Show() end
end

-- The game's Settings > AddOns page only holds a button that opens our own window: the game won't open
-- bags and the like while Settings is up, which makes testing awkward (same approach as Jest).
function SettingsWindow.Register()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local launcher = CreateFrame("Frame")
	local title = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Needy")
	local open = W.Button(launcher, "Open Needy settings", 180, 24)
	open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	open:SetScript("OnClick", function() SettingsWindow.Show() end)
	local hint = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
	hint:SetText("Also on the minimap icon, or type /needy help.")
	local category = Settings.RegisterCanvasLayoutCategory(launcher, "Needy")
	Settings.RegisterAddOnCategory(category)
end

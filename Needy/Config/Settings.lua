-- Needy's settings window: a sidebar of sections on the left, controls on the right.
-- Opened from the minimap icon, /needy options, or the launcher in the game's Settings > AddOns.
local _, ns = ...

local SettingsWindow = {}
ns.SettingsWindow = SettingsWindow

local W = ns.Widgets
local C = W.C

local WIDTH, HEIGHT = 600, 540
local SIDEBAR = 150
local PAGE_PAD = 20
local PAGE_WIDTH = WIDTH - SIDEBAR - PAGE_PAD * 2 - 2

local win
local pages = {}
local navButtons = {}
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
	local page = CreateFrame("Frame", nil, win.content)
	page:SetPoint("TOPLEFT", SIDEBAR + 1 + PAGE_PAD, -PAGE_PAD + 4)
	page:SetPoint("BOTTOMRIGHT", -PAGE_PAD, 10)
	page:Hide()
	page.controls = {}
	page.y = 0

	local heading = W.Text(page, "big")
	heading:SetPoint("TOPLEFT", 0, 0)
	heading:SetText(title)
	page.y = -26
	if blurb then
		local b = W.Text(page, "muted")
		b:SetPoint("TOPLEFT", 0, page.y)
		b:SetWidth(PAGE_WIDTH)
		b:SetText(blurb)
		page.y = page.y - (b:GetStringHeight() or 12) - 14
	else
		page.y = page.y - 8
	end

	function page:Add(control, height, gap)
		control:SetPoint("TOPLEFT", 0, self.y)
		self.y = self.y - (height or control:GetHeight()) - (gap or 14)
		if control.Refresh then table.insert(self.controls, control) end
		return control
	end
	function page:Section(text)
		self.y = self.y - 4
		local s = W.Section(self, text)
		s:SetPoint("TOPLEFT", 0, self.y)
		s.line:SetPoint("RIGHT", self, "RIGHT", 0, 0)
		self.y = self.y - 24
	end
	function page:Toggle(label, desc, key, after)
		local get, set = setting(key, after)
		return self:Add(W.Toggle(self, PAGE_WIDTH, label, desc, get, set))
	end
	function page:Slider(label, key, minV, maxV, step, fmt)
		local get, set = setting(key)
		return self:Add(W.Slider(self, PAGE_WIDTH, label, minV, maxV, step, fmt, get, set))
	end
	function page:Segmented(label, options, get, set)
		return self:Add(W.Segmented(self, PAGE_WIDTH, label, options, get, set))
	end
	function page:Buttons(list)
		local x = 0
		local row = CreateFrame("Frame", nil, self)
		row:SetSize(PAGE_WIDTH, 24)
		for _, def in ipairs(list) do
			local b = W.Button(row, def[1], def[3] or 130, 24, def[4])
			b:SetPoint("LEFT", x, 0)
			b:SetScript("OnClick", def[2])
			x = x + (def[3] or 130) + 6
		end
		return self:Add(row, 24)
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
	p:Toggle("Replace Blizzard's roll frames", "Hide the default loot roll popups and use Needy's bars.", "replaceBlizzard")
	p:Toggle("Animations", "Bars pop in; results spin a die, then the winner lands with a flash.", "animations")
	p:Toggle("Lock position", "Turn off to get a handle you can drag the bars around with. They snap to the centre of the screen, like Edit Mode.", "locked")
	p:Segmented("New bars stack", { { false, "Downwards" }, { true, "Upwards" } },
		function() return ns.settings.growUp end,
		function(v) ns.settings.growUp = v; ns.RollFrame.ApplySettings() end)
	p:Slider("Scale", "scale", ns.Limits.scale[1], ns.Limits.scale[2], 0.05, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Slider("Bar width", "barWidth", ns.Limits.barWidth[1], ns.Limits.barWidth[2], 10, function(v) return v .. " px" end)
	p:Buttons({
		{ "Show test rolls", function() ns.TestMode.Start(3) end, 130, "accent" },
		{ "Reset position", function() ns.RollFrame.ResetPosition() end, 120 },
	})

	-- Roll log -----------------------------------------------------------------
	p = newPage("log", "Roll Log", "A dice tab on screen during a run. Click it to open a list of everything that's dropped, who won it and with what roll.")
	p:Toggle("Show the Roll Log tab", "Appears while you're in a dungeon or raid (or a test run).", "showLog")
	p:Slider("Rows shown", "logRows", ns.Limits.logRows[1], ns.Limits.logRows[2], 1, function(v) return v .. " items" end)
	p:Buttons({
		{ "Reset position", function() ns.RollLog.ResetPosition() end, 120 },
		{ "Open full history", function() ns.HistoryWindow.Show() end, 140 },
	})

	-- End of run ---------------------------------------------------------------
	p = newPage("awards", "End of Run", "When you leave the instance, Needy hands out titles: Loot Hoarder, Unlucky, The Saint and friends.")
	p:Toggle("Show the awards window", "Pops up the Run Awards when the run ends.", "showSummary")
	p:Buttons({
		{ "Preview awards", function() ns.TestMode.Run() end, 130, "accent" },
	})

	-- General ------------------------------------------------------------------
	p = newPage("general", "General")
	p:Toggle("Minimap icon", "Left-click opens settings, right-click opens the roll history.", "minimapShow",
		function() ns.MinimapButton.Update() end)
	p:Slider("Runs kept in history", "historyLimit", ns.Limits.historyLimit[1], ns.Limits.historyLimit[2], 1, function(v) return v .. " runs" end)
	p:Toggle("Keep test runs in history", "Save /needy test runs alongside real ones.", "keepTestSessions")
	p:Section("Testing")
	p:Buttons({
		{ "Test rolls", function() ns.TestMode.Start(3) end, 110 },
		{ "More rolls", function() ns.TestMode.Start(2) end, 110 },
		{ "End test run", function() ns.TestMode.End() end, 110 },
	})
	p:Buttons({
		{ "Simulate a whole run", function() ns.TestMode.Run() end, 170, "accent" },
	})
	p:Section("Data")
	local resetArmed
	p:Buttons({
		{ "Reset all data", function(self)
			if not resetArmed then
				resetArmed = true
				self:SetText("Click again to confirm")
				C_Timer.After(4, function()
					resetArmed = false
					self:SetText("Reset all data")
				end)
				return
			end
			resetArmed = false
			self:SetText("Reset all data")
			SlashCmdList.NEEDY("reset confirm")
			SettingsWindow.Refresh()
		end, 170 },
	})
end

local NAV = {
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
	for _, b in ipairs(navButtons) do
		local on = b.key == key
		b.marker:SetShown(on)
		b.bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
		b.text:SetTextColor(on and C.accent[1] or C.text[1], on and C.accent[2] or C.text[2], on and C.accent[3] or C.text[3])
	end
	pages[key]:Refresh()
end

local function create()
	win = W.Window("NeedySettings", "Needy Settings", WIDTH, HEIGHT)
	win:SetPoint("CENTER")
	local c = win.content

	local side = CreateFrame("Frame", nil, c)
	side:SetPoint("TOPLEFT")
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR)
	side.bg = side:CreateTexture(nil, "BACKGROUND")
	side.bg:SetAllPoints()
	side.bg:SetColorTexture(0, 0, 0, 0.25)
	local divider = side:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPRIGHT")
	divider:SetPoint("BOTTOMRIGHT")
	divider:SetWidth(1)
	divider:SetColorTexture(C.hairline[1], C.hairline[2], C.hairline[3], C.hairline[4])

	for i, def in ipairs(NAV) do
		local b = CreateFrame("Button", nil, side)
		b:SetSize(SIDEBAR, 32)
		b:SetPoint("TOPLEFT", 0, -10 - (i - 1) * 34)
		b.key = def[1]
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(1, 1, 1, 0.04)
		b.marker = b:CreateTexture(nil, "ARTWORK")
		b.marker:SetPoint("TOPLEFT")
		b.marker:SetPoint("BOTTOMLEFT")
		b.marker:SetWidth(3)
		b.marker:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
		b.text = W.Text(b, "body")
		b.text:SetPoint("LEFT", 16, 0)
		b.text:SetText(def[2])
		b:SetScript("OnClick", function() selectPage(def[1]) end)
		navButtons[i] = b
	end

	local version = W.Text(side, "tiny")
	version:SetPoint("BOTTOMLEFT", 14, 12)
	version:SetText("Needy " .. W.Version() .. "\n|cff6b6b75/needy help for commands|r")

	buildPages()
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
	local open = W.Button(launcher, "Open Needy settings", 200, 26, "accent")
	open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	open:SetScript("OnClick", function() SettingsWindow.Show() end)
	local hint = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
	hint:SetText("Also on the minimap icon, or type /needy help.")
	local category = Settings.RegisterCanvasLayoutCategory(launcher, "Needy")
	Settings.RegisterAddOnCategory(category)
end

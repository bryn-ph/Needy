-- Needy's settings window: a standard game window with a tab per section along the bottom (as in Jest).
-- Opened from the minimap icon, /needy options, or the launcher in the game's Settings > AddOns.
local _, ns = ...

local SettingsWindow = {}
ns.SettingsWindow = SettingsWindow

local W = ns.Widgets

local WIDTH, HEIGHT = 600, 540
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
		return h
	end
	-- A control that takes whatever room is left.
	function page:Fill(control)
		control:SetPoint("TOPLEFT", 0, self.y)
		control:SetPoint("BOTTOMRIGHT")
		table.insert(self.controls, control)
		return control
	end
	function page:Check(label, tip, key, after)
		local get, set = setting(key, after)
		return self:Add(W.Check(self, label, tip, get, set), 26, 2)
	end
	function page:Slider(label, key, minV, maxV, step, fmt)
		local get, set = setting(key)
		return self:Add(W.Slider(self, label, minV, maxV, step, fmt, get, set), 26, 8)
	end
	function page:Segmented(label, items, get, set, tip, width)
		local row = CreateFrame("Frame", nil, self)
		row:SetSize(PAGE_WIDTH, 24)
		local l = W.Text(row, "GameFontHighlight")
		l:SetPoint("LEFT")
		l:SetText(label)
		if tip then
			row:EnableMouse(true)
			row:SetScript("OnEnter", function(r) W.Tip(r, label, tip) end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		local seg = W.Segmented(row, items, width or 230, set)
		seg:SetPoint("LEFT", 154, 0)
		function row:Refresh() seg:SetValue(get()) end
		return self:Add(row, 24, 10)
	end
	-- A row of buttons; each def is { text, onClick, width, tooltip }.
	function page:Buttons(list)
		local row = CreateFrame("Frame", nil, self)
		row:SetSize(PAGE_WIDTH, 22)
		local x = 0
		for _, def in ipairs(list) do
			local b = W.Button(row, def[1], def[3] or 130, 22)
			b:SetPoint("LEFT", x, 0)
			b:SetScript("OnClick", def[2])
			if def[4] then
				b:SetScript("OnEnter", function(self) W.Tip(self, def[1], def[4]) end)
				b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			end
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
	local p = newPage("rolls", "Roll Frame")
	p:Check("Replace Blizzard's roll frames", nil, "replaceBlizzard")

	p:Header("Look")
	local themes = {}
	for _, t in ipairs(ns.Themes.LIST) do table.insert(themes, { value = t.key, text = t.name }) end
	p:Segmented("Theme", themes,
		function() return ns.Themes.Key() end,
		function(v) ns.settings.theme = v; ns.RollFrame.ApplySettings() end, nil, 280)
	p:Slider("Scale", "scale", ns.Limits.scale[1], ns.Limits.scale[2], 0.05, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Slider("Bar width", "barWidth", ns.Limits.barWidth[1], ns.Limits.barWidth[2], 10, function(v) return tostring(v) end)
	p:Check("Animations", nil, "animations")
	p:Check("Flash new roll bars", nil, "flashBars",
		function(on) ns.RollFrame.FlashShown(on) end)

	p:Header("Position")
	p:Segmented("New bars stack", { { value = false, text = "Downwards" }, { value = true, text = "Upwards" } },
		function() return ns.settings.growUp end,
		function(v) ns.settings.growUp = v; ns.RollFrame.ApplySettings() end)
	local lock = p:Check("Lock position", nil, "locked")
	local reset = W.Button(p, "Reset position", 120, 22)
	reset:SetPoint("LEFT", lock.label, "RIGHT", 24, -1)
	reset:SetScript("OnClick", function() ns.RollFrame.ResetPosition() end)

	-- Roll log -----------------------------------------------------------------
	p = newPage("log", "Roll Log")
	p:Check("Show the Roll Log", nil, "showLog")
	p:Slider("Rows shown", "logRows", ns.Limits.logRows[1], ns.Limits.logRows[2], 1, function(v) return tostring(v) end)
	p:Buttons({
		{ "Reset position", function() ns.RollLog.ResetPosition() end, 120 },
		{ "Open history", function() ns.HistoryWindow.Show() end, 120 },
	})

	-- Wishlist -----------------------------------------------------------------
	p = newPage("wishlist", "Wishlist")
	p:Check("Wishlist sound", nil, "wishlistSound")
	p:Check("Remove items when you get them", nil, "removeOnLoot")
	p:Check("Share my wishlist", nil, "shareWishlist",
		function() ns.Sharing.SettingChanged() end)
	p:Check("Count others' wants in DungeonJournal", nil, "journalBadges",
		function() ns.DungeonJournal.Refresh() end)
	local tracked = p:Header("Your wishlist")
	p:Fill(ns.WishlistPanel.Create(p, PAGE_WIDTH, tracked))

	-- End of run ---------------------------------------------------------------
	p = newPage("awards", "End of Run")
	p:Check("Show the awards window", nil, "showSummary")
	p:Buttons({
		{ "Preview", function() ns.TestMode.Run() end, 100 },
	})

	-- General ------------------------------------------------------------------
	p = newPage("general", "General")
	p:Check("Minimap icon", nil, "minimapShow",
		function() ns.MinimapButton.Update() end)

	p:Header("History")
	p:Slider("Runs kept", "historyLimit", ns.Limits.historyLimit[1], ns.Limits.historyLimit[2], 1, function(v) return tostring(v) end)
	p:Check("Keep test runs", nil, "keepTestSessions")

	p:Header("Testing")
	p:Buttons({
		{ "Test rolls", function() ns.TestMode.Start(3) end, 106 },
		{ "Wishlist drop", function() ns.TestMode.Wish() end, 106 },
		{ "End test run", function() ns.TestMode.End() end, 106 },
		{ "Simulate run", function() ns.TestMode.Run() end, 106 },
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
	{ "wishlist", "Wishlist" },
	{ "awards", "End of Run" },
	{ "general", "General" },
}

local function selectPage(key)
	current = key
	for k, page in pairs(pages) do
		page:SetShown(k == key)
	end
	win:SelectTab(key)
	pages[key]:Refresh()
end

local function create()
	win = W.Window("NeedySettings", "Needy - Settings", WIDTH, HEIGHT)
	win:SetPoint("CENTER")

	-- Practice bars from any tab, to see a change take effect.
	local test = W.Button(win, "Test rolls", 96, 22)
	test:SetPoint("TOPRIGHT", -10, -30)
	test:SetScript("OnClick", function() ns.TestMode.Start(3) end)

	local version = W.Text(win, "GameFontDisableSmall")
	version:SetPoint("RIGHT", test, "LEFT", -10, 0)
	version:SetText("Needy " .. W.Version())
	version:SetJustifyH("RIGHT")

	win.inset = W.Inset(win)
	win.inset:SetPoint("TOPLEFT", 8, -60)
	win.inset:SetPoint("BOTTOMRIGHT", -8, 8)

	buildPages()

	W.Tabs(win, "NeedySettings", TABS, selectPage)
	selectPage("rolls")
	win:HookScript("OnShow", function() SettingsWindow.Refresh() end)
	local function refreshWishlist()
		if win:IsShown() and current == "wishlist" then SettingsWindow.Refresh() end
	end
	ns.Listen("WISHLIST_CHANGED", refreshWishlist)
	ns.Listen("SHARED_WISHLISTS_CHANGED", refreshWishlist)
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

-- Which tab is showing ("rolls", "wishlist", ...).
function SettingsWindow.Current()
	return current
end

-- page: the tab to open on (the last one shown, if not given).
function SettingsWindow.Toggle(page)
	if win and win:IsShown() then win:Hide() else SettingsWindow.Show(page) end
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
	local category = Settings.RegisterCanvasLayoutCategory(launcher, "Needy")
	Settings.RegisterAddOnCategory(category)
end

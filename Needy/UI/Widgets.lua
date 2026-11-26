-- Shared UI pieces, in the game's own style (Blizzard templates, fonts and tooltip borders), as in Jest.
local addonName, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\icon"
Widgets.GOLD = { 1, 0.82, 0 } -- NORMAL_FONT_COLOR
Widgets.GOLD_HEX = "ffffd100"
Widgets.GREY_HEX = "ff8c8c8c"
Widgets.FAINT_HEX = "ff5e5e5e"

Widgets.FLAT_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

-- Text -----------------------------------------------------------------------------------------

function Widgets.Text(parent, template, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	return fs
end

-- Full width of a fontstring's text, ignoring any width it's been squeezed to.
function Widgets.StringWidth(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

-- Surfaces --------------------------------------------------------------------------------------

-- A dark box with the tooltip-style border the game uses for things like the loot roll popups.
function Widgets.NativeBox(frame, alpha)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, alpha or 0.8)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- Subtle bordered panel used for list rows and cards.
function Widgets.Card(parent)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetBackdrop(Widgets.FLAT_BACKDROP)
	card:SetBackdropColor(1, 1, 1, 0.03)
	card:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
	return card
end

function Widgets.Hairline(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(1, 1, 1, 0.12)
	t:SetHeight(1)
	return t
end

-- Section title with a hairline running to the right edge of `parent`.
function Widgets.Header(parent, text)
	local fs = Widgets.Text(parent, "GameFontNormal")
	fs:SetText(text)
	local line = Widgets.Hairline(parent)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	fs.line = line
	return fs
end

-- The loot toast's icon border for a quality (as the game's roll popup picks it).
local TOAST_BORDERS = { [0] = "gray", "white", "green", "blue", "purple", "orange", "artifact", "heirloom", "heirloom" }
function Widgets.ToastBorderAtlas(quality)
	local cm = ColorManager
	if quality and cm and cm.GetAtlasDataForLootBorderItemQuality then
		local ok, atlas = pcall(cm.GetAtlasDataForLootBorderItemQuality, quality)
		if ok and type(atlas) == "string" then return atlas end
	end
	return "loottoast-itemborder-" .. (TOAST_BORDERS[quality or 2] or "green")
end

-- An item icon with the game's quality-coloured icon border.
function Widgets.ItemIcon(parent, size)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(size, size)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	ns.CropIcon(f.icon)
	f.border = f:CreateTexture(nil, "OVERLAY")
	f.border:SetAllPoints()
	f.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	f.count:SetPoint("BOTTOMRIGHT", -2, 2)
	f.style = "native"
	-- Colours the border for the item's quality, in whichever style it has.
	function f:SetItem(texture, quality)
		self.icon:SetTexture(texture or ns.FALLBACK_ICON)
		if quality ~= nil and ns.IsSecret(quality) then quality = nil end
		self.quality = quality
		local r, g, b = ns.QualityColor(quality)
		if self.style == "toast" then
			self.border:SetAtlas(Widgets.ToastBorderAtlas(quality))
			self.border:SetVertexColor(1, 1, 1)
		else
			self.border:SetVertexColor(r, g, b)
		end
		if self.edge then self.edge:SetBackdropBorderColor(r, g, b, 1) end
	end
	-- "native": the game's bevelled icon frame, tinted. "toast": the loot toast's quality border, as on the
	-- game's roll popup. "flat": a 1px quality-coloured edge. "none": just the icon.
	function f:SetBorderStyle(style)
		if self.style == style then return end
		self.style = style
		self.border:ClearAllPoints()
		if style == "toast" then
			-- 42 round a 34 icon on the popup, a touch low.
			local s = self:GetWidth() * 42 / 34
			self.border:SetSize(s, s)
			self.border:SetPoint("CENTER", 0, -2 * self:GetWidth() / 34)
		else
			self.border:SetTexture("Interface\\Common\\WhiteIconFrame")
			self.border:SetAllPoints()
		end
		if style == "flat" and not self.edge then
			self.edge = CreateFrame("Frame", nil, self, "BackdropTemplate")
			self.edge:SetPoint("TOPLEFT", -1, 1)
			self.edge:SetPoint("BOTTOMRIGHT", 1, -1)
			self.edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		end
		self.border:SetShown(style == "native" or style == "toast")
		if self.edge then self.edge:SetShown(style == "flat") end
		self:SetItem(self.icon:GetTexture(), self.quality)
	end
	-- The wishlist heart on the icon's corner.
	function f:SetWished(wished)
		if wished and not self.mark then
			local markSize = math.max(11, math.floor(size * 0.42))
			self.mark = self:CreateTexture(nil, "OVERLAY", nil, 7)
			self.mark:SetTexture(ns.Wishlist.MARK)
			self.mark:SetSize(markSize, markSize)
			self.mark:SetPoint("CENTER", self, "TOPLEFT", 3, -3)
		end
		if self.mark then self.mark:SetShown(wished) end
	end
	return f
end

-- The "Wishlist" tag, in the heart's red and gold.
function Widgets.WishTag(parent)
	local tag = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	tag:SetBackdrop(Widgets.FLAT_BACKDROP)
	local red, rim = ns.Wishlist.RED, ns.Wishlist.RIM
	tag:SetBackdropColor(red[1], red[2], red[3], 0.45)
	tag:SetBackdropBorderColor(rim[1], rim[2], rim[3], 0.8)
	local mark = tag:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(ns.Wishlist.MARK)
	mark:SetSize(10, 10)
	mark:SetPoint("LEFT", 4, 0)
	local label = Widgets.Text(tag, "GameFontHighlightSmall")
	label:SetPoint("LEFT", mark, "RIGHT", 3, 0)
	label:SetText("Wishlist")
	tag.fullWidth = Widgets.StringWidth(label) + 22
	tag:SetSize(tag.fullWidth, 15)
	return tag
end

-- Buttons and controls -------------------------------------------------------------------------------

function Widgets.Button(parent, text, width, height)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, height or 22)
	b:SetText(text or "")
	return b
end

-- The spellbook's page arrows; dir = "prev" or "next".
function Widgets.PageButton(parent, dir, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(28, 28)
	local base = dir == "prev" and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage"
	b:SetNormalTexture(base .. "-Up")
	b:SetPushedTexture(base .. "-Down")
	b:SetDisabledTexture(base .. "-Disabled")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetScript("OnClick", onClick)
	return b
end

-- A titled tooltip with wrapped text.
function Widgets.Tip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 1, 1)
	if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
	GameTooltip:Show()
end

function Widgets.Check(parent, text, tooltipText, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	check.label:SetText(text)
	check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	check:SetScript("OnEnter", function(self)
		if tooltipText then Widgets.Tip(self, text, tooltipText) end
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function check:Refresh() self:SetChecked(get() and true or false) end
	return check
end

-- A labelled slider with steppers, like the game's Settings (MinimalSliderWithSteppersTemplate).
-- format(value) is the text shown on its right. get() reads, set(value) stores (rounded to the step).
function Widgets.Slider(parent, text, minValue, maxValue, step, format, get, set)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(400, 26)
	holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	holder.label:SetPoint("LEFT")
	holder.label:SetWidth(150)
	holder.label:SetJustifyH("LEFT")
	holder.label:SetText(text)
	local slider = CreateFrame("Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", holder.label, "RIGHT", 4, 0)
	slider:SetSize(230, 26)
	holder.slider = slider

	local function round(v)
		return math.floor((v - minValue) / step + 0.5) * step + minValue
	end
	local formatters = {}
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		formatters[MinimalSliderWithSteppersMixin.Label.Right] = function(v) return format(round(v)) end
	end
	function holder:Refresh()
		self.refreshing = true
		slider:Init(get(), minValue, maxValue, (maxValue - minValue) / step, formatters)
		self.refreshing = false
	end
	if slider.RegisterCallback and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
		slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
			if not holder.refreshing then set(round(v)) end
		end, holder)
	end
	return holder
end

-- Row of mutually exclusive options. items = { { value = ..., text = ... }, ... };
-- onSelect(value) fires on click. holder:SetValue(v) shows the current one.
function Widgets.Segmented(parent, items, width, onSelect)
	local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	holder:SetSize(width, 24)
	holder:SetBackdrop(Widgets.FLAT_BACKDROP)
	holder:SetBackdropColor(0, 0, 0, 0.5)
	holder:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	holder.buttons = {}
	local segW = width / #items
	for i, item in ipairs(items) do
		local b = CreateFrame("Button", nil, holder)
		b:SetPoint("TOPLEFT", (i - 1) * segW + 1, -1)
		b:SetSize(segW - 2, 22)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(1, 0.82, 0, 0.25)
		b.bg:Hide()
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.08)
		if i > 1 then
			local div = b:CreateTexture(nil, "BORDER")
			div:SetColorTexture(0.4, 0.4, 0.4, 1)
			div:SetWidth(1)
			div:SetPoint("TOPLEFT", -1, 0)
			div:SetPoint("BOTTOMLEFT", -1, 0)
		end
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(item.text)
		b.value = item.value
		b:SetScript("OnClick", function()
			onSelect(item.value)
			holder:SetValue(item.value)
		end)
		holder.buttons[i] = b
	end
	function holder:SetValue(value)
		for _, b in ipairs(self.buttons) do
			local on = b.value == value
			b.bg:SetShown(on)
			if on then
				b.text:SetTextColor(1, 1, 1)
			else
				b.text:SetTextColor(0.62, 0.62, 0.62)
			end
		end
	end
	return holder
end

-- Windows ---------------------------------------------------------------------------------------------

local function child(frame, key)
	local v = rawget(frame, key)
	return type(v) == "table" and v or nil
end
Widgets.Child = child

-- A standard game window (ButtonFrameTemplate) with Needy's icon in the portrait, a title and close button.
-- Movable by dragging; Esc closes it. Its Inset is hidden; callers add their own where they want one.
function Widgets.Window(name, title, width, height)
	local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	f:SetSize(width, height)
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
	local container = child(f, "PortraitContainer")
	local portrait = container and child(container, "portrait")
	if portrait then portrait:SetTexture(Widgets.ICON) end
	local inset = child(f, "Inset")
	if inset then inset:Hide() end
	if f.SetTitle then
		f:SetTitle(title)
	else
		local tc = child(f, "TitleContainer")
		if tc and child(tc, "TitleText") then tc.TitleText:SetText(title) end
	end
	f:Hide()
	table.insert(UISpecialFrames, name) -- Esc closes it
	return f
end

-- Tabs along the bottom of a window, named <window name>Tab<i>. items = { { key, text }, ... }.
-- onClick(key) runs on a click; win:SelectTab(key) lights one up.
function Widgets.Tabs(win, name, items, onClick)
	win.Tabs = {}
	for i, def in ipairs(items) do
		local tab = CreateFrame("Button", name .. "Tab" .. i, win, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(def[2])
		if i == 1 then
			tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 11, 2)
		else
			tab:SetPoint("LEFT", win.Tabs[i - 1], "RIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function()
			onClick(def[1])
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
				PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			end
		end)
		win.Tabs[i] = tab
	end
	if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(win, #items) end
	function win:SelectTab(key)
		for i, def in ipairs(items) do
			if def[1] == key and PanelTemplates_SetTab then PanelTemplates_SetTab(self, i) end
		end
	end
end

-- Tabs along the top of a list, as on the game's Macro window (PanelTopTabButtonTemplate). items =
-- { { key, text }, ... }; onClick(key) runs on a click. Returns their holder, with :Select(key) to light
-- one up and :SetLabel(key, text), which resizes the tab to fit. Anchor the holder's BOTTOMLEFT.
local TOP_TAB_PAD = 12

function Widgets.TopTabs(parent, items, onClick)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(10, 24)
	holder.Tabs = {}
	holder.tabPadding = TOP_TAB_PAD
	holder.minTabWidth = 80
	local byKey = {}
	local function fit(tab)
		if PanelTemplates_TabResize then
			PanelTemplates_TabResize(tab, TOP_TAB_PAD, nil, holder.minTabWidth)
		end
	end
	for i, def in ipairs(items) do
		local tab = CreateFrame("Button", nil, holder, "PanelTopTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(def[2])
		if i == 1 then
			tab:SetPoint("BOTTOMLEFT")
		else
			tab:SetPoint("LEFT", holder.Tabs[i - 1], "RIGHT", 2, 0)
		end
		tab:SetScript("OnClick", function()
			onClick(def[1])
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
				PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			end
		end)
		holder.Tabs[i] = tab
		byKey[def[1]] = i
		fit(tab)
	end
	if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(holder, #items) end
	function holder:Select(key)
		if byKey[key] and PanelTemplates_SetTab then PanelTemplates_SetTab(self, byKey[key]) end
	end
	function holder:SetLabel(key, text)
		local tab = self.Tabs[byKey[key]]
		if tab and tab:GetText() ~= text then
			tab:SetText(text)
			fit(tab)
		end
	end
	return holder
end

-- A recessed panel (InsetFrameTemplate) for lists.
function Widgets.Inset(parent)
	return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

-- A vertical scroll area with a slim indicator. Returns scrollFrame, content; size content's height.
function Widgets.ScrollArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(4)
	thumb:SetColorTexture(1, 0.82, 0, 0.35)
	thumb:Hide()

	local function update()
		local view, total = scroll:GetHeight() or 0, content:GetHeight() or 0
		if total <= view + 1 or view <= 0 then
			thumb:Hide()
			return
		end
		local h = math.max(20, view * view / total)
		local y = (scroll:GetVerticalScroll() or 0) / (total - view) * (view - h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -y)
		thumb:SetHeight(h)
		thumb:Show()
	end

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
		local v = math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40))
		self:SetVerticalScroll(v)
		update()
	end)
	scroll:SetScript("OnSizeChanged", function(_, w)
		content:SetWidth(w)
		update()
	end)
	scroll.UpdateThumb = update
	return scroll, content
end

-- Tooltips ------------------------------------------------------------------------------------------

-- Everyone's choice and roll for a drop. withItem = true starts with the item's own tooltip.
function Widgets.DropTooltip(owner, drop, link, withItem)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if withItem and link then
		GameTooltip:SetHyperlink(link)
		GameTooltip:AddLine(" ")
	else
		GameTooltip:SetText(link or (drop and drop.name) or "Roll", 1, 1, 1)
	end
	if not drop then
		GameTooltip:AddLine("Waiting for the group's choices...", 0.7, 0.7, 0.7)
		GameTooltip:Show()
		return
	end
	local names = {}
	for name in pairs(drop.rolls) do table.insert(names, name) end
	table.sort(names, function(a, b)
		local ra, rb = drop.rolls[a], drop.rolls[b]
		local ta, tb = ns.CHOICE_TIER[ra.choice] or 0, ns.CHOICE_TIER[rb.choice] or 0
		if ta ~= tb then return ta > tb end
		if (ra.roll or 0) ~= (rb.roll or 0) then return (ra.roll or 0) > (rb.roll or 0) end
		return a < b
	end)
	local resolved = ns.Titles.IsResolved(drop)
	for _, name in ipairs(names) do
		local r = drop.rolls[name]
		local label = ns.ChoiceIcon(r.choice) .. " " .. (ns.Choices[r.choice] and ns.Choices[r.choice].label or r.choice)
		if r.choice == "none" and not resolved then label = "|cff888888choosing...|r" end
		GameTooltip:AddDoubleLine(ns.ColorName(name, r.class) .. (name == drop.winner and " |cffffd100(won)|r" or ""),
			label .. (r.roll and ("  |cffffffff" .. r.roll .. "|r") or ""))
	end
	GameTooltip:Show()
end

function Widgets.ItemTooltip(owner, link)
	if not link then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	GameTooltip:Show()
end

-- Recorded drops ------------------------------------------------------------------------------------

-- Item icon for a recorded drop (its saved texture, or looked up from the link).
function Widgets.DropIcon(drop)
	if drop.texture then return drop.texture end
	if drop.link and C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, _, icon = C_Item.GetItemInfoInstant(drop.link)
		if icon then return icon end
	end
	return ns.FALLBACK_ICON
end

-- Quality of a recorded drop (saved, or from the item cache).
function Widgets.DropQuality(drop)
	if drop.quality then return drop.quality end
	if drop.link and C_Item and C_Item.GetItemQualityByID then
		local q = C_Item.GetItemQualityByID(drop.link)
		if q then return q end
	end
	if drop.link and C_Item and C_Item.GetItemInfo then
		local _, _, q = C_Item.GetItemInfo(drop.link)
		if q then return q end
	end
	return 1
end

function Widgets.DropName(drop)
	return drop.name or (drop.link and drop.link:match("%[(.-)%]")) or "?"
end

function Widgets.Version()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = get and get(addonName, "Version")
	if not v or v:find("@") then return "dev" end
	return v
end

-- Roster lines ---------------------------------------------------------------------------------------
-- Who chose what, grouped by choice ("[need] Grimbolt 87, You 45 · [greed] Lunaria · [pass] 2"), squeezed
-- step by step until it fits `width`: passers and waiting players become counts first, then only the top
-- names of each group are kept ("+2"), and finally everything is counts. Sets fs's text and returns it.

local ROSTER_GROUPS = { "need", "greed", "pass", "none" }
local ROSTER_LEVELS = {
	{ need = "all", greed = "all", pass = "all", none = "all" },
	{ need = "all", greed = "all", pass = "count", none = "count" },
	{ need = 3, greed = 2, pass = "count", none = "count" },
	{ need = 2, greed = 1, pass = "count", none = "count" },
	{ need = 1, greed = "count", pass = "count", none = "count" },
	{ need = "count", greed = "count", pass = "count", none = "count" },
}
local SEPARATOR = "  |cff5e5e5e·|r  "

function Widgets.FitRoster(fs, drop, width, opts)
	opts = opts or {}
	local resolved = ns.Titles.IsResolved(drop)
	local groups = { need = {}, greed = {}, pass = {}, none = {} }
	for name, r in pairs(drop.rolls or {}) do
		if name ~= opts.exclude then
			table.insert(groups[r.choice] or groups.none, { name = name, class = r.class, roll = r.roll, me = ns.IsMe(name, r) })
		end
	end
	for _, list in pairs(groups) do
		table.sort(list, function(a, b)
			if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
			return a.name < b.name
		end)
	end

	local function nameText(key, p)
		if key == "none" then
			return ("|c%s%s|r"):format(Widgets.FAINT_HEX, p.me and "You" or ns.ShortName(p.name))
		end
		local n = p.me and ("|c%sYou|r"):format(Widgets.GOLD_HEX) or ns.ColorName(p.name, p.class)
		if p.roll and key ~= "pass" then
			n = n .. " |cffffffff" .. p.roll .. "|r"
		end
		return n
	end

	local function groupText(key, mode)
		local list = groups[key]
		if #list == 0 then return nil end
		local head = key == "none"
			and ("|c%s%s|r "):format(Widgets.GREY_HEX, resolved and "no roll:" or "waiting:")
			or (ns.ChoiceIcon(key, 12) .. " ")
		if mode == "count" then
			return head .. "|cffcfcfcf" .. #list .. "|r"
		end
		local limit = mode == "all" and #list or mode
		local names = {}
		for i = 1, math.min(limit, #list) do
			names[i] = nameText(key, list[i])
		end
		local text = head .. table.concat(names, ", ")
		if #list > limit then
			text = text .. (" |c%s+%d|r"):format(Widgets.GREY_HEX, #list - limit)
		end
		return text
	end

	local text = opts.prefix or ""
	for _, level in ipairs(ROSTER_LEVELS) do
		local parts = {}
		for _, key in ipairs(ROSTER_GROUPS) do
			local t = groupText(key, level[key])
			if t then table.insert(parts, t) end
		end
		text = (opts.prefix or "") .. table.concat(parts, SEPARATOR)
		fs:SetText(text)
		if Widgets.StringWidth(fs) <= width then
			return text
		end
	end
	return text -- the most compact form; the fontstring cuts it off with "..." if even that doesn't fit
end

-- Who else wants an item -------------------------------------------------------------------------------
-- `who` is ns.Sharing.WhoWants's { group, guild, count }. An item someone in your group wants as well as
-- you is contested (orange); one only guildmates want too is shared (gold).

Widgets.CONTESTED = { 1, 0.5, 0.1 }
Widgets.CONTESTED_HEX = "ffff8019"

-- "contested", "shared" or nil, for an item on your wishlist.
function Widgets.Overlap(who)
	if #who.group > 0 then return "contested" end
	if #who.guild > 0 then return "shared" end
	return nil
end

local function wantersText(who, limit)
	local parts = {}
	for _, key in ipairs({ "group", "guild" }) do
		local list = who[key]
		if #list > 0 then
			local head = ("|c%s%s|r "):format(Widgets.GREY_HEX, key == "group" and "Group:" or "Guild:")
			if limit == 0 then
				table.insert(parts, head .. "|cffcfcfcf" .. #list .. "|r")
			else
				local names = {}
				for i = 1, math.min(limit, #list) do names[i] = ns.ColorName(list[i].name, list[i].class) end
				local text = head .. table.concat(names, ", ")
				if #list > limit then text = text .. (" |c%s+%d|r"):format(Widgets.GREY_HEX, #list - limit) end
				table.insert(parts, text)
			end
		end
	end
	return table.concat(parts, SEPARATOR)
end

-- "Group: Grimbolt, Saffi · Guild: Pip +3", with fewer names until it fits `width`, then just counts.
-- Sets fs's text and returns it.
function Widgets.FitWanters(fs, who, width)
	local most = math.max(#who.group, #who.guild)
	for _, limit in ipairs({ most, 4, 3, 2, 1, 0 }) do
		if limit <= most then
			local text = wantersText(who, limit)
			fs:SetText(text)
			if Widgets.StringWidth(fs) <= width then return text end
		end
	end
	return fs:GetText()
end

local TIP_NAMES = 8 -- per line; the rest are counted

-- Adds "Wanted by" lines to a tooltip that's showing the item. mine: it's on your wishlist too.
-- Returns whether it added anything.
function Widgets.AddWanters(tooltip, who, mine)
	if who.count == 0 then return false end
	tooltip:AddLine(" ")
	local head = ("|T%s:12:12|t "):format(ns.Wishlist.MARK)
	if mine then
		local c = #who.group > 0 and Widgets.CONTESTED or Widgets.GOLD
		tooltip:AddLine(head .. ("You and %d other%s want this"):format(who.count, who.count == 1 and "" or "s"), c[1], c[2], c[3])
	else
		tooltip:AddLine(head .. ("Wanted by %d other%s"):format(who.count, who.count == 1 and "" or "s"),
			Widgets.GOLD[1], Widgets.GOLD[2], Widgets.GOLD[3])
	end
	for _, key in ipairs({ "group", "guild" }) do
		local list = who[key]
		if #list > 0 then
			local names = {}
			for i = 1, math.min(#list, TIP_NAMES) do names[i] = ns.ColorName(list[i].name, list[i].class) end
			local text = table.concat(names, ", ")
			if #list > TIP_NAMES then text = text .. ("  |c%s+%d more|r"):format(Widgets.GREY_HEX, #list - TIP_NAMES) end
			tooltip:AddLine(("|c%s%s|r %s"):format(Widgets.GREY_HEX, key == "group" and "Group:" or "Guild:", text), 1, 1, 1, true)
		end
	end
	return true
end

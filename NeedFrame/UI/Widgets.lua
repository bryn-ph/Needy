-- NeedFrame's look: a flat, dark, modern skin with warm gold accents, plus the widgets built from it
-- (windows, buttons, toggles, sliders, segmented pickers, scroll areas, tooltips).
local addonName, ns = ...

local Widgets = {}
ns.Widgets = Widgets

-- Palette --------------------------------------------------------------------------------------

local C = {
	bg = { 0.067, 0.067, 0.082, 0.96 }, -- window / bar background
	raised = { 0.105, 0.105, 0.125, 1 }, -- title bars, cards, buttons
	hover = { 0.15, 0.15, 0.18, 1 },
	border = { 0, 0, 0, 1 },
	hairline = { 1, 1, 1, 0.07 },
	accent = { 1, 0.78, 0.28 }, -- warm gold
	text = { 0.93, 0.93, 0.93 },
	muted = { 0.62, 0.62, 0.68 },
	faint = { 0.42, 0.42, 0.47 },
	good = { 0.35, 0.9, 0.45 },
	bad = { 1, 0.4, 0.4 },
}
Widgets.C = C
Widgets.ACCENT_HEX = "ffffc747"
Widgets.MUTED_HEX = "ff9e9ead"

Widgets.FLAT_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

Widgets.LOGO = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"

-- Fonts ----------------------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function font(name, size, color, flags)
	local f = CreateFont(name)
	f:SetFont(FONT, size, flags or "")
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.85)
	f:SetTextColor(color[1], color[2], color[3])
	return f
end

Widgets.Fonts = {
	big = font("NeedFrameFontBig", 17, C.text),
	title = font("NeedFrameFontTitle", 13, C.text),
	heading = font("NeedFrameFontHeading", 12, C.accent),
	body = font("NeedFrameFontBody", 12, C.text),
	small = font("NeedFrameFontSmall", 11, C.text),
	muted = font("NeedFrameFontMuted", 11, C.muted),
	tiny = font("NeedFrameFontTiny", 10, C.muted),
	badge = font("NeedFrameFontBadge", 10, { 0.08, 0.06, 0.02 }),
}

-- Full width of a fontstring's text, ignoring any width it's been squeezed to.
function Widgets.StringWidth(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

function Widgets.Text(parent, fontKey, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(Widgets.Fonts[fontKey or "body"])
	fs:SetJustifyH("LEFT")
	return fs
end

-- Surfaces --------------------------------------------------------------------------------------

-- Flat background + 1px border. frame must inherit BackdropTemplate.
function Widgets.Skin(frame, bg, border)
	bg = bg or C.bg
	border = border or C.border
	frame:SetBackdrop(Widgets.FLAT_BACKDROP)
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Soft drop shadow drawn just outside the frame.
function Widgets.Shadow(frame, size)
	size = size or 4
	local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	t:SetPoint("TOPLEFT", -size, size)
	t:SetPoint("BOTTOMRIGHT", size, -size)
	t:SetColorTexture(0, 0, 0, 0.35)
	return t
end

-- A faint light-to-clear sheen across the top of a surface.
function Widgets.Sheen(frame, height, alpha)
	local t = frame:CreateTexture(nil, "BORDER")
	t:SetPoint("TOPLEFT", 1, -1)
	t:SetPoint("TOPRIGHT", -1, -1)
	t:SetHeight(height or 18)
	t:SetColorTexture(1, 1, 1, 1)
	if t.SetGradient and CreateColor then
		t:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, alpha or 0.05))
	else
		t:SetAlpha(alpha or 0.03)
	end
	return t
end

-- Horizontal colour fade, e.g. a quality tint running in from the left edge.
function Widgets.SetFade(tex, r, g, b, alpha)
	tex:SetColorTexture(1, 1, 1, 1)
	if tex.SetGradient and CreateColor then
		tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, alpha), CreateColor(r, g, b, 0))
	else
		tex:SetColorTexture(r, g, b, alpha * 0.5)
	end
end

function Widgets.Hairline(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(C.hairline[1], C.hairline[2], C.hairline[3], C.hairline[4])
	t:SetHeight(1)
	return t
end

-- A raised panel used for cards and list rows.
function Widgets.Card(parent)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Widgets.Skin(card, C.raised, { 0, 0, 0, 0.9 })
	return card
end

-- Section title in accent with a hairline to the right.
function Widgets.Section(parent, text)
	local fs = Widgets.Text(parent, "heading")
	fs:SetText(text)
	local line = Widgets.Hairline(parent)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	fs.line = line
	return fs
end

-- Buttons ---------------------------------------------------------------------------------------

local function hoverable(b, normalBg, normalBorder)
	b.normalBg, b.normalBorder = normalBg, normalBorder
	b:HookScript("OnEnter", function(self)
		if not self:IsEnabled() then return end
		self:SetBackdropColor(C.hover[1], C.hover[2], C.hover[3], 1)
		self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
	end)
	b:HookScript("OnLeave", function(self)
		self:SetBackdropColor(self.normalBg[1], self.normalBg[2], self.normalBg[3], self.normalBg[4] or 1)
		self:SetBackdropBorderColor(self.normalBorder[1], self.normalBorder[2], self.normalBorder[3], self.normalBorder[4] or 1)
	end)
	b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
	b:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
end

-- Flat text button. style = "accent" for the main action of a window.
function Widgets.Button(parent, text, width, height, style)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width or 100, height or 24)
	local bg = style == "accent" and { 0.22, 0.17, 0.06, 1 } or C.raised
	local border = style == "accent" and { C.accent[1], C.accent[2], C.accent[3], 0.55 } or { 0, 0, 0, 1 }
	Widgets.Skin(b, bg, border)
	local fs = Widgets.Text(b, "small")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetJustifyH("CENTER")
	if style == "accent" then fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
	b:SetFontString(fs)
	b:SetText(text or "")
	hoverable(b, bg, border)
	b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then fs:SetPoint("CENTER", 1, -1) end end)
	b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
	return b
end

-- A little "X" drawn from two rotated bars (no dependency on close-button art).
function Widgets.CloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	local bars = {}
	for i, angle in ipairs({ 45, -45 }) do
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetSize(12, 2)
		t:SetPoint("CENTER")
		t:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
		t:SetRotation(math.rad(angle))
		bars[i] = t
	end
	b:SetScript("OnEnter", function()
		for _, t in ipairs(bars) do t:SetColorTexture(C.bad[1], C.bad[2], C.bad[3], 1) end
	end)
	b:SetScript("OnLeave", function()
		for _, t in ipairs(bars) do t:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1) end
	end)
	b:SetScript("OnClick", onClick)
	return b
end

-- Chevron made of two rotated bars; dir = "left" or "right".
function Widgets.ArrowButton(parent, dir, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(24, 24)
	Widgets.Skin(b, C.raised, C.border)
	hoverable(b, C.raised, C.border)
	local sign = dir == "left" and 1 or -1
	for _, part in ipairs({ { 45, 3 }, { -45, -3 } }) do
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetSize(9, 2)
		t:SetPoint("CENTER", 0, part[2])
		t:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
		t:SetRotation(math.rad(part[1] * sign))
	end
	b:SetScript("OnClick", onClick)
	return b
end

-- Small pill showing a number (e.g. drop count).
function Widgets.Badge(parent)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Widgets.Skin(f, { C.accent[1], C.accent[2], C.accent[3], 1 }, { 0, 0, 0, 1 })
	f:SetHeight(14)
	f.text = Widgets.Text(f, "badge")
	f.text:SetPoint("CENTER", 0, 0)
	f.text:SetShadowOffset(0, 0)
	function f:SetValue(v)
		self.text:SetText(v)
		self:SetWidth(math.max(14, (self.text:GetStringWidth() or 6) + 8))
	end
	return f
end

-- Small rounded-ish info chip: "12 items".
function Widgets.Chip(parent)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Widgets.Skin(f, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.08 })
	f:SetHeight(18)
	f.text = Widgets.Text(f, "tiny")
	f.text:SetPoint("CENTER", 0, 0)
	function f:SetValue(v)
		self.text:SetText(v)
		self:SetWidth((self.text:GetStringWidth() or 20) + 14)
	end
	return f
end

-- Windows -----------------------------------------------------------------------------------------

local function openAnimation(f)
	local g = f:CreateAnimationGroup()
	local a = g:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(0.15)
	local s = g:CreateAnimation("Scale")
	s:SetScaleFrom(0.97, 0.97)
	s:SetScaleTo(1, 1)
	s:SetDuration(0.18)
	s:SetSmoothing("OUT")
	return g
end

-- A draggable window with a title bar, close button and a .content frame. Esc closes it.
function Widgets.Window(name, title, width, height)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	Widgets.Skin(f)
	Widgets.Shadow(f, 6)

	local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(30)
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	bar:SetBackdropColor(C.raised[1], C.raised[2], C.raised[3], 1)
	Widgets.Sheen(bar, 30, 0.04)
	local line = Widgets.Hairline(bar)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	local accentLine = bar:CreateTexture(nil, "ARTWORK")
	accentLine:SetPoint("BOTTOMLEFT")
	accentLine:SetSize(64, 1)
	accentLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetSize(18, 18)
	bar.icon:SetPoint("LEFT", 9, 0)
	bar.icon:SetTexture(Widgets.LOGO)
	bar.title = Widgets.Text(bar, "title")
	bar.title:SetPoint("LEFT", bar.icon, "RIGHT", 7, 0)
	bar.title:SetText(title)
	bar.close = Widgets.CloseButton(bar, function() f:Hide() end)
	bar.close:SetPoint("RIGHT", -5, 0)
	f.titleBar = bar

	f.content = CreateFrame("Frame", nil, f)
	f.content:SetPoint("TOPLEFT", 1, -31)
	f.content:SetPoint("BOTTOMRIGHT", -1, 1)

	local open = openAnimation(f)
	f:HookScript("OnShow", function()
		if ns.settings and ns.settings.animations then open:Play() end
	end)
	f:Hide()
	table.insert(UISpecialFrames, name) -- Esc closes it
	function f:SetTitle(text) bar.title:SetText(text) end
	return f
end

-- Settings controls ---------------------------------------------------------------------------------
-- Each returns a row frame of the given width with :Refresh(); the caller positions it.

-- On/off switch with a label and optional description underneath.
function Widgets.Toggle(parent, width, label, desc, get, set)
	local row = CreateFrame("Button", nil, parent)
	row:SetWidth(width)
	row.label = Widgets.Text(row, "body")
	row.label:SetPoint("TOPLEFT", 0, -2)
	row.label:SetWidth(width - 56)
	row.label:SetText(label)
	local h = 18
	if desc then
		row.desc = Widgets.Text(row, "muted")
		row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
		row.desc:SetWidth(width - 56)
		row.desc:SetText(desc)
		h = h + 5 + (row.desc:GetStringHeight() or 12)
	end
	row:SetHeight(h)

	local sw = CreateFrame("Frame", nil, row, "BackdropTemplate")
	sw:SetSize(34, 18)
	sw:SetPoint("TOPRIGHT", 0, -1)
	sw.knob = sw:CreateTexture(nil, "OVERLAY")
	sw.knob:SetSize(12, 12)
	row.switch = sw

	function row:Refresh()
		local on = get() and true or false
		if on then
			Widgets.Skin(sw, { C.accent[1], C.accent[2], C.accent[3], 0.9 }, { 0, 0, 0, 1 })
			sw.knob:ClearAllPoints()
			sw.knob:SetPoint("RIGHT", -3, 0)
			sw.knob:SetColorTexture(0.1, 0.08, 0.03, 1)
		else
			Widgets.Skin(sw, C.raised, { 1, 1, 1, 0.12 })
			sw.knob:ClearAllPoints()
			sw.knob:SetPoint("LEFT", 3, 0)
			sw.knob:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
		end
	end
	row:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
	end)
	row:SetScript("OnEnter", function() row.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end)
	row:SetScript("OnLeave", function() row.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
	return row
end

-- Slider: label + value on top, slim track with gold fill underneath.
function Widgets.Slider(parent, width, label, minValue, maxValue, step, format, get, set)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 40)
	row.label = Widgets.Text(row, "body")
	row.label:SetPoint("TOPLEFT", 0, -2)
	row.label:SetText(label)
	row.value = Widgets.Text(row, "small")
	row.value:SetPoint("TOPRIGHT", 0, -2)
	row.value:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

	local s = CreateFrame("Slider", nil, row)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("TOPLEFT", 0, -20)
	s:SetPoint("TOPRIGHT", 0, -20)
	s:SetHeight(16)
	s:SetMinMaxValues(minValue, maxValue)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouseWheel(true)

	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(1, 1, 1, 0.1)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetHeight(4)
	fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 14)
	thumb:SetColorTexture(0.95, 0.95, 0.95, 1)
	s:SetThumbTexture(thumb)
	row.slider = s

	local function round(v)
		return math.floor((v - minValue) / step + 0.5) * step + minValue
	end
	local function paint(v)
		row.value:SetText(format(v))
		local w = (s:GetWidth() or 0) * (v - minValue) / (maxValue - minValue)
		fill:SetWidth(math.max(1, w))
	end
	s:SetScript("OnValueChanged", function(_, v)
		v = round(v)
		paint(v)
		if not row.refreshing then set(v) end
	end)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(math.min(maxValue, math.max(minValue, round(self:GetValue() + delta * step))))
	end)
	s:SetScript("OnSizeChanged", function() paint(round(s:GetValue() or minValue)) end)

	function row:Refresh()
		self.refreshing = true
		s:SetValue(get())
		paint(get())
		self.refreshing = false
	end
	return row
end

-- Row of mutually exclusive choices. options = { {value, text}, ... }.
function Widgets.Segmented(parent, width, label, options, get, set)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 46)
	row.label = Widgets.Text(row, "body")
	row.label:SetPoint("TOPLEFT", 0, -2)
	row.label:SetText(label)
	row.buttons = {}
	local gap = 4
	local bw = (width - gap * (#options - 1)) / #options
	for i, opt in ipairs(options) do
		local b = CreateFrame("Button", nil, row, "BackdropTemplate")
		b:SetSize(bw, 22)
		b:SetPoint("TOPLEFT", (i - 1) * (bw + gap), -21)
		b.text = Widgets.Text(b, "small")
		b.text:SetPoint("CENTER")
		b.text:SetText(opt[2])
		b.value = opt[1]
		b:SetScript("OnClick", function()
			set(opt[1])
			row:Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			if get() ~= self.value then self:SetBackdropColor(C.hover[1], C.hover[2], C.hover[3], 1) end
		end)
		b:SetScript("OnLeave", function() row:Refresh() end)
		row.buttons[i] = b
	end
	function row:Refresh()
		local v = get()
		for _, b in ipairs(self.buttons) do
			if b.value == v then
				Widgets.Skin(b, { 0.22, 0.17, 0.06, 1 }, { C.accent[1], C.accent[2], C.accent[3], 0.8 })
				b.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
			else
				Widgets.Skin(b, C.raised, C.border)
				b.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
			end
		end
	end
	return row
end

-- Scrolling -------------------------------------------------------------------------------------------

-- A vertical scroll area with a slim indicator. Returns scrollFrame, content; size content's height.
function Widgets.ScrollArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	thumb:SetColorTexture(1, 1, 1, 0.18)
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
		thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -y)
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
local SEPARATOR = "  |cff4a4a52·|r  "

function Widgets.FitRoster(fs, drop, width, opts)
	opts = opts or {}
	local resolved = ns.Titles.IsResolved(drop)
	local me = ns.PlayerName()
	local groups = { need = {}, greed = {}, pass = {}, none = {} }
	for name, r in pairs(drop.rolls or {}) do
		if name ~= opts.exclude then
			table.insert(groups[r.choice] or groups.none, { name = name, class = r.class, roll = r.roll, me = name == me })
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
			return "|cff6b6b75" .. (p.me and "You" or ns.ShortName(p.name)) .. "|r"
		end
		local n = p.me and ("|c%sYou|r"):format(Widgets.ACCENT_HEX) or ns.ColorName(p.name, p.class)
		if p.roll and key ~= "pass" then
			n = n .. " |cffffffff" .. p.roll .. "|r"
		end
		return n
	end

	local function groupText(key, mode)
		local list = groups[key]
		if #list == 0 then return nil end
		local head = key == "none"
			and ("|c%s%s|r "):format(Widgets.MUTED_HEX, resolved and "no roll:" or "waiting:")
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
			text = text .. (" |c%s+%d|r"):format(Widgets.MUTED_HEX, #list - limit)
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

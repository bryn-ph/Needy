-- Looks for the roll bars, their drag handle and the Roll Log (setting: theme). Each theme owns a bar's
-- whole look: its size, art, fonts and where everything sits. Windows keep the game's own frames.
--   original  Needy's first look: the tooltip border tinted with the item's quality colour (the default)
--   blizzard  the game's own roll popup (GroupLootFrame): the loot toast panel, its silver border tinted with
--             the item's quality colour, the quality icon border and the yellow timer in the panel's slot
--   modern    a flat dark card, the quality colour washing in from a strip down the left, Arial Narrow,
--             a thin timer line along the bottom
--   minimal   a slim, see-through strip: shadowed text on a fading dark backing, small buttons, no box
local _, ns = ...

local Themes = {}
ns.Themes = Themes

local W = ns.Widgets
local GOLD = W.GOLD
local WHITE = "Interface\\Buttons\\WHITE8x8"
local TOAST = "Interface\\LootFrame\\LootToast"
local SKILLS_BAR = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"

Themes.LIST = {
	{ key = "original", name = "Original" },
	{ key = "blizzard", name = "Blizzard" },
	{ key = "modern", name = "Modern" },
	{ key = "minimal", name = "Minimal" },
}
Themes.DEFAULT = "original"

-- Fonts ---------------------------------------------------------------------------------------------
-- Arial Narrow has no Cyrillic or East Asian letters; those clients keep the game's own font.

local NARROW = "Fonts\\ARIALN.TTF"
do
	local locale = GetLocale and GetLocale()
	if locale == "ruRU" or locale == "koKR" or locale == "zhCN" or locale == "zhTW" then
		NARROW = STANDARD_TEXT_FONT or NARROW
	end
end

-- A hard drop shadow rather than an outline: at these sizes an outline runs the letters together.
local function makeFont(name, size)
	local f = CreateFont(name)
	f:SetFont(NARROW, size, "")
	f:SetTextColor(1, 1, 1)
	f:SetShadowColor(0, 0, 0, 1)
	f:SetShadowOffset(1, -1)
	return f
end

local fonts = {
	modernName = makeFont("NeedyModernName", 16),
	modernSmall = makeFont("NeedyModernSmall", 13),
	minimalName = makeFont("NeedyMinimalName", 15),
	minimalSmall = makeFont("NeedyMinimalSmall", 13),
}

-- Definitions ----------------------------------------------------------------------------------------
-- height: the bar's. icon: size, x, y (from the top; nil = centred), border ("toast", "flat" or "none").
-- text: left edge, name's distance from the top, gap to the status line, fonts, room kept on the right
-- once the buttons have gone. buttons: size, gap, inset from the right, y (up from the centre).
-- timer: where the countdown runs; `under` puts it behind the bar (showing through the panel's slot),
-- `color` fixes its colour (otherwise green to red). anim: the dice roll's scale and centre (in from the
-- right; the number lands 13 of its units right of that), its "You" label's offset (ending a few px left
-- of a three-digit number), and the room the result line leaves for them.

local DEFS = {
	-- Exactly the bars from before themes: a 56 high tooltip box, 38 icon, 30 buttons, the timer between
	-- the icon and the buttons.
	original = {
		height = 56,
		native = true,
		icon = { size = 38, x = 9, border = "native" },
		text = { left = 55, nameTop = 10, gap = 4, name = "GameFontNormal", small = "GameFontHighlightSmall", right = 12 },
		buttons = { size = 30, gap = 2, right = 10, y = 1 },
		timer = { texture = "Interface\\TargetingFrame\\UI-StatusBar", height = 6, left = 55, right = 112, bottom = 9,
			bg = { 0, 0, 0, 0.5 } },
		anim = { scale = 0.7, x = 60, y = 0, labelX = -74, labelY = -8, reserve = 112 },
		bg = { 0, 0, 0, 0.85 },
		wishBg = { 0.22, 0.14, 0, 0.92 },
		log = "native",
	},
	blizzard = {
		height = 67,
		icon = { size = 34, x = 10, y = 11, border = "toast" },
		text = { left = 62, nameTop = 14, gap = 4, name = "GameFontNormal", small = "GameFontHighlightSmall", right = 87 },
		buttons = { size = 26, gap = 0, right = 6, y = 7 },
		timer = { texture = SKILLS_BAR, height = 8, left = 3, right = 84, bottom = 2, under = true,
			color = { 1, 1, 0 }, bg = { 0, 0, 0, 1 } },
		anim = { scale = 0.7, x = 38, y = 7, labelX = -52, labelY = -2, reserve = 87 },
		log = "native",
	},
	modern = {
		height = 48,
		icon = { size = 30, x = 13, border = "flat" },
		text = { left = 52, nameTop = 6, gap = 2, name = fonts.modernName, small = fonts.modernSmall, right = 12 },
		buttons = { size = 26, gap = 2, right = 8, y = 0 },
		timer = { texture = WHITE, height = 2, left = 3, right = 0, bottom = 0, bg = { 1, 1, 1, 0.07 } },
		anim = { scale = 0.6, x = 40, y = 0, labelX = -54, labelY = -6, reserve = 92 },
		bg = { 0.05, 0.05, 0.06, 0.94 },
		wishBg = { 0.13, 0.09, 0.02, 0.96 },
		strip = 3,
		wash = { 0.27, 0 }, -- quality colour's alpha from the strip to 60% across
		log = "flat",
	},
	minimal = {
		height = 36,
		icon = { size = 28, x = 3, border = "none" },
		text = { left = 38, nameTop = 2, gap = 1, name = fonts.minimalName, small = fonts.minimalSmall, right = 8 },
		buttons = { size = 24, gap = 1, right = 4, y = 0 },
		timer = { texture = WHITE, height = 1, left = 36, right = 4, bottom = 0, bg = { 1, 1, 1, 0 } },
		anim = { scale = 0.55, x = 32, y = 0, labelX = -47, labelY = -3, reserve = 78 },
		shadow = { 0.75, 0 }, -- black's alpha from the left edge to the right
		log = "glass",
	},
}

-- Panels for the handle and the Roll Log.
local SURFACES = {
	native = true,
	flat = { bg = { 0.05, 0.05, 0.06, 0.94 }, edge = { 0.2, 0.2, 0.22, 1 } },
	glass = { bg = { 0, 0, 0, 0.55 }, edge = { 0, 0, 0, 0 } },
}

function Themes.Valid(key)
	return DEFS[key] ~= nil
end

function Themes.Key()
	local key = ns.settings and ns.settings.theme
	return DEFS[key] and key or Themes.DEFAULT
end

function Themes.Current()
	return DEFS[Themes.Key()]
end

-- How much of a bar's right side the buttons take, text gap included.
function Themes.ButtonsArea(t)
	local b = (t or Themes.Current()).buttons
	return b.right + 3 * b.size + 2 * b.gap + 8
end

-- Panels -----------------------------------------------------------------------------------------------

-- The box behind the handle or the Roll Log. `alpha` overrides the background's.
function Themes.Surface(frame, alpha)
	local s = SURFACES[Themes.Current().log]
	if s == true then
		W.NativeBox(frame, alpha or 0.85)
	else
		frame:SetBackdrop(W.FLAT_BACKDROP)
		frame:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], alpha or s.bg[4])
		frame:SetBackdropBorderColor(s.edge[1], s.edge[2], s.edge[3], s.edge[4])
	end
	frame.needyTheme = Themes.Key()
end

-- Bar art ------------------------------------------------------------------------------------------------

-- Three textures across a box: fixed-width ends from the texture's own pixels, the middle stretched.
-- `px` = { left, right, top, bottom } of the piece in the texture (pixels), `ends` = { left, right } widths.
local function threeSlice(parent, layer, file, size, px, ends)
	local w, h = size[1], size[2]
	local parts = {}
	local cuts = { { px[1], px[1] + ends[1] }, { px[1] + ends[1], px[2] - ends[2] }, { px[2] - ends[2], px[2] } }
	for i, cut in ipairs(cuts) do
		local t = parent:CreateTexture(nil, layer)
		t:SetTexture(file)
		t:SetTexCoord(cut[1] / w, cut[2] / w, px[3] / h, px[4] / h)
		parts[i] = t
	end
	function parts:Place(frame, inset, height)
		local l, m, r = self[1], self[2], self[3]
		for _, t in ipairs(self) do t:ClearAllPoints() end
		l:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
		l:SetSize(ends[1], height)
		r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", inset, inset)
		r:SetSize(ends[2], height)
		m:SetPoint("TOPLEFT", l, "TOPRIGHT")
		m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
	end
	function parts:SetShown(on)
		for _, t in ipairs(self) do t:SetShown(on) end
	end
	function parts:SetVertexColor(r, g, b)
		for _, t in ipairs(self) do t:SetVertexColor(r, g, b) end
	end
	return parts
end

-- The game's roll popup, cut so the ends keep their shape at any bar width (GroupLootFrame.xml's
-- texture coordinates, in pixels of the 1024x256 LootToast texture).
local function toastArt(bar)
	if bar.toast then return bar.toast end
	bar.toast = {
		panel = threeSlice(bar, "BACKGROUND", TOAST, { 1024, 256 }, { 289, 566, 79, 146 }, { 58, 83 }),
		border = threeSlice(bar, "BORDER", TOAST, { 1024, 256 }, { 1, 287, 112, 188 }, { 40, 40 }),
	}
	bar.toast.panel:Place(bar, 0, 67)
	bar.toast.border:Place(bar, 4.5, 76)
	return bar.toast
end

local function wash(bar)
	if bar.wash then return bar.wash end
	bar.wash = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
	bar.wash:SetTexture(WHITE)
	return bar.wash
end

local function gradient(tex, r, g, b, from, to)
	if tex.SetGradient and CreateColor then
		tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, from), CreateColor(r, g, b, to))
	else
		tex:SetVertexColor(r, g, b, (from + to) / 2)
	end
end

-- Bars -----------------------------------------------------------------------------------------------------

local function placeButtons(bar, t)
	local b = t.buttons
	local x = -b.right
	for i = #bar.buttons, 1, -1 do
		local button = bar.buttons[i]
		button:ClearAllPoints()
		button:SetSize(b.size, b.size)
		button:SetPoint("RIGHT", bar, "RIGHT", x, b.y)
		button.glow:SetSize(b.size + 16, b.size + 16)
		x = x - b.size - b.gap
	end
end

local function placeTimer(bar, t)
	local timer, spec = bar.timer, t.timer
	timer:SetStatusBarTexture(spec.texture)
	timer:SetHeight(spec.height)
	timer.bg:SetColorTexture(spec.bg[1], spec.bg[2], spec.bg[3], spec.bg[4])
	timer:ClearAllPoints()
	timer:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", spec.left, spec.bottom)
	timer:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -spec.right, spec.bottom)
	-- Behind the bar, the timer only shows through the panel's slot, as on the game's own popup.
	local level = bar:GetFrameLevel()
	timer:SetFrameLevel(spec.under and math.max(0, level - 1) or level + 1)
	if spec.color then timer:SetStatusBarColor(spec.color[1], spec.color[2], spec.color[3]) end
end

-- Dress a roll bar for the current theme: art, sizes, fonts and places. Colours come after, from
-- Themes.PaintBar.
function Themes.StyleBar(bar)
	local t = Themes.Current()
	bar:SetHeight(t.height)

	local toast = t.icon.border == "toast"
	if toast then
		bar:SetBackdrop(nil)
		toastArt(bar)
	elseif t.native then
		W.NativeBox(bar)
	elseif t.bg then
		bar:SetBackdrop(W.FLAT_BACKDROP)
	else
		bar:SetBackdrop(nil)
	end
	if bar.toast then
		bar.toast.panel:SetShown(toast)
		bar.toast.border:SetShown(toast)
	end

	if t.wash or t.shadow then
		local tex = wash(bar)
		tex:ClearAllPoints()
		if t.wash then
			tex:SetPoint("TOPLEFT", (t.strip or 0), 0)
			tex:SetPoint("BOTTOMLEFT", (t.strip or 0), 0)
			tex:SetWidth(ns.settings.barWidth * 0.6)
		else
			tex:SetAllPoints()
		end
		tex:Show()
	elseif bar.wash then
		bar.wash:Hide()
	end

	if t.strip then
		if not bar.strip then
			bar.strip = bar:CreateTexture(nil, "ARTWORK")
			bar.strip:SetTexture(WHITE)
		end
		bar.strip:ClearAllPoints()
		bar.strip:SetPoint("TOPLEFT")
		bar.strip:SetPoint("BOTTOMLEFT")
		bar.strip:SetWidth(t.strip)
		bar.strip:Show()
	elseif bar.strip then
		bar.strip:Hide()
	end

	local icon = bar.icon
	icon:SetSize(t.icon.size, t.icon.size)
	icon:ClearAllPoints()
	if t.icon.y then
		icon:SetPoint("TOPLEFT", bar, "TOPLEFT", t.icon.x, -t.icon.y)
	else
		icon:SetPoint("LEFT", bar, "LEFT", t.icon.x, 0)
	end
	icon:SetBorderStyle(t.icon.border)

	-- The game's own fonts are named; ours are objects.
	bar.name:SetFontObject(type(t.text.name) == "string" and _G[t.text.name] or t.text.name)
	bar.status:SetFontObject(type(t.text.small) == "string" and _G[t.text.small] or t.text.small)
	bar.name:ClearAllPoints()
	bar.name:SetPoint("TOPLEFT", bar, "TOPLEFT", t.text.left, -t.text.nameTop)
	bar.status:ClearAllPoints()
	bar.status:SetPoint("TOPLEFT", bar.name, "BOTTOMLEFT", 0, -t.text.gap)

	placeButtons(bar, t)
	placeTimer(bar, t)

	local anim = bar.rollAnim
	if anim then
		anim:SetScale(t.anim.scale)
		anim:ClearAllPoints()
		anim:SetPoint("CENTER", bar, "RIGHT", -t.anim.x / t.anim.scale, t.anim.y / t.anim.scale)
	end
	bar.rollLabel:ClearAllPoints()
	bar.rollLabel:SetPoint("RIGHT", bar, "RIGHT", t.anim.labelX, t.anim.labelY)
end

-- A bar's colours: (r, g, b) is the item's quality colour, or gold when `highlight` (a wishlist item, or
-- one you've won). Original and Blizzard tint their border, Modern its strip and wash, Minimal its shadow.
function Themes.PaintBar(bar, r, g, b, highlight, wished)
	local t = Themes.Current()
	if bar.toast and t.icon.border == "toast" then
		bar.toast.border:SetVertexColor(r, g, b)
		if wished then
			bar.toast.panel:SetVertexColor(1, 0.86, 0.6)
		else
			bar.toast.panel:SetVertexColor(1, 1, 1)
		end
		return
	end
	if t.bg then
		local bg = wished and t.wishBg or t.bg
		bar:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
		if t.native then
			bar:SetBackdropBorderColor(r, g, b, 1)
		elseif highlight then
			bar:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
		else
			bar:SetBackdropBorderColor(0, 0, 0, 0)
		end
	end
	if t.strip then bar.strip:SetVertexColor(r, g, b, 1) end
	if t.wash then
		gradient(bar.wash, r, g, b, t.wash[1], t.wash[2])
	elseif t.shadow then
		if highlight then
			gradient(bar.wash, GOLD[1] * 0.45, GOLD[2] * 0.45, 0, t.shadow[1], t.shadow[2])
		else
			gradient(bar.wash, 0, 0, 0, t.shadow[1], t.shadow[2])
		end
	end
end

-- The bar's timer colour: fixed for some themes, otherwise green with time to spare, through yellow, to red.
function Themes.TimerColor(frac)
	local c = Themes.Current().timer.color
	if c then return c[1], c[2], c[3] end
	return math.min(1, 2 * (1 - frac)), math.min(1, 2 * frac), 0
end

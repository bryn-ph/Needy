-- The roll bars that replace Blizzard's GroupLootFrame popups. Their look comes from UI/Themes.lua.
local _, ns = ...

local RollFrame = {}
ns.RollFrame = RollFrame

local W = ns.Widgets
local GOLD = W.GOLD

local BAR_GAP = 4 -- bar sizes, and where things sit on them, come from the theme (UI/Themes.lua)
local RESULT_LINGER = 1.8 -- seconds a finished bar stays up after the result shows
local ANIM_SPEED = 0.6 -- Blizzard's need-roll animation, played a little faster (1 = their timing)
local REVEAL_TIME = 3.4 * ANIM_SPEED -- when the number lands in that animation
local WISH_PREFIX_WIDTH = 180 -- narrower status lines leave the word out; the glow says it
local MINE_WAIT = 3 -- seconds a finished roll waits for your own number before showing the winner's
local WAIT_LINGER = 45 -- seconds a closed bar waits for the result before giving up

local anchor
local bars = {} -- shown, in display order
local pool = {}
local barsByDrop = {} -- drop key -> bar
local seenResolved = {} -- drop keys already finished, so a repeat of the same item doesn't inherit an old result

-- Blizzard frames ---------------------------------------------------------------------------
-- Blizzard opens its popups from GameEvent.HandleStartLootRoll -> GroupLootContainer_AddRoll, not from a
-- frame we could unregister. Rather than rewire GroupLootContainer (which sits in the managed bottom
-- frame stack, so touching it could spread taint into the layout of protected bars), the popups are
-- left to run but made invisible and click-through. They still close themselves normally.

local function applyBlizzard(frame)
	local hide = ns.settings.replaceBlizzard
	frame:SetAlpha(hide and 0 or 1)
	frame:EnableMouse(not hide)
	local container = rawget(frame, "LootButtonContainer")
	if type(container) == "table" and container.GetChildren then
		for _, b in ipairs({ container:GetChildren() }) do
			b:EnableMouse(not hide)
		end
	end
	local iconFrame = rawget(frame, "IconFrame")
	if type(iconFrame) == "table" and iconFrame.EnableMouse then
		iconFrame:EnableMouse(not hide)
	end
end

local function hookBlizzard()
	for i = 1, 4 do
		local f = _G["GroupLootFrame" .. i]
		if f and f.HookScript then
			f:HookScript("OnShow", function(self) pcall(applyBlizzard, self) end)
		end
	end
end

function RollFrame.ApplyBlizzard()
	for i = 1, 4 do
		local f = _G["GroupLootFrame" .. i]
		if f and f:IsShown() then
			pcall(applyBlizzard, f)
		end
	end
end

-- Anchor ---------------------------------------------------------------------------------------
-- While unlocked the anchor is a handle you drag the bars by. Like Edit Mode, faint centre guides
-- appear across the screen and the bars snap onto them when dragged close; the handle also has a
-- "Centre" button. Positions are stored as CENTER offsets from the middle of the screen.

local SNAP = 16 -- UI units from a centre line at which the bars snap onto it
local guides

local function setAnchorOffset(x, y)
	-- x, y in UIParent units from the screen centre; SetPoint offsets are in the anchor's own scale.
	local s = anchor:GetScale()
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
end

local function anchorOffset()
	local x, y = anchor:GetCenter()
	if not x then return 0, 0 end
	local k = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return x * k - UIParent:GetWidth() / 2, y * k - UIParent:GetHeight() / 2
end

local function savePosition()
	local x, y = anchorOffset()
	local s = anchor:GetScale()
	ns.settings.position = { "CENTER", "CENTER", x / s, y / s }
end

local function placeAnchor()
	anchor:ClearAllPoints()
	local p = ns.settings.position
	if p then
		anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		anchor:SetPoint("TOP", UIParent, "TOP", 0, -240)
	end
end

local function createGuides()
	guides = CreateFrame("Frame", nil, UIParent)
	guides:SetAllPoints(UIParent)
	guides:SetFrameStrata("BACKGROUND")
	guides:Hide()
	guides.v = guides:CreateTexture(nil, "OVERLAY")
	guides.v:SetPoint("TOP", UIParent, "TOP")
	guides.v:SetPoint("BOTTOM", UIParent, "BOTTOM")
	guides.v:SetWidth(1)
	guides.h = guides:CreateTexture(nil, "OVERLAY")
	guides.h:SetPoint("LEFT", UIParent, "LEFT")
	guides.h:SetPoint("RIGHT", UIParent, "RIGHT")
	guides.h:SetHeight(1)
	function guides:Highlight(onX, onY)
		local function paint(t, on)
			if on then
				t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
			else
				t:SetColorTexture(1, 1, 1, 0.12)
			end
		end
		paint(self.v, onX)
		paint(self.h, onY)
	end
	guides:Highlight(false, false)
end

local function dragUpdate(self)
	local cx, cy = GetCursorPosition()
	local ui = UIParent:GetEffectiveScale()
	local x = cx / ui + self.dragOffset[1] - UIParent:GetWidth() / 2
	local y = cy / ui + self.dragOffset[2] - UIParent:GetHeight() / 2
	local onX, onY = math.abs(x) <= SNAP, math.abs(y) <= SNAP
	if onX then x = 0 end
	if onY then y = 0 end
	setAnchorOffset(x, y)
	guides:Highlight(onX, onY)
end

local function stopDrag(self)
	if not self.dragOffset then return end
	self.dragOffset = nil
	self:SetScript("OnUpdate", nil)
	savePosition()
	local x, y = anchorOffset()
	guides:Highlight(math.abs(x) < 0.5, math.abs(y) < 0.5)
end

local function createAnchor()
	anchor = CreateFrame("Frame", "NeedyAnchor", UIParent, "BackdropTemplate")
	anchor:SetSize(ns.settings.barWidth, 34)
	anchor:SetFrameStrata("HIGH")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or ns.settings.locked then return end
		local cx, cy = GetCursorPosition()
		local ui = UIParent:GetEffectiveScale()
		local x, y = anchorOffset()
		self.dragOffset = { x + UIParent:GetWidth() / 2 - cx / ui, y + UIParent:GetHeight() / 2 - cy / ui }
		self:SetScript("OnUpdate", dragUpdate)
	end)
	anchor:SetScript("OnMouseUp", stopDrag)
	anchor:SetScript("OnHide", stopDrag)
	ns.Themes.Surface(anchor)

	anchor.label = W.Text(anchor, "GameFontNormal")
	anchor.label:SetPoint("LEFT", 12, 0)
	anchor.label:SetText("Needy roll bars  |cff8c8c8cDrag to move|r")
	anchor.label:SetWordWrap(false)

	anchor.done = W.Button(anchor, DONE or "Done", 64, 22)
	anchor.done:SetPoint("RIGHT", -7, 0)
	anchor.done:SetScript("OnClick", function()
		ns.settings.locked = true
		RollFrame.ApplySettings()
		if ns.SettingsWindow then ns.SettingsWindow.Refresh() end
	end)
	anchor.centre = W.Button(anchor, "Centre", 70, 22)
	anchor.centre:SetPoint("RIGHT", anchor.done, "LEFT", -2, 0)
	anchor.centre:SetScript("OnClick", function()
		local _, y = anchorOffset()
		setAnchorOffset(0, y)
		savePosition()
		guides:Highlight(true, math.abs(y) < 0.5)
	end)

	createGuides()
	placeAnchor()
end

-- Buttons ---------------------------------------------------------------------------------------
-- The game's own need/greed/pass art. The chosen one keeps a gold action-button glow.

local function setButtonEnabled(button, enabled, reason)
	button:SetEnabled(enabled)
	button.reason = reason
	local tex = button:GetNormalTexture()
	if tex then tex:SetDesaturated(not enabled) end
	button:SetAlpha(enabled and 1 or 0.35)
end

local function makeButton(bar, choice)
	local info = ns.Choices[choice]
	local b = CreateFrame("Button", nil, bar)
	b:SetSize(30, 30)
	b:SetNormalAtlas(info.button .. "-up")
	b:SetHighlightAtlas(info.button .. "-highlight", "ADD")
	b:SetPushedAtlas(info.button .. "-down")
	b:SetMotionScriptsWhileDisabled(true)
	b.choice = choice
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(46, 46)
	b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	b.glow:Hide()
	b:SetScript("OnClick", function(self)
		local roll = bar.roll
		if roll and not roll.closed then
			ns.LootSource.Choose(roll, self.choice)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(info.label, 1, 1, 1)
		if not self:IsEnabled() and self.reason then
			GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Roll animation ---------------------------------------------------------------------------------
-- Blizzard's own need-roll animation (NeedRollAnim in Blizzard_UIPanels_Game/Mainline/GroupLootFrame.xml on
-- the forever branch), rebuilt in Lua: a dice flipbook, a glow, then reveal bursts as the number lands.
-- Times are Blizzard's, scaled by ANIM_SPEED. If anything here isn't available, results just appear.

local ROLL_ANIM_TEXTURES = {
	-- key, atlas, width, height, x, y, sublevel
	{ "DiceRoll", "lootroll-animdice", 58, 74, 0, 0, 0 },
	{ "FX_RevealA", "lootroll-animreveal-a", 128, 114, 19.5, -7, 0 },
	{ "FX_RevealFade", "lootroll-animrevealfade", 70, 220, 12.5, 30, 0 },
	{ "DiceGlow", "lootroll-animdiceglow", 70, 76, 13, -13, 1 },
	{ "FX_RevealB1", "lootroll-animreveal-b", 108, 150, 10, 15, 2 },
	{ "FX_RevealB2", "lootroll-animreveal-b", 108, 150, 23, 15, 2 },
}

local ROLL_ANIM_STEPS = {
	-- target, kind, duration, start delay, args (FlipBook: rows, columns, frames; Alpha: from, to;
	-- Scale: to; Translation: y offset)
	{ "DiceRoll", "FlipBook", 1.47, 0, { 9, 5, 44 } },
	{ "DiceRoll", "Alpha", 1.47, 0, { 1, 1 } },
	{ "DiceRoll", "Alpha", 0, 1.48, { 0, 0 } },
	{ "DiceGlow", "FlipBook", 1.67, 1.48, { 10, 5, 50 } },
	{ "DiceGlow", "Alpha", 1.47, 0, { 0, 0 } },
	{ "DiceGlow", "Alpha", 1.67, 1.48, { 1, 1 } },
	{ "DiceGlow", "Scale", 0.27, 3.15, { 1.3 } },
	{ "DiceGlow", "Alpha", 0.27, 3.15, { 1, 0 } },
	{ "FX_RevealB1", "FlipBook", 0.3, 3.15, { 2, 5, 10 } },
	{ "FX_RevealB1", "Alpha", 3.14, 0, { 0, 0 } },
	{ "FX_RevealB1", "Alpha", 0.3, 3.15, { 1, 1 } },
	{ "FX_RevealB1", "Alpha", 0, 3.46, { 0, 0 } },
	{ "FX_RevealB2", "FlipBook", 0.35, 3.2, { 2, 5, 10 } },
	{ "FX_RevealB2", "Alpha", 3.19, 0, { 0, 0 } },
	{ "FX_RevealB2", "Alpha", 0.35, 3.2, { 1, 1 } },
	{ "FX_RevealB2", "Alpha", 0, 3.56, { 0, 0 } },
	{ "FX_RevealA", "FlipBook", 0.4, 3.3, { 2, 6, 12 } },
	{ "FX_RevealA", "Alpha", 3.29, 0, { 0, 0 } },
	{ "FX_RevealA", "Alpha", 0.4, 3.3, { 1, 1 } },
	{ "FX_RevealFade", "FlipBook", 0.7, 3.4, { 3, 7, 21 } },
	{ "FX_RevealFade", "Alpha", 3.39, 0, { 0, 0 } },
	{ "FX_RevealFade", "Alpha", 0.7, 3.4, { 1, 1 } },
	{ "RollNumber", "Alpha", 3.39, 0, { 0, 0 } },
	{ "RollNumber", "Alpha", 0.1, 3.4, { 0, 1 } },
	{ "RollNumber", "Translation", 0, 0, { 5 } },
	{ "RollNumber", "Translation", 0.6, 3.4, { -5 } },
}

local function buildRollAnimation(bar)
	local f = CreateFrame("Frame", nil, bar)
	f:SetSize(128, 128)
	f:SetScale(0.7)
	f:SetPoint("CENTER", bar, "RIGHT", -60 / 0.7, 0)
	f:SetFrameLevel(bar:GetFrameLevel() + 5)
	f:Hide()
	for _, t in ipairs(ROLL_ANIM_TEXTURES) do
		local tex = f:CreateTexture(nil, "ARTWORK", nil, t[7])
		tex:SetAtlas(t[2])
		tex:SetSize(t[3], t[4])
		tex:SetPoint("CENTER", t[5], t[6])
		f[t[1]] = tex
	end
	f.RollNumber = f:CreateFontString(nil, "ARTWORK", "Game32Font")
	f.RollNumber:SetPoint("CENTER", 13, -13)

	local group = f:CreateAnimationGroup()
	group:SetToFinalAlpha(true)
	for _, s in ipairs(ROLL_ANIM_STEPS) do
		local a = group:CreateAnimation(s[2])
		a:SetTarget(f[s[1]])
		a:SetDuration(s[3] * ANIM_SPEED)
		a:SetStartDelay(s[4] * ANIM_SPEED)
		a:SetOrder(1)
		local v = s[5]
		if s[2] == "FlipBook" then
			a:SetFlipBookRows(v[1])
			a:SetFlipBookColumns(v[2])
			a:SetFlipBookFrames(v[3])
			a:SetFlipBookFrameWidth(0)
			a:SetFlipBookFrameHeight(0)
		elseif s[2] == "Alpha" then
			a:SetFromAlpha(v[1])
			a:SetToAlpha(v[2])
		elseif s[2] == "Scale" then
			a:SetScaleFrom(1, 1)
			a:SetScaleTo(v[1], v[1])
		elseif s[2] == "Translation" then
			a:SetOffset(0, v[1])
		end
	end
	f.group = group
	return f
end

function RollFrame.CreateRollAnimation(bar)
	local ok, anim = pcall(buildRollAnimation, bar)
	return ok and anim or nil
end

-- Bars -------------------------------------------------------------------------------------------

local paint, fitText -- defined below

-- Dress a bar for the theme, again if the theme or the bar width has changed since.
local function restyle(bar)
	local look = ns.Themes.Key() .. ":" .. ns.settings.barWidth
	if bar.look == look then return end
	bar.look = look
	ns.Themes.StyleBar(bar)
	if bar.roll then
		bar.icon:SetItem(bar.roll.texture, bar.roll.quality)
		bar.name:SetTextColor(ns.QualityColor(bar.roll.quality)) -- a new font brings its own colour
		paint(bar)
		fitText(bar, bar.need:IsShown())
	end
end

local function rosterTooltip(bar)
	W.DropTooltip(bar, bar.drop, bar.roll and bar.roll.link or (bar.drop and bar.drop.link), false)
end

local function createBar()
	local bar = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", rosterTooltip)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local icon = W.ItemIcon(bar, 38)
	icon:SetScript("OnEnter", function(self)
		local roll = bar.roll
		if not roll then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if roll.isTest or roll.closed then
			if roll.link then GameTooltip:SetHyperlink(roll.link) else GameTooltip:SetText(roll.name) end
		else
			GameTooltip:SetLootRollItem(roll.id)
		end
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	icon:SetScript("OnClick", function()
		local roll = bar.roll
		if roll and roll.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			HandleModifiedItemClick(roll.link)
		end
	end)
	bar.icon = icon

	bar.pass = makeButton(bar, "pass")
	bar.greed = makeButton(bar, "greed")
	bar.need = makeButton(bar, "need")
	bar.buttons = { bar.need, bar.greed, bar.pass }

	bar.name = W.Text(bar, "GameFontNormal")
	bar.name:SetWordWrap(false)
	if bar.name.SetMaxLines then bar.name:SetMaxLines(1) end

	bar.tag = W.Text(bar, "GameFontRedSmall")
	bar.tag:SetPoint("LEFT", bar.name, "RIGHT", 6, 0)
	bar.tag:SetWordWrap(false)

	bar.status = W.Text(bar, "GameFontHighlightSmall")
	bar.status:SetWordWrap(false)
	if bar.status.SetMaxLines then bar.status:SetMaxLines(1) end

	-- Countdown, like the default roll frame's (its texture and place depend on the theme).
	bar.timer = CreateFrame("StatusBar", nil, bar)
	bar.timer.bg = bar.timer:CreateTexture(nil, "BACKGROUND")
	bar.timer.bg:SetAllPoints()

	-- Animations (only played when the "animations" option is on).
	bar.intro = bar:CreateAnimationGroup()
	local fadeIn = bar.intro:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.2)
	local grow = bar.intro:CreateAnimation("Scale")
	grow:SetScaleFrom(0.94, 0.94)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.25)
	grow:SetSmoothing("OUT")

	bar.rollAnim = RollFrame.CreateRollAnimation(bar)
	-- "You", beside your number in the roll animation; appears as it lands.
	bar.rollLabel = W.Text(bar, "GameFontNormalSmall")
	bar.rollLabel:SetJustifyH("RIGHT")
	bar.rollLabel:Hide()

	bar.pop = bar.status:CreateAnimationGroup()
	local pop = bar.pop:CreateAnimation("Scale")
	pop:SetOrigin("LEFT", 0, 0)
	pop:SetScaleFrom(1.35, 1.35)
	pop:SetScaleTo(1, 1)
	pop:SetDuration(0.3)
	pop:SetSmoothing("OUT")

	bar:SetScript("OnUpdate", RollFrame.UpdateBar)
	restyle(bar)
	return bar
end

local function layout()
	local width = ns.settings.barWidth
	anchor:SetWidth(width)
	for i, bar in ipairs(bars) do
		bar:ClearAllPoints()
		bar:SetWidth(width)
		if bar.roll then fitText(bar, bar.need:IsShown()) end
		local offset = (i - 1) * (ns.Themes.Current().height + BAR_GAP)
		if ns.settings.growUp then
			bar:SetPoint("BOTTOM", anchor, "TOP", 0, offset + BAR_GAP)
		else
			bar:SetPoint("TOP", anchor, "BOTTOM", 0, -(offset + BAR_GAP))
		end
	end
	anchor:SetShown(#bars > 0 or not ns.settings.locked)
end

-- Give the name and roster lines explicit widths so long text is cut off with "..." inside the bar
-- (left of the buttons while the roll is open, the full bar once they're gone).
-- The theme says where text starts and how much room the buttons, or the landed number, need on the right.
function fitText(bar, withButtons)
	local t = ns.Themes.Current()
	local right = withButtons and ns.Themes.ButtonsArea(t) or t.text.right
	local avail = ns.settings.barWidth - t.text.left - right
	local numberShown = bar.rollAnim and bar.rollAnim:IsShown()
	local tagWidth = bar.tag:IsShown() and (W.StringWidth(bar.tag) + 6) or 0
	bar.name:SetWidth(math.max(20, math.min(W.StringWidth(bar.name) + 2, avail - tagWidth)))
	if numberShown then
		avail = ns.settings.barWidth - t.text.left - math.max(right, t.anim.reserve)
	end
	bar.statusWidth = math.max(20, avail)
	bar.status:SetWidth(bar.statusWidth)
end

-- Who's chosen what so far, fitted to the line (see Widgets.FitRoster). You show up as "You".
local function rosterLine(bar)
	local drop = bar.drop
	local prefix = bar.selfRoll and ("|c%sYou rolled %d|r   "):format(W.GOLD_HEX, bar.selfRoll) or ""
	if bar.wished and (bar.statusWidth or 0) >= WISH_PREFIX_WIDTH then
		prefix = ("|c%sWishlist!|r  "):format(W.GOLD_HEX) .. prefix
	end
	if not drop then
		local text = prefix
		local mine = bar.roll and bar.roll.myChoice
		if mine and not bar.selfRoll then
			text = text .. ("|c%sYou: %s|r   "):format(W.GOLD_HEX, ns.Choices[mine].label)
		end
		if bar.roll and bar.roll.closed then
			text = text .. ("|c%sWaiting for the others...|r"):format(W.GREY_HEX)
		end
		bar.status:SetText(text)
		return
	end
	W.FitRoster(bar.status, drop, bar.statusWidth or 200, { prefix = prefix })
end

local function resultText(drop)
	if drop.allPassed then
		return ("|c%sEveryone passed.|r"):format(W.GREY_HEX), false
	end
	local r = drop.rolls[drop.winner] or {}
	local how = r.choice and ns.Choices[r.choice] and ns.Choices[r.choice].label or ""
	local text = ("Won by %s"):format(ns.ColorName(drop.winner, drop.winnerClass or r.class))
	if r.roll then
		text = text .. ("  |c%s%s|r |cffffffff%d|r"):format(W.GREY_HEX, how, r.roll)
	end
	local mine = drop.winner ~= nil and ns.IsMe(drop.winner, drop.rolls[drop.winner])
	if mine then
		text = ("|c%sYours!|r  "):format(W.GOLD_HEX) .. text
	end
	return text, mine
end

-- A bar's colours, for the theme: gold for a wishlist item or once you've won it, otherwise the item's
-- quality colour.
function paint(bar)
	local highlight = bar.wished or bar.wonShown
	local r, g, b
	if highlight then
		r, g, b = GOLD[1], GOLD[2], GOLD[3]
	else
		r, g, b = ns.QualityColor(bar.roll and bar.roll.quality)
	end
	ns.Themes.PaintBar(bar, r, g, b, highlight, bar.wished)
end

-- Dress or undress a bar for an item on the wishlist.
local function setWished(bar, wished)
	if (bar.wished or false) == wished then return end
	bar.wished = wished
	if wished then
		bar.wishGlow = bar.wishGlow or ns.WishlistGlow.Create(bar, bar.icon)
		bar.wishGlow:Start(ns.settings.animations)
	else
		bar.wishGlow:Stop()
	end
	paint(bar)
end

local function stopAnimations(bar)
	bar.revealAt = nil
	bar.rollLabel:Hide()
	bar.intro:Stop()
	if bar.rollAnim then
		bar.rollAnim.group:Stop()
		bar.rollAnim:Hide()
	end
	bar.pop:Stop()
end

local function markWon(bar)
	if bar.youWon then
		bar.wonShown = true
		paint(bar)
	end
end

-- The number has landed in the roll animation: show the result line.
local function reveal(bar)
	bar.revealAt = nil
	bar.status:SetText(bar.resultText)
	markWon(bar)
	bar.rollLabel:Show()
	bar.pop:Play()
end

-- Your entry in the drop and your number: from the loot history, or for a need roll the number the game
-- told us as you rolled.
local function myRoll(bar, drop)
	local _, mine = ns.FindMe(drop.rolls)
	local number = mine and mine.roll
	if not number and (not mine or mine.choice == "need") then number = bar.selfRoll end
	return mine, number
end

-- Play Blizzard's roll animation over the bar with your roll, labelled "You" (green if you won, red if
-- not). Only for your own number: if you passed or didn't roll, there's no animation, just the result
-- line, which always names the winner and their roll. Returns false if it didn't play.
local function playRollAnimation(bar, myNumber, mine)
	local anim = bar.rollAnim
	if not anim or not myNumber then return false end
	local color = bar.youWon and "ff33ff33" or "ffff3333"
	anim.RollNumber:SetText(("|c%s%d|r"):format(color, myNumber))
	bar.rollLabel:SetText("You")
	anim:Show()
	anim.group:Stop()
	anim.group:Play()
	-- Blizzard's own (hidden) roll frame already plays this sound for a real need roll.
	local blizzardPlays = mine and mine.choice == "need" and bar.roll and not bar.roll.isTest
	if myNumber and not blizzardPlays and PlaySound and SOUNDKIT then
		local sound = bar.youWon and SOUNDKIT.UI_NEED_ROLL_POSITIVE or SOUNDKIT.UI_NEED_ROLL_NEGATIVE
		if sound then PlaySound(sound) end
	end
	return true
end

-- The roll is over: the timer stays, empty, as on the game's own popup (whose panel has a slot for it).
local function stopTimer(bar)
	bar.counting = false
	bar.timer:SetValue(0)
end

local function showResult(bar)
	local drop = bar.drop
	for _, b in ipairs(bar.buttons) do b:Hide() end
	stopTimer(bar)
	fitText(bar, false)
	bar.resultText, bar.youWon = resultText(drop)
	if bar.resultShown then
		-- A later update for an already-finished drop: just keep the text current.
		if not bar.revealAt then bar.status:SetText(bar.resultText) end
		return
	end
	-- The winner can be known a moment before your own number arrives: give it a few seconds.
	local mine, myNumber = myRoll(bar, drop)
	local rolled = ns.IsRollChoice(mine and mine.choice or bar.roll.myChoice)
	if rolled and not myNumber and not drop.allPassed and not bar.gaveUpOnMine then
		bar.awaitMineUntil = bar.awaitMineUntil or (GetTime() + MINE_WAIT)
		bar.status:SetText(("|c%sRolling...|r"):format(W.GREY_HEX))
		return
	end
	bar.awaitMineUntil = nil
	bar.resultShown = true
	if ns.settings.animations and not drop.allPassed and playRollAnimation(bar, myNumber, mine) then
		bar.revealAt = GetTime() + REVEAL_TIME
		fitText(bar, false) -- keep the result line clear of the number
		bar.status:SetText(("|c%sRolling...|r"):format(W.GREY_HEX))
		bar.fadeAt = bar.revealAt + RESULT_LINGER
	else
		-- No animation: your number, or your pass, leads the line instead.
		if myNumber and not bar.youWon then
			bar.resultText = ("|c%sYou %d|r   "):format(W.GOLD_HEX, myNumber) .. bar.resultText
		elseif not myNumber and not drop.allPassed and (mine and mine.choice or bar.roll.myChoice) == "pass" then
			bar.resultText = ("|c%sYou passed|r   "):format(W.GREY_HEX) .. bar.resultText
		end
		bar.status:SetText(bar.resultText)
		markWon(bar)
		bar.fadeAt = GetTime() + RESULT_LINGER
	end
end

local function refreshBar(bar)
	local roll = bar.roll
	if bar.drop and ns.Titles.IsResolved(bar.drop) then
		showResult(bar)
		return
	end
	local open = not roll.closed
	for _, b in ipairs(bar.buttons) do
		b:SetShown(open)
		b.glow:SetShown(roll.myChoice == b.choice)
	end
	if not open then stopTimer(bar) end
	fitText(bar, open)
	rosterLine(bar)
	if not open and not bar.fadeAt then
		bar.fadeAt = GetTime() + ((bar.drop or bar.roll.isTest) and WAIT_LINGER or 6)
	end
end

function RollFrame.UpdateBar(bar)
	local roll = bar.roll
	if not roll then return end
	if bar.counting then
		local left = ns.LootSource.TimeLeft(roll)
		local frac = roll.rollTime > 0 and left / roll.rollTime or 0
		bar.timer:SetValue(left)
		bar.timer:SetStatusBarColor(ns.Themes.TimerColor(frac))
	end
	if bar.awaitMineUntil and GetTime() >= bar.awaitMineUntil then
		bar.gaveUpOnMine = true
		showResult(bar)
	end
	if bar.revealAt and GetTime() >= bar.revealAt then
		reveal(bar)
	end
	if bar.fadeAt then
		local t = GetTime()
		if t >= bar.fadeAt + 0.6 then
			RollFrame.Release(bar)
		elseif t >= bar.fadeAt then
			bar:SetAlpha(1 - (t - bar.fadeAt) / 0.6)
		end
	end
end

function RollFrame.Release(bar)
	for i, b in ipairs(bars) do
		if b == bar then
			table.remove(bars, i)
			break
		end
	end
	if bar.drop then barsByDrop[bar.drop.key] = nil end
	if bar.roll then ns.LootSource.Forget(bar.roll.id) end
	stopAnimations(bar)
	setWished(bar, false)
	if bar.flash then bar.flash:Stop() end
	bar:Hide()
	bar.roll, bar.drop, bar.fadeAt, bar.selfRoll, bar.resultShown = nil, nil, nil, nil, nil
	bar.awaitMineUntil, bar.gaveUpOnMine, bar.wonShown = nil, nil, nil
	table.insert(pool, bar)
	layout()
end

local function barForRoll(rollID)
	for _, bar in ipairs(bars) do
		if bar.roll and bar.roll.id == rollID then return bar end
	end
end

local function onRollStart(roll)
	local bar = table.remove(pool) or createBar()
	bar.roll, bar.drop, bar.fadeAt, bar.selfRoll, bar.resultShown = roll, nil, nil, nil, nil
	bar.awaitMineUntil, bar.gaveUpOnMine, bar.wonShown = nil, nil, nil
	stopAnimations(bar)
	restyle(bar)
	bar:SetAlpha(1)
	bar.icon:SetItem(roll.texture, roll.quality)
	bar.icon.count:SetText((roll.count or 1) > 1 and roll.count or "")
	local r, g, b = ns.QualityColor(roll.quality)
	paint(bar)
	bar.name:SetText(roll.name or "?")
	bar.name:SetTextColor(r, g, b)
	bar.tag:SetText(roll.bop and "BoP" or "")
	bar.tag:SetShown(roll.bop == true)
	bar.timer:SetMinMaxValues(0, roll.rollTime)
	bar.timer:SetValue(roll.rollTime)
	bar.counting = true

	local function reason(code)
		return code and _G["LOOT_ROLL_INELIGIBLE_REASON" .. code] or nil
	end
	setButtonEnabled(bar.need, roll.canNeed == true, reason(roll.reasonNeed))
	setButtonEnabled(bar.greed, roll.canGreed == true, reason(roll.reasonGreed))
	setButtonEnabled(bar.pass, true, nil)

	table.insert(bars, bar)
	bar:Show()
	setWished(bar, ns.Wishlist.Matches(roll))
	layout()
	if ns.settings.flashBars then RollFrame.Flash(bar) end
	refreshBar(bar)
	if ns.settings.animations then
		bar.intro:Play()
	end
end

local function linkDrop(drop)
	local bar = barsByDrop[drop.key]
	if bar then return bar end
	if seenResolved[drop.key] then return nil end
	local itemID = ns.ItemIDFromLink(drop.link)
	for _, b in ipairs(bars) do
		if not b.drop and b.roll then
			local match
			if drop.rollID then
				match = drop.rollID == b.roll.id
			else
				match = (b.roll.link and b.roll.link == drop.link)
					or (itemID and itemID == ns.ItemIDFromLink(b.roll.link))
			end
			if match then
				barsByDrop[drop.key] = b
				return b
			end
		end
	end
end

function RollFrame.Init()
	createAnchor()
	RollFrame.ApplySettings()
	hookBlizzard()

	ns.Listen("ROLL_START", onRollStart)
	ns.Listen("WISHLIST_CHANGED", function()
		for _, bar in ipairs(bars) do
			local wished = ns.Wishlist.Matches(bar.roll)
			if wished ~= (bar.wished or false) then
				setWished(bar, wished)
				refreshBar(bar)
			end
		end
	end)
	ns.Listen("ROLL_CHOSEN", function(roll)
		local bar = barForRoll(roll.id)
		if bar then refreshBar(bar) end
	end)
	ns.Listen("ROLL_CLOSED", function(rollID)
		local bar = barForRoll(rollID)
		if bar then refreshBar(bar) end
	end)
	ns.Listen("ROLL_SELF_RESULT", function(rollID, value)
		local bar = barForRoll(rollID)
		if bar then
			bar.selfRoll = value
			refreshBar(bar)
		end
	end)
	ns.Listen("DROP_UPDATE", function(drop)
		local bar = linkDrop(drop)
		if ns.Titles.IsResolved(drop) then
			seenResolved[drop.key] = true
		end
		if bar then
			bar.drop = drop
			refreshBar(bar)
		end
	end)
end

function RollFrame.ApplySettings()
	anchor:SetScale(ns.settings.scale)
	local unlocked = not ns.settings.locked
	anchor:EnableMouse(unlocked)
	if anchor.needyTheme ~= ns.Themes.Key() then ns.Themes.Surface(anchor) end
	for _, bar in ipairs(bars) do restyle(bar) end
	for _, bar in ipairs(pool) do restyle(bar) end
	anchor:SetBackdropColor(0, 0, 0, unlocked and 0.85 or 0)
	anchor:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], unlocked and 1 or 0)
	anchor.label:SetShown(unlocked)
	anchor.label:SetWidth(math.max(40, ns.settings.barWidth - 170))
	anchor.done:SetShown(unlocked)
	anchor.centre:SetShown(unlocked)
	guides:SetShown(unlocked)
	if unlocked then
		local x, y = anchorOffset()
		guides:Highlight(math.abs(x) < 0.5, math.abs(y) < 0.5)
	end
	layout()
	RollFrame.ApplyBlizzard()
	if ns.RollLog then ns.RollLog.Refresh() end
end

function RollFrame.Flash(bar)
	local quality = bar.roll.quality
	if quality == nil or ns.IsSecret(quality) then quality = 1 end
	bar.flash = bar.flash or ns.BarFlash.Create(bar)
	bar.flash:Play(quality, bar.wished)
end

-- Switching the flash on shows it on any bars that are up; off stops them.
function RollFrame.FlashShown(on)
	for _, bar in ipairs(bars) do
		if on then
			RollFrame.Flash(bar)
		elseif bar.flash then
			bar.flash:Stop()
		end
	end
end

function RollFrame.ResetPosition()
	ns.settings.position = nil
	placeAnchor()
end

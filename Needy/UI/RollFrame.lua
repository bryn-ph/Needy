-- The roll bars that replace Blizzard's GroupLootFrame popups.
local _, ns = ...

local RollFrame = {}
ns.RollFrame = RollFrame

local W = ns.Widgets
local C = W.C

local BAR_HEIGHT = 52
local BAR_GAP = 5
local STRIPE = 3 -- quality colour stripe on the left edge
local ICON_SIZE = 36
local BUTTON_SIZE = 30
local BUTTON_GAP = 4
local RESULT_LINGER = 2.5 -- seconds a finished bar stays up
local REVEAL_TIME = 1 -- seconds of "Rolling..." before the result shows (animations on)
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
-- While unlocked the anchor is a gold handle you drag the bars by. Like Edit Mode, faint centre guides
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
				t:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
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
	anchor:SetSize(ns.settings.barWidth, 30)
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
	W.Skin(anchor, { 0.22, 0.17, 0.06, 0.92 }, { C.accent[1], C.accent[2], C.accent[3], 0.9 })

	anchor.label = W.Text(anchor, "small")
	anchor.label:SetPoint("LEFT", 10, 0)
	anchor.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	anchor.label:SetText("Roll bars  |cff9e9eadDrag - snaps to centre|r")
	anchor.label:SetWordWrap(false)

	anchor.done = W.Button(anchor, "Done", 54, 20, "accent")
	anchor.done:SetPoint("RIGHT", -5, 0)
	anchor.done:SetScript("OnClick", function()
		ns.settings.locked = true
		RollFrame.ApplySettings()
		if ns.SettingsWindow then ns.SettingsWindow.Refresh() end
	end)
	anchor.centre = W.Button(anchor, "Centre", 60, 20)
	anchor.centre:SetPoint("RIGHT", anchor.done, "LEFT", -4, 0)
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

local function paintButton(b)
	if not b:IsEnabled() then
		W.Skin(b, C.raised, C.border)
		b.icon:SetDesaturated(true)
		b:SetAlpha(0.35)
		return
	end
	b.icon:SetDesaturated(false)
	b:SetAlpha(1)
	if b.selected then
		W.Skin(b, { 0.24, 0.18, 0.05, 1 }, { C.accent[1], C.accent[2], C.accent[3], 1 })
	elseif b.hovered then
		W.Skin(b, C.hover, { C.accent[1], C.accent[2], C.accent[3], 0.7 })
	else
		W.Skin(b, C.raised, C.border)
	end
end

local function setButtonEnabled(button, enabled, reason)
	button:SetEnabled(enabled)
	button.reason = reason
	paintButton(button)
end

local function makeButton(bar, choice)
	local info = ns.Choices[choice]
	local b = CreateFrame("Button", nil, bar, "BackdropTemplate")
	b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	b:SetMotionScriptsWhileDisabled(true)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	b.icon:SetAtlas(info.button .. "-up")
	b.choice = choice
	b:SetScript("OnClick", function(self)
		local roll = bar.roll
		if roll and not roll.closed then
			ns.LootSource.Choose(roll, self.choice)
		end
	end)
	b:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then self.icon:SetAtlas(info.button .. "-down") end
	end)
	b:SetScript("OnMouseUp", function(self) self.icon:SetAtlas(info.button .. "-up") end)
	b:SetScript("OnEnter", function(self)
		self.hovered = true
		paintButton(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(info.label, 1, 1, 1)
		if not self:IsEnabled() and self.reason then
			GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.hovered = false
		paintButton(self)
		GameTooltip:Hide()
	end)
	return b
end

-- Bars -------------------------------------------------------------------------------------------

local function rosterTooltip(bar)
	W.DropTooltip(bar, bar.drop, bar.roll and bar.roll.link or (bar.drop and bar.drop.link), false)
end

local function createBar()
	local bar = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
	bar:SetHeight(BAR_HEIGHT)
	W.Skin(bar)
	W.Shadow(bar, 3)
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", rosterTooltip)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Quality stripe on the left, and a soft tint of the same colour fading in from it.
	bar.stripe = bar:CreateTexture(nil, "ARTWORK")
	bar.stripe:SetPoint("TOPLEFT", 1, -1)
	bar.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	bar.stripe:SetWidth(STRIPE)
	bar.tint = bar:CreateTexture(nil, "BORDER")
	bar.tint:SetPoint("TOPLEFT", 1 + STRIPE, -1)
	bar.tint:SetPoint("BOTTOMLEFT", 1 + STRIPE, 1)
	bar.tint:SetWidth(140)
	W.Sheen(bar, 20, 0.035)

	local iconButton = CreateFrame("Button", nil, bar, "BackdropTemplate")
	iconButton:SetSize(ICON_SIZE, ICON_SIZE)
	iconButton:SetPoint("LEFT", 1 + STRIPE + 7, 0)
	iconButton:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
	iconButton.icon:SetPoint("TOPLEFT", 1, -1)
	iconButton.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	ns.CropIcon(iconButton.icon)
	iconButton.count = iconButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	iconButton.count:SetPoint("BOTTOMRIGHT", -2, 2)
	iconButton:SetScript("OnEnter", function(self)
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
	iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	iconButton:SetScript("OnClick", function()
		local roll = bar.roll
		if roll and roll.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			HandleModifiedItemClick(roll.link)
		end
	end)
	bar.iconButton = iconButton

	bar.pass = makeButton(bar, "pass")
	bar.pass:SetPoint("RIGHT", -9, 1)
	bar.greed = makeButton(bar, "greed")
	bar.greed:SetPoint("RIGHT", bar.pass, "LEFT", -BUTTON_GAP, 0)
	bar.need = makeButton(bar, "need")
	bar.need:SetPoint("RIGHT", bar.greed, "LEFT", -BUTTON_GAP, 0)
	bar.buttons = { bar.need, bar.greed, bar.pass }

	bar.name = W.Text(bar, "body")
	bar.name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 9, -2)
	bar.name:SetWordWrap(false)
	if bar.name.SetMaxLines then bar.name:SetMaxLines(1) end

	bar.tag = W.Text(bar, "tiny")
	bar.tag:SetPoint("LEFT", bar.name, "RIGHT", 6, 0)
	bar.tag:SetTextColor(C.bad[1], C.bad[2], C.bad[3])
	bar.tag:SetWordWrap(false)

	bar.status = W.Text(bar, "small")
	bar.status:SetPoint("TOPLEFT", bar.name, "BOTTOMLEFT", 0, -5)
	bar.status:SetWordWrap(false)
	if bar.status.SetMaxLines then bar.status:SetMaxLines(1) end

	-- Countdown: a thin line along the bottom edge.
	bar.timer = CreateFrame("StatusBar", nil, bar)
	bar.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar.timer:SetHeight(2)
	bar.timer:SetPoint("BOTTOMLEFT", 1 + STRIPE, 1)
	bar.timer:SetPoint("BOTTOMRIGHT", -1, 1)
	bar.timer.bg = bar.timer:CreateTexture(nil, "BACKGROUND")
	bar.timer.bg:SetAllPoints()
	bar.timer.bg:SetColorTexture(1, 1, 1, 0.06)

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

	bar.dice = bar:CreateTexture(nil, "OVERLAY")
	bar.dice:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
	bar.dice:SetSize(30, 30)
	bar.dice:SetPoint("RIGHT", -14, 0)
	bar.dice:Hide()
	bar.dice.spin = bar.dice:CreateAnimationGroup()
	bar.dice.spin:SetLooping("REPEAT")
	local turn = bar.dice.spin:CreateAnimation("Rotation")
	turn:SetDegrees(-360)
	turn:SetDuration(0.45)

	bar.flash = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.flash:SetPoint("TOPLEFT", 1, -1)
	bar.flash:SetPoint("BOTTOMRIGHT", -1, 1)
	bar.flash:SetColorTexture(1, 1, 1, 1)
	bar.flash:SetBlendMode("ADD")
	bar.flash:SetAlpha(0)
	bar.flash.anim = bar.flash:CreateAnimationGroup()
	local up = bar.flash.anim:CreateAnimation("Alpha")
	up:SetFromAlpha(0)
	up:SetToAlpha(0.35)
	up:SetDuration(0.1)
	up:SetOrder(1)
	local down = bar.flash.anim:CreateAnimation("Alpha")
	down:SetFromAlpha(0.35)
	down:SetToAlpha(0)
	down:SetDuration(0.7)
	down:SetOrder(2)

	bar.pop = bar.status:CreateAnimationGroup()
	local pop = bar.pop:CreateAnimation("Scale")
	pop:SetOrigin("LEFT", 0, 0)
	pop:SetScaleFrom(1.35, 1.35)
	pop:SetScaleTo(1, 1)
	pop:SetDuration(0.3)
	pop:SetSmoothing("OUT")

	bar:SetScript("OnUpdate", RollFrame.UpdateBar)
	return bar
end

local fitText -- defined below

local function layout()
	local width = ns.settings.barWidth
	anchor:SetWidth(width)
	for i, bar in ipairs(bars) do
		bar:ClearAllPoints()
		bar:SetWidth(width)
		if bar.roll then fitText(bar, bar.need:IsShown()) end
		local offset = (i - 1) * (BAR_HEIGHT + BAR_GAP)
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
local TEXT_LEFT = 1 + STRIPE + 7 + ICON_SIZE + 9
local BUTTONS_AREA = 3 * BUTTON_SIZE + 2 * BUTTON_GAP + 9 + 10

function fitText(bar, withButtons)
	local avail = ns.settings.barWidth - TEXT_LEFT - (withButtons and BUTTONS_AREA or 10)
	local tagWidth = bar.tag:IsShown() and (W.StringWidth(bar.tag) + 6) or 0
	bar.name:SetWidth(math.max(20, math.min(W.StringWidth(bar.name) + 2, avail - tagWidth)))
	bar.statusWidth = math.max(20, avail)
	bar.status:SetWidth(bar.statusWidth)
end

-- Who's chosen what so far, fitted to the line (see Widgets.FitRoster). You show up as "You".
local function rosterLine(bar)
	local drop = bar.drop
	local prefix = bar.selfRoll and ("|c%sYou rolled %d|r   "):format(W.ACCENT_HEX, bar.selfRoll) or ""
	if not drop then
		local text = prefix
		local mine = bar.roll and bar.roll.myChoice
		if mine and not bar.selfRoll then
			text = text .. ("|c%sYou: %s|r   "):format(W.ACCENT_HEX, ns.Choices[mine].label)
		end
		if bar.roll and bar.roll.closed then
			text = text .. ("|c%sWaiting for the others...|r"):format(W.MUTED_HEX)
		end
		bar.status:SetText(text)
		return
	end
	W.FitRoster(bar.status, drop, bar.statusWidth or 200, { prefix = prefix })
end

local function resultText(drop)
	if drop.allPassed then
		return ("|c%sEveryone passed.|r"):format(W.MUTED_HEX), false
	end
	local r = drop.rolls[drop.winner] or {}
	local how = r.choice and ns.Choices[r.choice] and ns.Choices[r.choice].label or ""
	local text = ("Won by %s"):format(ns.ColorName(drop.winner, drop.winnerClass or r.class))
	if r.roll then
		text = text .. ("  |c%s%s|r |cffffffff%d|r"):format(W.MUTED_HEX, how, r.roll)
	end
	local mine = drop.winner == ns.PlayerName()
	if mine then
		text = ("|c%sYours!|r  "):format(W.ACCENT_HEX) .. text
	end
	return text, mine
end

local function stopAnimations(bar)
	bar.revealAt = nil
	bar.intro:Stop()
	bar.dice.spin:Stop()
	bar.dice:Hide()
	bar.flash.anim:Stop()
	bar.flash:SetAlpha(0)
	bar.pop:Stop()
end

-- The result lands: final text, a flash (gold if it's yours) and a little pop.
local function reveal(bar)
	bar.revealAt = nil
	bar.dice.spin:Stop()
	bar.dice:Hide()
	bar.status:SetText(bar.resultText)
	if bar.youWon then
		bar.flash:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
		bar:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
	else
		bar.flash:SetVertexColor(ns.QualityColor(bar.roll and bar.roll.quality))
	end
	bar.flash.anim:Play()
	bar.pop:Play()
end

local function showResult(bar)
	local drop = bar.drop
	for _, b in ipairs(bar.buttons) do b:Hide() end
	bar.timer:Hide()
	fitText(bar, false)
	bar.resultText, bar.youWon = resultText(drop)
	if bar.resultShown then
		-- A later update for an already-finished drop: just keep the text current.
		if not bar.revealAt then bar.status:SetText(bar.resultText) end
		return
	end
	bar.resultShown = true
	if ns.settings.animations and not drop.allPassed then
		bar.revealAt = GetTime() + REVEAL_TIME
		bar.nextTick = 0
		bar.dice:Show()
		bar.dice.spin:Play()
		bar.fadeAt = bar.revealAt + RESULT_LINGER
	else
		bar.status:SetText(bar.resultText)
		if bar.youWon then bar:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end
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
		b.selected = roll.myChoice == b.choice
		paintButton(b)
	end
	bar.timer:SetShown(open)
	fitText(bar, open)
	rosterLine(bar)
	if not open and not bar.fadeAt then
		bar.fadeAt = GetTime() + ((bar.drop or bar.roll.isTest) and WAIT_LINGER or 6)
	end
end

function RollFrame.UpdateBar(bar)
	local roll = bar.roll
	if not roll then return end
	if bar.timer:IsShown() then
		local left = ns.LootSource.TimeLeft(roll)
		local frac = roll.rollTime > 0 and left / roll.rollTime or 0
		bar.timer:SetValue(left)
		-- gold while there's time, sliding to red as it runs out
		bar.timer:SetStatusBarColor(1, 0.3 + frac * 0.48, 0.2 + frac * 0.08)
	end
	if bar.revealAt then
		local t = GetTime()
		if t >= bar.revealAt then
			reveal(bar)
		elseif t >= bar.nextTick then
			bar.nextTick = t + 0.06
			bar.status:SetText(("|c%sRolling...|r  |cffffffff%d|r"):format(W.MUTED_HEX, math.random(1, 100)))
		end
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
	bar:Hide()
	bar.roll, bar.drop, bar.fadeAt, bar.selfRoll, bar.resultShown = nil, nil, nil, nil, nil
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
	stopAnimations(bar)
	bar:SetAlpha(1)
	W.Skin(bar)
	bar.iconButton.icon:SetTexture(roll.texture or ns.FALLBACK_ICON)
	bar.iconButton.count:SetText((roll.count or 1) > 1 and roll.count or "")
	local r, g, b = ns.QualityColor(roll.quality)
	bar.iconButton:SetBackdropBorderColor(r, g, b, 1)
	bar.stripe:SetColorTexture(r, g, b, 1)
	W.SetFade(bar.tint, r, g, b, 0.16)
	bar.name:SetText(roll.name or "?")
	bar.name:SetTextColor(r, g, b)
	bar.tag:SetText(roll.bop and "BoP" or "")
	bar.tag:SetShown(roll.bop == true)
	bar.timer:SetMinMaxValues(0, roll.rollTime)

	local function reason(code)
		return code and _G["LOOT_ROLL_INELIGIBLE_REASON" .. code] or nil
	end
	for _, btn in ipairs(bar.buttons) do
		btn.selected, btn.hovered = false, false
	end
	setButtonEnabled(bar.need, roll.canNeed == true, reason(roll.reasonNeed))
	setButtonEnabled(bar.greed, roll.canGreed == true, reason(roll.reasonGreed))
	setButtonEnabled(bar.pass, true, nil)

	table.insert(bars, bar)
	bar:Show()
	layout()
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
	anchor:SetBackdropColor(0.22, 0.17, 0.06, unlocked and 0.92 or 0)
	anchor:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], unlocked and 0.9 or 0)
	anchor.label:SetShown(unlocked)
	anchor.label:SetWidth(math.max(40, ns.settings.barWidth - 140))
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

function RollFrame.ResetPosition()
	ns.settings.position = nil
	placeAnchor()
end


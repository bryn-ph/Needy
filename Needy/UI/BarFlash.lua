-- Optional (flashBars, off by default): a halo that breathes round a roll bar as it appears, for when the
-- bars are tucked away in a corner. It's the game's own loot toast glow, in the item's quality colour (gold
-- for the wishlist), drawn behind the bar so only the part outside it shows.
local _, ns = ...

local BarFlash = {}
ns.BarFlash = BarFlash

local GOLD = ns.Widgets.GOLD

local SPREAD = 22 -- how far the halo reaches past the bar's edge
local PULSE = 0.9 -- seconds each; slow enough to be a breath rather than a strobe
local PULSE_RISE = 0.22
local PULSES, WISH_PULSES = 2, 3
local STILL_TIME = 1.8 -- with animations off: one fade in, a hold and a fade out
local STILL_FADE = 0.3
local MAX_STEP = 0.1 -- so a frame hitch can't swallow the whole flash

local function smooth(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

local function brightness(f)
	local t = f.elapsed
	if f.still then
		return smooth(t / STILL_FADE) * smooth((f.duration - t) / STILL_FADE)
	end
	local p = t % PULSE
	if p < PULSE_RISE then return smooth(p / PULSE_RISE) end
	return smooth((PULSE - p) / (PULSE - PULSE_RISE))
end

local function update(self, elapsed)
	self.elapsed = self.elapsed + math.min(elapsed, MAX_STEP)
	if self.elapsed >= self.duration then
		self:Hide()
	else
		self:SetAlpha(brightness(self))
	end
end

-- Returns a halo for `bar` with :Play(quality, wished) and :Stop().
function BarFlash.Create(bar)
	-- A sibling just below the bar rather than a child, which would draw over it.
	local f = CreateFrame("Frame", nil, bar:GetParent())
	f:SetPoint("TOPLEFT", bar, "TOPLEFT", -SPREAD, SPREAD)
	f:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", SPREAD, -SPREAD)
	f:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	f:EnableMouse(false)
	f:Hide()
	f.glow = f:CreateTexture(nil, "BACKGROUND")
	f.glow:SetAtlas("loottoast-glow")
	f.glow:SetBlendMode("ADD")
	f.glow:SetAllPoints()
	f:SetScript("OnUpdate", update)

	function f:Play(quality, wished)
		if wished then
			self.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		else
			self.glow:SetVertexColor(ns.QualityColor(quality))
		end
		self.elapsed = 0
		self.still = not ns.settings.animations
		self.duration = self.still and STILL_TIME or PULSE * (wished and WISH_PULSES or PULSES)
		self:SetAlpha(0)
		self:Show()
	end

	function f:Stop()
		self:Hide()
	end

	return f
end

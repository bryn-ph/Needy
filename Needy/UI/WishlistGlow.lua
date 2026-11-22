-- What a roll bar wears when its item is on the wishlist: a burst as it appears, then a breathing glow on
-- the icon and a sheen across the bar. The art is the game's own loot toast's.
local _, ns = ...

local WishlistGlow = {}
ns.WishlistGlow = WishlistGlow

local SHEEN_WIDTH = 100
local EDGE = 4

local function texture(parent, atlas, sublevel)
	local t = parent:CreateTexture(nil, "OVERLAY", nil, sublevel)
	t:SetAtlas(atlas)
	t:SetBlendMode("ADD")
	t:SetAlpha(0)
	return t
end

local function fade(group, from, to, duration, delay)
	local a = group:CreateAnimation("Alpha")
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(duration)
	a:SetStartDelay(delay or 0)
	return a
end

-- Returns a frame over `bar` with :Start(animate) and :Stop(). `icon` is the bar's item icon.
function WishlistGlow.Create(bar, icon)
	local f = CreateFrame("Frame", nil, bar)
	f:SetAllPoints()
	f:SetFrameLevel(bar:GetFrameLevel() + 3) -- over the icon and buttons, under the roll animation
	f:Hide()

	f.flash = texture(f, "loottoast-glow", 1)
	f.flash:SetPoint("TOPLEFT", -10, 10)
	f.flash:SetPoint("BOTTOMRIGHT", 10, -10)
	f.flashing = f.flash:CreateAnimationGroup()
	fade(f.flashing, 1, 0, 1.2)

	f.burst = texture(f, "LegendaryToast-OrangeStarglow", 2)
	f.burst:SetSize(120, 121)
	f.burst:SetPoint("CENTER", icon)
	f.bursting = f.burst:CreateAnimationGroup()
	fade(f.bursting, 1, 0, 1.1)
	local grow = f.bursting:CreateAnimation("Scale")
	grow:SetScaleFrom(0.4, 0.4)
	grow:SetScaleTo(1.2, 1.2)
	grow:SetDuration(1.1)

	f.halo = texture(f, "loottoast-itemborder-glow", 3)
	f.halo:SetSize(52, 52)
	f.halo:SetPoint("CENTER", icon)
	f.breathing = f.halo:CreateAnimationGroup()
	f.breathing:SetLooping("BOUNCE")
	fade(f.breathing, 0.3, 1, 0.8):SetSmoothing("IN_OUT")

	f.sheen = texture(f, "loottoast-sheen", 4)
	f.sheen:SetSize(SHEEN_WIDTH, 48)
	f.sheen:SetPoint("LEFT", EDGE, 0)
	f.sweeping = f.sheen:CreateAnimationGroup()
	f.sweeping:SetLooping("REPEAT")
	fade(f.sweeping, 0, 0.8, 0.2)
	fade(f.sweeping, 0.8, 0, 0.3, 0.6):SetEndDelay(1.6) -- the pause between sweeps
	f.travel = f.sweeping:CreateAnimation("Translation")
	f.travel:SetDuration(0.9)

	f.mark = f:CreateTexture(nil, "OVERLAY", nil, 7)
	f.mark:SetTexture(ns.Wishlist.MARK)
	f.mark:SetSize(18, 18)
	f.mark:SetPoint("CENTER", icon, "TOPLEFT", 3, -3)

	local groups = { f.flashing, f.bursting, f.breathing, f.sweeping }

	function f:Stop()
		for _, group in ipairs(groups) do group:Stop() end
		self:Hide()
	end

	-- With animations off it's just the halo and the mark.
	function f:Start(animate)
		self:Show()
		self.halo:SetAlpha(animate and 0 or 1)
		if not animate then return end
		self.travel:SetOffset(ns.settings.barWidth - SHEEN_WIDTH - 2 * EDGE, 0)
		for _, group in ipairs(groups) do group:Play() end
	end

	return f
end

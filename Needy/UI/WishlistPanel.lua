-- The list on the Wishlist tab of settings, in two views:
--   Mine         each item you want, where it drops, and who else in your group or guild wants it too
--   Everyone's   everything your group and guildmates want, overlaps with yours first, with who wants each
-- An item someone in your group wants as well as you is contested (orange); one only guildmates also want is
-- shared (gold). Your group's lists always count; "Include guildmates" adds your guild's, here and in
-- DungeonJournal's badges and tooltips (the wantsFrom setting).
--
-- Each row is a dark card washed with the item's quality colour from the left, with a strip of it down the
-- edge; contested and shared items get a coloured edge and a tag saying how many others want them.
local _, ns = ...

local WishlistPanel = {}
ns.WishlistPanel = WishlistPanel

local W = ns.Widgets

local ROW_HEIGHT = 54
local ROW_GAP = 4
local ICON_SIZE = 34
local BUTTON_SIZE = 22
local TEXT_LEFT = 10 + ICON_SIZE + 10
local TOOLBAR = 28 -- the view tabs, and the guild tick box beside them
local INSET_PAD = 5
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function nobodyText()
	return ns.settings.wantsFrom == "group" and "Nobody else in your group wants this"
		or "Nobody else in your group or guild wants this"
end

-- Rows ---------------------------------------------------------------------------------------------

local function setTag(row, overlap, who)
	if not overlap then
		row.tag:Hide()
		return 0
	end
	local c = overlap == "contested" and W.CONTESTED or ns.Wishlist.RIM
	row.tag:SetBackdropColor(c[1], c[2], c[3], 0.22)
	row.tag:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
	row.tag.text:SetTextColor(c[1], c[2], c[3])
	if overlap == "contested" then
		row.tag.text:SetText(("%d in your group"):format(#who.group))
	else
		row.tag.text:SetText(("%d in your guild"):format(#who.guild))
	end
	local w = W.StringWidth(row.tag.text) + 12
	row.tag:SetWidth(w)
	row.tag:Show()
	return w
end

-- The edge says how the item overlaps; the strip and wash say its quality.
local function paint(row, quality, overlap)
	local r, g, b = ns.QualityColor(quality)
	row.strip:SetColorTexture(r, g, b, 0.9)
	if row.wash.SetGradient and CreateColor then
		row.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
	else
		row.wash:SetColorTexture(r, g, b, 0.08)
	end
	if overlap == "contested" then
		local c = W.CONTESTED
		row:SetBackdropBorderColor(c[1], c[2], c[3], 0.85)
	elseif overlap == "shared" then
		local c = ns.Wishlist.RIM
		row:SetBackdropBorderColor(c[1], c[2], c[3], 0.55)
	else
		row:SetBackdropBorderColor(1, 1, 1, 0.08)
	end
end

local function setHover(row, on)
	row.hover:SetShown(on)
	local a = on and 1 or 0.55
	row.remove:SetAlpha(a)
	row.toggle:SetAlpha(on and 1 or (ns.Wishlist.Has(row.itemID) and 0.9 or 0.45))
end

local function createRow(parent, width)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetSize(width, ROW_HEIGHT)
	row:SetBackdrop(W.FLAT_BACKDROP)
	row:SetBackdropColor(0.07, 0.07, 0.08, 0.92)
	row:EnableMouse(true)

	row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.wash:SetTexture(WHITE)
	row.wash:SetPoint("TOPLEFT", 1, -1)
	row.wash:SetPoint("BOTTOMLEFT", 1, 1)
	row.wash:SetWidth(width * 0.6)
	row.strip = row:CreateTexture(nil, "BORDER")
	row.strip:SetPoint("TOPLEFT", 1, -1)
	row.strip:SetPoint("BOTTOMLEFT", 1, 1)
	row.strip:SetWidth(3)
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.hover:Hide()

	row.icon = W.ItemIcon(row, ICON_SIZE)
	row.icon:SetPoint("LEFT", 10, 0)
	row.icon:EnableMouse(false)

	row.textWidth = width - TEXT_LEFT - BUTTON_SIZE - 16
	row.name = W.Text(row, "GameFontNormal")
	row.name:SetPoint("TOPLEFT", TEXT_LEFT, -7)
	row.name:SetWordWrap(false)
	row.where = W.Text(row, "GameFontHighlightSmall")
	row.where:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.where:SetWidth(row.textWidth)
	row.where:SetTextColor(0.6, 0.6, 0.6)
	row.where:SetWordWrap(false)
	row.wanters = W.Text(row, "GameFontHighlightSmall")
	row.wanters:SetPoint("TOPLEFT", row.where, "BOTTOMLEFT", 0, -3)
	row.wanters:SetWidth(row.textWidth)
	row.wanters:SetWordWrap(false)

	row.tag = CreateFrame("Frame", nil, row, "BackdropTemplate")
	row.tag:SetBackdrop(W.FLAT_BACKDROP)
	row.tag:SetHeight(15)
	row.tag:SetPoint("TOPRIGHT", -(BUTTON_SIZE + 14), -6)
	row.tag.text = W.Text(row.tag, "GameFontHighlightSmall")
	row.tag.text:SetPoint("CENTER", 0, 0)
	row.tag:Hide()

	-- Mine: take it off. Everyone's: the heart, lit when it's on your list, to add or remove it.
	row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.remove:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	row.remove:ClearAllPoints()
	row.remove:SetPoint("RIGHT", -8, 0)
	row.remove:SetScript("OnClick", function()
		GameTooltip:Hide()
		ns.Wishlist.Toggle(row.itemID)
	end)
	row.remove:SetScript("OnEnter", function()
		setHover(row, true)
	end)
	row.remove:SetScript("OnLeave", function()
		setHover(row, false)
		GameTooltip:Hide()
	end)

	row.toggle = CreateFrame("Button", nil, row)
	row.toggle:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	row.toggle:SetPoint("RIGHT", -8, 0)
	row.toggle.mark = row.toggle:CreateTexture(nil, "ARTWORK")
	row.toggle.mark:SetTexture(ns.Wishlist.MARK)
	row.toggle.mark:SetSize(18, 18)
	row.toggle.mark:SetPoint("CENTER")
	row.toggle:SetScript("OnClick", function()
		GameTooltip:Hide()
		ns.Wishlist.Toggle(row.itemID, row.itemName)
	end)
	row.toggle:SetScript("OnEnter", function(self)
		setHover(row, true)
		W.Tip(self, ns.Wishlist.Has(row.itemID) and "Remove from wishlist" or "Add to wishlist")
	end)
	row.toggle:SetScript("OnLeave", function()
		setHover(row, false)
		GameTooltip:Hide()
	end)

	row:SetScript("OnEnter", function(self)
		setHover(self, true)
		if not self.link then return end
		W.ItemTooltip(self, self.link)
		if self.who then
			W.AddWanters(GameTooltip, self.who, ns.Wishlist.Has(self.itemID))
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		setHover(self, false)
		GameTooltip:Hide()
	end)
	row:SetScript("OnMouseUp", function(self)
		if self.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			HandleModifiedItemClick(self.link)
		end
	end)
	return row
end

-- entry = { id, name?, who }. Shows what's known straight away, then fills in the game's name and link once
-- the item has loaded.
local function setRow(row, entry, view)
	local id = entry.id
	local mine = ns.Wishlist.Has(id)
	row.itemID = id
	row.who = entry.who
	row.link = "item:" .. id
	local source = ns.DungeonJournal.Source(id)
	row.itemName = entry.name or (source and source.name) or nil
	local quality = source and source.quality or W.DropQuality({ link = row.link })
	local overlap = mine and W.Overlap(entry.who) or nil

	row.icon:SetItem(W.DropIcon({ link = row.link }), quality)
	row.icon:SetWished(mine)
	local tagWidth = setTag(row, overlap, entry.who)
	row.name:SetWidth(row.textWidth - (tagWidth > 0 and tagWidth + 6 or 0)) -- the tag ends 6px short of the button
	row.name:SetText(row.itemName or ("Item " .. id))
	row.name:SetTextColor(ns.QualityColor(quality))
	row.where:SetText(source and source.text or "")
	if entry.who.count > 0 then
		W.FitWanters(row.wanters, entry.who, row.textWidth)
	else
		row.wanters:SetText(("|c%s%s|r"):format(W.FAINT_HEX, nobodyText()))
	end
	paint(row, quality, overlap)

	row.remove:SetShown(view == "mine")
	row.toggle:SetShown(view ~= "mine")
	row.toggle.mark:SetDesaturated(not mine)
	setHover(row, false)

	if not (Item and Item.CreateFromItemID) then return end
	local data = Item:CreateFromItemID(id)
	if data:IsItemEmpty() then return end
	data:ContinueOnItemLoad(function()
		if row.itemID ~= id then return end -- the row has moved on to another item
		local name = data:GetItemName()
		if name then
			row.name:SetText(name)
			row.itemName = row.itemName or name
		end
		row.link = data:GetItemLink() or row.link
		local loaded = source and source.quality or data:GetItemQuality()
		row.icon:SetItem(data:GetItemIcon(), loaded)
		row.name:SetTextColor(ns.QualityColor(loaded))
		paint(row, loaded, overlap)
	end)
end

-- Lists ----------------------------------------------------------------------------------------------

-- Your items, in the list's order (by name), each with who else wants it.
local function mineEntries()
	local out = {}
	for _, item in ipairs(ns.Wishlist.List()) do
		table.insert(out, { id = item.id, name = item.name, who = ns.Sharing.WhoWants(item.id) })
	end
	return out
end

-- Everything others want: your contested items, then your shared ones, then by how many in your group
-- want it, then how many in all.
local function everyoneEntries()
	local out = {}
	for _, e in ipairs(ns.Sharing.Wanted()) do
		local mine = ns.Wishlist.Has(e.id)
		table.insert(out, { id = e.id, who = e, rank = mine and (#e.group > 0 and 2 or 1) or 0 })
	end
	table.sort(out, function(a, b)
		if a.rank ~= b.rank then return a.rank > b.rank end
		if #a.who.group ~= #b.who.group then return #a.who.group > #b.who.group end
		if a.who.count ~= b.who.count then return a.who.count > b.who.count end
		return a.id < b.id
	end)
	return out
end

local function emptyText(view)
	if view == "mine" then
		return ns.DungeonJournal.IsHooked() and "Nothing here yet. Right-click an item in DungeonJournal to add it."
			or "Nothing here yet. Items are added from DungeonJournal, which isn't loaded."
	end
	if ns.settings.wantsFrom == "group" and not (IsInGroup and IsInGroup()) then
		return "You're not in a group."
	end
	return "No one has shared a wishlist yet."
end

-- "Your wishlist  ● 2 contested  ● 1 shared", coloured to match the rows.
local function headerText(view, mine)
	if view ~= "mine" then
		return ns.settings.wantsFrom == "group" and "Wanted in your group" or "Wanted in your group and guild"
	end
	local contested, shared = 0, 0
	for _, e in ipairs(mine) do
		local o = W.Overlap(e.who)
		if o == "contested" then contested = contested + 1 elseif o == "shared" then shared = shared + 1 end
	end
	local text = "Your wishlist"
	if contested > 0 then
		text = text .. ("   |c%s%d wanted in your group too|r"):format(W.CONTESTED_HEX, contested)
	end
	if shared > 0 then
		text = text .. ("   |cffdba838%d by guildmates|r"):format(shared)
	end
	return text
end

-- Panel ---------------------------------------------------------------------------------------------

-- header: the fontstring above the list, which says which view it is. Returns the list, with :Refresh().
function WishlistPanel.Create(parent, width, header)
	local panel = CreateFrame("Frame", nil, parent)
	WishlistPanel.panel = panel -- there's one, on the settings window's Wishlist tab
	local rowWidth = width - 2 * INSET_PAD - 12 -- inside the inset, clear of the scroll thumb
	panel.view = "mine"

	-- The list sits in a sunken inset, like the game's own lists, with the views as tabs on top of it.
	panel.inset = W.Inset(panel)
	panel.inset:SetPoint("TOPLEFT", 0, -TOOLBAR)
	panel.inset:SetPoint("BOTTOMRIGHT")

	panel.tabs = W.TopTabs(panel, { { "mine", "Mine" }, { "everyone", "Everyone's" } }, function(key)
		panel.view = key
		panel.scroll:SetVerticalScroll(0)
		panel:Refresh()
	end)
	panel.tabs:SetPoint("BOTTOMLEFT", panel.inset, "TOPLEFT", 8, -1)

	-- Your group's lists always count; guildmates' only when this is ticked.
	panel.guild = W.Check(panel, "Include guildmates", nil,
		function() return ns.settings.wantsFrom == "guild" end,
		function(on)
			ns.settings.wantsFrom = on and "guild" or "group"
			ns.Sharing.ScopeChanged()
		end)
	panel.guild:SetPoint("RIGHT", panel, "TOPRIGHT", -(W.StringWidth(panel.guild.label) + 8), -TOOLBAR / 2 + 1)

	panel.scroll, panel.list = W.ScrollArea(panel.inset)
	panel.scroll:SetPoint("TOPLEFT", INSET_PAD, -INSET_PAD)
	panel.scroll:SetPoint("BOTTOMRIGHT", -(INSET_PAD + 10), INSET_PAD)

	panel.emptyIcon = panel.inset:CreateTexture(nil, "ARTWORK")
	panel.emptyIcon:SetTexture(ns.Wishlist.MARK)
	panel.emptyIcon:SetSize(40, 40)
	panel.emptyIcon:SetPoint("BOTTOM", panel.inset, "CENTER", 0, 30)
	panel.emptyIcon:SetDesaturated(true)
	panel.emptyIcon:SetAlpha(0.35)
	panel.empty = W.Text(panel.inset, "GameFontDisable")
	panel.empty:SetPoint("TOP", panel.emptyIcon, "BOTTOM", 0, -10)
	panel.empty:SetWidth(width - 70)
	panel.empty:SetJustifyH("CENTER")

	panel.rows = {}
	function panel:Refresh()
		local mine, everyone = mineEntries(), everyoneEntries()
		self.tabs:SetLabel("mine", #mine > 0 and ("Mine  |cffb0b0b0%d|r"):format(#mine) or "Mine")
		self.tabs:SetLabel("everyone", #everyone > 0 and ("Everyone's  |cffb0b0b0%d|r"):format(#everyone) or "Everyone's")
		self.tabs:Select(self.view)
		self.guild:Refresh()
		header:SetText(headerText(self.view, mine))

		local entries = self.view == "mine" and mine or everyone
		for _, row in ipairs(self.rows) do row:Hide() end
		for i, entry in ipairs(entries) do
			local row = self.rows[i]
			if not row then
				row = createRow(self.list, rowWidth)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_GAP))
				self.rows[i] = row
			end
			setRow(row, entry, self.view)
			row:Show()
		end
		local height = math.max(1, #entries * (ROW_HEIGHT + ROW_GAP) - ROW_GAP)
		self.list:SetSize(rowWidth, height)

		self.empty:SetShown(#entries == 0)
		self.emptyIcon:SetShown(#entries == 0)
		self.empty:SetText(emptyText(self.view))

		-- Taking off the last row mustn't leave the list scrolled past its end.
		local most = math.max(0, height - (self.scroll:GetHeight() or 0))
		self.scroll:SetVerticalScroll(math.min(most, self.scroll:GetVerticalScroll() or 0))
		self.scroll.UpdateThumb()
	end

	return panel
end

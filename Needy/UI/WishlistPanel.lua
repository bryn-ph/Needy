-- The list on the Wishlist tab of settings: each wanted item, where it drops, and a button to take it off.
local _, ns = ...

local WishlistPanel = {}
ns.WishlistPanel = WishlistPanel

local W = ns.Widgets

local ROW_HEIGHT = 40
local ROW_GAP = 3
local ICON_SIZE = 30
local REMOVE_SIZE = 24
local TEXT_LEFT = 6 + ICON_SIZE + 10

local function createRow(parent, width)
	local row = W.Card(parent)
	row:SetSize(width, ROW_HEIGHT)
	row:EnableMouse(true)

	row.icon = W.ItemIcon(row, ICON_SIZE)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:EnableMouse(false)
	row.icon:SetWished(true)

	local textWidth = width - TEXT_LEFT - REMOVE_SIZE - 12
	row.name = W.Text(row, "GameFontNormal")
	row.name:SetPoint("TOPLEFT", TEXT_LEFT, -6)
	row.name:SetWidth(textWidth)
	row.name:SetWordWrap(false)
	row.where = W.Text(row, "GameFontHighlightSmall")
	row.where:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
	row.where:SetWidth(textWidth)
	row.where:SetTextColor(0.65, 0.65, 0.65)
	row.where:SetWordWrap(false)

	row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.remove:SetSize(REMOVE_SIZE, REMOVE_SIZE)
	row.remove:ClearAllPoints()
	row.remove:SetPoint("RIGHT", -6, 0)
	row.remove:SetScript("OnClick", function()
		GameTooltip:Hide()
		ns.Wishlist.Toggle(row.itemID)
	end)
	row.remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Remove from wishlist", 1, 1, 1)
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row:SetScript("OnEnter", function(self) W.ItemTooltip(self, self.link) end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		if self.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			HandleModifiedItemClick(self.link)
		end
	end)
	return row
end

-- Shows what's known straight away, then fills in the game's name and link once the item has loaded.
local function setRow(row, item)
	row.itemID = item.id
	row.link = "item:" .. item.id
	local source = ns.DungeonJournal.Source(item.id)
	local quality = source and source.quality or W.DropQuality({ link = row.link })
	row.icon:SetItem(W.DropIcon({ link = row.link }), quality)
	row.name:SetText(item.name)
	row.name:SetTextColor(ns.QualityColor(quality))
	row.where:SetText(source and source.text or "")

	if not (Item and Item.CreateFromItemID) then return end
	local data = Item:CreateFromItemID(item.id)
	if data:IsItemEmpty() then return end
	data:ContinueOnItemLoad(function()
		if row.itemID ~= item.id then return end -- the row has moved on to another item
		local name = data:GetItemName()
		if name then row.name:SetText(name) end
		row.link = data:GetItemLink() or row.link
		local loaded = source and source.quality or data:GetItemQuality()
		row.icon:SetItem(data:GetItemIcon(), loaded)
		row.name:SetTextColor(ns.QualityColor(loaded))
	end)
end

-- header: the fontstring that carries the count. Returns the list, with :Refresh().
function WishlistPanel.Create(parent, width, header)
	local panel = CreateFrame("Frame", nil, parent)
	local rowWidth = width - 10 -- clear of the scroll thumb

	panel.scroll, panel.list = W.ScrollArea(panel)
	panel.scroll:SetPoint("TOPLEFT")
	panel.scroll:SetPoint("BOTTOMRIGHT", -10, 0)

	panel.empty = W.Text(panel, "GameFontDisable")
	panel.empty:SetPoint("CENTER")
	panel.empty:SetWidth(width - 60)
	panel.empty:SetJustifyH("CENTER")

	panel.rows = {}
	function panel:Refresh()
		local items = ns.Wishlist.List()
		header:SetText(#items > 0 and ("Tracked items (%d)"):format(#items) or "Tracked items")
		for _, row in ipairs(self.rows) do row:Hide() end
		for i, item in ipairs(items) do
			local row = self.rows[i]
			if not row then
				row = createRow(self.list, rowWidth)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_GAP))
				self.rows[i] = row
			end
			setRow(row, item)
			row:Show()
		end
		local height = math.max(1, #items * (ROW_HEIGHT + ROW_GAP))
		self.list:SetSize(rowWidth, height)

		self.empty:SetShown(#items == 0)
		self.empty:SetText(ns.DungeonJournal.IsHooked()
			and "Nothing tracked yet.\n\nRight-click an item in DungeonJournal's loot lists and choose Add to Needy Wishlist."
			or "Nothing tracked yet.\n\nItems are added from the DungeonJournal addon, which isn't running or is a version Needy doesn't know.")

		-- Taking off the last row mustn't leave the list scrolled past its end.
		local most = math.max(0, height - (self.scroll:GetHeight() or 0))
		self.scroll:SetVerticalScroll(math.min(most, self.scroll:GetVerticalScroll() or 0))
		self.scroll.UpdateThumb()
	end

	return panel
end

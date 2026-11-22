-- The end-of-run awards screen, plus posting the awards to group chat.
local _, ns = ...

local SummaryWindow = {}
ns.SummaryWindow = SummaryWindow

local W = ns.Widgets
local C = W.C

local WIDTH, HEIGHT = 460, 580
local CARD_HEIGHT = 54
local CARD_GAP = 5

local win
local cards = {}

-- Chat ------------------------------------------------------------------------------------------

-- The group's channel: instance chat, then raid, then party; nil when you're not in a group.
local function channelFor()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function plainNames(players)
	local names = {}
	for _, p in ipairs(players) do
		table.insert(names, ns.ShortName(p.name))
	end
	return table.concat(names, ", ")
end

function SummaryWindow.AnnounceLines(session)
	local awards = ns.Titles.Compute(session)
	local lines = {}
	table.insert(lines, ("Needy awards for %s%s:"):format(
		ns.HistoryWindow.SessionLabel(session), session.isTest and " (test run)" or ""))
	for _, a in ipairs(awards) do
		local line = ("%s: %s (%s)"):format(a.title, plainNames(a.players), a.text)
		if #line > 250 then line = line:sub(1, 247) .. "..." end
		table.insert(lines, line)
	end
	return lines
end

local function send(text, channel)
	local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok = pcall(fn, text, channel)
	return ok
end

-- Posts the awards to group chat, or prints them for you when you're not in a group.
function SummaryWindow.Announce(session)
	local lines = SummaryWindow.AnnounceLines(session)
	local channel = channelFor()
	local locked = (InCombatLockdown and InCombatLockdown())
		or (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
	if not channel or locked then
		if locked then ns.Print("Can't post to chat right now (combat or chat lockdown); here are the awards:") end
		for _, line in ipairs(lines) do
			print("  " .. ns.Escape(line))
		end
		return
	end
	for i, line in ipairs(lines) do
		C_Timer.After((i - 1) * 0.35, function()
			if not send(line, channel) and i == 1 then
				ns.Print("The game refused the chat message.")
			end
		end)
	end
end

-- Window ----------------------------------------------------------------------------------------

local function createCard(parent)
	local card = W.Card(parent)
	card:SetHeight(CARD_HEIGHT)

	card.stripe = card:CreateTexture(nil, "ARTWORK")
	card.stripe:SetPoint("TOPLEFT", 1, -1)
	card.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	card.stripe:SetWidth(3)
	card.tint = card:CreateTexture(nil, "BORDER")
	card.tint:SetPoint("TOPLEFT", 4, -1)
	card.tint:SetPoint("BOTTOMLEFT", 4, 1)
	card.tint:SetWidth(160)

	card.iconBorder = card:CreateTexture(nil, "ARTWORK")
	card.iconBorder:SetSize(38, 38)
	card.iconBorder:SetPoint("LEFT", 12, 0)
	card.icon = card:CreateTexture(nil, "OVERLAY")
	card.icon:SetPoint("TOPLEFT", card.iconBorder, "TOPLEFT", 1, -1)
	card.icon:SetPoint("BOTTOMRIGHT", card.iconBorder, "BOTTOMRIGHT", -1, 1)
	ns.CropIcon(card.icon)

	card.title = W.Text(card, "heading")
	card.title:SetPoint("TOPLEFT", card.iconBorder, "TOPRIGHT", 11, -3)
	card.text = W.Text(card, "muted")
	card.text:SetPoint("BOTTOMLEFT", card.iconBorder, "BOTTOMRIGHT", 11, 3)

	card.players = W.Text(card, "body")
	card.players:SetPoint("RIGHT", -12, 0)
	card.players:SetJustifyH("RIGHT")
	card.players:SetWordWrap(true)

	card.appear = card:CreateAnimationGroup()
	if card.appear.SetToFinalAlpha then card.appear:SetToFinalAlpha(true) end
	local a = card.appear:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(0.25)
	card.appearDelay = a
	local s = card.appear:CreateAnimation("Scale")
	s:SetScaleFrom(0.95, 0.95)
	s:SetScaleTo(1, 1)
	s:SetDuration(0.25)
	s:SetSmoothing("OUT")
	card.appearScale = s
	return card
end

local function setCard(card, award, i, width)
	local fallback = award.key == "background"
	local accent = fallback and C.faint or C.accent
	card.stripe:SetColorTexture(accent[1], accent[2], accent[3], 1)
	W.SetFade(card.tint, accent[1], accent[2], accent[3], fallback and 0.05 or 0.1)
	card.iconBorder:SetColorTexture(accent[1], accent[2], accent[3], fallback and 0.6 or 0.9)
	card.icon:SetTexture(award.icon or ns.FALLBACK_ICON)
	card.icon:SetDesaturated(fallback)
	card.title:SetText(award.title)
	card.title:SetTextColor(fallback and C.muted[1] or C.accent[1], fallback and C.muted[2] or C.accent[2], fallback and C.muted[3] or C.accent[3])
	card.text:SetText(award.text)
	local names = {}
	for _, p in ipairs(award.players) do
		table.insert(names, ns.ColorName(p.name, p.class))
	end
	card.players:SetText(table.concat(names, ", "))
	card.players:SetWidth(math.max(80, width * 0.42))
	local textWidth = width - 12 - 38 - 11 - width * 0.42 - 18
	card.title:SetWidth(textWidth)
	card.text:SetWidth(textWidth)
	card.title:SetWordWrap(false)
	card.text:SetWordWrap(false)

	if ns.settings.animations then
		card.appearDelay:SetStartDelay((i - 1) * 0.05)
		card.appearScale:SetStartDelay((i - 1) * 0.05)
		card:SetAlpha(0)
		card.appear:SetScript("OnFinished", function() card:SetAlpha(1) end)
		card.appear:Play()
	else
		card:SetAlpha(1)
	end
end

local function create()
	win = W.Window("NeedySummary", "Run Awards", WIDTH, HEIGHT)
	win:SetPoint("CENTER", 240, 30)
	local c = win.content

	win.heading = W.Text(c, "big")
	win.heading:SetPoint("TOPLEFT", 16, -14)
	win.heading:SetPoint("RIGHT", c, "RIGHT", -16, 0)
	win.heading:SetWordWrap(false)

	win.chips = {}
	local prevChip
	for i = 1, 4 do
		local chip = W.Chip(c)
		if prevChip then
			chip:SetPoint("LEFT", prevChip, "RIGHT", 6, 0)
		else
			chip:SetPoint("TOPLEFT", 16, -42)
		end
		win.chips[i] = chip
		prevChip = chip
	end

	local line = W.Hairline(c)
	line:SetPoint("TOPLEFT", 1, -70)
	line:SetPoint("TOPRIGHT", -1, -70)

	win.scroll, win.list = W.ScrollArea(c)
	win.scroll:SetPoint("TOPLEFT", 14, -80)
	win.scroll:SetPoint("BOTTOMRIGHT", -20, 50)

	win.empty = W.Text(c, "muted")
	win.empty:SetPoint("CENTER", 0, 0)
	win.empty:SetText("No finished rolls in this run, so no awards.")

	local footer = W.Hairline(c)
	footer:SetPoint("BOTTOMLEFT", 1, 40)
	footer:SetPoint("BOTTOMRIGHT", -1, 40)

	win.close = W.Button(c, CLOSE or "Close", 84, 24)
	win.close:SetPoint("BOTTOMRIGHT", -14, 9)
	win.close:SetScript("OnClick", function() win:Hide() end)
	win.history = W.Button(c, "History", 84, 24)
	win.history:SetPoint("RIGHT", win.close, "LEFT", -6, 0)
	win.history:SetScript("OnClick", function() ns.HistoryWindow.Show(win.session) end)
	win.announce = W.Button(c, "Announce to group", 150, 24, "accent")
	win.announce:SetPoint("BOTTOMLEFT", 14, 9)
	win.announce:SetScript("OnClick", function()
		if win.session then SummaryWindow.Announce(win.session) end
	end)
	win.announce:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local ch = channelFor()
		GameTooltip:SetText("Announce", 1, 1, 1)
		GameTooltip:AddLine(ch and ("Posts the awards to " .. ch:lower():gsub("_", " ") .. " chat.")
			or "You're not in a group, so the awards print to your own chat window.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	win.announce:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function SummaryWindow.Show(session)
	if not session then
		ns.Print("No run to show awards for yet.")
		return
	end
	if not win then create() end
	win.session = session
	win:Show()
	win:Raise()

	local awards, stats = ns.Titles.Compute(session)
	win.heading:SetText(ns.HistoryWindow.SessionLabel(session))
	local resolved, players = 0, 0
	for _, d in ipairs(session.drops) do
		if ns.Titles.IsResolved(d) then resolved = resolved + 1 end
	end
	for _ in pairs(stats) do players = players + 1 end
	local mins = math.max(1, math.floor(((session.endTime or time()) - session.startTime) / 60 + 0.5))
	local chipText = {
		("%d items rolled"):format(resolved),
		("%d players"):format(players),
		("%d min"):format(mins),
		session.isTest and "|cffff9933test run|r" or nil,
	}
	for i, chip in ipairs(win.chips) do
		if chipText[i] then
			chip:SetValue(chipText[i])
			chip:Show()
		else
			chip:Hide()
		end
	end

	for _, card in ipairs(cards) do card:Hide() end
	local width = win.scroll:GetWidth() or 0
	if width < 10 then width = WIDTH - 36 end
	local y = 0
	for i, a in ipairs(awards) do
		local card = cards[i]
		if not card then
			card = createCard(win.list)
			cards[i] = card
		end
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", 0, -y)
		card:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
		setCard(card, a, i, width)
		card:Show()
		y = y + CARD_HEIGHT + CARD_GAP
	end
	win.list:SetHeight(math.max(1, y))
	win.scroll:SetVerticalScroll(0)
	win.scroll.UpdateThumb()
	win.empty:SetShown(#awards == 0)
	win.announce:SetEnabled(#awards > 0)
end

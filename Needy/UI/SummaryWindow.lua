-- The end-of-run awards screen, plus posting the awards to group chat.
local _, ns = ...

local SummaryWindow = {}
ns.SummaryWindow = SummaryWindow

local W = ns.Widgets
local GOLD = W.GOLD

local WIDTH, HEIGHT = 470, 580
local CARD_HEIGHT = 50
local CARD_GAP = 4

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

	card.iconFrame = CreateFrame("Frame", nil, card)
	card.iconFrame:SetSize(36, 36)
	card.iconFrame:SetPoint("LEFT", 7, 0)
	card.icon = card.iconFrame:CreateTexture(nil, "ARTWORK")
	card.icon:SetAllPoints()
	ns.CropIcon(card.icon)
	card.border = card.iconFrame:CreateTexture(nil, "OVERLAY")
	card.border:SetAllPoints()
	card.border:SetTexture("Interface\\Common\\WhiteIconFrame")

	card.title = W.Text(card, "GameFontNormal")
	card.title:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 9, -3)
	card.title:SetWordWrap(false)
	card.text = W.Text(card, "GameFontHighlightSmall")
	card.text:SetPoint("BOTTOMLEFT", card.iconFrame, "BOTTOMRIGHT", 9, 3)
	card.text:SetTextColor(0.75, 0.75, 0.75)
	card.text:SetWordWrap(false)

	card.players = W.Text(card, "GameFontHighlight")
	card.players:SetPoint("RIGHT", -10, 0)
	card.players:SetJustifyH("RIGHT")
	card.players:SetWordWrap(true)

	card.appear = card:CreateAnimationGroup()
	if card.appear.SetToFinalAlpha then card.appear:SetToFinalAlpha(true) end
	card.appearAlpha = card.appear:CreateAnimation("Alpha")
	card.appearAlpha:SetFromAlpha(0)
	card.appearAlpha:SetToAlpha(1)
	card.appearAlpha:SetDuration(0.25)
	return card
end

local function setCard(card, award, i, width)
	local fallback = award.key == "background"
	card.icon:SetTexture(award.icon or ns.FALLBACK_ICON)
	card.icon:SetDesaturated(fallback)
	if fallback then
		card.border:SetVertexColor(0.5, 0.5, 0.5)
		card.title:SetTextColor(0.6, 0.6, 0.6)
	else
		card.border:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		card.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end
	card.title:SetText(award.title)
	card.text:SetText(award.text)
	local names = {}
	for _, p in ipairs(award.players) do
		table.insert(names, ns.ColorName(p.name, p.class))
	end
	card.players:SetText(table.concat(names, ", "))
	local playersWidth = math.floor(width * 0.42)
	card.players:SetWidth(playersWidth)
	local textWidth = width - 7 - 36 - 9 - playersWidth - 18
	card.title:SetWidth(textWidth)
	card.text:SetWidth(textWidth)

	if ns.settings.animations then
		card.appearAlpha:SetStartDelay((i - 1) * 0.05)
		card:SetAlpha(0)
		card.appear:SetScript("OnFinished", function() card:SetAlpha(1) end)
		card.appear:Play()
	else
		card:SetAlpha(1)
	end
end

local function create()
	win = W.Window("NeedySummary", "Needy - Run Awards", WIDTH, HEIGHT)
	win:SetPoint("CENTER", 240, 30)

	win.heading = W.Text(win, "GameFontNormalLarge")
	win.heading:SetPoint("TOPLEFT", 62, -30)
	win.heading:SetPoint("RIGHT", win, "RIGHT", -12, 0)
	win.heading:SetWordWrap(false)
	win.sub = W.Text(win, "GameFontHighlightSmall")
	win.sub:SetPoint("TOPLEFT", win.heading, "BOTTOMLEFT", 0, -4)

	local inset = W.Inset(win)
	inset:SetPoint("TOPLEFT", 8, -66)
	inset:SetPoint("BOTTOMRIGHT", -8, 32)

	win.scroll, win.list = W.ScrollArea(inset)
	win.scroll:SetPoint("TOPLEFT", 6, -6)
	win.scroll:SetPoint("BOTTOMRIGHT", -14, 6)

	win.empty = W.Text(inset, "GameFontDisable")
	win.empty:SetPoint("CENTER", 0, 0)
	win.empty:SetText("Nothing stood out this run, so no awards.")

	win.close = W.Button(win, CLOSE or "Close", 80, 22)
	win.close:SetPoint("BOTTOMRIGHT", -8, 6)
	win.close:SetScript("OnClick", function() win:Hide() end)
	win.history = W.Button(win, "History", 80, 22)
	win.history:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
	win.history:SetScript("OnClick", function() ns.HistoryWindow.Show(win.session) end)
	win.announce = W.Button(win, "Announce to group", 150, 22)
	win.announce:SetPoint("BOTTOMLEFT", 8, 6)
	win.announce:SetScript("OnClick", function()
		if win.session then SummaryWindow.Announce(win.session) end
	end)
	win.announce:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local ch = channelFor()
		GameTooltip:SetText("Announce", 1, 1, 1)
		GameTooltip:AddLine(ch and ("Posts the awards to " .. ch:lower():gsub("_", " ") .. " chat.")
			or "You're not in a group, so the awards print to your own chat window.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	win.announce:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
	win.sub:SetText(("%d items rolled, %d players, %d min%s"):format(resolved, players, mins,
		session.isTest and "  -  |cffff9933test run|r" or ""))

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

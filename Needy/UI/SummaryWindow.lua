-- The end-of-run report (an Awards page and a Stats page).
local _, ns = ...

local SummaryWindow = {}
ns.SummaryWindow = SummaryWindow

local W = ns.Widgets
local GOLD = W.GOLD

local WIDTH, HEIGHT = 510, 580
local CONTENT_WIDTH = WIDTH - 36 -- inside the inset, clear of the scroll thumb
local CARD_HEIGHT = 50
local CARD_GAP = 4

local TABS = {
	{ "awards", "Awards" },
	{ "stats", "Stats" },
}

local win
local cards = {}
local current

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

local function setCard(card, award, i, width, animate)
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

	card.appear:Stop() -- hiding the page mid-animation would otherwise leave the card invisible
	if animate and ns.settings.animations then
		card.appearAlpha:SetStartDelay((i - 1) * 0.05)
		card:SetAlpha(0)
		card.appear:SetScript("OnFinished", function() card:SetAlpha(1) end)
		card.appear:Play()
	else
		card:SetAlpha(1)
	end
end

local function createAwardsPage(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()

	page.scroll, page.list = W.ScrollArea(page)
	page.scroll:SetPoint("TOPLEFT", 6, -6)
	page.scroll:SetPoint("BOTTOMRIGHT", -14, 6)

	page.empty = W.Text(page, "GameFontDisable")
	page.empty:SetPoint("CENTER", 0, 0)
	page.empty:SetText("Nothing stood out this run, so no awards.")
	return page
end

local function refreshHeader()
	local session = win.session
	local totals, stats = ns.Titles.Totals(session)
	local players = 0
	for _ in pairs(stats) do players = players + 1 end
	local mins = math.max(1, math.floor(((session.endTime or time()) - session.startTime) / 60 + 0.5))
	win.heading:SetText(ns.HistoryWindow.SessionLabel(session))
	win.sub:SetText(("%d items rolled, %d players, %d min%s"):format(totals.items, players, mins,
		session.isTest and "  -  |cffff9933test run|r" or ""))
end

local function refreshAwards(animate)
	local page = win.awardsPage
	local awards = ns.Titles.Compute(win.session)
	for _, card in ipairs(cards) do card:Hide() end
	local width = page.scroll:GetWidth() or 0
	if width < 10 then width = CONTENT_WIDTH end
	local y = 0
	for i, a in ipairs(awards) do
		local card = cards[i]
		if not card then
			card = createCard(page.list)
			cards[i] = card
		end
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", 0, -y)
		card:SetPoint("RIGHT", page.list, "RIGHT", 0, 0)
		setCard(card, a, i, width, animate)
		card:Show()
		y = y + CARD_HEIGHT + CARD_GAP
	end
	page.list:SetHeight(math.max(1, y))
	page.scroll.UpdateThumb()
	page.empty:SetShown(#awards == 0)
end

-- animate: only when the report opens, not on every switch back to the Awards tab.
local function selectPage(key, animate)
	current = key
	win:SelectTab(key)
	win.awardsPage:SetShown(key == "awards")
	win.statsPage:SetShown(key == "stats")
	refreshHeader()
	if key == "awards" then
		refreshAwards(animate)
	else
		win.statsPage:SetSession(win.session)
	end
end

local function create()
	win = W.Window("NeedySummary", "Needy - Run Report", WIDTH, HEIGHT)
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

	win.awardsPage = createAwardsPage(inset)
	win.statsPage = ns.StatsPage.Create(inset, CONTENT_WIDTH)

	win.close = W.Button(win, CLOSE or "Close", 80, 22)
	win.close:SetPoint("BOTTOMRIGHT", -8, 6)
	win.close:SetScript("OnClick", function() win:Hide() end)
	win.history = W.Button(win, "History", 80, 22)
	win.history:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
	win.history:SetScript("OnClick", function() ns.HistoryWindow.Show(win.session) end)

	W.Tabs(win, "NeedySummary", TABS, selectPage)

	-- Keep the stats current when they're open during a run.
	ns.Listen("DROP_UPDATE", function()
		if win:IsShown() and current == "stats" and not win.session.endTime then
			refreshHeader()
			win.statsPage:SetSession(win.session)
		end
	end)
end

function SummaryWindow.Show(session)
	if not session then
		ns.Print("No run to report on yet.")
		return
	end
	if not win then create() end
	win.session = session
	win:Show()
	win:Raise()
	win.awardsPage.scroll:SetVerticalScroll(0)
	win.statsPage.scroll:SetVerticalScroll(0)
	selectPage("awards", true)
end

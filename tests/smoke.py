"""Load the addon in TOC order against a mocked WoW API and exercise the main paths: test mode end to end,
the roll log, settings, roster fitting, dragging the roll bars, and the awards maths."""
import pathlib, sys
from lupa import lua51

root = pathlib.Path(__file__).resolve().parents[1]
addon = root / "Needy"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)


MOCK = r"""
local printed = {}
__printed = printed
function print(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  printed[#printed + 1] = table.concat(t, " ")
end
date = os.date
time = os.time
local now = 1000
function GetTime() return now end
function __advance(s) now = now + s end

-- Timers run when __flush() is called, in due-time order.
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
function __flush(seconds)
  local stop = now + (seconds or 1000)
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > stop then break end
    table.remove(timers, 1)
    if t.at > now then now = t.at end
    t.fn()
  end
  if now < stop then now = stop end
end

-- Frames: any unknown method is a no-op returning nil; a few track state.
local Obj = {}
local function newObj(kind)
  local o = setmetatable({ __kind = kind, __shown = true, __scripts = {}, __text = "" }, Obj)
  return o
end
Obj.__index = function(self, key)
  local m = rawget(Obj, key)
  if m then return m end
  if type(key) == "string" and key:match("^Create") then
    return function() return newObj(key) end
  end
  if type(key) == "string" and key:match("^%u") then
    return function() return nil end
  end
end
function Obj:Show() self.__shown = true end
function Obj:Hide() self.__shown = false; local f = self.__scripts.OnHide; if f then f(self) end end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:IsShown() return self.__shown end
function Obj:IsVisible() return self.__shown end
function Obj:SetScript(name, fn) self.__scripts[name] = fn end
function Obj:HookScript(name, fn) self.__scripts[name] = fn end
function Obj:GetScript(name) return self.__scripts[name] end
function Obj:SetText(t) self.__text = t end
function Obj:GetText() return self.__text end
function Obj:CreateTexture() return newObj("Texture") end
function Obj:CreateFontString() return newObj("FontString") end
function Obj:GetNormalTexture() return newObj("Texture") end
function Obj:SetEnabled(v) self.__enabled = v end
function Obj:IsEnabled() return self.__enabled ~= false end
function Obj:GetHeight() return 0 end
function Obj:GetFrameLevel() return 1 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetScale() return 1 end
function Obj:GetStringHeight() return 12 end
function Obj:GetWidth() return 0 end
function Obj:GetChildren() return end
function Obj:GetVerticalScroll() return 0 end
function Obj:GetChecked() return false end
function Obj:Click() local f = self.__scripts.OnClick; if f then f(self, "LeftButton") end end
function Obj:CreateAnimationGroup() return newObj("AnimationGroup") end
function Obj:CreateAnimation() return newObj("Animation") end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end

__frames = {}
function CreateFrame(kind, name, parent, template)
  local o = newObj(kind)
  o.__template = template
  if template and template:find("ButtonFrameTemplate") then o.__shown = false end
  if name then _G[name] = o end
  __frames[#__frames + 1] = o
  return o
end
UIParent = newObj("Frame")
Minimap = newObj("Minimap")
function CreateFont(name) local f = newObj("Font"); _G[name] = f; return f end
function GetCursorPosition() return 0, 0 end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
SlashCmdList = {}
GameTooltip = newObj("GameTooltip")
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff" } end })
function UnitName() return "Tester" end
function UnitClass() return "Mage", "MAGE" end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "Nowhere", "none", 0, "", 5, 0, false, 0 end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
function geterrorhandler() return function(e) error(e, 0) end end
function hooksecurefunc(tbl, key, hook)
  local orig = tbl[key]
  tbl[key] = function(...) orig(...); hook(...) end
end
SOUNDKIT = { UI_LEGENDARY_LOOT_TOAST = 63971 }
__sounds = {}
function PlaySound(id, channel) __sounds[#__sounds + 1] = id end

-- The parts of DungeonJournal that Needy hooks.
local journal = {}
ForeverDungeonJournal_NS = journal
function journal.ShowItemFavouriteMenu()
  local menu = journal.favouriteContextMenu
  if not menu then
    menu = newObj("Frame")
    menu.button = newObj("Button")
    journal.favouriteContextMenu = menu
  end
  menu:Show()
end
function journal.HideItemFavouriteMenu() journal.favouriteContextMenu:Hide() end
function journal.UpdateFavouriteIndicator() end
journal.ORDER = { "Deep Cave" }
journal.DB = { ["Deep Cave"] = { bosses = {
  { name = "Recipes", recipeTab = true, loot = { { 4242, "Shiny Hat", "Head", 3 } } },
  { name = "Big Troll", loot = { { 4242, "Shiny Hat", "Head", 3 } } },
} } }
function RollOnLoot(id, t) __lastRoll = { id, t } end

local nextItem = 0
Item = { CreateFromItemID = function(_, id)
  return {
    IsItemEmpty = function() return false end,
    ContinueOnItemLoad = function(self, fn) C_Timer.After(0, fn) end,
    GetItemName = function() return "Item " .. id end,
    GetItemLink = function() return "|cffa335ee|Hitem:" .. id .. "::::::::|h[Item " .. id .. "]|h|r" end,
    GetItemQuality = function() return 4 end,
    GetItemIcon = function() return 134400 end,
  }
end }
C_Item = { GetItemInfoInstant = function(id) return id, "Armor", "Plate", "INVTYPE_CHEST", 134400 end }
"""

lua.execute(MOCK)
toc = (addon / "Needy.toc").read_text(encoding="utf-8")
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
ns = lua.eval("{}")
for f in files:
    path = addon / f.replace("\\", "/")
    chunk = lua.eval("function(src, name) return assert(loadstring(src, name)) end")(path.read_text(encoding="utf-8"), "@" + f)
    chunk("Needy", ns)

run = lua.eval("""function(ns)
  -- Fire ADDON_LOADED through the event frame (the first frame Init.lua created).
  local ef = __frames[1]
  ef.__scripts.OnEvent(ef, "ADDON_LOADED", "Needy")
  ef.__scripts.OnEvent(ef, "PLAYER_ENTERING_WORLD")
  assert(ns.settings and ns.settings.replaceBlizzard == true, "settings loaded")

  ef.__scripts.OnEvent(ef, "PLAYER_LOGIN")
  -- Live test: three bars appear, we click Need on the first, everything resolves.
  SlashCmdList.NEEDY("test")
  __flush(0.5)
  local rolls = 0
  for id, roll in pairs(ns.LootSource.All()) do rolls = rolls + 1 end
  assert(rolls == 3, "three fake rolls, got " .. rolls)
  local firstID
  for id, roll in pairs(ns.LootSource.All()) do
    if roll.canNeed then firstID = id; ns.LootSource.Choose(roll, "need") break end
  end
  __flush(40)
  local s = ns.Tracker.testSession
  assert(s and #s.drops == 3, "three drops recorded")
  assert(_G.NeedyLogTab:IsShown(), "roll log tab shows during a run")
  assert(not _G.NeedyLog:IsShown(), "roll log starts tucked away")
  ns.RollLog.Toggle()
  assert(_G.NeedyLog:IsShown(), "clicking the tab opens the log")
  -- Bars animate their results: run their OnUpdates past the reveal.
  for _, f in ipairs(__frames) do
    local u = f.__scripts.OnUpdate
    if u and f.roll then u(f, 0.1) end
  end
  SlashCmdList.NEEDY("log")
  assert(not _G.NeedyLogTab:IsShown(), "/needy log hides it")
  SlashCmdList.NEEDY("log")
  for _, d in ipairs(s.drops) do
    assert(d.winner or d.allPassed, "every test drop resolved")
  end
  if firstID then
    local d
    for _, x in ipairs(s.drops) do if x.key == "test:" .. firstID then d = x end end
    assert(d.rolls.Tester.choice == "need", "our choice recorded")
    assert(type(d.rolls.Tester.roll) == "number", "we got a roll number")
  end
  SlashCmdList.NEEDY("test end")
  assert(ns.Tracker.testSession == nil, "test session finished")
  assert(not _G.NeedyLogTab:IsShown(), "roll log hides when the run ends")
  assert(_G.NeedySummary and _G.NeedySummary:IsShown(), "summary window shown")

  -- Simulated run: awards include the obvious ones.
  _G.NeedySummary:Hide()
  math.randomseed(7)
  SlashCmdList.NEEDY("test run")
  __flush(1)
  local last = ns.Tracker.lastTest
  assert(last and #last.drops == 12, "simulated run has 12 drops")
  local awards = ns.Titles.Compute(last)
  local keys = {}
  for _, a in ipairs(awards) do keys[a.key] = a end
  assert(keys.hoarder or keys.golden, "the hoarder gets Loot Hoarder or Golden Hands")
  assert(keys.saint, "The Saint awarded")
  SlashCmdList.NEEDY("summary")
  -- Awards and Stats tabs of the Run Report.
  local report = _G.NeedySummary
  assert(report.awardsPage:IsShown() and not report.statsPage:IsShown(), "report opens on Awards")
  _G.NeedySummaryTab2:Click()
  assert(report.statsPage:IsShown() and not report.awardsPage:IsShown(), "Stats tab shows the stats")
  assert(report.statsPage.tiles.items.value:GetText() == "12", "stats count the run's 12 items")
  assert(#report.statsPage.rows >= 6, "a line for each of the six players")
  _G.NeedySummaryTab1:Click()
  assert(report.awardsPage:IsShown() and not report.statsPage:IsShown(), "Awards tab switches back")
  SlashCmdList.NEEDY("history")
  SlashCmdList.NEEDY("options")
  assert(_G.NeedySettings:IsShown(), "settings window opens")
  assert(_G.NeedyMinimapButton:IsShown(), "minimap icon shown")
  SlashCmdList.NEEDY("minimap")
  assert(not _G.NeedyMinimapButton:IsShown(), "/needy minimap hides it")
  SlashCmdList.NEEDY("help")

  -- Roster fitting: a fake fontstring whose width is 6px per visible character.
  local fs = setmetatable({}, { __index = function(t, k)
    if k == "SetText" then return function(self, txt) self.txt = txt end end
    if k == "GetUnboundedStringWidth" then return function(self)
      local plain = self.txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", "XX")
      return #plain * 6
    end end
  end })
  local raid = { rolls = {} }
  for i = 1, 20 do
    raid.rolls["Player" .. i] = { choice = (i <= 6 and "need") or (i <= 12 and "greed") or (i <= 18 and "pass") or "none", class = "MAGE" }
  end
  local wide = ns.Widgets.FitRoster(fs, raid, 100000)
  assert(wide:find("Player18"), "wide line lists everyone")
  local narrow = ns.Widgets.FitRoster(fs, raid, 120)
  assert(not narrow:find("Player"), "narrow line falls back to counts: " .. narrow)
  local mid = ns.Widgets.FitRoster(fs, raid, 600)
  assert(mid:find("Player") and mid:find("+"), "medium line keeps top names with +N: " .. mid)

  -- Unlock, drag the handle, centre it, lock.
  SlashCmdList.NEEDY("unlock")
  local a = _G.NeedyAnchor
  a.__scripts.OnMouseDown(a, "LeftButton")
  a.__scripts.OnUpdate(a, 0.1)
  a.__scripts.OnMouseUp(a)
  assert(ns.settings.position and ns.settings.position[1] == "CENTER", "drag saves a centre-relative position")
  a.centre:Click()
  a.done:Click()
  assert(ns.settings.locked, "Done locks the bars")

  -- Titles maths on a hand-made session.
  local hand = { drops = {
    { key = "a", winner = "A", rolls = { A = { choice = "need", roll = 90 }, B = { choice = "need", roll = 80 }, C = { choice = "pass" } } },
    { key = "b", winner = "A", rolls = { A = { choice = "need", roll = 70 }, B = { choice = "need", roll = 60 }, C = { choice = "pass" } } },
    { key = "c", winner = "B", rolls = { A = { choice = "greed", roll = 99 }, B = { choice = "need", roll = 1 }, C = { choice = "pass" } } },
    { key = "d", rolls = { A = { choice = "none" } } }, -- unresolved: ignored
  } }
  local st = ns.Titles.Stats(hand)
  assert(st.A.needs == 2 and st.A.wins == 2 and st.A.losses == 1, "A stats")
  assert(st.B.losses == 2 and st.B.seconds == 2, "B lost twice, second twice")
  assert(st.C.passes == 3, "C passed 3 times")
  local totals = ns.Titles.Totals(hand)
  assert(totals.items == 3 and totals.unfinished == 1, "totals count finished drops only")
  assert(totals.needWins == 3 and totals.greedWins == 0 and totals.allPassed == 0, "how the items were won")
  assert(totals.rolls == 6 and totals.high == 99 and totals.low == 1, "roll count and extremes")
  assert(math.abs(totals.average - 400 / 6) < 0.001, "average roll")

  -- The table: sorted by wins, blanks for someone who never rolled, and live while the run goes on.
  hand.startTime, hand.instanceName = time(), "Hand-made"
  ns.SummaryWindow.Show(hand)
  _G.NeedySummaryTab2:Click()
  local page = _G.NeedySummary.statsPage
  local function cells(i)
    local t = {}
    for c, cell in ipairs(page.rows[i].cells) do t[c] = cell:GetText() end
    return table.concat(t, ",")
  end
  assert(cells(1) == "2,+1.0,2,1,0,0,86,99,70", "A's line: " .. cells(1))
  assert(cells(2) == "1,-1.0,3,0,0,0,47,80,1", "B's line: " .. cells(2))
  assert(cells(3) == "0,-,0,0,3,0,-,-,-", "C's line: " .. cells(3))
  for i = 4, #page.rows do assert(not page.rows[i]:IsShown(), "leftover lines are hidden") end
  assert(page.note:GetText():find("1 unfinished roll"), "unfinished roll noted")
  hand.drops[4].allPassed = true
  ns.Fire("DROP_UPDATE", { key = "unrelated" })
  assert(page.tiles.allPassed.value:GetText() == "1", "stats update during a run")
  assert(page.note:GetText() == "", "note clears when the roll finishes")
  hand.drops[4].allPassed = nil

  -- A short run: B's roll of 1 is the only thing that stands out (B also needed most, but gets one title).
  local small = ns.Titles.Compute(hand)
  assert(#small == 1 and small[1].key == "critfail" and small[1].players[1].name == "B", "small run: just Critical Fail")

  -- A longer run with clear standouts: A needs and wins everything, B rolls low and wins nothing,
  -- C passes on everything, D lets most rolls time out.
  local run = { drops = {} }
  for i = 1, 6 do
    run.drops[i] = { key = "r" .. i, winner = "A", rolls = {
      A = { choice = "need", roll = 60 + i }, B = { choice = "greed", roll = 10 + i },
      C = { choice = "pass" }, D = { choice = i <= 4 and "none" or "pass" },
    } }
  end
  local aw = {}
  local list = ns.Titles.Compute(run)
  for _, a in ipairs(list) do aw[a.key] = a end
  assert(#list == 4, "one title each for A, B, C and D, got " .. #list)
  local aTitle = aw.hoarder or aw.golden -- A needed and won everything: either title fits
  assert(aTitle and aTitle.players[1].name == "A", "A gets Loot Hoarder or Golden Hands")
  assert(not (aw.hoarder and aw.golden), "A doesn't get both (one title each)")
  local bTitle = aw.unlucky or aw.bridesmaid -- B lost every roll, always to A: either title fits
  assert(bTitle and bTitle.players[1].name == "B" and not (aw.unlucky and aw.bridesmaid), "B gets Unlucky or Bridesmaid")
  assert(aw.saint and aw.saint.players[1].name == "C", "C is The Saint")
  assert(aw.asleep and aw.asleep.players[1].name == "D", "D is Asleep at the Wheel")

  -- A tie for the lead earns nothing.
  local tie = { drops = {} }
  for i = 1, 4 do
    tie.drops[i] = { key = "t" .. i, winner = (i % 2 == 0) and "A" or "B", rolls = {
      A = { choice = "need", roll = 50 + i }, B = { choice = "need", roll = 40 + i },
    } }
  end
  for _, a in ipairs(ns.Titles.Compute(tie)) do
    assert(a.key ~= "hoarder", "tied needs give no Loot Hoarder")
  end
  -- Luck: off-spec and greed have no chance against a main-spec need.
  local spec = { drops = { { key = "s", winner = "M", rolls = {
    M = { choice = "need", roll = 5 }, N = { choice = "need", roll = 4 },
    O = { choice = "need", roll = 99, offSpec = true }, G = { choice = "greed", roll = 100 },
  } } } }
  local sst = ns.Titles.Stats(spec)
  assert(ns.Titles.Luck(sst.M) == 0.5 and ns.Titles.Luck(sst.N) == -0.5, "main-spec needs split the odds")
  assert(ns.Titles.Luck(sst.O) == nil and ns.Titles.Luck(sst.G) == nil, "no chance means no luck either way")

  -- Wishlist: added from DungeonJournal's menu, marked on its rows, lights up the bar with one fanfare.
  local journal = ForeverDungeonJournal_NS
  local row = CreateFrame("Button")
  row.icon = row:CreateTexture()
  journal.UpdateFavouriteIndicator(row, 4242)
  assert(not row.needyMark:IsShown(), "no mark before it's on the list")
  journal.ShowItemFavouriteMenu(row, { 4242, "Shiny Hat" }, "Dungeon", "Boss")
  local menu = journal.favouriteContextMenu
  local entry
  for _, f in ipairs(__frames) do
    if f.mark and f.text and f.text:GetText() == "Add to Needy Wishlist" then entry = f end
  end
  assert(entry, "menu offers the wishlist")
  entry:Click()
  assert(ns.Wishlist.Has(4242) and row.needyMark:IsShown(), "item added and marked")
  assert(not menu:IsShown(), "menu closes")
  journal.ShowItemFavouriteMenu(row, { 4242, "Shiny Hat" }, "Dungeon", "Boss")
  assert(entry.text:GetText() == "Remove from Needy Wishlist", "menu offers removal")
  journal.ShowItemFavouriteMenu(row, { 4242, "Shiny Hat" }, "Dungeon", nil, { id = 1 })
  assert(not entry:IsShown(), "not offered on quest rewards")

  local function barFor(id)
    for _, f in ipairs(__frames) do
      if f.need and type(f.roll) == "table" and f.roll.id == id then return f end
    end
  end
  local function roll(id, item)
    ns.Fire("ROLL_START", { id = id, rollTime = 60000, endsAt = GetTime() + 60, isTest = true, canNeed = true,
      canGreed = true, name = "Item", quality = 3, link = "|Hitem:" .. item .. "::::|h[Item]|h" })
    return barFor(id)
  end
  local before = #__sounds
  local plain = roll(9001, 42420)
  assert(not plain.wished and #__sounds == before, "other items are left alone")
  local wanted = roll(9002, 4242)
  assert(wanted.wished and wanted.wishGlow:IsShown() and #__sounds == before + 1, "wishlist drop glows and plays")
  assert(wanted.status:GetText():find("Wishlist!"), "and says so")
  roll(9003, 4242)
  assert(#__sounds == before + 1, "items dropping together share a fanfare")
  ns.Wishlist.Toggle(4242)
  assert(not wanted.wished and not wanted.wishGlow:IsShown() and not row.needyMark:IsShown(), "removal undoes it all")

  __advance(5)
  ns.Wishlist.Toggle(9372, "Combined Sword", { 11086, 9379 })
  local piece = roll(9004, 9379)
  assert(piece.wished and #__sounds == before + 2, "a piece of a combined item counts")
  ns.RollFrame.Release(piece)
  assert(not piece.wished, "a reused bar starts plain")

  ns.Wishlist.Clear()
  SlashCmdList.NEEDY("test wish")
  __flush(0.5)
  local glowing = false
  for _, r in pairs(ns.LootSource.All()) do
    if r.wishlisted and barFor(r.id).wished then glowing = true end
  end
  assert(glowing, "/needy test wish works with an empty list")
  -- The Wishlist tab: lists what's tracked, where it drops, and takes items off.
  ns.Wishlist.Toggle(4242, "Shiny Hat")
  SlashCmdList.NEEDY("wishlist")
  local listed
  for _, f in ipairs(__frames) do
    if f.remove and f.itemID == 4242 then listed = f end
  end
  assert(listed and listed:IsShown(), "the tab lists the tracked item")
  assert(listed.where:GetText() == "Deep Cave - Big Troll", "with its boss: " .. tostring(listed.where:GetText()))

  -- History tags the drops that are on the list, and only those.
  local past = { startTime = time(), endTime = time(), drops = {
    { key = "w", link = "|Hitem:4242::::|h[Shiny Hat]|h", rolls = {}, allPassed = true },
    { key = "o", link = "|Hitem:777::::|h[Old Boot]|h", rolls = {}, allPassed = true },
  } }
  ns.DB.SaveSession(past)
  ns.HistoryWindow.Show(past)
  local tagged, untagged
  for _, f in ipairs(__frames) do
    if f.tag and f.drop == past.drops[1] then tagged = f end
    if f.tag and f.drop == past.drops[2] then untagged = f end
  end
  assert(tagged.tag:IsShown() and not untagged.tag:IsShown(), "history tags wishlist drops only")
  listed.remove:Click()
  assert(not ns.Wishlist.Has(4242) and not listed:IsShown(), "the X takes it off the list")
  assert(not tagged.tag:IsShown(), "and off the history tag")
  return #awards
end""")
try:
    n = run(ns)
    print(f"OK   smoke test ({n} awards in the simulated run)")
except Exception as e:  # noqa: BLE001
    print("FAIL smoke test:", e)
    sys.exit(1)
print("Smoke test passed")

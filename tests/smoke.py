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
function IsInGroup() return false end
function IsInRaid() return false end
function InCombatLockdown() return false end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
function geterrorhandler() return function(e) error(e, 0) end end
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
  assert(keys.hoarder, "Loot Hoarder awarded")
  assert(keys.saint, "The Saint awarded")
  local lines = ns.SummaryWindow.AnnounceLines(last)
  assert(#lines == #awards + 1, "one chat line per award plus header")
  SlashCmdList.NEEDY("summary")
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
  local aw = {}
  for _, a in ipairs(ns.Titles.Compute(hand)) do aw[a.key] = a end
  assert(aw.hoarder.players[1].name == "B" and #aw.hoarder.players == 1, "B needed most")
  assert(aw.golden.players[1].name == "A", "A won most")
  assert(aw.saint.players[1].name == "C", "C is the saint")
  assert(aw.low.title == "Critical Fail", "a roll of 1 is a Critical Fail")
  assert(aw.bridesmaid.players[1].name == "B", "B is the bridesmaid")
  return #awards
end""")
try:
    n = run(ns)
    print(f"OK   smoke test ({n} awards in the simulated run)")
except Exception as e:  # noqa: BLE001
    print("FAIL smoke test:", e)
    sys.exit(1)
print("Smoke test passed")

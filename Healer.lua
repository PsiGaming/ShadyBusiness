-- Shady Business: healer check (only you see the result).
-- Members assigned the Healer role, level 12 and up:
--   * a class that can't heal (anything but Druid, Paladin, Priest, Shaman) -> alert
--   * otherwise their gear is inspected and judged by level brackets (decided 2026-11-23). "Pieces" are items with
--     any healer stat (Intellect, Spirit, MP5, spell power, healing); healing power = spell power + healing.
--     Levels 12-29: healing power 20+ or 4+ pieces -> checks out; exactly 3 pieces -> "meets the bare minimum";
--     fewer -> alert. Levels 30+: 3+ pieces and at least 30 / 40 / 50 / 60 healing power (by 10-level bracket)
--     -> checks out, otherwise alert. A failing healer below level 20 ("still gearing") also gets a "Note:" line
--     saying characters that low aren't expected to be well geared.
-- Inspected gear arrives in pieces (PsiLab 2026-11-22: 2-4 items at INSPECT_READY, all a second later), so the
-- gear is read again every second until the item count stops changing and every item's data is loaded.
-- Re-checks (people often change gear after joining, just before the run; decided 2026-11-22): when the healer's
-- equipment changes (UNIT_INVENTORY_CHANGED / UNIT_MODEL_CHANGED, which Forever's own Inspect window uses to
-- refresh another player's gear: Blizzard_InspectUI/Mainline/InspectPaperDollFrame.lua), on entering a dungeon or
-- raid, and on a ready check; never in combat. A re-check only speaks when the verdict changes: failing -> alert,
-- otherwise a chat line.

local _, SB = ...

local RED, ORANGE, YELLOW, GREEN, GREY = "|cffff2020", "|cffff8000", "|cffffd100", "|cff20ff20", "|cff9d9d9d"

-- Talents are only reported, never judged (decided 2026-11-23). The spec (tree with the most points) is coloured by
-- tree (decided 2026-11-25): Holy and Discipline yellow, Restoration green, any other tree red. Healing trees by
-- position (tree names and order from PsiLab's talent scans 2026-11-23: Druid Balance / Feral Combat / Restoration,
-- Paladin Holy / Protection / Retribution, Priest Discipline / Holy / Shadow Magic, Shaman Elemental Combat /
-- Enhancement / Restoration).
-- Inspected talents have no unit argument: they belong to whoever was inspected last, so they are read at
-- INSPECT_READY, before another inspect can replace them.
local HEALING_TREES = {
  DRUID = { [3] = GREEN },
  PALADIN = { [1] = YELLOW },
  PRIEST = { [1] = YELLOW, [2] = YELLOW },
  SHAMAN = { [3] = GREEN },
}
-- Short tree names in the talent list and the spec (decided 2026-11-25), by the tree name the game returns; other
-- trees keep their full name.
local SHORT_TREE = { Restoration = "Resto", Retribution = "Ret", Protection = "Prot", ["Feral Combat"] = "Feral" }
local INSPECT_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)
  or -1

local MIN_LEVEL = 12  -- below this, no checks at all (decided 2026-11-22)
local LOW_LEVEL = 20  -- below this ("still gearing"), a failed gear check comes with a "very low level" note
local HEALING_CLASSES = { DRUID = true, PALADIN = true, PRIEST = true, SHAMAN = true }

-- The bracket with the highest fromLevel at or below the healer's level applies (level cap 60).
-- "+healing" items (which also carry "+damage" at about 3:1, PsiLab 2026-11-22) and spell power items ("damage and
-- healing") both raise healing. healingEnough: that much healing power checks out on its own; otherwise minPieces
-- items with healer stats are the bare minimum and more check out. minHealing (30+): minPieces and that much
-- healing power are both required, no bare minimum.
-- PsiLab 2026-11-22 (TacoTip inspects of healer classes): healer-geared players had 6-14 such items and, at levels
-- 31-36, 34-209 healing power; Strength Paladins and Enhancement-looking Shamans at 31-51 had 0-4.
local BRACKETS = {
  { fromLevel = 12, healingEnough = 20, minPieces = 3 },
  { fromLevel = 30, minHealing = 30, minPieces = 3 },
  { fromLevel = 40, minHealing = 40, minPieces = 3 },
  { fromLevel = 50, minHealing = 50, minPieces = 3 },
  { fromLevel = 60, minHealing = 60, minPieces = 3 },
}

local INSPECT_EVERY = 4    -- seconds between inspect attempts until one works (decided: every 3 to 5 s)
local READ_EVERY = 1       -- seconds between gear reads after an inspect reply
local MIN_READS = 3        -- judge no earlier than 2 s after the reply
local MAX_READS = 10       -- then give up on this reply and inspect again
local GEAR_SETTLE = 5      -- seconds after the last equipment change before re-checking (several pieces in a row)
local ZONE_IN_DELAY = 3    -- seconds after entering a dungeon or raid

-- GUID -> { classChecked, classShady, verdict ("bad" / "fine"), recheckAt, reading }
local healers = {}
local rotation = 0

local function Bracket(level)
  local best
  for _, b in ipairs(BRACKETS) do
    if level >= b.fromLevel and (not best or b.fromLevel > best.fromLevel) then best = b end
  end
  return best
end

local function UnitForGUID(guid)
  for _, unit in ipairs(SB:GroupUnits()) do
    local g = UnitGUID(unit)
    if not SB.IsSecret(g) and g == guid then return unit end
  end
end

local function Number(v)
  v = SB.Plain(v)
  return type(v) == "number" and v or 0
end

-- The healer stats on the unit's (inspected) gear. Stat names as Forever returns them (PsiLab 2026-11-22, 402
-- items): spell power and "+healing" are separate stats.
local STATS = {
  intellect = "ITEM_MOD_INTELLECT_SHORT",
  spirit = "ITEM_MOD_SPIRIT_SHORT",
  mp5 = "ITEM_MOD_MANA_REGENERATION_SHORT",
  spellPower = "ITEM_MOD_SPELL_POWER_SHORT",
  healing = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
}

-- GetItemStats returns nothing for an item whose data the game hasn't loaded yet (PsiLab 2026-11-22: 9 of 11 of a
-- character's own items at login), so unloaded items are requested and counted in g.loading; the gear is only
-- judged once that is 0. g.pieces counts the items with at least one healer stat.
local function ReadGear(unit)
  local g = { items = 0, loading = 0, pieces = 0 }
  for key in pairs(STATS) do g[key] = 0 end
  for slot = 1, 19 do
    local link = SB.Plain(GetInventoryItemLink(unit, slot))
    if type(link) == "string" then
      g.items = g.items + 1
      if not C_Item.IsItemDataCachedByID(link) then
        g.loading = g.loading + 1
        C_Item.RequestLoadItemDataByID(link)
      else
        local stats = C_Item.GetItemStats(link)
        if type(stats) == "table" and not SB.IsSecret(stats) then
          local healerPiece = false
          for key, statName in pairs(STATS) do
            local value = Number(stats[statName])
            g[key] = g[key] + value
            if value > 0 then healerPiece = true end
          end
          if healerPiece then g.pieces = g.pieces + 1 end
        end
      end
    end
  end
  return g
end

-- Spell power counts fully for healing ("increases damage and healing done by magical spells"); healing items carry
-- "+healing" instead (seen in game, 2026-11-23). Their sum is the healer's real healing power, the only one reported.
local function HealingBonus(g)
  return g.spellPower + g.healing
end

local function StatsText(g)
  return string.format("%d Intellect, %d Spirit, %d MP5, %d healing power", g.intellect, g.spirit, g.mp5,
    HealingBonus(g))
end

-- "3 of 9 items have healer stats"
local function GearText(g)
  return string.format("%d of %s %s healer stats", g.pieces, g.items == 1 and "1 item" or (g.items .. " items"),
    g.pieces == 1 and "has" or "have")
end

-- The last inspected player's talent trees: { { position, name, points }, ... }, or nil if unreadable.
local function ReadTalents()
  if not C_Traits then return nil end
  local info = SB.Plain(C_Traits.GetConfigInfo(INSPECT_CONFIG_ID))
  local treeID = type(info) == "table" and type(info.treeIDs) == "table" and SB.Plain(info.treeIDs[1])
  if type(treeID) ~= "number" then return nil end
  local groups = SB.Plain(C_Traits.GetGroupDisplayInfoByTreeID(treeID))
  if type(groups) ~= "table" then return nil end
  local trees, byGroup, groupIDs = {}, {}, {}
  for _, g in ipairs(groups) do
    local groupID = type(g) == "table" and SB.Plain(g.groupID)
    if type(groupID) == "number" then
      local tree = { position = Number(g.orderIndex) + 1, name = SB.Plain(g.displayName) or "?", points = 0 }
      trees[#trees + 1] = tree
      byGroup[groupID] = tree
      groupIDs[#groupIDs + 1] = groupID
    end
  end
  -- Listed in no particular order, and trees with 0 points are missing (PsiLab 2026-11-22).
  local spent = SB.Plain(C_Traits.GetGroupCurrencyInfo(INSPECT_CONFIG_ID, groupIDs))
  for _, s in ipairs(type(spent) == "table" and spent or {}) do
    local tree = type(s) == "table" and byGroup[SB.Plain(s.traitNodeGroupID)]
    local currency = tree and type(s.currencyInfos) == "table" and s.currencyInfos[1]
    if type(currency) == "table" then tree.points = tree.points + Number(currency.spent) end
  end
  return #trees > 0 and trees or nil
end

-- A detail line's grey label, e.g. "Gear: ".
local function Label(text)
  return GREY .. text .. ":|r "
end

-- "Talents: Ret 31, Prot 6 (Spec: Ret)" with only the spec name coloured; a tie lists every
-- top tree ("Spec: Holy/Retribution"), each in its own colour. nil when the talents couldn't be read.
local function TalentsText(trees, classFile)
  if not trees then return nil end
  local used = {}
  for _, tree in ipairs(trees) do
    if tree.points > 0 then used[#used + 1] = tree end
  end
  if #used == 0 then return Label("Talents") .. "none yet" end
  table.sort(used, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    return a.position < b.position
  end)
  local parts, top = {}, {}
  local healingTrees = HEALING_TREES[classFile] or {}
  for _, tree in ipairs(used) do
    local name = SHORT_TREE[tree.name] or tree.name
    parts[#parts + 1] = name .. " " .. tree.points
    if tree.points == used[1].points then
      top[#top + 1] = (healingTrees[tree.position] or RED) .. name .. "|r"
    end
  end
  return string.format("%s%s (Spec: %s)", Label("Talents"), table.concat(parts, ", "), table.concat(top, "/"))
end

-- Detail lines go under the header line, indented and without the "Shady Business:" prefix.
local function PrintDetails(lines)
  for _, line in ipairs(lines) do print("  " .. line) end
end

local function Describe(unit)
  local className = SB.Plain(UnitClass(unit)) or "?"
  return string.format("%s (Healer, level %d %s)", SB.Name(unit), Number(UnitLevel(unit)), className)
end

-- "fine", "minimum" (bare minimum) or "bad".
local function Verdict(g, b)
  if b.minHealing then
    return (g.pieces >= b.minPieces and HealingBonus(g) >= b.minHealing) and "fine" or "bad"
  end
  if HealingBonus(g) >= b.healingEnough or g.pieces > b.minPieces then return "fine" end
  return g.pieces == b.minPieces and "minimum" or "bad"
end

local VERDICT_TEXT = { fine = "checks out", minimum = "meets the bare minimum", bad = "doesn't look geared to heal" }
local VERDICT_COLOR = { fine = GREEN, minimum = ORANGE, bad = RED }

-- First check: always says the result. Re-check: silent unless the verdict changed. "bad" -> alert, otherwise a chat
-- line; either way the details follow as chat lines (decided 2026-11-25), so the on-screen alert is just the header:
--   Shady Business: Bonkadin (Healer, level 38 Paladin): doesn't look geared to heal
--     Gear: 2 of 17 items have healer stats
--     Stats: 14 Intellect, 6 Spirit, 0 MP5, 12 healing power
--     Talents: Ret 24, Holy 5 (Spec: Ret)
--     Shady's bare minimum for level 30+: 3 healer pieces and 30 healing power   (only on a failure from level 30)
local function Judge(unit, h, g)
  local level = Number(UnitLevel(unit))
  local b = Bracket(level)
  if not b then return end
  local verdict = Verdict(g, b)
  local previous = h.verdict
  h.verdict = verdict
  if previous == verdict then return end
  local header = string.format("%s: %s%s%s|r", Describe(unit), previous and "now " or "", VERDICT_COLOR[verdict],
    VERDICT_TEXT[verdict])
  local lines = { Label("Gear") .. GearText(g), Label("Stats") .. StatsText(g) }
  lines[#lines + 1] = TalentsText(h.talents, SB.Plain(select(2, UnitClass(unit))))
  if verdict == "bad" and b.minHealing then
    lines[#lines + 1] = string.format("%s%d healer pieces and %d healing power",
      Label("Shady's bare minimum for level " .. b.fromLevel .. "+"), b.minPieces, b.minHealing)
  end
  if verdict == "bad" and level < LOW_LEVEL then
    lines[#lines + 1] = string.format("%sonly level %d; characters this low usually haven't found much healing gear yet.",
      Label("Note"), level)
  end
  if verdict == "bad" then SB:Alert(header) else SB:Print(header) end
  PrintDetails(lines)
end

-- Finds the members assigned the Healer role and checks their class; forgets members who left or lost the role.
local function Scan()
  if not SB:Watching() then
    wipe(healers)
    return
  end
  local seen = {}
  for _, unit in ipairs(SB:GroupUnits()) do
    local guid = SB.Plain(UnitGUID(unit))
    if guid and SB.Plain(UnitGroupRolesAssigned(unit)) == "HEALER" then
      seen[guid] = true
      local h = healers[guid] or {}
      healers[guid] = h
      if Number(UnitLevel(unit)) >= MIN_LEVEL and not h.classChecked then
        h.classChecked = true
        local _, classFile = UnitClass(unit)
        classFile = SB.Plain(classFile)
        if classFile and not HEALING_CLASSES[classFile] then
          h.classShady = true  -- no gear check needed
          SB:Alert(string.format("%s: %snot a healing class|r", Describe(unit), RED))
        end
      end
    end
  end
  for guid in pairs(healers) do
    if not seen[guid] then healers[guid] = nil end
  end
end

-- A healer's gear needs checking: never checked yet, or a re-check is due.
local function Due(h)
  if not h.classChecked or h.classShady then return false end
  return h.verdict == nil or (h.recheckAt ~= nil and GetTime() >= h.recheckAt)
end

local function RecheckAll(delay)
  for _, h in pairs(healers) do
    if h.verdict then h.recheckAt = GetTime() + delay end
  end
end

-- Every few seconds: inspect the next healer whose gear is due. Skipped in combat (gear can't change then) and while
-- Blizzard's Inspect window is open, so it doesn't replace the player you are looking at.
local function InspectNext()
  if not SB:Watching() or InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then return end
  local candidates = {}
  for guid, h in pairs(healers) do
    local unit = UnitForGUID(guid)
    if unit and Due(h) and not h.reading and SB.Plain(UnitIsConnected(unit)) and SB.Plain(CanInspect(unit)) then
      candidates[#candidates + 1] = unit
    end
  end
  if #candidates == 0 then return end
  table.sort(candidates)
  rotation = rotation % #candidates + 1
  NotifyInspect(candidates[rotation])
end

-- Any inspect reply for a healer that is due counts, whoever asked for it (other addons inspect too).
local function OnInspectReady(guid)
  if SB.IsSecret(guid) then return end
  local h = healers[guid]
  if not h or h.reading or not Due(h) then return end
  h.reading = true
  h.talents = ReadTalents()
  local started = GetTime()
  local reads, lastCount = 0, -1
  local function Step()
    local unit = UnitForGUID(guid)
    if healers[guid] ~= h or not unit then
      h.reading = false
      return
    end
    local g = ReadGear(unit)
    reads = reads + 1
    if reads >= MIN_READS and g.items > 0 and g.items == lastCount and g.loading == 0 then
      h.reading = false
      -- A gear change during the read keeps its own (later) re-check.
      if h.recheckAt and h.recheckAt <= started then h.recheckAt = nil end
      Judge(unit, h, g)
      return
    end
    lastCount = g.items
    if reads >= MAX_READS then
      h.reading = false  -- try again with a new inspect
      return
    end
    C_Timer.After(READ_EVERY, function() SB:Call("healer gear", Step) end)
  end
  Step()
end

-- The healer's equipment changed: re-check once they've stopped swapping.
local function OnGearChanged(unit)
  if SB.IsSecret(unit) or type(unit) ~= "string" then return end
  local guid = SB.Plain(UnitGUID(unit))
  local h = guid and healers[guid]
  if h and h.verdict then h.recheckAt = GetTime() + GEAR_SETTLE end
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
    "ROLE_CHANGED_INFORM", "UNIT_LEVEL" }) do
  SB:On(event, Scan)
end
SB:On("PLAYER_ENTERING_WORLD", function()
  if IsInInstance() then RecheckAll(ZONE_IN_DELAY) end
end)
SB:On("READY_CHECK", function() RecheckAll(0) end)
SB:On("UNIT_INVENTORY_CHANGED", OnGearChanged)
SB:On("UNIT_MODEL_CHANGED", OnGearChanged)
SB:On("INSPECT_READY", OnInspectReady)
C_Timer.NewTicker(INSPECT_EVERY, function()
  if SB.db then SB:Call("inspect", InspectNext) end
end)

function SB:HealerStatus()
  local any = false
  for guid, h in pairs(healers) do
    any = true
    local unit = UnitForGUID(guid)
    local state
    if h.classShady then state = "not a healing class"
    elseif h.reading then state = "reading gear"
    elseif not h.classChecked then state = "below level " .. MIN_LEVEL
    elseif h.verdict and Due(h) then state = VERDICT_TEXT[h.verdict] .. ", re-check due"
    elseif h.verdict then state = VERDICT_TEXT[h.verdict]
    else state = "waiting for inspect" end
    self:Print(string.format("healer %s: %s", unit and SB.Name(unit) or guid, state))
  end
  if not any then self:Print("no member is assigned the Healer role.") end
end

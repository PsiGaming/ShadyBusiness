-- Shady Business: loot rule alerts and leader changes (only you see them in test.00).
-- Every change of the loot method made by someone else, and, on joining, a group already set to Free for All,
-- Master Looter or Round Robin. Forever source: C_PartyInfo.GetLootMethod and PARTY_LOOT_METHOD_CHANGED
-- (PartyInfoDocumentation.lua), Enum.LootMethod (LootConstantsDocumentation.lua).

local _, SB = ...

local M = Enum and Enum.LootMethod or {}
local NAMES = {
  [M.Freeforall or 0] = "Free for All",
  [M.Roundrobin or 1] = "Round Robin",
  [M.Masterlooter or 2] = "Master Looter",
  [M.Group or 3] = "Group Loot",
  [M.Needbeforegreed or 4] = "Need Before Greed",
  [M.Personal or 5] = "Personal Loot",
}
local RISKY = { [M.Freeforall or 0] = true, [M.Roundrobin or 1] = true, [M.Masterlooter or 2] = true }

-- Right after joining, the group's real setting can still be on its way; changes this soon count as "the
-- setting when you joined", not as someone changing it.
local JOIN_SETTLE_SECONDS = 3

local current   -- loot method last seen; nil while not in a watched group
local joinedAt

local function MethodName(method)
  return NAMES[method] or ("unknown loot method " .. tostring(method))
end

local function ReadMethod()
  local method = C_PartyInfo.GetLootMethod()
  return SB.Plain(method)
end

local function LeaderName()
  for _, unit in ipairs(SB:GroupUnits()) do
    if SB.Plain(UnitIsGroupLeader(unit)) then return SB.Name(unit) end
  end
end

local function AlertJoinSetting(method)
  if RISKY[method] then SB:Alert("this group's loot is set to " .. MethodName(method) .. ".") end
end

local function Check()
  if not SB:Watching() then
    current = nil
    return
  end
  local method = ReadMethod()
  if method == nil then return end
  if current == nil then
    current, joinedAt = method, GetTime()
    AlertJoinSetting(method)
    return
  end
  if method == current then return end
  local old = current
  current = method
  if GetTime() - joinedAt < JOIN_SETTLE_SECONDS then
    AlertJoinSetting(method)
    return
  end
  if UnitIsGroupLeader("player") then return end  -- your own change
  -- Every change alerts; "SUSPICIOUS ACTIVITY" only when the new method takes rolls away from the group.
  SB:Alert(string.format("%s%s changed the loot rules from %s to %s.", RISKY[method] and "SUSPICIOUS ACTIVITY: " or "",
    LeaderName() or "the group leader", MethodName(old), MethodName(method)))
end

-- Entering a dungeon or raid with risky loot rules still set: remind (the join alert may be long ago; loot trouble
-- is mostly an in-dungeon issue, decided 2026-11-22). Not right after joining (the join alert just said it), and not
-- when you are the leader (your own setting).
SB:On("PLAYER_ENTERING_WORLD", function()
  local known = current ~= nil
  Check()
  if known and current and RISKY[current] and IsInInstance() and not UnitIsGroupLeader("player") then
    local instanceName = SB.Plain(GetInstanceInfo())
    SB:Alert(string.format("entering %s with the loot set to %s.", instanceName or "an instance", MethodName(current)))
  end
end)
SB:On("GROUP_ROSTER_UPDATE", Check)
SB:On("PARTY_LOOT_METHOD_CHANGED", Check)

-- Leader changes inside a dungeon or raid: a chat line only (decided 2026-11-22).
local leaderGUID  -- nil while not in a watched group

local function CurrentLeader()
  if UnitIsGroupLeader("player") then return SB.Plain(UnitGUID("player")), "You are" end
  for _, unit in ipairs(SB:GroupUnits()) do
    if SB.Plain(UnitIsGroupLeader(unit)) then return SB.Plain(UnitGUID(unit)), SB.Name(unit) .. " is" end
  end
end

local function CheckLeader()
  if not SB:Watching() then
    leaderGUID = nil
    return
  end
  local guid, who = CurrentLeader()
  if not guid or guid == leaderGUID then return end
  local had = leaderGUID
  leaderGUID = guid
  if had and IsInInstance() then SB:Print(who .. " now the group leader.") end
end

SB:On("PLAYER_ENTERING_WORLD", CheckLeader)
SB:On("GROUP_ROSTER_UPDATE", CheckLeader)
SB:On("PARTY_LEADER_CHANGED", CheckLeader)

function SB:LootStatus()
  self:Print("loot: " .. (current and MethodName(current) or "not watching"))
end

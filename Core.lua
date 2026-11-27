-- Shady Business: core (saved settings, events, alerts, slash command).
-- test.00 never sends anything to the group: every alert is shown only to you (raid-warning style on screen
-- plus a chat line), see DESIGN.md "0.1-test.00 scope".

local ADDON_NAME, SB = ...

SB.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"

local DEFAULTS = {
  party = true,   -- watch parties
  raid = false,   -- watch raids (and battlegrounds)
}

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local PREFIX = "|cffff6040Shady Business:|r "

-- A chat line only you see.
function SB:Print(msg)
  print(PREFIX .. msg)
end

-- Raid-warning style message on your screen with Blizzard's raid warning sound, plus a chat line; only you see
-- them. Forever's own raid warnings do the same (Blizzard_RaidWarning/RaidWarning.lua, OnEvent).
function SB:Alert(msg)
  self:Print(msg)
  pcall(function()
    RaidWarningFrame:AddMessage("Shady Business: " .. msg, ChatTypeInfo["RAID_WARNING"])
    PlaySound(SOUNDKIT.RAID_WARNING)
  end)
end

-- Runs fn in pcall; each different error is printed once (test version: the testers should see them).
local shownErrors = {}
function SB:Call(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local text = label .. ": " .. tostring(err)
    if not shownErrors[text] then
      shownErrors[text] = true
      self:Print("|cffff0000error|r in " .. text)
    end
  end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Forever can hand addons "secret" values; even a truth test on one is an error, so check first.
function SB.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- The value, or nil when it is secret.
function SB.Plain(v)
  if SB.IsSecret(v) then return nil end
  return v
end

-- True when you are in a group of a type the settings watch.
function SB:Watching()
  if IsInRaid() then return self.db.raid end
  if IsInGroup() then return self.db.party end
  return false
end

-- Unit tokens of the other group members.
function SB:GroupUnits()
  local units = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if not UnitIsUnit(unit, "player") then units[#units + 1] = unit end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
  end
  return units
end

-- "First Last" (Forever's UnitName returns first and last name).
function SB.Name(unit)
  local first, last = UnitName(unit)
  first, last = SB.Plain(first), SB.Plain(last)
  if not first then return "?" end
  if last and last ~= "" then return first .. " " .. last end
  return first
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function SB:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON_NAME then return end
    ShadyBusinessDB = type(ShadyBusinessDB) == "table" and ShadyBusinessDB or {}
    for key, value in pairs(DEFAULTS) do
      if ShadyBusinessDB[key] == nil then ShadyBusinessDB[key] = value end
    end
    SB.db = ShadyBusinessDB
    return
  end
  if not SB.db then return end
  for _, fn in ipairs(handlers[event] or {}) do SB:Call(event, fn, ...) end
end)

-- Called by the settings when "Party" or "Raid" changes, so both features re-check the group.
function SB:SettingsChanged()
  for _, fn in ipairs(handlers.GROUP_ROSTER_UPDATE or {}) do self:Call("settings", fn) end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_SHADYBUSINESS1 = "/shady"
SLASH_SHADYBUSINESS2 = "/shadybusiness"
SlashCmdList.SHADYBUSINESS = function(msg)
  if not SB.db then return end
  msg = strtrim(msg or ""):lower()
  if msg == "" or msg == "settings" then
    SB:ToggleSettings()
  elseif msg == "status" then
    SB:Print("version " .. SB.version .. ". Watching: " .. (SB:Watching() and "yes" or "no (not in a watched group)") .. ".")
    if SB.LootStatus then SB:LootStatus() end
    if SB.HealerStatus then SB:HealerStatus() end
  else
    SB:Print("commands: /shady (settings), /shady status")
  end
end

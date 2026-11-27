-- Shady Business: settings, the same simple design as ProfitCraft's and PsiLab's:
--   * its own movable window (/shady). Closing it just closes it; it never goes through Blizzard's settings
--     panel, whose close always reopens the game menu (Forever source: SettingsPanelMixin:
--     TransitionBackOpeningPanel -> ToggleGameMenu).
--   * The same page under Blizzard's Options > AddOns > Shady Business.
-- Each page re-reads the settings when shown and after any change, so they never disagree.

local _, SB = ...

local ROW_SPACING = 30
local WIDTH = 320

local OPTIONS = {
  { key = "party", label = "Watch parties",
    help = "Loot rule alerts and the healer check in 5-player groups (dungeons, questing groups)." },
  { key = "raid", label = "Watch raids",
    help = "Loot rule alerts and the healer check in raids and battlegrounds. Off by default: raids often use "
      .. "Master Looter on purpose." },
}

local pages = {}
local window

local function Sync(page)
  for option, box in pairs(page.boxes) do box:SetChecked(SB.db[option.key] and true or false) end
end

local function SyncVisible()
  for _, page in ipairs(pages) do
    if page:IsVisible() then Sync(page) end
  end
end

local function BuildPage(container, x, y)
  container.boxes = {}
  local heading = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  heading:SetPoint("TOPLEFT", x + 4, y - 4)
  heading:SetText("GROUPS")
  for i, option in ipairs(OPTIONS) do
    local box = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", x, y - 20 - (i - 1) * ROW_SPACING)
    box.Text:SetText(option.label)
    box.Text:SetFontObject("GameFontHighlight")
    box:SetScript("OnClick", function(self)
      SB.db[option.key] = self:GetChecked() and true or false
      SyncVisible()
      SB:SettingsChanged()
    end)
    box:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(option.label, 1, 1, 1)
      GameTooltip:AddLine(option.help, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.boxes[option] = box
  end
  local note = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", x + 4, y - 28 - #OPTIONS * ROW_SPACING)
  note:SetWidth(WIDTH - 40)
  note:SetJustifyH("LEFT")
  note:SetText("Test version: every alert is shown only to you, nothing is sent to the group.")
  container:HookScript("OnShow", Sync)
  pages[#pages + 1] = container
end

-- Blizzard's flat panel (DefaultPanelFlatTemplate: dark background, border and title bar, no portrait) with
-- Blizzard's close button, which hides the window. The template has no close button or inset of its own; its
-- background starts 20 below the top edge (Forever source: Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml).
local function CreateWindowPage()
  window = CreateFrame("Frame", "ShadyBusinessSettings", UIParent, "DefaultPanelFlatTemplate")
  window:SetSize(WIDTH, 110 + #OPTIONS * ROW_SPACING)
  window:SetTitle("Shady Business")
  CreateFrame("Button", nil, window, "UIPanelCloseButtonDefaultAnchors")
  window:SetPoint("CENTER")
  window:SetFrameStrata("HIGH")
  window:SetClampedToScreen(true)
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  table.insert(UISpecialFrames, "ShadyBusinessSettings")  -- Escape closes it
  window:Hide()
  local page = CreateFrame("Frame", nil, window)
  page:SetPoint("TOPLEFT", 6, -22)
  page:SetPoint("BOTTOMRIGHT", -2, 2)
  BuildPage(page, 8, -6)
  local version = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  version:SetPoint("BOTTOMLEFT", 12, 8)
  version:SetText("Shady Business " .. SB.version)
end

function SB:ToggleSettings()
  if not window then CreateWindowPage() end
  window:SetShown(not window:IsShown())
end

-- The page in Blizzard's Options > AddOns. Blizzard sizes and shows the canvas frame itself.
local function RegisterBlizzardPage()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local canvas = CreateFrame("Frame", nil, UIParent)
  canvas:Hide()
  local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Shady Business")
  BuildPage(canvas, 12, -52)
  Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(canvas, "Shady Business"))
end

SB:On("PLAYER_LOGIN", RegisterBlizzardPage)

-- CoA Loot Feed / core.lua
-- Loot feed for WoW 3.3.5a (12340). Idea: Ultimate Loot Frame (DevYiang).
-- Clean-room implementation: no code from the original addon is used.
-- verify-allow: ChatEdit_InsertLink, GameTooltip_ShowCompareItem, GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT, LOOT_ITEM, LOOT_ITEM_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, ITEM_BIND_QUEST, ULF335DB, Atr_GetAuctionPrice
-- Allowed: FrameXML 3.3.5 functions and GlobalStrings (checked in 335-interface-files); ULF335DB is this addon's SavedVariable; Atr_GetAuctionPrice is Auctionator 2.6.8, called only when present.

local ADDON_NAME = "CoALootFeed"
local API = {}
_G["COALF"] = API

local ULF = CreateFrame("Frame", "ULF335Feed", UIParent)
ULF:SetFrameStrata("MEDIUM")
ULF:SetClampedToScreen(true)
ULF:SetMovable(true)
ULF:RegisterForDrag("LeftButton")
ULF:Hide()

ULF.rows = {}
ULF.pool = {}
ULF.sessionCopper = 0
ULF.moving = false

local db
local lastMoneyAmount, lastMoneyTime = 0, 0
local borderR, borderG, borderB = 0.55, 0.55, 0.55
local FADE_IN, FADE_OUT = 0.15, 0.5

local DEFAULTS = {
  enabled = true,
  locked = true,
  growUp = false,
  width = 430,
  rowHeight = 50,
  maxRows = 6,
  duration = 6,
  fadeIn = 0.15,
  fadeOut = 0.45,
  iconSize = 44,
  showSubText = true,
  layoutV2 = false,
  priceSource = "both",
  showStackPrice = false,
  coinStyle = "compact",
  priceLabels = false,
  maxNameLength = 35,
  highlightEnabled = true,
  highlightT1 = 1,
  highlightT2 = 5,
  useQualityDuration = true,
  qualityDurations = { 5, 10, 15, 20, 25, 40 },
  bgAlpha = 0.75,
  borderSize = 1,
  iconRarityBorder = true,
  frameRarityBorder = false,
  showGroupLoot = false,
  showMoney = true,
  showSessionTotal = true,
  showSellPrice = true,
  showAuctionPrice = true,
  showIlvl = true,
  showQuestMark = true,
  showPrice = true,
  prices = {},
  minimapShown = true,
  minimapAngle = 225,
  soundEnabled = true,
  soundQuality = 4,
  soundMoneyGold = 10,
  soundName = "LOOTWINDOWCOINSOUND",
  font = "Fonts\\FRIZQT__.TTF",
  fontSize = 12,
  fontOutline = "",
  point = { "CENTER", "CENTER", 0, 180 },
}

-- 3.3.5 requires a font before the first SetText; styleRow sets the final font later.
local function makeFontString(parent, layer)
  local fs = parent:CreateFontString(nil, layer)
  fs:SetFont(DEFAULTS.font, DEFAULTS.fontSize, "")
  return fs
end

-- Cuts a plain string with "..." so a long item name cannot run into the price block.
local function fitText(fs, text, maxWidth)
  text = text or ""
  fs:SetText(text)
  if not fs.GetStringWidth or maxWidth <= 0 then return end
  if fs:GetStringWidth() <= maxWidth then return end
  local lo, hi = 1, #text
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    fs:SetText(text:sub(1, mid) .. "...")
    if fs:GetStringWidth() <= maxWidth then lo = mid + 1 else hi = mid end
  end
  fs:SetText(text:sub(1, math.max(0, lo - 1)) .. "...")
end

local QUALITY_HEX = {}
for q = 0, 7 do
  local r, g, b = GetItemQualityColor(q)
  QUALITY_HEX[q] = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function printMsg(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CoALF:|r " .. tostring(msg))
end
API.Print = printMsg

-- Escapes Lua-pattern magic characters in a GlobalString format.
local function escapeMagic(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Turns "%s receives loot: %sx%d." into an anchored capture pattern.
local function buildPattern(fmt)
  local p = escapeMagic(fmt)
  p = p:gsub("%%%%s", "(.-)")
  p = p:gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

-- Order matters: MULTIPLE variants must be tested before single ones.
local lootPatterns = {
  { pat = buildPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d."), link = 1, qty = 2 },
  { pat = buildPattern(LOOT_ITEM_SELF or "You receive loot: %s."), link = 1 },
  { pat = buildPattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE or "You receive item: %sx%d."), link = 1, qty = 2 },
  { pat = buildPattern(LOOT_ITEM_PUSHED_SELF or "You receive item: %s."), link = 1 },
  { pat = buildPattern(LOOT_ITEM_MULTIPLE or "%s receives loot: %sx%d."), who = 1, link = 2, qty = 3 },
  { pat = buildPattern(LOOT_ITEM or "%s receives loot: %s."), who = 1, link = 2 },
}

local function moneyPat(fmt)
  return (escapeMagic(fmt):gsub("%%%%d", "(%%d+)"))
end
local moneyPats = {
  gold = moneyPat(GOLD_AMOUNT or "%d Gold"),
  silver = moneyPat(SILVER_AMOUNT or "%d Silver"),
  copper = moneyPat(COPPER_AMOUNT or "%d Copper"),
}

local GOLD_WORD = ((GOLD_AMOUNT or "%d Gold"):gsub("%%d%s*", ""))
local SILVER_WORD = ((SILVER_AMOUNT or "%d Silver"):gsub("%%d%s*", ""))
local COPPER_WORD = ((COPPER_AMOUNT or "%d Copper"):gsub("%%d%s*", ""))

-- Extracts a copper amount from any money message, locale-safe.
local function parseCopper(text)
  if not text then return nil end
  local total, found = 0, false
  local g = text:match(moneyPats.gold)
  if g then total = total + tonumber(g) * 10000; found = true end
  local s = text:match(moneyPats.silver)
  if s then total = total + tonumber(s) * 100; found = true end
  local c = text:match(moneyPats.copper)
  if c then total = total + tonumber(c); found = true end
  if found then return total end
  return nil
end

-- Coin display: compact "1g 85s 17c" (default), coin icons, or locale words.
local COIN_ICON = {
  g = "Interface\\MoneyFrame\\UI-GoldIcon.blp",
  s = "Interface\\MoneyFrame\\UI-SilverIcon.blp",
  c = "Interface\\MoneyFrame\\UI-CopperIcon.blp",
}

local function formatCopper(c)
  c = math.floor(c or 0)
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local cc = c % 100
  local parts = {}
  local style = (db and db.coinStyle) or "compact"
  if style == "coins" then
    if g > 0 then parts[#parts + 1] = "|T" .. COIN_ICON.g .. ":12:12|t" .. g end
    if s > 0 then parts[#parts + 1] = "|T" .. COIN_ICON.s .. ":12:12|t" .. s end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = "|T" .. COIN_ICON.c .. ":12:12|t" .. cc end
  elseif style == "words" then
    if g > 0 then parts[#parts + 1] = string.format("|cffffd100%d %s|r", g, GOLD_WORD) end
    if s > 0 then parts[#parts + 1] = string.format("|cffc7c7cf%d %s|r", s, SILVER_WORD) end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = string.format("|cffeda55f%d %s|r", cc, COPPER_WORD) end
  else
    if g > 0 then parts[#parts + 1] = string.format("|cffffd100%dg|r", g) end
    if s > 0 then parts[#parts + 1] = string.format("|cffc7c7cf%ds|r", s) end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = string.format("|cffeda55f%dc|r", cc) end
  end
  return table.concat(parts, " ")
end
API.FormatMoney = formatCopper

-- Grey label above the value on the right; the label changes colour for expensive loot.
local function priceLabelHex(value)
  if not db.highlightEnabled then return "ffaaaaaa" end
  local g = (value or 0) / 10000
  if g >= (db.highlightT2 or 5) then return "ffff4444" end
  if g >= (db.highlightT1 or 1) then return "ffcc6600" end
  return "ffaaaaaa"
end

local function priceBlock(label, value, qty, labelHex)
  local v = value or 0
  if db.showStackPrice and qty and qty > 1 then v = v * qty end
  if not db.priceLabels then return formatCopper(v) end
  local hex = labelHex or "ffaaaaaa"
  return "|c" .. hex .. label .. "|r\n" .. formatCopper(v)
end

-- Sound names are taken from 3.3.5 FrameXML (PlaySound calls there).
local SOUND_NAMES = { "LOOTWINDOWCOINSOUND", "igQuestListComplete", "TellMessage", "RaidWarning", "LFG_Rewards" }
API.SoundNames = SOUND_NAMES

local function playAlert()
  if not db or not db.soundEnabled then return end
  if db.soundName and db.soundName ~= "" then PlaySound(db.soundName) end
end

-- "12g34s56c", "12g", "500" (bare number = copper).
local function parsePriceValue(s)
  if not s then return nil end
  s = s:gsub("[%s,]", ""):lower()
  if s == "" then return nil end
  local g = tonumber(s:match("(%d+)g")) or 0
  local sv = tonumber(s:match("(%d+)s")) or 0
  local c = tonumber(s:match("(%d+)c")) or 0
  if g == 0 and sv == 0 and c == 0 then
    local plain = tonumber(s)
    if plain then return math.floor(plain) end
    return nil
  end
  return g * 10000 + sv * 100 + c
end

local function itemIDFromInput(s)
  if not s then return nil end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  local id = s:match("|Hitem:(%d+)") or s:match("item:(%d+)")
  if id then return tonumber(id) end
  if tonumber(s) then return tonumber(s) end
  return nil
end

-- Hidden tooltip used to detect quest items.
local scanTip = CreateFrame("GameTooltip", "ULF335ScanTooltip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function isQuestItem(link)
  scanTip:ClearLines()
  scanTip:SetHyperlink(link)
  local questText = ITEM_BIND_QUEST or "Quest Item"
  for i = 1, scanTip:NumLines() do
    local fs = _G["ULF335ScanTooltipTextLeft" .. i]
    if fs then
      local t = fs:GetText()
      if t and t:find(questText, 1, true) then return true end
    end
  end
  return false
end

ULF.footer = makeFontString(ULF, "OVERLAY")
ULF.footer:SetPoint("BOTTOMLEFT", ULF, "BOTTOMLEFT", 6, 4)
ULF.footer:SetJustifyH("LEFT")
ULF.footer:Hide()

ULF.hint = makeFontString(ULF, "OVERLAY")
ULF.hint:SetPoint("CENTER", ULF, "CENTER", 0, 0)
ULF.hint:SetText("CoA Loot Feed: drag me")
ULF.hint:SetTextColor(0.5, 1, 0.5, 0.6)
ULF.hint:Hide()

-- Dragging works from the frame and from any row (rows cover most of the frame).
local function beginMove()
  if db and not db.locked then ULF:StartMoving() end
end

local function endMove()
  ULF:StopMovingOrSizing()
  local p, _, rp, x, y = ULF:GetPoint(1)
  db.point = { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }
end

-- Self-contained minimap button: left-click options, right-click move, drag to orbit.
local minibtn = CreateFrame("Button", "ULF335MinimapButton", Minimap)
minibtn:SetFrameStrata("MEDIUM")
minibtn:SetWidth(32)
minibtn:SetHeight(32)
minibtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_01")
minibtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
minibtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minibtn:RegisterForDrag("LeftButton")

local function placeMinimapButton()
  if not db then return end
  if not db.minimapShown then minibtn:Hide() return end
  minibtn:Show()
  local radius = (Minimap:GetWidth() or 140) / 2 + 8
  local a = math.rad(db.minimapAngle or 225)
  minibtn:ClearAllPoints()
  minibtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end
API.PlaceMinimapButton = placeMinimapButton

local function dragMinimapButton(self)
  local mx, my = Minimap:GetCenter()
  if not mx or not my then return end
  local sx, sy = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale() or 1
  sx, sy = sx / scale, sy / scale
  db.minimapAngle = math.deg(math.atan2(sy - my, sx - mx))
  placeMinimapButton()
end

minibtn:SetScript("OnDragStart", function(self)
  self.wasDragged = true
  self:SetScript("OnUpdate", dragMinimapButton)
end)
minibtn:SetScript("OnDragStop", function(self)
  self:SetScript("OnUpdate", nil)
end)
minibtn:SetScript("OnClick", function(self, button)
  if self.wasDragged then self.wasDragged = nil; return end
  if button == "RightButton" then
    if API.ToggleMove then API.ToggleMove() end
  elseif API.OpenOptions then
    API.OpenOptions()
  else
    printMsg("Use /coalf to open options")
  end
end)
minibtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("CoA Loot Feed")
  GameTooltip:AddLine("Left-click: options", 1, 1, 1)
  GameTooltip:AddLine("Right-click: move the feed", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this icon", 1, 1, 1)
  GameTooltip:Show()
end)
minibtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function applyBackdrop()
  local edge = nil
  if db.borderSize > 0 then edge = "Interface\\Buttons\\WHITE8X8" end
  ULF:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = edge,
    tile = false,
    edgeSize = db.borderSize,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  ULF:SetBackdropColor(0, 0, 0, db.bgAlpha)
  ULF:SetBackdropBorderColor(borderR, borderG, borderB, 1)
end

local function rightBlockWidth()
  local n = 0
  if db.showSellPrice then n = n + 1 end
  if db.showAuctionPrice and Atr_GetAuctionPrice then n = n + 1 end
  if db.showPrice and db.prices and next(db.prices) then n = n + 1 end
  if n == 1 then return 100 end
  if n == 2 then return 145 end
  if n >= 3 then return 185 end
  return 0
end

local function styleRow(row)
  local h = db.rowHeight
  local icon = math.min(db.iconSize or 44, h - 4)
  if icon < 16 then icon = 16 end
  local twoLine = h >= 40 and db.showSubText
  local rightW = (row and row.rightTextWidth and row.rightTextWidth > 0) and (row.rightTextWidth + 14) or rightBlockWidth()

  row:SetHeight(h)
  row:SetWidth(db.width - 8)
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetWidth(icon)
  row.icon:SetHeight(icon)
  row.iconBorder:ClearAllPoints()
  row.iconBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
  row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)

  local dy = twoLine and math.floor(h * 0.18) or 0

  row.quest:SetFont(db.font, db.fontSize + 2, db.fontOutline)
  row.quest:ClearAllPoints()
  row.quest:SetPoint("LEFT", row.icon, "RIGHT", 3, dy)

  row.right:SetFont(db.font, math.max(8, db.fontSize - 1), db.fontOutline)
  row.right:SetJustifyV("CENTER")
  row.right:ClearAllPoints()
  row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)

  row.name:SetFont(db.font, db.fontSize, db.fontOutline)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row.quest, "RIGHT", 3, dy)
  row.name:SetPoint("RIGHT", row, "RIGHT", -(rightW + 12), dy)

  row.sub:SetFont(db.font, math.max(8, db.fontSize - 2), db.fontOutline)
  row.sub:ClearAllPoints()
  row.sub:SetPoint("LEFT", row.quest, "RIGHT", 3, -dy)
  row.sub:SetPoint("RIGHT", row, "RIGHT", -(rightW + 12), -dy)

  if twoLine and row.sub:GetText() and row.sub:GetText() ~= "" then
    row.sub:Show()
  else
    row.sub:Hide()
  end
end

local function createRow()
  local row = CreateFrame("Button", nil, ULF)
  row.iconBorder = row:CreateTexture(nil, "BACKGROUND")
  row.iconBorder:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.quest = makeFontString(row, "OVERLAY")
  row.quest:SetText("!")
  row.quest:SetTextColor(1, 0.82, 0)
  row.quest:Hide()
  row.name = makeFontString(row, "OVERLAY")
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.name:SetTextColor(1, 1, 1)
  row.sub = makeFontString(row, "OVERLAY")
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)
  row.sub:SetTextColor(0.67, 0.67, 0.67)
  row.sub:Hide()
  row.right = makeFontString(row, "OVERLAY")
  row.right:SetJustifyH("RIGHT")
  row.right:SetJustifyV("TOP")
  row.right:SetTextColor(1, 1, 1)
  row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  row:RegisterForClicks("LeftButtonUp")
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnClick", function(self)
    if self.link and IsShiftKeyDown() and ChatEdit_InsertLink then
      ChatEdit_InsertLink(self.link)
    end
  end)
  row:SetScript("OnDragStart", beginMove)
  row:SetScript("OnDragStop", endMove)
  row:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    if GameTooltip_ShowCompareItem then
      GameTooltip_ShowCompareItem(GameTooltip)
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return row
end

-- Measured from the right block actually rendered, so it works at ANY window size.
local function nameMaxWidth(row)
  local icon = math.min(db.iconSize or 44, (db.rowHeight or 50) - 4)
  local rightW = (row and row.rightTextWidth) or rightBlockWidth()
  if rightW > 0 then rightW = rightW + 14 end
  return math.max(40, db.width - 12 - icon - rightW - 12)
end

local function rebuildName(row)
  if row.isMoney then return end
  -- Explicit character limit first, then pixel-fit; colour codes add no width.
  local plain = row.displayName or "?"
  local limit = db.maxNameLength or 35
  if #plain > limit then
    plain = plain:sub(1, math.max(1, limit - 3)) .. "..."
  end
  fitText(row.name, plain, nameMaxWidth(row))
  local shown = row.name:GetText() or "?"
  local text = ""
  if row.qty and row.qty > 1 then
    text = "|cffffffff" .. row.qty .. "x |r"
  end
  if row.who then text = text .. "|cffaaaaaa" .. row.who .. ": |r" end
  text = text .. "|c" .. (row.hex or "ffffffff") .. shown .. "|r"
  row.name:SetText(text)
end

-- Fills icon/quality/ilvl/sell price from the item cache; retried while pending.
local function fillItemData(row)
  local name, link, quality, ilvl, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice = GetItemInfo(row.link)
  if not name and row.itemId then
    name, link, quality, ilvl, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice = GetItemInfo(row.itemId)
  end
  if not name then return end
  row.pending = false
  row.quality = quality
  if not row.itemId and row.link then
    row.itemId = tonumber(row.link:match("|Hitem:(%d+)"))
  end
  row.hex = QUALITY_HEX[quality] or "ffffffff"
  row.displayName = name
  row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
  local r, g, b = GetItemQualityColor(quality)
  if db.iconRarityBorder then
    row.iconBorder:SetTexture(r, g, b, 0.9)
    row.iconBorder:Show()
  else
    row.iconBorder:Hide()
  end
  if db.frameRarityBorder then
    borderR, borderG, borderB = r, g, b
    applyBackdrop()
  end
  local parts = {}
  if not db.showSubText and db.showIlvl and ilvl and ilvl > 0 then
    parts[#parts + 1] = "|cffaaaaaaiLvl " .. ilvl .. "|r"
  end
  local source = db.priceSource or "both"
  local vendor = (sellPrice and sellPrice > 0) and sellPrice or nil
  -- Auctionator 2.6.8: Atr_GetAuctionPrice(itemName) -> copper from its scan DB.
  local auction = nil
  if source ~= "vendor" and db.showAuctionPrice and Atr_GetAuctionPrice then
    local a = Atr_GetAuctionPrice(name)
    if a and a > 0 then auction = a end
  end
  if auction then
    local hex = priceLabelHex(auction)
    if hex == "ffaaaaaa" then hex = "ff3fc30e" end
    parts[#parts + 1] = priceBlock("Auction:", auction, row.qty, hex)
  end
  if source ~= "auction" and db.showSellPrice and vendor then
    parts[#parts + 1] = priceBlock("Sell Price:", vendor, row.qty, "ffc7c7cf")
  end
  if db.showPrice and db.prices and row.itemId then
    local custom = db.prices[row.itemId]
    if custom and custom > 0 then
      parts[#parts + 1] = priceBlock("Price:", custom, row.qty, priceLabelHex(custom))
    end
  end
  row.right:SetText(table.concat(parts, db.priceLabels and "  " or "\n"))
  -- Measure what is really on the right, then fit the left text to the leftover space.
  row.rightTextWidth = row.right:GetStringWidth() or 0

  -- Details line under the name: "ilvl: 315 Indestructible", like the WA example.
  local subParts = {}
  if db.showIlvl and ilvl and ilvl > 0 then
    subParts[#subParts + 1] = "ilvl: " .. ilvl
  end
  if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
    subParts[#subParts + 1] = "|cff66dddd" .. (_G[equipLoc] or equipLoc) .. "|r"
  end
  if itemSubType and itemSubType ~= "" and itemSubType ~= itemType then
    subParts[#subParts + 1] = "|cff66dddd" .. itemSubType .. "|r"
  end
  local subText = table.concat(subParts, " ")
  rebuildName(row)
  fitText(row.sub, subText, nameMaxWidth(row))
  if db.showSubText and (db.rowHeight or 50) >= 40 and subText ~= "" then
    row.sub:Show()
  else
    row.sub:Hide()
  end

  if quality and quality >= (db.soundQuality or 4) and not row.soundPlayed then
    row.soundPlayed = true
    playAlert()
  end
  if db.showQuestMark and (row.forceQuest or isQuestItem(row.link)) then
    row.quest:Show()
  else
    row.quest:Hide()
  end
end

local function layoutRows()
  local n = #ULF.rows
  local step = db.rowHeight + 2
  local h = n * step + 8
  ULF:SetWidth(db.width)
  if db.showSessionTotal and ULF.sessionCopper > 0 then
    ULF.footer:SetText("|cffaaaaaaSession total:|r " .. formatCopper(ULF.sessionCopper))
    ULF.footer:Show()
    h = h + 16
  else
    ULF.footer:Hide()
  end
  if ULF.moving and h < 34 then h = 34 end
  ULF:SetHeight(h)
  for i, row in ipairs(ULF.rows) do
    local idx = i - 1
    if db.growUp then idx = n - i end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ULF, "TOPLEFT", 4, -4 - idx * step)
    row:Show()
  end
  if ULF.moving then ULF.hint:Show() else ULF.hint:Hide() end
end

local function recycleRow(index)
  local row = table.remove(ULF.rows, index)
  if not row then return end
  row:Hide()
  row:ClearAllPoints()
  row.pending = false
  row.link = nil
  row.itemId = nil
  row.forceQuest = nil
  tinsert(ULF.pool, row)
end

local function addRow(data)
  local row = table.remove(ULF.pool) or createRow()
  row.age = 0
  row.isMoney = data.isMoney or false
  row.who = data.who
  row.qty = data.qty or 1
  row.pending = false
  row.nextRetry = 0
  row.forceQuest = data.forceQuest
  row.soundPlayed = nil
  row.link = nil
  row.itemId = nil
  row.right:SetText("")
  row.rightTextWidth = 0
  row.sub:SetText("")
  row.quest:Hide()
  row.iconBorder:Hide()
  row:SetAlpha(0)
  if row.isMoney then
    row.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    row.icon:SetTexCoord(0, 1, 0, 1)
    row.name:SetText("Gold")
    if db.priceLabels then
      row.right:SetText("|cffaaaaaaMoney Earned:|r\n+" .. formatCopper(data.amount))
    else
      row.right:SetText("+" .. formatCopper(data.amount))
    end
    row.rightTextWidth = row.right:GetStringWidth() or 0
    if db.iconRarityBorder then
      row.iconBorder:SetTexture(1, 0.82, 0, 0.9)
      row.iconBorder:Show()
    end
  else
    row.link = data.link
    row.itemId = data.itemId or tonumber(data.link:match("|Hitem:(%d+)"))
    row.hex = data.link:match("^|c(%x%x%x%x%x%x%x%x)") or "ffffffff"
    row.displayName = data.link:match("|h%[(.-)%]|h") or "?"
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    styleRow(row)
    row.pending = true
    fillItemData(row)
  end
  styleRow(row)
  tinsert(ULF.rows, row)
  while #ULF.rows > db.maxRows do
    recycleRow(1)
  end
  layoutRows()
  ULF:Show()
end

local function onMoney(amount)
  if not amount or amount <= 0 then return end
  local now = GetTime()
  if amount == lastMoneyAmount and now - lastMoneyTime < 0.5 then return end
  lastMoneyAmount, lastMoneyTime = amount, now
  ULF.sessionCopper = ULF.sessionCopper + amount
  if amount >= (db.soundMoneyGold or 0) * 10000 then playAlert() end
  if db.showMoney then
    addRow({ isMoney = true, amount = amount })
  else
    layoutRows()
  end
end

local function onLoot(msg)
  if not msg then return end
  if not msg:find("|Hitem:", 1, true) then
    local c = parseCopper(msg)
    if c then onMoney(c) end
    return
  end
  for _, p in ipairs(lootPatterns) do
    local caps = { msg:match(p.pat) }
    if #caps > 0 then
      local link = caps[p.link]
      if link and link:find("|Hitem:", 1, true) then
        if p.who and not db.showGroupLoot then return end
        addRow({
          link = link,
          qty = p.qty and tonumber(caps[p.qty]) or 1,
          who = p.who and caps[p.who] or nil,
        })
      end
      return
    end
  end
end

local function applyAll()
  applyBackdrop()
  ULF:EnableMouse(not db.locked)
  ULF:ClearAllPoints()
  ULF:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
  ULF.footer:SetFont(db.font, math.max(8, db.fontSize - 1), db.fontOutline)
  ULF.hint:SetFont(db.font, db.fontSize, db.fontOutline)
  for _, row in ipairs(ULF.rows) do
    styleRow(row)
    if not row.isMoney and row.link then fillItemData(row) end
  end
  layoutRows()
  placeMinimapButton()
end
API.Apply = applyAll

local function initDB()
  if type(ULF335DB) ~= "table" then ULF335DB = {} end
  db = ULF335DB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then
      if k == "point" then db[k] = { unpack(v) }
      elseif k == "prices" then db[k] = {}
      else db[k] = v end
    end
  end
  -- One-time layout migration for profiles saved by the old compact build.
  if not db.layoutV2 then
    db.layoutV2 = true
    db.rowHeight = DEFAULTS.rowHeight
    db.width = DEFAULTS.width
    db.iconSize = DEFAULTS.iconSize
    db.fadeIn = DEFAULTS.fadeIn
    db.fadeOut = DEFAULTS.fadeOut
  end
  API.db = db
end

-- Preview: real WotLK item IDs; "!" on Hearthstone is a demo marker only.
local PREVIEW_IDS = { 49623, 32837, 19019, 2589, 6948 }
local function Preview()
  if not db then return end
  for _, id in ipairs(PREVIEW_IDS) do
    local name = GetItemInfo(id) or ("Item " .. id)
    local link = "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
    addRow({
      link = link,
      itemId = id,
      qty = (id == 2589) and 20 or 1,
      forceQuest = (id == 6948) or nil,
    })
  end
  onMoney(12345)
end
API.Preview = Preview

function API.SetPrice(input, valueStr)
  if not db then return end
  local id = itemIDFromInput(input)
  if not id then
    printMsg("Usage: /ulf price <itemID or item link> <12g34s56c | copper>")
    return
  end
  local value = parsePriceValue(valueStr)
  if value == nil then
    printMsg("Invalid price. Use 12g34s56c, 12g or a copper number")
    return
  end
  if value <= 0 then
    db.prices[id] = nil
    printMsg("Price removed for item " .. id)
  else
    db.prices[id] = value
    printMsg("Price set: " .. (GetItemInfo(id) or ("item " .. id)) .. " = " .. formatCopper(value))
  end
  for _, row in ipairs(ULF.rows) do
    if row.itemId == id and not row.isMoney and row.link then fillItemData(row) end
  end
end

function API.ListPrices()
  if not db then return end
  local n = 0
  for id, value in pairs(db.prices) do
    printMsg(id .. "  " .. (GetItemInfo(id) or ("item " .. id)) .. ": " .. formatCopper(value))
    n = n + 1
  end
  if n == 0 then printMsg("Price DB is empty") end
end

function API.ClearPrices()
  if not db then return end
  for k in pairs(db.prices) do db.prices[k] = nil end
  printMsg("Price DB cleared")
end

local function ToggleMove()
  db.locked = not db.locked
  ULF.moving = not db.locked
  applyAll()
  if ULF.moving then
    ULF:Show()
  elseif #ULF.rows == 0 then
    ULF:Hide()
  end
  printMsg(db.locked and "Position locked" or "Position unlocked - drag the frame")
end
API.ToggleMove = ToggleMove

local function ResetPos()
  db.point = { unpack(DEFAULTS.point) }
  applyAll()
  printMsg("Position reset")
end
API.ResetPos = ResetPos

local function ResetAll()
  for k in pairs(db) do db[k] = nil end
  initDB()
  ULF.sessionCopper = 0
  borderR, borderG, borderB = 0.55, 0.55, 0.55
  ULF.moving = false
  applyAll()
  if #ULF.rows == 0 then ULF:Hide() end
  printMsg("Settings reset")
end
API.ResetAll = ResetAll

API.GetSession = function() return ULF.sessionCopper end

ULF:SetScript("OnDragStart", beginMove)
ULF:SetScript("OnDragStop", endMove)

ULF:SetScript("OnUpdate", function(self, elapsed)
  local changed = false
  local fadeIn = db.fadeIn or FADE_IN
  local fadeOut = db.fadeOut or FADE_OUT
  for i = #self.rows, 1, -1 do
    local row = self.rows[i]
    row.age = row.age + elapsed
    local dur = db.duration
    if db.useQualityDuration and not row.isMoney and row.quality and db.qualityDurations then
      dur = db.qualityDurations[row.quality + 1] or dur
    end
    if row.pending and row.age >= row.nextRetry then
      row.nextRetry = row.age + 0.3
      fillItemData(row)
    end
    local a = 1
    if fadeIn > 0 and row.age < fadeIn then
      a = row.age / fadeIn
    elseif row.age > dur then
      a = fadeOut > 0 and math.max(0, 1 - (row.age - dur) / fadeOut) or 0
    end
    row:SetAlpha(a)
    if row.age > dur + fadeOut then
      recycleRow(i)
      changed = true
    end
  end
  if changed then layoutRows() end
  if #self.rows == 0 and not self.moving then self:Hide() end
end)

ULF:RegisterEvent("ADDON_LOADED")
ULF:RegisterEvent("CHAT_MSG_LOOT")
ULF:RegisterEvent("CHAT_MSG_MONEY")
ULF:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON_NAME then
      initDB()
      applyAll()
      self:UnregisterEvent("ADDON_LOADED")
    end
  elseif event == "CHAT_MSG_LOOT" then
    if db and db.enabled then onLoot((...)) end
  elseif event == "CHAT_MSG_MONEY" then
    if db and db.enabled then
      local c = parseCopper((...))
      if c then onMoney(c) end
    end
  end
end)

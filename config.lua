-- CoA Loot Feed / config.lua
-- Interface Options panels + slash commands. 3.3.5 native templates only.
-- verify-allow: COALF
-- COALF is the API table published by core.lua via _G["COALF"].

local API = COALF

-- The 3.3.5 options frame already draws panel.name as a centred header,
-- so we only add a short hint below it and keep controls clear of that band.
local function makePanel(name, subText)
  local p = CreateFrame("Frame", nil, UIParent)
  p.name = name
  p:Hide()
  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -34)
  sub:SetText(subText)
  return p
end

-- Each panel gets its own control lists so refresh/default stay independent.
local function newBuilder(panel, prefix)
  local checks, sliders, cycles = {}, {}, {}
  local b = {}

  function b.check(x, y, label, tip, key)
    local cb = CreateFrame("CheckButton", prefix .. "Check" .. key, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb.tooltipText = tip
    cb:SetScript("OnClick", function(self)
      API.db[key] = self:GetChecked() == 1
      API.Apply()
    end)
    checks[#checks + 1] = { w = cb, key = key }
    return y - 26
  end

  function b.slider(x, y, label, key, minV, maxV, step, fmt)
    local sl = CreateFrame("Slider", prefix .. "Slider" .. (key:gsub("%.", "_")), panel, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    sl:SetWidth(170)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    _G[sl:GetName() .. "Low"]:SetText(tostring(minV))
    _G[sl:GetName() .. "High"]:SetText(tostring(maxV))
    local labelFs = _G[sl:GetName() .. "Text"]
    sl:SetScript("OnValueChanged", function(self, value)
      value = math.floor(value / step + 0.5) * step
      value = tonumber(string.format("%.2f", value))
      labelFs:SetText(label .. ": " .. string.format(fmt, value))
      local tname, idx = key:match("^(.-)%.([0-9]+)$")
      if tname and API.db and API.db[tname] then
        local n = tonumber(idx)
        if API.db[tname][n] ~= value then
          API.db[tname][n] = value
          API.Apply()
        end
      elseif API.db and API.db[key] ~= value then
        API.db[key] = value
        API.Apply()
      end
    end)
    sliders[#sliders + 1] = { w = sl, key = key }
    return y - 42
  end

  -- Cycle button instead of UIDropDownMenu: no dropdown API signature risks on 3.3.5.
  function b.cycle(x, y, label, key, values, labels)
    local btn = CreateFrame("Button", prefix .. "Cycle" .. key, panel, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    btn:SetWidth(170)
    btn:SetHeight(24)
    btn:SetScript("OnClick", function(self)
      local idx = 1
      for i, v in ipairs(values) do
        if v == API.db[key] then idx = i break end
      end
      idx = idx + 1
      if idx > #values then idx = 1 end
      API.db[key] = values[idx]
      self:SetText(label .. ": " .. labels[idx])
      API.Apply()
    end)
    cycles[#cycles + 1] = { w = btn, key = key, label = label, values = values, labels = labels }
    return y - 36
  end

  function b.button(x, y, label, onClick)
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    btn:SetWidth(170)
    btn:SetHeight(24)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return y - 32
  end

  function b.refresh()
    if not API.db then return end
    for _, c in ipairs(checks) do
      c.w:SetChecked(API.db[c.key] and 1 or nil)
    end
    for _, s in ipairs(sliders) do
      local tname, idx = s.key:match("^(.-)%.([0-9]+)$")
      if tname and API.db[tname] then
        s.w:SetValue(API.db[tname][tonumber(idx)] or 0)
      else
        s.w:SetValue(API.db[s.key])
      end
    end
    for _, c in ipairs(cycles) do
      local idx = 1
      for i, v in ipairs(c.values) do
        if v == API.db[c.key] then idx = i break end
      end
      c.w:SetText(c.label .. ": " .. c.labels[idx])
    end
  end

  return b
end

-- ---- Panel 1: feed and appearance ----
local main = makePanel("CoA Loot Feed",
  "Commands: /coalf, /coalf alerts, /coalf timings")
local b1 = newBuilder(main, "ULF335")

local y1 = -76
y1 = b1.check(16, y1, "Enabled", "Show the loot feed", "enabled")
y1 = b1.check(16, y1, "Lock position", "Disable frame dragging", "locked")
y1 = b1.check(16, y1, "Group loot", "Show items looted by other players", "showGroupLoot")
y1 = b1.check(16, y1, "Money", "Show rows for received money", "showMoney")
y1 = b1.check(16, y1, "Session total", "Total money received under the feed", "showSessionTotal")
y1 = b1.check(16, y1, "Sell price", "Sell Price from GetItemInfo (since patch 3.2)", "showSellPrice")
y1 = b1.check(16, y1, "Item level", "Item level for equippable items", "showIlvl")
y1 = b1.check(16, y1, "Quest marker !", "Scan the tooltip for the quest item line", "showQuestMark")
y1 = b1.check(16, y1, "Rarity border on icon", "Icon border color = item quality color", "iconRarityBorder")
y1 = b1.check(16, y1, "Rarity border on frame", "Frame border follows the latest item quality", "frameRarityBorder")

local y2 = -76
y2 = b1.slider(220, y2, "Width", "width", 200, 500, 10, "%d")
y2 = b1.slider(220, y2, "Row height", "rowHeight", 18, 40, 1, "%d")
y2 = b1.slider(220, y2, "Max rows", "maxRows", 1, 12, 1, "%d")
y2 = b1.slider(220, y2, "Duration", "duration", 2, 15, 0.5, "%.1f s")
y2 = b1.slider(220, y2, "Background opacity", "bgAlpha", 0, 1, 0.05, "%.2f")
y2 = b1.slider(220, y2, "Border thickness", "borderSize", 0, 4, 1, "%d px")
y2 = b1.slider(220, y2, "Font size", "fontSize", 8, 20, 1, "%d")

local y3 = -76
y3 = b1.cycle(424, y3, "Growth", "growUp", { false, true }, { "Down", "Up" })
y3 = b1.cycle(424, y3, "Font", "font",
  { "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF", "Fonts\\MORPHEUS.TTF", "Fonts\\SKURRI.TTF" },
  { "Friz", "Arial Narrow", "Morpheus", "Skurri" })
y3 = b1.cycle(424, y3, "Outline", "fontOutline", { "", "OUTLINE", "THICKOUTLINE" }, { "None", "Thin", "Thick" })
y3 = b1.button(424, y3, "Preview", function() API.Preview() end)
y3 = b1.button(424, y3, "Move feed", function()
  API.ToggleMove()
end)
y3 = b1.button(424, y3, "Reset position", function() API.ResetPos() end)

-- ---- Panel 2: minimap, sounds, price DB ----
local alerts = makePanel("CoA Loot Feed - Alerts & Prices",
  "Minimap, sounds, prices.")
local b2 = newBuilder(alerts, "ULF335A")

local a1 = -76
a1 = b2.check(16, a1, "Minimap icon", "Show the draggable minimap button", "minimapShown")
a1 = b2.check(16, a1, "Sound alerts", "Play a sound for rare loot and large money gains", "soundEnabled")
a1 = b2.check(16, a1, "Show custom price", "Show a saved price from the price DB on the row", "showPrice")
a1 = b2.check(16, a1, "Auction price (Auctionator)", "Show Atr_GetAuctionPrice from Auctionator 2.6.8 when installed", "showAuctionPrice")
a1 = b2.check(16, a1, "Details line", "Second line under the name: ilvl, slot, item type", "showSubText")

local a2 = -76
a2 = b2.slider(220, a2, "Min item quality", "soundQuality", 0, 5, 1, "%d")
a2 = b2.slider(220, a2, "Min money (gold)", "soundMoneyGold", 0, 1000, 1, "%d g")
a2 = b2.slider(220, a2, "Fade in (s)", "fadeIn", 0, 2, 0.05, "%.2f s")
a2 = b2.slider(220, a2, "Fade out (s)", "fadeOut", 0, 2, 0.05, "%.2f s")
a2 = b2.slider(220, a2, "Icon size", "iconSize", 20, 64, 1, "%d px")

local a3 = -76
a3 = b2.cycle(424, a3, "Sound", "soundName", API.SoundNames,
  { "Coins", "Quest", "Tell", "Raid", "Rewards" })
a3 = b2.button(424, a3, "Test sound", function() PlaySound(API.db.soundName) end)
a3 = b2.button(424, a3, "Clear price DB", function() API.ClearPrices() end)

local help1 = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
help1:SetPoint("TOPLEFT", alerts, "TOPLEFT", 16, -300)
help1:SetText("Price DB (saved account-wide):")

local help2 = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
help2:SetPoint("TOPLEFT", alerts, "TOPLEFT", 16, -320)
help2:SetText("/ulf price <itemID or shift-clicked link> 12g34s56c")

local help3 = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
help3:SetPoint("TOPLEFT", alerts, "TOPLEFT", 16, -340)
help3:SetText("/ulf price <itemID> 0 - remove  |  /ulf prices - list")

-- ---- Panel 3: timings, price source, highlighting ----
local timings = makePanel("CoA Loot Feed - Timings",
  "Duration by quality, price source and highlighting.")
local b3 = newBuilder(timings, "ULF335T")

local t1 = -76
t1 = b3.check(16, t1, "Quality-based duration", "Separate display time for each item quality", "useQualityDuration")
t1 = b3.check(16, t1, "Stack price", "Multiply the price by the looted stack size", "showStackPrice")
t1 = b3.check(16, t1, "Highlight expensive", "Colour the price label above the thresholds", "highlightEnabled")
t1 = b3.check(16, t1, "Price labels", "Show Auction: / Sell Price: captions above the values", "priceLabels")

local t2 = -76
t2 = b3.slider(220, t2, "Poor (s)", "qualityDurations.1", 1, 60, 1, "%d")
t2 = b3.slider(220, t2, "Common (s)", "qualityDurations.2", 1, 60, 1, "%d")
t2 = b3.slider(220, t2, "Uncommon (s)", "qualityDurations.3", 1, 60, 1, "%d")
t2 = b3.slider(220, t2, "Rare (s)", "qualityDurations.4", 1, 60, 1, "%d")
t2 = b3.slider(220, t2, "Epic (s)", "qualityDurations.5", 1, 60, 1, "%d")
t2 = b3.slider(220, t2, "Legendary (s)", "qualityDurations.6", 1, 60, 1, "%d")

local t3 = -76
t3 = b3.cycle(424, t3, "Price source", "priceSource", { "both", "vendor", "auction" }, { "Both", "Vendor", "Auction" })
t3 = b3.slider(424, t3, "Max name length", "maxNameLength", 10, 80, 1, "%d")
t3 = b3.slider(424, t3, "Highlight T1 (g)", "highlightT1", 0, 100, 1, "%d g")
t3 = b3.slider(424, t3, "Highlight T2 (g)", "highlightT2", 0, 1000, 1, "%d g")
t3 = b3.cycle(424, t3, "Coins", "coinStyle", { "compact", "coins", "words" }, { "1g 85s", "Icons", "Words" })

local function refreshAll()
  b1.refresh()
  b2.refresh()
  b3.refresh()
end

main.refresh = refreshAll
alerts.refresh = refreshAll
timings.refresh = refreshAll
local function resetAll()
  API.ResetAll()
  refreshAll()
end
main.default = resetAll
alerts.default = resetAll
timings.default = resetAll

InterfaceOptions_AddCategory(main)
InterfaceOptions_AddCategory(alerts)
InterfaceOptions_AddCategory(timings)

local function OpenOptions(which)
  local target = (which == "alerts" and alerts) or (which == "timings" and timings) or main
  InterfaceOptionsFrame_OpenToCategory(target)
  InterfaceOptionsFrame_OpenToCategory(target)
end
API.OpenOptions = OpenOptions

local function handleCommand(msg)
  msg = string.lower(msg or "")
  msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if cmd == "preview" then
    API.Preview()
  elseif cmd == "move" then
    API.ToggleMove()
  elseif cmd == "reset" then
    API.ResetPos()
  elseif cmd == "money" then
    API.Print("Money Earned: " .. API.FormatMoney(API.GetSession()))
  elseif cmd == "alerts" then
    OpenOptions("alerts")
  elseif cmd == "timings" then
    OpenOptions("timings")
  elseif cmd == "price" then
    -- Split at the LAST space: item links can contain spaces in the item name.
    local idStr, valueStr = rest:match("^(.+)%s+(%S+)$")
    if not idStr then idStr = rest end
    idStr = idStr:gsub("^%s+", ""):gsub("%s+$", "")
    API.SetPrice(idStr, valueStr)
  elseif cmd == "prices" then
    API.ListPrices()
  elseif cmd == "help" or cmd == "?" then
    API.Print("/coalf - options; /coalf alerts - sounds, minimap; /coalf timings - durations, price source; /coalf preview - demo; /coalf move - drag; /coalf price <item> 12g34s - set price; /coalf prices - list prices")
  else
    OpenOptions()
  end
end

SLASH_COALF1 = "/coalf"
SLASH_COALF2 = "/coalfeed"
SlashCmdList["COALF"] = handleCommand
-- Old commands kept as aliases so existing users do not lose their workflow.
SLASH_ULF3351 = "/ulf"
SLASH_ULF3352 = "/ulf335"
SlashCmdList["ULF335"] = handleCommand

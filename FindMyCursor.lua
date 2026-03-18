-- FindMyCursor
-- Highlights the cursor during combat.

local ADDON_NAME = "FindMyCursor"

local DEFAULTS = {
    size            = 35,
    alpha           = 0.95,
    pulseSpeed      = 2.20,
    gradient        = 0.30,
    color           = { r = 1, g = 1, b = 1, a = 1 },
    triggerCombat   = true,
    triggerAlways   = false,
    triggerInstance = false,
    triggerMap      = false,
}

-- Live settings (replaced by FindMyCursorDB after ADDON_LOADED)
local db = {
    size            = DEFAULTS.size,
    alpha           = DEFAULTS.alpha,
    pulseSpeed      = DEFAULTS.pulseSpeed,
    gradient        = DEFAULTS.gradient,
    color           = { r = DEFAULTS.color.r, g = DEFAULTS.color.g, b = DEFAULTS.color.b, a = 1 },
    triggerCombat   = DEFAULTS.triggerCombat,
    triggerAlways   = DEFAULTS.triggerAlways,
    triggerInstance = DEFAULTS.triggerInstance,
    triggerMap      = DEFAULTS.triggerMap,
}

FindMyCursorDB = FindMyCursorDB or {}

-------------------------------------------------------------------------------
-- Cursor indicator
-------------------------------------------------------------------------------
local indicator = CreateFrame("Frame", "FindMyCursorIndicator", UIParent)
indicator:SetFrameStrata("TOOLTIP")
indicator:SetSize(db.size, db.size)
indicator:Hide()

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local NUM_LAYERS = 10

local glowLayers = {}
for i = 1, NUM_LAYERS do
    local t = indicator:CreateTexture(nil, "ARTWORK")
    t:SetPoint("CENTER", indicator, "CENTER")
    t:SetTexture(CIRCLE)
    t:SetBlendMode("ADD")
    glowLayers[i] = t
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local isActive    = false
local inCombat    = false
local inInstance  = false
local mapOpen     = false
local testMode    = false
local pulseElapsed = 0

local function UpdateVisibility()
    local should = testMode
        or db.triggerAlways
        or (db.triggerCombat   and inCombat)
        or (db.triggerInstance and inInstance)
        or (db.triggerMap      and mapOpen)
    if should == isActive then return end
    isActive = should
    if isActive then indicator:Show() else indicator:Hide() end
end

local updateSwatchColor  -- set when the settings panel is built
local panelRefreshFns = {}  -- keyed by setting name; called after a reset

local function ApplyColor()
    local r = db.color.r / NUM_LAYERS
    local g = db.color.g / NUM_LAYERS
    local b = db.color.b / NUM_LAYERS
    for _, t in ipairs(glowLayers) do
        t:SetVertexColor(r, g, b, 1)
    end
    if updateSwatchColor then updateSwatchColor() end
end

-------------------------------------------------------------------------------
-- OnUpdate — track cursor and pulse
-------------------------------------------------------------------------------
indicator:SetScript("OnUpdate", function(self, elapsed)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    self:SetSize(db.size, db.size)

    for i, t in ipairs(glowLayers) do
        local f = (i - 1) / (NUM_LAYERS - 1)  -- 0 = outermost, 1 = innermost
        local layerSize = math.max(2, db.size * (1 - f * db.gradient))
        t:SetSize(layerSize, layerSize)
    end

    if db.pulseSpeed > 0 then
        pulseElapsed = pulseElapsed + elapsed
        local pulse = 0.5 + 0.5 * math.sin(pulseElapsed * db.pulseSpeed * math.pi * 2)
        self:SetAlpha(db.alpha * (0.5 + 0.5 * pulse))
    else
        self:SetAlpha(db.alpha)
    end
end)

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Merge saved vars over defaults
        for k, v in pairs(db) do
            if FindMyCursorDB[k] == nil then
                FindMyCursorDB[k] = v
            end
        end
        db = FindMyCursorDB
        ApplyColor()

        WorldMapFrame:HookScript("OnShow", function() mapOpen = true;  UpdateVisibility() end)
        WorldMapFrame:HookScript("OnHide", function() mapOpen = false; UpdateVisibility() end)

        RegisterSettingsPanel()

        print("|cff00ccff[FindMyCursor]|r Loaded. |cffffff00/fmc options|r  or  Escape > Options > AddOns")

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true;  UpdateVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false; UpdateVisibility()
    elseif event == "UPDATE_INSTANCE_INFO" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        local inInst, instType = IsInInstance()
        inInstance = inInst or (instType ~= nil and instType ~= "none")
        UpdateVisibility()
    end
end)

-------------------------------------------------------------------------------
-- WoW Settings panel  (Escape > Options > AddOns > FindMyCursor)
-------------------------------------------------------------------------------
local settingsCategory

function RegisterSettingsPanel()
    local panel = CreateFrame("Frame")
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(ADDON_NAME)

    local sliderDefs = {
        { name = "Ring Size",   key = "size",       min = 20, max = 200, step = 1,    low = "20",         high = "200",  fmt = function(v) return string.format("%.0f px", v) end },
        { name = "Opacity",     key = "alpha",      min = 0,  max = 1,   step = 0.01, low = "0%",         high = "100%", fmt = function(v) return string.format("%.0f%%", v * 100) end },
        { name = "Pulse Speed", key = "pulseSpeed", min = 0,  max = 4,   step = 0.05, low = "0 (steady)", high = "4",   fmt = function(v) return string.format("%.2f", v) end },
        { name = "Gradient",    key = "gradient",   min = 0,  max = 1,   step = 0.01, low = "Edge",       high = "Center", fmt = function(v) return string.format("%.0f%%", v * 100) end },
    }

    local previewBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewBtn:SetSize(120, 24)
    previewBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        testMode = not testMode
        UpdateVisibility()
        previewBtn:SetText(testMode and "Stop Preview" or "Preview")
    end)
    previewBtn:SetScript("OnShow", function()
        previewBtn:SetText(testMode and "Stop Preview" or "Preview")
    end)

    local lastItem = title
    for _, entry in ipairs(sliderDefs) do
        local wrapper = CreateFrame("Frame", nil, panel)
        wrapper:SetPoint("TOPLEFT", lastItem, "BOTTOMLEFT", 0, -20)
        wrapper:SetPoint("RIGHT", panel)
        wrapper:SetHeight(55)

        local label = wrapper:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 30, 0)
        label:SetText(entry.name)

        local slider = CreateFrame("Slider", nil, wrapper, "UISliderTemplate")
        slider:SetHeight(20)
        slider:SetPoint("LEFT", wrapper, "LEFT", 30, -10)
        slider:SetPoint("RIGHT", wrapper, "RIGHT", -30, -10)
        slider:SetMinMaxValues(entry.min, entry.max)
        slider:SetValueStep(entry.step)
        slider:SetObeyStepOnDrag(true)

        local lowText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT")
        lowText:SetText(entry.low)

        local highText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT")
        highText:SetText(entry.high)

        local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        valueText:SetPoint("BOTTOM", slider, "TOP")

        local key = entry.key
        local fmt = entry.fmt
        slider:HookScript("OnValueChanged", function(self, value, userInput)
            if not userInput then return end
            db[key] = value
            valueText:SetText(fmt(value))
        end)
        slider:HookScript("OnShow", function(self)
            self:SetValue(db[key])
            valueText:SetText(fmt(db[key]))
        end)

        panelRefreshFns[key] = function()
            slider:SetValue(db[key])
            valueText:SetText(fmt(db[key]))
        end

        lastItem = wrapper
    end

    -- Color row
    local colorRow = CreateFrame("Frame", nil, panel)
    colorRow:SetPoint("TOPLEFT", lastItem, "BOTTOMLEFT", 0, -20)
    colorRow:SetPoint("RIGHT", panel)
    colorRow:SetHeight(30)

    local colorLabel = colorRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    colorLabel:SetPoint("LEFT", colorRow, "LEFT", 30, 0)
    colorLabel:SetText("Ring Color")

    local swatch = CreateFrame("Button", nil, colorRow, "BackdropTemplate")
    swatch:SetSize(24, 24)
    swatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropColor(db.color.r, db.color.g, db.color.b, 1)
    swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    updateSwatchColor = function()
        swatch:SetBackdropColor(db.color.r, db.color.g, db.color.b, 1)
    end

    swatch:SetScript("OnClick", function()
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                db.color = { r = r, g = g, b = b, a = 1 }
                ApplyColor()
            end,
            cancelFunc = function(prev)
                db.color = { r = prev.r, g = prev.g, b = prev.b, a = 1 }
                ApplyColor()
            end,
            hasOpacity = false,
            r = db.color.r,
            g = db.color.g,
            b = db.color.b,
        })
    end)

    -- "Activate When" section
    local activateHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    activateHeader:SetPoint("TOPLEFT", colorRow, "BOTTOMLEFT", 30, -20)
    activateHeader:SetText("Activate When")

    local checkDefs = {
        { key = "triggerCombat",   label = "In Combat",     col = 0, row = 0 },
        { key = "triggerAlways",   label = "Always",        col = 1, row = 0 },
        { key = "triggerInstance", label = "In Instances",  col = 0, row = 1 },
        { key = "triggerMap",      label = "On World Map",  col = 1, row = 1 },
    }

    for _, entry in ipairs(checkDefs) do
        local xOff = entry.col * 180
        local yOff = -8 - entry.row * 26

        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", activateHeader, "BOTTOMLEFT", xOff, yOff)
        cb:SetChecked(db[entry.key])

        local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(entry.label)

        local key = entry.key
        cb:SetScript("OnClick", function(self)
            db[key] = not not self:GetChecked()
            UpdateVisibility()
        end)

        panelRefreshFns[key] = function()
            cb:SetChecked(db[key])
        end
    end

    -- invisible spacer so Reset button anchors below the 2-row checkbox grid
    local checksSpacer = CreateFrame("Frame", nil, panel)
    checksSpacer:SetPoint("TOPLEFT", activateHeader, "BOTTOMLEFT", 0, -8 - 2 * 26)
    checksSpacer:SetSize(1, 1)

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("TOPLEFT", checksSpacer, "BOTTOMLEFT", 0, -12)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("FINDMYCURSOR_RESET")
    end)

    panel.OnCommit  = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function() end

    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
    Settings.RegisterAddOnCategory(settingsCategory)

    -- Hide the Defaults button when our category is active
    if SettingsPanel and SettingsPanel.Defaults then
        hooksecurefunc(SettingsPanel, "SetCurrentCategory", function(self, cat)
            self.Defaults:SetShown(cat ~= settingsCategory)
        end)
    end
end

local function ShowOptions()
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

-------------------------------------------------------------------------------
-- Reset confirmation dialog
-------------------------------------------------------------------------------
StaticPopupDialogs["FINDMYCURSOR_RESET"] = {
    text = "Reset FindMyCursor settings to defaults?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        db.size            = DEFAULTS.size
        db.alpha           = DEFAULTS.alpha
        db.pulseSpeed      = DEFAULTS.pulseSpeed
        db.gradient        = DEFAULTS.gradient
        db.color           = { r = DEFAULTS.color.r, g = DEFAULTS.color.g, b = DEFAULTS.color.b, a = 1 }
        db.triggerCombat   = DEFAULTS.triggerCombat
        db.triggerAlways   = DEFAULTS.triggerAlways
        db.triggerInstance = DEFAULTS.triggerInstance
        db.triggerMap      = DEFAULTS.triggerMap
        ApplyColor()
        UpdateVisibility()
        for _, fn in pairs(panelRefreshFns) do fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-------------------------------------------------------------------------------
-- Slash commands:  /fmc  or  /findmycursor
-------------------------------------------------------------------------------
SLASH_FINDMYCURSOR1 = "/fmc"
SLASH_FINDMYCURSOR2 = "/findmycursor"

SlashCmdList["FINDMYCURSOR"] = function(msg)
    local cmd, a, b, c = (msg or ""):match("^(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
    cmd = cmd:lower()

    if cmd == "options" or cmd == "opt" then
        ShowOptions()

    elseif cmd == "size" then
        local v = tonumber(a)
        if v and v > 0 then
            db.size = v
            print("|cff00ccff[FindMyCursor]|r size = " .. v)
        else
            print("|cff00ccff[FindMyCursor]|r Usage: /fmc size <number>")
        end

    elseif cmd == "alpha" then
        local v = tonumber(a)
        if v and v >= 0 and v <= 1 then
            db.alpha = v
            print("|cff00ccff[FindMyCursor]|r alpha = " .. v)
        else
            print("|cff00ccff[FindMyCursor]|r Usage: /fmc alpha <0-1>")
        end

    elseif cmd == "pulse" then
        local v = tonumber(a)
        if v and v >= 0 then
            db.pulseSpeed = v
            pulseElapsed  = 0
            print("|cff00ccff[FindMyCursor]|r pulse = " .. v)
        else
            print("|cff00ccff[FindMyCursor]|r Usage: /fmc pulse <speed>  (0 = steady)")
        end

    elseif cmd == "color" then
        local r, g, _b = tonumber(a), tonumber(b), tonumber(c)
        if r and g and _b then
            db.color = { r = r, g = g, b = _b, a = 1 }
            ApplyColor()
            print(string.format("|cff00ccff[FindMyCursor]|r color = %.2f %.2f %.2f", r, g, _b))
        else
            print("|cff00ccff[FindMyCursor]|r Usage: /fmc color <r> <g> <b>  (0-1 each)")
        end

    elseif cmd == "debug" then
        local inInst, instType = IsInInstance()
        print(string.format("|cff00ccff[FMC]|r IsInInstance: %s  type: %s", tostring(inInst), tostring(instType)))
        print(string.format("  cached: inInstance=%s  inCombat=%s  mapOpen=%s  testMode=%s  isActive=%s",
            tostring(inInstance), tostring(inCombat), tostring(mapOpen), tostring(testMode), tostring(isActive)))
        print(string.format("  triggers: combat=%s  always=%s  instance=%s  map=%s",
            tostring(db.triggerCombat), tostring(db.triggerAlways), tostring(db.triggerInstance), tostring(db.triggerMap)))

    elseif cmd == "test" then
        testMode = not testMode
        UpdateVisibility()
        print("|cff00ccff[FindMyCursor]|r test mode " .. (testMode and "ON" or "OFF"))

    else
        -- default: show status
        print(string.format("|cff00ccff[FindMyCursor]|r  size=%.0f  alpha=%.0f%%  pulse=%.2f  active=%s",
            db.size, db.alpha * 100, db.pulseSpeed, tostring(isActive)))
        print("  Commands: options, size, alpha, pulse, color, test")
    end
end

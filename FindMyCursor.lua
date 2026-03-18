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
    triggerLocate   = true,
    mapRingSize     = 50,
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
    triggerLocate   = DEFAULTS.triggerLocate,
    mapRingSize     = DEFAULTS.mapRingSize,
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
local pulseElapsed         = 0
local mapPulseElapsed      = 0
local mapRingUpdateElapsed = 0

-- Map ring (created in ADDON_LOADED once WorldMapFrame is ready)
local mapRing
local mapRingLayers = {}

local function UpdateMapRing()
    if mapRing then
        if db.triggerLocate and mapOpen then mapRing:Show() else mapRing:Hide() end
    end
end

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
    if #mapRingLayers > 0 then
        local n = #mapRingLayers
        for _, t in ipairs(mapRingLayers) do
            t:SetVertexColor(db.color.r / n, db.color.g / n, db.color.b / n, 1)
        end
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

        -- Map position ring
        local canvas = WorldMapFrame.ScrollContainer:GetScrollChild()
        mapRing = CreateFrame("Frame", nil, canvas)
        mapRing:SetSize(db.mapRingSize, db.mapRingSize)
        mapRing:Hide()

        -- Three concentric circles using TempPortraitAlphaMask (guaranteed centered)
        -- Sizes: 100%, 70%, 40% of mapRingSize → bright center, dimmer edge
        local MAP_NUM_LAYERS = 3
        for i = 1, MAP_NUM_LAYERS do
            local t = mapRing:CreateTexture(nil, "OVERLAY")
            t:SetPoint("CENTER", mapRing, "CENTER")
            t:SetTexture(CIRCLE)
            t:SetBlendMode("ADD")
            mapRingLayers[i] = t
        end
        ApplyColor()

        mapRing:SetScript("OnUpdate", function(self, elapsed)
            mapPulseElapsed      = mapPulseElapsed + elapsed
            mapRingUpdateElapsed = mapRingUpdateElapsed + elapsed

            if mapRingUpdateElapsed >= 0.05 then
                mapRingUpdateElapsed = 0
                local mapID = WorldMapFrame:GetMapID()
                if mapID then
                    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
                    if pos then
                        local x, y = pos:GetXY()
                        local cw, ch = canvas:GetWidth(), canvas:GetHeight()
                        if cw > 0 then
                            self:ClearAllPoints()
                            self:SetPoint("CENTER", canvas, "TOPLEFT", x * cw, -y * ch)
                        end
                    end
                end
                -- Normalize by effective scale so the ring stays the same screen
                -- size whether the map is normal or maximized.
                local ringCanvasSize = db.mapRingSize * UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
                self:SetSize(ringCanvasSize, ringCanvasSize)
                -- Layer sizes: 100%, 70%, 40% — bright center, dimmer edge
                local scales = { 1.0, 0.7, 0.4 }
                for i, t in ipairs(mapRingLayers) do
                    local s = scales[i] or 0.4
                    t:SetSize(ringCanvasSize * s, ringCanvasSize * s)
                end
            end

            if db.pulseSpeed > 0 then
                local pulse = 0.5 + 0.5 * math.sin(mapPulseElapsed * db.pulseSpeed * math.pi * 2)
                self:SetAlpha(db.alpha * (0.5 + 0.5 * pulse))
            else
                self:SetAlpha(db.alpha)
            end
        end)

        WorldMapFrame:HookScript("OnShow", function() mapOpen = true;  UpdateVisibility(); UpdateMapRing() end)
        WorldMapFrame:HookScript("OnHide", function() mapOpen = false; UpdateVisibility(); UpdateMapRing() end)

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

    -- Scrollable content area
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 900)
    scrollFrame:SetScrollChild(content)
    scrollFrame:HookScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    title:SetText(ADDON_NAME)

    local sliderDefs = {
        { name = "Ring Size",   key = "size",       min = 20, max = 200, step = 1,    low = "20",         high = "200",    fmt = function(v) return string.format("%.0f px", v) end },
        { name = "Opacity",     key = "alpha",      min = 0,  max = 1,   step = 0.01, low = "0%",         high = "100%",   fmt = function(v) return string.format("%.0f%%", v * 100) end },
        { name = "Pulse Speed", key = "pulseSpeed", min = 0,  max = 4,   step = 0.05, low = "0 (steady)", high = "4",      fmt = function(v) return string.format("%.2f", v) end },
        { name = "Gradient",    key = "gradient",   min = 0,  max = 1,   step = 0.01, low = "Edge",       high = "Center", fmt = function(v) return string.format("%.0f%%", v * 100) end },
    }

    local previewBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    previewBtn:SetSize(120, 24)
    previewBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -16)
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
        local wrapper = CreateFrame("Frame", nil, content)
        wrapper:SetPoint("TOPLEFT", lastItem, "BOTTOMLEFT", 0, -20)
        wrapper:SetPoint("RIGHT", content)
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
    local colorRow = CreateFrame("Frame", nil, content)
    colorRow:SetPoint("TOPLEFT", lastItem, "BOTTOMLEFT", 0, -20)
    colorRow:SetPoint("RIGHT", content)
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
    local activateHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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

        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", activateHeader, "BOTTOMLEFT", xOff, yOff)
        cb:SetChecked(db[entry.key])

        local lbl = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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

    -- invisible spacer so Map Position section anchors below the 2-row checkbox grid
    local checksSpacer = CreateFrame("Frame", nil, content)
    checksSpacer:SetPoint("TOPLEFT", activateHeader, "BOTTOMLEFT", 0, -8 - 2 * 26)
    checksSpacer:SetSize(1, 1)

    -- "Map Position" section
    local mapHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    mapHeader:SetPoint("TOPLEFT", checksSpacer, "BOTTOMLEFT", 0, -20)
    mapHeader:SetText("Map Position")

    local locateCb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    locateCb:SetSize(20, 20)
    locateCb:SetPoint("TOPLEFT", mapHeader, "BOTTOMLEFT", 0, -8)
    locateCb:SetChecked(db.triggerLocate)
    local locateLbl = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    locateLbl:SetPoint("LEFT", locateCb, "RIGHT", 2, 0)
    locateLbl:SetText("Locate My Position")
    locateCb:SetScript("OnClick", function(self)
        db.triggerLocate = not not self:GetChecked()
        UpdateMapRing()
    end)
    panelRefreshFns["triggerLocate"] = function() locateCb:SetChecked(db.triggerLocate) end

    local mapSizeWrapper = CreateFrame("Frame", nil, content)
    mapSizeWrapper:SetPoint("TOPLEFT", locateCb, "BOTTOMLEFT", 0, -15)
    mapSizeWrapper:SetPoint("RIGHT", content)
    mapSizeWrapper:SetHeight(55)

    local mapSizeLabel = mapSizeWrapper:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    mapSizeLabel:SetPoint("TOPLEFT", mapSizeWrapper, "TOPLEFT", 30, 0)
    mapSizeLabel:SetText("Map Ring Size")

    local mapSizeSlider = CreateFrame("Slider", nil, mapSizeWrapper, "UISliderTemplate")
    mapSizeSlider:SetHeight(20)
    mapSizeSlider:SetPoint("LEFT", mapSizeWrapper, "LEFT", 30, -10)
    mapSizeSlider:SetPoint("RIGHT", mapSizeWrapper, "RIGHT", -30, -10)
    mapSizeSlider:SetMinMaxValues(50, 200)
    mapSizeSlider:SetValueStep(1)
    mapSizeSlider:SetObeyStepOnDrag(true)

    local mapSizeLow = mapSizeSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mapSizeLow:SetPoint("TOPLEFT", mapSizeSlider, "BOTTOMLEFT")
    mapSizeLow:SetText("50")
    local mapSizeHigh = mapSizeSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mapSizeHigh:SetPoint("TOPRIGHT", mapSizeSlider, "BOTTOMRIGHT")
    mapSizeHigh:SetText("200")
    local mapSizeVal = mapSizeSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    mapSizeVal:SetPoint("BOTTOM", mapSizeSlider, "TOP")

    mapSizeSlider:HookScript("OnValueChanged", function(self, value, userInput)
        if not userInput then return end
        db.mapRingSize = value
        mapSizeVal:SetText(string.format("%.0f px", value))
    end)
    mapSizeSlider:HookScript("OnShow", function(self)
        self:SetValue(db.mapRingSize)
        mapSizeVal:SetText(string.format("%.0f px", db.mapRingSize))
    end)
    panelRefreshFns["mapRingSize"] = function()
        mapSizeSlider:SetValue(db.mapRingSize)
        mapSizeVal:SetText(string.format("%.0f px", db.mapRingSize))
    end

    local mapSpacer = CreateFrame("Frame", nil, content)
    mapSpacer:SetPoint("TOPLEFT", mapSizeWrapper, "BOTTOMLEFT")
    mapSpacer:SetSize(1, 1)

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("TOPLEFT", mapSpacer, "BOTTOMLEFT", 0, -20)
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
        db.triggerLocate   = DEFAULTS.triggerLocate
        db.mapRingSize     = DEFAULTS.mapRingSize
        ApplyColor()
        UpdateVisibility()
        UpdateMapRing()
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

    elseif cmd == "on" then
        testMode = true
        UpdateVisibility()
        print("|cff00ccff[FindMyCursor]|r forced ON")
    elseif cmd == "off" then
        testMode = false
        UpdateVisibility()
        print("|cff00ccff[FindMyCursor]|r forced OFF")

    else
        -- default: show status
        print(string.format("|cff00ccff[FindMyCursor]|r  size=%.0f  alpha=%.0f%%  pulse=%.2f  active=%s",
            db.size, db.alpha * 100, db.pulseSpeed, tostring(isActive)))
        print("  Commands: options, size, alpha, pulse, color, on, off")
    end
end

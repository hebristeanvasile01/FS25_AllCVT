-- All CVT: every vehicle with a manual / powershift gearbox gets a CVT automatic transmission.
-- Author: FS Modding
AllCVT = {}
AllCVT.converted = 0
AllCVT.logged = {}
AllCVT.DEFAULT_ON = true        -- vehicles you never switched: CVT on (cvtDefault on/off)

local function logOnce(key, text, ...)
    if AllCVT.logged[key] then return end
    AllCVT.logged[key] = true
    Logging.info("[AllCVT] " .. text, ...)
end

local function keysOf(t)
    local parts = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "number" or tv == "boolean" or tv == "string" then
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        else
            table.insert(parts, tostring(k) .. "=" .. tv)
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- the ratio of one gear (FS stores it as ratio)
local function gearRatio(g)
    if type(g) == "number" then return g end
    if type(g) == "table" then return g.ratio or g.gearRatio end
    return nil
end

-- smallest and largest ratio of a gear list, with the gear groups (ranges)
local function ratioRange(gears, groups)
    local lo, hi = nil, nil
    local gMin, gMax = 1, 1
    if type(groups) == "table" and #groups > 0 then
        gMin, gMax = nil, nil
        for _, grp in ipairs(groups) do
            local r = gearRatio(grp)
            if r ~= nil and r > 0 then
                gMin = gMin == nil and r or math.min(gMin, r)
                gMax = gMax == nil and r or math.max(gMax, r)
            end
        end
        gMin, gMax = gMin or 1, gMax or 1
    end
    for _, g in ipairs(gears) do
        local r = gearRatio(g)
        if r ~= nil then
            r = math.abs(r)
            if r > 0 then
                lo = lo == nil and r or math.min(lo, r)
                hi = hi == nil and r or math.max(hi, r)
            end
        end
    end
    if lo == nil then return nil end
    return lo * gMin, hi * gMax
end

-- back to the original gearbox
function AllCVT:restore(vehicle)
    local spec = vehicle.spec_motorized
    local motor = spec ~= nil and spec.motor or nil
    if motor == nil or not motor.fsCvt or motor.fsCvtGears == nil then return end
    local o = motor.fsCvtGears
    motor.minForwardGearRatio = nil
    motor.maxForwardGearRatio = nil
    motor.minBackwardGearRatio = nil
    motor.maxBackwardGearRatio = nil
    motor.forwardGears = o.forward
    motor.backwardGears = o.backward
    motor.gearGroups = o.groups
    motor.currentGears = o.currentGears
    motor.gear = o.gear
    motor.targetGear = o.targetGear
    motor.previousGear = o.previousGear
    motor.gearRatio = o.gearRatio
    motor.maxForwardSpeed = o.maxForwardSpeed
    motor.maxBackwardSpeed = o.maxBackwardSpeed
    motor.activeGearGroupIndex = o.activeGearGroupIndex
    motor.fsCvt = false
    motor.fsCvtGears = nil
    self.converted = math.max(0, self.converted - 1)
    Logging.info("[AllCVT] %s: original gearbox", vehicle:getName())
end

function AllCVT:convert(vehicle)
    local spec = vehicle.spec_motorized
    local motor = spec ~= nil and spec.motor or nil
    if motor == nil or motor.fsCvt then return end
    if motor.minForwardGearRatio ~= nil then return end           -- already CVT
    local fwd = motor.forwardGears
    if type(fwd) ~= "table" or #fwd == 0 then return end

    logOnce("motor", "motor values (%s): %s", vehicle:getName(), keysOf(motor))
    logOnce("gear", "gear values: %s", type(fwd[1]) == "table" and keysOf(fwd[1]) or tostring(fwd[1]))

    local minF, maxF = ratioRange(fwd, motor.gearGroups)
    if minF == nil then
        logOnce("noratio", "no gear ratio found on %s, not changed", vehicle:getName())
        return
    end
    local minB, maxB = minF, maxF
    if type(motor.backwardGears) == "table" and #motor.backwardGears > 0 then
        local a, b = ratioRange(motor.backwardGears, motor.gearGroups)
        if a ~= nil then minB, maxB = a, b end
    end

    motor.fsCvtGears = {
        forward = motor.forwardGears, backward = motor.backwardGears, groups = motor.gearGroups,
        currentGears = motor.currentGears, gear = motor.gear, targetGear = motor.targetGear,
        previousGear = motor.previousGear, gearRatio = motor.gearRatio,
        maxForwardSpeed = motor.maxForwardSpeed, maxBackwardSpeed = motor.maxBackwardSpeed,
        activeGearGroupIndex = motor.activeGearGroupIndex,
    }
    motor.minForwardGearRatio = minF
    motor.maxForwardGearRatio = maxF
    motor.minBackwardGearRatio = minB
    motor.maxBackwardGearRatio = maxB
    if motor.maxForwardSpeed == nil and motor.maxRpm ~= nil then
        motor.maxForwardSpeed = motor.maxRpm * math.pi / (30 * minF)
    end
    if motor.maxBackwardSpeed == nil and motor.maxRpm ~= nil then
        motor.maxBackwardSpeed = motor.maxRpm * math.pi / (30 * minB)
    end

    motor.forwardGears = nil
    motor.backwardGears = nil
    motor.currentGears = nil
    motor.gearGroups = nil
    motor.gear = 0
    motor.targetGear = 0
    motor.previousGear = 0
    motor.gearRatio = maxF
    motor.fsCvt = true
    self.converted = self.converted + 1
    Logging.info("[AllCVT] %s: CVT %.1f - %.1f (forward), %.1f - %.1f (reverse)", vehicle:getName(), minF, maxF, minB, maxB)
end

local function getControlledVehicle()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local v = g_localPlayer:getCurrentVehicle()
        if v ~= nil then return v end
    end
    local m = g_currentMission
    if m ~= nil and m.controlledVehicle ~= nil then return m.controlledVehicle end
    return nil
end
AllCVT.getControlledVehicle = getControlledVehicle

-- ---------------------------------------------------------------- on / off per vehicle, kept in the savegame

local function vehicleKey(vehicle)
    local id = nil
    if vehicle.getUniqueId ~= nil then id = vehicle:getUniqueId() end
    if id == nil then id = vehicle.uniqueId end
    if id ~= nil and id ~= "" then return "id:" .. tostring(id) end
    if vehicle.configFileName ~= nil then return "xml:" .. vehicle.configFileName end
    return nil
end

local function saveFile()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info == nil or info.savegameDirectory == nil then return nil end
    return info.savegameDirectory .. "/allCVT.xml"
end

local function settingsFile()
    if getUserProfileAppPath == nil then return nil end
    return getUserProfileAppPath() .. "modSettings/FS25_AllCVT.xml"
end

function AllCVT:loadSaved()
    self.saved = {}
    local path = settingsFile()
    if path ~= nil and fileExists(path) then
        local xml = loadXMLFile("allCVTSettings", path)
        if xml ~= nil and xml ~= 0 then
            local d = getXMLBool(xml, "allCVT#defaultOn")
            if d ~= nil then self.DEFAULT_ON = d end
            delete(xml)
        end
    end
    path = saveFile()
    if path == nil or not fileExists(path) then return end
    local xml = loadXMLFile("allCVT", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local base = string.format("allCVT.vehicle(%d)", i)
        local key = getXMLString(xml, base .. "#key")
        if key == nil then break end
        self.saved[key] = getXMLBool(xml, base .. "#cvt")
        i = i + 1
    end
    delete(xml)
end

function AllCVT:writeSaved()
    if self.saved == nil then return end
    local path = saveFile()
    if path == nil then return end
    local xml = createXMLFile("allCVT", path, "allCVT")
    if xml == nil or xml == 0 then return end
    local i = 0
    for key, on in pairs(self.saved) do
        local base = string.format("allCVT.vehicle(%d)", i)
        setXMLString(xml, base .. "#key", key)
        setXMLBool(xml, base .. "#cvt", on)
        i = i + 1
    end
    saveXMLFile(xml)
    delete(xml)
end

function AllCVT:writeSettings()
    local path = settingsFile()
    if path == nil then return end
    createFolder(getUserProfileAppPath() .. "modSettings/")
    local xml = createXMLFile("allCVTSettings", path, "allCVT")
    if xml == nil or xml == 0 then return end
    setXMLBool(xml, "allCVT#defaultOn", self.DEFAULT_ON)
    saveXMLFile(xml)
    delete(xml)
end

function AllCVT:wantsCvt(vehicle)
    if self.saved == nil then self:loadSaved() end
    local key = vehicleKey(vehicle)
    local v = key ~= nil and self.saved[key] or nil
    if v == nil then return self.DEFAULT_ON end
    return v
end

-- has this vehicle a gearbox we can switch
local function canSwitch(vehicle)
    local spec = vehicle.spec_motorized
    local motor = spec ~= nil and spec.motor or nil
    if motor == nil then return false end
    if motor.fsCvt then return true end
    return motor.minForwardGearRatio == nil and type(motor.forwardGears) == "table" and #motor.forwardGears > 0
end

local function notify(text, ok)
    if g_currentMission == nil then return end
    g_currentMission:addIngameNotification(ok and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_INFO, text)
end

function AllCVT:toggle(vehicle)
    if vehicle == nil or not canSwitch(vehicle) then
        notify(g_i18n:getText("cvt_noGearbox"), false)
        return
    end
    local speed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    if speed > 1 then
        notify(g_i18n:getText("cvt_stopFirst"), false)
        return
    end
    local motor = vehicle.spec_motorized.motor
    local key = vehicleKey(vehicle)
    if motor.fsCvt then
        self:restore(vehicle)
        notify(string.format(g_i18n:getText("cvt_off"), vehicle:getName()), true)
    else
        self:convert(vehicle)
        notify(string.format(g_i18n:getText("cvt_on"), vehicle:getName()), true)
    end
    -- gear keys come back / go away
    if vehicle.requestActionEventUpdate ~= nil then vehicle:requestActionEventUpdate() end
    if key ~= nil then
        if self.saved == nil then self:loadSaved() end
        self.saved[key] = motor.fsCvt == true
        self:writeSaved()
    end
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        AllCVT:writeSaved()
    end)
end

-- key in the vehicle (Alt + G)
function AllCVT.onToggleKey()
    local v = AllCVT.getControlledVehicle()
    if v ~= nil then AllCVT:toggle(v.rootVehicle or v) end
end

if Enterable ~= nil and Enterable.onRegisterActionEvents ~= nil then
    Enterable.onRegisterActionEvents = Utils.appendedFunction(Enterable.onRegisterActionEvents,
        function(vehicle, isActiveForInput, isActiveForInputIgnoreSelection)
            if vehicle.isClient and isActiveForInputIgnoreSelection and InputAction.ALLCVT_TOGGLE ~= nil then
                local spec = vehicle.spec_enterable
                if spec ~= nil and spec.actionEvents ~= nil and canSwitch(vehicle) then
                    local _, id = vehicle:addActionEvent(spec.actionEvents, InputAction.ALLCVT_TOGGLE, AllCVT, AllCVT.onToggleKey, false, true, false, true, nil)
                    if id ~= nil then
                        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_LOW)
                        g_inputBinding:setActionEventTextVisibility(id, true)
                        g_inputBinding:setActionEventText(id, g_i18n:getText("input_ALLCVT_TOGGLE"))
                    end
                end
            end
        end)
end

-- after a vehicle is loaded (also after a new configuration in the shop)
if Motorized ~= nil and Motorized.onPostLoad ~= nil then
    Motorized.onPostLoad = Utils.appendedFunction(Motorized.onPostLoad, function(vehicle, ...)
        if AllCVT:wantsCvt(vehicle) then AllCVT:convert(vehicle) end
    end)
else
    Logging.warning("[AllCVT] Motorized.onPostLoad not found")
end

-- no gear / range shifting on a CVT
if VehicleMotor ~= nil then
    for _, name in ipairs({ "shiftGear", "selectGear", "shiftGroup", "selectGroup" }) do
        if VehicleMotor[name] ~= nil then
            VehicleMotor[name] = Utils.overwrittenFunction(VehicleMotor[name], function(motor, superFunc, ...)
                if motor.fsCvt then return end
                return superFunc(motor, ...)
            end)
        end
    end
end

-- ---------------------------------------------------------------- console


function AllCVT:consoleInfo()
    local v = getControlledVehicle()
    local motor = v ~= nil and v.spec_motorized ~= nil and v.spec_motorized.motor or nil
    if motor == nil then return string.format("%d vehicles changed to CVT. Get in a vehicle for details.", AllCVT.converted) end
    local kind = motor.fsCvt and "CVT (changed by All CVT)" or (motor.minForwardGearRatio ~= nil and "CVT (original)" or "gears")
    return string.format("%s: %s, ratio %.1f - %.1f, now %.2f. %d vehicles changed.", v:getName(), kind,
        motor.minForwardGearRatio or 0, motor.maxForwardGearRatio or 0, motor.gearRatio or 0, AllCVT.converted)
end
addConsoleCommand("cvtInfo", "All CVT: transmission of your vehicle", "consoleInfo", AllCVT)

function AllCVT:consoleDefault(value)
    if value == "on" then AllCVT.DEFAULT_ON = true
    elseif value == "off" then AllCVT.DEFAULT_ON = false end
    AllCVT:writeSettings()
    return string.format("vehicles you never switched: CVT %s (cvtDefault on/off, after a restart)", AllCVT.DEFAULT_ON and "on" or "off")
end
addConsoleCommand("cvtDefault", "All CVT: CVT on or off for vehicles you never switched", "consoleDefault", AllCVT)

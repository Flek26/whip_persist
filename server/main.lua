-- ============================================
-- whip_persist — server: street cars players drove stay, and come back if removed
-- ============================================
--
-- whip_core already keeps owned cars (KeepEntity, and rebuilt after a restart). A street car someone gets into is a
-- whip "session vehicle": kept while a player is within 300 m, then, after ten minutes with nobody near, handed back
-- to GTA (whip_core:vehicle:released, reason 'idle'), which may clean it up.
--
-- This keeps those cars for the session:
--   * TRACKED from whip's own events: a street car registered (someone got in) or entered.
--   * KEPT: set KeepEntity again when whip hands it back for being idle.
--   * BROUGHT BACK when the entity is removed anyway (entityRemoved): built again where it stood, with its model,
--     plate, lock and the look its last driver's game reported (client/main.lua), applied by whoever owns it now.
--   * FORGOTTEN when it is removed on purpose: whip despawned or deleted it (/dv), a player stood right by it
--     (Config.DeliberateRange), another resource called exports.whip_persist:Forget, or it went unused too long.
-- In memory only: a restart starts fresh.

local Tracked = {}      -- [entity] = { model, vehType, plate, props, x, y, z, h, locked, touchedAt, vehicleId }
local byVehicleId = {}  -- [whip vehicleId] = entity
local count = 0

local BLACK = {}
for _, m in ipairs(Config.Blacklist) do BLACK[GetHashKey(m)] = true end

local function log(fmt, ...)
    if Config.Debug then print(('[whip_persist] ' .. fmt):format(...)) end
end

local function note(entity, rec)
    if not DoesEntityExist(entity) then return end
    local c = GetEntityCoords(entity)
    rec.x, rec.y, rec.z, rec.h = c.x, c.y, c.z, GetEntityHeading(entity)
    rec.locked = GetVehicleDoorLockStatus(entity) == 2
    rec.plate = GetVehicleNumberPlateText(entity) or rec.plate
end

--- Stop keeping it. `letGo`: hand it back to GTA as well (it may then be cleaned up).
local function forget(entity, letGo)
    local rec = Tracked[entity]
    if not rec then return false end
    Tracked[entity] = nil
    count = count - 1
    if rec.vehicleId and byVehicleId[rec.vehicleId] == entity then byVehicleId[rec.vehicleId] = nil end
    if letGo and DoesEntityExist(entity) then SetEntityOrphanMode(entity, 0) end
    return true
end

--- The kept car driven longest ago.
local function oldest()
    local best, bestAt
    for entity, rec in pairs(Tracked) do
        if not bestAt or rec.touchedAt < bestAt then best, bestAt = entity, rec.touchedAt end
    end
    return best
end

--- Keep a street car. Owned and temporary cars are whip's, and blacklisted models are never kept.
---@return boolean kept
local function track(entity, vehicleId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
    local rec = Tracked[entity]
    if rec then
        rec.touchedAt = os.time()
        if vehicleId then rec.vehicleId = vehicleId; byVehicleId[vehicleId] = entity end
        return true
    end
    local model = GetEntityModel(entity)
    if BLACK[model] then return false end
    local st = Entity(entity).state
    -- A whip car that is not a session vehicle is owned (or temporary): whip_core keeps those itself.
    if st.whipVehicleId and not st.whipVehicleSession then return false end

    while count >= Config.Max do
        local o = oldest()
        if not o then break end
        forget(o, true)
    end
    rec = { model = model, vehType = GetVehicleType(entity) or 'automobile', touchedAt = os.time(), vehicleId = vehicleId }
    note(entity, rec)
    Tracked[entity] = rec
    count = count + 1
    if vehicleId then byVehicleId[vehicleId] = entity end
    SetEntityOrphanMode(entity, 2)
    return true
end

-- ============================================
-- whip's vehicle events
-- ============================================

--- The entity of a whip street car (not a temporary one: a rental, a job van), or nil.
local function entityOf(vehicleId)
    local def = exports.whip_core:GetVehicle(vehicleId)
    if not def or not def.session or def.temp then return nil end
    return (def.entity and def.entity ~= 0) and def.entity or nil
end

AddEventHandler('whip_core:vehicle:registered', function(e)
    if type(e) ~= 'table' or not e.session or not e.vehicleId then return end
    -- The entity is bound a moment after the record is announced.
    SetTimeout(500, function() track(entityOf(e.vehicleId), e.vehicleId) end)
end)

AddEventHandler('whip_core:vehicle:entered', function(e)
    if type(e) ~= 'table' or not e.vehicleId then return end
    local entity = entityOf(e.vehicleId)
    if entity then track(entity, e.vehicleId) end
end)

-- Handed back to GTA. Idle: keep it ourselves. Put away or deleted on purpose: forget it.
local FORGET_ON = { despawned = true, deleted = true, expired = true, stopped = true, failed = true }
AddEventHandler('whip_core:vehicle:released', function(e)
    if type(e) ~= 'table' or not e.vehicleId then return end
    local entity = byVehicleId[e.vehicleId]
    if not entity then return end
    byVehicleId[e.vehicleId] = nil
    local rec = Tracked[entity]
    if not rec then return end
    rec.vehicleId = nil
    if FORGET_ON[e.reason] then
        forget(entity)
    elseif DoesEntityExist(entity) then
        SetEntityOrphanMode(entity, 2)   -- whip let go of it for being idle; we keep it
    end
end)

-- A street car becoming someone's own (claimed, bought): whip keeps it now.
AddEventHandler('whip_core:vehicle:claimed', function(e)
    if type(e) ~= 'table' or not e.from then return end
    local entity = byVehicleId[e.from]
    if entity then forget(entity) end
end)

-- ============================================
-- The look, from the last driver's game
-- ============================================

Whip.register(function()
    Whip.core:SecureEvent('whip_persist:props', {
        rateLimit = 2000,
        params = { { 'netId', 'int', 1, 65535 }, { 'props', 'any' } },
    }, function(source, _, netId, props)
        if type(props) ~= 'table' then return false end
        local entity = NetworkGetEntityFromNetworkId(netId)
        local rec = Tracked[entity]
        if not rec or not DoesEntityExist(entity) then return end
        if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(entity)) > 15.0 then return false end
        -- A sane size: a look is a few hundred bytes of numbers.
        local ok, encoded = pcall(json.encode, props)
        if not ok or #encoded > 8000 then return false end
        rec.props = props
        rec.touchedAt = os.time()
    end)
end)

-- ============================================
-- Removed anyway: build it again
-- ============================================

local function nearPlayer(at, range)
    if range <= 0 then return false end
    for _, s in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(s)
        if ped ~= 0 and #(GetEntityCoords(ped) - at) <= range then return true end
    end
    return false
end

local function rebuild(rec)
    local veh = CreateVehicleServerSetter(rec.model, rec.vehType, rec.x, rec.y, rec.z, rec.h)
    local deadline = GetGameTimer() + 3000
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() < deadline do Wait(50) end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        print(('[whip_persist] could not bring back a %s at %.1f, %.1f'):format(tostring(rec.model), rec.x, rec.y))
        return
    end
    SetEntityOrphanMode(veh, 2)
    if rec.plate then SetVehicleNumberPlateText(veh, rec.plate) end
    SetVehicleDoorsLocked(veh, rec.locked and 2 or 1)
    if rec.props then Entity(veh).state:set('whipPersistProps', rec.props, true) end

    local new = { model = rec.model, vehType = rec.vehType, plate = rec.plate, props = rec.props, x = rec.x, y = rec.y,
        z = rec.z, h = rec.h, locked = rec.locked, touchedAt = rec.touchedAt }
    Tracked[veh] = new
    count = count + 1
    log('brought back %s (%s)', tostring(rec.plate), tostring(rec.model))
end

AddEventHandler('entityRemoved', function(handle)
    local rec = Tracked[handle]
    if not rec then return end
    -- Where it stood, read now if the game still says.
    pcall(note, handle, rec)
    forget(handle)
    if nearPlayer(vector3(rec.x, rec.y, rec.z), Config.DeliberateRange) then
        log('%s removed next to a player: forgotten', tostring(rec.plate))
        return
    end
    CreateThread(function() rebuild(rec) end)
end)

-- ============================================
-- The sweep: where each stands, and letting go of the long unused
-- ============================================

CreateThread(function()
    while true do
        Wait(Config.SweepSeconds * 1000)
        local now = os.time()
        local stale = {}
        for entity, rec in pairs(Tracked) do
            if DoesEntityExist(entity) then
                note(entity, rec)
                if GetPedInVehicleSeat(entity, -1) ~= 0 then rec.touchedAt = now end
                if Config.ForgetAfterMinutes > 0 and now - rec.touchedAt > Config.ForgetAfterMinutes * 60 then
                    stale[#stale + 1] = entity
                end
            end
        end
        for _, entity in ipairs(stale) do forget(entity, true) end
    end
end)

-- ============================================
-- Exports
-- ============================================

local function resolve(ref)
    ref = tonumber(ref)
    if not ref then return nil end
    if Tracked[ref] then return ref end
    local e = NetworkGetEntityFromNetworkId(ref)
    if e and e ~= 0 then return e end
    return ref
end

--- Stop keeping a car before you delete it, or it comes back: Forget(entityOrNetId, deleteToo).
exports('Forget', function(ref, deleteToo)
    local entity = resolve(ref)
    if not entity then return false end
    local was = forget(entity)
    if deleteToo and DoesEntityExist(entity) then DeleteEntity(entity) end
    return was
end)

--- Keep a car (a street car you spawned for a player, say): Keep(entityOrNetId).
exports('Keep', function(ref) return track(resolve(ref)) end)

--- Is this car kept?
exports('IsKept', function(ref) local e = resolve(ref) return e ~= nil and Tracked[e] ~= nil end)

--- How many are kept now.
exports('Count', function() return count end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- Not ours to keep any more: whip keeps the ones it still tracks; the rest go back to GTA.
    for entity, rec in pairs(Tracked) do
        if not rec.vehicleId and DoesEntityExist(entity) then SetEntityOrphanMode(entity, 0) end
    end
end)

Whip.sayStarted()

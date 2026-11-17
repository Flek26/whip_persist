-- ============================================
-- whip_persist — client: tell the server how a street car looks, and dress one that was brought back
-- ============================================
--
-- The look (mods, colours, wheels, extras) is only readable on a game: the driver's reports it when they get in,
-- every minute while they drive, and when they get out (whip's GetVehicleProperties). A car brought back carries it
-- in a state bag (whipPersistProps); whoever's game owns the car puts it on (only the owner's changes sync).

local function report(veh)
    if veh == 0 or not DoesEntityExist(veh) or not NetworkGetEntityIsNetworked(veh) then return end
    local st = Entity(veh).state
    -- Street cars only: an owned car's look is whip's, from its row.
    if st.whipVehicleId and not st.whipVehicleSession then return end
    local props = exports.whip_core:GetVehicleProperties({ entity = veh })
    if type(props) == 'table' then TriggerServerEvent('whip_persist:props', VehToNet(veh), props) end
end

CreateThread(function()
    local driving, since = 0, 0
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        if isDriver and veh ~= driving then
            -- In: a moment for whip to register it first.
            driving, since = veh, GetGameTimer()
            SetTimeout(2000, function() if driving == veh then report(veh) end end)
        elseif isDriver and GetGameTimer() - since > 60000 then
            since = GetGameTimer()
            report(veh)
        elseif not isDriver and driving ~= 0 then
            -- Out (or slid over): the last look.
            report(driving)
            driving = 0
        end
    end
end)

-- A car brought back: the owner of the entity dresses it.
AddStateBagChangeHandler('whipPersistProps', nil, function(bagName, _, props)
    if type(props) ~= 'table' then return end
    CreateThread(function()
        local deadline = GetGameTimer() + 15000
        while GetGameTimer() < deadline do
            local veh = GetEntityFromStateBagName(bagName)
            if veh ~= 0 and DoesEntityExist(veh) then
                if NetworkGetEntityOwner(veh) == PlayerId() then
                    exports.whip_core:SetVehicleProperties({ entity = veh }, props)
                    return
                end
            end
            Wait(500)
        end
    end)
end)

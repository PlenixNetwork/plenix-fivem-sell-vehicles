lib.locale()

local point, marker = nil, nil
local SellPointBlip = nil

local showPoint = nil
local showingVehicle = 0
local showingVehiclePrice = 0
local showingVehicleId = 0
local showingVehicleOwner = false
local deletingShowingVehicle = false
local loadingCar = false
local sellingCarTextPosition = vector3(0,0,0)

Citizen.CreateThread(function()
    -- 📍 Create Sell Point Blip
    SellPointBlip = AddBlipForCoord(Config.SellPoint.blipPos.x, Config.SellPoint.blipPos.y, Config.SellPoint.blipPos.z)
    SetBlipSprite(SellPointBlip, Config.SellPoint.blipSprite)
    SetBlipDisplay(SellPointBlip, 4)
    SetBlipScale(SellPointBlip, Config.SellPoint.blipScale)
    SetBlipColour(SellPointBlip, Config.SellPoint.blipColor)
    SetBlipAsShortRange(SellPointBlip, Config.SellPoint.blipShortRange)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(locale('blip_name'))
    EndTextCommandSetBlipName(SellPointBlip)

    -- 🎯 Marker Point
    point = lib.points.new({
        coords = Config.SellPoint.markerPos,
        distance = Config.SellPoint.markerShowRadius,
    })

    marker = lib.marker.new({
        type = Config.SellPoint.markerType,
        color = Config.SellPoint.markerColor,
        coords = Config.SellPoint.markerPos,
        width = Config.SellPoint.markerWidth,
        height = Config.SellPoint.markerHeight,
    })

    function point:nearby()
        marker:draw()

        if self.currentDistance <= 1.5 then
            if not lib.isTextUIOpen() then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                    lib.showTextUI(locale('sell_vehicle_prompt'), {
                        position = "top-center"
                    })
                end
            end

            if IsControlJustPressed(0, 51) then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
                    ESX.ShowNotification(locale('sell_vehicle_prompt_notinvehicle'), "error")
                    return
                end

                local vehicleProperties = lib.getVehicleProperties(vehicle)
                lib.hideTextUI()

                local ownsVehicle = lib.callback.await('plenix-sell-vehicles:checkCar', false, vehicle, vehicleProperties.plate)
                if not ownsVehicle then
                    ESX.ShowNotification(locale('sell_vehicle_not_owned'), "error")
                    return
                end

                local money = lib.inputDialog(locale('sell_vehicle_price_prompt_title'), {
                    {type = "number", label = locale('sell_vehicle_price_prompt_text'), icon = "dollar"}
                })
                if not money then return end

                local price = math.floor(tonumber(money[1]) or 0)
                if not price or price <= 0 then
                    ESX.ShowNotification(locale('sell_vehicle_price_invalid'), "error")
                    return
                end

                local success = lib.callback.await('plenix-sell-vehicles:putOnSale', false, price, vehicleProperties)
                if success then
                    local plate = GetVehicleNumberPlateText(vehicle)
                    RemoveVehicleKeys(plate, vehicle) -- 🔑 Remove keys when selling
                    ESX.ShowNotification(locale('sell_vehicle_success', price))
                    ESX.Game.DeleteVehicle(vehicle)
                else
                    ESX.ShowNotification(locale('sell_vehicle_error'), "error")
                end
            end
        else
            if lib.isTextUIOpen() then lib.hideTextUI() end
        end
    end
end)

Citizen.CreateThread(function ()
    showPoint = lib.points.new({
        coords = Config.ViewVehicles.position,
        distance = Config.ViewVehicles.spawnDistance,
    })

    function showPoint:onEnter()
        if deletingShowingVehicle then
            deletingShowingVehicle = false
            return
        end

        if showingVehicle ~= 0 then
            if DoesEntityExist(showingVehicle) then
                DeleteEntity(showingVehicle)
            end
            showingVehicle = 0
            showingVehicleId = 0
        end

        SpawnVehicle(showingVehicleId)
    end

    function showPoint:nearby()
        if self.currentDistance <= 6.5 then

            if not lib.isTextUIOpen() then
                lib.showTextUI(locale('view_vehicle_prompt'), {
                    position = "top-center"
                })
            end

            if IsControlJustPressed(0, 51) then
                lib.hideTextUI()
                if showingVehicle == -1 then
                    ESX.ShowNotification(locale('no_vehicle_for_sale'), "error")
                    return
                end

                lib.registerContext({
                    id = "plenix-sell-vehicles:vehicleOptions",
                    title = locale('vehicle_options_title'),
                    canClose = true,
                    options = {
                        {title = locale('vehicle_options_buy', showingVehiclePrice), icon = "dollar", serverEvent = "plenix-sell-vehicles:buyVehicle", args = showingVehicleId},
                        {title = locale('vehicle_options_return'), icon = "car", serverEvent = "plenix-sell-vehicles:returnVehicle", args = showingVehicleId, disabled = showingVehicleOwner ~= ESX.PlayerData.identifier},
                        {title = locale('vehicle_options_change_vehicle'), icon = "car-side", onSelect = openAllVehiclesMenu},
                    }
                })

                lib.showContext("plenix-sell-vehicles:vehicleOptions")
            end
        else
            if self.currentDistance <= 10 then
                if lib.isTextUIOpen() then
                    lib.hideTextUI()
                end
            end
        end
    end

    function showPoint:onExit()
        if loadingCar then
            deletingShowingVehicle = true
        end

        while loadingCar and deletingShowingVehicle do
            Citizen.Wait(1)
        end

        if showingVehicle ~= -1 and showingVehicle ~= 0 then
            if DoesEntityExist(showingVehicle) then
                DeleteEntity(showingVehicle)
                showingVehicle = 0
                showingVehicleId = 0
            end
        end
    end
end)

function SpawnVehicle(id)
    local vehicle = lib.callback.await('plenix-sell-vehicles:getVehicleForSale', false, id)

    if not vehicle or not vehicle[1] then
        showingVehicle = -1
        return
    end

    loadingCar = true

    local vehicleProps = json.decode(vehicle[1].vehicleProps or "{}")
    local listingId = vehicle[1].id
    showingVehiclePrice = formatMoney(vehicle[1].price or 0)
    showingVehicleOwner = vehicle[1].seller or "unknown"

    ESX.Game.SpawnLocalVehicle(vehicleProps.model, Config.ViewVehicles.position.xyz, Config.ViewVehicles.position.w, function (veh)
        lib.setVehicleProperties(veh, vehicleProps)
        SetVehicleLights(veh, 2)
        SetVehicleLightsMode(veh, 2)
        SetVehicleOnGroundProperly(veh)
        SetEntityCanBeDamaged(veh, false)
        FreezeEntityPosition(veh, true)

        showingVehicle = veh
        showingVehicleId = listingId -- real listing id from the database

        local min, max = GetModelDimensions(GetEntityModel(veh))
        local height = max.z - min.z
        local location = GetEntityCoords(veh)
        sellingCarTextPosition = vector3(location.x, location.y, location.z + height)
        loadingCar = false
    end)
end

Citizen.CreateThread(function ()
    while true do
        local sleep = 500
        local PlayerCoords = GetEntityCoords(PlayerPedId())
        local distance = #(PlayerCoords - Config.ViewVehicles.position.xyz)
        if distance < Config.ViewVehicles.spawnDistance then
            sleep = 0
        else
            goto continue
        end
        if showingVehicle == -1 then
            ESX.Game.Utils.DrawText3D(Config.ViewVehicles.position.xyz, locale('no_vehicle_for_sale'), 1.0)
            goto continue
        end

        if loadingCar or showingVehiclePrice == 0 then
            ESX.Game.Utils.DrawText3D(Config.ViewVehicles.position.xyz, locale('loading_vehicle'), 1.0)
            goto continue
        end

        ESX.Game.Utils.DrawText3D(sellingCarTextPosition, locale('vehicle_for_sale', showingVehiclePrice), 1.0)

        ::continue::
        Citizen.Wait(sleep)
    end
end)

RegisterNetEvent('plenix-sell-vehicles:viewVehicle')
AddEventHandler('plenix-sell-vehicles:viewVehicle', function(data)
    if showingVehicle ~= 0 then
        if DoesEntityExist(showingVehicle) then
            DeleteEntity(showingVehicle)
        end
        showingVehicle = 0
    end

    local PlayerCoords = GetEntityCoords(PlayerPedId())
    local distance = #(PlayerCoords - Config.ViewVehicles.position.xyz)
    if distance > Config.ViewVehicles.spawnDistance then
        return
    end

    showingVehicleId = data
    SpawnVehicle(showingVehicleId)
end)

RegisterNetEvent('plenix-sell-vehicles:removedVehicle')
AddEventHandler('plenix-sell-vehicles:removedVehicle', function(data)
    if showingVehicleId == data and showingVehicle ~= 0 then
        if DoesEntityExist(showingVehicle) then
            DeleteEntity(showingVehicle)
        end
        showingVehicle = 0
        showingVehicleId = 0

        -- Show the next listing if the player is still at the dealership
        local coords = GetEntityCoords(PlayerPedId())
        if #(coords - Config.ViewVehicles.position.xyz) < Config.ViewVehicles.spawnDistance then
            SpawnVehicle(0)
        end
    end

    if lib.getOpenContextMenu() == "plenix-sell-vehicles:vehicleOptions" or lib.getOpenContextMenu() == "plenix-sell-vehicles:allVehicles" then
        lib.hideContext(false)
    end
end)

function openAllVehiclesMenu()
    local elements = {}
    local vehicles = lib.callback.await('plenix-sell-vehicles:getVehiclesForSale', false)
    if #vehicles == 0 then
        ESX.ShowNotification(locale('no_vehicle_for_sale'), "error")
        return
    end

    for i = 1, #vehicles do
        local model = json.decode(vehicles[i].vehicleProps).model
        table.insert(elements, {
            title = locale('choose_vehicle_item_title', GetVehicleLabel(model)),
            description = locale('choose_vehicle_item_description', formatMoney(vehicles[i].price)),
            icon = "car",
            event = "plenix-sell-vehicles:viewVehicle",
            args = vehicles[i].id,
            disabled = vehicles[i].id == showingVehicleId
        })
    end

    lib.registerContext({
        id = "plenix-sell-vehicles:allVehicles",
        title = locale('choose_vehicle_title'),
        menu = "plenix-sell-vehicles:vehicleOptions",
        canClose = true,
        options = elements
    })

    if lib.getOpenContextMenu() ~= nil then
        lib.hideContext(false)
    end

    lib.showContext("plenix-sell-vehicles:allVehicles")
end

function GetVehicleLabel(model)
    local label = GetLabelText(GetDisplayNameFromVehicleModel(model))
    
    if label == 'NULL' then 
        label = GetDisplayNameFromVehicleModel(model)
    end

    return label
end

function formatMoney(amount)
    local formatted = amount
    while true do  
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k==0) then
            break
        end
    end
    return formatted
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        RemoveBlip(SellPointBlip)

        if point then
            point:remove()
        end

        if showPoint then
            showPoint:remove()
            if showingVehicle ~= 0 then
                if DoesEntityExist(showingVehicle) then
                    DeleteEntity(showingVehicle)
                end
                showingVehicle = 0
            end
        end
    end
end)

-- 🔑 Vehicle Keys Handler
local function getActiveKeySystem()
    if Config.VehicleKeys == "auto" then
        if GetResourceState('qs-vehiclekeys') == 'started' then
            return "qs-vehiclekeys"
        elseif GetResourceState('qb-vehiclekeys') == 'started' then
            return "qb-vehiclekeys"
        elseif GetResourceState('wasabi_carlock') == 'started' then
            return "wasabi_carlock"
        else
            return "none"
        end
    else
        return Config.VehicleKeys
    end
end

function GiveVehicleKeys(plate, vehicle)
    local system = getActiveKeySystem()
    if system == "qs-vehiclekeys" then
        local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
        exports['qs-vehiclekeys']:GiveKeys(plate, model, true)
    elseif system == "qb-vehiclekeys" then
        TriggerEvent("vehiclekeys:client:SetOwner", plate)
    elseif system == "wasabi_carlock" then
        exports['wasabi_carlock']:GiveKey(plate)
    end
end

function RemoveVehicleKeys(plate, vehicle)
    local system = getActiveKeySystem()
    if system == "qs-vehiclekeys" then
        local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
        exports['qs-vehiclekeys']:RemoveKeys(plate, model)
    elseif system == "qb-vehiclekeys" then
        TriggerEvent("qb-vehiclekeys:client:RemoveKeys", plate)
    elseif system == "wasabi_carlock" then
        exports['wasabi_carlock']:RemoveKey(plate)
    end
end

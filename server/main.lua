lib.locale()

-----------------------------------------------------------
-- owned_vehicles column detection
-- ESX servers have different owned_vehicles schemas (in_garage, garage_id, mileage, parking...).
-- Inserting into a column that doesn't exist fails, so only use the ones that are there.
-----------------------------------------------------------
local ownedVehicleColumns = {}

MySQL.ready(function()
    local columns = MySQL.query.await([[
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'owned_vehicles'
    ]]) or {}

    for _, c in ipairs(columns) do
        ownedVehicleColumns[c.COLUMN_NAME] = true
    end
end)

local function InsertOwnedVehicle(owner, vehicleProps, mileage)
    local columns = { 'owner', 'plate', 'vehicle' }
    local values = { owner, vehicleProps.plate, json.encode(vehicleProps) }

    local optional = {
        { 'type', 'car' },
        { 'stored', 1 },
        { 'in_garage', 1 },
        { 'garage_id', Config.Garage },
        { 'parking', Config.Garage },
        { 'mileage', mileage or 0 },
    }

    for _, col in ipairs(optional) do
        if ownedVehicleColumns[col[1]] then
            columns[#columns + 1] = col[1]
            values[#values + 1] = col[2]
        end
    end

    local placeholders = string.rep('?', #columns, ', ')
    local query = ('INSERT INTO owned_vehicles (`%s`) VALUES (%s)'):format(table.concat(columns, '`, `'), placeholders)

    local ok, id = pcall(MySQL.insert.await, query, values)
    return ok and id ~= nil
end

local function GetListing(id)
    id = tonumber(id)
    if not id then return nil end

    return MySQL.single.await('SELECT id, seller, vehicleProps, mileage, price FROM vehicles_for_sale WHERE id = ?', { id })
end

-- Deletes the listing and reports whether *we* removed it (prevents two players buying the same car)
local function ClaimListing(id)
    local affected = MySQL.update.await('DELETE FROM vehicles_for_sale WHERE id = ?', { id })
    return affected and affected > 0
end

-----------------------------------------------------------
-- Callbacks
-----------------------------------------------------------
lib.callback.register('plenix-sell-vehicles:checkCar', function(source, vehicle, vehiclePlate)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end

    local response = MySQL.scalar.await('SELECT 1 FROM owned_vehicles WHERE owner = ? AND plate = ? LIMIT 1', {
        xPlayer.getIdentifier(), vehiclePlate
    })

    return response ~= nil
end)

lib.callback.register('plenix-sell-vehicles:putOnSale', function(source, money, vehicleProps)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or type(vehicleProps) ~= 'table' or not vehicleProps.plate then
        return false
    end

    -- Never trust the client price (negative prices would pay the buyer)
    local price = math.floor(tonumber(money) or 0)
    if price <= 0 or price > (Config.MaxPrice or 100000000) then
        return false
    end

    local owned = MySQL.single.await('SELECT * FROM owned_vehicles WHERE owner = ? AND plate = ? LIMIT 1', {
        xPlayer.getIdentifier(), vehicleProps.plate
    })
    if not owned then
        return false
    end

    -- The model must match what's stored, so a modified client can't list a different car
    local storedProps = json.decode(owned.vehicle or '{}') or {}
    if storedProps.model and tonumber(storedProps.model) ~= tonumber(vehicleProps.model) then
        return false
    end

    local listingId = MySQL.insert.await('INSERT INTO vehicles_for_sale (seller, vehicleProps, mileage, price) VALUES (?, ?, ?, ?)', {
        xPlayer.getIdentifier(), json.encode(vehicleProps), owned.mileage or 0, price
    })
    if not listingId then
        return false
    end

    MySQL.update.await('DELETE FROM owned_vehicles WHERE owner = ? AND plate = ?', {
        xPlayer.getIdentifier(), vehicleProps.plate
    })

    return true
end)

-- id = listing id, or 0/nil for the first listing
lib.callback.register('plenix-sell-vehicles:getVehicleForSale', function(source, id)
    id = tonumber(id) or 0

    local listing = id > 0 and GetListing(id) or nil
    if not listing then
        listing = MySQL.single.await('SELECT id, seller, vehicleProps, price FROM vehicles_for_sale ORDER BY id LIMIT 1')
    end

    return listing and { listing } or {}
end)

lib.callback.register('plenix-sell-vehicles:getVehiclesForSale', function(source)
    return MySQL.query.await('SELECT id, seller, vehicleProps, mileage, price FROM vehicles_for_sale ORDER BY id') or {}
end)

-----------------------------------------------------------
-- Buy / Return
-----------------------------------------------------------
RegisterNetEvent('plenix-sell-vehicles:buyVehicle', function(id)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local listing = GetListing(id)
    if not listing then
        xPlayer.showNotification(locale('no_vehicle_for_sale'))
        return
    end

    local price = listing.price
    if xPlayer.getMoney() < price then
        xPlayer.showNotification(locale('not_enough_money'))
        return
    end

    if not ClaimListing(listing.id) then
        xPlayer.showNotification(locale('no_vehicle_for_sale'))
        return
    end

    local vehicleProps = json.decode(listing.vehicleProps)

    if not InsertOwnedVehicle(xPlayer.getIdentifier(), vehicleProps, listing.mileage) then
        -- Put the listing back so nothing is lost
        MySQL.insert.await('INSERT INTO vehicles_for_sale (id, seller, vehicleProps, mileage, price) VALUES (?, ?, ?, ?, ?)', {
            listing.id, listing.seller, listing.vehicleProps, listing.mileage, listing.price
        })
        xPlayer.showNotification(locale('sell_vehicle_error'))
        return
    end

    xPlayer.removeMoney(price)
    UpdateCash(listing.seller, math.floor(price - (price * (Config.SellCarTax or 0.1))))

    TriggerClientEvent('plenix-sell-vehicles:removedVehicle', -1, listing.id)
    xPlayer.showNotification(locale('vehicle_bought', price))
end)

RegisterNetEvent('plenix-sell-vehicles:returnVehicle', function(id)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local listing = GetListing(id)
    if not listing then
        xPlayer.showNotification(locale('no_vehicle_for_sale'))
        return
    end

    if listing.seller ~= xPlayer.getIdentifier() then
        xPlayer.showNotification(locale('not_your_vehicle'))
        return
    end

    -- Return fee (Config.ReturnCarToOwnerTax of the listing price), paid from cash first, then bank
    local fee = math.floor(listing.price * (Config.ReturnCarToOwnerTax or 0))
    local feeAccount = nil
    if fee > 0 then
        if xPlayer.getMoney() >= fee then
            feeAccount = 'money'
        elseif (((xPlayer.getAccount('bank') or {}).money) or 0) >= fee then
            feeAccount = 'bank'
        else
            xPlayer.showNotification(locale('not_enough_money_fee', fee))
            return
        end
    end

    if not ClaimListing(listing.id) then
        return
    end

    if not InsertOwnedVehicle(listing.seller, json.decode(listing.vehicleProps), listing.mileage) then
        MySQL.insert.await('INSERT INTO vehicles_for_sale (id, seller, vehicleProps, mileage, price) VALUES (?, ?, ?, ?, ?)', {
            listing.id, listing.seller, listing.vehicleProps, listing.mileage, listing.price
        })
        xPlayer.showNotification(locale('vehicle_return_error'))
        return
    end

    if feeAccount then
        xPlayer.removeAccountMoney(feeAccount, fee)
    end

    TriggerClientEvent('plenix-sell-vehicles:removedVehicle', -1, listing.id)
    if fee > 0 then
        xPlayer.showNotification(locale('vehicle_returned_fee', fee))
    else
        xPlayer.showNotification(locale('vehicle_returned'))
    end
end)

-----------------------------------------------------------
-- Pay the seller (online or offline)
-----------------------------------------------------------
function UpdateCash(identifier, cash)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)

    if xPlayer then
        xPlayer.addAccountMoney('bank', cash)
        xPlayer.showNotification(locale('vehicle_sold', cash))
        return
    end

    local accounts = MySQL.scalar.await('SELECT accounts FROM users WHERE identifier = ?', { identifier })
    if not accounts then return end

    local accountsData = json.decode(accounts) or {}
    accountsData.bank = (accountsData.bank or 0) + cash

    MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', {
        json.encode(accountsData), identifier
    })
end

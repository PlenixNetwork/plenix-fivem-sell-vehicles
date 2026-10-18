Config = {}

-- 🔑 Vehicle key system integration
-- Choose which key resource to use:
--   "qs-vehiclekeys" → Uses qs-vehiclekeys exports
--   "qb-vehiclekeys" → Uses qb-vehiclekeys events
--   "wasabi_carlock" → Uses wasabi_carlock exports
--   "none"           → No key handling at all
--   "auto"           → Auto-detect which of the above is running (recommended)
Config.VehicleKeys = "auto"

-- 📍 Vehicle Sell Point Configuration
Config.SellPoint = {
    blipSprite = 147,                                -- Map blip icon
    blipColor = 52,                                  -- Blip color
    blipScale = 0.6,                                 -- Blip size
    blipShortRange = true,                           -- Blip only shows when close
    blipPos = vector3(-23.2987, -1678.4564, 29.4658),-- Blip position

    markerType = 36,                                 -- Marker type shown in world
    markerColor = { r = 10, g = 255, b = 0, a = 80 },-- Marker color RGBA
    markerWidth = 1.0,                               -- Marker width
    markerHeight = 1.0,                              -- Marker height
    markerPos = vector3(-23.2987, -1678.4564, 29.4658), -- Marker position
    markerShowRadius = 10.0,                         -- Show marker when within this distance
}

-- 👀 Preview Vehicle Configuration
Config.ViewVehicles = {
    position = vector4(-51.8511, -1685.3160, 29.4917, 316.3311), -- Vehicle spawn location (x,y,z,heading)
    spawnDistance = 30.0,                                        -- Distance from point at which vehicles are spawned/despawned
}

-- 💰 Tax Settings
Config.ReturnCarToOwnerTax = 0.1 -- Tax applied when owner takes back their car from dealership (default 10%)
Config.SellCarTax = 0.1          -- Tax applied when selling a car through the dealership (default 10%)

-- 🅿️ Garage the bought/returned vehicle is stored in (only used if your owned_vehicles table has a garage_id or parking column)
Config.Garage = "Legion Square"

-- Maximum price a player can list a vehicle for
Config.MaxPrice = 100000000

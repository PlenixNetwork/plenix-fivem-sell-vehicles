# 🚗 Plenix FiveM Sell Vehicles

**Plenix FiveM Sell Vehicles** is a lightweight FiveM script designed to replace the old `esx-qalle-sellvehicles`.  
It’s inspired by the original but takes a fresh approach to how vehicles are displayed and sold.

---

## 📦 Features
- Clean and optimized code
- Uses [OxLib](https://github.com/overextended/ox_lib) for UI/logic
- Secure integration with [OxMySQL](https://github.com/overextended/oxmysql)
- Optional target support (ox_target) and map blips
- Configurable sale zones, pricing limits, and commission
- Ownership checks via ESX `owned_vehicles`
- Server & client exports for extensibility
- Locale-ready strings
- Keys system

---

## 🔗 Dependencies
Make sure you have the following resources installed **and started before this one**:
- [ESX](https://github.com/esx-framework/esx-legacy) (⚠️ **No QB support**)
- [OxLib](https://github.com/overextended/ox_lib)
- [OxMySQL](https://github.com/overextended/oxmysql)
- *(Optional)* [ox_target](https://github.com/overextended/ox_target)

---

## ⚙️ Installation

### A) Git clone
```bash
cd resources
git clone https://github.com/PlenixNetwork/plenix-sell-vehicles
```
### B) Manual

- Download the latest release and extract it into your `resources` folder.  
- Ensure the folder name is `plenix-sell-vehicles` (or update your `server.cfg` accordingly).

### server.cfg
```cfg
ensure oxmysql
ensure ox_lib
# ensure ox_target         # (optional)
ensure plenix-sell-vehicles
```

### Database
- Run the provided create-table.sql file on your database (via HeidiSQL, phpMyAdmin or MySQL CLI):

---

## 🕹️ Usage

Go to any Sell Zone and interact (target prompt or marker) to open the selling/buying UI.

- **List Vehicle:** Select a nearby owned vehicle and set a price within limits.  
- **Buy Vehicle:** Browse listings at the zone, preview details, and purchase.

On successful sale:
- Seller receives `price - commission`.  
- Ownership transfers to the buyer (ESX `owned_vehicles` updated).  
- Listing is removed.

Tip: If `Config.UseTarget = false`, markers/text UI will appear instead of target.

---

## 🤝 Credits

- Inspired by `esx-qalle-sellvehicles`  

---

## 📄 License

This project is licensed under the **MIT License**.

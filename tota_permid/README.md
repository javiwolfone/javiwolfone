# Permanent ID System with Advanced Admin Panel  

[![Discord Support](https://img.shields.io/badge/Discord-Support-blue?logo=discord&logoColor=white)](https://discord.gg/YOURSERVER)  

---

## 📖 Overview  
This resource provides a **Permanent ID System** for FiveM servers, designed to assign and manage unique player IDs. It comes with an **advanced admin panel** that allows staff to manage players directly in-game with ease.  

### ✨ Main Features  
- 🔑 **Permanent Player IDs** with two assignment methods:  
  - Random IDs (fast & less predictable)  
  - Incremental IDs (sequential 1, 2, 3...)  
- 🛠️ **Admin Panel** with powerful tools:  
  - Kick, kill, revive players  
  - Freeze/unfreeze  
  - Teleport players to you or go to them  
  - Vehicle spawning by model  
  - Spectate players (with prevention of self-spectating)  
- 🧑 **Overhead IDs** (toggle with `/ids`)  
  - Configurable max permID  
  - Option to display player names above heads  
- 🖥️ **Discord Integration**  
  - Webhook support for logging admin actions  
- 🗄️ **Database Integration**  
  - Works with both ESX (`users` table) and QBCore (`players` table)  
  - Adds columns for `permid` and `discord`  

---

## ⚙️ Installation  

### 1. Dependencies  
- [oxmysql](https://github.com/overextended/oxmysql) or [mysql-async](https://github.com/brouznouf/fivem-mysql-async)  

### 2. Database Setup  
Run the appropriate SQL query from **`tota_permid.sql`** depending on your framework:  

- For **ESX**:  
```sql
ALTER TABLE `users`
ADD COLUMN `permid` INT(11) NULL DEFAULT NULL,
ADD COLUMN `discord` VARCHAR(50) NULL DEFAULT NULL;
```

- For **QBCORE**:  
```sql
ALTER TABLE `players`
ADD COLUMN `permid` INT(11) NULL DEFAULT NULL,
ADD COLUMN `discord` VARCHAR(50) NULL DEFAULT NULL;
```

### 3. Add to Server
Place the script in your `resources` folder.

Update your `server.cfg`:
```cfg
ensure tota_permid
```

### 4. Configuration
Open `config.lua` and adjust settings to fit your server:
- `Config.Framework` → `esx` or `qbcore`
- `Config.AdminPermission` → minimum admin permission required
- `Config.IdAssignmentMethod` → `random` or `increment`
- `Config.DiscordWebhook` → insert your Discord webhook for logging
- `Config.ServerName` and `Config.KickMessage` → customize to your server branding

## 🖥️ Commands
- `/ids` → Toggle overhead IDs
- `/idpanel` → Open the admin panel

## 🛠️ Debugging
- Set `Config.Debug = true` to enable debug logging.

## 🤝 Support
For help, updates, or suggestions, join our Discord community:  

[![Discord](https://img.shields.io/badge/Discord-Support-blue?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/9tspPPHEfM)

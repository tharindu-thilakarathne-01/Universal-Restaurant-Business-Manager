# 🍽️ Universal Restaurant & Business Manager — Installation Guide

Thank you for purchasing **Universal Restaurant & Business Manager (Multi-Business System)**.  
> 💡 **NOT ONLY FOR BURGER SHOT:** This resource can run **Burger Shot, Pizza This, UwU Cafe, Bean Machine Coffee, Yellow Jack Bar, Taco Trucks, Diners, Clubs, and ANY custom player-owned restaurant or food business** on your server simultaneously without duplicate resources!

This resource is built for **Qbox (`qbx_core`)** and **QBCore (`qb-core`)** with full support for `ox_inventory`, `ox_target`, `ox_lib`, and `oxmysql`.

---

## 📋 Requirements & Dependencies
Make sure these resources are running on your server:
1. `oxmysql` (Database)
2. `ox_lib` (UI & Callbacks)
3. `ox_target` (Target interaction)
4. `ox_inventory` OR `qb-inventory`
5. `qbx_core` OR `qb-core`

---

## 🚀 Step 1: Database Setup
1. Open HeidiSQL, phpMyAdmin, or your database management tool.
2. Select your server database.
3. Import and execute the SQL file located at:
   ```
   sql/install.sql
   ```
   *This automatically sets up all required tables (`rm_stations`, `rm_roles`, `rm_recipes`, `rm_orders`, `rm_menu_state`, `rm_logs`, `rm_doors`, `rm_vending_funds`).*

---

## 📦 Step 2: Register Inventory Items & Icons

### For `ox_inventory` Users:
1. Open `ox_inventory/data/items.lua`.
2. Copy the item definitions from `install/ox_inventory_items.lua` and paste them into your `items.lua`.
3. Copy the item image files (`.png`) from `web/images/` and place them into:
   ```
   resources/[ox]/ox_inventory/web/images/
   ```
   *(Ensure `burgershot_tablet.png` and all `bs_*.png` are placed there).*
4. Restart your server or type `restart ox_inventory` in server console.

### For `qb-inventory` / `qb-core` Users:
1. Open `qb-core/shared/items.lua`.
2. Copy the items from `install/qb_core_items.lua` and paste them into `items.lua`.
3. Copy the `.png` images into:
   ```
   resources/[qb]/qb-inventory/html/images/
   ```

---

## 👔 Step 3: Job Configuration
1. Open your server's jobs file:
   - For **Qbox**: `resources/[qbx]/qbx_core/shared/jobs.lua`
   - For **QBCore**: `resources/[qb]/qb-core/shared/jobs.lua`
2. Copy the `burgershot` job table from `install/jobs.lua` and paste it inside your `QBShared.Jobs` table.

---

## ⚙️ Step 4: Add to `server.cfg`
Ensure resources are started in the correct order:
```cfg
ensure oxmysql
ensure ox_lib
ensure ox_target
ensure ox_inventory # or qb-inventory
ensure qbx_core     # or qb-core

# Restaurant Manager Resource
ensure burgershot
```

---

## 🎮 In-Game Commands & Usage
- `/burgershot` or `/bsmenu` — Opens the Restaurant Management Tablet (requires tablet item or staff role).
- `/bstablet` — Gives a company tablet to the player (if permitted).
- **Owner Tablet:** Grade 9 (Owner) and Grade 10 (Admin) have permanent access to:
  - **Live Orders:** View customer orders, accept, cook, deliver, or refund.
  - **Recipes:** Live dynamic recipe creation and ingredient editor.
  - **3D Placement:** Press [E] to place customer counters, grills, fryers, drink dispensers, storage fridges, and duty clocks anywhere in 3D space!
  - **Door Locks:** 3D Door raycast picker — aim at any door, press [E] to register permanent single/double door locks with [E] interaction prompts!
  - **Staff Management:** View online players, hire staff, promote/demote grades, issue tablets, or fire employees.
  - **Audit Logs:** Real-time log tracking of all staff actions, cooking history, and transactions.

---

## 💬 Support & Inquiries
For support, documentation, or customization requests, reach out via your Tebex support channel or Discord community!


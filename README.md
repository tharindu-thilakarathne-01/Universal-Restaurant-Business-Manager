# 🍽️ UNIVERSAL RESTAURANT & BUSINESS MANAGER
> **All-in-One Multi-Business Framework for FiveM (Qbox & QBCore)**  
> 🚀 **NOT JUST BURGER SHOT!** This single framework powers **Burger Shot, Pizza This, UwU Cafe, Bean Machine Coffee, Yellow Jack Bar, Taco Bomb, Cluckin' Bell, Food Trucks, and ANY custom player-owned restaurant, cafe, bakery, or bar** on your server simultaneously!  
> Built with `ox_lib`, `ox_target`, `ox_inventory`, and `oxmysql`. Featuring 3D Station Placement, 3D DoorSystem Locking, Live Tablet Management, Dynamic Recipe Editor, Vending Revenue Funds, and Audit Logs.

---

## 🌐 NOT JUST BURGER SHOT — USE FOR ANY RESTAURANT OR BUSINESS!

One of the greatest advantages of this resource is that **it is 100% universal and multi-business by design**. You do **NOT** need to buy or run 10 separate scripts for different food joints on your server. This single resource runs unlimited businesses simultaneously with isolated orders, roles, menus, vending machines, and door locks!

### 💡 Examples of Businesses You Can Run With This Single Script:
| Business Type | Examples | What It Uses |
|---|---|---|
| **Fast Food & Burgers** | Burger Shot, Up-n-Atom, Horny's | Flame Grills, Assembly Boards, Deep Fryers, Soda Dispensers |
| **Pizzerias & Italian** | Pizza This, Italian Diners | Electric Baking Ovens, Assembly Boards, Prep Counters, Drinks |
| **Cafes & Bakeries** | UwU Cat Cafe, Bean Machine, Cool Beans | Coffee Espresso Machines, Bubble Tea Dispensers, Bakery Ovens |
| **Bars, Pubs & Clubs** | Yellow Jack Inn, Tequi-la-la, Bahama Mamas | Drink/Cocktail Dispensers, Bar Counters, Snack Grills |
| **Mexican & Fast Dining** | Taco Bomb, Burrito Stalls | Meat Grills, Assembly Boards, Chip Fryers |
| **Food Trucks & Pop-up Stalls** | Street Food Trucks, Beach Stalls | 3D Raycast placement anywhere on streets, beaches, or piers! |

### 🎯 Why It Works for ANY Location (No Code Needed!):
1. **No Hardcoded Coordinates:** Owners and Admins use the **3D Raycast Placement Tool** to walk into ANY building, MLO, or food truck and place ordering counters, grills, fryers, storage fridges, and duty clocks wherever they want!
2. **Dynamic 3D Door Locks for Any Interior:** Aim at any door in any custom MLO or building to instantly create lockable doors with interactive `[E]` prompts.
3. **In-Game Recipe Creator:** No need to edit Lua files to add pizza, coffee, or tacos. Owners open the **Recipe Editor** on their tablet and create whatever recipes match their business live in-game!
4. **Isolated Multi-Business Economy:** Each business has its own roles, grades, society funds, order queue, menu items, and audit logs.

---

## 📑 TABLE OF CONTENTS
1. [🌟 Key Features Overview](#-key-features-overview)
2. [⚙️ Complete Installation Guide](#️-complete-installation-guide)
   - [Requirements & Dependencies](#requirements--dependencies)
   - [Step 1: Database Setup](#step-1-database-setup)
   - [Step 2: Inventory Items & Images](#step-2-inventory-items--images)
   - [Step 3: Job Grades Setup](#step-3-job-grades-setup)
   - [Step 4: Startup Order (server.cfg)](#step-4-startup-order-servercfg)
   - [Step 5: Discord Webhook Setup (Optional)](#step-5-discord-webhook-setup-optional)
3. [📖 Complete In-Game Usage Guide](#-complete-in-game-usage-guide)
   - [🍔 1. For Customers](#1-for-customers)
   - [👨‍🍳 2. For Staff & Kitchen Employees](#2-for-staff--kitchen-employees)
   - [💼 3. For Managers](#3-for-managers)
   - [👑 4. For Owners & Admins (Advanced Tools)](#4-for-owners--admins-advanced-tools)
4. [🎮 In-Game Commands & Keybinds](#-in-game-commands--keybinds)
5. [🏢 Multi-Restaurant Architecture (Adding New Restaurants)](#-multi-restaurant-architecture-adding-new-restaurants)
6. [❓ Troubleshooting & FAQ](#-troubleshooting--faq)

---

## 🌟 KEY FEATURES OVERVIEW

- 📱 **Interactive Tablet System:** Openable via item (`burgershot_tablet`), command (`/burgershot` or `/bsmenu`), or target terminal.
- 🎯 **3D Raycast Station Placement:** Owners can place customer ordering counters, grills, fryers, drink fountains, coffee machines, storage fridges, food trays, and duty clocks anywhere in full 3D space with real-time rotation.
- 🚪 **3D Door Lock Picker (GTA DoorSystem):** Aim at any single or double door in 3D, press `[E]` to register, and staff can lock/unlock with interactive `[E]` prompts.
- 📋 **Live Order Management Board:** Kanban-style order board (Pending ➔ Claimed ➔ Cooking ➔ Ready ➔ Delivered) with real-time sound notifications.
- 🧪 **Live Recipe Editor:** Owners can create brand-new cooking recipes on the fly without server restarts.
- 👥 **Staff Management & Tablet Distribution:** View online players, hire, promote, demote, fire, and issue company tablets via Server ID or live player list.
- 🏪 **Self-Service Vending Machines:** Automated customer vending with dedicated cash revenue fund and owner withdrawals.
- 🍔 **Consumables Included:** Finished burgers and drinks come with custom eating/drinking animations, props, and hunger/thirst restoration.
- 📜 **Security & Audit Logs:** In-game audit history plus optional Discord Webhook logging for staff actions, salaries, and door toggles.
- ⚡ **Optimized Performance:** 0.00ms idle resmon usage; server-side authoritative anti-cheat and rate-limiting.

---

## ⚙️ COMPLETE INSTALLATION GUIDE

### Requirements & Dependencies
Make sure the following official resources are installed and running:
- `oxmysql` (Database connector)
- `ox_lib` (UI & Callbacks)
- `ox_target` (Third-eye target interactions)
- `ox_inventory` (OR `qb-inventory`)
- `qbx_core` (OR `qb-core`)

---

### Step 1: Database Setup
1. Open your database management tool (HeidiSQL, phpMyAdmin, etc.).
2. Select your server's database (e.g. `qbox` or `qbcore`).
3. Import and execute the SQL installation script:
   ```
   burgershot/sql/install.sql
   ```
   *This automatically creates all required tables (`rm_stations`, `rm_roles`, `rm_recipes`, `rm_orders`, `rm_menu_state`, `rm_logs`, `rm_doors`, `rm_vending_funds`, `rm_staff_hours`).*
4. *(Optional)* If you ever want to reset the database to a completely fresh factory state, run:
   ```
   burgershot/sql/reset_database.sql
   ```

---

### Step 2: Inventory Items & Images

#### A. If you use `ox_inventory`:
1. Open `resources/[ox]/ox_inventory/data/items.lua`.
2. Open the helper file located at `burgershot/install/ox_inventory_items.lua`.
3. Copy all item definitions (`burgershot_tablet`, ingredients, finished burgers, and drinks) and paste them inside your `items.lua`.
4. Copy all item `.png` files from:
   ```
   burgershot/install/item_images/
   ```
   and paste them into your:
   ```
   resources/[ox]/ox_inventory/web/images/
   ```
5. In your server console, type `restart ox_inventory` (or restart the server).

#### B. If you use `qb-inventory` / `qb-core`:
1. Open `resources/[qb]/qb-core/shared/items.lua`.
2. Copy the items from `burgershot/install/qb_core_items.lua` into your `QBShared.Items`.
3. Copy all `.png` files from `burgershot/install/item_images/` into:
   ```
   resources/[qb]/qb-inventory/html/images/
   ```

---

### Step 3: Job Grades Setup
1. Open your server's jobs file:
   - For **Qbox**: `resources/[qbx]/qbx_core/shared/jobs.lua`
   - For **QBCore**: `resources/[qb]/qb-core/shared/jobs.lua`
2. Open `burgershot/install/jobs.lua` and copy the `['burgershot']` job definition.
3. Paste it inside your `QBShared.Jobs` table.  
   *Grades included: 0 (Trainee), 1 (Crew Member), 2 (Cook), 3 (Senior Cook), 4 (Cashier), 5 (Shift Lead), 6 (Supervisor), 7 (Assistant Manager), 8 (Manager), 9 (Owner), 10 (Restaurant Admin).*

---

### Step 4: Startup Order (`server.cfg`)
Ensure dependencies are started **BEFORE** `burgershot` in your `server.cfg`:
```cfg
# Database & Core Libraries
ensure oxmysql
ensure ox_lib
ensure ox_target
ensure ox_inventory # or qb-inventory
ensure qbx_core     # or qb-core

# Restaurant Manager Resource
ensure burgershot
```

---

### Step 5: Discord Webhook Setup (Optional)
To send live audit logs to a private Discord staff channel:
1. Open `burgershot/config.lua`.
2. Locate `Config.DiscordWebhook`:
   ```lua
   Config.DiscordWebhook = {
       enabled = true,
       url = 'https://discord.com/api/webhooks/YOUR_WEBHOOK_URL_HERE',
       title = 'Burger Shot Management Logs',
       color = 16744192
   }
   ```
3. Set `enabled = true` and paste your Discord Webhook URL.

---

## 📖 COMPLETE IN-GAME USAGE GUIDE

### 1. For Customers

#### Placing an Order at the Counter:
1. Walk up to any Customer Ordering Counter.
2. Target the counter using `ox_target` (Left Alt) and click **"Order Food"**.
3. Browse the menu categories (All, Food, Drinks, Sides).
4. Click items to add them to your order cart.
5. Choose your payment method (**Cash** or **Bank**).
6. Click **"Place Order"**.
7. You will receive an on-screen confirmation with your unique **Order #ID**. Wait near the counter or food tray for staff to call your number!

#### Using Vending Machines:
1. Walk up to any Burger Shot Vending Machine.
2. Target with `ox_target` and click **"Use Vending Machine"**.
3. Select any in-stock snack or drink and purchase instantly with Cash or Bank.

#### Eating & Drinking (Consumables):
- **Cheese And Chilli Burger / BBQ Burger:** Use the item from your inventory. Your character will play the burger eating animation and gain **+35% to +38% Hunger**.
- **E-Cola / Bubble Tea:** Use the item from your inventory. Your character will drink from a soda can or bubble tea cup and gain **+28% to +32% Thirst**.

---

### 2. For Staff & Kitchen Employees

#### Clocking In / Out:
1. Walk up to the **Duty Clock** interaction zone.
2. Target with `ox_target` and click **"Clock In"**. Your duty status turns ON, and your worked hours begin tracking.

#### Opening the Tablet:
- Use the `burgershot_tablet` item from your inventory, OR
- Type `/burgershot` (or `/bsmenu`) in chat, OR
- Target any **Management Terminal** interaction point.

#### Live Orders Board (Kitchen Flow):
1. Open the tablet and navigate to the **Live Orders** tab.
2. When a customer places an order, an alert chime plays and the order card appears in **Pending**.
3. Click **"Claim Order"** ➔ Moves to **Accepted** (other employees cannot double-claim it).
4. Click **"Start Cooking"** ➔ Moves to **Cooking** (notifies the customer that food is being prepared).
5. Head to the appropriate cooking stations to prepare the food.
6. Once cooked, click **"Mark Ready"** ➔ Moves to **Ready**.
7. Place the meal on the **Food Tray (Stash)** for the customer, and click **"Serve Order"** to complete!

#### Cooking at Stations:
1. Walk up to the station (e.g. Flame Grill, Assembly Board, Deep Fryer, Drink Dispenser, Oven, Coffee Machine).
2. Target the station with `ox_target` to view available recipes.
3. Ensure you have the required ingredients in your inventory.
4. Click the recipe. A progress circle with custom cooking animations will play:
   - Required raw ingredients are safely deducted.
   - Finished meal is added directly to your inventory.

---

### 3. For Managers

#### Managing Menu & Stock:
1. Open the Tablet and go to **Management** ➔ **Menu & Stock**.
2. **Toggle Stock:** Toggle any item to **Out of Stock** if the kitchen runs out of ingredients. It will instantly grey out on customer counters.
3. **Edit Prices:** Update item prices on the fly. Changes apply to counters immediately.

#### Order History & Refunds:
1. Open **Management** ➔ **Order History**.
2. View completed, cancelled, or pending orders.
3. If a customer is unhappy or leaves, click **"Refund Order"**. The customer is automatically refunded their money, and the transaction is logged.

#### Vending Machine Restock & Revenue:
1. Target any Vending Machine with `ox_target` and choose **"Manage Vending"**.
2. Add items, set prices, and adjust quantities.

---

### 4. For Owners & Admins (Advanced Tools)

> **Access:** Grade 9 (Owner) and Grade 10 (Restaurant Admin) have permanent, unrestricted access to the **Owner Controls** tab.

#### A. 3D Station Placement Mode:
*Place counters, cooking stations, storage, and duty clocks anywhere in 3D space!*
1. Open Tablet ➔ **Owner Controls** ➔ **Target Zones**.
2. Choose the station you want to create (e.g., *Customer Ordering Counter*, *Flame Grill*, *Assembly Board*, *Deep Fryer*, *Drink Dispenser*, *Ingredient Fridge*, *Food Tray*, *Staff Duty Clock*, *Vending Machine*).
3. Click **"Place Station (3D Mode)"**.
4. The tablet closes and an interactive **3D Raycast Preview Box** appears on the floor.
5. Move your character to position it.
6. Use **Mouse Scroll Wheel** or **Left/Right Arrow Keys** to rotate heading.
7. Press **`[E]`** to confirm and place!
   - The zone is permanently saved to the database (`rm_stations`).
   - Third-eye target zones immediately sync to all players on the server.
8. To delete a station, open the Target Zones tab and click the red **Delete** button next to any station.

#### B. 3D Door Lock Picker (GTA DoorSystem):
*Make any door in the restaurant interactive and lockable!*
1. Open Tablet ➔ **Owner Controls** ➔ **Door Locks**.
2. Click **"3D Door Picker Mode"**.
3. Walk up to any single or double door. Aim your crosshair directly at the door leaf.
4. A 3D marker will highlight the door model.
5. Press **`[E]`** to select the door leaf:
   - For a **Single Door:** Press **`[G]`** to save immediately!
   - For a **Double Door:** Aim at the second leaf, press **`[E]`**, and then press **`[G]`** to save!
6. Enter a name (e.g. *"Main Entrance"* or *"Kitchen Back Door"*).
7. The door is permanently registered in `rm_doors`.
8. Any staff member with the `door_unlock` permission can walk up to the door and press **`[E]`** to Lock or Unlock it.

#### C. Live Recipe Editor:
*Create brand new menu items and cooking combinations without server restarts!*
1. Open Tablet ➔ **Owner Controls** ➔ **Recipe Editor**.
2. Click **"Create New Recipe"**.
3. Choose the **Output Item** (must exist in inventory items).
4. Select the target **Cooking Station** (e.g., Assembly, Grill, Fryer, Drinks, Oven).
5. Set the cooking duration (in milliseconds).
6. Add up to 6 required ingredient items and quantities (e.g., `bs_burger_bun` x1, `bs_meat_pattie` x1, `bs_cheese` x1).
7. Click **"Save Recipe"**. The recipe is immediately active across all kitchen stations!

#### D. Staff Management & Tablet Distribution:
1. Open Tablet ➔ **Owner Controls** ➔ **Give Tablet** / **Staff**.
2. **Issue Tablets to Staff:**
   - Enter the player's active **Server ID**, choose their job grade, and click **"Give Tablet"**.
   - OR click **"Give To Myself"** to instantly receive a tablet.
   - OR browse the **Live Online Players Table**, find the citizen, and click **"Give Tab"**.
   - An official `burgershot_tablet` is safely delivered to their inventory!
3. **Promotions & Hiring:**
   - Select any online player to assign job grades (Grades 0 through 9).
   - Click **"Fire Staff"** to remove employment.

#### E. Vending Machine Revenue Fund:
1. Customers purchasing from vending machines generate revenue that accumulates in the restaurant's vending fund.
2. Owners can view the total accumulated balance and click **"Withdraw Revenue"** to collect the cash.

#### F. Audit Logs & History:
1. Open Tablet ➔ **Owner Controls** ➔ **Audit Logs**.
2. Inspect every staff action, salary payout, recipe creation, and door toggle with exact timestamps and Citizen IDs.
3. If Discord Webhook is configured, these actions are simultaneously dispatched to your Discord server.

---

## 🎮 IN-GAME COMMANDS & KEYBINDS

| Command / Key | Permission | Description |
|---|---|---|
| `/burgershot` or `/bsmenu` | Staff / Tablet Holder | Opens the Restaurant Management Tablet. |
| `/bstablet` | Admin / Allowed Staff | Gives an official company tablet to your inventory. |
| **`[E]`** | Customer / Staff | Interact with Counter, Stations, or Lock/Unlock Doors. |
| **`[G]`** | Placement Mode | Confirms single-door placement in 3D Door Picker. |
| **`[X]`** or **Backspace** | Placement Mode | Cancels 3D Placement or 3D Door Picker mode. |
| **Mouse Scroll** | Placement Mode | Rotates 3D station heading before placing. |

---

## 🏢 MULTI-RESTAURANT ARCHITECTURE (ADDING NEW RESTAURANTS)

This resource is built to support unlimited restaurants simultaneously (e.g., *Pizza This*, *UwU Cafe*, *Bean Machine*, *Horny's*).

To add a second restaurant:
1. Open `burgershot/config.lua`.
2. Add a new restaurant key inside `Config.Restaurants`:
   ```lua
   Config.Restaurants['pizzathis'] = {
       label = 'Pizza This',
       job = 'pizzathis',
       adminGrade = 10,
       ownerGrade = 4,
       managerGrade = 3,
       societyAccount = 'pizzathis',
       blip = {
           enabled = true,
           coords = vec3(797.35, -749.91, 31.27),
           sprite = 267,
           color = 1,
           scale = 0.8,
           name = 'Pizza This'
       },
       orderingCounters = {},
       dutyTarget = nil,
       managementTerminal = nil
   }
   ```
3. Run SQL seed data for `pizzathis` in `rm_roles` and `rm_menu_state`.
4. Owners can place all stations and door locks dynamically via the tablet!

---

## ❓ TROUBLESHOOTING & FAQ

#### Q: The tablet says `invalid_item` when trying to give a tablet.
> **A:** When adding new items to `ox_inventory/data/items.lua`, `ox_inventory` must be reloaded to register the item definition into server memory. Type `restart ox_inventory` in your server console or restart the server.

#### Q: How do I change the default keybind or prompt style?
> **A:** If you use **Hud_manger**, you can customize the interaction prompt (`[E] Lock Main Door`) by opening `/hud` (or `F7`) and navigating to the **Interaction Prompts** tab to change styles (Hexagon, Cyber, Glass, Pill, Retro), badge colors, and screen positions.

#### Q: How do I completely wipe all test stations and recipes?
> **A:** Run `burgershot/sql/reset_database.sql` in your database manager. It will clear all test stations, doors, orders, and logs, and restore clean factory default recipes.

#### Q: Can I run this with standard QBCore without Qbox?
> **A:** Yes! The resource features an automatic hybrid bridge that detects `qbx_core` first, and if not present, seamlessly falls back to standard `qb-core`.

---

## 📄 LICENSE & CREDITS
- **Resource:** Restaurant Manager / Burger Shot
- **Framework:** Qbox & QBCore Hybrid
- **Support:** Available via your store support tickets and Discord.

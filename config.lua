Config = {}

-- General Settings
Config.Locale = 'en' -- 'en' or 'si'
Config.Debug = false
Config.LowEndMode = false -- Reduces raycast preview render steps and UI blur effects for low-end systems

-- Discord Audit Logs Webhook (Optional)
Config.DiscordWebhook = {
    enabled = false, -- Set to true to broadcast audit logs to Discord
    url = '',        -- Paste your Discord Channel Webhook URL here
    title = 'Burger Shot Management Logs',
    color = 16744192 -- Amber/Orange
}

-- Distance & Security Validations
Config.MaxStationDistance = 3.0 -- Maximum distance (in meters) to interact with a cooking station
Config.MaxCounterDistance = 3.2 -- Maximum distance (in meters) to order food from customer counter
Config.RateLimitMs = 1000 -- Net event rate limiting window per player in milliseconds
Config.RefundOnCancel = true -- Automatically refund customer if manager cancels/refunds pending/accepted order
Config.RequireOnDutyEmployeeToOrder = false -- If true, customer cannot place an order unless at least 1 employee is on duty

-- Available Station & Interaction Zone Types (Owner can place any of these via tablet)
Config.StationTypes = {
    -- Customer & Staff Interaction Points
    ['counter'] = {
        label = 'Customer Ordering Counter',
        icon = 'fas fa-cash-register',
        category = 'service',
        maxPerRestaurant = 10,
        length = 1.2,
        width = 1.0,
        propModel = nil
    },
    ['vending'] = {
        label = 'Vending Machine',
        icon = 'fas fa-cart-shopping',
        category = 'service',
        maxPerRestaurant = 6,
        length = 1.2,
        width = 1.0,
        propModel = nil
    },
    ['duty'] = {
        label = 'Staff Duty Clock (Clock In/Out)',
        icon = 'fas fa-business-time',
        category = 'service',
        maxPerRestaurant = 5,
        length = 0.8,
        width = 0.8,
        propModel = nil
    },
    ['terminal'] = {
        label = 'Management Tablet Terminal',
        icon = 'fas fa-laptop-code',
        category = 'service',
        maxPerRestaurant = 5,
        length = 0.8,
        width = 0.8,
        propModel = nil
    },
    ['tray'] = {
        label = 'Food Counter / Tray (Stash)',
        icon = 'fas fa-utensils',
        category = 'service',
        maxPerRestaurant = 10,
        length = 1.0,
        width = 0.8,
        propModel = nil
    },
    ['storage'] = {
        label = 'Ingredient Storage / Fridge',
        icon = 'fas fa-box-archive',
        category = 'service',
        maxPerRestaurant = 5,
        length = 1.4,
        width = 1.2,
        propModel = nil
    },

    -- Cooking Stations
    ['grill'] = {
        label = 'Flame Grill',
        icon = 'fas fa-fire-burner',
        category = 'cooking',
        maxPerRestaurant = 6,
        animDict = 'amb@prop_human_bbq@male@idle_a',
        animClip = 'idle_b',
        length = 1.4,
        width = 1.2,
        propModel = nil
    },
    ['meat_grill'] = {
        label = 'Meat Grill',
        icon = 'fas fa-drumstick-bite',
        category = 'cooking',
        maxPerRestaurant = 5,
        animDict = 'amb@prop_human_bbq@male@idle_a',
        animClip = 'idle_b',
        length = 1.4,
        width = 1.2,
        propModel = nil
    },
    ['assembly'] = {
        label = 'Assembly Board',
        icon = 'fas fa-burger',
        category = 'cooking',
        maxPerRestaurant = 6,
        animDict = 'anim@heists@prison_heiststation@cop_reactions',
        animClip = 'cop_b_idle',
        length = 1.4,
        width = 1.2,
        propModel = nil
    },
    ['fry'] = {
        label = 'Deep Fryer',
        icon = 'fas fa-temperature-arrow-up',
        category = 'cooking',
        maxPerRestaurant = 6,
        animDict = 'amb@prop_human_bbq@male@idle_a',
        animClip = 'idle_b',
        length = 1.2,
        width = 1.0,
        propModel = nil
    },
    ['chip_fryer'] = {
        label = 'Chip Fryer',
        icon = 'fas fa-temperature-arrow-up',
        category = 'cooking',
        maxPerRestaurant = 5,
        animDict = 'amb@prop_human_bbq@male@idle_a',
        animClip = 'idle_b',
        length = 1.2,
        width = 1.0,
        propModel = nil
    },
    ['baking_oven'] = {
        label = 'Electric Baking Oven',
        icon = 'fas fa-fire-burner',
        category = 'cooking',
        maxPerRestaurant = 5,
        animDict = 'anim@heists@prison_heiststation@cop_reactions',
        animClip = 'cop_b_idle',
        length = 1.4,
        width = 1.2,
        propModel = nil
    },
    ['drinks'] = {
        label = 'Drink Dispenser',
        icon = 'fas fa-glass-water',
        category = 'cooking',
        maxPerRestaurant = 6,
        animDict = 'mp_ped_interaction',
        animClip = 'handshake_guy_a',
        length = 1.2,
        width = 1.0,
        propModel = nil
    },
    ['coffee'] = {
        label = 'Coffee Machine',
        icon = 'fas fa-mug-hot',
        category = 'cooking',
        maxPerRestaurant = 4,
        animDict = 'mp_ped_interaction',
        animClip = 'handshake_guy_a',
        length = 1.0,
        width = 0.8,
        propModel = nil
    }
}

-- All Granular Permissions Available in System
Config.AllPermissions = {
    { id = 'view_orders', label = 'View & Accept Orders', description = 'Access to live orders tab and can accept/update order status' },
    { id = 'cook', label = 'Cook / Craft Food', description = 'Can interact with cooking stations to prepare meals' },
    { id = 'refund_orders', label = 'Refund / Cancel Orders', description = 'Can cancel orders and issue customer refunds' },
    { id = 'view_history', label = 'View Order History', description = 'View completed and cancelled order history' },
    { id = 'manage_menu', label = 'Manage Menu & Prices', description = 'Edit item prices and visibility' },
    { id = 'manage_stock', label = 'Manage Stock Availability', description = 'Toggle In-Stock / Out-of-Stock and adjust inventory quantities' },
    { id = 'vending_manage', label = 'Vending Manage', description = 'Restock items, set prices, and manage vending machine inventory' },
    { id = 'vending_fund', label = 'Vending Fund', description = 'View accumulated vending revenue and withdraw money from the vending machine fund' },
    { id = 'door_unlock', label = 'Door Unlock', description = 'Can lock and unlock restaurant doors using [E]' },
    { id = 'manage_stations', label = 'Station & Zone Placement', description = 'Place or delete third-eye interaction zones' },
    { id = 'manage_recipes', label = 'Recipe Editor', description = 'Create, update, or disable cooking recipes' },
    { id = 'manage_roles', label = 'Manage Roles & Grades', description = 'Assign granular permissions to staff job grades' },
    { id = 'manage_staff', label = 'Staff & Promotions', description = 'Hire, promote, demote staff and issue official restaurant tablets' },
    { id = 'view_logs', label = 'Audit Logs', description = 'Inspect staff action history, recipe changes, and refunds' }
}

-- ====================================================================
-- MULTI-RESTAURANT & BUSINESS CONFIGURATION
-- This system is 100% UNIVERSAL: It is NOT limited to Burger Shot!
-- You can run UNLIMITED restaurants, cafes, bars, bakeries, pizzerias,
-- diners, taco trucks, or clubs simultaneously with this single resource.
-- Simply add your restaurant/business entry below:
-- ====================================================================
Config.Restaurants = {
    -- 1. Burger Shot (Default Fast Food)
    ['burgershot'] = {
        label = 'Burger Shot',
        job = 'burgershot',
        adminGrade = 10,      -- Grade 10 is Restaurant Admin (Permanent Full Access)
        ownerGrade = 9,       -- Grade 9 in qbx_core / qb-core jobs.lua is Owner (Configurable by Admin)
        managerGrade = 8,     -- Grade 8 is Manager
        societyAccount = 'burgershot', -- Society/Management account for payments
        
        blip = {
            enabled = true,
            coords = vec3(-1192.83, -890.72, 13.99),
            sprite = 106,
            color = 1,
            scale = 0.8,
            name = 'Burger Shot'
        },

        -- Static targets removed so Owner can place all interaction points anywhere via Tablet
        orderingCounters = {},
        dutyTarget = nil,
        managementTerminal = nil
    },

    -- 2. Pizza This (Pizzeria & Italian Restaurant Example)
    -- ['pizzathis'] = {
    --     label = 'Pizza This',
    --     job = 'pizzathis',
    --     adminGrade = 10,
    --     ownerGrade = 4,
    --     managerGrade = 3,
    --     societyAccount = 'pizzathis',
    --     blip = { enabled = true, coords = vec3(797.35, -749.91, 31.27), sprite = 267, color = 1, scale = 0.8, name = 'Pizza This' },
    --     orderingCounters = {}, dutyTarget = nil, managementTerminal = nil
    -- },

    -- 3. UwU Cafe (Cat Cafe, Bubble Tea & Bakery Example)
    -- ['uwu_cafe'] = {
    --     label = 'UwU Cafe',
    --     job = 'uwu_cafe',
    --     adminGrade = 10,
    --     ownerGrade = 4,
    --     managerGrade = 3,
    --     societyAccount = 'uwu_cafe',
    --     blip = { enabled = true, coords = vec3(-580.9, -1066.8, 22.3), sprite = 621, color = 34, scale = 0.8, name = 'UwU Cafe' },
    --     orderingCounters = {}, dutyTarget = nil, managementTerminal = nil
    -- },

    -- 4. Bean Machine (Coffee Shop & Bakery Example)
    -- ['beanmachine'] = {
    --     label = 'Bean Machine Coffee',
    --     job = 'beanmachine',
    --     adminGrade = 10,
    --     ownerGrade = 4,
    --     managerGrade = 3,
    --     societyAccount = 'beanmachine',
    --     blip = { enabled = true, coords = vec3(-628.8, 233.7, 81.8), sprite = 106, color = 21, scale = 0.8, name = 'Bean Machine' },
    --     orderingCounters = {}, dutyTarget = nil, managementTerminal = nil
    -- },

    -- 5. Yellow Jack (Bar, Pub & Grill Example)
    -- ['yellowjack'] = {
    --     label = 'Yellow Jack Inn',
    --     job = 'yellowjack',
    --     adminGrade = 10,
    --     ownerGrade = 4,
    --     managerGrade = 3,
    --     societyAccount = 'yellowjack',
    --     blip = { enabled = true, coords = vec3(1986.2, 3053.6, 47.2), sprite = 93, color = 5, scale = 0.8, name = 'Yellow Jack' },
    --     orderingCounters = {}, dutyTarget = nil, managementTerminal = nil
    -- }
}

-- ====================================================================
-- BURGERSHOT / RESTAURANT MANAGER: OX_INVENTORY ITEMS
-- Copy and paste this block into your:
--   resources/[ox]/ox_inventory/data/items.lua
-- ====================================================================

-- 1. Management Tablet
['burgershot_tablet'] = {
    label = 'Burgershot Tablet',
    weight = 500,
    stack = false,
    close = true,
    description = 'Official Burger Shot company terminal & management tablet for orders, staff, recipes, doors, and stock.',
    client = {
        event = 'burgershot:client:useTablet'
    }
},

-- 2. Raw Ingredients & Cooking Supplies
['bs_meat_pattie'] = {
    label = 'Meat Pattie',
    weight = 150,
    stack = true,
    close = true,
    description = 'A freshly grilled beef meat pattie for Burger Shot burgers.'
},

['bs_burger_bun'] = {
    label = 'Burger Bun',
    weight = 100,
    stack = true,
    close = true,
    description = 'A soft toasted sesame burger bun.'
},

['bs_cheese'] = {
    label = 'Cheese',
    weight = 60,
    stack = true,
    close = true,
    description = 'Sliced cheddar cheese for burgers.'
},

['bs_pepper'] = {
    label = 'Green & Red Pepper',
    weight = 60,
    stack = true,
    close = true,
    description = 'Freshly sliced green and red chilli peppers.'
},

['bs_tomato_lettuce'] = {
    label = 'Tomato & Lettuce',
    weight = 80,
    stack = true,
    close = true,
    description = 'Fresh sliced tomato and crisp lettuce leaves.'
},

['bs_bbq_sauce'] = {
    label = 'BBQ Sauce',
    weight = 100,
    stack = true,
    close = true,
    description = 'Smoky sweet barbecue sauce.'
},

['bs_onion_rings'] = {
    label = 'Onion Rings',
    weight = 100,
    stack = true,
    close = true,
    description = 'Crispy golden fried onion rings.'
},

['bs_bacon'] = {
    label = 'Bacon',
    weight = 80,
    stack = true,
    close = true,
    description = 'Crispy smoked bacon strips.'
},

['bs_ice_cubes'] = {
    label = 'Ice Cubes',
    weight = 80,
    stack = true,
    close = true,
    description = 'Cold clear ice cubes for fountain beverages.'
},

['bs_cola_syrup'] = {
    label = 'Cola Syrup',
    weight = 120,
    stack = true,
    close = true,
    description = 'Concentrated cola flavoring syrup for E-Cola.'
},

['bs_carbonated_water'] = {
    label = 'Carbonated Water',
    weight = 200,
    stack = true,
    close = true,
    description = 'Sparkling carbonated water base for fountain drinks.'
},

['bs_bubbles'] = {
    label = 'Bubbles',
    weight = 100,
    stack = true,
    close = true,
    description = 'Chewy tapioca pearls for Bubble Tea.'
},

['bs_sugar_cubes'] = {
    label = 'Sugar Cubes',
    weight = 60,
    stack = true,
    close = true,
    description = 'Refined sugar cubes for sweetening beverages.'
},

['bs_milk'] = {
    label = 'Milk',
    weight = 200,
    stack = true,
    close = true,
    description = 'Fresh cold milk for creamy drinks and bubble tea.'
},

-- 3. Finished Food & Drinks (Consumables with Eating/Drinking Animations)
['bs_cheese_chilli_burger'] = {
    label = 'Cheese And Chilli Burger',
    weight = 350,
    stack = true,
    rarity = 'rare',
    close = true,
    degrade = 2880,
    decay = true,
    description = 'A juicy grilled meat pattie topped with melted cheddar cheese, fresh veggies, and spicy chilli peppers.',
    client = {
        status = { hunger = 350000 },
        anim = 'eating',
        prop = 'burger',
        usetime = 2500,
        notification = 'You ate a delicious Cheese And Chilli Burger'
    }
},

['bs_bbq_burger'] = {
    label = 'BBQ Burger',
    weight = 350,
    stack = true,
    rarity = 'rare',
    close = true,
    degrade = 2880,
    decay = true,
    description = 'Loaded with crispy bacon, onion rings, melted cheese, fresh tomato & lettuce, and smoky BBQ sauce.',
    client = {
        status = { hunger = 380000 },
        anim = 'eating',
        prop = 'burger',
        usetime = 2500,
        notification = 'You ate a smoky BBQ Burger'
    }
},

['bs_ecola'] = {
    label = 'E-Cola',
    weight = 300,
    stack = true,
    rarity = 'rare',
    close = true,
    degrade = 2880,
    decay = true,
    description = 'Ice-cold fizzy E-Cola served fresh from the Burger Shot dispenser.',
    client = {
        status = { thirst = 280000 },
        anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
        prop = { model = `prop_ld_can_01`, pos = vec3(0.01, 0.01, 0.06), rot = vec3(5.0, 5.0, -180.5) },
        usetime = 2500,
        notification = 'You drank a refreshing E-Cola'
    }
},

['bs_bubble_tea'] = {
    label = 'Bubble Tea',
    weight = 300,
    stack = true,
    rarity = 'rare',
    close = true,
    degrade = 2880,
    decay = true,
    description = 'Sweet creamy iced milk tea loaded with chewy tapioca bubbles.',
    client = {
        status = { thirst = 320000 },
        anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
        prop = { model = `prop_ld_can_01`, pos = vec3(0.01, 0.01, 0.06), rot = vec3(5.0, 5.0, -180.5) },
        usetime = 2500,
        notification = 'You drank a sweet Bubble Tea'
    }
},


-- ====================================================================
-- BURGERSHOT / RESTAURANT MANAGER: QB-CORE / QB-INVENTORY ITEMS
-- Copy and paste this block into your:
--   resources/[qb]/qb-core/shared/items.lua
-- ====================================================================

-- 1. Management Tablet
['burgershot_tablet'] = {
    name = 'burgershot_tablet',
    label = 'Burgershot Tablet',
    weight = 500,
    type = 'item',
    image = 'burgershot_tablet.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Official Burger Shot company terminal & management tablet.'
},

-- 2. Raw Ingredients & Cooking Supplies
['bs_meat_pattie'] = {
    name = 'bs_meat_pattie',
    label = 'Meat Pattie',
    weight = 150,
    type = 'item',
    image = 'bs_meat_pattie.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'A freshly grilled beef meat pattie for Burger Shot burgers.'
},

['bs_burger_bun'] = {
    name = 'bs_burger_bun',
    label = 'Burger Bun',
    weight = 100,
    type = 'item',
    image = 'bs_burger_bun.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'A soft toasted sesame burger bun.'
},

['bs_cheese'] = {
    name = 'bs_cheese',
    label = 'Cheese',
    weight = 60,
    type = 'item',
    image = 'bs_cheese.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Sliced cheddar cheese for burgers.'
},

['bs_pepper'] = {
    name = 'bs_pepper',
    label = 'Green & Red Pepper',
    weight = 60,
    type = 'item',
    image = 'bs_pepper.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Freshly sliced green and red chilli peppers.'
},

['bs_tomato_lettuce'] = {
    name = 'bs_tomato_lettuce',
    label = 'Tomato & Lettuce',
    weight = 80,
    type = 'item',
    image = 'bs_tomato_lettuce.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Fresh sliced tomato and crisp lettuce leaves.'
},

['bs_bbq_sauce'] = {
    name = 'bs_bbq_sauce',
    label = 'BBQ Sauce',
    weight = 100,
    type = 'item',
    image = 'bs_bbq_sauce.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Smoky sweet barbecue sauce.'
},

['bs_onion_rings'] = {
    name = 'bs_onion_rings',
    label = 'Onion Rings',
    weight = 100,
    type = 'item',
    image = 'bs_onion_rings.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Crispy golden fried onion rings.'
},

['bs_bacon'] = {
    name = 'bs_bacon',
    label = 'Bacon',
    weight = 80,
    type = 'item',
    image = 'bs_bacon.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Crispy smoked bacon strips.'
},

['bs_ice_cubes'] = {
    name = 'bs_ice_cubes',
    label = 'Ice Cubes',
    weight = 80,
    type = 'item',
    image = 'bs_ice_cubes.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Cold clear ice cubes for fountain beverages.'
},

['bs_cola_syrup'] = {
    name = 'bs_cola_syrup',
    label = 'Cola Syrup',
    weight = 120,
    type = 'item',
    image = 'bs_cola_syrup.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Concentrated cola flavoring syrup for E-Cola.'
},

['bs_carbonated_water'] = {
    name = 'bs_carbonated_water',
    label = 'Carbonated Water',
    weight = 200,
    type = 'item',
    image = 'bs_carbonated_water.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Sparkling carbonated water base for fountain drinks.'
},

['bs_bubbles'] = {
    name = 'bs_bubbles',
    label = 'Bubbles',
    weight = 100,
    type = 'item',
    image = 'bs_bubbles.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Chewy tapioca pearls for Bubble Tea.'
},

['bs_sugar_cubes'] = {
    name = 'bs_sugar_cubes',
    label = 'Sugar Cubes',
    weight = 60,
    type = 'item',
    image = 'bs_sugar_cubes.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Refined sugar cubes for sweetening beverages.'
},

['bs_milk'] = {
    name = 'bs_milk',
    label = 'Milk',
    weight = 200,
    type = 'item',
    image = 'bs_milk.png',
    unique = false,
    useable = false,
    shouldClose = false,
    combinable = nil,
    description = 'Fresh cold milk for creamy drinks and bubble tea.'
},

-- 3. Finished Meals & Drinks (Consumables)
['bs_cheese_chilli_burger'] = {
    name = 'bs_cheese_chilli_burger',
    label = 'Cheese And Chilli Burger',
    weight = 350,
    type = 'item',
    image = 'bs_cheese_chilli_burger.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'A juicy grilled meat pattie topped with melted cheddar cheese, fresh veggies, and spicy chilli peppers.'
},

['bs_bbq_burger'] = {
    name = 'bs_bbq_burger',
    label = 'BBQ Burger',
    weight = 350,
    type = 'item',
    image = 'bs_bbq_burger.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Loaded with crispy bacon, onion rings, melted cheese, fresh tomato & lettuce, and smoky BBQ sauce.'
},

['bs_ecola'] = {
    name = 'bs_ecola',
    label = 'E-Cola',
    weight = 300,
    type = 'item',
    image = 'bs_ecola.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Ice-cold fizzy E-Cola served fresh from the Burger Shot dispenser.'
},

['bs_bubble_tea'] = {
    name = 'bs_bubble_tea',
    label = 'Bubble Tea',
    weight = 300,
    type = 'item',
    image = 'bs_bubble_tea.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Sweet creamy iced milk tea loaded with chewy tapioca bubbles.'
},


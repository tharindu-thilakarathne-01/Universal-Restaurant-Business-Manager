-- ====================================================================
-- RESTAURANT MANAGER (BURGER SHOT): COMPLETE FACTORY RESET SCRIPT
-- Clears all placed stations, doors, test recipes, orders, logs, staff hours
-- and resets roles and menu items to clean factory defaults.
-- ====================================================================

-- 1. Wipe Dynamic Placements & Runtime Data
TRUNCATE TABLE `rm_stations`;
TRUNCATE TABLE `rm_doors`;
TRUNCATE TABLE `rm_orders`;
TRUNCATE TABLE `rm_logs`;
TRUNCATE TABLE `rm_staff_hours`;
TRUNCATE TABLE `rm_settings`;
TRUNCATE TABLE `rm_vending_funds`;
TRUNCATE TABLE `rm_vending_items`;

-- 2. Wipe Recipes & Menu State
TRUNCATE TABLE `rm_recipes`;
TRUNCATE TABLE `rm_menu_state`;
TRUNCATE TABLE `rm_roles`;

-- 3. Seed Clean Default Roles (Grades 0 - 10)
INSERT INTO `rm_roles` (`restaurant_id`, `grade`, `role_name`, `permissions`, `is_owner`)
VALUES 
('burgershot', 10, 'Admin', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock","vending_manage","vending_fund","door_unlock","manage_stations","manage_recipes","manage_roles","manage_staff","view_logs"]', 1),
('burgershot', 9, 'Owner', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock","vending_manage","vending_fund","door_unlock","manage_stations","manage_recipes","manage_roles","manage_staff","view_logs"]', 1),
('burgershot', 8, 'Manager', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock","vending_manage","vending_fund","door_unlock","manage_staff","view_logs"]', 0),
('burgershot', 7, 'Assistant Manager', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock","door_unlock"]', 0),
('burgershot', 6, 'Supervisor', '["view_orders","cook","view_history","manage_stock","door_unlock"]', 0),
('burgershot', 5, 'Shift Lead', '["view_orders","cook","view_history","door_unlock"]', 0),
('burgershot', 4, 'Cashier', '["view_orders","cook","door_unlock"]', 0),
('burgershot', 3, 'Senior Cook', '["view_orders","cook","door_unlock"]', 0),
('burgershot', 2, 'Cook', '["view_orders","cook","door_unlock"]', 0),
('burgershot', 1, 'Crew Member', '["view_orders","cook","door_unlock"]', 0),
('burgershot', 0, 'Trainee', '["view_orders","cook"]', 0);

-- 4. Seed Clean Default Recipes (Burgershot Official Menu)
INSERT INTO `rm_recipes` (`restaurant_id`, `recipe_name`, `station_type`, `ingredients`, `output_item`, `output_count`, `cooking_time`, `enabled`)
VALUES
('burgershot', 'Cheese And Chilli Burger', 'assembly', '[{"item":"bs_meat_pattie","count":1},{"item":"bs_burger_bun","count":1},{"item":"bs_cheese","count":1},{"item":"bs_pepper","count":1},{"item":"bs_tomato_lettuce","count":1}]', 'bs_cheese_chilli_burger', 1, 6000, 1),
('burgershot', 'BBQ Burger', 'assembly', '[{"item":"bs_bbq_sauce","count":1},{"item":"bs_cheese","count":1},{"item":"bs_tomato_lettuce","count":1},{"item":"bs_onion_rings","count":1},{"item":"bs_burger_bun","count":1},{"item":"bs_bacon","count":1}]', 'bs_bbq_burger', 1, 7000, 1),
('burgershot', 'E-Cola', 'drinks', '[{"item":"bs_ice_cubes","count":1},{"item":"bs_cola_syrup","count":1},{"item":"bs_carbonated_water","count":1}]', 'bs_ecola', 1, 3500, 1),
('burgershot', 'Bubble tea', 'drinks', '[{"item":"bs_bubbles","count":1},{"item":"bs_ice_cubes","count":1},{"item":"bs_sugar_cubes","count":1},{"item":"bs_milk","count":1}]', 'bs_bubble_tea', 1, 4000, 1);

-- 5. Seed Clean Default Menu State
INSERT INTO `rm_menu_state` (`restaurant_id`, `item_name`, `label`, `price`, `in_stock`, `stock_count`, `category`)
VALUES
('burgershot', 'bs_cheese_chilli_burger', 'Cheese And Chilli Burger', 18, 1, -1, 'food'),
('burgershot', 'bs_bbq_burger', 'BBQ Burger', 20, 1, -1, 'food'),
('burgershot', 'bs_ecola', 'E-Cola', 5, 1, -1, 'drinks'),
('burgershot', 'bs_bubble_tea', 'Bubble tea', 8, 1, -1, 'drinks');


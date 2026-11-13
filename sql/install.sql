-- ====================================================================
-- RESTAURANT MANAGER (MULTI-RESTAURANT) DATABASE SCHEMA
-- Prefix: rm_
-- Compatible with oxmysql and MySQL 5.7+ / MariaDB 10.3+
-- ====================================================================

-- 1. STATIONS TABLE
CREATE TABLE IF NOT EXISTS `rm_stations` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `restaurant_id` VARCHAR(50) NOT NULL,
    `station_type` VARCHAR(50) NOT NULL,
    `coords` LONGTEXT NOT NULL COMMENT 'JSON string containing x, y, z, heading, length, width, minZ, maxZ',
    `created_by` VARCHAR(60) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_rm_stations_res` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. ROLES & PERMISSIONS TABLE
CREATE TABLE IF NOT EXISTS `rm_roles` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `restaurant_id` VARCHAR(50) NOT NULL,
    `grade` INT NOT NULL,
    `role_name` VARCHAR(50) NOT NULL,
    `permissions` LONGTEXT NOT NULL COMMENT 'JSON array of permission IDs',
    `base_salary` INT NOT NULL DEFAULT 0 COMMENT 'Periodic base paycheck amount per interval',
    `is_owner` TINYINT(1) DEFAULT 0,
    UNIQUE KEY `uk_res_grade` (`restaurant_id`, `grade`),
    INDEX `idx_rm_roles_res` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. RECIPES TABLE
CREATE TABLE IF NOT EXISTS `rm_recipes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `restaurant_id` VARCHAR(50) NOT NULL,
    `recipe_name` VARCHAR(100) NOT NULL,
    `station_type` VARCHAR(50) NOT NULL,
    `ingredients` LONGTEXT NOT NULL COMMENT 'JSON array: [{"item":"bs_bun","count":1}]',
    `output_item` VARCHAR(60) NOT NULL,
    `output_count` INT NOT NULL DEFAULT 1,
    `cooking_time` INT NOT NULL DEFAULT 5000 COMMENT 'Duration in milliseconds',
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    INDEX `idx_rm_recipes_res_station` (`restaurant_id`, `station_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. ORDERS TABLE
CREATE TABLE IF NOT EXISTS `rm_orders` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `restaurant_id` VARCHAR(50) NOT NULL,
    `customer_identifier` VARCHAR(60) NOT NULL,
    `customer_name` VARCHAR(100) NOT NULL,
    `items` LONGTEXT NOT NULL COMMENT 'JSON array: [{"item":"bs_classic_burger","name":"Classic Burger","count":2,"price":15}]',
    `total_price` INT NOT NULL,
    `tax_amount` INT NOT NULL DEFAULT 0,
    `payment_method` VARCHAR(20) NOT NULL DEFAULT 'cash',
    `status` ENUM('pending', 'accepted', 'cooking', 'ready', 'delivered', 'cancelled') NOT NULL DEFAULT 'pending',
    `claimed_by` VARCHAR(60) DEFAULT NULL,
    `claimed_name` VARCHAR(100) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_rm_orders_res_status` (`restaurant_id`, `status`),
    INDEX `idx_rm_orders_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. MENU & STOCK STATE TABLE
CREATE TABLE IF NOT EXISTS `rm_menu_state` (
    `restaurant_id` VARCHAR(50) NOT NULL,
    `item_name` VARCHAR(60) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `price` INT NOT NULL DEFAULT 10,
    `in_stock` TINYINT(1) NOT NULL DEFAULT 1,
    `stock_count` INT NOT NULL DEFAULT -1 COMMENT '-1 means unlimited stock',
    `category` VARCHAR(50) NOT NULL DEFAULT 'food',
    PRIMARY KEY (`restaurant_id`, `item_name`),
    INDEX `idx_rm_menu_res` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. AUDIT LOGS TABLE
CREATE TABLE IF NOT EXISTS `rm_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `restaurant_id` VARCHAR(50) NOT NULL,
    `citizenid` VARCHAR(60) NOT NULL,
    `player_name` VARCHAR(100) NOT NULL,
    `action` VARCHAR(50) NOT NULL,
    `details` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_rm_logs_res_time` (`restaurant_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. RESTAURANT SETTINGS TABLE (Tax & General Settings)
CREATE TABLE IF NOT EXISTS `rm_settings` (
    `restaurant_id` VARCHAR(50) NOT NULL,
    `setting_key` VARCHAR(50) NOT NULL,
    `setting_value` LONGTEXT NOT NULL,
    PRIMARY KEY (`restaurant_id`, `setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. VENDING MACHINE FUND TABLE
CREATE TABLE IF NOT EXISTS `rm_vending_funds` (
    `restaurant_id` VARCHAR(50) NOT NULL,
    `balance` INT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 9. RESTAURANT DOOR LOCKS TABLE
CREATE TABLE IF NOT EXISTS `rm_doors` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `restaurant_id` VARCHAR(50) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `door_data` LONGTEXT NOT NULL COMMENT 'JSON: center coords, maxDistance, isDouble, leaves',
    `locked` TINYINT(1) NOT NULL DEFAULT 1,
    `created_by` VARCHAR(60) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_rm_doors_res` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ====================================================================
-- SEED DATA FOR BURGERSHOT (DEFAULT SETUP)
-- ====================================================================

-- Default Roles for Burgershot (All job grades 0-10)
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
('burgershot', 0, 'Trainee', '["view_orders","cook"]', 0)
ON DUPLICATE KEY UPDATE `permissions` = VALUES(`permissions`);

-- Default Recipes for Burgershot (Custom Recipes)
INSERT INTO `rm_recipes` (`restaurant_id`, `recipe_name`, `station_type`, `ingredients`, `output_item`, `output_count`, `cooking_time`, `enabled`)
VALUES
('burgershot', 'Cheese And Chilli Burger', 'assembly', '[{"item":"bs_meat_pattie","count":1},{"item":"bs_burger_bun","count":1},{"item":"bs_cheese","count":1},{"item":"bs_pepper","count":1},{"item":"bs_tomato_lettuce","count":1}]', 'bs_cheese_chilli_burger', 1, 6000, 1),
('burgershot', 'BBQ Burger', 'assembly', '[{"item":"bs_bbq_sauce","count":1},{"item":"bs_cheese","count":1},{"item":"bs_tomato_lettuce","count":1},{"item":"bs_onion_rings","count":1},{"item":"bs_burger_bun","count":1},{"item":"bs_bacon","count":1}]', 'bs_bbq_burger', 1, 7000, 1),
('burgershot', 'E-Cola', 'drinks', '[{"item":"bs_ice_cubes","count":1},{"item":"bs_cola_syrup","count":1},{"item":"bs_carbonated_water","count":1}]', 'bs_ecola', 1, 3500, 1),
('burgershot', 'Bubble tea', 'drinks', '[{"item":"bs_bubbles","count":1},{"item":"bs_ice_cubes","count":1},{"item":"bs_sugar_cubes","count":1},{"item":"bs_milk","count":1}]', 'bs_bubble_tea', 1, 4000, 1);

-- Default Menu State & Prices for Burgershot
INSERT INTO `rm_menu_state` (`restaurant_id`, `item_name`, `label`, `price`, `in_stock`, `stock_count`, `category`)
VALUES
('burgershot', 'bs_cheese_chilli_burger', 'Cheese And Chilli Burger', 18, 1, -1, 'food'),
('burgershot', 'bs_bbq_burger', 'BBQ Burger', 20, 1, -1, 'food'),
('burgershot', 'bs_ecola', 'E-Cola', 5, 1, -1, 'drinks'),
('burgershot', 'bs_bubble_tea', 'Bubble tea', 8, 1, -1, 'drinks')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `price` = VALUES(`price`);


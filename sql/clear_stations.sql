-- ====================================================================
-- CLEAR ALL PREVIOUS BURGERSHOT THIRD-EYE STATIONS & TARGET ZONES
-- Execute this query if you want to wipe any old placed zones from database
-- ====================================================================

TRUNCATE TABLE `rm_stations`;

-- Alternatively, delete only Burger Shot stations if multi-restaurant is used:
-- DELETE FROM `rm_stations` WHERE `restaurant_id` = 'burgershot';

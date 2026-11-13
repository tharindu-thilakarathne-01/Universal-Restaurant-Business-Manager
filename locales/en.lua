Locales = Locales or {}

Locales['en'] = {
    -- General & Notifications
    ['restaurant_not_found'] = 'Invalid restaurant configuration.',
    ['not_on_duty'] = 'You must be on duty to perform this action!',
    ['no_permission'] = 'You do not have permission to do this.',
    ['too_far_away'] = 'You are too far away!',
    ['rate_limited'] = 'Please wait a moment before trying again.',
    ['invalid_data'] = 'Invalid request data received.',
    ['station_limit_reached'] = 'Maximum limit of %s stations reached for this restaurant.',
    ['station_created'] = 'Station %s created successfully.',
    ['station_deleted'] = 'Station removed successfully.',
    
    -- Orders
    ['no_staff_on_duty'] = 'No restaurant staff currently on duty. Counter is temporarily closed.',
    ['cart_empty'] = 'Your cart is empty!',
    ['insufficient_funds'] = 'You do not have enough money (%s: $%s required).',
    ['order_placed'] = 'Order #%s placed successfully for $%s.',
    ['new_order_received'] = 'New Order #%s received!',
    ['order_claimed'] = 'Order #%s has been claimed by %s.',
    ['order_already_claimed'] = 'This order has already been claimed by another employee.',
    ['order_status_updated'] = 'Order #%s status changed to %s.',
    ['order_cancelled'] = 'Order #%s has been cancelled.',
    ['order_refunded'] = 'Order #%s was refunded ($%s returned).',
    ['item_out_of_stock'] = 'Item %s is currently out of stock.',
    
    -- Cooking
    ['cooking_started'] = 'Preparing %s...',
    ['cooking_success'] = 'Finished preparing %s!',
    ['cooking_cancelled'] = 'Cooking was cancelled.',
    ['missing_ingredients'] = 'You do not have the required ingredients for this recipe!',
    ['inventory_full'] = 'Your inventory is too full to hold the prepared item!',
    ['wrong_station'] = 'This recipe cannot be prepared at this station.',
    
    -- Stock & Management
    ['stock_updated'] = 'Stock updated for %s.',
    ['recipe_saved'] = 'Recipe %s saved successfully.',
    ['recipe_deleted'] = 'Recipe removed.',
    ['role_updated'] = 'Role permissions updated.',
    ['cannot_edit_owner_lockout'] = 'Owner role permissions are locked and cannot be removed.',
    ['duty_on'] = 'You clocked IN for %s.',
    ['duty_off'] = 'You clocked OUT.'
}

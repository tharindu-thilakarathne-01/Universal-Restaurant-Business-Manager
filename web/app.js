// ====================================================================
// RESTAURANT MANAGER: CLIENT NUI APP LOGIC
// Plain Modern JavaScript, Reactive UI State & Zero External Libraries
// ====================================================================

const RESOURCE_NAME = (window.GetParentResourceName ? window.GetParentResourceName() : 'burgershot');

const AppState = {
    restaurantId: null,
    restaurantLabel: 'Restaurant',
    isEmployee: false,
    onduty: false,
    grade: 0,
    isOwner: false,
    isAdmin: false,
    canEditOwnerRole: false,
    isManager: false,
    permissions: {},
    allPermissionsList: [],
    roles: [],
    stationTypes: {},
    menu: [],
    cart: [],
    activeOrders: {},
    recipes: {},
    stations: {},
    doors: [],
    oxItems: [],
    vendingItems: [],
    vendingInventory: [],
    vendingCart: [],
    vendingFundBalance: 0,
    vendingOnlyMode: false,
    vendingPaymentMethod: 'cash',
    settings: { tax_rate: 10 }
};

// Safe Post to NUI
async function postNUI(callbackName, data = {}) {
    try {
        const response = await fetch(`https://${RESOURCE_NAME}/${callbackName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        });
        return await response.json();
    } catch (err) {
        return null;
    }
}

// Show Toast Notification
function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => {
        toast.remove();
    }, 4000);
}

// ====================================================================
// ITEM IMAGE RESOLUTION & MULTI-TIER FALLBACK
// ====================================================================
function handleImgFallback(imgEl, itemName) {
    if (!imgEl) return;
    // Tier 1: Try ox_inventory with .jpg
    if (!imgEl.getAttribute('data-tried-ox-jpg')) {
        imgEl.setAttribute('data-tried-ox-jpg', 'true');
        imgEl.src = `nui://ox_inventory/web/images/${itemName}.jpg`;
        return;
    }
    // Tier 2: Try label-based image if available
    const label = (typeof getStationItemLabel === 'function') ? getStationItemLabel(itemName) : '';
    if (label && label !== itemName && !imgEl.getAttribute('data-tried-label')) {
        imgEl.setAttribute('data-tried-label', 'true');
        imgEl.src = `nui://ox_inventory/web/images/${label}.jpg`;
        return;
    }
    // Tier 3: Try local burgershot web/images
    if (!imgEl.getAttribute('data-tried-local-png')) {
        imgEl.setAttribute('data-tried-local-png', 'true');
        imgEl.src = `images/${itemName}.png`;
        return;
    }
    if (!imgEl.getAttribute('data-tried-local-jpg')) {
        imgEl.setAttribute('data-tried-local-jpg', 'true');
        imgEl.src = `images/${itemName}.jpg`;
        return;
    }
    // Tier 4: Try local placeholder SVG
    if (!imgEl.getAttribute('data-tried-placeholder')) {
        imgEl.setAttribute('data-tried-placeholder', 'true');
        imgEl.src = 'images/placeholder.svg';
        return;
    }
    // Tier 5: FontAwesome Icon
    imgEl.style.display = 'none';
    if (imgEl.parentElement && !imgEl.parentElement.querySelector('.fallback-icon')) {
        const icon = document.createElement('i');
        icon.className = 'fa-solid fa-burger fallback-icon';
        imgEl.parentElement.appendChild(icon);
    }
}

let doorAudioCtx = null;
function playDoorLockTone(locked, volume = 1.0) {
    try {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return;
        if (!doorAudioCtx) doorAudioCtx = new AudioCtx();
        if (doorAudioCtx.state === 'suspended') {
            doorAudioCtx.resume().catch(() => {});
        }

        const now = doorAudioCtx.currentTime;
        const scale = Math.max(0.15, Math.min(1.0, Number(volume) || 1.0));
        const notes = locked
            ? [{ freq: 640, start: 0, dur: 0.065 }, { freq: 440, start: 0.068, dur: 0.12 }]
            : [{ freq: 587.33, start: 0, dur: 0.065 }, { freq: 880, start: 0.065, dur: 0.13 }];

        notes.forEach((n) => {
            const osc = doorAudioCtx.createOscillator();
            const gain = doorAudioCtx.createGain();
            osc.type = 'triangle';
            osc.frequency.setValueAtTime(n.freq, now + n.start);

            const peak = 0.14 * scale;
            gain.gain.setValueAtTime(0.0001, now + n.start);
            gain.gain.exponentialRampToValueAtTime(peak, now + n.start + 0.012);
            gain.gain.exponentialRampToValueAtTime(0.0001, now + n.start + n.dur);

            osc.connect(gain);
            gain.connect(doorAudioCtx.destination);
            osc.start(now + n.start);
            osc.stop(now + n.start + n.dur + 0.02);
        });
    } catch (_) {
        // Ignore audio playback errors if browser blocks audio context
    }
}

// ====================================================================
// WINDOW & MESSAGE LISTENERS
// ====================================================================
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {
        case 'openStationCooking':
            initStationCookingView(data);
            break;
        case 'openCustomer':
            initCustomerView(data);
            break;
        case 'openVending':
            initVendingCustomerView(data);
            break;
        case 'openManagement':
            initManagementView(data);
            break;
        case 'syncVending':
            handleSyncVending(data.restaurantId, data.items);
            break;
        case 'syncVendingFund':
            handleSyncVendingFund(data.restaurantId, data.balance);
            break;
        case 'close':
            closeApp();
            break;
        case 'orderReceived':
            handleOrderReceived(data.order);
            break;
        case 'orderUpdated':
            handleOrderUpdated(data.order);
            break;
        case 'syncMenuState':
            handleSyncMenuState(data.restaurantId, data.itemName, data.state);
            break;
        case 'syncPrice':
            handleSyncPrice(data.restaurantId, data.itemName, data.price);
            break;
        case 'syncSettings':
            handleSyncSettings(data.restaurantId, data.settings);
            break;
        case 'stationAdded':
            if (data.station) {
                if (Array.isArray(AppState.stations)) {
                    AppState.stations = AppState.stations.filter(s => s && s.id !== data.station.id);
                    AppState.stations.push(data.station);
                } else {
                    AppState.stations = AppState.stations || {};
                    AppState.stations[data.station.id] = data.station;
                }
                renderOwnerStationsTable();
            }
            break;
        case 'stationRemoved':
            if (data.stationId) {
                const sid = Number(data.stationId);
                if (Array.isArray(AppState.stations)) {
                    AppState.stations = AppState.stations.filter(s => s && s.id !== sid);
                } else if (AppState.stations) {
                    delete AppState.stations[sid];
                    delete AppState.stations[String(sid)];
                }
                renderOwnerStationsTable();
            }
            break;
        case 'allStationsRemoved':
            AppState.stations = [];
            renderOwnerStationsTable();
            break;
        case 'doorAdded':
            if (data.door) {
                const list = Array.isArray(AppState.doors) ? AppState.doors : [];
                AppState.doors = list.filter(d => d && d.id !== data.door.id);
                AppState.doors.push(data.door);
                renderOwnerDoorsTable();
            }
            break;
        case 'doorStateUpdated':
            if (data.doorId !== undefined) {
                const did = Number(data.doorId);
                AppState.doors = (Array.isArray(AppState.doors) ? AppState.doors : []).map(d =>
                    (d && Number(d.id) === did) ? { ...d, locked: !!data.locked } : d
                );
                renderOwnerDoorsTable();
            }
            break;
        case 'doorAutoLockUpdated':
            if (data.doorId !== undefined) {
                const did = Number(data.doorId);
                AppState.doors = (Array.isArray(AppState.doors) ? AppState.doors : []).map(d =>
                    (d && Number(d.id) === did) ? { ...d, autoLock: !!data.autoLock } : d
                );
                renderOwnerDoorsTable();
            }
            break;
        case 'playDoorTone':
            playDoorLockTone(!!data.locked, data.volume);
            break;
        case 'doorRemoved':
            if (data.doorId !== undefined) {
                const did = Number(data.doorId);
                AppState.doors = (Array.isArray(AppState.doors) ? AppState.doors : []).filter(d => d && Number(d.id) !== did);
                renderOwnerDoorsTable();
            }
            break;
        case 'allDoorsRemoved':
            AppState.doors = [];
            renderOwnerDoorsTable();
            break;
        case 'syncRecipes':
            if (!data.restaurantId || data.restaurantId === AppState.restaurantId) {
                AppState.recipes = Array.isArray(data.recipes) ? data.recipes : Object.values(data.recipes || {});
                renderOwnerRecipesTable();
                renderStaffRecipes();

                const stationView = document.getElementById('station-cooking-view');
                if (stationView && !stationView.classList.contains('hidden')) {
                    const stType = StationCookingState.stationType;
                    StationCookingState.recipes = AppState.recipes.filter(r => r && r.enabled && r.station_type === stType);
                    const prevId = StationCookingState.selectedRecipe ? Number(StationCookingState.selectedRecipe.id) : null;
                    const searchEl = document.getElementById('station-recipe-search');
                    const query = searchEl ? searchEl.value : '';
                    renderStationRecipesList(query);

                    if (StationCookingState.recipes.length > 0) {
                        const match = prevId
                            ? StationCookingState.recipes.find(r => Number(r.id) === prevId)
                            : null;
                        selectStationRecipe(match || StationCookingState.recipes[0]);
                    } else {
                        StationCookingState.selectedRecipe = null;
                        const emptyState = document.getElementById('station-empty-state');
                        const panel = document.getElementById('station-recipe-panel');
                        if (emptyState) emptyState.classList.remove('hidden');
                        if (panel) panel.classList.add('hidden');
                    }
                }
            }
            break;
    }
});

// Close UI on ESC key
window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        const settingsModal = document.getElementById('ui-settings-modal');
        const recipeModal = document.getElementById('recipe-modal');
        const roleModal = document.getElementById('role-modal');
        if (settingsModal && !settingsModal.classList.contains('hidden')) {
            closeUiSettingsModal();
        } else if (roleModal && !roleModal.classList.contains('hidden')) {
            closeRoleModal();
        } else if (recipeModal && !recipeModal.classList.contains('hidden')) {
            closeRecipeModal();
        } else {
            closeApp();
        }
    }
});

document.getElementById('btn-close').addEventListener('click', closeApp);

function closeApp() {
    const appEl = document.getElementById('app');
    if (appEl) {
        appEl.classList.add('hidden');
        appEl.style.display = 'none';
    }
    const stationView = document.getElementById('station-cooking-view');
    if (stationView) {
        stationView.classList.add('hidden');
        stationView.style.display = 'none';
    }

    const vendingView = document.getElementById('vending-customer-view');
    if (vendingView) {
        vendingView.classList.add('hidden');
        vendingView.style.display = 'none';
    }
    AppState.vendingCart = [];
    AppState.vendingOnlyMode = false;
    const roleModal = document.getElementById('role-modal');
    if (roleModal) {
        roleModal.classList.add('hidden');
    }
    const windowContainer = document.getElementById('main-window') || document.querySelector('.window-container');
    if (windowContainer) {
        windowContainer.classList.add('hidden');
        windowContainer.style.display = 'none';
    }
    const modal = document.getElementById('recipe-modal');
    if (modal) {
        modal.classList.add('hidden');
        modal.style.display = 'none';
    }
    const settingsModal = document.getElementById('ui-settings-modal');
    if (settingsModal) {
        settingsModal.classList.add('hidden');
        settingsModal.style.display = 'none';
    }
    postNUI('closeUI');
}

// ====================================================================
// TAB NAVIGATION
// ====================================================================
document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const targetTab = btn.getAttribute('data-tab');
        switchMainTab(targetTab);
    });
});

function switchMainTab(tabId, skipFetch = false) {
    if (!tabId) return;
    const activeBtn = document.querySelector(`.nav-btn[data-tab="${tabId}"]`);
    if (activeBtn && activeBtn.classList.contains('hidden')) {
        return;
    }

    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));

    const activePane = document.getElementById(tabId);
    if (activeBtn) activeBtn.classList.add('active');
    if (activePane) activePane.classList.add('active');

    // Trigger tab specific data refreshes
    if (tabId === 'employee-tab') {
        renderKanbanBoard();
        if (!skipFetch) {
            refreshActiveOrders();
        }
    } else if (tabId === 'manager-tab') {
        if (AppState.vendingOnlyMode) {
            loadManagerVending();
            loadManagerVendingFund();
        } else {
            loadManagerHistory();
            loadManagerStaff();
            loadManagerVending();
            loadManagerVendingFund();
            renderManagerStockTable();
        }
    } else if (tabId === 'recipes-tab') {
        loadOxItems().then(() => renderStaffRecipes());
    } else if (tabId === 'owner-tab') {
        loadOwnerRoles();
        loadOwnerLogs();
        loadOxItems().then(() => renderOwnerRecipesTable());
        renderOwnerStationsTable();
        renderOwnerDoorsTable();
        renderOwnerRecipesTable();
    }
}

// Sub-Tab Navigation (Manager & Owner)
document.querySelectorAll('.sub-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
        const parent = btn.closest('.tab-pane');
        const targetSub = btn.getAttribute('data-sub');

        parent.querySelectorAll('.sub-btn').forEach(b => b.classList.remove('active'));
        parent.querySelectorAll('.sub-pane').forEach(p => p.classList.remove('active'));

        btn.classList.add('active');
        const pane = document.getElementById(targetSub);
        if (pane) pane.classList.add('active');

        if (targetSub === 'manager-staff') {
            loadManagerStaff();
        } else if (targetSub === 'manager-history') {
            loadManagerHistory();
        } else if (targetSub === 'manager-vending') {
            loadManagerVending();
        } else if (targetSub === 'manager-vending-fund') {
            loadManagerVendingFund();
        } else if (targetSub === 'owner-stations') {
            renderOwnerStationsTable();
        } else if (targetSub === 'owner-doors') {
            renderOwnerDoorsTable();
        } else if (targetSub === 'owner-recipe-editor') {
            renderOwnerRecipesTable();
        } else if (targetSub === 'owner-roles' || targetSub === 'owner-salary') {
            loadOwnerRoles();
        } else if (targetSub === 'owner-logs') {
            loadOwnerLogs();
        } else if (targetSub === 'owner-give-tablet') {
            loadOwnerGiveTablet();
        }
    });
});

// ====================================================================
// VIEW 1: CUSTOMER VIEW & CART SYSTEM
// ====================================================================
function initCustomerView(data) {
    AppState.restaurantId = data.restaurantId;
    AppState.restaurantLabel = data.restaurantLabel || 'Restaurant';
    AppState.menu = data.menu || [];
    AppState.settings = data.settings || { tax_rate: 10 };
    AppState.cart = [];

    document.getElementById('restaurant-name').textContent = AppState.restaurantLabel;
    document.getElementById('role-badge').textContent = 'Customer Ordering';

    // Show customer tab and hide staff tabs
    const customerBtn = document.getElementById('tab-btn-customer');
    if (customerBtn) {
        customerBtn.classList.remove('hidden');
        customerBtn.style.display = 'inline-flex';
    }
    ['tab-btn-employee', 'tab-btn-recipes', 'tab-btn-manager', 'tab-btn-owner'].forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            el.classList.add('hidden');
            el.style.display = 'none';
        }
    });
    const navTabs = document.getElementById('nav-tabs');
    if (navTabs) navTabs.style.display = 'flex';

    switchMainTab('customer-tab', true);
    renderMenuGrid('all');
    renderCart();

    const stationView = document.getElementById('station-cooking-view');
    if (stationView) {
        stationView.classList.add('hidden');
        stationView.style.display = 'none';
    }

    const vendingView = document.getElementById('vending-customer-view');
    if (vendingView) {
        vendingView.classList.add('hidden');
        vendingView.style.display = 'none';
    }
    AppState.vendingCart = [];

    const windowContainer = document.getElementById('main-window') || document.querySelector('.window-container');
    if (windowContainer) {
        windowContainer.classList.remove('hidden');
        windowContainer.style.display = 'flex';
    }

    const appEl = document.getElementById('app');
    if (appEl) {
        appEl.classList.remove('hidden');
        appEl.style.display = 'flex';
    }
}

// Category Filtering
document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        renderMenuGrid(btn.getAttribute('data-cat'));
    });
});

document.getElementById('menu-search-input').addEventListener('input', (e) => {
    const query = e.target.value.toLowerCase().trim();
    renderMenuGrid('all', query);
});

function renderMenuGrid(category = 'all', searchQuery = '') {
    const container = document.getElementById('menu-grid');
    container.innerHTML = '';

    const filtered = AppState.menu.filter(item => {
        const matchCat = (category === 'all' || item.category === category);
        const matchSearch = (!searchQuery || item.label.toLowerCase().includes(searchQuery));
        return matchCat && matchSearch;
    });

    if (filtered.length === 0) {
        container.innerHTML = '<div style="color: var(--text-dim); padding: 20px;">No items match your filter.</div>';
        return;
    }

    filtered.forEach(item => {
        const card = document.createElement('div');
        const isOutOfStock = (!item.in_stock || item.stock_count === 0);
        card.className = `food-card ${isOutOfStock ? 'out-of-stock' : ''}`;

        let iconClass = 'fa-burger';
        if (item.category === 'drinks') iconClass = 'fa-glass-water';
        else if (item.category === 'sides') iconClass = 'fa-bowl-food';

        card.innerHTML = `
            <div class="card-top">
                <div class="food-icon-box">
                    <img src="nui://ox_inventory/web/images/${item.item_name}.png" 
                         onerror="handleImgFallback(this, '${item.item_name}')" 
                         alt="${item.label}">
                </div>
                <span class="stock-tag ${isOutOfStock ? 'out-stock' : 'in-stock'}">
                    ${isOutOfStock ? 'Out of Stock' : (item.stock_count > 0 ? `${item.stock_count} Left` : 'In Stock')}
                </span>
            </div>
            <div>
                <h4>${item.label}</h4>
                <div class="card-price">$${item.price}</div>
            </div>
            <button class="add-cart-btn" ${isOutOfStock ? 'disabled' : ''}>
                <i class="fa-solid fa-cart-plus"></i> ${isOutOfStock ? 'Unavailable' : 'Add to Cart'}
            </button>
        `;

        const addBtn = card.querySelector('.add-cart-btn');
        if (!isOutOfStock) {
            addBtn.addEventListener('click', () => addToCart(item));
        }

        container.appendChild(card);
    });
}

function addToCart(item) {
    const existing = AppState.cart.find(c => c.item === item.item);
    if (existing) {
        if (item.stock_count !== -1 && existing.count >= item.stock_count) {
            showToast(`Cannot add more. Only ${item.stock_count} in stock.`, 'warning');
            return;
        }
        existing.count++;
    } else {
        AppState.cart.push({
            item: item.item,
            label: item.label,
            price: item.price,
            count: 1
        });
    }
    renderCart();
}

function changeCartQty(itemName, delta) {
    const item = AppState.cart.find(c => c.item === itemName);
    if (!item) return;

    item.count += delta;
    if (item.count <= 0) {
        AppState.cart = AppState.cart.filter(c => c.item !== itemName);
    }
    renderCart();
}

document.getElementById('btn-clear-cart').addEventListener('click', () => {
    AppState.cart = [];
    renderCart();
});

function renderCart() {
    const container = document.getElementById('cart-items');
    const subtotalEl = document.getElementById('cart-subtotal');
    const totalEl = document.getElementById('cart-total');
    const taxRateEl = document.getElementById('cart-tax-rate');
    const taxAmountEl = document.getElementById('cart-tax-amount');
    const submitBtn = document.getElementById('btn-submit-order');

    container.innerHTML = '';

    const taxRate = Number(AppState.settings && AppState.settings.tax_rate !== undefined ? AppState.settings.tax_rate : 10);
    if (taxRateEl) taxRateEl.textContent = taxRate;

    if (AppState.cart.length === 0) {
        container.innerHTML = `
            <div class="cart-empty-message">
                <i class="fa-solid fa-cart-arrow-down"></i>
                <p>Your cart is empty.</p>
                <span>Select items from the menu to build your meal!</span>
            </div>
        `;
        subtotalEl.textContent = '$0';
        if (taxAmountEl) taxAmountEl.textContent = '$0';
        totalEl.textContent = '$0';
        submitBtn.disabled = true;
        return;
    }

    let subtotal = 0;
    AppState.cart.forEach(c => {
        const row = document.createElement('div');
        row.className = 'cart-item-row';
        const lineTotal = c.price * c.count;
        subtotal += lineTotal;

        row.innerHTML = `
            <div class="cart-item-info">
                <h5>${c.label}</h5>
                <span>$${c.price} each</span>
            </div>
            <div class="cart-qty-ctrls">
                <button class="qty-btn btn-minus"><i class="fa-solid fa-minus"></i></button>
                <span class="cart-qty-val">${c.count}</span>
                <button class="qty-btn btn-plus"><i class="fa-solid fa-plus"></i></button>
            </div>
        `;

        row.querySelector('.btn-minus').addEventListener('click', () => changeCartQty(c.item, -1));
        row.querySelector('.btn-plus').addEventListener('click', () => changeCartQty(c.item, 1));
        container.appendChild(row);
    });

    const taxAmount = Math.round((subtotal * taxRate) / 100);
    const finalTotal = subtotal + taxAmount;

    subtotalEl.textContent = `$${subtotal}`;
    if (taxAmountEl) taxAmountEl.textContent = `$${taxAmount}`;
    totalEl.textContent = `$${finalTotal}`;
    submitBtn.disabled = false;
}

// Place Order Button Handler
document.getElementById('btn-submit-order').addEventListener('click', () => {
    if (AppState.cart.length === 0) return;

    const payMethod = document.querySelector('input[name="pay-method"]:checked').value || 'cash';
    postNUI('placeOrder', {
        restaurantId: AppState.restaurantId,
        cart: AppState.cart,
        paymentMethod: payMethod
    });

    AppState.cart = [];
    renderCart();
    closeApp();
});

// ====================================================================
// VIEW 2: STAFF / MANAGEMENT TERMINAL
// ====================================================================
function initManagementView(data) {
    AppState.restaurantId = data.restaurantId;
    AppState.restaurantLabel = data.restaurantLabel || 'Restaurant';
    AppState.isEmployee = data.playerData.isEmployee;
    AppState.onduty = data.playerData.onduty;
    AppState.grade = data.playerData.grade;
    AppState.isOwner = Boolean(data.playerData.isOwner);
    AppState.isAdmin = Boolean(data.playerData.isAdmin);
    AppState.canEditOwnerRole = Boolean(data.playerData.canEditOwnerRole || data.playerData.isAdmin);
    AppState.isManager = data.playerData.isManager;
    AppState.permissions = data.playerData.permissions || {};
    AppState.allPermissionsList = data.allPermissions || [];
    AppState.recipes = data.recipes || {};
    AppState.menu = data.menu || [];
    AppState.stations = data.stations || {};
    AppState.doors = Array.isArray(data.doors) ? data.doors : Object.values(data.doors || {});
    AppState.stationTypes = data.stationTypes || {};
    AppState.settings = data.settings || { tax_rate: 10 };

    // Initialize Active Orders Cache
    syncActiveOrders(data.activeOrders);
    renderKanbanBoard();
    initOwnerSettings();

    document.getElementById('restaurant-name').textContent = AppState.restaurantLabel;
    const roleStatusLabel = AppState.isAdmin
        ? 'Admin Access'
        : (AppState.onduty ? 'Duty ON' : 'Duty OFF');
    document.getElementById('role-badge').textContent = `${data.playerData.gradeName || 'Staff'} (${roleStatusLabel})`;

    // Role-based Tab Permissions (Server Admins have all permissions; Owners follow assigned Role permissions)
    const isVendingOnly = data.preferredSubTab === 'manager-vending';
    AppState.vendingOnlyMode = isVendingOnly;

    const canCook = AppState.isAdmin || (AppState.permissions && AppState.permissions.cook === true);
    const canViewOrders = AppState.isAdmin || (AppState.permissions && AppState.permissions.view_orders === true);
    const hasManagementPerms = AppState.isAdmin || (AppState.permissions && (
        AppState.permissions.refund_orders === true ||
        AppState.permissions.view_history === true ||
        AppState.permissions.manage_menu === true ||
        AppState.permissions.manage_stock === true ||
        AppState.permissions.vending_manage === true ||
        AppState.permissions.vending_fund === true
    ));
    const hasOwnerPerms = AppState.isAdmin || (AppState.permissions && (
        AppState.permissions.manage_stations === true ||
        AppState.permissions.manage_recipes === true ||
        AppState.permissions.manage_roles === true ||
        AppState.permissions.view_logs === true
    ));

    const canStock = AppState.isAdmin || (AppState.permissions && (AppState.permissions.manage_stock === true || AppState.permissions.manage_menu === true));
    const canHistory = AppState.isAdmin || (AppState.permissions && (AppState.permissions.view_history === true || AppState.permissions.refund_orders === true));
    const canStaff = AppState.isAdmin || (AppState.permissions && AppState.permissions.view_history === true);
    const canVending = AppState.isAdmin || (AppState.permissions && AppState.permissions.vending_manage === true);
    const canVendingFund = AppState.isAdmin || (AppState.permissions && AppState.permissions.vending_fund === true);

    const showRecipesTab = !isVendingOnly && canCook;
    const showOrdersTab = !isVendingOnly && canViewOrders;
    const showManagerTab = isVendingOnly ? (canVending || canVendingFund) : hasManagementPerms;
    const showOwnerTab = !isVendingOnly && hasOwnerPerms;

    const setTabVisibility = (btnId, isVisible) => {
        const btn = document.getElementById(btnId);
        if (!btn) return;
        if (isVisible) {
            btn.classList.remove('hidden');
            btn.style.display = 'inline-flex';
        } else {
            btn.classList.add('hidden');
            btn.style.display = 'none';
        }
    };

    setTabVisibility('tab-btn-customer', false);
    setTabVisibility('tab-btn-recipes', showRecipesTab);
    setTabVisibility('tab-btn-employee', showOrdersTab);
    setTabVisibility('tab-btn-manager', showManagerTab);
    setTabVisibility('tab-btn-owner', showOwnerTab);

    const navTabs = document.getElementById('nav-tabs');
    if (navTabs) {
        const anyVisible = showRecipesTab || showOrdersTab || showManagerTab || showOwnerTab;
        navTabs.style.display = anyVisible ? 'flex' : 'none';
    }

    if (showOwnerTab) {
        populateStationTypeDropdown();
        renderOwnerDoorsTable();
    }

    // Granular Sub-Tab Visibility inside Management Tab
    const setSubTabVisibility = (selector, isVisible) => {
        const btn = document.querySelector(selector);
        if (!btn) return;
        if (isVisible) {
            btn.classList.remove('hidden');
            btn.style.display = '';
        } else {
            btn.classList.add('hidden');
            btn.style.display = 'none';
        }
    };

    setSubTabVisibility('.sub-btn[data-sub="manager-stock"]', !isVendingOnly && canStock);
    setSubTabVisibility('.sub-btn[data-sub="manager-history"]', !isVendingOnly && canHistory);
    setSubTabVisibility('.sub-btn[data-sub="manager-staff"]', !isVendingOnly && canStaff);
    setSubTabVisibility('.sub-btn[data-sub="manager-vending"]', canVending);
    setSubTabVisibility('.sub-btn[data-sub="manager-vending-fund"]', canVendingFund);

    // Granular Sub-Tab Visibility inside Owner Tab
    setSubTabVisibility('.sub-btn[data-sub="owner-stations"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.manage_stations === true));
    setSubTabVisibility('.sub-btn[data-sub="owner-doors"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.manage_stations === true));
    setSubTabVisibility('.sub-btn[data-sub="owner-roles"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.manage_roles === true));
    setSubTabVisibility('.sub-btn[data-sub="owner-recipe-editor"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.manage_recipes === true));
    setSubTabVisibility('.sub-btn[data-sub="owner-settings"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.manage_roles === true));
    setSubTabVisibility('.sub-btn[data-sub="owner-salary"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.manage_roles === true));
    setSubTabVisibility('.sub-btn[data-sub="owner-logs"]', AppState.isAdmin || (AppState.permissions && AppState.permissions.view_logs === true));

    // Ensure active sub-tab is valid and visible
    const ensureVisibleSubTab = (paneId) => {
        const pane = document.getElementById(paneId);
        if (!pane) return;
        const visibleBtns = Array.from(pane.querySelectorAll('.sub-btn')).filter(b => b.style.display !== 'none');
        const activeBtn = pane.querySelector('.sub-btn.active');
        if (!activeBtn || activeBtn.style.display === 'none') {
            if (visibleBtns.length > 0) {
                pane.querySelectorAll('.sub-btn').forEach(b => b.classList.remove('active'));
                pane.querySelectorAll('.sub-pane').forEach(p => p.classList.remove('active'));
                visibleBtns[0].classList.add('active');
                const targetSub = document.getElementById(visibleBtns[0].getAttribute('data-sub'));
                if (targetSub) targetSub.classList.add('active');
            }
        }
    };
    ensureVisibleSubTab('manager-tab');
    ensureVisibleSubTab('owner-tab');

    // Select preferred sub-tab inside manager/owner if requested (e.g. Vending Manage target)
    if (data.preferredSubTab) {
        const subBtn = document.querySelector(`.sub-btn[data-sub="${data.preferredSubTab}"]`);
        const subPane = document.getElementById(data.preferredSubTab);
        if (subBtn && subPane && subBtn.style.display !== 'none') {
            const parentPane = subBtn.closest('.tab-pane');
            if (parentPane) {
                parentPane.querySelectorAll('.sub-btn').forEach(b => b.classList.remove('active'));
                parentPane.querySelectorAll('.sub-pane').forEach(p => p.classList.remove('active'));
            }
            subBtn.classList.add('active');
            subPane.classList.add('active');
        }
    }

    // Auto-select the first visible tab that the player has permission for
    let tabToSelect = null;
    if (data.preferredTab) {
        if (data.preferredTab === 'owner-tab' && showOwnerTab) tabToSelect = 'owner-tab';
        else if (data.preferredTab === 'manager-tab' && showManagerTab) tabToSelect = 'manager-tab';
        else if (data.preferredTab === 'employee-tab' && showOrdersTab) tabToSelect = 'employee-tab';
        else if (data.preferredTab === 'recipes-tab' && showRecipesTab) tabToSelect = 'recipes-tab';
    }

    if (!tabToSelect) {
        if (showOrdersTab) {
            tabToSelect = 'employee-tab';
        } else if (showRecipesTab) {
            tabToSelect = 'recipes-tab';
        } else if (showManagerTab) {
            tabToSelect = 'manager-tab';
        } else if (showOwnerTab) {
            tabToSelect = 'owner-tab';
        } else {
            tabToSelect = 'manager-tab';
        }
    }

    switchMainTab(tabToSelect, true);

    renderStaffRecipes();

    const stationView = document.getElementById('station-cooking-view');
    if (stationView) {
        stationView.classList.add('hidden');
        stationView.style.display = 'none';
    }

    const vendingView = document.getElementById('vending-customer-view');
    if (vendingView) {
        vendingView.classList.add('hidden');
        vendingView.style.display = 'none';
    }
    AppState.vendingCart = [];

    const windowContainer = document.getElementById('main-window') || document.querySelector('.window-container');
    if (windowContainer) {
        windowContainer.classList.remove('hidden');
        windowContainer.style.display = 'flex';
    }

    const appEl = document.getElementById('app');
    if (appEl) {
        appEl.classList.remove('hidden');
        appEl.style.display = 'flex';
    }
}

// ====================================================================
// LIVE ORDERS KANBAN (Employee Tab)
// ====================================================================
function syncActiveOrders(rawOrders) {
    AppState.activeOrders = {};
    if (Array.isArray(rawOrders)) {
        rawOrders.forEach(o => {
            if (o && o.id) AppState.activeOrders[o.id] = o;
        });
    } else if (rawOrders && typeof rawOrders === 'object') {
        AppState.activeOrders = rawOrders;
    }
}

async function refreshActiveOrders() {
    if (!AppState.restaurantId) return;
    const orders = await postNUI('getActiveOrders', { restaurantId: AppState.restaurantId });
    if (orders !== null && orders !== undefined) {
        syncActiveOrders(orders);
        renderKanbanBoard();
    }
}

const refreshOrdersBtn = document.getElementById('btn-refresh-orders');
if (refreshOrdersBtn) {
    refreshOrdersBtn.addEventListener('click', () => {
        refreshActiveOrders();
    });
}

function handleOrderReceived(order) {
    if (!order) return;
    AppState.activeOrders[order.id] = order;
    renderKanbanBoard();
    showToast(`🔔 New Order #${order.id} received! ($${order.total_price || 0})`, 'info');
}

function handleOrderUpdated(order) {
    if (!order) return;
    if (order.status === 'delivered' || order.status === 'cancelled') {
        delete AppState.activeOrders[order.id];
    } else {
        AppState.activeOrders[order.id] = order;
    }
    renderKanbanBoard();
}

function renderKanbanBoard() {
    const cols = {
        pending: document.getElementById('orders-list-pending'),
        accepted: document.getElementById('orders-list-accepted'),
        cooking: document.getElementById('orders-list-cooking'),
        ready: document.getElementById('orders-list-ready')
    };

    if (!cols.pending) return;

    Object.values(cols).forEach(col => col.innerHTML = '');

    let counts = { pending: 0, accepted: 0, cooking: 0, ready: 0 };
    const ordersList = Object.values(AppState.activeOrders || {});

    ordersList.forEach(order => {
        if (!order || !order.id) return;
        const col = cols[order.status];
        if (!col) return;

        counts[order.status] = (counts[order.status] || 0) + 1;
        const ticket = document.createElement('div');
        ticket.className = `order-ticket status-${order.status}`;

        let itemsHtml = '';
        let itemsList = order.items;
        if (typeof itemsList === 'string') {
            try { itemsList = JSON.parse(itemsList); } catch (e) { itemsList = []; }
        }
        if (Array.isArray(itemsList)) {
            itemsHtml = itemsList.map(i => `
                <div class="ticket-item-row">
                    <span class="item-name"><strong class="item-qty">${i.count}x</strong> ${i.label || i.item}</span>
                    <span class="item-price">$${i.subtotal || (i.price * i.count)}</span>
                </div>
            `).join('');
        }

        // Action Buttons based on Status
        let actionBtnHtml = '';
        if (order.status === 'pending') {
            actionBtnHtml = `
                <div class="ticket-actions">
                    <button class="ticket-btn btn-accept" data-order="${order.id}" data-next="accepted">
                        <i class="fa-solid fa-check-circle"></i> Accept Order
                    </button>
                </div>
            `;
        } else if (order.status === 'accepted') {
            actionBtnHtml = `
                <div class="ticket-actions split">
                    <button class="ticket-btn btn-cook" data-order="${order.id}" data-next="cooking">
                        <i class="fa-solid fa-fire-burner"></i> Start Cooking
                    </button>
                    <button class="ticket-btn btn-finish-direct" data-order="${order.id}" data-next="delivered" title="Quick Complete Order">
                        <i class="fa-solid fa-circle-check"></i> Finish
                    </button>
                </div>
            `;
        } else if (order.status === 'cooking') {
            actionBtnHtml = `
                <div class="ticket-actions split">
                    <button class="ticket-btn btn-ready" data-order="${order.id}" data-next="ready">
                        <i class="fa-solid fa-bell"></i> Mark Ready
                    </button>
                    <button class="ticket-btn btn-finish-direct" data-order="${order.id}" data-next="delivered" title="Quick Complete Order">
                        <i class="fa-solid fa-circle-check"></i> Finish
                    </button>
                </div>
            `;
        } else if (order.status === 'ready') {
            actionBtnHtml = `
                <div class="ticket-actions">
                    <button class="ticket-btn btn-deliver" data-order="${order.id}" data-next="delivered">
                        <i class="fa-solid fa-box-check"></i> Finish & Deliver Order
                    </button>
                </div>
            `;
        }

        const totalFormatted = `$${Number(order.total_price || 0).toLocaleString()}`;
        const payMethodBadge = order.payment_method === 'bank'
            ? '<span class="pay-badge bank"><i class="fa-solid fa-credit-card"></i> Card</span>'
            : '<span class="pay-badge cash"><i class="fa-solid fa-money-bill-wave"></i> Cash</span>';

        ticket.innerHTML = `
            <div class="ticket-header">
                <div class="ticket-id-tag">
                    <span class="id-hash">#</span><span class="id-num">${order.id}</span>
                </div>
                <div class="ticket-meta-right">
                    ${payMethodBadge}
                    <span class="ticket-total">${totalFormatted}</span>
                    ${order.tax_amount ? `<span class="ticket-tax-badge" style="font-size: 10px; color: var(--text-dim); text-align: right; display: block;">Incl. $${order.tax_amount} Tax</span>` : ''}
                </div>
            </div>

            <div class="ticket-customer-row">
                <i class="fa-solid fa-user-circle"></i>
                <span class="customer-name">${order.customer_name || 'Customer'}</span>
            </div>

            <div class="ticket-items-list">
                ${itemsHtml || '<span style="color: var(--text-dim);">No items listed</span>'}
            </div>

            ${order.claimed_name ? `
                <div class="ticket-claimed-info">
                    <i class="fa-solid fa-user-check"></i> <span>Claimed by: <strong>${order.claimed_name}</strong></span>
                </div>
            ` : ''}

            ${actionBtnHtml}
        `;

        ticket.querySelectorAll('.ticket-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const next = btn.getAttribute('data-next');
                const ordId = Number(btn.getAttribute('data-order'));
                postNUI('updateOrderStatus', {
                    restaurantId: AppState.restaurantId,
                    orderId: ordId,
                    status: next
                });
                if (next === 'delivered') {
                    showToast(`Order #${ordId} completed & finished!`, 'success');
                    delete AppState.activeOrders[ordId];
                    renderKanbanBoard();
                } else {
                    showToast(`Order #${ordId} updated to ${next.toUpperCase()}`, 'info');
                }
            });
        });

        col.appendChild(ticket);
    });

    // Empty state messages for columns
    const emptyStates = {
        pending: '<div class="kanban-empty"><i class="fa-solid fa-clock"></i><p>No pending orders</p></div>',
        accepted: '<div class="kanban-empty"><i class="fa-solid fa-clipboard-check"></i><p>No accepted orders</p></div>',
        cooking: '<div class="kanban-empty"><i class="fa-solid fa-fire-burner"></i><p>Nothing cooking</p></div>',
        ready: '<div class="kanban-empty"><i class="fa-solid fa-bell"></i><p>No orders waiting</p></div>'
    };

    ['pending', 'accepted', 'cooking', 'ready'].forEach(st => {
        if ((!counts[st] || counts[st] === 0) && cols[st]) {
            cols[st].innerHTML = emptyStates[st];
        }
    });

    // Update column counters
    const pCount = document.querySelector('#col-pending .col-count');
    const aCount = document.querySelector('#col-accepted .col-count');
    const cCount = document.querySelector('#col-cooking .col-count');
    const rCount = document.querySelector('#col-ready .col-count');
    if (pCount) pCount.textContent = counts.pending || 0;
    if (aCount) aCount.textContent = counts.accepted || 0;
    if (cCount) cCount.textContent = counts.cooking || 0;
    if (rCount) rCount.textContent = counts.ready || 0;

    const totalActive = Object.keys(AppState.activeOrders || {}).length;
    const badge = document.getElementById('active-orders-count');
    if (badge) badge.textContent = totalActive;
}

// ====================================================================
// RECIPES DIRECTORY (Staff Tab)
// ====================================================================
function renderStaffRecipes() {
    const grid = document.getElementById('staff-recipes-grid');
    if (!grid) return;
    grid.innerHTML = '';

    Object.values(AppState.recipes || {}).filter(Boolean).forEach(rec => {
        if (!rec.enabled) return;
        const card = document.createElement('div');
        card.className = 'recipe-card';

        const ings = Array.isArray(rec.ingredients) ? rec.ingredients.map(i => `• ${i.count}x ${getStationItemLabel(i.item)}`).join('<br>') : 'None';

        card.innerHTML = `
            <div class="recipe-card-header">
                <h4>${rec.recipe_name}</h4>
                <span class="recipe-station-pill">${rec.station_type.toUpperCase()}</span>
            </div>
            <div class="recipe-ingredients-box">
                <strong>Ingredients:</strong>
                <div>${ings}</div>
            </div>
            <div style="font-size: 11.5px; color: var(--text-dim); display: flex; justify-content: space-between;">
                <span>Prep Time: ${(rec.cooking_time || 5000) / 1000}s</span>
                <span>Produces: ${rec.output_count}x ${getStationItemLabel(rec.output_item)}</span>
            </div>
        `;
        grid.appendChild(card);
    });
}

// ====================================================================
// MANAGER TAB (Stock, History, Staff)
// ====================================================================
function renderManagerStockTable() {
    const tbody = document.getElementById('stock-table-body');
    tbody.innerHTML = '';

    AppState.menu.forEach(item => {
        const tr = document.createElement('tr');
        const isInStock = (item.in_stock === true || item.in_stock === 1);
        tr.innerHTML = `
            <td><strong>${item.label}</strong></td>
            <td><span class="badge">${item.category}</span></td>
            <td><input type="number" class="price-input" value="${item.price}" style="width: 80px;"></td>
            <td><input type="number" class="stock-input" value="${item.stock_count}" style="width: 80px;" title="-1 means unlimited stock"></td>
            <td>
                <label style="display: flex; align-items: center; gap: 8px; cursor: pointer;">
                    <input type="checkbox" class="stock-checkbox" ${isInStock ? 'checked' : ''}>
                    <span class="stock-status-text" style="font-weight: 600; color: ${isInStock ? 'var(--success)' : 'var(--danger)'};">
                        ${isInStock ? 'In Stock' : 'Out of Stock'}
                    </span>
                </label>
            </td>
            <td>
                <button class="action-btn primary small btn-save-stock"><i class="fa-solid fa-floppy-disk"></i> Save</button>
            </td>
        `;

        const checkbox = tr.querySelector('.stock-checkbox');
        const statusSpan = tr.querySelector('.stock-status-text');
        checkbox.addEventListener('change', () => {
            if (checkbox.checked) {
                statusSpan.textContent = 'In Stock';
                statusSpan.style.color = 'var(--success)';
            } else {
                statusSpan.textContent = 'Out of Stock';
                statusSpan.style.color = 'var(--danger)';
            }
        });

        tr.querySelector('.btn-save-stock').addEventListener('click', () => {
            const newPrice = parseInt(tr.querySelector('.price-input').value) || item.price;
            let newStock = parseInt(tr.querySelector('.stock-input').value);
            if (isNaN(newStock)) newStock = -1;
            const inStock = checkbox.checked;

            item.price = newPrice;
            item.stock_count = newStock;
            item.in_stock = inStock;

            postNUI('updateStock', {
                restaurantId: AppState.restaurantId,
                item_name: item.item || item.item_name,
                in_stock: inStock,
                stock_count: newStock
            });

            postNUI('updatePrice', {
                restaurantId: AppState.restaurantId,
                item_name: item.item || item.item_name,
                price: newPrice
            });

            showToast(`Saved ${item.label} (${inStock ? (newStock === -1 ? 'In Stock / Unlimited' : newStock + ' in stock') : 'Out of Stock'})`, 'success');
        });

        tbody.appendChild(tr);
    });
}

async function loadManagerHistory() {
    const tbody = document.getElementById('history-table-body');
    tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-dim);">Loading records...</td></tr>';

    const history = await postNUI('getOrderHistory', { restaurantId: AppState.restaurantId }) || [];
    tbody.innerHTML = '';

    if (history.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-dim);">No order history found.</td></tr>';
        return;
    }

    history.forEach(ord => {
        const tr = document.createElement('tr');
        const itemsSummary = Array.isArray(ord.items) ? ord.items.map(i => `${i.count}x ${i.label || i.item}`).join(', ') : 'N/A';

        let actionBtn = '';
        if (ord.status !== 'cancelled' && ord.status !== 'delivered') {
            actionBtn = `<button class="action-btn danger small btn-refund"><i class="fa-solid fa-ban"></i> Refund & Cancel</button>`;
        }

        tr.innerHTML = `
            <td>#${ord.id}</td>
            <td>${ord.customer_name}</td>
            <td style="max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${itemsSummary}</td>
            <td><strong>$${ord.total_price}</strong></td>
            <td><span class="badge">${ord.payment_method}</span></td>
            <td><span class="stock-tag ${ord.status === 'delivered' ? 'in-stock' : (ord.status === 'cancelled' ? 'out-stock' : '')}">${ord.status.toUpperCase()}</span></td>
            <td>${ord.claimed_name || 'None'}</td>
            <td>${actionBtn}</td>
        `;

        const refundBtn = tr.querySelector('.btn-refund');
        if (refundBtn) {
            refundBtn.addEventListener('click', () => {
                postNUI('cancelOrder', {
                    restaurantId: AppState.restaurantId,
                    orderId: ord.id,
                    reason: 'Manager Refund'
                });
                loadManagerHistory();
            });
        }

        tbody.appendChild(tr);
    });
}

const STAFF_STATUS_META = {
    on_duty: { cls: 'in-stock', label: 'ON DUTY' },
    off_duty: { cls: 'out-stock', label: 'OFF DUTY' },
    offline: { cls: 'offline-tag', label: 'OFFLINE' },
    former: { cls: 'former-tag', label: 'FORMER STAFF' }
};

function escapeHtml(text) {
    return String(text == null ? '' : text)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function formatWorkedHours(totalSeconds) {
    const cleanSec = Math.max(0, Math.floor(Number(totalSeconds) || 0));
    const hours = Math.floor(cleanSec / 3600);
    const mins = Math.floor((cleanSec % 3600) / 60);
    const secs = cleanSec % 60;
    const primary = `${hours}h ${String(mins).padStart(2, '0')}m`;

    if (cleanSec === 0) {
        return { primary, sub: '0.0 hrs' };
    }
    if (hours === 0 && mins === 0) {
        return { primary, sub: `${secs}s` };
    }
    return { primary, sub: `${(cleanSec / 3600).toFixed(1)} hrs` };
}

async function populatePromoteGradesDropdown() {
    const select = document.getElementById('promote-grade-select');
    if (!select) return;

    const curVal = select.value;
    try {
        const roles = await postNUI('getRoles', { restaurantId: AppState.restaurantId }) || [];
        if (Array.isArray(roles) && roles.length > 0) {
            select.innerHTML = '';
            roles.forEach(r => {
                const opt = document.createElement('option');
                opt.value = r.grade;
                opt.textContent = `Grade ${r.grade} - ${r.role_name || 'Staff'}`;
                select.appendChild(opt);
            });
            if (curVal !== undefined && curVal !== null && curVal !== '') {
                select.value = curVal;
            }
            return;
        }
    } catch (err) {
        console.warn('Failed to fetch roles for promotion dropdown:', err);
    }

    if (select.children.length <= 1) {
        select.innerHTML = `
            <option value="0">Grade 0 - Trainee</option>
            <option value="1">Grade 1 - Cook</option>
            <option value="2">Grade 2 - Cashier</option>
            <option value="3">Grade 3 - Lead Cook</option>
            <option value="4">Grade 4 - Assistant Manager</option>
            <option value="8">Grade 8 - Store Manager</option>
        `;
    }
}

async function loadManagerStaff() {
    const tbody = document.getElementById('staff-table-body');
    const summaryEl = document.getElementById('staff-roster-summary');
    if (!tbody) return;

    populatePromoteGradesDropdown();

    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-dim);">Fetching staff...</td></tr>';

    const staff = await postNUI('getStaffList', { restaurantId: AppState.restaurantId }) || [];
    tbody.innerHTML = '';

    if (staff.length === 0) {
        if (summaryEl) summaryEl.textContent = 'No employees have joined this restaurant yet.';
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-dim);">No staff records found yet.</td></tr>';
        return;
    }

    const onDutyCount = staff.filter(s => s.status === 'on_duty' || s.onduty).length;
    const totalWorkedSec = staff.reduce((acc, s) => acc + Math.max(0, Number(s.workedSeconds) || 0), 0);
    if (summaryEl) {
        const totalFmt = formatWorkedHours(totalWorkedSec);
        summaryEl.textContent = `Total Staff: ${staff.length} • On Duty Now: ${onDutyCount} • Combined Work: ${totalFmt.primary} (${totalFmt.sub})`;
    }

    staff.forEach(s => {
        const statusKey = s.status || (s.onduty ? 'on_duty' : 'offline');
        const badge = STAFF_STATUS_META[statusKey] || STAFF_STATUS_META.offline;
        const worked = formatWorkedHours(s.workedSeconds);
        const tr = document.createElement('tr');

        let actionButtons = '';
        if (s.online && s.source) {
            actionButtons = `
                <div class="staff-row-actions">
                    <button class="btn-table-action btn-table-tab" data-source="${s.source}" title="Give Burgershot Tablet to ${escapeHtml(s.name)} (ID: ${s.source})">
                        <i class="fa-solid fa-tablet-screen-button"></i> Give Tab
                    </button>
                    <button class="btn-table-action btn-table-fill" data-source="${s.source}" data-grade="${s.grade}" title="Select this player for promotion">
                        <i class="fa-solid fa-pen-to-square"></i> Select
                    </button>
                </div>
            `;
        } else {
            actionButtons = `
                <div class="staff-row-actions">
                    <button class="btn-table-action btn-table-fire" data-cid="${escapeHtml(s.citizenid)}" data-name="${escapeHtml(s.name)}" title="Remove offline employee">
                        <i class="fa-solid fa-user-minus"></i> Fire
                    </button>
                </div>
            `;
        }

        tr.innerHTML = `
            <td><code>${escapeHtml(s.citizenid)}</code></td>
            <td><strong>${escapeHtml(s.name)}</strong> ${s.source ? `<span class="player-id-pill">ID ${s.source}</span>` : ''}</td>
            <td>${escapeHtml(s.gradeName)} (Grade ${Number(s.grade) || 0})</td>
            <td><span class="worked-hours-value">${worked.primary}</span><span class="worked-hours-sub">${worked.sub}</span></td>
            <td><span class="stock-tag ${badge.cls}">${badge.label}</span></td>
            <td>${actionButtons}</td>
        `;
        tbody.appendChild(tr);
    });

    // Event delegates for row buttons
    tbody.querySelectorAll('.btn-table-tab').forEach(btn => {
        btn.addEventListener('click', async () => {
            const src = btn.getAttribute('data-source');
            if (!src) return;
            btn.disabled = true;
            try {
                const res = await postNUI('giveTablet', { restaurantId: AppState.restaurantId, targetId: Number(src) });
                if (res && res.ok) {
                    showToast(res.message || 'Burgershot Tablet issued!', 'success');
                } else {
                    showToast((res && res.message) || 'Failed to issue tablet.', 'error');
                }
            } finally {
                btn.disabled = false;
            }
        });
    });

    tbody.querySelectorAll('.btn-table-fill').forEach(btn => {
        btn.addEventListener('click', () => {
            const src = btn.getAttribute('data-source');
            const grade = btn.getAttribute('data-grade');
            const inputId = document.getElementById('promote-target-id');
            const selectGrade = document.getElementById('promote-grade-select');
            if (inputId && src) {
                inputId.value = src;
                inputId.focus();
            }
            if (selectGrade && grade !== null && grade !== undefined) {
                selectGrade.value = grade;
            }
            showToast(`Selected Player Server ID ${src} for role management.`, 'info');
        });
    });

    tbody.querySelectorAll('.btn-table-fire').forEach(btn => {
        btn.addEventListener('click', async () => {
            const cid = btn.getAttribute('data-cid');
            const name = btn.getAttribute('data-name') || 'this staff member';
            if (!confirm(`Are you sure you want to dismiss ${name} from Burgershot?`)) return;
            btn.disabled = true;
            try {
                const res = await postNUI('fireStaff', { restaurantId: AppState.restaurantId, citizenid: cid });
                if (res && res.ok) {
                    showToast(res.message || 'Staff dismissed.', 'success');
                    loadManagerStaff();
                } else {
                    showToast((res && res.message) || 'Failed to dismiss staff.', 'error');
                }
            } finally {
                btn.disabled = false;
            }
        });
    });
}

document.getElementById('btn-refresh-history').addEventListener('click', loadManagerHistory);
document.getElementById('btn-refresh-staff').addEventListener('click', loadManagerStaff);

// Staff Promotion & Tablet Distribution Buttons
const btnPromotePlayer = document.getElementById('btn-promote-player');
if (btnPromotePlayer) {
    btnPromotePlayer.addEventListener('click', async () => {
        const inputId = document.getElementById('promote-target-id');
        const selectGrade = document.getElementById('promote-grade-select');
        const targetId = inputId ? Number(inputId.value) : 0;
        const grade = selectGrade ? Number(selectGrade.value) : 0;

        if (!targetId || targetId <= 0) {
            showToast('Please enter a valid Player Server ID (e.g. 1, 2, 5).', 'error');
            if (inputId) inputId.focus();
            return;
        }

        btnPromotePlayer.disabled = true;
        try {
            const res = await postNUI('promoteStaff', {
                restaurantId: AppState.restaurantId,
                targetId: targetId,
                grade: grade
            });
            if (res && res.ok) {
                showToast(res.message || 'Staff promoted successfully!', 'success');
                if (inputId) inputId.value = '';
                loadManagerStaff();
            } else {
                showToast((res && res.message) || 'Failed to promote staff.', 'error');
            }
        } finally {
            btnPromotePlayer.disabled = false;
        }
    });
}

const btnGiveTabletId = document.getElementById('btn-give-tablet-id');
if (btnGiveTabletId) {
    btnGiveTabletId.addEventListener('click', async () => {
        const inputId = document.getElementById('promote-target-id');
        const targetId = inputId ? Number(inputId.value) : 0;

        if (!targetId || targetId <= 0) {
            showToast('Please enter a valid Player Server ID to receive the tablet.', 'error');
            if (inputId) inputId.focus();
            return;
        }

        btnGiveTabletId.disabled = true;
        try {
            const res = await postNUI('giveTablet', {
                restaurantId: AppState.restaurantId,
                targetId: targetId
            });
            if (res && res.ok) {
                showToast(res.message || 'Burgershot tablet issued!', 'success');
            } else {
                showToast((res && res.message) || 'Failed to issue tablet.', 'error');
            }
        } finally {
            btnGiveTabletId.disabled = false;
        }
    });
}

const btnFirePlayer = document.getElementById('btn-fire-player');
if (btnFirePlayer) {
    btnFirePlayer.addEventListener('click', async () => {
        const inputId = document.getElementById('promote-target-id');
        const targetId = inputId ? Number(inputId.value) : 0;

        if (!targetId || targetId <= 0) {
            showToast('Please enter a valid Player Server ID to dismiss.', 'error');
            if (inputId) inputId.focus();
            return;
        }

        if (!confirm(`Are you sure you want to dismiss Server ID ${targetId} from Burgershot?`)) return;

        btnFirePlayer.disabled = true;
        try {
            const res = await postNUI('fireStaff', {
                restaurantId: AppState.restaurantId,
                targetId: targetId
            });
            if (res && res.ok) {
                showToast(res.message || 'Staff dismissed successfully.', 'success');
                if (inputId) inputId.value = '';
                loadManagerStaff();
            } else {
                showToast((res && res.message) || 'Failed to dismiss staff.', 'error');
            }
        } finally {
            btnFirePlayer.disabled = false;
        }
    });
}

// ====================================================================
// VENDING MACHINE MANAGEMENT & CUSTOMER KIOSK
// ====================================================================
function populateVendingItemDropdown() {
    const select = document.getElementById('vending-item-select');
    if (!select) return;
    select.innerHTML = '';

    const list = AppState.vendingInventory || [];
    if (list.length === 0) {
        const opt = document.createElement('option');
        opt.value = '';
        opt.textContent = 'No items in your inventory';
        select.appendChild(opt);
        return;
    }

    list.forEach(item => {
        const opt = document.createElement('option');
        opt.value = item.name;
        opt.textContent = `${item.label || item.name} (Have: ${Number(item.count) || 0})`;
        select.appendChild(opt);
    });
}

function renderVendingManageTable() {
    const tbody = document.getElementById('vending-manage-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';

    const items = AppState.vendingItems || [];
    if (items.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" style="text-align: center; color: var(--text-dim);">No items stocked in the vending machine yet.</td></tr>';
        return;
    }

    items.forEach(item => {
        const stock = Math.max(0, Number(item.stock) || 0);
        const price = Math.max(1, Number(item.price) || 15);
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>
                <div class="vending-item-meta">
                    <img src="nui://ox_inventory/web/images/${escapeHtml(item.item_name)}.png" class="vending-item-thumb" onerror="handleImgFallback(this, '${escapeHtml(item.item_name)}')">
                    <div>
                        <strong>${escapeHtml(item.label || item.item_name)}</strong>
                        <div style="font-size: 11px; color: var(--text-dim);">${escapeHtml(item.item_name)}</div>
                    </div>
                </div>
            </td>
            <td>
                <div class="price-input-wrap">
                    <input type="number" class="vending-price-input" value="${price}" min="1" max="50000">
                    <button type="button" class="action-btn small btn-vending-save-price">Save</button>
                </div>
            </td>
            <td><span class="stock-tag ${stock > 0 ? 'in-stock' : 'out-stock'}">${stock > 0 ? `${stock} in stock` : 'Out of Stock'}</span></td>
            <td>
                <div class="role-card-actions">
                    ${stock > 0 ? '<button type="button" class="action-btn small btn-vending-withdraw" title="Withdraw 1 to Inventory"><i class="fa-solid fa-hand-holding"></i> -1</button>' : ''}
                    <button type="button" class="action-btn danger small btn-vending-remove" title="Remove Item"><i class="fa-solid fa-trash"></i></button>
                </div>
            </td>
        `;

        const priceInput = tr.querySelector('.vending-price-input');
        const btnSavePrice = tr.querySelector('.btn-vending-save-price');
        if (btnSavePrice && priceInput) {
            btnSavePrice.addEventListener('click', async () => {
                const newPrice = Math.max(1, Math.min(50000, Math.floor(Number(priceInput.value) || 15)));
                priceInput.value = newPrice;
                const res = await postNUI('upsertVendingItem', {
                    restaurantId: AppState.restaurantId,
                    item_name: item.item_name,
                    price: newPrice,
                    add_stock: 0
                });
                if (res && res.ok) {
                    if (Array.isArray(res.items)) AppState.vendingItems = res.items;
                    showToast(res.message || 'Vending price updated!', 'success');
                    renderVendingManageTable();
                } else {
                    showToast((res && res.message) || 'Failed to update price.', 'error');
                }
            });
        }

        const btnWithdraw = tr.querySelector('.btn-vending-withdraw');
        if (btnWithdraw) {
            btnWithdraw.addEventListener('click', async () => {
                btnWithdraw.disabled = true;
                try {
                    const res = await postNUI('withdrawVendingItem', {
                        restaurantId: AppState.restaurantId,
                        item_name: item.item_name,
                        qty: 1,
                        remove_listing: false
                    });
                    if (res && res.ok) {
                        showToast(res.message || 'Withdrew 1x item.', 'success');
                        await loadManagerVending();
                    } else {
                        showToast((res && res.message) || 'Failed to withdraw item.', 'error');
                    }
                } finally {
                    btnWithdraw.disabled = false;
                }
            });
        }

        const btnRemove = tr.querySelector('.btn-vending-remove');
        if (btnRemove) {
            let resetTimer = null;
            btnRemove.addEventListener('click', async () => {
                if (!btnRemove.classList.contains('confirming')) {
                    btnRemove.classList.add('confirming');
                    btnRemove.innerHTML = '<i class="fa-solid fa-check"></i> Confirm?';
                    resetTimer = setTimeout(() => {
                        btnRemove.classList.remove('confirming');
                        btnRemove.innerHTML = '<i class="fa-solid fa-trash"></i>';
                    }, 3500);
                    return;
                }
                if (resetTimer) clearTimeout(resetTimer);
                btnRemove.disabled = true;
                const res = await postNUI('withdrawVendingItem', {
                    restaurantId: AppState.restaurantId,
                    item_name: item.item_name,
                    remove_listing: true
                });
                if (res && res.ok) {
                    showToast(res.message || 'Removed vending item.', 'success');
                    await loadManagerVending();
                } else {
                    btnRemove.disabled = false;
                    btnRemove.classList.remove('confirming');
                    btnRemove.innerHTML = '<i class="fa-solid fa-trash"></i>';
                    showToast((res && res.message) || 'Failed to remove item.', 'error');
                }
            });
        }

        tbody.appendChild(tr);
    });
}

async function loadManagerVending() {
    if (!AppState.restaurantId) return;
    const canVending = AppState.isAdmin || (AppState.permissions && AppState.permissions.vending_manage === true);
    if (!canVending) return;

    const selectEl = document.getElementById('vending-item-select');
    const tbodyEl = document.getElementById('vending-manage-table-body');
    if (selectEl) {
        selectEl.innerHTML = '<option value="">Loading inventory...</option>';
    }
    if (tbodyEl) {
        tbodyEl.innerHTML = '<tr><td colspan="4" style="text-align: center; color: var(--text-dim);">Loading vending items...</td></tr>';
    }

    try {
        const res = await postNUI('getVendingData', {
            restaurantId: AppState.restaurantId,
            includeInventory: true
        });

        if (res && typeof res === 'object') {
            AppState.vendingItems = Array.isArray(res.items)
                ? res.items
                : (res.items && typeof res.items === 'object' ? Object.values(res.items) : []);
            AppState.vendingInventory = Array.isArray(res.inventory)
                ? res.inventory
                : (res.inventory && typeof res.inventory === 'object' ? Object.values(res.inventory) : []);
        } else {
            AppState.vendingItems = [];
            AppState.vendingInventory = [];
        }
    } catch (err) {
        AppState.vendingItems = [];
        AppState.vendingInventory = [];
    }
    populateVendingItemDropdown();
    renderVendingManageTable();
}

const btnRefreshVending = document.getElementById('btn-refresh-vending');
if (btnRefreshVending) {
    btnRefreshVending.addEventListener('click', loadManagerVending);
}

const btnAddVendingItem = document.getElementById('btn-add-vending-item');
if (btnAddVendingItem) {
    btnAddVendingItem.addEventListener('click', async () => {
        if (btnAddVendingItem.disabled) return;
        const select = document.getElementById('vending-item-select');
        const qtyInput = document.getElementById('vending-stock-qty');
        const priceInput = document.getElementById('vending-item-price');

        const itemName = select ? select.value : '';
        const qty = Math.max(1, Math.min(500, Math.floor(Number(qtyInput ? qtyInput.value : 1) || 1)));
        const price = Math.max(1, Math.min(50000, Math.floor(Number(priceInput ? priceInput.value : 15) || 15)));

        if (!itemName) {
            showToast('Select a valid item from your inventory to restock.', 'error');
            return;
        }

        btnAddVendingItem.disabled = true;
        try {
            const res = await postNUI('upsertVendingItem', {
                restaurantId: AppState.restaurantId,
                item_name: itemName,
                add_stock: qty,
                price
            });
            if (res && res.ok) {
                if (Array.isArray(res.items)) {
                    AppState.vendingItems = res.items;
                    renderVendingManageTable();
                }
                showToast(res.message || 'Item stocked in vending machine!', 'success');
                await loadManagerVending();
            } else {
                showToast((res && res.message) || 'Failed to restock item.', 'error');
            }
        } finally {
            btnAddVendingItem.disabled = false;
        }
    });
}

function renderVendingFundBalance() {
    const balEl = document.getElementById('vending-fund-balance');
    const bal = Math.max(0, Math.floor(Number(AppState.vendingFundBalance) || 0));
    if (balEl) {
        balEl.textContent = `$${bal.toLocaleString('en-US')}`;
    }
    const amtInput = document.getElementById('vending-fund-amount');
    if (amtInput) {
        amtInput.max = bal > 0 ? String(bal) : '';
    }
}

function handleSyncVendingFund(restaurantId, balance) {
    if (AppState.restaurantId !== restaurantId) return;
    AppState.vendingFundBalance = Math.max(0, Math.floor(Number(balance) || 0));
    renderVendingFundBalance();
}

async function loadManagerVendingFund() {
    if (!AppState.restaurantId) return;
    const canVendingFund = AppState.isAdmin || (AppState.permissions && AppState.permissions.vending_fund === true);
    if (!canVendingFund) return;

    try {
        const res = await postNUI('getVendingFund', { restaurantId: AppState.restaurantId });
        if (res && res.ok) {
            AppState.vendingFundBalance = Math.max(0, Math.floor(Number(res.balance) || 0));
        }
    } catch (err) {
        // Ignore transient fetch errors cleanly
    }
    renderVendingFundBalance();
}

async function handleWithdrawVendingFund(withdrawAll) {
    if (!AppState.restaurantId) return;
    const canVendingFund = AppState.isAdmin || (AppState.permissions && AppState.permissions.vending_fund === true);
    if (!canVendingFund) {
        showToast('You do not have permission to withdraw vending funds.', 'error');
        return;
    }

    const destEl = document.getElementById('vending-fund-destination');
    const amtEl = document.getElementById('vending-fund-amount');
    const btnWithdraw = document.getElementById('btn-withdraw-vending-fund');
    const btnWithdrawAll = document.getElementById('btn-withdraw-all-vending-fund');

    const destination = destEl ? destEl.value : 'cash';
    const rawAmount = Math.floor(Number(amtEl ? amtEl.value : 0) || 0);
    if (!withdrawAll && rawAmount <= 0) {
        showToast('Enter a valid withdrawal amount greater than $0.', 'error');
        return;
    }

    if (btnWithdraw) btnWithdraw.disabled = true;
    if (btnWithdrawAll) btnWithdrawAll.disabled = true;
    try {
        const res = await postNUI('withdrawVendingFund', {
            restaurantId: AppState.restaurantId,
            destination,
            amount: rawAmount,
            withdrawAll: !!withdrawAll
        });
        if (res && res.ok) {
            AppState.vendingFundBalance = Math.max(0, Math.floor(Number(res.balance) || 0));
            renderVendingFundBalance();
            if (amtEl) amtEl.value = '';
            showToast(res.message || 'Vending fund withdrawn successfully!', 'success');
        } else {
            if (res && typeof res.balance === 'number') {
                AppState.vendingFundBalance = Math.max(0, Math.floor(res.balance));
                renderVendingFundBalance();
            }
            showToast((res && res.message) || 'Failed to withdraw vending funds.', 'error');
        }
    } finally {
        if (btnWithdraw) btnWithdraw.disabled = false;
        if (btnWithdrawAll) btnWithdrawAll.disabled = false;
    }
}

const btnRefreshVendingFund = document.getElementById('btn-refresh-vending-fund');
if (btnRefreshVendingFund) {
    btnRefreshVendingFund.addEventListener('click', loadManagerVendingFund);
}

const btnWithdrawVendingFund = document.getElementById('btn-withdraw-vending-fund');
if (btnWithdrawVendingFund) {
    btnWithdrawVendingFund.addEventListener('click', () => handleWithdrawVendingFund(false));
}

const btnWithdrawAllVendingFund = document.getElementById('btn-withdraw-all-vending-fund');
if (btnWithdrawAllVendingFund) {
    btnWithdrawAllVendingFund.addEventListener('click', () => handleWithdrawVendingFund(true));
}

function getVendingInCartQty(itemName) {
    const found = (AppState.vendingCart || []).find(c => c.item_name === itemName);
    return found ? (Number(found.count) || 0) : 0;
}

function reconcileVendingCart() {
    const itemMap = new Map();
    (AppState.vendingItems || []).forEach(it => {
        if (it && it.item_name) itemMap.set(it.item_name, it);
    });

    const nextCart = [];
    (AppState.vendingCart || []).forEach(c => {
        const live = itemMap.get(c.item_name);
        const stock = live ? Math.max(0, Number(live.stock) || 0) : 0;
        if (!live || stock <= 0) return;
        const clamped = Math.max(0, Math.min(Math.min(50, stock), Math.floor(Number(c.count) || 0)));
        if (clamped <= 0) return;
        nextCart.push({
            item_name: live.item_name,
            label: live.label || live.item_name,
            price: Math.max(1, Number(live.price) || 15),
            count: clamped
        });
    });
    AppState.vendingCart = nextCart;
}

function addToVendingCart(item, rawQty) {
    if (!item || !item.item_name) return;
    const stock = Math.max(0, Number(item.stock) || 0);
    const maxCap = Math.min(50, stock);
    const inCart = getVendingInCartQty(item.item_name);
    const remaining = maxCap - inCart;
    if (remaining <= 0) {
        showToast(`Cannot add more. Max available is ${maxCap}.`, 'warning');
        return;
    }

    const addQty = Math.max(1, Math.min(remaining, Math.floor(Number(rawQty) || 1)));
    const existing = AppState.vendingCart.find(c => c.item_name === item.item_name);
    if (existing) {
        existing.count += addQty;
        existing.price = Math.max(1, Number(item.price) || 15);
        existing.label = item.label || item.item_name;
    } else {
        AppState.vendingCart.push({
            item_name: item.item_name,
            label: item.label || item.item_name,
            price: Math.max(1, Number(item.price) || 15),
            count: addQty
        });
    }

    renderVendingShopGrid();
    renderVendingCart();
}

function changeVendingCartQty(itemName, delta) {
    const entry = (AppState.vendingCart || []).find(c => c.item_name === itemName);
    if (!entry) return;
    const live = (AppState.vendingItems || []).find(i => i.item_name === itemName);
    const maxCap = live ? Math.min(50, Math.max(0, Number(live.stock) || 0)) : 0;

    const next = entry.count + delta;
    if (next <= 0 || maxCap <= 0) {
        AppState.vendingCart = AppState.vendingCart.filter(c => c.item_name !== itemName);
    } else if (next > maxCap) {
        showToast(`Only ${maxCap} available in stock.`, 'warning');
        entry.count = maxCap;
    } else {
        entry.count = next;
    }

    renderVendingShopGrid();
    renderVendingCart();
}

function renderVendingCart() {
    const container = document.getElementById('vending-cart-items');
    const countEl = document.getElementById('vending-cart-count');
    const totalEl = document.getElementById('vending-cart-total');
    const checkoutBtn = document.getElementById('btn-vending-checkout');
    const checkoutLabel = document.getElementById('vending-checkout-label');
    if (!container) return;

    reconcileVendingCart();
    container.innerHTML = '';

    if (!AppState.vendingCart || AppState.vendingCart.length === 0) {
        container.innerHTML = `
            <div class="cart-empty-message">
                <i class="fa-solid fa-cart-arrow-down"></i>
                <p>Your cart is empty.</p>
                <span>Add items from the machine to buy together!</span>
            </div>
        `;
        if (countEl) countEl.textContent = '0';
        if (totalEl) totalEl.textContent = '$0';
        if (checkoutLabel) checkoutLabel.textContent = 'Checkout ($0)';
        if (checkoutBtn) checkoutBtn.disabled = true;
        return;
    }

    let totalUnits = 0;
    let totalCost = 0;
    AppState.vendingCart.forEach(c => {
        const lineTotal = c.price * c.count;
        totalUnits += c.count;
        totalCost += lineTotal;

        const row = document.createElement('div');
        row.className = 'cart-item-row';
        row.innerHTML = `
            <div class="cart-item-info">
                <h5>${escapeHtml(c.label)}</h5>
                <span>$${c.price} &times; ${c.count} = $${lineTotal}</span>
            </div>
            <div class="cart-qty-ctrls">
                <button type="button" class="qty-btn btn-minus"><i class="fa-solid fa-minus"></i></button>
                <span class="cart-qty-val">${c.count}</span>
                <button type="button" class="qty-btn btn-plus"><i class="fa-solid fa-plus"></i></button>
            </div>
        `;

        row.querySelector('.btn-minus').addEventListener('click', () => changeVendingCartQty(c.item_name, -1));
        row.querySelector('.btn-plus').addEventListener('click', () => changeVendingCartQty(c.item_name, 1));
        container.appendChild(row);
    });

    if (countEl) countEl.textContent = String(totalUnits);
    if (totalEl) totalEl.textContent = `$${totalCost}`;
    if (checkoutLabel) checkoutLabel.textContent = `Checkout ($${totalCost})`;
    if (checkoutBtn) checkoutBtn.disabled = false;
}

function renderVendingShopGrid() {
    const grid = document.getElementById('vending-customer-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const items = (AppState.vendingItems || []).filter(i => (Number(i.stock) || 0) > 0);
    if (items.length === 0) {
        grid.innerHTML = `
            <div class="vending-empty-state">
                <i class="fa-solid fa-box-open"></i>
                <p>This vending machine is currently empty.</p>
                <span>Check back soon for fresh restocks!</span>
            </div>
        `;
        return;
    }

    items.forEach(item => {
        const stock = Math.max(0, Number(item.stock) || 0);
        const price = Math.max(1, Number(item.price) || 15);
        const inCart = getVendingInCartQty(item.item_name);
        const availableToAdd = Math.max(0, Math.min(50, stock) - inCart);

        const card = document.createElement('div');
        card.className = 'vending-item-card';
        card.innerHTML = `
            <div class="vending-card-top">
                <img src="nui://ox_inventory/web/images/${escapeHtml(item.item_name)}.png" class="vending-card-img" onerror="handleImgFallback(this, '${escapeHtml(item.item_name)}')">
                <div>
                    <div class="vending-card-title">${escapeHtml(item.label || item.item_name)}</div>
                    <div class="vending-card-price">$${price}</div>
                    <div class="vending-card-badges">
                        <span class="stock-tag in-stock">Stock: ${stock}</span>
                        ${inCart > 0 ? `<span class="stock-tag vending-in-cart-tag">In Cart: ${inCart}</span>` : ''}
                    </div>
                </div>
            </div>
            <div class="vending-buy-row">
                <input type="number" class="vending-buy-qty" min="1" max="${Math.max(1, availableToAdd)}" value="1" ${availableToAdd <= 0 ? 'disabled' : ''}>
                <button type="button" class="action-btn primary flex-1 btn-vending-add" ${availableToAdd <= 0 ? 'disabled' : ''}>
                    <i class="fa-solid fa-cart-plus"></i> ${availableToAdd <= 0 ? 'Max' : 'Add'}
                </button>
            </div>
        `;

        const qtyInput = card.querySelector('.vending-buy-qty');
        const btnAdd = card.querySelector('.btn-vending-add');
        if (btnAdd && qtyInput) {
            btnAdd.addEventListener('click', () => {
                if (btnAdd.disabled) return;
                const qty = Math.max(1, Math.min(Math.max(1, availableToAdd), Math.floor(Number(qtyInput.value) || 1)));
                qtyInput.value = qty;
                addToVendingCart(item, qty);
            });
        }

        grid.appendChild(card);
    });
}

function initVendingCustomerView(data) {
    AppState.restaurantId = data.restaurantId || 'burgershot';
    AppState.restaurantLabel = data.restaurantLabel || 'Restaurant';
    AppState.vendingItems = Array.isArray(data.items) ? data.items : [];
    AppState.vendingCart = [];
    AppState.vendingOnlyMode = false;
    AppState.vendingPaymentMethod = 'cash';

    const cashRadio = document.getElementById('vending-pay-cash');
    if (cashRadio) cashRadio.checked = true;

    const titleEl = document.getElementById('vending-shop-title');
    if (titleEl) titleEl.textContent = `${AppState.restaurantLabel} Vending Machine`;

    renderVendingShopGrid();
    renderVendingCart();

    const windowContainer = document.getElementById('main-window') || document.querySelector('.window-container');
    if (windowContainer) {
        windowContainer.classList.add('hidden');
        windowContainer.style.display = 'none';
    }
    const stationView = document.getElementById('station-cooking-view');
    if (stationView) {
        stationView.classList.add('hidden');
        stationView.style.display = 'none';
    }
    const vendingView = document.getElementById('vending-customer-view');
    if (vendingView) {
        vendingView.classList.remove('hidden');
        vendingView.style.display = 'flex';
    }
    const appEl = document.getElementById('app');
    if (appEl) {
        appEl.classList.remove('hidden');
        appEl.style.display = 'flex';
    }
}

function handleSyncVending(restaurantId, items) {
    if (AppState.restaurantId !== restaurantId || !Array.isArray(items)) return;
    AppState.vendingItems = items;
    reconcileVendingCart();

    const vendingView = document.getElementById('vending-customer-view');
    if (vendingView && !vendingView.classList.contains('hidden')) {
        renderVendingShopGrid();
        renderVendingCart();
    }
    const managePane = document.getElementById('manager-vending');
    if (managePane && managePane.classList.contains('active')) {
        renderVendingManageTable();
    }
}

const btnCloseVendingView = document.getElementById('btn-close-vending-view');
if (btnCloseVendingView) {
    btnCloseVendingView.addEventListener('click', closeApp);
}

const btnClearVendingCart = document.getElementById('btn-vending-clear-cart');
if (btnClearVendingCart) {
    btnClearVendingCart.addEventListener('click', () => {
        AppState.vendingCart = [];
    AppState.vendingOnlyMode = false;
        renderVendingShopGrid();
        renderVendingCart();
    });
}

document.querySelectorAll('input[name="vending-pay-method"]').forEach(radio => {
    radio.addEventListener('change', () => {
        if (radio.checked) {
            AppState.vendingPaymentMethod = radio.value === 'bank' ? 'bank' : 'cash';
        }
    });
});

const btnVendingCheckout = document.getElementById('btn-vending-checkout');
if (btnVendingCheckout) {
    btnVendingCheckout.addEventListener('click', async () => {
        if (btnVendingCheckout.disabled || !AppState.vendingCart || AppState.vendingCart.length === 0) return;
        btnVendingCheckout.disabled = true;
        try {
            const res = await postNUI('buyVendingCart', {
                restaurantId: AppState.restaurantId,
                items: AppState.vendingCart.map(c => ({
                    item_name: c.item_name,
                    qty: c.count
                })),
                paymentMethod: AppState.vendingPaymentMethod || 'cash'
            });
            if (res && res.ok) {
                AppState.vendingCart = [];
    AppState.vendingOnlyMode = false;
                if (Array.isArray(res.items)) AppState.vendingItems = res.items;
                showToast(res.message || 'Purchase completed!', 'success');
                renderVendingShopGrid();
                renderVendingCart();
            } else {
                showToast((res && res.message) || 'Purchase failed.', 'error');
                renderVendingCart();
            }
        } finally {
            renderVendingCart();
        }
    });
}

// ====================================================================
// OWNER TAB (Stations, Roles, Recipe Editor, Logs)
// ====================================================================
function populateStationTypeDropdown() {
    const select = document.getElementById('station-type-select');
    select.innerHTML = '';
    Object.entries(AppState.stationTypes).forEach(([type, data]) => {
        const opt = document.createElement('option');
        opt.value = type;
        opt.textContent = `${data.label} (Max: ${data.maxPerRestaurant})`;
        select.appendChild(opt);
    });
}

document.getElementById('btn-place-station').addEventListener('click', () => {
    const type = document.getElementById('station-type-select').value;
    postNUI('startPlacementMode', {
        restaurantId: AppState.restaurantId,
        stationType: type
    });
});

document.getElementById('btn-delete-all-stations').addEventListener('click', () => {
    const confirmed = confirm('Are you sure you want to remove ALL placed target zones and cooking stations? This cannot be undone.');
    if (!confirmed) return;

    postNUI('deleteAllStations', {
        restaurantId: AppState.restaurantId
    });

    AppState.stations = [];
    renderOwnerStationsTable();
    showToast('All zones and stations have been deleted.', 'info');
});

function renderOwnerStationsTable() {
    const tbody = document.getElementById('stations-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';

    const rawList = Array.isArray(AppState.stations)
        ? AppState.stations
        : Object.values(AppState.stations || {});

    // Filter out null, undefined, or malformed items
    const list = rawList.filter(st => st && typeof st === 'object' && st.id);

    if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-dim); padding: 25px;">No target zones or stations placed yet. Select a zone type above and click "Place Zone (3D Mode)".</td></tr>';
        return;
    }

    list.forEach(st => {
        const tr = document.createElement('tr');
        const c = st.coords || {};
        const coordsStr = `${c.x || 0}, ${c.y || 0}, ${c.z || 0}`;
        const typeInfo = AppState.stationTypes[st.station_type];
        const typeLabel = (typeInfo && typeInfo.label) || st.station_type;

        tr.innerHTML = `
            <td><strong>#${st.id}</strong></td>
            <td><strong>${typeLabel}</strong></td>
            <td><code>${coordsStr}</code></td>
            <td>${st.created_by || 'Owner'}</td>
            <td><button class="action-btn danger small btn-del-station"><i class="fa-solid fa-trash"></i> Delete</button></td>
        `;

        tr.querySelector('.btn-del-station').addEventListener('click', () => {
            postNUI('deleteStation', {
                restaurantId: AppState.restaurantId,
                stationId: st.id
            });
            if (Array.isArray(AppState.stations)) {
                AppState.stations = AppState.stations.filter(s => s && s.id !== st.id);
            } else if (AppState.stations) {
                delete AppState.stations[st.id];
                delete AppState.stations[String(st.id)];
            }
            renderOwnerStationsTable();
        });

        tbody.appendChild(tr);
    });
}

// ====================================================================
// DOOR LOCKS MANAGEMENT (Owner Controls)
// ====================================================================
document.getElementById('btn-place-door')?.addEventListener('click', () => {
    const labelInput = document.getElementById('door-label-input');
    const labelVal = labelInput ? labelInput.value.trim() : '';
    if (labelInput) labelInput.value = '';
    postNUI('startDoorPlacementMode', {
        restaurantId: AppState.restaurantId,
        label: labelVal
    });
});

document.getElementById('btn-delete-all-doors')?.addEventListener('click', () => {
    const confirmed = confirm('Are you sure you want to remove ALL saved door locks?');
    if (!confirmed) return;

    postNUI('deleteAllDoors', {
        restaurantId: AppState.restaurantId
    });

    AppState.doors = [];
    renderOwnerDoorsTable();
    showToast('All door locks have been removed.', 'info');
});

function renderOwnerDoorsTable() {
    const tbody = document.getElementById('doors-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';

    const rawList = Array.isArray(AppState.doors)
        ? AppState.doors
        : Object.values(AppState.doors || {});
    const list = rawList.filter(d => d && typeof d === 'object' && d.id);

    if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-dim); padding: 25px;">No door locks added yet. Enter a name and click "Pick Door (3D Mode)" to lock a single or double door.</td></tr>';
        return;
    }

    list.forEach(door => {
        const tr = document.createElement('tr');
        const isLocked = door.locked === true;
        const isAutoLock = door.autoLock === true;
        const typeLabel = door.isDouble ? 'Double Door' : 'Single Door';

        tr.innerHTML = `
            <td><strong>#${door.id}</strong></td>
            <td><strong>${escapeHtml(door.label || ('Door #' + door.id))}</strong></td>
            <td><span class="recipe-station-pill">${typeLabel}</span></td>
            <td><span class="stock-tag ${isLocked ? 'out-stock' : 'in-stock'}">${isLocked ? 'Locked' : 'Unlocked'}</span></td>
            <td>${escapeHtml(door.created_by || 'Owner')}</td>
            <td style="display: flex; gap: 6px; flex-wrap: wrap;">
                <button class="action-btn secondary small btn-toggle-door" title="Toggle Lock State">
                    <i class="fa-solid ${isLocked ? 'fa-lock-open' : 'fa-lock'}"></i> ${isLocked ? 'Unlock' : 'Lock'}
                </button>
                <button class="action-btn ${isAutoLock ? 'primary' : 'secondary'} small btn-auto-lock" title="Automatically re-locks this door 5 seconds after unlocking">
                    <i class="fa-solid fa-clock-rotate-left"></i> Auto Lock: ${isAutoLock ? 'ON' : 'OFF'}
                </button>
                <button class="action-btn danger small btn-del-door"><i class="fa-solid fa-trash"></i> Delete</button>
            </td>
        `;

        tr.querySelector('.btn-toggle-door').addEventListener('click', async () => {
            const res = await postNUI('toggleDoorLock', {
                restaurantId: AppState.restaurantId,
                doorId: door.id
            });
            if (res && res.ok) {
                door.locked = !!res.locked;
                renderOwnerDoorsTable();
            } else if (res && res.message) {
                showToast(res.message, 'danger');
            }
        });

        tr.querySelector('.btn-auto-lock').addEventListener('click', async () => {
            const res = await postNUI('toggleDoorAutoLock', {
                restaurantId: AppState.restaurantId,
                doorId: door.id
            });
            if (res && res.ok) {
                door.autoLock = !!res.autoLock;
                renderOwnerDoorsTable();
                showToast(
                    `${door.label || ('Door #' + door.id)} Auto Lock ${door.autoLock ? 'activated (5s)' : 'deactivated'}.`,
                    door.autoLock ? 'success' : 'info'
                );
            } else if (res && res.message) {
                showToast(res.message, 'danger');
            }
        });

        tr.querySelector('.btn-del-door').addEventListener('click', () => {
            postNUI('deleteDoor', {
                restaurantId: AppState.restaurantId,
                doorId: door.id
            });
            AppState.doors = list.filter(d => d && d.id !== door.id);
            renderOwnerDoorsTable();
        });

        tbody.appendChild(tr);
    });
}

function buildPermissionCheckboxesHtml(selectedPerms = [], disabled = false) {
    const permsSet = new Set(Array.isArray(selectedPerms) ? selectedPerms : []);
    return (AppState.allPermissionsList || []).map(p => {
        const isChecked = permsSet.has(p.id);
        return `
            <label class="perm-item">
                <input type="checkbox" value="${escapeHtml(p.id)}" ${isChecked ? 'checked' : ''} ${disabled ? 'disabled' : ''}>
                <span>${escapeHtml(p.label)}</span>
            </label>
        `;
    }).join('');
}

function getNextAvailableRoleGrade() {
    const used = new Set((AppState.roles || []).map(r => Number(r.grade)));
    for (let g = 1; g <= 8; g++) {
        if (!used.has(g)) return g;
    }
    for (let g = 11; g <= 99; g++) {
        if (!used.has(g)) return g;
    }
    return 11;
}

function openRoleModal(role = null) {
    const modal = document.getElementById('role-modal');
    if (!modal) return;

    const isEdit = Boolean(role);
    const titleEl = document.getElementById('role-modal-title');
    const isNewEl = document.getElementById('role-input-is-new');
    const nameEl = document.getElementById('role-input-name');
    const gradeEl = document.getElementById('role-input-grade');
    const salaryEl = document.getElementById('role-input-salary');
    const permsEl = document.getElementById('role-modal-perms-list');

    if (titleEl) titleEl.textContent = isEdit ? `Edit Role (Grade ${role.grade})` : 'Add New Role';
    if (isNewEl) isNewEl.value = isEdit ? '0' : '1';
    if (nameEl) nameEl.value = isEdit ? (role.role_name || '') : '';
    if (gradeEl) {
        gradeEl.value = isEdit ? Number(role.grade) : getNextAvailableRoleGrade();
        gradeEl.disabled = isEdit;
    }
    if (salaryEl) salaryEl.value = isEdit ? Math.max(0, parseInt(role.base_salary, 10) || 0) : 0;
    if (permsEl) {
        const defaultPerms = isEdit ? (role.permissions || []) : ['view_orders', 'cook'];
        permsEl.innerHTML = buildPermissionCheckboxesHtml(defaultPerms, false);
    }

    modal.classList.remove('hidden');
    modal.style.display = 'flex';
}

function closeRoleModal() {
    const modal = document.getElementById('role-modal');
    if (modal) {
        modal.classList.add('hidden');
        modal.style.display = 'none';
    }
}

// Role Permissions Editor & Salary Role Base List
async function loadOwnerRoles() {
    const container = document.getElementById('roles-list-container');
    const salaryList = document.getElementById('salary-roles-list');
    if (container) container.innerHTML = 'Loading roles...';
    if (salaryList) salaryList.innerHTML = '<div style="color: var(--text-dim); padding: 12px;">Loading role salaries...</div>';

    const roles = await postNUI('getRoles', { restaurantId: AppState.restaurantId }) || [];
    AppState.roles = roles;
    if (container) container.innerHTML = '';

    roles.forEach(role => {
        if (!container) return;
        const card = document.createElement('div');
        card.className = 'role-card';

        const gradeNum = Number(role.grade) || 0;
        const isAdminRole = Boolean(role.is_admin);
        const isOwnerGrade = !isAdminRole && Boolean(role.is_owner);
        const isBaseGrade = (gradeNum === 0);
        const canEditRole = !isAdminRole && (!isOwnerGrade || AppState.canEditOwnerRole);
        const canDeleteRole = !isAdminRole && !isOwnerGrade && !isBaseGrade;
        const effectivePerms = isAdminRole ? (AppState.allPermissionsList || []).map(p => p.id) : role.permissions;
        const permsCheckboxes = buildPermissionCheckboxesHtml(effectivePerms, !canEditRole);

        let badgeHtml = '';
        if (isAdminRole) {
            badgeHtml = '<span class="badge" style="background: rgba(16, 185, 129, 0.15); color: #10b981;">Full Access (Admin)</span>';
        } else if (isBaseGrade) {
            badgeHtml = '<span class="badge" style="background: rgba(59, 130, 246, 0.14); color: #60a5fa;">Default Base Grade</span>';
        }

        const actionsHtml = !canEditRole ? '' : `
            <div class="role-card-actions">
                <button type="button" class="action-btn small btn-edit-role" title="Edit Name &amp; Role Settings"><i class="fa-solid fa-pen"></i> Edit</button>
                <button type="button" class="action-btn primary small btn-save-role" title="Save Checked Permissions"><i class="fa-solid fa-floppy-disk"></i> Save</button>
                ${canDeleteRole ? '<button type="button" class="action-btn danger small btn-delete-role" title="Delete Role"><i class="fa-solid fa-trash"></i></button>' : ''}
            </div>
        `;

        card.innerHTML = `
            <div class="role-card-header">
                <div>
                    <h4>${escapeHtml(role.role_name)} (Grade ${gradeNum})</h4>
                    ${badgeHtml}
                </div>
                ${actionsHtml}
            </div>
            <div class="perms-checklist">
                ${permsCheckboxes}
            </div>
        `;

        if (canEditRole) {
            const btnSave = card.querySelector('.btn-save-role');
            if (btnSave) {
                btnSave.addEventListener('click', async () => {
                    const selectedPerms = [];
                    card.querySelectorAll('input[type="checkbox"]:checked').forEach(cb => selectedPerms.push(cb.value));

                    const res = await postNUI('saveRole', {
                        restaurantId: AppState.restaurantId,
                        grade: gradeNum,
                        role_name: role.role_name,
                        permissions: selectedPerms,
                        base_salary: role.base_salary,
                        isNew: false
                    });
                    if (res && res.ok === false) {
                        showToast(res.message || 'Failed to save role.', 'error');
                        return;
                    }
                    showToast(`Saved permissions for ${role.role_name} (Grade ${gradeNum})`, 'success');
                    loadOwnerRoles();
                });
            }

            const btnEdit = card.querySelector('.btn-edit-role');
            if (btnEdit) {
                btnEdit.addEventListener('click', () => openRoleModal(role));
            }

            const btnDelete = card.querySelector('.btn-delete-role');
            if (btnDelete) {
                let resetTimer = null;
                btnDelete.addEventListener('click', async () => {
                    if (!btnDelete.classList.contains('confirming')) {
                        btnDelete.classList.add('confirming');
                        btnDelete.innerHTML = '<i class="fa-solid fa-check"></i> Confirm?';
                        resetTimer = setTimeout(() => {
                            btnDelete.classList.remove('confirming');
                            btnDelete.innerHTML = '<i class="fa-solid fa-trash"></i>';
                        }, 3500);
                        return;
                    }

                    if (resetTimer) clearTimeout(resetTimer);
                    btnDelete.disabled = true;
                    const res = await postNUI('deleteRole', {
                        restaurantId: AppState.restaurantId,
                        grade: gradeNum
                    });
                    if (res && res.ok) {
                        showToast(res.message || `Deleted role ${role.role_name}`, 'success');
                        loadOwnerRoles();
                    } else {
                        btnDelete.disabled = false;
                        btnDelete.classList.remove('confirming');
                        btnDelete.innerHTML = '<i class="fa-solid fa-trash"></i>';
                        showToast((res && res.message) || 'Failed to delete role.', 'error');
                    }
                });
            }
        }

        container.appendChild(card);
    });

    renderSalaryRolesList(roles);
}

const btnOpenRoleModal = document.getElementById('btn-open-role-modal');
if (btnOpenRoleModal) {
    btnOpenRoleModal.addEventListener('click', () => openRoleModal(null));
}
const btnCloseRoleModal = document.getElementById('btn-close-role-modal');
if (btnCloseRoleModal) {
    btnCloseRoleModal.addEventListener('click', closeRoleModal);
}
const btnCancelRole = document.getElementById('btn-cancel-role');
if (btnCancelRole) {
    btnCancelRole.addEventListener('click', closeRoleModal);
}
const btnSaveRoleModal = document.getElementById('btn-save-role-modal');
if (btnSaveRoleModal) {
    btnSaveRoleModal.addEventListener('click', async () => {
        if (btnSaveRoleModal.disabled) return;

        const isNewEl = document.getElementById('role-input-is-new');
        const nameEl = document.getElementById('role-input-name');
        const gradeEl = document.getElementById('role-input-grade');
        const salaryEl = document.getElementById('role-input-salary');
        const permsEl = document.getElementById('role-modal-perms-list');

        const isNew = isNewEl && isNewEl.value === '1';
        const roleName = (nameEl ? nameEl.value : '').trim();
        const grade = parseInt(gradeEl ? gradeEl.value : '', 10);
        const baseSalary = Math.max(0, Math.min(1000000, Math.floor(Number(salaryEl ? salaryEl.value : 0) || 0)));

        if (!roleName || roleName.length > 50) {
            showToast('Please enter a valid role name (1 - 50 characters).', 'error');
            return;
        }
        if (Number.isNaN(grade) || grade < 0 || grade > 99) {
            showToast('Please enter a valid grade level between 0 and 99.', 'error');
            return;
        }

        const selectedPerms = [];
        if (permsEl) {
            permsEl.querySelectorAll('input[type="checkbox"]:checked').forEach(cb => selectedPerms.push(cb.value));
        }

        btnSaveRoleModal.disabled = true;
        try {
            const res = await postNUI('saveRole', {
                restaurantId: AppState.restaurantId,
                grade,
                role_name: roleName,
                permissions: selectedPerms,
                base_salary: baseSalary,
                isNew
            });

            if (res && res.ok) {
                closeRoleModal();
                showToast(res.message || `Saved role ${roleName}!`, 'success');
                await loadOwnerRoles();
            } else {
                showToast((res && res.message) || 'Failed to save role.', 'error');
            }
        } finally {
            btnSaveRoleModal.disabled = false;
        }
    });
}

/** Render base salary inputs for every configured restaurant job role. */
function renderSalaryRolesList(roles) {
    const listEl = document.getElementById('salary-roles-list');
    if (!listEl) return;
    listEl.innerHTML = '';

    if (!Array.isArray(roles) || roles.length === 0) {
        listEl.innerHTML = '<div style="color: var(--text-dim); padding: 12px;">No roles found.</div>';
        return;
    }

    roles.forEach(role => {
        const row = document.createElement('div');
        row.className = 'salary-role-row';
        const baseSalary = Math.max(0, parseInt(role.base_salary, 10) || 0);

        row.innerHTML = `
            <div class="salary-role-meta">
                <span class="salary-grade-pill">Grade ${Number(role.grade) || 0}</span>
                <span class="salary-role-name">${escapeHtml(role.role_name || ('Grade ' + role.grade))}</span>
            </div>
            <div class="salary-role-input-wrap">
                <span class="salary-role-currency">$</span>
                <input type="number" class="salary-role-input" data-grade="${Number(role.grade) || 0}" min="0" max="1000000" step="10" value="${baseSalary}">
            </div>
        `;
        listEl.appendChild(row);
    });
}

// Recipe Editor Table & Modal
async function loadOxItems() {
    if (AppState.oxItems.length === 0) {
        AppState.oxItems = await postNUI('getOxItems') || [];
    }
}

function renderOwnerRecipesTable() {
    const tbody = document.getElementById('owner-recipes-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';

    const list = (Array.isArray(AppState.recipes)
        ? AppState.recipes
        : Object.values(AppState.recipes || {})).filter(rec => rec && typeof rec === 'object' && rec.id);
    if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-dim);">No recipes configured.</td></tr>';
        return;
    }

    list.forEach(rec => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td><strong>${escapeHtml(rec.recipe_name || '')}</strong></td>
            <td><span class="recipe-station-pill">${escapeHtml(rec.station_type || '')}</span></td>
            <td>${rec.output_count || 1}x ${escapeHtml(getStationItemLabel(rec.output_item))}</td>
            <td>${(rec.cooking_time || 5000) / 1000}s</td>
            <td><span class="stock-tag ${rec.enabled ? 'in-stock' : 'out-stock'}">${rec.enabled ? 'Active' : 'Disabled'}</span></td>
            <td>
                <button class="action-btn small btn-edit-recipe" title="Edit Recipe"><i class="fa-solid fa-pen"></i></button>
                <button class="action-btn danger small btn-del-recipe" title="Delete Recipe"><i class="fa-solid fa-trash"></i></button>
            </td>
        `;

        tr.querySelector('.btn-edit-recipe').addEventListener('click', () => {
            loadOxItems().then(() => {
                openRecipeModal(rec);
            });
        });

        tr.querySelector('.btn-del-recipe').addEventListener('click', () => {
            postNUI('deleteRecipe', {
                restaurantId: AppState.restaurantId,
                recipeId: rec.id
            });
            AppState.recipes = list.filter(r => r && Number(r.id) !== Number(rec.id));
            renderOwnerRecipesTable();
            renderStaffRecipes();
        });

        tbody.appendChild(tr);
    });
}

function closeRecipeModal() {
    const modal = document.getElementById('recipe-modal');
    if (modal) {
        modal.classList.add('hidden');
        modal.style.display = 'none';
    }
}

document.getElementById('btn-open-recipe-modal')?.addEventListener('click', async () => {
    try {
        await loadOxItems();
    } catch (_) {}
    openRecipeModal();
});

document.getElementById('btn-close-recipe-modal')?.addEventListener('click', closeRecipeModal);
document.getElementById('btn-cancel-recipe')?.addEventListener('click', closeRecipeModal);

function populateOxItemSelect(selectEl, query = '', preferredValue = '') {
    if (!selectEl) return;
    const oxItems = Array.isArray(AppState.oxItems) ? AppState.oxItems : [];
    const term = String(query || '').trim().toLowerCase();
    const filtered = term
        ? oxItems.filter(item => {
            if (!item || !item.name) return false;
            const name = String(item.name).toLowerCase();
            const label = String(item.label || item.name).toLowerCase();
            return name.includes(term) || label.includes(term);
        })
        : oxItems.filter(item => item && item.name);

    selectEl.innerHTML = '';
    if (filtered.length === 0) {
        const emptyOpt = document.createElement('option');
        emptyOpt.value = '';
        emptyOpt.disabled = true;
        emptyOpt.selected = true;
        emptyOpt.textContent = term ? `No items matching "${query.trim()}"` : 'No items loaded';
        selectEl.appendChild(emptyOpt);
        return;
    }

    let matchedPreferred = false;
    filtered.forEach(item => {
        const opt = document.createElement('option');
        opt.value = item.name;
        opt.textContent = `${item.label || item.name} (${item.name})`;
        if (preferredValue && item.name === preferredValue) {
            opt.selected = true;
            matchedPreferred = true;
        }
        selectEl.appendChild(opt);
    });

    if (!matchedPreferred && filtered[0]) {
        selectEl.value = filtered[0].name;
    }
}

document.getElementById('recipe-output-search')?.addEventListener('input', (e) => {
    const outputSelect = document.getElementById('recipe-input-output');
    if (outputSelect) {
        populateOxItemSelect(outputSelect, e.target.value, outputSelect.value);
    }
});

function openRecipeModal(existing = null) {
    const modal = document.getElementById('recipe-modal');
    if (!modal) return;
    const titleEl = document.getElementById('recipe-modal-title');
    if (titleEl) titleEl.textContent = existing ? 'Edit Recipe' : 'Create New Recipe';
    const stationSelect = document.getElementById('recipe-input-station');
    const outputSelect = document.getElementById('recipe-input-output');
    const outputSearch = document.getElementById('recipe-output-search');
    if (outputSearch) outputSearch.value = '';

    if (stationSelect) {
        stationSelect.innerHTML = '';
        const allStations = Object.entries(AppState.stationTypes || {});
        const cookingStations = allStations.filter(([, data]) => data && data.category === 'cooking');
        const stationEntries = (cookingStations.length > 0 ? cookingStations : allStations)
            .sort(([, a], [, b]) => String((a && a.label) || '').localeCompare(String((b && b.label) || '')));

        if (!existing || !existing.station_type) {
            const placeholder = document.createElement('option');
            placeholder.value = '';
            placeholder.textContent = '-- Select Cooking Machine --';
            placeholder.disabled = true;
            placeholder.selected = true;
            stationSelect.appendChild(placeholder);
        }

        stationEntries.forEach(([type, data]) => {
            const opt = document.createElement('option');
            opt.value = type;
            opt.textContent = (data && data.label) ? data.label : type;
            if (existing && existing.station_type === type) opt.selected = true;
            stationSelect.appendChild(opt);
        });
    }

    populateOxItemSelect(outputSelect, '', existing ? existing.output_item : '');

    document.getElementById('edit-recipe-id').value = existing ? existing.id : '';
    document.getElementById('recipe-input-name').value = existing ? existing.recipe_name : '';
    document.getElementById('recipe-input-count').value = existing ? existing.output_count : '1';
    document.getElementById('recipe-input-time').value = existing ? (existing.cooking_time / 1000) : '5';

    const ingsList = document.getElementById('recipe-ingredients-list');
    ingsList.innerHTML = '';

    if (existing && Array.isArray(existing.ingredients)) {
        existing.ingredients.forEach(i => addIngredientRow(i.item, i.count));
    } else {
        addIngredientRow();
    }

    modal.classList.remove('hidden');
    modal.style.display = 'flex';
}

document.getElementById('btn-add-ingredient')?.addEventListener('click', () => addIngredientRow());

function addIngredientRow(selectedItem = '', count = 1) {
    const list = document.getElementById('recipe-ingredients-list');
    if (!list) return;
    const row = document.createElement('div');
    row.className = 'ingredient-row';

    row.innerHTML = `
        <input type="text" class="ing-item-search" placeholder="Search item..." style="width: 145px;">
        <select class="custom-select ing-item-select" style="flex: 1;"></select>
        <input type="number" class="ing-count-input" value="${count}" min="1" max="20" style="width: 80px;">
        <button type="button" class="action-btn danger small btn-remove-ing"><i class="fa-solid fa-xmark"></i></button>
    `;

    const searchInput = row.querySelector('.ing-item-search');
    const itemSelect = row.querySelector('.ing-item-select');
    populateOxItemSelect(itemSelect, '', selectedItem);

    if (searchInput && itemSelect) {
        searchInput.addEventListener('input', (e) => {
            populateOxItemSelect(itemSelect, e.target.value, itemSelect.value);
        });
    }

    row.querySelector('.btn-remove-ing').addEventListener('click', () => row.remove());
    list.appendChild(row);
}

document.getElementById('btn-save-recipe').addEventListener('click', async () => {
    const saveBtn = document.getElementById('btn-save-recipe');
    if (saveBtn && saveBtn.disabled) return;

    const name = document.getElementById('recipe-input-name').value.trim();
    const station = document.getElementById('recipe-input-station').value;
    const output = document.getElementById('recipe-input-output').value;
    const outputCount = parseInt(document.getElementById('recipe-input-count').value) || 1;
    const prepSeconds = parseInt(document.getElementById('recipe-input-time').value) || 5;

    if (!name) {
        showToast('Please enter a recipe name!', 'warning');
        return;
    }
    if (!station) {
        showToast('Please select a Cooking Machine!', 'warning');
        return;
    }
    if (!output) {
        showToast('Please select a valid Output Item!', 'warning');
        return;
    }

    const ingredients = [];
    document.querySelectorAll('.ingredient-row').forEach(row => {
        const ing = row.querySelector('.ing-item-select')?.value;
        const cnt = parseInt(row.querySelector('.ing-count-input')?.value) || 1;
        if (ing) {
            ingredients.push({ item: ing, count: cnt });
        }
    });

    if (ingredients.length === 0) {
        showToast('Please add at least one ingredient!', 'warning');
        return;
    }

    if (saveBtn) saveBtn.disabled = true;
    try {
        const res = await postNUI('saveRecipe', {
            restaurantId: AppState.restaurantId,
            id: document.getElementById('edit-recipe-id').value || null,
            recipe_name: name,
            station_type: station,
            ingredients: ingredients,
            output_item: output,
            output_count: outputCount,
            cooking_time: prepSeconds * 1000,
            enabled: true
        });

        if (!res || res.ok !== true) {
            showToast((res && res.message) || 'Failed to save recipe!', 'danger');
            return;
        }

        if (Array.isArray(res.recipes)) {
            AppState.recipes = res.recipes;
        } else if (res.recipe && res.recipe.id) {
            const current = (Array.isArray(AppState.recipes) ? AppState.recipes : Object.values(AppState.recipes || {})).filter(r => r && Number(r.id) !== Number(res.recipe.id));
            current.push(res.recipe);
            AppState.recipes = current;
        }

        renderOwnerRecipesTable();
        renderStaffRecipes();
        closeRecipeModal();
        showToast('Recipe saved successfully!', 'success');
    } finally {
        if (saveBtn) saveBtn.disabled = false;
    }
});

// Audit Logs View
async function loadOwnerLogs() {
    const tbody = document.getElementById('logs-table-body');
    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-dim);">Loading logs...</td></tr>';

    const logs = await postNUI('getLogs', { restaurantId: AppState.restaurantId }) || [];
    tbody.innerHTML = '';

    if (logs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-dim);">No audit logs recorded yet.</td></tr>';
        return;
    }

    logs.forEach(l => {
        const tr = document.createElement('tr');
        const detailsStr = typeof l.details === 'object' ? JSON.stringify(l.details) : (l.details || '{}');

        tr.innerHTML = `
            <td style="color: var(--text-muted); font-size: 11.5px;">${l.created_at || 'Just now'}</td>
            <td><code>${l.citizenid}</code></td>
            <td>${l.player_name}</td>
            <td><span class="badge">${l.action}</span></td>
            <td style="max-width: 320px; font-size: 11.5px; color: var(--text-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${detailsStr}</td>
        `;
        tbody.appendChild(tr);
    });
}

document.getElementById('btn-refresh-logs').addEventListener('click', loadOwnerLogs);

// ====================================================================
// SUB-TAB: OWNER GIVE TABLET & ONLINE PLAYERS PROVISIONING
// ====================================================================
let cachedOnlinePlayersList = [];

async function populateOwnerGradeDropdown() {
    const select = document.getElementById('owner-grade-select');
    if (!select) return;
    const curVal = select.value;
    try {
        const roles = await postNUI('getRoles', { restaurantId: AppState.restaurantId }) || [];
        if (Array.isArray(roles) && roles.length > 0) {
            select.innerHTML = '';
            roles.forEach(r => {
                const opt = document.createElement('option');
                opt.value = r.grade;
                opt.textContent = `Grade ${r.grade} - ${r.role_name || 'Staff'}`;
                select.appendChild(opt);
            });
            if (curVal !== undefined && curVal !== null && curVal !== '') {
                select.value = curVal;
            }
            return;
        }
    } catch (err) {
        console.warn('Failed to load roles for owner-grade-select:', err);
    }
    if (select.children.length <= 1) {
        select.innerHTML = `
            <option value="0">Grade 0 - Trainee</option>
            <option value="1">Grade 1 - Cook</option>
            <option value="2">Grade 2 - Cashier</option>
            <option value="3">Grade 3 - Lead Cook</option>
            <option value="4">Grade 4 - Assistant Manager</option>
            <option value="8">Grade 8 - Store Manager</option>
        `;
    }
}

function renderOnlinePlayersTable(players, query = '') {
    const tbody = document.getElementById('owner-players-table-body');
    const countEl = document.getElementById('online-players-count');
    if (!tbody) return;

    let list = Array.isArray(players) ? players : [];
    const q = (query || '').toLowerCase().trim();
    if (q) {
        list = list.filter(p =>
            String(p.source || '').includes(q) ||
            String(p.name || '').toLowerCase().includes(q) ||
            String(p.citizenid || '').toLowerCase().includes(q) ||
            String(p.jobLabel || '').toLowerCase().includes(q)
        );
    }

    if (countEl) {
        countEl.textContent = `Online: ${list.length} / ${players.length} Players`;
    }

    tbody.innerHTML = '';
    if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-dim); padding: 18px;">No matching online players found.</td></tr>';
        return;
    }

    list.forEach(p => {
        const tr = document.createElement('tr');
        const isStaff = p.isStaff === true;
        const staffBadge = isStaff
            ? (p.onduty ? '<span class="stock-tag tag-in-stock">On Duty</span>' : '<span class="stock-tag tag-orange">Off Duty</span>')
            : '<span class="stock-tag tag-out-of-stock">Citizen / Other</span>';

        tr.innerHTML = `
            <td><strong style="color: var(--primary-light);">#${p.source}</strong></td>
            <td><strong>${escapeHtml(p.name)}</strong></td>
            <td><code>${escapeHtml(p.citizenid)}</code></td>
            <td>${escapeHtml(p.jobLabel)}</td>
            <td>${staffBadge}</td>
            <td>
                <div class="staff-row-actions">
                    <button class="btn-table-action btn-table-tab" data-source="${p.source}" title="Give Burgershot Tablet to ${escapeHtml(p.name)} (ID: ${p.source})">
                        <i class="fa-solid fa-tablet-screen-button"></i> Give Tab
                    </button>
                    <button class="btn-table-action btn-table-fill" data-source="${p.source}" data-grade="${isStaff ? p.grade : 0}" title="Select this player">
                        <i class="fa-solid fa-pen-to-square"></i> Select
                    </button>
                    ${isStaff ? `
                        <button class="btn-table-action btn-table-fire" data-source="${p.source}" data-name="${escapeHtml(p.name)}" title="Dismiss from Burgershot">
                            <i class="fa-solid fa-user-minus"></i> Fire
                        </button>
                    ` : ''}
                </div>
            </td>
        `;
        tbody.appendChild(tr);
    });

    // Row button event handlers
    tbody.querySelectorAll('.btn-table-tab').forEach(btn => {
        btn.addEventListener('click', async () => {
            const src = btn.getAttribute('data-source');
            if (!src) return;
            btn.disabled = true;
            try {
                const res = await postNUI('giveTablet', { restaurantId: AppState.restaurantId, targetId: Number(src) });
                if (res && res.ok) {
                    showToast(res.message || 'Burgershot Tablet issued!', 'success');
                } else {
                    showToast((res && res.message) || 'Failed to issue tablet.', 'error');
                }
            } finally {
                btn.disabled = false;
            }
        });
    });

    tbody.querySelectorAll('.btn-table-fill').forEach(btn => {
        btn.addEventListener('click', () => {
            const src = btn.getAttribute('data-source');
            const grade = btn.getAttribute('data-grade');
            const inputId = document.getElementById('owner-target-id');
            const selectGrade = document.getElementById('owner-grade-select');
            if (inputId && src) {
                inputId.value = src;
                inputId.focus();
            }
            if (selectGrade && grade !== null && grade !== undefined) {
                selectGrade.value = grade;
            }
            showToast(`Selected Player Server ID ${src}.`, 'info');
        });
    });

    tbody.querySelectorAll('.btn-table-fire').forEach(btn => {
        btn.addEventListener('click', async () => {
            const src = btn.getAttribute('data-source');
            const name = btn.getAttribute('data-name') || 'this player';
            if (!confirm(`Are you sure you want to dismiss ${name} (Server ID ${src}) from Burgershot?`)) return;
            btn.disabled = true;
            try {
                const res = await postNUI('fireStaff', { restaurantId: AppState.restaurantId, targetId: Number(src) });
                if (res && res.ok) {
                    showToast(res.message || 'Staff dismissed.', 'success');
                    loadOwnerGiveTablet();
                } else {
                    showToast((res && res.message) || 'Failed to dismiss staff.', 'error');
                }
            } finally {
                btn.disabled = false;
            }
        });
    });
}

async function loadOwnerGiveTablet() {
    populateOwnerGradeDropdown();
    const tbody = document.getElementById('owner-players-table-body');
    if (tbody) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-dim); padding: 18px;">Fetching active online players...</td></tr>';
    }

    try {
        const players = await postNUI('getOnlinePlayers', { restaurantId: AppState.restaurantId }) || [];
        cachedOnlinePlayersList = Array.isArray(players) ? players : [];
        const searchInput = document.getElementById('owner-players-search');
        renderOnlinePlayersTable(cachedOnlinePlayersList, searchInput ? searchInput.value : '');
    } catch (err) {
        console.error('Failed to load online players for tablet provisioning:', err);
        if (tbody) {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: #f87171;">Failed to load online players.</td></tr>';
        }
    }
}

// Live Search Filter for Online Players
const ownerPlayersSearch = document.getElementById('owner-players-search');
if (ownerPlayersSearch) {
    ownerPlayersSearch.addEventListener('input', (e) => {
        renderOnlinePlayersTable(cachedOnlinePlayersList, e.target.value);
    });
}

// Refresh Online Players Button
const btnRefreshOnlinePlayers = document.getElementById('btn-refresh-online-players');
if (btnRefreshOnlinePlayers) {
    btnRefreshOnlinePlayers.addEventListener('click', loadOwnerGiveTablet);
}

// Give Tablet to Myself Button
const btnOwnerGiveSelf = document.getElementById('btn-owner-give-self');
if (btnOwnerGiveSelf) {
    btnOwnerGiveSelf.addEventListener('click', async () => {
        btnOwnerGiveSelf.disabled = true;
        try {
            const res = await postNUI('giveTablet', { restaurantId: AppState.restaurantId, targetId: 0 });
            if (res && res.ok) {
                showToast(res.message || 'Burgershot tablet added to your inventory!', 'success');
            } else {
                showToast((res && res.message) || 'Failed to receive tablet.', 'error');
            }
        } finally {
            btnOwnerGiveSelf.disabled = false;
        }
    });
}

// Direct Give Tablet by ID in Owner Pane
const ownerBtnGiveTab = document.getElementById('owner-btn-give-tab');
if (ownerBtnGiveTab) {
    ownerBtnGiveTab.addEventListener('click', async () => {
        const inputId = document.getElementById('owner-target-id');
        const targetId = inputId ? Number(inputId.value) : 0;
        if (!targetId || targetId <= 0) {
            showToast('Please enter a valid Player Server ID to receive the tablet.', 'error');
            if (inputId) inputId.focus();
            return;
        }

        ownerBtnGiveTab.disabled = true;
        try {
            const res = await postNUI('giveTablet', { restaurantId: AppState.restaurantId, targetId: targetId });
            if (res && res.ok) {
                showToast(res.message || 'Burgershot tablet issued!', 'success');
            } else {
                showToast((res && res.message) || 'Failed to issue tablet.', 'error');
            }
        } finally {
            ownerBtnGiveTab.disabled = false;
        }
    });
}

// Direct Promote / Assign Role in Owner Pane
const ownerBtnPromote = document.getElementById('owner-btn-promote');
if (ownerBtnPromote) {
    ownerBtnPromote.addEventListener('click', async () => {
        const inputId = document.getElementById('owner-target-id');
        const selectGrade = document.getElementById('owner-grade-select');
        const targetId = inputId ? Number(inputId.value) : 0;
        const grade = selectGrade ? Number(selectGrade.value) : 0;

        if (!targetId || targetId <= 0) {
            showToast('Please enter a valid Player Server ID.', 'error');
            if (inputId) inputId.focus();
            return;
        }

        ownerBtnPromote.disabled = true;
        try {
            const res = await postNUI('promoteStaff', {
                restaurantId: AppState.restaurantId,
                targetId: targetId,
                grade: grade
            });
            if (res && res.ok) {
                showToast(res.message || 'Role assigned successfully!', 'success');
                if (inputId) inputId.value = '';
                loadOwnerGiveTablet();
            } else {
                showToast((res && res.message) || 'Failed to assign role.', 'error');
            }
        } finally {
            ownerBtnPromote.disabled = false;
        }
    });
}

// Direct Fire in Owner Pane
const ownerBtnFire = document.getElementById('owner-btn-fire');
if (ownerBtnFire) {
    ownerBtnFire.addEventListener('click', async () => {
        const inputId = document.getElementById('owner-target-id');
        const targetId = inputId ? Number(inputId.value) : 0;

        if (!targetId || targetId <= 0) {
            showToast('Please enter a valid Player Server ID to dismiss.', 'error');
            if (inputId) inputId.focus();
            return;
        }

        if (!confirm(`Are you sure you want to dismiss Server ID ${targetId} from Burgershot?`)) return;

        ownerBtnFire.disabled = true;
        try {
            const res = await postNUI('fireStaff', {
                restaurantId: AppState.restaurantId,
                targetId: targetId
            });
            if (res && res.ok) {
                showToast(res.message || 'Staff dismissed successfully.', 'success');
                if (inputId) inputId.value = '';
                loadOwnerGiveTablet();
            } else {
                showToast((res && res.message) || 'Failed to dismiss staff.', 'error');
            }
        } finally {
            ownerBtnFire.disabled = false;
        }
    });
}

// Realtime Stock & Price Sync Handlers
function handleSyncMenuState(restaurantId, itemName, state) {
    if (AppState.restaurantId !== restaurantId) return;
    const item = AppState.menu.find(m => (m.item === itemName || m.item_name === itemName));
    if (item) {
        item.in_stock = (state.in_stock === true || state.in_stock === 1);
        item.stock_count = state.stock_count;
        const custTab = document.getElementById('customer-tab');
        if (custTab && custTab.classList.contains('active')) {
            renderMenuGrid();
        }
    }
}

function handleSyncPrice(restaurantId, itemName, newPrice) {
    if (AppState.restaurantId !== restaurantId) return;
    const item = AppState.menu.find(m => (m.item === itemName || m.item_name === itemName));
    if (item) {
        item.price = newPrice;
        const custTab = document.getElementById('customer-tab');
        if (custTab && custTab.classList.contains('active')) {
            renderMenuGrid();
        }
    }
}

// ====================================================================
// OWNER TAX & FINANCIAL SETTINGS
// ====================================================================
function syncSalaryIntervalUI(minsOverride = null, enabledOverride = null) {
    const intervalInput = document.getElementById('owner-salary-interval');
    const scheduleCheckbox = document.getElementById('owner-salary-schedule-enabled');
    const mins = Math.max(1, Math.min(240, Math.floor(Number(minsOverride !== null ? minsOverride : (intervalInput ? intervalInput.value : 15)) || 15)));
    const enabled = enabledOverride !== null ? !!enabledOverride : (!scheduleCheckbox || scheduleCheckbox.checked);

    document.querySelectorAll('.salary-time-chip').forEach(chip => {
        const chipMins = parseInt(chip.getAttribute('data-mins'), 10);
        chip.classList.toggle('active', chipMins === mins);
    });

    const badge = document.getElementById('salary-roles-interval-badge');
    if (badge) {
        badge.textContent = enabled ? `Every ${mins}m` : 'Timer Disabled';
    }
}

function syncSalaryControlsFromSettings(settings = {}) {
    const salaryInput = document.getElementById('owner-salary-input');
    const salarySelect = document.getElementById('owner-salary-account');
    const intervalInput = document.getElementById('owner-salary-interval');
    const scheduleCheckbox = document.getElementById('owner-salary-schedule-enabled');
    const dutyCheckbox = document.getElementById('owner-salary-onduty-only');

    const salaryPercent = Number(settings.salary_percent !== undefined ? settings.salary_percent : 10);
    const salaryAccount = (settings.salary_account === 'cash') ? 'cash' : 'bank';
    const intervalMinutes = Math.max(1, Math.min(240, Math.floor(Number(settings.salary_interval_minutes !== undefined ? settings.salary_interval_minutes : 15) || 15)));
    const scheduleEnabled = settings.salary_schedule_enabled !== undefined ? (settings.salary_schedule_enabled === true || settings.salary_schedule_enabled === 1 || settings.salary_schedule_enabled === '1') : true;
    const onDutyOnly = settings.salary_on_duty_only !== undefined ? (settings.salary_on_duty_only === true || settings.salary_on_duty_only === 1 || settings.salary_on_duty_only === '1') : true;

    if (salaryInput) salaryInput.value = salaryPercent;
    if (salarySelect) salarySelect.value = salaryAccount;
    if (intervalInput) intervalInput.value = intervalMinutes;
    if (scheduleCheckbox) scheduleCheckbox.checked = scheduleEnabled;
    if (dutyCheckbox) dutyCheckbox.checked = onDutyOnly;

    updateSalaryPreview(salaryPercent);
    syncSalaryIntervalUI(intervalMinutes, scheduleEnabled);
}

function initOwnerSettings() {
    const taxInput = document.getElementById('owner-tax-input');
    const taxRate = Number(AppState.settings && AppState.settings.tax_rate !== undefined ? AppState.settings.tax_rate : 10);
    if (taxInput) {
        taxInput.value = taxRate;
    }
    updateTaxPreview(taxRate);
    syncSalaryControlsFromSettings(AppState.settings || {});
}

function updateTaxPreview(rate) {
    const r = Math.max(0, Math.min(50, Number(rate) || 0));
    const sampleSubtotal = 50;
    const calcTax = Math.round((sampleSubtotal * r) / 100);
    const calcTotal = sampleSubtotal + calcTax;

    const pRate = document.getElementById('tax-preview-percent');
    const pTax = document.getElementById('tax-preview-amount');
    const pTotal = document.getElementById('tax-preview-total');

    if (pRate) pRate.textContent = r;
    if (pTax) pTax.textContent = `$${calcTax}.00`;
    if (pTotal) pTotal.textContent = `$${calcTotal}.00`;
}

function updateSalaryPreview(percent) {
    const p = Math.max(0, Math.min(100, Math.floor(Number(percent) || 0)));
    const sampleOrder = 100;
    const staffPay = Math.round((sampleOrder * p) / 100);
    const restNet = sampleOrder - staffPay;

    const pPct = document.getElementById('salary-preview-percent');
    const pAmt = document.getElementById('salary-preview-amount');
    const pNet = document.getElementById('salary-preview-net');

    if (pPct) pPct.textContent = p;
    if (pAmt) pAmt.textContent = `$${staffPay}.00`;
    if (pNet) pNet.textContent = `$${restNet}.00`;
}

// Tax input live change
const ownerTaxInput = document.getElementById('owner-tax-input');
if (ownerTaxInput) {
    ownerTaxInput.addEventListener('input', (e) => {
        updateTaxPreview(e.target.value);
    });
}

// Salary input & interval live updates
const ownerSalaryInput = document.getElementById('owner-salary-input');
if (ownerSalaryInput) {
    ownerSalaryInput.addEventListener('input', (e) => {
        updateSalaryPreview(e.target.value);
    });
}

const ownerSalaryInterval = document.getElementById('owner-salary-interval');
if (ownerSalaryInterval) {
    ownerSalaryInterval.addEventListener('input', () => syncSalaryIntervalUI());
}

const ownerScheduleToggle = document.getElementById('owner-salary-schedule-enabled');
if (ownerScheduleToggle) {
    ownerScheduleToggle.addEventListener('change', () => syncSalaryIntervalUI());
}

document.querySelectorAll('.salary-time-chip').forEach(chip => {
    chip.addEventListener('click', () => {
        const mins = parseInt(chip.getAttribute('data-mins'), 10) || 15;
        const intervalInput = document.getElementById('owner-salary-interval');
        if (intervalInput) intervalInput.value = mins;
        syncSalaryIntervalUI(mins);
    });
});

// Save Tax Rate Button Handler
const btnSaveTax = document.getElementById('btn-save-tax');
if (btnSaveTax) {
    btnSaveTax.addEventListener('click', () => {
        const input = document.getElementById('owner-tax-input');
        const rate = Math.max(0, Math.min(50, parseInt(input.value) || 0));

        AppState.settings = AppState.settings || {};
        AppState.settings.tax_rate = rate;

        postNUI('saveTaxRate', {
            restaurantId: AppState.restaurantId,
            taxRate: rate
        });

        updateTaxPreview(rate);
        showToast(`Sales Tax Rate saved at ${rate}%!`, 'success');
    });
}

// Persist all Salary tab settings (commission, schedule, and per-role base pay) together
async function persistAllSalaryConfigs(silent = false) {
    const input = document.getElementById('owner-salary-input');
    const select = document.getElementById('owner-salary-account');
    const intervalInput = document.getElementById('owner-salary-interval');
    const scheduleCheckbox = document.getElementById('owner-salary-schedule-enabled');
    const dutyCheckbox = document.getElementById('owner-salary-onduty-only');

    const percent = Math.max(0, Math.min(100, Math.floor(Number(input ? input.value : 10) || 0)));
    const account = (select && select.value === 'cash') ? 'cash' : 'bank';
    const intervalMinutes = Math.max(1, Math.min(240, Math.floor(Number(intervalInput ? intervalInput.value : 15) || 15)));
    const scheduleEnabled = !scheduleCheckbox || scheduleCheckbox.checked;
    const onDutyOnly = !dutyCheckbox || dutyCheckbox.checked;

    if (input) input.value = percent;
    if (intervalInput) intervalInput.value = intervalMinutes;

    AppState.settings = Object.assign(AppState.settings || {}, {
        salary_percent: percent,
        salary_account: account,
        salary_interval_minutes: intervalMinutes,
        salary_schedule_enabled: scheduleEnabled,
        salary_on_duty_only: onDutyOnly
    });

    const requests = [
        postNUI('saveSalarySettings', {
            restaurantId: AppState.restaurantId,
            salaryPercent: percent,
            salaryAccount: account,
            salaryScheduleEnabled: scheduleEnabled,
            salaryIntervalMinutes: intervalMinutes,
            salaryOnDutyOnly: onDutyOnly
        })
    ];

    const listEl = document.getElementById('salary-roles-list');
    if (listEl) {
        const salaries = [];
        listEl.querySelectorAll('.salary-role-input').forEach(roleInput => {
            const grade = parseInt(roleInput.getAttribute('data-grade'), 10);
            const cleanAmount = Math.max(0, Math.min(1000000, Math.floor(Number(roleInput.value) || 0)));
            roleInput.value = cleanAmount;
            if (!Number.isNaN(grade)) {
                salaries.push({ grade, salary: cleanAmount });
            }
        });
        requests.push(postNUI('saveRoleSalaries', {
            restaurantId: AppState.restaurantId,
            salaries
        }));
    }

    await Promise.all(requests);
    updateSalaryPreview(percent);
    syncSalaryIntervalUI(intervalMinutes, scheduleEnabled);

    if (!silent) {
        showToast(`Salary settings saved (${percent}%, ${scheduleEnabled ? `every ${intervalMinutes}m` : 'Timer Off'})!`, 'success');
    }
}

// Save Staff Order Salary Commission & Paycheck Schedule Button Handler
const btnSaveSalary = document.getElementById('btn-save-salary');
if (btnSaveSalary) {
    btnSaveSalary.addEventListener('click', () => {
        persistAllSalaryConfigs(false);
    });
}

// Save Per-Role Base Salaries Button Handler (persists full salary config)
const btnSaveRoleSalaries = document.getElementById('btn-save-role-salaries');
if (btnSaveRoleSalaries) {
    btnSaveRoleSalaries.addEventListener('click', () => {
        persistAllSalaryConfigs(false);
    });
}

// Pay Eligible Staff Immediately Button Handler
const btnPaySalariesNow = document.getElementById('btn-pay-salaries-now');
if (btnPaySalariesNow) {
    btnPaySalariesNow.addEventListener('click', async () => {
        if (btnPaySalariesNow.disabled) return;
        btnPaySalariesNow.disabled = true;
        try {
            await persistAllSalaryConfigs(true);
            const result = await postNUI('triggerSalaryPayout', {
                restaurantId: AppState.restaurantId
            });
            if (result && result.ok) {
                const paidCount = Number(result.paidCount) || 0;
                const totalPaid = Number(result.totalPaid) || 0;
                const msg = result.message || (paidCount > 0
                    ? `Paid $${totalPaid.toLocaleString()} across ${paidCount} staff.`
                    : 'No eligible staff to pay right now.');
                showToast(msg, paidCount > 0 ? 'success' : 'info');
            } else {
                showToast((result && result.message) ? result.message : 'Failed to trigger salary payout.', 'error');
            }
        } finally {
            btnPaySalariesNow.disabled = false;
        }
    });
}

function handleSyncSettings(restaurantId, settings) {
    if (AppState.restaurantId !== restaurantId || !settings) return;
    AppState.settings = Object.assign(AppState.settings || {}, settings);

    if (settings.tax_rate !== undefined) {
        const taxInput = document.getElementById('owner-tax-input');
        if (taxInput) taxInput.value = settings.tax_rate;
        updateTaxPreview(settings.tax_rate);

        const custTab = document.getElementById('customer-tab');
        if (custTab && custTab.classList.contains('active')) {
            renderCart();
        }
    }

    if (
        settings.salary_percent !== undefined ||
        settings.salary_account !== undefined ||
        settings.salary_interval_minutes !== undefined ||
        settings.salary_schedule_enabled !== undefined ||
        settings.salary_on_duty_only !== undefined
    ) {
        syncSalaryControlsFromSettings(AppState.settings);
    }
}

// ====================================================================
// STATION COOKING & BATCH PROCESSING CONTROLLER
// ====================================================================

const StationCookingState = {
    restaurantId: null,
    stationId: null,
    stationType: null,
    stationLabel: '',
    isOwner: false,
    recipes: [],
    inventoryCounts: {},
    itemDetails: {},
    selectedRecipe: null,
    batchAmount: 1
};

function getStationItemLabel(itemName) {
    if (!itemName) return 'Item';
    const stationLabel = StationCookingState.itemDetails && StationCookingState.itemDetails[itemName]
        ? StationCookingState.itemDetails[itemName].label
        : null;
    if (stationLabel && stationLabel !== itemName) {
        return stationLabel;
    }
    if (Array.isArray(AppState.oxItems) && AppState.oxItems.length > 0) {
        const match = AppState.oxItems.find(i => i && i.name === itemName);
        if (match && match.label && match.label !== itemName) {
            return match.label;
        }
    }
    return String(itemName)
        .replace(/^bs_/, '')
        .split('_')
        .filter(Boolean)
        .map(w => w.charAt(0).toUpperCase() + w.slice(1))
        .join(' ');
}

function initStationCookingView(data) {
    StationCookingState.restaurantId = data.restaurantId || 'burgershot';
    StationCookingState.stationId = data.stationId;
    StationCookingState.stationType = data.stationType || 'assembly';
    StationCookingState.stationLabel = data.stationLabel || 'Cooking Station';
    StationCookingState.isOwner = !!data.isOwner;
    StationCookingState.recipes = data.recipes || [];
    StationCookingState.inventoryCounts = data.inventoryCounts || {};
    StationCookingState.itemDetails = data.itemDetails || {};
    StationCookingState.selectedRecipe = null;
    StationCookingState.batchAmount = 1;

    // Header info
    const titleEl = document.getElementById('station-ui-title');
    if (titleEl) titleEl.textContent = data.stationLabel || 'Cooking Station';

    const typeEl = document.getElementById('station-ui-type');
    if (typeEl) typeEl.textContent = (data.stationType || 'station').toUpperCase();

    const iconBadge = document.getElementById('station-icon-badge');
    if (iconBadge) {
        let iconClass = 'fa-solid fa-fire-burner';
        const st = (data.stationType || '').toLowerCase();
        if (st.includes('assembly') || st.includes('board')) iconClass = 'fa-solid fa-layer-group';
        else if (st.includes('grill')) iconClass = 'fa-solid fa-fire-burner';
        else if (st.includes('fry')) iconClass = 'fa-solid fa-bowl-food';
        else if (st.includes('drink') || st.includes('bar')) iconClass = 'fa-solid fa-wine-glass';
        else if (st.includes('coffee')) iconClass = 'fa-solid fa-mug-hot';
        iconBadge.innerHTML = `<i class="${iconClass}"></i>`;
    }

    // Hide tablet window and show station cooking view
    const windowContainer = document.getElementById('main-window') || document.querySelector('.window-container');
    if (windowContainer) {
        windowContainer.classList.add('hidden');
        windowContainer.style.display = 'none';
    }

    const stationView = document.getElementById('station-cooking-view');
    if (stationView) {
        stationView.classList.remove('hidden');
        stationView.style.display = 'flex';
    }

    const recipeModal = document.getElementById('recipe-modal');
    if (recipeModal) {
        recipeModal.classList.add('hidden');
        recipeModal.style.display = 'none';
    }

    const appEl = document.getElementById('app');
    if (appEl) {
        appEl.classList.remove('hidden');
        appEl.style.display = 'flex';
    }

    // Reset search
    const searchInput = document.getElementById('station-recipe-search');
    if (searchInput) searchInput.value = '';

    // Render recipes
    renderStationRecipesList();

    // Auto-select first recipe if available
    if (StationCookingState.recipes.length > 0) {
        selectStationRecipe(StationCookingState.recipes[0]);
    } else {
        const emptyState = document.getElementById('station-empty-state');
        const panel = document.getElementById('station-recipe-panel');
        if (emptyState) emptyState.classList.remove('hidden');
        if (panel) panel.classList.add('hidden');
    }
}

function calculateRecipeMaxCraftable(recipe) {
    if (!recipe || !Array.isArray(recipe.ingredients) || recipe.ingredients.length === 0) return 20;
    let maxAmounts = [];
    for (const ing of recipe.ingredients) {
        const bagCount = StationCookingState.inventoryCounts[ing.item] || 0;
        const requiredPerUnit = ing.count || 1;
        const possible = Math.floor(bagCount / requiredPerUnit);
        maxAmounts.push(possible);
    }
    return Math.max(0, Math.min(20, Math.min(...maxAmounts)));
}

function renderStationRecipesList(query = '') {
    const listEl = document.getElementById('station-recipes-list');
    const countBadge = document.getElementById('station-recipe-count');
    if (!listEl) return;
    listEl.innerHTML = '';

    const lowerQuery = query.toLowerCase().trim();
    const filtered = StationCookingState.recipes.filter(rec => {
        if (!lowerQuery) return true;
        const nameMatch = (rec.recipe_name || '').toLowerCase().includes(lowerQuery);
        const outMatch = (rec.output_item || '').toLowerCase().includes(lowerQuery);
        return nameMatch || outMatch;
    });

    if (countBadge) countBadge.textContent = filtered.length;

    if (filtered.length === 0) {
        listEl.innerHTML = `
            <div class="empty-list-notice">
                <i class="fa-solid fa-circle-question"></i>
                <p>No recipes found matching your filter.</p>
            </div>
        `;
        return;
    }

    filtered.forEach(rec => {
        const maxCanCook = calculateRecipeMaxCraftable(rec);
        const isSelected = StationCookingState.selectedRecipe && StationCookingState.selectedRecipe.id === rec.id;
        
        let ingredientsText = 'None';
        if (Array.isArray(rec.ingredients) && rec.ingredients.length > 0) {
            ingredientsText = rec.ingredients.map(ing => `${ing.count || 1}x ${getStationItemLabel(ing.item)}`).join(', ');
        }

        const card = document.createElement('div');
        card.className = `station-recipe-card ${isSelected ? 'active' : ''} ${maxCanCook > 0 ? 'craftable' : 'uncraftable'}`;
        card.innerHTML = `
            <div class="card-icon">
                <img src="nui://ox_inventory/web/images/${rec.output_item}.png" 
                     onerror="handleImgFallback(this, '${rec.output_item}')" 
                     alt="${rec.recipe_name}">
            </div>
            <div class="card-details">
                <div class="card-title-row">
                    <span class="recipe-name">${rec.recipe_name}</span>
                    ${maxCanCook > 0 
                        ? `<span class="status-pill in-stock"><i class="fa-solid fa-check"></i> Can make ${maxCanCook}x</span>` 
                        : `<span class="status-pill out-of-stock"><i class="fa-solid fa-xmark"></i> Missing items</span>`}
                </div>
                <div class="card-ingredients-preview">${ingredientsText}</div>
            </div>
        `;

        card.addEventListener('click', () => {
            selectStationRecipe(rec);
        });

        listEl.appendChild(card);
    });
}

function selectStationRecipe(recipe) {
    StationCookingState.selectedRecipe = recipe;
    StationCookingState.batchAmount = 1;

    // Update active highlight in sidebar
    document.querySelectorAll('.station-recipe-card').forEach(c => c.classList.remove('active'));
    renderStationRecipesList(document.getElementById('station-recipe-search') ? document.getElementById('station-recipe-search').value : '');

    const emptyState = document.getElementById('station-empty-state');
    const panel = document.getElementById('station-recipe-panel');
    if (emptyState) emptyState.classList.add('hidden');
    if (panel) panel.classList.remove('hidden');

    updateStationRecipeDetails();
}

function updateStationRecipeDetails() {
    const rec = StationCookingState.selectedRecipe;
    if (!rec) return;

    const amount = Math.max(1, Math.min(20, StationCookingState.batchAmount));
    StationCookingState.batchAmount = amount;

    // 1. Hero Card
    const heroTitle = document.getElementById('dish-hero-title');
    if (heroTitle) heroTitle.textContent = rec.recipe_name;

    const heroIcon = document.getElementById('dish-hero-icon');
    if (heroIcon) {
        heroIcon.innerHTML = `
            <img src="nui://ox_inventory/web/images/${rec.output_item}.png" 
                 onerror="handleImgFallback(this, '${rec.output_item}')" 
                 alt="${rec.recipe_name}">
        `;
    }

    const baseTime = (rec.cooking_time ? Math.round(rec.cooking_time / 1000) : 5);
    const dishBaseTime = document.getElementById('dish-base-time');
    if (dishBaseTime) dishBaseTime.textContent = `${baseTime}s`;

    const baseYield = (rec.output_count || 1);
    const dishBaseYield = document.getElementById('dish-base-yield');
    if (dishBaseYield) dishBaseYield.textContent = `${baseYield}x ${getStationItemLabel(rec.output_item)}`;

    // 2. Batch Quantity Controls & Max Calculation
    const maxCraftable = calculateRecipeMaxCraftable(rec);
    const maxValSpan = document.getElementById('batch-max-val');
    if (maxValSpan) maxValSpan.textContent = maxCraftable;

    const batchInput = document.getElementById('batch-amount-input');
    if (batchInput) batchInput.value = amount;

    // Update preset pills active state
    document.querySelectorAll('.preset-pill').forEach(pill => {
        const pAmt = parseInt(pill.getAttribute('data-amount'));
        if (pAmt === amount) {
            pill.classList.add('active');
        } else {
            pill.classList.remove('active');
        }
    });

    // 3. Dynamic Ingredients Checklist Grid
    const grid = document.getElementById('station-ingredients-grid');
    if (grid) grid.innerHTML = '';

    let hasAllIngredients = true;
    if (Array.isArray(rec.ingredients) && rec.ingredients.length > 0) {
        rec.ingredients.forEach(ing => {
            const reqTotal = (ing.count || 1) * amount;
            const inBag = StationCookingState.inventoryCounts[ing.item] || 0;
            const sufficient = inBag >= reqTotal;
            if (!sufficient) hasAllIngredients = false;

            const percent = Math.min(100, Math.round((inBag / reqTotal) * 100));

            const ingCard = document.createElement('div');
            ingCard.className = `ingredient-check-item ${sufficient ? 'sufficient' : 'insufficient'}`;
            ingCard.innerHTML = `
                <div class="ing-img-box">
                    <img src="nui://ox_inventory/web/images/${ing.item}.png" 
                         onerror="handleImgFallback(this, '${ing.item}')" 
                         alt="${getStationItemLabel(ing.item)}">
                </div>
                <div class="ing-details">
                    <div class="ing-header">
                        <span class="ing-name" title="${getStationItemLabel(ing.item)}">${getStationItemLabel(ing.item)}</span>
                        <span class="ing-ratio"><strong>${inBag}</strong> / ${reqTotal}</span>
                    </div>
                    <div class="ing-bar-track">
                        <div class="ing-bar-fill ${sufficient ? 'fill-good' : 'fill-bad'}" style="width: ${percent}%;"></div>
                    </div>
                    <div class="ing-status-tag">
                        ${sufficient 
                            ? `<i class="fa-solid fa-circle-check"></i> In Inventory (${inBag} available)` 
                            : `<i class="fa-solid fa-circle-xmark"></i> Need ${reqTotal - inBag} more`}
                    </div>
                </div>
            `;
            grid.appendChild(ingCard);
        });
    }

    // 4. Overall Status & Craftable Tag
    const overallStatus = document.getElementById('ingredients-overall-status');
    const craftableTag = document.getElementById('dish-craftable-tag');
    if (hasAllIngredients) {
        if (overallStatus) {
            overallStatus.textContent = 'Ready to Cook';
            overallStatus.className = 'inventory-check-status success';
        }
        if (craftableTag) {
            craftableTag.innerHTML = '<i class="fa-solid fa-check"></i> Ready to Cook';
            craftableTag.className = 'dish-tag success-tag';
        }
    } else {
        if (overallStatus) {
            overallStatus.textContent = 'Missing Ingredients';
            overallStatus.className = 'inventory-check-status danger';
        }
        if (craftableTag) {
            craftableTag.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Missing Items';
            craftableTag.className = 'dish-tag danger-tag';
        }
    }

    // 5. Total Output & Duration Calculation
    const totalOutputCount = (rec.output_count || 1) * amount;
    const summaryOutput = document.getElementById('summary-total-output');
    if (summaryOutput) summaryOutput.textContent = `${totalOutputCount}x ${getStationItemLabel(rec.output_item)}`;

    const scaledSeconds = Math.round(baseTime * (1 + Math.min(2.5, (amount - 1) * 0.3)));
    const summaryTime = document.getElementById('summary-total-time');
    if (summaryTime) summaryTime.textContent = `${scaledSeconds} seconds`;

    // 6. Action Button & Error Notice
    const cookBtn = document.getElementById('btn-station-cook-now');
    const cookLabel = document.getElementById('btn-cook-label');
    const errorNotice = document.getElementById('cook-error-notice');
    const errorText = document.getElementById('cook-error-text');

    if (cookLabel) cookLabel.textContent = `Start Cooking (${amount}x)`;

    if (hasAllIngredients) {
        if (cookBtn) {
            cookBtn.disabled = false;
            cookBtn.classList.remove('disabled');
        }
        if (errorNotice) errorNotice.classList.add('hidden');
    } else {
        if (cookBtn) {
            cookBtn.disabled = true;
            cookBtn.classList.add('disabled');
        }
        if (errorNotice) {
            errorNotice.classList.remove('hidden');
            if (errorText) {
                errorText.textContent = maxCraftable > 0 
                    ? `You only have enough ingredients for ${maxCraftable}x. Reduce quantity or gather ingredients.`
                    : 'You do not have enough ingredients to prepare this dish.';
            }
        }
    }
}

function initStationCookingEventHandlers() {
    // Close / Cancel
    const closeBtn = document.getElementById('btn-close-station-view');
    if (closeBtn) closeBtn.addEventListener('click', closeApp);

    const cancelBtn = document.getElementById('btn-station-cancel');
    if (cancelBtn) cancelBtn.addEventListener('click', closeApp);

    // Search filter
    const searchInput = document.getElementById('station-recipe-search');
    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            renderStationRecipesList(e.target.value);
        });
    }

    // Stepper buttons
    const btnDec = document.getElementById('btn-batch-dec');
    if (btnDec) {
        btnDec.addEventListener('click', () => {
            if (StationCookingState.batchAmount > 1) {
                StationCookingState.batchAmount--;
                updateStationRecipeDetails();
            }
        });
    }

    const btnInc = document.getElementById('btn-batch-inc');
    if (btnInc) {
        btnInc.addEventListener('click', () => {
            if (StationCookingState.batchAmount < 20) {
                StationCookingState.batchAmount++;
                updateStationRecipeDetails();
            }
        });
    }

    const batchInput = document.getElementById('batch-amount-input');
    if (batchInput) {
        batchInput.addEventListener('change', (e) => {
            const val = parseInt(e.target.value) || 1;
            StationCookingState.batchAmount = Math.max(1, Math.min(20, val));
            updateStationRecipeDetails();
        });
    }

    // Preset pills (1x, 2x, 3x, 5x, 10x)
    document.querySelectorAll('.preset-pill:not(.max-pill)').forEach(pill => {
        pill.addEventListener('click', () => {
            const amt = parseInt(pill.getAttribute('data-amount')) || 1;
            StationCookingState.batchAmount = amt;
            updateStationRecipeDetails();
        });
    });

    // Max pill
    const maxPill = document.getElementById('btn-batch-max');
    if (maxPill) {
        maxPill.addEventListener('click', () => {
            if (!StationCookingState.selectedRecipe) return;
            const max = calculateRecipeMaxCraftable(StationCookingState.selectedRecipe);
            StationCookingState.batchAmount = Math.max(1, max);
            updateStationRecipeDetails();
            if (max === 0) {
                showToast('You do not have enough ingredients for any craft!', 'danger');
            } else {
                showToast(`Set to maximum possible batch (${max}x)`, 'info');
            }
        });
    }

    // Start Cooking Button
    const cookNowBtn = document.getElementById('btn-station-cook-now');
    if (cookNowBtn) {
        cookNowBtn.addEventListener('click', () => {
            if (!StationCookingState.selectedRecipe) return;
            const max = calculateRecipeMaxCraftable(StationCookingState.selectedRecipe);
            if (StationCookingState.batchAmount > max) {
                showToast('Missing required ingredients for this batch amount!', 'danger');
                return;
            }

            postNUI('startCooking', {
                restaurantId: StationCookingState.restaurantId,
                stationId: StationCookingState.stationId,
                recipeId: StationCookingState.selectedRecipe.id,
                amount: StationCookingState.batchAmount
            });
        });
    }
}

// Initialize station cooking handlers on load
document.addEventListener('DOMContentLoaded', () => {
    initStationCookingEventHandlers();
    initUiSettingsHandlers();
});
// Also invoke immediately in case DOMContentLoaded already fired
initStationCookingEventHandlers();

// ====================================================================
// UNIVERSAL DISPLAY SETTINGS (COLORS & UI SCALE FOR ALL USERS)
// ====================================================================
const UI_PREFS_STORAGE_KEY = 'burgershot_tablet_ui_prefs_v1';
const DEFAULT_UI_PREFS = Object.freeze({
    scale: 1,
    accent: '#e08e0b',
    chassis: '#232833',
    screen: '#141923'
});

let uiSettingsBound = false;

/** Normalize a CSS hex color string to #RRGGBB format. */
function normalizeHexColor(value, fallback) {
    if (typeof value !== 'string') return fallback;
    let hex = value.trim();
    if (!hex.startsWith('#')) hex = `#${hex}`;
    if (/^#[0-9a-fA-F]{3}$/.test(hex)) {
        hex = `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`;
    }
    return /^#[0-9a-fA-F]{6}$/.test(hex) ? hex.toLowerCase() : fallback;
}

/** Parse #RRGGBB into RGB integer components. */
function hexToRgb(hex) {
    const clean = normalizeHexColor(hex, '#000000').slice(1);
    return {
        r: parseInt(clean.slice(0, 2), 16),
        g: parseInt(clean.slice(2, 4), 16),
        b: parseInt(clean.slice(4, 6), 16)
    };
}

/** Blend two hex colors linearly where weight is in [0, 1] toward hexB. */
function mixHexColors(hexA, hexB, weight) {
    const a = hexToRgb(hexA);
    const b = hexToRgb(hexB);
    const t = Math.max(0, Math.min(1, weight));
    const toHex = (n) => Math.round(n).toString(16).padStart(2, '0');
    return `#${toHex(a.r + (b.r - a.r) * t)}${toHex(a.g + (b.g - a.g) * t)}${toHex(a.b + (b.b - a.b) * t)}`;
}

/** Format a hex color and opacity as rgba(). */
function hexToRgba(hex, alpha) {
    const { r, g, b } = hexToRgb(hex);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/** Compute relative luminance (0..1) for contrast adaptation. */
function getColorLuminance(hex) {
    const { r, g, b } = hexToRgb(hex);
    const channel = (c) => {
        const v = c / 255;
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/** Clamp and validate user display preference object. */
function sanitizeUiPrefs(raw = {}) {
    const scaleNum = parseFloat(raw.scale);
    const scale = Number.isFinite(scaleNum) ? Math.max(0.65, Math.min(1.25, Math.round(scaleNum * 100) / 100)) : DEFAULT_UI_PREFS.scale;
    return {
        scale,
        accent: normalizeHexColor(raw.accent, DEFAULT_UI_PREFS.accent),
        chassis: normalizeHexColor(raw.chassis, DEFAULT_UI_PREFS.chassis),
        screen: normalizeHexColor(raw.screen, DEFAULT_UI_PREFS.screen)
    };
}

/** Load persisted UI preferences from localStorage safely. */
function loadUiPrefs() {
    try {
        const stored = window.localStorage.getItem(UI_PREFS_STORAGE_KEY);
        if (!stored) return { ...DEFAULT_UI_PREFS };
        return sanitizeUiPrefs(JSON.parse(stored));
    } catch (_) {
        return { ...DEFAULT_UI_PREFS };
    }
}

/** Persist UI preferences to localStorage safely. */
function saveUiPrefs(prefs) {
    try {
        window.localStorage.setItem(UI_PREFS_STORAGE_KEY, JSON.stringify(prefs));
    } catch (_) {
        // Ignore storage errors in restricted contexts
    }
}

/** Apply color palette and UI scale CSS custom properties on :root. */
function applyUiPrefs(rawPrefs) {
    const prefs = sanitizeUiPrefs(rawPrefs);
    const root = document.documentElement.style;
    const isLightScreen = getColorLuminance(prefs.screen) > 0.42;
    const accentLum = getColorLuminance(prefs.accent);

    const primaryLight = (isLightScreen && accentLum > 0.52)
        ? mixHexColors(prefs.accent, '#000000', 0.28)
        : mixHexColors(prefs.accent, '#ffffff', 0.16);
    const primaryDark = mixHexColors(prefs.accent, '#000000', 0.24);
    const primaryOn = accentLum > 0.34 ? '#0e1117' : '#ffffff';

    const vars = {
        '--ui-scale': String(prefs.scale),
        '--primary': prefs.accent,
        '--primary-light': primaryLight,
        '--primary-dark': primaryDark,
        '--primary-on': primaryOn,
        '--border-color-focus': primaryDark,
        '--primary-alpha-12': hexToRgba(prefs.accent, 0.12),
        '--primary-alpha-16': hexToRgba(prefs.accent, 0.16),
        '--primary-alpha-24': hexToRgba(prefs.accent, 0.24),
        '--primary-alpha-32': hexToRgba(prefs.accent, 0.32),
        '--primary-alpha-38': hexToRgba(prefs.accent, 0.38),
        '--primary-alpha-45': hexToRgba(prefs.accent, 0.45),
        '--primary-alpha-75': hexToRgba(prefs.accent, 0.75),

        '--chassis-top': mixHexColors(prefs.chassis, '#ffffff', 0.14),
        '--chassis-mid': prefs.chassis,
        '--chassis-deep': mixHexColors(prefs.chassis, '#000000', 0.28),
        '--chassis-bottom': mixHexColors(prefs.chassis, '#000000', 0.14),
        '--chassis-border': mixHexColors(prefs.chassis, '#ffffff', 0.28),
        '--chassis-border-dark': mixHexColors(prefs.chassis, '#000000', 0.45),
        '--chassis-border-right': mixHexColors(prefs.chassis, '#000000', 0.18),

        '--screen-top': isLightScreen ? prefs.screen : mixHexColors(prefs.screen, '#000000', 0.05),
        '--screen-bottom': isLightScreen ? mixHexColors(prefs.screen, '#cbd5e1', 0.22) : mixHexColors(prefs.screen, '#000000', 0.28),
        '--header-top': isLightScreen ? mixHexColors(prefs.screen, '#ffffff', 0.65) : mixHexColors(prefs.screen, '#ffffff', 0.06),
        '--header-bottom': isLightScreen ? mixHexColors(prefs.screen, '#cbd5e1', 0.15) : prefs.screen,
        '--nav-well': isLightScreen ? mixHexColors(prefs.screen, '#94a3b8', 0.24) : mixHexColors(prefs.screen, '#000000', 0.38),
        '--bg-surface': isLightScreen ? mixHexColors(prefs.screen, '#ffffff', 0.55) : prefs.screen,
        '--bg-card': isLightScreen ? mixHexColors(prefs.screen, '#ffffff', 0.72) : mixHexColors(prefs.screen, '#ffffff', 0.05),
        '--bg-card-top': isLightScreen ? '#ffffff' : mixHexColors(prefs.screen, '#ffffff', 0.09),
        '--bg-card-bottom': isLightScreen ? mixHexColors(prefs.screen, '#ffffff', 0.45) : mixHexColors(prefs.screen, '#ffffff', 0.03),
        '--bg-card-hover': isLightScreen ? mixHexColors(prefs.screen, '#ffffff', 0.92) : mixHexColors(prefs.screen, '#ffffff', 0.13),
        '--bg-well': isLightScreen ? 'rgba(15, 23, 42, 0.06)' : 'rgba(0, 0, 0, 0.3)',
        '--modal-top': isLightScreen ? '#ffffff' : mixHexColors(prefs.screen, '#ffffff', 0.09),
        '--modal-bottom': isLightScreen ? mixHexColors(prefs.screen, '#cbd5e1', 0.2) : mixHexColors(prefs.screen, '#000000', 0.12),
        '--text-main': isLightScreen ? '#0f172a' : '#f1f5f9',
        '--text-muted': isLightScreen ? '#475569' : '#94a3b8',
        '--text-dim': '#64748b',
        '--border-color': isLightScreen ? 'rgba(15, 23, 42, 0.12)' : 'rgba(255, 255, 255, 0.08)',
        '--border-top-highlight': isLightScreen ? 'rgba(255, 255, 255, 0.85)' : 'rgba(255, 255, 255, 0.14)'
    };

    Object.entries(vars).forEach(([key, val]) => root.setProperty(key, val));
    syncUiSettingsControls(prefs);
    return prefs;
}

/** Update UI settings modal inputs, swatches, and badges to match active preferences. */
function syncUiSettingsControls(prefs) {
    const scaleSlider = document.getElementById('setting-ui-scale');
    const scaleLabel = document.getElementById('settings-scale-value');
    if (scaleSlider) scaleSlider.value = String(prefs.scale);
    if (scaleLabel) scaleLabel.textContent = `${Math.round(prefs.scale * 100)}%`;

    document.querySelectorAll('.scale-chip').forEach((chip) => {
        const chipScale = parseFloat(chip.getAttribute('data-scale'));
        chip.classList.toggle('active', Math.abs(chipScale - prefs.scale) < 0.015);
    });

    const colorFields = [
        { key: 'accent', inputId: 'setting-accent-color', hexId: 'setting-accent-hex' },
        { key: 'chassis', inputId: 'setting-chassis-color', hexId: 'setting-chassis-hex' },
        { key: 'screen', inputId: 'setting-screen-color', hexId: 'setting-screen-hex' }
    ];

    colorFields.forEach(({ key, inputId, hexId }) => {
        const input = document.getElementById(inputId);
        const label = document.getElementById(hexId);
        if (input) input.value = prefs[key];
        if (label) label.textContent = prefs[key].toUpperCase();
        document.querySelectorAll(`.color-swatch[data-target="${key}"]`).forEach((btn) => {
            const swatchColor = normalizeHexColor(btn.getAttribute('data-color'), '');
            btn.classList.toggle('active', swatchColor === prefs[key]);
        });
    });
}

function updateAndPersistUiPref(patch) {
    const next = applyUiPrefs({ ...loadUiPrefs(), ...patch });
    saveUiPrefs(next);
}

function openUiSettingsModal() {
    const modal = document.getElementById('ui-settings-modal');
    if (!modal) return;
    syncUiSettingsControls(loadUiPrefs());
    modal.classList.remove('hidden');
    modal.style.display = 'flex';
}

function closeUiSettingsModal() {
    const modal = document.getElementById('ui-settings-modal');
    if (!modal) return;
    modal.classList.add('hidden');
    modal.style.display = 'none';
}

/** Bind header Settings buttons and live theme/scale modal controls (runs once). */
function initUiSettingsHandlers() {
    applyUiPrefs(loadUiPrefs());
    if (uiSettingsBound) return;
    uiSettingsBound = true;

    ['btn-ui-settings', 'btn-station-settings'].forEach((id) => {
        const btn = document.getElementById(id);
        if (btn) btn.addEventListener('click', openUiSettingsModal);
    });

    ['btn-close-settings-modal', 'btn-done-ui-settings'].forEach((id) => {
        const btn = document.getElementById(id);
        if (btn) btn.addEventListener('click', closeUiSettingsModal);
    });

    const modalOverlay = document.getElementById('ui-settings-modal');
    if (modalOverlay) {
        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) closeUiSettingsModal();
        });
    }

    const scaleSlider = document.getElementById('setting-ui-scale');
    if (scaleSlider) {
        scaleSlider.addEventListener('input', (e) => {
            updateAndPersistUiPref({ scale: e.target.value });
        });
    }

    document.querySelectorAll('.scale-chip').forEach((chip) => {
        chip.addEventListener('click', () => {
            updateAndPersistUiPref({ scale: chip.getAttribute('data-scale') });
        });
    });

    [
        { key: 'accent', inputId: 'setting-accent-color' },
        { key: 'chassis', inputId: 'setting-chassis-color' },
        { key: 'screen', inputId: 'setting-screen-color' }
    ].forEach(({ key, inputId }) => {
        const input = document.getElementById(inputId);
        if (input) {
            input.addEventListener('input', (e) => {
                updateAndPersistUiPref({ [key]: e.target.value });
            });
        }
    });

    document.querySelectorAll('.color-swatch').forEach((btn) => {
        btn.addEventListener('click', () => {
            const target = btn.getAttribute('data-target');
            const color = btn.getAttribute('data-color');
            if (target && color) updateAndPersistUiPref({ [target]: color });
        });
    });

    const resetBtn = document.getElementById('btn-reset-ui-settings');
    if (resetBtn) {
        resetBtn.addEventListener('click', () => {
            const resetPrefs = applyUiPrefs({ ...DEFAULT_UI_PREFS });
            saveUiPrefs(resetPrefs);
            showToast('Tablet display & colors reset to default.', 'info');
        });
    }
}

initUiSettingsHandlers();



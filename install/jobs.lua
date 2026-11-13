-- ====================================================================
-- BURGERSHOT: QBOX / QB-CORE JOBS CONFIGURATION
-- Copy and paste this block into your:
--   resources/[qbx]/qbx_core/shared/jobs.lua OR
--   resources/[qb]/qb-core/shared/jobs.lua
-- ====================================================================

['burgershot'] = {
    label = 'Burger Shot',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        ['0'] = {
            name = 'Trainee',
            payment = 100
        },
        ['1'] = {
            name = 'Crew Member',
            payment = 150
        },
        ['2'] = {
            name = 'Cook',
            payment = 200
        },
        ['3'] = {
            name = 'Senior Cook',
            payment = 250
        },
        ['4'] = {
            name = 'Cashier',
            payment = 250
        },
        ['5'] = {
            name = 'Shift Lead',
            payment = 300
        },
        ['6'] = {
            name = 'Supervisor',
            payment = 350
        },
        ['7'] = {
            name = 'Assistant Manager',
            payment = 400
        },
        ['8'] = {
            name = 'Manager',
            isboss = true,
            payment = 500
        },
        ['9'] = {
            name = 'Owner',
            isboss = true,
            payment = 650
        },
        ['10'] = {
            name = 'Restaurant Admin',
            isboss = true,
            payment = 800
        }
    }
},


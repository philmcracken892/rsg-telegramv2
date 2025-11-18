local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local cuteBird = nil
local birdPrompt = nil
local letterPromptGroup = GetRandomIntInRange(0, 0xffffff)
local birdBlip = nil
local targetPed = nil
local targetCoords = nil
local playerCoords = nil
local notified = false
local destination = nil
local howFar = 0
local senderID = nil
local sID = nil
local tPName = nil
local buildingNotified = false
local isBirdCanSpawn = false
local isBirdAlreadySpawned = false
local birdTime = Config.BirdTimeout
local blipEntries = {}
local cachedPlayers = nil
local freezedPlayer = false
local currentMessageId = nil


CreateThread(function()
    Wait(1000) 
    
    local savedLocale = GetResourceKvpString('telegram_language')
    
    if savedLocale and savedLocale ~= '' then
        lib.setLocale(savedLocale)
        if Config.Debug then
            print('^3[TELEGRAM]^7 Loaded saved language: ' .. savedLocale)
        end
    else
        lib.setLocale(Config.DefaultLocale)
        if Config.Debug then
            print('^3[TELEGRAM]^7 Using default language: ' .. Config.DefaultLocale)
        end
    end
end)


RegisterNetEvent('rsg-telegram:client:changeLanguage', function(lang)
    lib.setLocale(lang)
    SetResourceKvp('telegram_language', lang)
    
    lib.notify({
        title = "Language Changed",
        description = "Language set to: " .. lang,
        type = 'success',
        duration = 3000
    })
end)


RegisterNetEvent('rsg-telegram:client:openLanguageMenu', function()
    if not Config.AllowPlayerLanguageChange then
        lib.notify({
            title = "Error",
            description = "Language changing is disabled by the server",
            type = 'error',
            duration = 5000
        })
        return
    end
    
    local languageOptions = {}
    
    for i = 1, #Config.AvailableLanguages do
        local lang = Config.AvailableLanguages[i]
        table.insert(languageOptions, {
            title = lang.label,
            description = "Switch to " .. lang.label,
            icon = 'fa-solid fa-language',
            onSelect = function()
                TriggerServerEvent('rsg-telegram:server:setLanguage', lang.code)
            end
        })
    end
    
    lib.registerContext({
        id = 'language_menu',
        title = 'Choose Language',
        options = languageOptions
    })
    lib.showContext('language_menu')
end)

local function GetBirdAttachConfig()
    local birdModel = Config.BirdModel
    
    if not Config.BirdAttach[birdModel] then
        print("^1[TELEGRAM ERROR]^7 Bird model '" .. birdModel .. "' not found in Config.BirdAttach! Using A_C_Eagle_01 as fallback.")
        birdModel = "A_C_Eagle_01"
    end
    
    local AttachConfig = Config.BirdAttach[birdModel]
    local Attach = IsPedMale(PlayerPedId()) and AttachConfig.Male or AttachConfig.Female
    
    return Attach
end

local function UpdateMailCount()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getUnreadLetterCount', function(count)
        LocalPlayer.state:set('telegramUnreadMessages', count or 0, true)
    end)
end

RegisterNetEvent('rsg-telegram:client:UpdateMailCount')
AddEventHandler('rsg-telegram:client:UpdateMailCount', function()
    UpdateMailCount()
end)

exports('IsBirdPostApproaching', function()
    return LocalPlayer.state.telegramIsBirdPostApproaching
end)

CreateThread(function() 
    LocalPlayer.state.telegramIsBirdPostApproaching = false
    repeat Wait(100) until LocalPlayer.state.isLoggedIn

    UpdateMailCount()
    
    CreateThread(function()
        while true do
            Wait(30000)
            if LocalPlayer.state.isLoggedIn then
                UpdateMailCount()
            end
        end
    end)
end)

-- Bird Prompt
local BirdPrompt = function()
    Citizen.CreateThread(function()
        birdPrompt = Citizen.InvokeNative(0x04F97DE45A519419)
        PromptSetControlAction(birdPrompt, RSGCore.Shared.Keybinds['ENTER'])
        local str = CreateVarString(10, 'LITERAL_STRING', locale("cl_prompt_button"))
        PromptSetText(birdPrompt, str)
        PromptSetEnabled(birdPrompt, true)
        PromptSetVisible(birdPrompt, true)
        PromptSetHoldMode(birdPrompt, true)
        PromptSetGroup(birdPrompt, letterPromptGroup)
        PromptRegisterEnd(birdPrompt)
    end)
end

function TaskFlyAway(ped, ped2)
    return Citizen.InvokeNative(0xE86A537B5A3C297C, ped, ped2)
end

-- Prompts
Citizen.CreateThread(function()
    for i = 1, #Config.PostOfficeLocations do
        local pos = Config.PostOfficeLocations[i]

        exports['rsg-core']:createPrompt(pos.location, pos.coords, RSGCore.Shared.Keybinds['J'], locale("cl_prompt") ..' '.. pos.name, {
            type = 'client',
            event = 'rsg-telegram:client:TelegramMenu'
        })

        if pos.showblip == true then
            PostOfficeBlip = BlipAddForCoords(1664425300, pos.coords)
            SetBlipSprite(PostOfficeBlip, joaat(pos.blipsprite), true)
            SetBlipScale(PostOfficeBlip, pos.blipscale)
            SetBlipName(PostOfficeBlip, pos.name)

            blipEntries[#blipEntries + 1] = { type = "BLIP", handle = PostOfficeBlip }
        end
    end
end)

-- Telegram Menu
RegisterNetEvent('rsg-telegram:client:TelegramMenu', function()
    local MenuTelegram = {
        {
            title = locale("cl_title_01"),
            icon = "fa-solid fa-book",
            description = locale("cl_title_02"),
            event = "rsg-telegram:client:OpenAddressbook",
            args = {}
        },
        {
            title = locale("cl_title_03"),
            icon = "fa-solid fa-file-contract",
            description = locale("cl_title_04"),
            event = "rsg-telegram:client:ReadMessages",
            args = {}
        },
        {
            title = locale("cl_title_05"),
            icon = "fa-solid fa-pen-to-square",
            description = locale("cl_title_06"),
            event = "rsg-telegram:client:ChooseSendMethod",
            args = {}
        },
    }
    lib.registerContext({
        id = "telegram_menu",
        title = locale("cl_title_07"),
        options = MenuTelegram
    })
    lib.showContext("telegram_menu")
end)

-- Choose Send Method
RegisterNetEvent('rsg-telegram:client:ChooseSendMethod', function()
    local SendMethodMenu = {
        {
            title = locale("cl_send_online"),
            icon = "fa-solid fa-envelope",
            description = locale("cl_send_online_desc"),
            event = "rsg-telegram:client:SendToOnlinePlayersFromPostOffice",
            args = {}
        },
        {
            title = locale("cl_send_any"),
            icon = "fa-solid fa-search",
            description = locale("cl_send_any_desc"),
            event = "rsg-telegram:client:SendToAnyPlayer",
            args = {}
        },
        {
            title = locale("cl_send_addressbook"),
            icon = "fa-solid fa-address-book",
            description = locale("cl_send_addressbook_desc"),
            event = "rsg-telegram:client:WriteMessagePostOffice",
            args = {}
        },
        {
            title = locale("cl_back"),
            icon = "fa-solid fa-arrow-left",
            description = locale("cl_back_desc"),
            event = "rsg-telegram:client:TelegramMenu",
            args = {}
        }
    }
    lib.registerContext({
        id = "send_method_menu",
        title = locale("cl_choose_method"),
        options = SendMethodMenu
    })
    lib.showContext("send_method_menu")
end)

RegisterNetEvent('rsg-telegram:client:SendToOnlinePlayersFromPostOffice', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayers', function(players)
        local option = {}

        if players ~= nil and #players > 0 then
            for i = 1, #players do
                local serverID = players[i].value
                local fullname = players[i].name
                local content = {value = serverID, label = players[i].label}
                option[#option + 1] = content
            end

            local sendButton = locale("cl_send_button_free")

            if Config.ChargePlayer then
                local lPrice = tonumber(Config.CostPerLetter)
                sendButton = string.format(locale('cl_send_button_paid'), lPrice)
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, label = locale('cl_recipient') },
                { type = 'input', label = locale("cl_title_08"), required = true },
                { type = 'textarea', label = locale("cl_title_09"), required = true, autosize = true },
            })
            
            if not input then return end

            local recipient = input[1]
            local subject = input[2]
            local message = input[3]

            if recipient and subject and message then
                local alert = lib.alertDialog({
                    header = sendButton,
                    content = locale("cl_send_confirm_bird"),
                    centered = true,
                    cancel = true
                })
                
                if alert == 'confirm' then
                    local pID = PlayerId()
                    local senderID = GetPlayerServerId(pID)
                    local playerData = RSGCore.Functions.GetPlayerData()
                    local senderfullname = playerData.charinfo.firstname..' '..playerData.charinfo.lastname
                    local sendertelegram = playerData.citizenid
                    
                    TriggerServerEvent('rsg-telegram:server:SendMessageToOnlinePlayer', 
                        senderID, 
                        sendertelegram, 
                        senderfullname, 
                        recipient,
                        subject, 
                        message
                    )
                end
            end
        else
            lib.notify({ title = locale("cl_title_11"), description = locale("cl_no_results_desc"), type = 'error', duration = 7000 })
        end
    end)
end)


RegisterNetEvent('rsg-telegram:client:SendToAnyPlayer', function()
    local input = lib.inputDialog(locale('cl_search_player'), {
        { 
            type = 'input', 
            label = locale('cl_search_input'), 
            description = locale('cl_search_hint'),
            required = true,
            min = 3
        }
    })
    
    if not input then return end
    
    local searchTerm = input[1]
    
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:SearchPlayers', function(players)
        if not players or #players == 0 then
            lib.notify({ 
                title = locale("cl_no_results"), 
                description = locale("cl_no_results_desc") .. " '" .. searchTerm .. "'", 
                type = 'error', 
                duration = 5000 
            })
            return
        end
        
        local option = {}
        
        for i = 1, #players do
            local player = players[i]
            local status = player.online and "player " .. locale("cl_online") or "?? " .. locale("cl_offline")
            local content = {
                value = player.citizenid, 
                label = player.name .. " (" .. player.citizenid .. ") " .. status
            }
            option[#option + 1] = content
        end
        
        local sendButton = locale("cl_send_button_free")
        
        if Config.ChargePlayer then
            local lPrice = tonumber(Config.CostPerLetter)
            sendButton = string.format(locale('cl_send_button_paid'), lPrice)
        end
        
        local input2 = lib.inputDialog(locale('cl_send_letter_to'), {
            { type = 'select', options = option, required = true, label = locale('cl_select_recipient') },
            { type = 'input', label = locale("cl_title_08"), required = true },
            { type = 'textarea', label = locale("cl_title_09"), required = true, autosize = true },
        })
        
        if not input2 then return end
        
        local recipient = input2[1]
        local subject = input2[2]
        local message = input2[3]
        
        if recipient and subject and message then
            local alert = lib.alertDialog({
                header = sendButton,
                content = locale("cl_send_confirm_any"),
                centered = true,
                cancel = true
            })
            
            if alert == 'confirm' then
                local pID = PlayerId()
                local senderID = GetPlayerServerId(pID)
                local playerData = RSGCore.Functions.GetPlayerData()
                local senderfullname = playerData.charinfo.firstname..' '..playerData.charinfo.lastname
                local sendertelegram = playerData.citizenid
                
                TriggerServerEvent('rsg-telegram:server:SendToSearchedPlayer', 
                    sendertelegram, 
                    senderfullname, 
                    recipient,
                    subject, 
                    message
                )
            end
        end
    end, searchTerm)
end)

RegisterNetEvent('rsg-telegram:client:WriteMessagePostOffice', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayersPostOffice', function(players)
        local option = {}

        if players~=nil then
            for i = 1, #players do
                local citizenid = players[i].citizenid
                local fullname = players[i].name
                local content = {value = citizenid, label = fullname..' ('..citizenid..')'}

                option[#option + 1] = content
            end

            local sendButton = locale("cl_send_button_free")

            if Config.ChargePlayer then
                local lPrice = tonumber(Config.CostPerLetter)
                sendButton = string.format(locale('cl_send_button_paid'), lPrice)
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, label = locale('cl_recipient') },
                { type = 'input', label = locale("cl_title_08"), required = true },
                { type = 'textarea', label = locale("cl_title_09"), required = true, autosize = true },
            })
            if not input then return end

            local recipient = input[1]
            local subject = input[2]
            local message = input[3]

            if recipient and subject and message then
                local alert = lib.alertDialog({
                    header = sendButton,
                    content = locale("cl_title_10"),
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    local pID =  PlayerId()
                    senderID = GetPlayerServerId(pID)
                    local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
                    local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
                    local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
                    local senderfullname = senderfirstname..' '..senderlastname
                    TriggerServerEvent('rsg-telegram:server:SendMessagePostOffice', sendertelegram, senderfullname, recipient, subject, message)
                end
            end
        else
            lib.notify({ title = locale("cl_title_11"), description = locale("cl_title_12"), type = 'error', duration = 7000 })
        end
    end)
end)

local function Prompts()
    if not PromptHasHoldModeCompleted(birdPrompt) then return end

    local ped = PlayerPedId()

    if destination < 3 and IsPedOnMount(ped) or IsPedOnVehicle(ped) then
        lib.notify({ title = locale("cl_title_11"), description = locale('cl_player_on_horse'), type = 'error', duration = 7000 })
        Wait(3000)
        return
    end

    

    TriggerServerEvent('rsg-telegram:server:DeliverySuccess', sID, tPName)

    Wait(1000)

    TaskFlyToCoord(cuteBird, 0, playerCoords.x - 100, playerCoords.y - 100, playerCoords.z + 50, 1, 0)

    if birdBlip ~= nil then
        RemoveBlip(birdBlip)
    end

    LocalPlayer.state.telegramIsBirdPostApproaching = false
    isBirdAlreadySpawned = false
    notified = false

    Wait(10000)

    SetEntityInvincible(cuteBird, false)
    SetEntityCanBeDamaged(cuteBird, true)
    SetEntityAsMissionEntity(cuteBird, false, false)
    SetEntityAsNoLongerNeeded(cuteBird)
    DeleteEntity(cuteBird)
end

-- Set Bird Attribute
local SetPetAttributes = function(entity)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 0, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 1, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 2, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 0, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 1, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 2, 1100)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 0, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 1, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 2, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 0, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 1, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 2, 10)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 0, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 1, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 2, 5000.0, false)
end

-- Spawn the Bird Post
local SpawnBirdPost = function(posX, posY, posZ, heading, rfar, isIncoming)
    local playerPed = PlayerPedId()
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, -100.0, 0.1))
    
    cuteBird = CreatePed(Config.BirdModel, x, y, z + 50.0, heading, 1, 1)
    
    while not IsEntityAPed(cuteBird) do
        Citizen.Wait(1)
    end

    SetPetAttributes(cuteBird)
    Citizen.InvokeNative(0x013A7BA5015C1372, cuteBird, true)
    Citizen.InvokeNative(0xAEB97D84CDF3C00B, cuteBird, false)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(cuteBird), GetHashKey('PLAYER'))
    SetBlockingOfNonTemporaryEvents(cuteBird, true)
    SetEntityInvincible(cuteBird, true)
    SetEntityCollision(cuteBird, false, false)
    Citizen.InvokeNative(0x283978A15512B2FE, cuteBird, true)
    
    Wait(500)

    Citizen.InvokeNative(0x283978A15512B2FE, cuteBird, true)
    ClearPedTasks(cuteBird)
    ClearPedSecondaryTask(cuteBird)
    ClearPedTasksImmediately(cuteBird)
    SetPedFleeAttributes(cuteBird, 0, 0)
    TaskWanderStandard(cuteBird, 0, 0)
    TaskSetBlockingOfNonTemporaryEvents(cuteBird, 1)
    SetEntityAsMissionEntity(cuteBird, true, true)
    Citizen.InvokeNative(0xA5C38736C426FCB8, cuteBird, true)

    Wait(2000)

    local blipname = isIncoming and "Incoming " .. locale("cl_prompt_desc") or "Outgoing " .. locale("cl_prompt_desc")
    local bliphash = -1749618580

    birdBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, bliphash, cuteBird)
    Citizen.InvokeNative(0x9CB1A1623062F402, birdBlip, blipname)
    Citizen.InvokeNative(0x0DF2B55F717DDB10, birdBlip)
    
    if isIncoming then
        Citizen.InvokeNative(0x662D364ABF16DE2F, birdBlip, GetHashKey("BLIP_MODIFIER_DEBUG_BLUE"))
    else
        Citizen.InvokeNative(0x662D364ABF16DE2F, birdBlip, GetHashKey("BLIP_MODIFIER_DEBUG_YELLOW"))
    end
    
    SetBlipScale(birdBlip, 0.8)
end

CreateThread(function()
    while true do
        Wait(500)
        
        if cuteBird and DoesEntityExist(cuteBird) and birdBlip then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local birdCoords = GetEntityCoords(cuteBird)
            local distance = #(playerCoords - birdCoords)
            
            if not DoesBlipExist(birdBlip) then
                local blipname = LocalPlayer.state.telegramIsBirdPostApproaching and "Incoming " .. locale("cl_prompt_desc") or "Outgoing " .. locale("cl_prompt_desc")
                birdBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, -1749618580, cuteBird)
                Citizen.InvokeNative(0x9CB1A1623062F402, birdBlip, blipname)
                SetBlipScale(birdBlip, 0.8)
            end
            
            if distance < 20 then
                Citizen.InvokeNative(0x662D364ABF16DE2F, birdBlip, GetHashKey("BLIP_MODIFIER_DEBUG_GREEN"))
            end
        end
    end
end)

CreateThread(function()
    BirdPrompt()

    while true do
        Wait(1)

        if notified and destination < 3 then
            local Bird = CreateVarString(10, "LITERAL_STRING", locale("cl_prompt_desc"))
            PromptSetActiveGroupThisFrame(letterPromptGroup, Bird)

            if PromptHasHoldModeCompleted(birdPrompt) then
                Prompts()
            end
        end
    end
end)

-- Receive Message
RegisterNetEvent('rsg-telegram:client:ReceiveMessage')
AddEventHandler('rsg-telegram:client:ReceiveMessage', function(SsID, StPName, letterData)
    LocalPlayer.state.telegramIsBirdPostApproaching = true
    sID = SsID
    tPName = StPName
    local ped = PlayerPedId()
    local rFar = math.random(50, 100)
    buildingNotified = false
    notified = false
    isBirdAlreadySpawned = false
    birdTime = Config.BirdTimeout or 300

    while LocalPlayer.state.telegramIsBirdPostApproaching do
        Wait(1)
        playerCoords = GetEntityCoords(ped)
        local myCoords = vector3(playerCoords.x, playerCoords.y, playerCoords.z)
        local insideBuilding = GetInteriorFromEntity(ped)
        isBirdCanSpawn = true

        if insideBuilding ~= 0 then
            if not buildingNotified then
                lib.notify({ title = locale("cl_prompt_desc"), description = locale("cl_bird_cant_find"), type = 'error', duration = 7000 })
                buildingNotified = true
            end
            isBirdCanSpawn = false
            goto continue
        end

        if isBirdCanSpawn and not isBirdAlreadySpawned then
            SpawnBirdPost(playerCoords.x - 100, playerCoords.y - 100, playerCoords.z + 100, 92.0, rFar, true)
            if cuteBird then
                ClearPedTasks(cuteBird)
                Wait(100)
                TaskFlyToCoord(cuteBird, 1.0, playerCoords.x, playerCoords.y, playerCoords.z + 0.8, 1, 0)
                isBirdCanSpawn = false
                isBirdAlreadySpawned = true
            end
        end

        if cuteBird then
            local birdCoords = GetEntityCoords(cuteBird)
            destination = #(birdCoords - myCoords)

            if destination < 100 and not notified then
                notified = true
                lib.notify({ title = locale("cl_prompt_desc"), description = locale("cl_bird_approaching"), type = 'info', duration = 7000 })
                Wait(5000)
                lib.notify({ title = locale("cl_prompt_desc"), description = locale("cl_wait_for_bird"), type = 'info', duration = 7000 })
            end

            if destination <= 10 and not freezedPlayer then
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                freezedPlayer = true
            end

            if destination <= 2.5 then
                local pc2 = GetEntityCoords(PlayerPedId())
                local dist2 = GetDistanceBetweenCoords(GetEntityCoords(cuteBird), pc2, true)
                if dist2 > 1.2 then
                    ClearPedTasks(cuteBird)
                    TaskFlyToCoord(cuteBird, 1.0, pc2.x, pc2.y, pc2.z + 0.5, 1, 0)
                end
                
                while dist2 > 1.5 do
                    dist2 = GetDistanceBetweenCoords(GetEntityCoords(cuteBird), pc2, true)
                    Citizen.Wait(100)
                end
                
                ClearPedTasks(ped)
                ClearPedSecondaryTask(ped)
                FreezeEntityPosition(ped, false)
                SetEntityInvincible(ped, true)
                
                local Attach = GetBirdAttachConfig()

                AttachEntityToEntity(
                    cuteBird,
                    PlayerPedId(),
                    Attach[1], Attach[2], Attach[3], Attach[4], Attach[5], Attach[6], Attach[7],
                    false, false, true, false, 0, true, false, false
                )

                ClearPedTasksImmediately(cuteBird)
                SetBlockingOfNonTemporaryEvents(cuteBird, true)
                FreezeEntityPosition(cuteBird, true)

                Wait(2000)

                TriggerServerEvent('rsg-telegram:server:GiveLetter', letterData)

                Wait(1000)

                if IsEntityAttached(cuteBird) then
                    DetachEntity(cuteBird, 1, 1)
                end
                if IsEntityFrozen(cuteBird) then
                    FreezeEntityPosition(cuteBird, false)
                end
                SetEntityCollision(cuteBird, false, false)
                
                ClearPedTasks(cuteBird)
                Wait(100)
                
                TaskFlyAway(cuteBird, PlayerPedId())

                Wait(Config.BirdArrivalDelay)

                SetEntityInvincible(cuteBird, false)
                SetEntityCanBeDamaged(cuteBird, true)
                SetEntityAsMissionEntity(cuteBird, false, false)
                SetEntityAsNoLongerNeeded(cuteBird)
                DeleteEntity(cuteBird)

                if birdBlip ~= nil then
                    RemoveBlip(birdBlip)
                end

                FreezeEntityPosition(ped, false)
                SetEntityInvincible(ped, false)
                ClearPedTasks(ped)
                ClearPedSecondaryTask(ped)

                TriggerServerEvent('rsg-telegram:server:DeliverySuccess', sID, tPName)
                LocalPlayer.state.telegramIsBirdPostApproaching = false
                freezedPlayer = false
                return
            end
        end

        local IsPedAir = IsEntityInAir(cuteBird, 1)
        local isBirdDead = Citizen.InvokeNative(0x7D5B1F88E7504BBA, cuteBird)
        BirdCoords = GetEntityCoords(cuteBird)

        if cuteBird ~= nil and not IsPedAir and notified and destination > 3 then
            if Config.AutoResurrect and isBirdDead then
                ClearPedTasksImmediately(cuteBird)
                SetEntityCoords(cuteBird, BirdCoords.x, BirdCoords.y, BirdCoords.z)
                Wait(1000)
                Citizen.InvokeNative(0x71BC8E838B9C6035, cuteBird)
                Wait(1000)
            end
            
            ClearPedTasks(cuteBird)
            Wait(50)
            TaskFlyToCoord(cuteBird, 1.0, myCoords.x, myCoords.y, myCoords.z + 0.5, 1, 0)
        end

        if birdTime > 0 then
            birdTime = birdTime - 1
            Wait(1000)
        end

        if birdTime == 0 and cuteBird ~= nil and notified then
            lib.notify({ title = locale("cl_title_11"), description = locale("cl_delivery_fail1"), type = 'error', duration = 7000 })
            Wait(3000)
            lib.notify({ title = locale("cl_title_11"), description = locale("cl_delivery_fail2"), type = 'error', duration = 7000 })
            
            TriggerServerEvent('rsg-telegram:server:SaveFailedDelivery', letterData)
            
            SetEntityInvincible(cuteBird, false)
            SetEntityAsMissionEntity(cuteBird, false, false)
            SetEntityAsNoLongerNeeded(cuteBird)
            DeleteEntity(cuteBird)
            RemoveBlip(birdBlip)
            notified = false
            LocalPlayer.state.telegramIsBirdPostApproaching = false
            freezedPlayer = false
            return
        end

        ::continue::
    end
end)

RegisterNetEvent('rsg-telegram:client:WriteMessage', function()
    local selectionMenu = {
        {
            title = locale("cl_online_players_bird"),
            icon = "fa-solid fa-dove",
            description = locale("cl_bird_post_bird"),
            event = "rsg-telegram:client:SendToOnlinePlayers",
            args = {}
        },
        {
            title = locale("cl_addressbook_post"),
            icon = "fa-solid fa-address-book", 
            description = locale("cl_bird_post_office"),
            event = "rsg-telegram:client:SendToAddressBookViaBird",
            args = {}
        }
    }
    
    lib.registerContext({
        id = "send_message_selection",
        title = locale("cl_send_bird_post"),
        options = selectionMenu
    })
    lib.showContext("send_message_selection")
end)

RegisterNetEvent('rsg-telegram:client:SendToAddressBookViaBird', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayersPostOffice', function(players)
        local option = {}

        if players~=nil then
            for i = 1, #players do
                local citizenid = players[i].citizenid
                local fullname = players[i].name
                local content = {value = citizenid, label = fullname..' ('..citizenid..')'}

                option[#option + 1] = content
            end

            local sendButton = locale("cl_send_button_free")

            if Config.ChargePlayer then
                local lPrice = tonumber(Config.CostPerLetter)
                sendButton = string.format(locale('cl_send_button_paid'), lPrice)
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, label = locale('cl_recipient') },
                { type = 'input', label = locale("cl_title_08"), required = true },
                { type = 'textarea', label = locale("cl_title_09"), required = true, autosize = true },
            })
            if not input then return end

            local recipient = input[1]
            local subject = input[2]
            local message = input[3]

            if recipient and subject and message then
                local alert = lib.alertDialog({
                    header = sendButton,
                    content = locale("cl_send_confirm_addressbook"),
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    local pID =  PlayerId()
                    local senderID = GetPlayerServerId(pID)
                    local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
                    local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
                    local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
                    local senderfullname = senderfirstname..' '..senderlastname
                    TriggerServerEvent('rsg-telegram:server:SendMessagePostOffice', sendertelegram, senderfullname, recipient, subject, message)
                end
            end
        else
            lib.notify({ title = locale("cl_title_11"), description = locale("cl_title_12"), type = 'error', duration = 7000 })
        end
    end)
end)

RegisterNetEvent('rsg-telegram:client:SendToOnlinePlayers', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayers', function(players)
        if players ~= nil then
            local option = {}

            if LocalPlayer.state.telegramIsBirdPostApproaching then
                lib.notify({ title = locale("cl_title_11"), description = locale('cl_send_receiving'), type = 'error', duration = 7000 })
                return
            end

            local ped = PlayerPedId()
            local pID = PlayerId()
            senderID = GetPlayerServerId(pID)

            if IsPedOnMount(ped) or IsPedOnVehicle(ped) then
                lib.notify({ title = locale("cl_title_11"), description = locale('cl_player_on_horse'), type = 'error', duration = 7000 })
                return
            end

            -- Check if player is inside a building
            local insideBuilding = GetInteriorFromEntity(ped)
            if insideBuilding ~= 0 then
                lib.notify({ title = locale("cl_title_11"), description = locale('cl_cannot_call_bird_inside'), type = 'error', duration = 7000 })
                return
            end

            ClearPedTasks(ped)
            ClearPedSecondaryTask(ped)
            FreezeEntityPosition(ped, false)
            SetEntityInvincible(ped, true)

            playerCoords = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)
            local rFar = 30

            TaskWhistleAnim(ped, GetHashKey('WHISTLEHORSELONG'))

            SpawnBirdPost(playerCoords.x, playerCoords.y - rFar, playerCoords.z, heading, rFar, false)
            SetEntityCollision(cuteBird, false, false)

            if cuteBird == nil then
                lib.notify({ title = locale("cl_title_11"), description = locale("cl_title_14"), type = 'error', duration = 7000 })
                return
            end

            ClearPedTasks(cuteBird)
            Wait(100)
            TaskFlyToCoord(cuteBird, 1.0, playerCoords.x, playerCoords.y, playerCoords.z + 0.5, 1, 0)
            TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_WRITE_NOTEBOOK'), -1, true, false, false, false)
			Citizen.Wait(7000)
			ClearPedTasks(ped)

            Citizen.CreateThread(function()
                local pc = GetEntityCoords(PlayerPedId())
                while true do
                    Citizen.Wait(500)
                    local dist = GetDistanceBetweenCoords(pc, GetEntityCoords(cuteBird), true)
                    if dist < 5.0 then
                        local pc2 = GetEntityCoords(PlayerPedId())
                        local dist2 = GetDistanceBetweenCoords(GetEntityCoords(cuteBird), pc2, true)
                        if dist2 > 1.2 then
                            ClearPedTasks(cuteBird)
                            TaskFlyToCoord(cuteBird, 1.0, pc2.x, pc2.y, pc2.z + 0.5, 1, 0)
                        end
                        while dist2 > 1.5 do
                            dist2 = GetDistanceBetweenCoords(GetEntityCoords(cuteBird), pc2, true)
                            Citizen.Wait(100)
                        end
                        
                        local Attach = GetBirdAttachConfig()
                        
                        AttachEntityToEntity(cuteBird, PlayerPedId(), Attach[1], Attach[2], Attach[3], Attach[4], Attach[5], Attach[6], Attach[7], false, false, true, false, 0, true, false, false)
                        ClearPedTasksImmediately(cuteBird)
                        SetBlockingOfNonTemporaryEvents(cuteBird, true)
                        FreezeEntityPosition(cuteBird, true)
                        break
                    end
                end
            end)
            
            while not IsEntityAttached(cuteBird) do
                Citizen.Wait(100)
            end

            local sendButton = locale("cl_send_button_free")

            if Config.ChargePlayer then
                local lPrice = tonumber(Config.CostPerLetter)
                sendButton = string.format(locale('cl_send_button_paid'), lPrice)
            end

            for i = 1, #players do
                local targetPlayer = players[i]
                local content = { value = targetPlayer.value, label = targetPlayer.label }
                option[#option + 1] = content
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, label = locale('cl_recipient') },
                {type = 'input', label = locale("cl_title_08"), required = true},
                {type = 'input', label = locale("cl_title_09"), required = true},
            })

            if not input then
                FreezeEntityPosition(PlayerPedId(), false)
                SetEntityInvincible(PlayerPedId(), false)
                ClearPedTasks(PlayerPedId())
                ClearPedSecondaryTask(PlayerPedId())

                if IsEntityAttached(cuteBird) then
                    DetachEntity(cuteBird, 1, 1)
                end
                if IsEntityFrozen(cuteBird) then
                    FreezeEntityPosition(cuteBird, false)
                end

                SetEntityInvincible(cuteBird, false)
                SetEntityCanBeDamaged(cuteBird, true)
                SetEntityAsMissionEntity(cuteBird, false, false)
                SetEntityCollision(cuteBird, false, false)
                SetEntityAsNoLongerNeeded(cuteBird)
                DeleteEntity(cuteBird)

                if birdBlip ~= nil then
                    RemoveBlip(birdBlip)
                end

                lib.notify({ title = locale("cl_title_11"), description = locale('cl_cancel_send'), type = 'error', duration = 7000 })
                return
            end

            local recipient = input[1]
            local subject = input[2]
            local message = input[3]
            
            local alert = lib.alertDialog({
                header = sendButton,
                content = locale("cl_title_10"),
                centered = true,
                cancel = true
            })

            if alert == 'confirm' then
                local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
                local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
                local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
                local senderfullname = senderfirstname..' '..senderlastname

                if IsEntityAttached(cuteBird) then
                    DetachEntity(cuteBird, 1, 1)
                end
                if IsEntityFrozen(cuteBird) then
                    FreezeEntityPosition(cuteBird, false)
                end
                SetEntityCollision(cuteBird, false, false)

                FreezeEntityPosition(ped, false)
                SetEntityInvincible(ped, false)
                ClearPedTasks(ped)
                ClearPedSecondaryTask(ped)

                ClearPedTasks(cuteBird)
                Wait(100)
                TaskFlyAway(cuteBird, PlayerPedId())

                Wait(Config.BirdArrivalDelay)

                SetEntityInvincible(cuteBird, false)
                FreezeEntityPosition(cuteBird, false)
                SetEntityCanBeDamaged(cuteBird, true)
                SetEntityAsMissionEntity(cuteBird, false, false)
                SetEntityAsNoLongerNeeded(cuteBird)
                DeleteEntity(cuteBird)
                
                if birdBlip ~= nil then
                    RemoveBlip(birdBlip)
                end

                TriggerServerEvent('rsg-telegram:server:SendMessage', 
                    senderID, 
                    sendertelegram, 
                    senderfullname, 
                    recipient,
                    subject, 
                    message
                )
            else
                FreezeEntityPosition(ped, false)
                SetEntityInvincible(ped, false)
                ClearPedTasks(ped)
                ClearPedSecondaryTask(ped)

                if IsEntityAttached(cuteBird) then
                    DetachEntity(cuteBird, 1, 1)
                end
                if IsEntityFrozen(cuteBird) then
                    FreezeEntityPosition(cuteBird, false)
                end
                
                SetEntityInvincible(cuteBird, false)
                SetEntityCanBeDamaged(cuteBird, true)
                SetEntityAsMissionEntity(cuteBird, false, false)
                SetEntityCollision(cuteBird, false, false)
                SetEntityAsNoLongerNeeded(cuteBird)
                DeleteEntity(cuteBird)

                if birdBlip ~= nil then
                    RemoveBlip(birdBlip)
                end

                lib.notify({ title = locale("cl_title_15"), description = locale("cl_title_16"), type = 'error' })
            end
        else
            lib.notify({ title = locale("cl_title_15"), description = locale("cl_title_16"), type = 'error' })
        end
    end)
end)

RegisterNetEvent('rsg-telegram:client:ReadLetter')
AddEventHandler('rsg-telegram:client:ReadLetter', function(letterData, slot)
    TriggerServerEvent('rsg-telegram:server:MarkLetterRead', slot)
    
    local letterContent = string.format(
        "```\n" ..
        "═══════════════════════════════════════════\n" ..
        "               WESTERN UNION\n" ..
        "                 TELEGRAM\n" ..
        "════════════════════════════════════════════\n\n" ..
        "FROM: %s\n" ..
        "TO:   %s\n" ..
        "DATE: %s\n\n" ..
        "────────────────────────────────────────────\n\n" ..
        "%s\n\n" ..
        "────────────────────────────────────────────\n" ..
        "```",
        string.upper(letterData.sender or "UNKNOWN"),
        string.upper(letterData.recipient or "YOU"),
        string.upper(letterData.date or "UNKNOWN"),
        letterData.message or locale("cl_letter_blank")
    )

    local choice = lib.alertDialog({
        header = letterData.subject or "TELEGRAM",
        content = letterContent,
        centered = true,
        cancel = true,
        labels = {
            confirm = 'ACTIONS',
            cancel = 'CLOSE'
        }
    })
    
    if choice == 'confirm' then
        lib.registerContext({
            id = 'letter_actions',
            title = 'TELEGRAM ACTIONS',
            options = {
                {
                    title = locale("cl_read_again"),
                    icon = 'fa-solid fa-envelope-open',
                    iconColor = '#8B7355',
                    onSelect = function()
                        TriggerEvent('rsg-telegram:client:ReadLetter', letterData, slot)
                    end
                },
                {
                    title = locale("cl_copy_message"),
                    icon = 'fa-solid fa-copy',
                    iconColor = '#2C5F2D',
                    onSelect = function()
                        lib.setClipboard(letterData.message)
                        lib.notify({ 
                            title = 'MESSAGE COPIED', 
                            type = 'success' 
                        })
                    end
                },
                {
                    title = locale("cl_burn_letter"),
                    icon = 'fa-solid fa-fire',
                    iconColor = '#8B0000',
                    onSelect = function()
                        local alert = lib.alertDialog({
                            header = 'DESTROY TELEGRAM',
                            content = 'This action cannot be undone.',
                            centered = true,
                            cancel = true,
                            labels = {
                                confirm = 'DESTROY',
                                cancel = 'CANCEL'
                            }
                        })
                        if alert == 'confirm' then
                            TriggerServerEvent('rsg-telegram:server:DestroyLetter', slot)
                        end
                    end
                },
                {
                    title = locale("cl_keep_letter"),
                    icon = 'fa-solid fa-archive',
                    iconColor = '#DAA520',
                    onSelect = function()
                        lib.notify({ 
                            title = 'TELEGRAM SAVED', 
                            type = 'info' 
                        })
                    end
                }
            }
        })
        lib.showContext('letter_actions')
    end
end)

RegisterNetEvent('rsg-telegram:client:ReadMessages')
AddEventHandler('rsg-telegram:client:ReadMessages', function()
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

RegisterNetEvent('rsg-telegram:client:InboxList')
AddEventHandler('rsg-telegram:client:InboxList', function(data)
    local messages = data.list
    
    if not messages or #messages == 0 then
        lib.notify({ 
            title = locale("cl_title_03"), 
            description = locale("cl_no_messages"), 
            type = 'info', 
            duration = 5000 
        })
        return
    end

    local options = {}

    for i, msg in ipairs(messages) do
        table.insert(options, {
            title = msg.subject,
            description = locale("cl_from") .. ": " .. msg.sendername .. " | " .. msg.sentDate,
            icon = 'fa-solid fa-envelope',
            iconColor = 'yellow',
            onSelect = function()
                local alert = lib.alertDialog({
                    header = locale('cl_claim_letter'),
                    content = locale('cl_claim_letter_desc') .. '\n\n' .. locale('cl_from') .. ': **'..msg.sendername..'**\n' .. locale('cl_title_08') .. ': **'..msg.subject..'**',
                    centered = true,
                    cancel = true,
                    labels = {
                        confirm = locale('cl_claim'),
                        cancel = locale('cl_leave_it')
                    }
                })
                if alert == 'confirm' then
                    TriggerServerEvent('rsg-telegram:server:ClaimLetter', msg.id)
                end
            end,
            metadata = {
                {label = locale('cl_from'), value = msg.sendername},
                {label = locale('cl_date'), value = msg.sentDate}
            }
        })
    end

    if #messages > 0 then
        table.insert(options, {
            title = "---------------",
            disabled = true
        })

        table.insert(options, {
            title = locale("cl_delete_all"),
            icon = 'fa-solid fa-trash',
            iconColor = 'red',
            description = locale("cl_delete_all_desc"),
            onSelect = function()
                local alert = lib.alertDialog({
                    header = locale('cl_delete_all_confirm'),
                    content = string.format(locale('cl_delete_all_confirm_desc'), #messages),
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    local count = #messages
                    for _, msg in ipairs(messages) do
                        TriggerServerEvent('rsg-telegram:server:DeleteMessage', msg.id, true)
                    end
                    lib.notify({ 
                        title = locale("cl_success"), 
                        description = count .. " " .. locale("cl_messages_deleted"), 
                        type = 'success',
                        duration = 3000
                    })
                    Wait(1000)
                    TriggerServerEvent('rsg-telegram:server:CheckInbox')
                end
            end
        })
    end

    lib.registerContext({
        id = 'telegram_inbox',
        title = 'ðŸ“‚ ' .. locale('cl_post_office_inbox') .. ' (' .. #messages .. ')',
        options = options
    })
    lib.showContext('telegram_inbox')
end)

-- Cleanup
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if birdBlip ~= nil then
        RemoveBlip(birdBlip)
    end

    SetEntityAsMissionEntity(cuteBird, false)
    FreezeEntityPosition(cuteBird, false)
    DeleteEntity(cuteBird)
    PromptDelete(birdPrompt)

    for i = 1, #Config.PostOfficeLocations do
        local pos = Config.PostOfficeLocations[i]
        exports['rsg-core']:deletePrompt(pos.location)
    end

    for i = 1, #blipEntries do
        if blipEntries[i].type == "BLIP" then
            RemoveBlip(blipEntries[i].handle)
        end
    end
end)

-- AddressBook
RegisterNetEvent('rsg-telegram:client:OpenAddressbook', function()
    lib.registerContext({
        id = 'addressbook_menu',
        title = locale("cl_title_17"),
        position = 'top-right',
        options = {
            {
                title = locale("cl_title_18"),
                description = locale("cl_title_19"),
                icon = 'fa-solid fa-book',
                event = 'rsg-telegram:client:ViewAddressBook',
                args = { isServer = false }
            },
            {
                title = locale("cl_title_20"),
                description = locale("cl_title_21"),
                icon = 'fa-solid fa-book',
                iconColor = 'green',
                event = 'rsg-telegram:client:AddPersonMenu',
                args = { isServer = false }
            },
            {
                title = locale("cl_title_22"),
                description = locale("cl_title_23"),
                icon = 'fa-solid fa-book',
                iconColor = 'red',
                event = 'rsg-telegram:client:RemovePersonMenu',
                args = { isServer = false }
            },
        }
    })
    lib.showContext('addressbook_menu')
end)

RegisterNetEvent('rsg-telegram:client:AddPersonMenu', function()
    local input = lib.inputDialog(locale("cl_title_24"), {
        { type = 'input', label = locale("cl_title_25"), required = true },
        { type = 'input', label = locale("cl_title_26"), required = true },
    })
    if not input then return end

    local name = input[1]
    local cid = input[2]
    if name and cid then
        TriggerServerEvent('rsg-telegram:server:SavePerson', name, cid)
    end
end)

RegisterNetEvent('rsg-telegram:client:ViewAddressBook', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayersPostOffice', function(players)
        if players ~= nil then
            local options = {
                {
                    title = locale("cl_title_27"),
                    description = locale("cl_title_28"),
                    icon = 'fa-solid fa-envelope-open-text',
                    isMenuHeader = true,
                },
            }
            for i = 1, #players do
                local player = players[i]
                options[#options + 1] = {
                    title = player.name,
                    description = locale("cl_title_29") .. player.citizenid,
                    disabled = true
                }
            end
            options[#options + 1] = {
                title = locale("cl_title_30"),
                description = locale("cl_title_31"),
                icon = 'fa-solid fa-circle-xmark',
                event = 'rsg-telegram:client:OpenAddressbook',
                args = { isServer = false }
            }
            lib.registerContext({
                id = 'addressbook_view',
                title = locale("cl_title_32"),
                position = 'top-right',
                options = options
            })
            lib.showContext('addressbook_view')
        else
            lib.notify({ title = locale("cl_title_33"), description = locale("cl_title_34"), type = 'error', duration = 7000 })
        end
    end)
end)

RegisterNetEvent('rsg-telegram:client:RemovePersonMenu', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayersPostOffice', function(players)
        if players ~= nil then
            local option = {}
            for i = 1, #players do
                local citizenid = players[i].citizenid
                local fullname = players[i].name
                local content = { value = citizenid, label = fullname .. ' (' .. citizenid .. ')' }
                option[#option + 1] = content
            end

            local input = lib.inputDialog(locale("cl_title_35"), {
                { type = 'select', options = option, required = true, label = locale('cl_recipient') }
            })
            if not input then return end

            local citizenid = input[1]
            if citizenid then
                TriggerServerEvent('rsg-telegram:server:RemovePerson', citizenid)
            end
        else
            lib.notify({ title = locale("cl_title_36"), description = locale("cl_title_37"), type = 'error', duration = 7000 })
        end
    end)
end)

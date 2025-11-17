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

---@deprecated use state LocalPlayer.state.telegramIsBirdPostApproaching
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
            title = "Send Letter",
            icon = "fa-solid fa-pen-to-square",
            description = "Choose how to send your letter",
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
            title = "Send to Online Players",
            icon = "fa-solid fa-users",
            description = "Send directly to players currently online (instant delivery)",
            event = "rsg-telegram:client:SendToOnlinePlayersFromPostOffice",
            args = {}
        },
        {
            title = "Send to Address Book",
            icon = "fa-solid fa-address-book",
            description = "Send to saved contacts (will be stored if offline)",
            event = "rsg-telegram:client:WriteMessagePostOffice",
            args = {}
        },
        {
            title = "Back",
            icon = "fa-solid fa-arrow-left",
            description = "Return to main menu",
            event = "rsg-telegram:client:TelegramMenu",
            args = {}
        }
    }
    lib.registerContext({
        id = "send_method_menu",
        title = "Choose Sending Method",
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

            local sendButton = "Send Letter (Free)"

            if Config.ChargePlayer then
                local lPrice = tonumber(Config.CostPerLetter)
                sendButton = 'Send Letter ($'..lPrice..')'
            end

            local input = lib.inputDialog('Send Letter to Online Player', {
                { type = 'select', options = option, required = true, label = 'Recipient' },
                { type = 'input', label = 'Subject', required = true },
                { type = 'textarea', label = 'Message', required = true, autosize = true },
            })
            
            if not input then return end

            local recipient = input[1]  -- server ID
            local subject = input[2]
            local message = input[3]

            if recipient and subject and message then
                local alert = lib.alertDialog({
                    header = sendButton,
                    content = "Send this letter via post office?\n\nThe recipient will receive it instantly.",
                    centered = true,
                    cancel = true
                })
                
                if alert == 'confirm' then
                    local pID = PlayerId()
                    local senderID = GetPlayerServerId(pID)
                    local playerData = RSGCore.Functions.GetPlayerData()
                    local senderfullname = playerData.charinfo.firstname..' '..playerData.charinfo.lastname
                    local sendertelegram = playerData.citizenid
                    
                    -- Send directly via post office (no bird)
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
            lib.notify({ title = "Error", description = "No online players found", type = 'error', duration = 7000 })
        end
    end)
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
                sendButton = locale('cl_send_button_paid') ..' $'..lPrice
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, default = 'Recipient' },
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

-- Prompt Handling
local function Prompts()
    if not PromptHasHoldModeCompleted(birdPrompt) then return end

    local ped = PlayerPedId()

    if destination < 3 and IsPedOnMount(ped) or IsPedOnVehicle(ped) then
        lib.notify({ title = locale("title_11"), description = locale('cl_player_on_horse'), type = 'error', duration = 7000 })
        Wait(3000)
        return
    end

    TriggerEvent("rsg-telegram:client:ReadMessages")

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

    local blipname = isIncoming and "Incoming Bird Post" or "Outgoing Bird Post"
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

-- Keep blip visible and update during flight
CreateThread(function()
    while true do
        Wait(500)
        
        if cuteBird and DoesEntityExist(cuteBird) and birdBlip then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local birdCoords = GetEntityCoords(cuteBird)
            local distance = #(playerCoords - birdCoords)
            
            if not DoesBlipExist(birdBlip) then
                local blipname = LocalPlayer.state.telegramIsBirdPostApproaching and "Incoming Bird Post" or "Outgoing Bird Post"
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

-- Prompt Thread
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
                lib.notify({ title = "Bird Post", description = "The bird cannot find you inside. Go outside!", type = 'error', duration = 7000 })
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
                lib.notify({ title = "Bird Post", description = "A bird is approaching with a letter!", type = 'info', duration = 7000 })
                Wait(5000)
                lib.notify({ title = "Bird Post", description = "Wait for the bird to land...", type = 'info', duration = 7000 })
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
                TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_WRITE_NOTEBOOK'), -1, true, false, false, false)
                
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
            lib.notify({ title = "Delivery Failed", description = "The bird couldn't deliver the letter", type = 'error', duration = 7000 })
            Wait(3000)
            lib.notify({ title = "Delivery Failed", description = "The letter will be waiting at the post office", type = 'error', duration = 7000 })
            
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

-- Write the Message (using bird post item)
RegisterNetEvent('rsg-telegram:client:WriteMessage', function()
    local selectionMenu = {
        {
            title = "Online Players",
            icon = "fa-solid fa-users",
            description = "Send message to currently online players using a bird",
            event = "rsg-telegram:client:SendToOnlinePlayers",
            args = {}
        },
        {
            title = "Address Book",
            icon = "fa-solid fa-address-book", 
            description = "Send message to saved contacts (stored at post office)",
            event = "rsg-telegram:client:SendToAddressBookViaBird",
            args = {}
        }
    }
    
    lib.registerContext({
        id = "send_message_selection",
        title = "Send Message",
        options = selectionMenu
    })
    lib.showContext("send_message_selection")
end)

-- Send to Address Book via Bird
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
                sendButton = locale('cl_send_button_paid') ..' $'..lPrice
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, default = 'Recipient' },
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
                    content = "Send this letter?\n\nIf recipient is online, they'll get it via bird.\nIf offline, it will be stored at post office.",
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

-- Send to Online Players (using bird post item with bird animation)
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

            ClearPedTasks(ped)
            ClearPedSecondaryTask(ped)
            FreezeEntityPosition(ped, true)
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
                sendButton = locale("cl_send_button_paid", {lPrice = tonumber(Config.CostPerLetter)})
            end

            for i = 1, #players do
                local targetPlayer = players[i]
                local content = { value = targetPlayer.value, label = targetPlayer.label }
                option[#option + 1] = content
            end

            local input = lib.inputDialog(locale('cl_send_message_header'), {
                { type = 'select', options = option, required = true, default = 'Recipient' },
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

-- Read Letter Item
RegisterNetEvent('rsg-telegram:client:ReadLetter')
AddEventHandler('rsg-telegram:client:ReadLetter', function(letterData, slot)
    TriggerServerEvent('rsg-telegram:server:MarkLetterRead', slot)
    
    Wait(500)
    UpdateMailCount()
    
    local letterContent = string.format(
        "**From:** %s  \n" ..
        "**To:** %s  \n" ..
        "**Date:** %s  \n\n" ..
        "---\n\n" ..
        "%s\n\n" ..
        "---",
        letterData.sender or "Unknown",
        letterData.recipient or "You",
        letterData.date or "Unknown",
        letterData.message or "The letter is blank"
    )

    local choice = lib.alertDialog({
        header = '📨 ' .. (letterData.subject or "Letter"),
        content = letterContent,
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Letter Actions',
            cancel = 'Close'
        }
    })
    
    if choice == 'confirm' then
        local actionOptions = {
            {
                title = "Read Again",
                icon = 'fa-solid fa-envelope-open',
                iconColor = 'blue',
                description = "Open the letter again",
                onSelect = function()
                    TriggerEvent('rsg-telegram:client:ReadLetter', letterData, slot)
                end
            },
            {
                title = "Copy Message",
                icon = 'fa-solid fa-copy',
                iconColor = 'green',
                description = "Copy message text to clipboard",
                onSelect = function()
                    lib.setClipboard(letterData.message)
                    lib.notify({ 
                        title = "Copied", 
                        description = "Message copied to clipboard", 
                        type = 'success', 
                        duration = 3000 
                    })
                end
            },
            {
                title = "Burn Letter",
                icon = 'fa-solid fa-fire',
                iconColor = 'red',
                description = "Destroy this letter permanently",
                onSelect = function()
                    local alert = lib.alertDialog({
                        header = 'Burn Letter?',
                        content = 'Are you sure you want to destroy this letter?\n\nThis cannot be undone.',
                        centered = true,
                        cancel = true,
                        labels = {
                            confirm = 'Burn It',
                            cancel = 'Keep It'
                        }
                    })
                    if alert == 'confirm' then
                        TriggerServerEvent('rsg-telegram:server:DestroyLetter', slot)
                        Wait(500)
                        UpdateMailCount()
                    end
                end
            },
            {
                title = "Keep Letter",
                icon = 'fa-solid fa-hand-holding',
                iconColor = 'yellow',
                description = "Store the letter in your inventory",
                onSelect = function()
                    lib.notify({ 
                        title = "Letter Kept", 
                        description = "The letter remains in your inventory", 
                        type = 'info', 
                        duration = 3000 
                    })
                end
            }
        }

        lib.registerContext({
            id = 'letter_actions',
            title = 'Letter Actions',
            options = actionOptions
        })
        lib.showContext('letter_actions')
    end
end)

-- Read the Message
RegisterNetEvent('rsg-telegram:client:ReadMessages')
AddEventHandler('rsg-telegram:client:ReadMessages', function()
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

-- Show Messages List
RegisterNetEvent('rsg-telegram:client:InboxList')
AddEventHandler('rsg-telegram:client:InboxList', function(data)
    local messages = data.list
    
    if not messages or #messages == 0 then
        lib.notify({ 
            title = "Post Office", 
            description = "No messages waiting for you", 
            type = 'info', 
            duration = 5000 
        })
        return
    end

    local options = {}

    for i, msg in ipairs(messages) do
        table.insert(options, {
            title = msg.subject,
            description = "From: " .. msg.sendername .. " | " .. msg.sentDate,
            icon = 'fa-solid fa-envelope',
            iconColor = 'yellow',
            onSelect = function()
                local alert = lib.alertDialog({
                    header = 'Claim Letter?',
                    content = 'This will add the letter to your inventory.\n\nFrom: **'..msg.sendername..'**\nSubject: **'..msg.subject..'**',
                    centered = true,
                    cancel = true,
                    labels = {
                        confirm = 'Claim Letter',
                        cancel = 'Leave It'
                    }
                })
                if alert == 'confirm' then
                    TriggerServerEvent('rsg-telegram:server:ClaimLetter', msg.id)
                end
            end,
            metadata = {
                {label = 'From', value = msg.sendername},
                {label = 'Date', value = msg.sentDate}
            }
        })
    end

    if #messages > 0 then
        table.insert(options, {
            title = "───────────────",
            disabled = true
        })

        table.insert(options, {
            title = "Delete All Messages",
            icon = 'fa-solid fa-trash',
            iconColor = 'red',
            description = "Permanently delete all post office messages",
            onSelect = function()
                local alert = lib.alertDialog({
                    header = 'Delete All?',
                    content = 'This will delete all ' .. #messages .. ' messages permanently.',
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    local count = #messages
                    for _, msg in ipairs(messages) do
                        TriggerServerEvent('rsg-telegram:server:DeleteMessage', msg.id, true)
                    end
                    lib.notify({ 
                        title = "Success", 
                        description = count .. " messages deleted", 
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
        title = '📬 Post Office Messages (' .. #messages .. ')',
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
                { type = 'select', options = option, required = true, default = 'Recipient' }
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

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

---@deprecated use state LocalPlayer.state.telegramIsBirdPostApproaching
exports('IsBirdPostApproaching', function()
    return LocalPlayer.state.telegramIsBirdPostApproaching
end)

CreateThread(function() 
    LocalPlayer.state.telegramIsBirdPostApproaching = false
    repeat Wait(100) until LocalPlayer.state.isLoggedIn

    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getTelegramsAmount', function(amount)
        LocalPlayer.state:set('telegramUnreadMessages', amount or 0, true)
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
            event = "rsg-telegram:client:WriteMessagePostOffice",
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

-- Write Message
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
    -- SET_ATTRIBUTE_POINTS
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 0, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 1, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 2, 1100)

    -- ADD_ATTRIBUTE_POINTS
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 0, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 1, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 2, 1100)

    -- SET_ATTRIBUTE_BASE_RANK
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 0, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 1, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 2, 10)

    -- SET_ATTRIBUTE_BONUS_RANK
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 0, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 1, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 2, 10)

    -- SET_ATTRIBUTE_OVERPOWER_AMOUNT
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 0, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 1, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 2, 5000.0, false)
end

local function SetPetBehavior(entity)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 143493179)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -2040077242)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1222652248)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1077299173)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -887307738)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1998572072)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -661858713)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1232372459)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1836932466)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1878159675)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1078461828)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1535431934)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1862763509)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1663301869)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1448293989)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1201903818)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -886193798)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1996978098)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 555364152)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -2020052692)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 707888648)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 378397108)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -350651841)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1538724068)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1030835986)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1919885972)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1976316465)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 841021282)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 889541022)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1329647920)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -319516747)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -767591988)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -989642646)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1986610512)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1683752762)
end


local SpawnBirdPost = function(posX, posY, posZ, heading, rfar, isIncoming)
    
    local playerPed = PlayerPedId()
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, -100.0, 0.1))
    
    cuteBird = CreatePed(Config.BirdModel, x, y, z + 50.0, heading, 1, 1)
    
   
    while not IsEntityAPed(cuteBird) do
        Citizen.Wait(1)
    end

    SetPetAttributes(cuteBird)

    Citizen.InvokeNative(0x013A7BA5015C1372, cuteBird, true) -- SetPedIgnoreDeadBodies
    Citizen.InvokeNative(0xAEB97D84CDF3C00B, cuteBird, false) -- SetAnimalIsWild

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

    -- Create blip on bird
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
    
    if Config.Debug then
        print("Bird Blip Created: " .. tostring(birdBlip))
    end
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
AddEventHandler('rsg-telegram:client:ReceiveMessage', function(SsID, StPName)
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
                lib.notify({ title = locale("cl_title_11"), description = locale('cl_inside_building'), type = 'error', duration = 7000 })
                buildingNotified = true
            end
            isBirdCanSpawn = false
            goto continue
        end

        
        if isBirdCanSpawn and not isBirdAlreadySpawned then
            SpawnBirdPost(playerCoords.x - 100, playerCoords.y - 100, playerCoords.z + 100, 92.0, rFar, true) -- true = incoming
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
                lib.notify({ title = locale("cl_title_13"), description = locale('cl_bird_approaching'), type = 'info', duration = 7000 })
                Wait(5000)
                lib.notify({ title = locale("cl_title_13"), description = locale('cl_wait_for_bird'), type = 'info', duration = 7000 })
            end

            
            if destination <= 10 and not freezedPlayer then
                FreezeEntityPosition(ped, true)  -- Freeze player
                SetEntityInvincible(ped, true)  -- Make player invincible
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
                
                
                local AttachConfig = Config.BirdAttach["A_C_Hawk_01"]
                local Attach = IsPedMale(PlayerPedId()) and AttachConfig.Male or AttachConfig.Female

                AttachEntityToEntity(
                    cuteBird,
                    PlayerPedId(),
                    Attach[1], -- Bone Index
                    Attach[2], -- xOffset
                    Attach[3], -- yOffset
                    Attach[4], -- zOffset
                    Attach[5], -- xRot
                    Attach[6], -- yRot
                    Attach[7], -- zRot
                    false, false, true, false, 0, true, false, false
                )

               
                ClearPedTasksImmediately(cuteBird)
                SetBlockingOfNonTemporaryEvents(cuteBird, true)
                FreezeEntityPosition(cuteBird, true)

                
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

               
                TriggerServerEvent('rsg-telegram:server:ReadMessage', sID)
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
            lib.notify({ title = locale("cl_title_11"), description = locale('cl_delivery_fail1'), type = 'error', duration = 7000 })
            Wait(8000)
            lib.notify({ title = locale("cl_title_11"), description = locale('cl_delivery_fail2'), type = 'error', duration = 7000 })
            Wait(8000)
            lib.notify({ title = locale("cl_title_11"), description = locale('cl_delivery_fail3'), type = 'error', duration = 7000 })
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


local function GetPlayers(callback)
    RSGCore.Functions.TriggerCallback('rsg-lawman:server:GetPlayers', function(players)
        
        cachedPlayers = players
        
       
        if callback then
            callback(players)
        end
    end)
end

-- Write the Message
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
            description = "Send message to saved contacts (no bird required)",
            event = "rsg-telegram:client:SendToAddressBook",
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


RegisterNetEvent('rsg-telegram:client:SendToOnlinePlayers', function()
    GetPlayers(function(players)
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
            targetCoords = GetEntityCoords(targetPed)
            local coordsOffset = math.random(200, 300)

            local heading = GetEntityHeading(ped)
            local rFar = 30

            TaskWhistleAnim(ped, GetHashKey('WHISTLEHORSELONG'))

            SpawnBirdPost(playerCoords.x, playerCoords.y - rFar, playerCoords.z, heading, rFar, false) -- false = outgoing
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
                        
                        
                        local model = GetEntityModel(cuteBird)
                        local AttachConfig = Config.BirdAttach["A_C_Hawk_01"]
                        local Attach
                        if IsPedMale(PlayerPedId()) then
                            Attach = AttachConfig.Male
                        else
                            Attach = AttachConfig.Female
                        end
                        
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
                    locale('cl_message_prefix')..': '..subject, 
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


RegisterNetEvent('rsg-telegram:client:SendToAddressBook', function()
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

            local recipient = input[1]  -- citizenid for address book
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


RegisterNetEvent('rsg-telegram:client:ReadMessages')
AddEventHandler('rsg-telegram:client:ReadMessages', function()
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

RegisterNetEvent('rsg-telegram:client:InboxList')
AddEventHandler('rsg-telegram:client:InboxList', function(data)
    local messages = data.list
    
    if not messages or #messages == 0 then
        lib.notify({ 
            title = "Inbox", 
            description = "No messages in your inbox", 
            type = 'info', 
            duration = 5000 
        })
        return
    end

    local options = {}

    
    for i, msg in ipairs(messages) do
        local statusIcon = 'fa-solid fa-envelope'
        local statusColor = 'yellow'
        
        if msg.status == 1 and msg.birdstatus == 1 then
            statusIcon = 'fa-solid fa-envelope-open'
            statusColor = 'green'
        end

        table.insert(options, {
            title = msg.subject,
            description = "From: " .. msg.sendername .. " | " .. msg.sentDate,
            icon = statusIcon,
            iconColor = statusColor,
            onSelect = function()
                TriggerServerEvent('rsg-telegram:server:GetMessages', msg.id)
            end,
            metadata = {
                {label = 'From', value = msg.sendername},
                {label = 'Date', value = msg.sentDate},
                {label = 'Status', value = (msg.status == 1 and msg.birdstatus == 1) and 'Read' or 'Unread'}
            }
        })
    end

    
    if #messages > 0 then
        table.insert(options, {
            title = "───────────────",
            disabled = true
        })
        
        table.insert(options, {
            title = "Mark All as Read",
            icon = 'fa-solid fa-check-double',
            iconColor = 'blue',
            onSelect = function()
                for _, msg in ipairs(messages) do
                    TriggerServerEvent('rsg-telegram:server:GetMessages', msg.id)
                end
                lib.notify({ 
                    title = "Success", 
                    description = "All messages marked as read", 
                    type = 'success', 
                    duration = 3000 
                })
                Wait(1000)
                TriggerServerEvent('rsg-telegram:server:CheckInbox')
            end
        })

        table.insert(options, {
            title = "Delete All Messages",
            icon = 'fa-solid fa-trash',
            iconColor = 'red',
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
                        TriggerServerEvent('rsg-telegram:server:DeleteMessage', msg.id, true) -- true = silent (no notification per message)
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
        title = 'Telegram Inbox (' .. #messages .. ')',
        options = options
    })
    lib.showContext('telegram_inbox')
end)

-- Message Data View
RegisterNetEvent('rsg-telegram:client:MessageData')
AddEventHandler('rsg-telegram:client:MessageData', function(tele, msgId)
    currentMessageId = msgId or currentMessageId
    
   
    local messageContent = string.format(
        "━━━━━━━━━━━━━━━━━━━━━\n\n" ..
        "FROM: %s\n" ..
        "TO: %s\n" ..
        "DATE: %s\n\n" ..
        "━━━━━━━━━━━━━━━━━━━━━\n\n" ..
        "%s\n\n" ..
        "━━━━━━━━━━━━━━━━━━━━━",
        tele.sendername,
        tele.recipient,
        tele.sentDate,
        tele.message
    )

    lib.alertDialog({
        header = '📨 ' .. tele.subject,
        content = messageContent,
        centered = true,
        labels = {
            confirm = 'Close Letter'
        }
    })
    
    
    Wait(100)
    
    local actionOptions = {
        {
            title = "Message Actions",
            icon = 'fa-solid fa-gear',
            disabled = true,
            description = "What would you like to do with this message?"
        },
        {
            title = "───────────────",
            disabled = true
        },
        {
            title = "Read Again",
            icon = 'fa-solid fa-envelope-open',
            iconColor = 'blue',
            description = "Open the letter again",
            onSelect = function()
                TriggerServerEvent('rsg-telegram:server:GetMessages', currentMessageId)
            end
        },
        {
            title = "Copy Message",
            icon = 'fa-solid fa-copy',
            iconColor = 'green',
            description = "Copy message text to clipboard",
            onSelect = function()
                lib.setClipboard(tele.message)
                lib.notify({ 
                    title = "Copied", 
                    description = "Message copied to clipboard", 
                    type = 'success', 
                    duration = 3000 
                })
                
                Wait(500)
                TriggerEvent('rsg-telegram:client:MessageData', tele, currentMessageId)
            end
        },
        {
            title = "Delete Message",
            icon = 'fa-solid fa-trash',
            iconColor = 'red',
            description = "Permanently delete this message",
            onSelect = function()
                local alert = lib.alertDialog({
                    header = 'Delete Message?',
                    content = 'Are you sure you want to delete this message from **' .. tele.sendername .. '**?\n\nThis cannot be undone.',
                    centered = true,
                    cancel = true,
                    labels = {
                        confirm = 'Delete',
                        cancel = 'Keep'
                    }
                })
                if alert == 'confirm' then
                    TriggerServerEvent('rsg-telegram:server:DeleteMessage', currentMessageId, false)
                else
                   
                    TriggerEvent('rsg-telegram:client:MessageData', tele, currentMessageId)
                end
            end
        },
        {
            title = "───────────────",
            disabled = true
        },
        {
            title = "Back to Inbox",
            icon = 'fa-solid fa-arrow-left',
            iconColor = 'yellow',
            description = "Return to message list",
            event = 'rsg-telegram:client:ReadMessages'
        }
    }

    lib.registerContext({
        id = 'telegram_message_actions',
        title = '📨 Message Options',
        options = actionOptions
    })
    lib.showContext('telegram_message_actions')
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
                args = {
                    isServer = false
                }
            },
            {
                title = locale("cl_title_20"),
                description = locale("cl_title_21"),
                icon = 'fa-solid fa-book',
                iconColor = 'green',
                event = 'rsg-telegram:client:AddPersonMenu',
                args = {
                    isServer = false
                }
            },
            {
                title = locale("cl_title_22"),
                description = locale("cl_title_23"),
                icon = 'fa-solid fa-book',
                iconColor = 'red',
                event = 'rsg-telegram:client:RemovePersonMenu',
                args = {
                    isServer = false
                }
            },
        }
    })
    lib.showContext('addressbook_menu')
end)

RegisterNetEvent('rsg-telegram:client:AddPersonMenu', function()
    local input = lib.inputDialog(locale("cl_title_24"), {
        { type = 'input', label = locale("cl_title_25"),      required = true },
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
                args = {
                    isServer = false
                }
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
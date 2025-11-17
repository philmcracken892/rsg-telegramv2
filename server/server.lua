local RSGCore = exports['rsg-core']:GetCoreObject()

lib.locale()

------------------------------------------------
-- USABLE ITEMS
------------------------------------------------

-- Make Bird Post as a Usable Item (opens send menu)
RSGCore.Functions.CreateUseableItem('birdpost', function(source)
    TriggerClientEvent('rsg-telegram:client:WriteMessage', source)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:GetPlayers', function(source, cb)
    local players = {}
    
    for _, v in pairs(RSGCore.Functions.GetPlayers()) do
        local Player = RSGCore.Functions.GetPlayer(v)
        if Player then
            local charinfo = Player.PlayerData.charinfo
            local fullName = string.format("%s %s", charinfo.firstname, charinfo.lastname)
            table.insert(players, {
                value = v,
                label = string.format("[%d] %s", v, fullName)
            })
        end
    end
    
    cb(players)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:SearchPlayers', function(source, cb, searchTerm)
    local src = source
    searchTerm = string.lower(searchTerm)
    
    local result = MySQL.query.await([[
        SELECT citizenid, charinfo 
        FROM players 
        WHERE LOWER(citizenid) LIKE @search 
        OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname'))) LIKE @search
        OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE @search
        LIMIT 20
    ]], {
        ['@search'] = '%' .. searchTerm .. '%'
    })
    
    if not result or #result == 0 then
        cb(nil)
        return
    end
    
    local players = {}
    
    for i = 1, #result do
        local charinfo = json.decode(result[i].charinfo)
        local citizenid = result[i].citizenid
        local fullName = charinfo.firstname .. ' ' .. charinfo.lastname
        
        -- Check if player is online
        local onlinePlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
        local isOnline = onlinePlayer ~= nil
        
        table.insert(players, {
            citizenid = citizenid,
            name = fullName,
            online = isOnline
        })
    end
    
    cb(players)
end)

RSGCore.Functions.CreateUseableItem('letter', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local letterData = item.info or {}
    
    if not letterData.sender or not letterData.message then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_letter_error_blank"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end
    
    TriggerClientEvent('rsg-telegram:client:ReadLetter', src, letterData, item.slot)
end)

------------------------------------------------
-- BIRD DELIVERY EVENTS
------------------------------------------------

-- Delivery Success
RegisterNetEvent('rsg-telegram:server:DeliverySuccess')
AddEventHandler('rsg-telegram:server:DeliverySuccess', function(sID, tPName)
    TriggerClientEvent('ox_lib:notify', sID, {
        title = locale("sv_title_38"), 
        description = locale('sv_letter_delivered') .. ' ' .. tPName, 
        type = 'success', 
        duration = 5000 
    })
end)

RegisterServerEvent('rsg-telegram:server:SendMessage')
AddEventHandler('rsg-telegram:server:SendMessage', function(senderID, sender, sendername, tgtid, subject, message)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)

    if RSGPlayer == nil then return end
    
    local targetPlayer = RSGCore.Functions.GetPlayer(tonumber(tgtid))
    if targetPlayer == nil then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_player_unavailable"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    if not Config.AllowSendToSelf and RSGPlayer.PlayerData.source == tonumber(tgtid) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_send_to_self"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_insufficient_balance") .. " ($"..cost..")", 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local hasBirdPost = RSGPlayer.Functions.GetItemByName('birdpost')
    if not hasBirdPost or hasBirdPost.amount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_no_bird_post"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local targetPlayerName = targetPlayer.PlayerData.charinfo.firstname..' '..targetPlayer.PlayerData.charinfo.lastname
    
    local letterInfo = {
        sender = sendername,
        sendercid = sender,
        recipient = targetPlayerName,
        subject = subject,
        message = message,
        date = sentDate,
        unread = true
    }
    
    TriggerClientEvent('rsg-telegram:client:ReceiveMessage', targetPlayer.PlayerData.source, senderID, targetPlayerName, letterInfo)

    RSGPlayer.Functions.RemoveItem('birdpost', 1)
    TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items['birdpost'], "remove", 1)
    
    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send-post')
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale("sv_bird_post_sent") .. " " .. targetPlayerName, 
        type = 'success', 
        duration = 5000 
    })
end)

RegisterServerEvent('rsg-telegram:server:SendMessageToOnlinePlayer')
AddEventHandler('rsg-telegram:server:SendMessageToOnlinePlayer', function(senderID, sender, sendername, tgtid, subject, message)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)

    if RSGPlayer == nil then return end
    
    local targetPlayer = RSGCore.Functions.GetPlayer(tonumber(tgtid))
    if targetPlayer == nil then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_player_unavailable"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    if not Config.AllowSendToSelf and RSGPlayer.PlayerData.source == tonumber(tgtid) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_send_to_self"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_insufficient_balance") .. " ($"..cost..")", 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local targetPlayerName = targetPlayer.PlayerData.charinfo.firstname..' '..targetPlayer.PlayerData.charinfo.lastname
    local targetCitizenId = targetPlayer.PlayerData.citizenid
    
    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?);', 
        {targetCitizenId, targetPlayerName, sender, sendername, subject, sentDate, message})
    
    TriggerClientEvent('ox_lib:notify', targetPlayer.PlayerData.source, {
        title = locale("cl_title_03"), 
        description = string.format(locale("sv_post_office_notify"), sendername), 
        type = 'info', 
        duration = 7000 
    })
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale("sv_letter_sent") .. " " .. targetPlayerName .. ". " .. locale("sv_letter_sent_desc"), 
        type = 'success', 
        duration = 5000 
    })

    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send letter')
    end
end)

-- Send Message to Searched Player (online or offline - always to database)
RegisterServerEvent('rsg-telegram:server:SendToSearchedPlayer')
AddEventHandler('rsg-telegram:server:SendToSearchedPlayer', function(sender, sendername, citizenid, subject, message)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    
    if not RSGPlayer then return end
    
    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_insufficient_balance") .. " ($"..cost..")", 
            type = 'error', 
            duration = 5000 
        })
        return
    end
    
    if not Config.AllowSendToSelf and RSGPlayer.PlayerData.citizenid == citizenid then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_send_to_self"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = @citizenid', {citizenid = citizenid})

    if result[1] == nil then 
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_recipient_not_found"), 
            type = 'error', 
            duration = 5000 
        })
        return 
    end

    local tFirstName = json.decode(result[1].charinfo).firstname
    local tLastName = json.decode(result[1].charinfo).lastname
    local tFullName = tFirstName..' '..tLastName

    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?);', 
        {citizenid, tFullName, sender, sendername, subject, sentDate, message})
    
    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    
    if targetPlayer then
        TriggerClientEvent('ox_lib:notify', targetPlayer.PlayerData.source, {
            title = locale("cl_title_03"), 
            description = string.format(locale("sv_post_office_notify"), sendername), 
            type = 'info', 
            duration = 7000 
        })
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_38"), 
            description = tFullName .. " " .. locale("sv_letter_sent_online"), 
            type = 'success', 
            duration = 5000 
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_38"), 
            description = tFullName .. " " .. locale("sv_letter_sent_offline"), 
            type = 'success', 
            duration = 5000 
        })
    end

    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send letter')
    end
end)

RegisterServerEvent('rsg-telegram:server:GiveLetter')
AddEventHandler('rsg-telegram:server:GiveLetter', function(letterData)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local letterAdded = Player.Functions.AddItem('letter', 1, false, letterData)
    
    if letterAdded then
        TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items['letter'], "add", 1)
        
        TriggerClientEvent('rsg-telegram:client:UpdateMailCount', src)
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_38"), 
            description = locale("sv_letter_received") .. " " .. (letterData.sender or "Unknown") .. ". " .. locale("sv_check_inventory"),
            type = 'success', 
            duration = 7000 
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_inventory_full"), 
            type = 'error', 
            duration = 7000 
        })
        
        local citizenid = Player.PlayerData.citizenid
        exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?)',
            {citizenid, letterData.recipient, letterData.sendercid, letterData.sender, letterData.subject, letterData.date, letterData.message})
    end
end)

RegisterServerEvent('rsg-telegram:server:SaveFailedDelivery')
AddEventHandler('rsg-telegram:server:SaveFailedDelivery', function(letterData)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {citizenid, letterData.recipient, letterData.sendercid, letterData.sender, letterData.subject, letterData.date, letterData.message})
end)

------------------------------------------------
-- LETTER ITEM MANAGEMENT
------------------------------------------------

RegisterServerEvent('rsg-telegram:server:MarkLetterRead')
AddEventHandler('rsg-telegram:server:MarkLetterRead', function(slot)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local item = Player.Functions.GetItemBySlot(slot)
    
    if item and item.name == 'letter' and item.info then
        item.info.unread = false
        
        Player.PlayerData.items[slot] = item
        Player.Functions.SetInventory(Player.PlayerData.items)
        
        if Config.Debug then
            print("^3[TELEGRAM DEBUG]^7 Marked letter in slot " .. slot .. " as read for player " .. src)
        end
        
        Wait(500)
        TriggerClientEvent('rsg-telegram:client:UpdateMailCount', src)
    end
end)

RegisterServerEvent('rsg-telegram:server:DestroyLetter')
AddEventHandler('rsg-telegram:server:DestroyLetter', function(slot)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    Player.Functions.RemoveItem('letter', 1, slot)
    TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items['letter'], "remove", 1)
    
    if Config.Debug then
        print("^3[TELEGRAM DEBUG]^7 Destroyed letter in slot " .. slot .. " for player " .. src)
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale("sv_letter_destroyed"), 
        type = 'info', 
        duration = 3000 
    })
    
    Wait(500)
    TriggerClientEvent('rsg-telegram:client:UpdateMailCount', src)
end)

------------------------------------------------
-- POST OFFICE MESSAGES
------------------------------------------------

RegisterServerEvent('rsg-telegram:server:SendMessagePostOffice')
AddEventHandler('rsg-telegram:server:SendMessagePostOffice', function(sender, sendername, citizenid, subject, message)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_insufficient_balance") .. " ($"..cost..")", 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = @citizenid', {citizenid = citizenid})

    if result[1] == nil then 
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_recipient_not_found"), 
            type = 'error', 
            duration = 5000 
        })
        return 
    end

    local tFirstName = json.decode(result[1].charinfo).firstname
    local tLastName = json.decode(result[1].charinfo).lastname
    local tFullName = tFirstName..' '..tLastName

    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    
    if targetPlayer then
        local letterInfo = {
            sender = sendername,
            sendercid = sender,
            recipient = tFullName,
            subject = subject,
            message = message,
            date = sentDate,
            unread = true
        }
        
        local letterAdded = targetPlayer.Functions.AddItem('letter', 1, false, letterInfo)
        
        if letterAdded then
            TriggerClientEvent('inventory:client:ItemBox', targetPlayer.PlayerData.source, RSGCore.Shared.Items['letter'], "add", 1)
            
            TriggerClientEvent('rsg-telegram:client:UpdateMailCount', targetPlayer.PlayerData.source)
            
            TriggerClientEvent('ox_lib:notify', targetPlayer.PlayerData.source, {
                title = locale("cl_title_03"), 
                description = locale("sv_letter_received") .. " " .. sendername, 
                type = 'info', 
                duration = 7000 
            })
        else
            exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?);', 
                {citizenid, tFullName, sender, sendername, subject, sentDate, message})
            TriggerClientEvent('ox_lib:notify', src, {
                title = locale("cl_title_13"), 
                description = locale("sv_recipient_inventory_full"), 
                type = 'info', 
                duration = 7000 
            })
        end
    else
        exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?);', 
            {citizenid, tFullName, sender, sendername, subject, sentDate, message})
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = string.format(locale("sv_message_sent_post"), tFullName), 
        type = 'success', 
        duration = 5000 
    })

    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send telegram')
    end
end)

RegisterServerEvent('rsg-telegram:server:CheckInbox')
AddEventHandler('rsg-telegram:server:CheckInbox', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if Player == nil then return end

    local citizenid = Player.PlayerData.citizenid

    exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC',{citizenid}, function(result)
        local res = {}
        res['list'] = result or {}
        TriggerClientEvent('rsg-telegram:client:InboxList', src, res)
    end)
end)

RegisterServerEvent('rsg-telegram:server:ClaimLetter')
AddEventHandler('rsg-telegram:server:ClaimLetter', function(messageId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local result = MySQL.query.await('SELECT * FROM telegrams WHERE id = @id', {['@id'] = messageId})
    
    if not result[1] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_message_not_found"), 
            type = 'error', 
            duration = 5000 
        })
        return
    end
    
    local msg = result[1]
    
    local letterInfo = {
        sender = msg.sendername,
        sendercid = msg.sender,
        recipient = msg.recipient,
        subject = msg.subject,
        message = msg.message,
        date = msg.sentDate,
        unread = true
    }
    
    local letterAdded = Player.Functions.AddItem('letter', 1, false, letterInfo)
    
    if letterAdded then
        MySQL.Async.execute('DELETE FROM telegrams WHERE id = @id', {['@id'] = messageId})
        
        TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items['letter'], "add", 1)
        
        TriggerClientEvent('rsg-telegram:client:UpdateMailCount', src)
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_38"), 
            description = locale("sv_letter_claimed"), 
            type = 'success', 
            duration = 5000 
        })
        
        -- FIX: Changed from TriggerServerEvent to triggering CheckInbox directly
        Wait(500)
        local citizenid = Player.PlayerData.citizenid
        exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC',{citizenid}, function(result)
            local res = {}
            res['list'] = result or {}
            TriggerClientEvent('rsg-telegram:client:InboxList', src, res)
        end)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale("sv_inventory_full_claim"), 
            type = 'error', 
            duration = 5000 
        })
    end
end)

RegisterServerEvent('rsg-telegram:server:DeleteMessage')
AddEventHandler('rsg-telegram:server:DeleteMessage', function(tid, silent)
    local src = source
    silent = silent or false

    local result = MySQL.query.await('SELECT * FROM telegrams WHERE id = @id', {['@id'] = tid})

    if result[1] == nil then
        if not silent then
            TriggerClientEvent('ox_lib:notify', src, {
                title = locale("sv_title_39"), 
                description = locale("sv_message_not_found"), 
                type = 'error', 
                duration = 5000 
            })
        end
        return
    end

    MySQL.Async.execute('DELETE FROM telegrams WHERE id = @id', {['@id'] = tid})

    if not silent then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_38"), 
            description = locale("sv_delete_success"), 
            type = 'success', 
            duration = 3000 
        })
        -- FIX: Changed from TriggerServerEvent to triggering CheckInbox directly
        Wait(500)
        local Player = RSGCore.Functions.GetPlayer(src)
        if Player then
            local citizenid = Player.PlayerData.citizenid
            exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC',{citizenid}, function(result)
                local res = {}
                res['list'] = result or {}
                TriggerClientEvent('rsg-telegram:client:InboxList', src, res)
            end)
        end
    end
end)

------------------------------------------------
-- ADDRESS BOOK
------------------------------------------------

RegisterServerEvent('rsg-telegram:server:SavePerson')
AddEventHandler('rsg-telegram:server:SavePerson', function(name, cid)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    while xPlayer == nil do Wait(0) end
    exports.oxmysql:execute('INSERT INTO address_book (`citizenid`, `name`, `owner`) VALUES (?, ?, ?);', {cid, name, xPlayer.PlayerData.citizenid})
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale("sv_contact_added"), 
        type = 'success', 
        duration = 5000 
    })
end)

RegisterServerEvent('rsg-telegram:server:RemovePerson')
AddEventHandler('rsg-telegram:server:RemovePerson', function(cid)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    while xPlayer == nil do Wait(0) end
    MySQL.Async.execute('DELETE FROM address_book WHERE owner like @owner AND citizenid like @citizenid', {
        ['@owner'] = xPlayer.PlayerData.citizenid,
        ['citizenid'] = cid
    })
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale("sv_contact_removed"), 
        type = 'success', 
        duration = 5000 
    })
end)

------------------------------------------------
-- LANGUAGE SYSTEM
------------------------------------------------

RegisterServerEvent('rsg-telegram:server:setLanguage')
AddEventHandler('rsg-telegram:server:setLanguage', function(lang)
    local src = source
    
    if not Config.AllowPlayerLanguageChange then
        TriggerClientEvent('ox_lib:notify', src, {
            title = "Error",
            description = "Language changing is disabled",
            type = 'error',
            duration = 5000
        })
        return
    end
    
    -- Validate language exists
    local validLang = false
    for i = 1, #Config.AvailableLanguages do
        if Config.AvailableLanguages[i].code == lang then
            validLang = true
            break
        end
    end
    
    if not validLang then
        TriggerClientEvent('ox_lib:notify', src, {
            title = "Error",
            description = "Invalid language code",
            type = 'error',
            duration = 5000
        })
        return
    end
    
    TriggerClientEvent('rsg-telegram:client:changeLanguage', src, lang)
end)

------------------------------------------------
-- COMMANDS
------------------------------------------------

-- Language command
if Config.AllowPlayerLanguageChange then
    RSGCore.Commands.Add('language', 'Change telegram language', {}, false, function(source)
        local src = source
        TriggerClientEvent('rsg-telegram:client:openLanguageMenu', src)
    end)
end

RSGCore.Commands.Add('addressbook', locale("sv_command"), {}, false, function(source)
    local src = source
    TriggerClientEvent('rsg-telegram:client:OpenAddressbook', src)
end)

------------------------------------------------
-- CALLBACKS
------------------------------------------------

RSGCore.Functions.CreateCallback('rsg-telegram:server:GetPlayers', function(source, cb)
    local players = {}
    
    for _, v in pairs(RSGCore.Functions.GetPlayers()) do
        local Player = RSGCore.Functions.GetPlayer(v)
        if Player then
            local charinfo = Player.PlayerData.charinfo
            local fullName = string.format("%s %s", charinfo.firstname, charinfo.lastname)
            table.insert(players, {
                value = v,
                label = string.format("[%d] %s", v, fullName),
                citizenid = Player.PlayerData.citizenid,
                name = fullName
            })
        end
    end
    
    cb(players)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:GetPlayersPostOffice', function(source, cb)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    exports.oxmysql:execute('SELECT * FROM `address_book` WHERE owner = @owner ORDER BY name ASC', {
        ['@owner'] = xPlayer.PlayerData.citizenid
    }, function(result)
        if result[1] then
            cb(result)
        else
            cb(nil)
        end
    end)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:getUnreadLetterCount', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player ~= nil then
        local unreadCount = 0
        
        local currentLetters = Player.Functions.GetItemsByName('letter')
        
        if currentLetters then
            for _, letter in pairs(currentLetters) do
                if letter.info and letter.info.unread == true then
                    unreadCount = unreadCount + 1
                end
            end
        end
        
        local dbCount = MySQL.prepare.await('SELECT COUNT(*) FROM telegrams WHERE citizenid = ? AND (status = ? OR birdstatus = ?)', 
            {Player.PlayerData.citizenid, 0, 0})
        
        local totalUnread = unreadCount + (dbCount or 0)
        
        if Config.Debug then
            print("^3[TELEGRAM DEBUG]^7 Player " .. src .. " has " .. unreadCount .. " unread letters in inventory and " .. (dbCount or 0) .. " in post office. Total: " .. totalUnread)
        end
        
        cb(totalUnread)
    else
        cb(0)
    end
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:getTelegramsAmount', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player ~= nil then
        local unreadCount = 0
        
        local currentLetters = Player.Functions.GetItemsByName('letter')
        
        if currentLetters then
            for _, letter in pairs(currentLetters) do
                if letter.info and letter.info.unread == true then
                    unreadCount = unreadCount + 1
                end
            end
        end
        
        local dbCount = MySQL.prepare.await('SELECT COUNT(*) FROM telegrams WHERE citizenid = ? AND (status = ? OR birdstatus = ?)', 
            {Player.PlayerData.citizenid, 0, 0})
        
        local totalUnread = unreadCount + (dbCount or 0)
        cb(totalUnread)
    else
        cb(0)
    end
end)
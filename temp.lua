if not game:IsLoaded() then
    game.Loaded:Wait()
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- === 1. ЗАГРУЗКА БАЗЫ ЦЕН ===
local PRICES_URL = "https://raw.githubusercontent.com/Kenderlike/test/main/prices.json"
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
                break
            end
        end
        task.wait(2)
    end
end)

-- Проверка, что элемент и все его родительские окна реально открыты на экране
local function isActuallyVisible(obj)
    local curr = obj
    while curr and curr ~= PlayerGui do
        if curr:IsA("GuiObject") and not curr.Visible then
            return false
        elseif curr:IsA("ScreenGui") and not curr.Enabled then
            return false
        end
        curr = curr.Parent
    end
    return curr == PlayerGui
end

-- === 2. ПЛАШКА ЦЕНЫ ===
local function updatePriceTag(targetFrame, price)
    if not targetFrame or not targetFrame:IsA("GuiObject") then return end
    local w, h = targetFrame.AbsoluteSize.X, targetFrame.AbsoluteSize.Y
    if w > 500 or h > 500 or w < 20 or h < 20 then return end

    local tag = targetFrame:FindFirstChild("MM2_PriceTag")
    if not tag then
        tag = Instance.new("TextLabel")
        tag.Name = "MM2_PriceTag"
        tag.Size = UDim2.new(1, -4, 0, 16)
        tag.Position = UDim2.new(0.5, 0, 0, 2)
        tag.AnchorPoint = Vector2.new(0.5, 0)
        tag.TextXAlignment = Enum.TextXAlignment.Center
        tag.TextYAlignment = Enum.TextYAlignment.Top
        tag.BackgroundTransparency = 1 
        tag.TextStrokeTransparency = 0.25
        tag.Font = Enum.Font.GothamBlack
        tag.ZIndex = 99999
        tag.Visible = true
        tag.BorderSizePixel = 0
        tag.Parent = targetFrame
    end

    tag.TextSize = (w < 65) and 10 or 13

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

-- Находим строго слот предмета, не трогая кнопки интерфейса
local function getSlotCell(el)
    local cell = el:FindFirstAncestor("NewItem") or el:FindFirstAncestor("ItemFrame")
    if cell then return cell end
    local p = el.Parent
    if p and p:IsA("GuiObject") and (p:FindFirstChild("ItemName") or p:FindFirstChild("Amount") or (p.Parent and p.Parent:FindFirstChild("ItemName"))) then
        return p
    end
    return nil
end

-- === 3. ОБРАБОТКА СЛОТОВ ===
local function processContainer(container, isOffer)
    local sum = 0
    local items = {}
    local processedCells = {}

    if not container then return end

    for _, el in ipairs(container:GetDescendants()) do
        if el:IsA("ImageLabel") and el.Visible then
            local assetId = extractAssetId(el.Image)
            
            if assetId and assetPrices[tostring(assetId)] and isActuallyVisible(el) then
                local cell = getSlotCell(el)
                
                if cell and not processedCells[cell] then
                    processedCells[cell] = true
                    local price = assetPrices[tostring(assetId)]

                    local qty = 1
                    local amountLabel = cell:FindFirstChild("Amount", true)
                    if amountLabel and amountLabel:IsA("TextLabel") and amountLabel.Text ~= "" then
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

local function handleTradeGui(tradeGui)
    if not tradeGui or not tradeGui.Enabled then return end
    
    -- Ждем, пока откроется само окно обмена (чтобы не ломать запрос на трейд)
    local tradeContainer = tradeGui:FindFirstChild("Container")
    if not tradeContainer or not isActuallyVisible(tradeContainer) then return end

    processContainer(tradeContainer, false)

    local tradeBase = tradeContainer:FindFirstChild("Trade")
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

-- === 4. ОСНОВНОЙ ЦИКЛ ===
task.spawn(function()
    while not pricesLoaded do task.wait(0.5) end

    while task.wait(0.5) do
        pcall(function()
            handleTradeGui(PlayerGui:FindFirstChild("TradeGUI"))
            handleTradeGui(PlayerGui:FindFirstChild("TradeGUI_Phone"))

            local mainGui = PlayerGui:FindFirstChild("MainGUI")
            if mainGui and mainGui.Enabled then
                processContainer(mainGui, false)
            end
        end)
    end
end)

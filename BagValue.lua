local pairs, ipairs, tinsert = pairs, ipairs, table.insert
local CreateFrame, GetItemInfo, GetCoinTextureString = CreateFrame, GetItemInfo, GetCoinTextureString
local UIParent, UISpecialFrames = UIParent, UISpecialFrames
local C_Container, C_Timer = C_Container, C_Timer
local NUM_BAG_SLOTS = NUM_BAG_SLOTS
local UIDropDownMenu_CreateInfo, UIDropDownMenu_Initialize, UIDropDownMenu_AddButton, ToggleDropDownMenu =
      UIDropDownMenu_CreateInfo, UIDropDownMenu_Initialize, UIDropDownMenu_AddButton, ToggleDropDownMenu
local GetServerTime = GetServerTime

local addonFullyLoaded = false

ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS or {
    [0] = { r = 0.5, g = 0.5, b = 0.5 },
    [1] = { r = 1.0, g = 1.0, b = 1.0 },
    [2] = { r = 0.0, g = 1.0, b = 0.0 },
    [3] = { r = 0.0, g = 0.0, b = 1.0 },
    [4] = { r = 0.65, g = 0.0, b = 1.0 },
}

local availableFonts = {
    { name = "FrizQT", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
    { name = "Skurri", path = "Fonts\\Skurri.ttf" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
}

local SavedVars
local frameScale
local includedRarities
local excludedItems
local sortMode
local itemLootTimes
local excludedScrollFrame, includedScrollFrame
local excludedScrollChild, includedScrollChild

local rarityCheckboxes = {}
local excludedItemsCheckboxes, includedItemsCheckboxes
local ADDON_NAME, ADDON_TABLE = ...
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")

local frame = CreateFrame("Frame", "BagValueFrame", UIParent)
frame:SetPoint("TOP", UIParent, "TOP", -50, -50)
frame:SetSize(400, 50)
frame:SetScale(1.0)
frame:Show()

local totalValueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
totalValueText:SetPoint("CENTER", frame, "CENTER", 0, 0)

local dropdownMenu = CreateFrame("Frame", "BagValueDropdownMenu", UIParent, "UIDropDownMenuTemplate")

local function GetBagItems()
    local uniqueItems = {}
    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local itemID = info.itemID
                local auctionPrice = Auctionator.API.v1.GetAuctionPriceByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, info.hyperlink)
                local name, _, rarity, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
                if auctionPrice ~= nil then
                    sellPrice = auctionPrice
                end
                if (sellPrice or 0) > 0 then
                    if not uniqueItems[itemID] then
                        uniqueItems[itemID] = {
                            name = name or "Unknown",
                            rarity = rarity or 0,
                            sellPrice = sellPrice or 0,
                            count = info.stackCount,
                            lootTime = itemLootTimes[itemID] or 0
                        }
                    else
                        uniqueItems[itemID].count = uniqueItems[itemID].count + info.stackCount
                        uniqueItems[itemID].lootTime = uniqueItems[itemID].lootTime or 0
                    end
                end
            end
        end
    end
    return uniqueItems
end

local previousBagItems = {}

local function FormatValue(value)
    if SavedVars.useLetters then
        local gold = math.floor(value / 10000)
        local silver = math.floor((value % 10000) / 100)
        local copper = value % 100
        local formatted = ""
        
        if gold > 0 then
            formatted = string.format("|cffffd700%dg|r ", gold)
        end
        if silver > 0 then
            formatted = formatted .. string.format("|cffc7c7cf%ds|r ", silver)
        end
        formatted = formatted .. string.format("|cffeda55f%dc|r", copper)
        return formatted
    else
        return GetCoinTextureString(value)
    end
end

local function UpdateBagValue()
    local totalValue = 0
    local itemsNotCached = false
    local allItems = GetBagItems()

    for itemID, data in pairs(allItems) do
        if not data.sellPrice then
            itemsNotCached = true
        else
            if not excludedItems[itemID] then
                totalValue = totalValue + (data.sellPrice * data.count)
            end
        end
    end

    if itemsNotCached then
        C_Timer.After(0.5, UpdateBagValue)
        return
    end
	
	if SavedVars.includeCurrency then
    totalValue = totalValue + GetMoney()
end


    local valueString = FormatValue(totalValue)
    if SavedVars.showTotalLabel then
        totalValueText:SetText(string.format("|cffFFD100Bag Value:|r |cFFFFFFFF%s|r", valueString))
		totalValueText:SetAlpha(SavedVars.textOpacity)
    else
        totalValueText:SetText(string.format("|cFFFFFFFF%s|r", valueString))
		totalValueText:SetAlpha(SavedVars.textOpacity)
    end
end

local function UpdateCurrencyStatusText()
    if SavedVars.includeCurrency then
        BagValue_SettingsFrame.includedCurrencyStatus:SetText("|cffccccccCurrency Tracking:|r |cff00ff00Enabled|r")
    else
        BagValue_SettingsFrame.includedCurrencyStatus:SetText("|cffccccccCurrency Tracking:|r |cffff0000Disabled|r")
    end
end


local function SortFunction(a, b)
    if sortMode == "value" then
        return (a.sellPrice * a.count) > (b.sellPrice * b.count)
    elseif sortMode == "name" then
        return a.name < b.name
    elseif sortMode == "count" then
        return a.count > b.count
    elseif sortMode == "quality" then
        return a.rarity > b.rarity
    end
    return false
end

local function UpdateRarityCheckboxes()
    local allItems = GetBagItems()
    for rarity, checkbox in pairs(rarityCheckboxes) do
        local itemsOfRarity = {}
        for itemID, data in pairs(allItems) do
            if data.rarity == rarity then
                table.insert(itemsOfRarity, itemID)
            end
        end

        local totalItems = #itemsOfRarity
        local excludedCount = 0

        for _, itemID in ipairs(itemsOfRarity) do
            if excludedItems[itemID] then
                excludedCount = excludedCount + 1
            end
        end

        if totalItems > 0 then
            if excludedCount == totalItems then
                SavedVars.includedRarities[rarity] = false
                checkbox:SetChecked(false)
            elseif excludedCount == 0 then
                SavedVars.includedRarities[rarity] = true
                checkbox:SetChecked(true)
            else
                SavedVars.includedRarities[rarity] = false
                checkbox:SetChecked(false)
            end
        else
            SavedVars.includedRarities[rarity] = false
            checkbox:SetChecked(false)
        end
    end
end

local function RefreshSettingsItemList()
    if not BagValue_SettingsFrame or not BagValue_SettingsFrame:IsShown() then
        return
    end
		
	    if not excludedScrollFrame or not includedScrollFrame then
        return
    end

    for _, child in ipairs({excludedScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, child in ipairs({includedScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    excludedItemsCheckboxes, includedItemsCheckboxes = {}, {}
    local yOffsetExcluded, yOffsetIncluded = -5, -5

    local uniqueItems = GetBagItems()
    local sortedItems = {}

    for itemID, data in pairs(uniqueItems) do
        table.insert(sortedItems, {
            itemID = itemID,
            name = data.name,
            sellPrice = data.sellPrice,
            count = data.count,
            rarity = data.rarity,
            lootTime = data.lootTime
        })
    end

    table.sort(sortedItems, SortFunction)
	
	local excludedCount = 0
    local includedCount = 0
    for itemID, data in pairs(uniqueItems) do
        if excludedItems[itemID] then
            excludedCount = excludedCount + 1
        else
            includedCount = includedCount + 1
        end
    end
	
	if BagValue_SettingsFrame.excludedListTitleCount then
        BagValue_SettingsFrame.excludedListTitleCount:SetText(string.format("(%d)", excludedCount))
    end
    if BagValue_SettingsFrame.includedListTitleCount then
        BagValue_SettingsFrame.includedListTitleCount:SetText(string.format("(%d)", includedCount))
    end

    local ITEM_HEIGHT = 22

    local totalHeightExcluded = 0
    local totalHeightIncluded = 0

    for _, entry in ipairs(sortedItems) do
        local itemID, name, sellPrice, count, rarity, lootTime =
              entry.itemID, entry.name, entry.sellPrice, entry.count, entry.rarity, entry.lootTime

        local color = ITEM_QUALITY_COLORS[rarity] or { r = 1, g = 1, b = 1 }
        local colorCode = string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        local isExcluded = excludedItems[itemID]

        local scrollChild = isExcluded and excludedScrollChild or includedScrollChild
        local yOffset = isExcluded and yOffsetExcluded or yOffsetIncluded

        local itemFrame = CreateFrame("Frame", nil, scrollChild)
        itemFrame:SetSize(260, 20)
        itemFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
        itemFrame:EnableMouse(true)
        itemFrame:SetScript("OnEnter", function(self)
            if itemID then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
                GameTooltip:SetHyperlink("item:"..itemID)
                GameTooltip:Show()
            end
        end)
        itemFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        local itemCheckbox = CreateFrame("CheckButton", nil, itemFrame, "UICheckButtonTemplate")
        itemCheckbox:SetPoint("LEFT", itemFrame, "LEFT", -8, 0)
        itemCheckbox:SetSize(22, 22)

        local countText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		countText:SetPoint("LEFT", itemCheckbox, "RIGHT", 0, 0)
		countText:SetWidth(27)
		countText:SetJustifyH("RIGHT")
		countText:SetText(string.format("%dx", count))
		countText:SetTextColor(0.8, 0.8, 0.8)
		
			local iconTexture = select(10, GetItemInfo(itemID))
		local itemIcon = itemFrame:CreateTexture(nil, "OVERLAY")
		itemIcon:SetSize(16, 16)
		itemIcon:SetPoint("LEFT", countText, "RIGHT", 2, 0)
		itemIcon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

        local nameText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", itemIcon, "RIGHT", 4, 0)
        local maxLength = 24
		if #name > maxLength then
		name = name:sub(1, maxLength - 3) .. "..."
		end
		nameText:SetText(string.format("|cff%s[%s]|r", colorCode, name))

        local valueText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetPoint("RIGHT", itemFrame, "RIGHT", 18, 0)
        valueText:SetText(GetCoinTextureString(sellPrice * count))

        if isExcluded then
            itemCheckbox:SetChecked(false)
            itemCheckbox:SetScript("OnClick", function(self)
                if self:GetChecked() then
                    excludedItems[itemID] = nil
                else
                    excludedItems[itemID] = true
                end
                RefreshSettingsItemList()
                UpdateBagValue()
                UpdateRarityCheckboxes()
            end)
            excludedItemsCheckboxes[itemID] = itemCheckbox
            yOffsetExcluded = yOffsetExcluded - ITEM_HEIGHT
			totalHeightExcluded = totalHeightExcluded + ITEM_HEIGHT
        else
            itemCheckbox:SetChecked(true)
            itemCheckbox:SetScript("OnClick", function(self)
                if not self:GetChecked() then
                    excludedItems[itemID] = true
                else
                    excludedItems[itemID] = nil
                end
                RefreshSettingsItemList()
                UpdateBagValue()
                UpdateRarityCheckboxes()
            end)
            includedItemsCheckboxes[itemID] = itemCheckbox
            yOffsetIncluded = yOffsetIncluded - ITEM_HEIGHT
            totalHeightIncluded = totalHeightIncluded + ITEM_HEIGHT
        end
    end
	
    local function AdjustScrollChild(scrollFrame, scrollChild, totalHeight)
        local visibleHeight = scrollFrame:GetHeight()
        if totalHeight > visibleHeight then
            scrollChild:SetHeight(totalHeight)
            scrollFrame.ScrollBar:Show()
        else
            scrollChild:SetHeight(visibleHeight)
            scrollFrame.ScrollBar:Hide()
        end
    end

    AdjustScrollChild(excludedScrollFrame, excludedScrollChild, totalHeightExcluded)
    AdjustScrollChild(includedScrollFrame, includedScrollChild, totalHeightIncluded)
	
	if excludedScrollFrame and excludedScrollChild then
        AdjustScrollChild(excludedScrollFrame, excludedScrollChild, totalHeightExcluded)
    end

    if includedScrollFrame and includedScrollChild then
        AdjustScrollChild(includedScrollFrame, includedScrollChild, totalHeightIncluded)
    end
	
	UpdateRarityCheckboxes()
end

local function CreateSettingsFrame()
    if BagValue_SettingsFrame and BagValue_SettingsFrame:IsShown() then
        BagValue_SettingsFrame:Show()
        RefreshSettingsItemList()
        return
    end

    BagValue_SettingsFrame = CreateFrame("Frame", "BagValue_SettingsFrame", UIParent, "PortraitFrameTemplate")
    tinsert(UISpecialFrames, "BagValue_SettingsFrame")

    BagValue_SettingsFrame:SetFrameStrata("DIALOG")
    BagValue_SettingsFrame:SetSize(700, 500)
    BagValue_SettingsFrame:SetPoint("CENTER")
    BagValue_SettingsFrame:EnableMouse(true)
    BagValue_SettingsFrame:SetMovable(true)
    BagValue_SettingsFrame:RegisterForDrag("LeftButton")
    BagValue_SettingsFrame:SetScript("OnDragStart", BagValue_SettingsFrame.StartMoving)
    BagValue_SettingsFrame:SetScript("OnDragStop", BagValue_SettingsFrame.StopMovingOrSizing)

	BagValue_SettingsFrame.TitleText:SetText(string.format("BagValue Settings |cFFAAAAAAv%s|r", ADDON_VERSION))
	
	BagValue_SettingsFrame.portrait:SetTexture("Interface\\AddOns\\BagValue\\Textures\\BagValueIcon")
	BagValue_SettingsFrame.portrait:SetSize(60, 60)
	BagValue_SettingsFrame.portrait:SetPoint("LEFT", BagValue_SettingsFrame, "TOPLEFT", 5, -5)



    local mainInfoIcon = BagValue_SettingsFrame:CreateTexture(nil, "OVERLAY")
    mainInfoIcon:SetTexture("Interface\\AddOns\\BagValue\\Textures\\BagValueInfo")
    mainInfoIcon:SetSize(21, 21)
    mainInfoIcon:SetPoint("LEFT", BagValue_SettingsFrame.TitleText, "RIGHT", 28, -30)
    mainInfoIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("|cffffd700BagValue displays the total value of your inventory, updating dynamically as items and currency come and go or as you change settings.|r\n\n|cffffd700Text Appearance|r\nCustomize the text frame, adjust its position, scale, style, outline and opacity.\n\n|cffffd700Filters & Sort Lists|r\nCheckboxes adjust based on your inventory and settings. Filter currency or item categories based on quality. Sort the included and excluded lists using different criteria.\n\n|cffffd700Included & Excluded Lists:|r\nTrack specific items by moving them between the lists. New items are included by default and changes are saved automatically.", 1, 1, 1, true)
        GameTooltip:SetScale(0.9)
        GameTooltip:Show()
    end)
    mainInfoIcon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

local settingsBackground = CreateFrame("Frame", nil, BagValue_SettingsFrame, "InsetFrameTemplate")
	settingsBackground:SetPoint("LEFT", BagValue_SettingsFrame, "LEFT", 40, 105)
	settingsBackground:SetPoint("RIGHT", BagValue_SettingsFrame, "RIGHT", -269, 105)
    settingsBackground:SetHeight(130)

local itemsBackground = CreateFrame("Frame", nil, BagValue_SettingsFrame, "InsetFrameTemplate")
	itemsBackground:SetPoint("LEFT", BagValue_SettingsFrame, "LEFT", 438, 105)
	itemsBackground:SetPoint("RIGHT", BagValue_SettingsFrame, "RIGHT", -40, 105)
    itemsBackground:SetHeight(130)

    local generalSettingsTitle = BagValue_SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    generalSettingsTitle:SetPoint("TOPLEFT", BagValue_SettingsFrame, "BOTTOMLEFT", 40, 440)
    generalSettingsTitle:SetText("Text Appearance")
    generalSettingsTitle:SetTextColor(1, 0.82, 0)
    generalSettingsTitle:SetFont("Fonts\\FRIZQT__.TTF", 14)

    local lockCheckbox = CreateFrame("CheckButton", nil, BagValue_SettingsFrame, "UICheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", BagValue_SettingsFrame, "BOTTOMLEFT", 50, 410)
    lockCheckbox.text = lockCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lockCheckbox.text:SetPoint("LEFT", lockCheckbox, "RIGHT", 5, 0)
    lockCheckbox.text:SetText("Lock Text")
    lockCheckbox:SetChecked(SavedVars.locked)
    lockCheckbox:SetScript("OnClick", function(self)
        SavedVars.locked = self:GetChecked()
    end)
    BagValue_SettingsFrame.lockCheckbox = lockCheckbox
	
local useLettersCheckbox = CreateFrame("CheckButton", nil, BagValue_SettingsFrame, "UICheckButtonTemplate")
useLettersCheckbox:SetPoint("LEFT", lockCheckbox, "RIGHT", -32, -80)
useLettersCheckbox.text = useLettersCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
useLettersCheckbox.text:SetPoint("LEFT", useLettersCheckbox, "RIGHT", 5, 0)
useLettersCheckbox.text:SetText("Value Format")
useLettersCheckbox:SetChecked(SavedVars.useLetters)
useLettersCheckbox:SetScript("OnClick", function(self)
    SavedVars.useLetters = self:GetChecked()
    UpdateBagValue()
end)
BagValue_SettingsFrame.useLettersCheckbox = useLettersCheckbox
useLettersCheckbox:SetChecked(SavedVars.useLetters)

local outlineOptions = {
    { text = "None", value = "NONE" },
    { text = "Outline", value = "OUTLINE" },
    { text = "Monochrome", value = "MONOCHROME" },
    { text = "MonoOutline", value = "MONOCHROME,OUTLINE" },
    { text = "ThickOutline", value = "THICKOUTLINE" },
}

local valueToTextMap = {}
for _, option in ipairs(outlineOptions) do
    valueToTextMap[option.value] = option.text
end

local function GetOutlineTextByValue(value)
    return valueToTextMap[value] or "OUTLINE"
end

local outlineDropdown = CreateFrame("Frame", "BagValueOutlineDropdown", BagValue_SettingsFrame, "UIDropDownMenuTemplate")
outlineDropdown:SetPoint("LEFT", useLettersCheckbox, "RIGHT", 70, 0)
UIDropDownMenu_SetWidth(outlineDropdown, 101)

local fontDropdown = CreateFrame("Frame", "BagValueFontDropdown", BagValue_SettingsFrame, "UIDropDownMenuTemplate")
fontDropdown:SetPoint("LEFT", useLettersCheckbox, "RIGHT", 70, 60)
UIDropDownMenu_SetWidth(fontDropdown, 101)

local outlineLabel = BagValue_SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
outlineLabel:SetPoint("TOP", outlineDropdown, "TOP", -23, 13)
outlineLabel:SetText("Text Outline:")
outlineLabel:SetTextColor(1, 0.82, 0)

local fontLabel = BagValue_SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
fontLabel:SetPoint("TOP", fontDropdown, "TOP", -30, 13)
fontLabel:SetText("Font Style:")
fontLabel:SetTextColor(1, 0.82, 0)

local function OnOutlineSelect(self)

    SavedVars.fontOutline = self.value

    UIDropDownMenu_SetSelectedValue(outlineDropdown, self.value)
    UIDropDownMenu_SetText(outlineDropdown, self:GetText())

    if totalValueText then
        local font, size, flags = totalValueText:GetFont()
        totalValueText:SetFont(font, size, SavedVars.fontOutline)
    end
end

local function OnFontSelect(self)

    SavedVars.selectedFont = self.value

    UIDropDownMenu_SetSelectedValue(fontDropdown, self.value)
    UIDropDownMenu_SetText(fontDropdown, self:GetText())

    if totalValueText then
        local _, size, flags = totalValueText:GetFont()
        totalValueText:SetFont(SavedVars.selectedFont, size, SavedVars.fontOutline)
    end
end

local function InitializeOutlineDropdown(self, level)
    for _, option in ipairs(outlineOptions) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.text
        info.value = option.value
        info.func = OnOutlineSelect
        info.checked = (SavedVars.fontOutline == option.value)
        UIDropDownMenu_AddButton(info, level)
    end
end

local function InitializeFontDropdown(self, level)
    for _, font in ipairs(availableFonts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = font.name
        info.value = font.path
        info.func = OnFontSelect
        info.checked = (SavedVars.selectedFont == font.path)
        UIDropDownMenu_AddButton(info, level)
    end
end


UIDropDownMenu_Initialize(outlineDropdown, InitializeOutlineDropdown)
UIDropDownMenu_SetSelectedValue(outlineDropdown, SavedVars.fontOutline)
UIDropDownMenu_SetText(outlineDropdown, GetOutlineTextByValue(SavedVars.fontOutline) or "OUTLINE")

UIDropDownMenu_Initialize(fontDropdown, InitializeFontDropdown)

local selectedFontName
for _, font in ipairs(availableFonts) do
    if font.path == SavedVars.selectedFont then
        selectedFontName = font.name
        break
    end
end

UIDropDownMenu_SetSelectedValue(fontDropdown, SavedVars.selectedFont)
UIDropDownMenu_SetText(fontDropdown, selectedFontName or "FrizQT")





    local showLabelCheckbox = CreateFrame("CheckButton", nil, BagValue_SettingsFrame, "UICheckButtonTemplate")
    showLabelCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -22)
    showLabelCheckbox.text = showLabelCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    showLabelCheckbox.text:SetPoint("LEFT", showLabelCheckbox, "RIGHT", 5, 0)
    showLabelCheckbox.text:SetText("Show Label")
    showLabelCheckbox:SetChecked(SavedVars.showTotalLabel)
    showLabelCheckbox:SetScript("OnClick", function(self)
        SavedVars.showTotalLabel = self:GetChecked()
        UpdateBagValue()
    end)

    local showHideCheckbox = CreateFrame("CheckButton", nil, BagValue_SettingsFrame, "UICheckButtonTemplate")
    showHideCheckbox:SetPoint("TOPLEFT", showLabelCheckbox, "BOTTOMLEFT", 0, 59)
    showHideCheckbox.text = showHideCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    showHideCheckbox.text:SetPoint("LEFT", showHideCheckbox, "RIGHT", 5, 0)
    showHideCheckbox.text:SetText("Show Text")
    showHideCheckbox:SetChecked(not SavedVars.hideAddon)
    showHideCheckbox:SetScript("OnClick", function(self)
        SavedVars.hideAddon = not self:GetChecked()
        if SavedVars.hideAddon then
            frame:Hide()
        else
            frame:Show()
        end
    end)
	
    local textScaleSlider = CreateFrame("Slider", "BagValue_TextScaleSlider", BagValue_SettingsFrame, BackdropTemplateMixin and "BackdropTemplate")
    textScaleSlider:SetOrientation("HORIZONTAL")
    textScaleSlider:SetSize(116, 16)
    textScaleSlider:SetPoint("LEFT", lockCheckbox, "RIGHT", 220, -17)
    textScaleSlider:SetMinMaxValues(0.5, 2)
    textScaleSlider:SetValueStep(0.05)
    textScaleSlider:SetObeyStepOnDrag(true)
    textScaleSlider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UUI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    textScaleSlider:SetBackdropColor(0, 0, 0, 0.5)

    local thumb = textScaleSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(30, 30)
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    textScaleSlider:SetThumbTexture(thumb)
  
    local text = textScaleSlider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("BOTTOM", textScaleSlider, "TOP", -28, 2)
    text:SetText("Text Scale:")
    text:SetTextColor(1.00, 0.82, 0.00)
	
	local scaleValueText = textScaleSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	scaleValueText:SetPoint("LEFT", textScaleSlider, "RIGHT", -20, 15)
	scaleValueText:SetText(string.format("%.1f", SavedVars.textScale or 1.0))

    textScaleSlider:SetValue(SavedVars.textScale or 1.0)
    textScaleSlider:SetScript("OnValueChanged", function(_, value)
        SavedVars.textScale = value
        frame:SetScale(value)
		scaleValueText:SetText(string.format("%.1f", value))
    end)
	
local textOpacitySlider = CreateFrame("Slider", "BagValue_TextOpacitySlider", BagValue_SettingsFrame, BackdropTemplateMixin and "BackdropTemplate")
textOpacitySlider:SetOrientation("HORIZONTAL")
textOpacitySlider:SetSize(116, 16)
textOpacitySlider:SetPoint("TOP", textScaleSlider, "TOP", 0, -60)
textOpacitySlider:SetMinMaxValues(0.0, 1.0)
textOpacitySlider:SetValueStep(0.05)
textOpacitySlider:SetObeyStepOnDrag(true)
textOpacitySlider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
})
textOpacitySlider:SetBackdropColor(0, 0, 0, 0.5)

local opacityThumb = textOpacitySlider:CreateTexture(nil, "OVERLAY")
opacityThumb:SetSize(30, 30)
opacityThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
textOpacitySlider:SetThumbTexture(opacityThumb)

local opacityLabel = textOpacitySlider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
opacityLabel:SetPoint("BOTTOM", textOpacitySlider, "TOP", -21, 2)
opacityLabel:SetText("Text Opacity:")
opacityLabel:SetTextColor(1.00, 0.82, 0.00)

local opacityValueText = textOpacitySlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
opacityValueText:SetPoint("LEFT", textOpacitySlider, "RIGHT", -20, 15)
opacityValueText:SetText(string.format("%.1f", SavedVars.textOpacity or 1.0))

textOpacitySlider:SetValue(SavedVars.textOpacity or 1.0)
textOpacitySlider:SetScript("OnValueChanged", function(_, value)
    SavedVars.textOpacity = value
    totalValueText:SetAlpha(value)
    opacityValueText:SetText(string.format("%.1f", value))
end)


    local itemQualityTitle = BagValue_SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    itemQualityTitle:SetPoint("TOPLEFT", BagValue_SettingsFrame, "BOTTOMLEFT", 437, 440)
    itemQualityTitle:SetText("Filters & Sort Lists")
    itemQualityTitle:SetTextColor(1, 0.82, 0)
    itemQualityTitle:SetFont("Fonts\\FRIZQT__.TTF", 14)

local raritiesFrame = CreateFrame("Frame", nil, BagValue_SettingsFrame)
raritiesFrame:SetPoint("TOPLEFT", BagValue_SettingsFrame, "BOTTOMLEFT", 0, 282)
raritiesFrame:SetSize(600, 200)

local rarities = {
    { rarity = 0, label = "|cff9d9d9d Junk|r" },
    { rarity = 1, label = "|cffffffff Common|r" },
    { rarity = 2, label = "|cff1eff00 Uncommon|r" },
    { rarity = 3, label = "|cff0070dd Rare|r" },
    { rarity = 4, label = "|cffa335ee Epic|r" }
}

local columns, spacingX, spacingY = 2, 95, -27
local startX, startY = 447, 128

for i, data in ipairs(rarities) do
    local col, row

    if i <= 2 then
        col = 0
        row = i - 1
    else
        col = 1
        row = i - 3
    end

    local xOffset = startX + (col * spacingX)
    local yOffset = startY + (row * spacingY)

    local rarityCheckbox = CreateFrame("CheckButton", nil, raritiesFrame, "UICheckButtonTemplate")
    rarityCheckbox:SetPoint("TOPLEFT", raritiesFrame, "TOPLEFT", xOffset, yOffset)
    rarityCheckbox.text = rarityCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rarityCheckbox.text:SetPoint("LEFT", rarityCheckbox, "RIGHT", 2, 0)
    rarityCheckbox.text:SetText(data.label)
    rarityCheckbox:SetChecked(SavedVars.includedRarities[data.rarity])
    rarityCheckboxes[data.rarity] = rarityCheckbox

    rarityCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        SavedVars.includedRarities[data.rarity] = isChecked
        local allItems = GetBagItems()

        for itemID, itemData in pairs(allItems) do
            if itemData.rarity == data.rarity then
                if isChecked then
                    excludedItems[itemID] = nil
                else
                    excludedItems[itemID] = true
                end
            end
        end
        UpdateBagValue()
        RefreshSettingsItemList()
        UpdateRarityCheckboxes()
    end)
end

    local includeCurrencyCheckbox = CreateFrame("CheckButton", nil, BagValue_SettingsFrame, "UICheckButtonTemplate")
includeCurrencyCheckbox:SetPoint("TOPLEFT", raritiesFrame, "TOPLEFT", 447, 74)
    includeCurrencyCheckbox.text = includeCurrencyCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    includeCurrencyCheckbox.text:SetPoint("LEFT", includeCurrencyCheckbox, "RIGHT", 5, 0)
includeCurrencyCheckbox.text:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:16:16|t " ..
                                       "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16|t " ..
                                       "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16|t")
    includeCurrencyCheckbox:SetChecked(SavedVars.includeCurrency)
    includeCurrencyCheckbox:SetScript("OnClick", function(self)
        SavedVars.includeCurrency = self:GetChecked()
		UpdateCurrencyStatusText()
        UpdateBagValue()
    end)
    BagValue_SettingsFrame.includeCurrencyCheckbox = includeCurrencyCheckbox
	
includeCurrencyCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Currency Filter", 1, 0.82, 0)
    GameTooltip:AddLine("As currency isn’t an item, it's tracked separately. Use this toggle to set tracking to |cff00ff00Enabled|r or |cffff0000Disabled|r, as indicated on the status text below.", 1, 1, 1, true)
    GameTooltip:SetScale(0.9)
	GameTooltip:Show()
end)

includeCurrencyCheckbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
	

excludedFrame = CreateFrame("Frame", nil, BagValue_SettingsFrame, "InsetFrameTemplate")
excludedFrame:SetSize(300, 220)
	excludedFrame:SetPoint("LEFT", BagValue_SettingsFrame, "LEFT", 40, -100)

excludedScrollFrame = CreateFrame("ScrollFrame", nil, excludedFrame, "UIPanelScrollFrameTemplate")
excludedScrollFrame:SetSize(300, 220)
excludedScrollFrame:SetPoint("TOPLEFT", 5, -5)
excludedScrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)

excludedScrollChild = CreateFrame("Frame", nil, excludedScrollFrame)
excludedScrollChild:SetSize(300, 220)
excludedScrollFrame:SetScrollChild(excludedScrollChild)

BagValue_SettingsFrame.excludedListTitleLabel = excludedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
BagValue_SettingsFrame.excludedListTitleLabel:SetPoint("TOPLEFT", BagValue_SettingsFrame, "BOTTOMLEFT", 40, 280)
BagValue_SettingsFrame.excludedListTitleLabel:SetText("Excluded List ")
BagValue_SettingsFrame.excludedListTitleLabel:SetTextColor(1, 0.82, 0)
BagValue_SettingsFrame.excludedListTitleLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)

BagValue_SettingsFrame.excludedListTitleCount = excludedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
BagValue_SettingsFrame.excludedListTitleCount:SetPoint("LEFT", BagValue_SettingsFrame.excludedListTitleLabel, "RIGHT", 0, 0)
BagValue_SettingsFrame.excludedListTitleCount:SetText("(0)")
BagValue_SettingsFrame.excludedListTitleCount:SetTextColor(0.8, 0.8, 0.8)
BagValue_SettingsFrame.excludedListTitleCount:SetFont("Fonts\\FRIZQT__.TTF", 12)

includedFrame = CreateFrame("Frame", nil, BagValue_SettingsFrame, "InsetFrameTemplate")
includedFrame:SetSize(300, 220)
includedFrame:SetPoint("RIGHT", BagValue_SettingsFrame, "RIGHT", -40, -100)

includedScrollFrame = CreateFrame("ScrollFrame", nil, includedFrame, "UIPanelScrollFrameTemplate")
includedScrollFrame:SetSize(300, 220)
includedScrollFrame:SetPoint("TOPLEFT", 5, -5)
includedScrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)

includedScrollChild = CreateFrame("Frame", nil, includedScrollFrame)
includedScrollChild:SetSize(300, 220)
includedScrollFrame:SetScrollChild(includedScrollChild)

BagValue_SettingsFrame.includedListTitleLabel = includedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
BagValue_SettingsFrame.includedListTitleLabel:SetPoint("TOPLEFT", BagValue_SettingsFrame, "BOTTOMLEFT", 360, 280)
BagValue_SettingsFrame.includedListTitleLabel:SetText("Included List ")
BagValue_SettingsFrame.includedListTitleLabel:SetTextColor(1, 0.82, 0)
BagValue_SettingsFrame.includedListTitleLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)

BagValue_SettingsFrame.includedListTitleCount = includedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
BagValue_SettingsFrame.includedListTitleCount:SetPoint("LEFT", BagValue_SettingsFrame.includedListTitleLabel, "RIGHT", 0, 0)
BagValue_SettingsFrame.includedListTitleCount:SetText("(0)")
BagValue_SettingsFrame.includedListTitleCount:SetTextColor(0.8, 0.8, 0.8)
BagValue_SettingsFrame.includedListTitleCount:SetFont("Fonts\\FRIZQT__.TTF", 12)

BagValue_SettingsFrame.includedCurrencyStatus = BagValue_SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
BagValue_SettingsFrame.includedCurrencyStatus:SetPoint("LEFT", BagValue_SettingsFrame.includedListTitleLabel, "RIGHT", 68, 0)

    local excludeAllButton = CreateFrame("Button", nil, BagValue_SettingsFrame, "GameMenuButtonTemplate")
    excludeAllButton:SetPoint("LEFT", excludedScrollFrame, "RIGHT", -84, -124)
    excludeAllButton:SetSize(90, 24)
	excludeAllButton:SetNormalFontObject("GameFontNormal")
	excludeAllButton:SetHighlightFontObject("GameFontHighlight")
    excludeAllButton:SetText("Exclude All")
    excludeAllButton:SetScript("OnClick", function()
        local allItems = GetBagItems()
        for itemID in pairs(allItems) do
            excludedItems[itemID] = true
        end
        for rarity, checkbox in pairs(rarityCheckboxes) do
            checkbox:SetChecked(false)
            SavedVars.includedRarities[rarity] = false
        end
        UpdateBagValue()
        RefreshSettingsItemList()
    end)

    local includeAllButton = CreateFrame("Button", nil, BagValue_SettingsFrame, "GameMenuButtonTemplate")
    includeAllButton:SetPoint("LEFT", includedScrollFrame, "RIGHT", -297, -124)
    includeAllButton:SetSize(90, 24)
	includeAllButton:SetNormalFontObject("GameFontNormal")
	includeAllButton:SetHighlightFontObject("GameFontHighlight")
    includeAllButton:SetText("Include All")
    includeAllButton:SetScript("OnClick", function()
        for itemID in pairs(excludedItems) do
            excludedItems[itemID] = nil
        end
        for rarity, checkbox in pairs(rarityCheckboxes) do
            checkbox:SetChecked(true)
            SavedVars.includedRarities[rarity] = true
        end
        UpdateBagValue()
        RefreshSettingsItemList()
    end)

local sortDropdown = CreateFrame("Frame", "BagValueSortDropdown", BagValue_SettingsFrame, "UIDropDownMenuTemplate")
sortDropdown:SetPoint("TOP", outlineDropdown, "TOP", 321, -15)
UIDropDownMenu_SetWidth(sortDropdown, 205)

local savedText = SavedVars.sortText or "Sort By"
UIDropDownMenu_SetText(sortDropdown, savedText)

local sortOptions = {
    { text = "Sort by Value", value = "value" },
    { text = "Sort by Name", value = "name" },
    { text = "Sort by Count", value = "count" },
    { text = "Sort by Quality", value = "quality" },
}

local function OnSelect(self, arg1)
    sortMode = arg1
    SavedVars.sortMode = sortMode
    SavedVars.sortText = self:GetText()
    UIDropDownMenu_SetText(sortDropdown, self:GetText())
    RefreshSettingsItemList()
end

local function InitializeDropdown(self, level)
    for _, option in ipairs(sortOptions) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.text
        info.arg1 = option.value
        info.func = OnSelect
		info.minWidth = 205
        info.checked = (sortMode == option.value)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(sortDropdown, InitializeDropdown)

	UpdateCurrencyStatusText()

    RefreshSettingsItemList()
end

local function ShowDropdownMenu(_, button)
    if button == "RightButton" then
        local menu = {
            {
                text = SavedVars.locked and "Unlock Text" or "Lock Text",
                func = function()
                    SavedVars.locked = not SavedVars.locked
                    if BagValue_SettingsFrame and BagValue_SettingsFrame.lockCheckbox then
                        BagValue_SettingsFrame.lockCheckbox:SetChecked(SavedVars.locked)
                    end
                end,
                notCheckable = true
            },
            {
                text = "Settings",
                func = function() CreateSettingsFrame() end,
                notCheckable = true
            }
        }

        local function InitializeDropdown(_, level)
            for _, item in ipairs(menu) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.func = item.func
                info.notCheckable = item.notCheckable
                UIDropDownMenu_AddButton(info, level)
            end
        end

        UIDropDownMenu_Initialize(dropdownMenu, InitializeDropdown, "MENU")
        ToggleDropDownMenu(1, nil, dropdownMenu, "cursor", 0, 0)
    end
end

frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if not SavedVars.locked then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    SavedVars.point = point
    SavedVars.relativePoint = relativePoint
    SavedVars.xOfs = xOfs
    SavedVars.yOfs = yOfs
end)
frame:SetScript("OnMouseDown", ShowDropdownMenu)

local function UpdateLootTimes()
    if not addonFullyLoaded then
        return
    end
    local currentBagItems = GetBagItems()

    for itemID in pairs(excludedItems) do
        if not currentBagItems[itemID] then
            excludedItems[itemID] = nil
        end
    end

    for itemID, data in pairs(currentBagItems) do
        if not previousBagItems[itemID] then
            itemLootTimes[itemID] = GetServerTime()
        else
            itemLootTimes[itemID] = itemLootTimes[itemID] or previousBagItems[itemID].lootTime or 0
        end
    end

    SavedVars.itemLootTimes = itemLootTimes
    previousBagItems = currentBagItems
end

SLASH_BAGVALUE1 = "/bagvalue"
SLASH_BAGVALUE2 = "/bv"
SlashCmdList["BAGVALUE"] = function()
    CreateSettingsFrame()
end

local function HandleEvent(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        BagValue_SavedVars = BagValue_SavedVars or {}
        SavedVars = BagValue_SavedVars

        SavedVars.includedRarities = SavedVars.includedRarities or {
            [0] = true,
            [1] = true,
            [2] = true,
            [3] = true,
            [4] = true
        }
        SavedVars.textScale = SavedVars.textScale or 1.0
        SavedVars.locked = SavedVars.locked or false
        SavedVars.excludedItems = SavedVars.excludedItems or {}
        SavedVars.showTotalLabel = (SavedVars.showTotalLabel == nil) and true or SavedVars.showTotalLabel
        SavedVars.sortMode = SavedVars.sortMode or "value"
        SavedVars.hideAddon = SavedVars.hideAddon or false
        SavedVars.itemLootTimes = SavedVars.itemLootTimes or {}
		SavedVars.useLetters = SavedVars.useLetters or false
		SavedVars.fontOutline = SavedVars.fontOutline or "OUTLINE"
		SavedVars.selectedFont = SavedVars.selectedFont or "Fonts\\FRIZQT__.TTF"
		SavedVars.textOpacity = SavedVars.textOpacity or 1.0
		SavedVars.includeCurrency = SavedVars.includeCurrency or false



        frameScale = SavedVars.textScale
        includedRarities = SavedVars.includedRarities
        excludedItems = SavedVars.excludedItems
        sortMode = SavedVars.sortMode
        itemLootTimes = SavedVars.itemLootTimes

        frame:SetScale(frameScale)
        if SavedVars.point then
            frame:ClearAllPoints()
            frame:SetPoint(SavedVars.point, UIParent, SavedVars.relativePoint, SavedVars.xOfs, SavedVars.yOfs)
        end
        if SavedVars.hideAddon then
            frame:Hide()
        else
            frame:Show()
        end
		
		if totalValueText then
    local _, size, flags = totalValueText:GetFont()
    totalValueText:SetFont(SavedVars.selectedFont, size, SavedVars.fontOutline)
end



        self:RegisterEvent("PLAYER_ENTERING_WORLD")

        UpdateBagValue()
        previousBagItems = GetBagItems()

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            addonFullyLoaded = true
            UpdateBagValue()
            UpdateLootTimes()
            if BagValue_SettingsFrame and BagValue_SettingsFrame:IsShown() then
                RefreshSettingsItemList()
            end
        end)

    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateBagValue()
        UpdateLootTimes()
        if BagValue_SettingsFrame and BagValue_SettingsFrame:IsShown() then
            RefreshSettingsItemList()
        end
    end
end

frame:SetScript("OnEvent", HandleEvent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")

print("|cffffd700BagValue|r loaded. Settings: |cffffd700/bagvalue|r or |cffffd700/bv|r")
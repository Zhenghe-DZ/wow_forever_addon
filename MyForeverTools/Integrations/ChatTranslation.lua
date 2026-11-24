local ct = ChatTranslator
if not (ct and ct.Engine and ct.Packs and ct.Script and ct.Incoming and ct.IsSecret) then return end

local settings, dialog, panelButton
local cache = {}

local function LanguageName(code)
    if code == "en" then return "English" end
    return ct.LANGS[code].nativeName
end

local function LoadPair()
    for _, code in ipairs({ settings.from, settings.to }) do
        if code ~= "en" then ct.Packs.Want(code, "MyForeverTools") end
    end
end

local function TranslateStep(text, from, to)
    if not ct.Engine.CanTranslate(from, to) then return end
    local result, stats = ct.Engine.Translate(text, from, to)
    if stats.changed and stats.words > 0 and stats.hit / stats.words >= ct.Engine.MIN_HIT_RATIO then
        return result
    end
end

local function Translate(text, from, to)
    if from == "en" or to == "en" then return TranslateStep(text, from, to) end
    local english = TranslateStep(text, from, "en")
    if english then return TranslateStep(english, "en", to) end
end

local function Filter(frame, event, text, sender, _, channelName, _, _, zoneID, _, channelBase, _, lineID, guid)
    local db = ChatTranslatorDB
    if not settings.incoming or not db or db.enabled == false or event == "CHAT_MSG_WHISPER_INFORM" then return end
    if ct.IsSecret(text, sender, channelName, zoneID, channelBase, lineID, guid) then return end
    if type(text) ~= "string" or text == "" or (guid and guid == ct.playerGUID) then return end
    if lineID and lineID ~= 0 and C_ChatInfo and C_ChatInfo.IsChatLineCensored
        and C_ChatInfo.IsChatLineCensored(lineID) then return end

    local channel = ct.Incoming.CHANNEL_OF[event]
    if not channel or not db.channels or not db.channels[channel] then return end
    if channel == "CHANNEL" and not ct.Incoming.ShowsChannel(frame, channelName, zoneID, channelBase) then return end

    local from, to = settings.from, settings.to
    -- Let Chat Translator display a pair it already handles with its native incoming switch.
    if db.inbound and ((from == "en" and to == db.lang) or (db.lang == "en" and to == "en")) then return end
    if not (ct.Engine.CanTranslate(from, "en") or from == "en")
        or not (ct.Engine.CanTranslate("en", to) or to == "en") then return end

    local slot = type(lineID) == "number" and lineID > 0 and lineID % 128
    local entry = slot and cache[slot]
    if not entry or entry.id ~= lineID then
        local _, detected = ct.Script.Detect(text, from)
        local result
        local detectedPack = ct.Script.PackLang(detected)
        if detectedPack == from
            or (detectedPack == "en" and ct.LANG_SCRIPT[from] == "Latn" and ct.Engine.LooksLike(text, from)) then
            result = Translate(text, from, to)
        end
        entry = { id = lineID, result = result, frames = {} }
        if slot then cache[slot] = entry end
    end
    if not entry.result or entry.frames[frame] then return end
    entry.frames[frame] = true

    local mark = from:upper() .. " > " .. to:upper()
    local line = ct.GlossHead(mark) .. ct.Incoming.Plain(entry.result)
    C_Timer.After(0, function()
        if settings.incoming and settings.from == from and settings.to == to then
            frame:AddMessage(line)
        end
    end)
end

local function SafeFilter(...)
    -- An integration error must never hide the original message.
    pcall(Filter, ...)
end

local function Button(parent, label, width, action)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(label)
    button:SetScript("OnClick", action)
    return button
end

local function BuildDialog()
    local frame = CreateFrame("Frame", "MyForeverToolsChatTranslation", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(450, 237)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("翻译语言")
    table.insert(UISpecialFrames, frame:GetName())

    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("LEFT", frame, "BOTTOMLEFT", 16, 19)
    status:SetJustifyH("LEFT")

    local function EditBox(label, top)
        local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        heading:SetPoint("TOPLEFT", 16, -top)
        heading:SetText(label)
        local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 4, -3)
        box:SetSize(414, 26)
        box:SetAutoFocus(false)
        box:SetFontObject(GameFontHighlight)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        return box
    end

    local input = EditBox("输入原文", 100)
    local output = EditBox("译文", 150)
    local source, target
    local function RefreshPair()
        cache = {}
        LoadPair()
        source:SetText("原文：" .. LanguageName(settings.from))
        target:SetText("译文：" .. LanguageName(settings.to))
        output:SetText("")
        status:SetText("")
    end

    local function SelectLanguage(button, key, other)
        MenuUtil.CreateContextMenu(button, function(_, menu)
            local function Add(code)
                local item = menu:CreateRadio(LanguageName(code), function() return settings[key] == code end, function()
                    if settings[other] == code then settings[other] = settings[key] end
                    settings[key] = code
                    RefreshPair()
                end)
                local pack = code ~= "en" and ct.Packs.Status(code)
                item:SetEnabled(code == "en" or pack == "loaded" or pack == "loadable")
            end
            Add("en")
            for _, code in ipairs(ct.LANG_ORDER) do Add(code) end
        end)
    end

    source = Button(frame, "", 177, function(self) SelectLanguage(self, "from", "to") end)
    source:SetPoint("TOPLEFT", 16, -34)
    target = Button(frame, "", 177, function(self) SelectLanguage(self, "to", "from") end)
    target:SetPoint("TOPRIGHT", -16, -34)
    local swap = Button(frame, "互换", 55, function()
        settings.from, settings.to = settings.to, settings.from
        RefreshPair()
    end)
    swap:SetPoint("LEFT", source, "RIGHT", 5, 0)

    local incoming = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    incoming:SetPoint("TOPLEFT", 13, -65)
    incoming:SetChecked(settings.incoming)
    local caption = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    caption:SetPoint("LEFT", incoming, "RIGHT", 3, 0)
    caption:SetText("收到所选原文语言时显示译文")
    incoming:SetScript("OnClick", function(self)
        settings.incoming = self:GetChecked() and true or false
        if settings.incoming then LoadPair() end
    end)

    local function Preview()
        local text = input:GetText():match("^%s*(.-)%s*$")
        if text == "" then status:SetText("请输入要翻译的文字。"); return end
        LoadPair()
        local result = Translate(text, settings.from, settings.to)
        output:SetText(result or "")
        if result then
            output:SetFocus()
            output:HighlightText()
            status:SetText("已选中译文，按 Ctrl+C 复制。")
        else
            status:SetText("未找到可用译文。请检查语言选择或语言包。")
        end
    end
    input:SetScript("OnEnterPressed", Preview)
    local translate = Button(frame, "翻译", 68, Preview)
    translate:SetPoint("BOTTOMRIGHT", -16, 7)
    status:SetPoint("RIGHT", translate, "LEFT", -6, 0)
    RefreshPair()
    return frame
end

local function OpenDialog()
    if not settings or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    if not dialog then dialog = BuildDialog() end
    dialog:Show()
    dialog:Raise()
end

local function AddPanelButton()
    local panel = ct.Panel and ct.Panel.frame
    if panelButton or not panel then return end
    panelButton = Button(panel, "翻译语言", 120, OpenDialog)
    panelButton:SetPoint("TOP", panel, "BOTTOM", 0, -3)
end

SLASH_MYFOREVERTOOLSTRANSLATE1 = "/mfttranslate"
SlashCmdList.MYFOREVERTOOLSTRANSLATE = OpenDialog

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    MyForeverToolsCharacterDB = MyForeverToolsCharacterDB or {}
    settings = MyForeverToolsCharacterDB.chatTranslation or { from = "de", to = "zhCN", incoming = false }
    MyForeverToolsCharacterDB.chatTranslation = settings
    if settings.incoming then LoadPair() end

    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if addFilter then
        for _, event in ipairs(ct.Incoming.EVENTS) do addFilter(event, SafeFilter) end
    end
    if ct.Panel and ct.Panel.Show then
        hooksecurefunc(ct.Panel, "Show", AddPanelButton)
        AddPanelButton()
    end
end)

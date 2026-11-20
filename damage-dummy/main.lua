--[[=====================================================================
    W H I T E C H E A T S   •   D A M A G E   D U M M Y
    version: 1.1.0

    Локальный (client-side) NPC-манекен для теста урона.
    Модель существует только на твоём клиенте: сервер её не видит,
    другие игроки видят, будто ты стреляешь в пустоту.

    КАК РАБОТАЕТ УРОН (два канала):
      1) пассивный — если игра сама наносит урон клиенту манекена
         (HealthChanged), попадание логируется как есть;
      2) hit-детектор — каждый твой клик превращается в raycast от
         камеры: попал в манекен -> урон. Значение берётся из твоего
         Tool (атрибут или Value с именем Damage / DMG). Если оружие
         не сообщает урон — применяется тестовое (слайдер TEST DAMAGE)
         и попадание помечается "est".

    Возможности:
      - R6-манекен (сборка с нуля) или клон твоего персонажа (R15/R6);
      - внешность: имя, цвет кожи, футболка и штаны по ID,
        волосы и аксессуары по ID;
      - движение: стоит / бродит / следует за тобой, WalkSpeed,
        JumpPower, радиус брожения;
      - тест урона: лог попаданий (часть тела, дистанция), суммарный
        урон, DPS за окно 5 сек, всплывающие числа, полоска HP;
      - headshot x2 (эмуляция), god mode, авто-респаун, лечение,
        сброс статистики.

    Запуск из loader (кнопка INJECT) или отдельно:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/whroblox/scripts/main/damage-dummy/main.lua"))()

    Управление:
      RightShift   — показать / скрыть панель
      кнопка ✕     — скрыть панель (скрипт продолжает работать)
=====================================================================]]

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {
    VERSION    = "1.1.0",
    TOGGLE_KEY = Enum.KeyCode.RightShift,
    STATE_PATH = "whitecheats_damage_dummy.json",
    UI_WIDTH   = 540,
    UI_HEIGHT  = 524,
    ICON_URL   = "https://raw.githubusercontent.com/whroblox/scripts/main/damage-dummy/icon.png",
}

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS + STATE
---------------------------------------------------------------------

local settings = {
    rig            = "R6",      -- "R6" | "R15" (клон моего персонажа)
    name           = "Dummy",
    shirt          = "",        -- id; пусто = копия с меня, 0 = снять
    pants          = "",
    accessories    = "",        -- id через запятую
    skin           = "d9d9d9",  -- hex
    highlight      = true,
    motion         = "stand",   -- stand | wander | follow
    walkspeed      = 16,
    jumppower      = 50,
    maxHealth      = 100,
    godMode        = false,
    respawn        = true,
    respawnDelay   = 3,
    wanderRadius   = 20,
    floatDamage    = true,
    healthBar      = true,
    hitDetector    = true,      -- активный канал урона (клик -> raycast)
    headshotMult   = false,     -- x2 при попадании в голову (эмуляция)
    testDamage     = 25,        -- урон за выстрел, если оружие не сообщает
}

local themeMode = "dark"

-- forward declarations (заполняются ниже)
local dummy        -- состояние манекена
local spawnDummy   -- спавн / респаун

local function loadAll()
    if type(readfile) ~= "function" then return end
    local ok, raw = pcall(readfile, CONFIG.STATE_PATH)
    if not ok or type(raw) ~= "string" then return end
    local okJson, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not (okJson and type(data) == "table") then return end
    if data.theme == "dark" or data.theme == "white" then themeMode = data.theme end
    if type(data.settings) == "table" then
        for k, v in pairs(data.settings) do
            if type(settings[k]) == type(v) then settings[k] = v end
        end
    end
end

local function saveAll()
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(CONFIG.STATE_PATH, HttpService:JSONEncode({
            theme = themeMode,
            settings = settings,
        }))
    end)
end

loadAll()

---------------------------------------------------------------------
-- THEME (dark / white — палитра как у loader)
---------------------------------------------------------------------

local THEMES = {
    dark = {
        bg      = Color3.fromRGB(17, 17, 22),
        panel   = Color3.fromRGB(26, 26, 34),
        card    = Color3.fromRGB(31, 31, 40),
        stroke  = Color3.fromRGB(78, 78, 98),
        text    = Color3.fromRGB(236, 236, 245),
        subtext = Color3.fromRGB(148, 148, 164),
        accent  = Color3.fromRGB(139, 92, 246),
        accent2 = Color3.fromRGB(34, 211, 238),
        success = Color3.fromRGB(52, 199, 123),
        danger  = Color3.fromRGB(236, 84, 84),
        btnText = Color3.fromRGB(255, 255, 255),
        glassT  = 0.06,
        shadow  = 0.45,
    },
    white = {
        bg      = Color3.fromRGB(240, 241, 246),
        panel   = Color3.fromRGB(249, 250, 253),
        card    = Color3.fromRGB(255, 255, 255),
        stroke  = Color3.fromRGB(206, 209, 222),
        text    = Color3.fromRGB(28, 30, 38),
        subtext = Color3.fromRGB(122, 126, 142),
        accent  = Color3.fromRGB(124, 58, 237),
        accent2 = Color3.fromRGB(14, 165, 233),
        success = Color3.fromRGB(28, 168, 104),
        danger  = Color3.fromRGB(222, 62, 62),
        btnText = Color3.fromRGB(255, 255, 255),
        glassT  = 0.10,
        shadow  = 0.72,
    },
}

local currentPal = THEMES[themeMode] or THEMES.dark

local repainters = {}
local function bind(painter)
    table.insert(repainters, painter)
    pcall(painter, currentPal)
end

local function repaint()
    for _, painter in ipairs(repainters) do
        pcall(painter, currentPal)
    end
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function mk(className, props, parent)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        pcall(function() inst[k] = v end)
    end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(parent, r)
    return mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

local function stroke(parent, thickness)
    return mk("UIStroke", { Thickness = thickness or 1 }, parent)
end

local function gradient(parent)
    return mk("UIGradient", {
        Rotation = 45,
        Color = ColorSequence.new(
            ColorSequenceKeypoint.new(0, currentPal.accent),
            ColorSequenceKeypoint.new(1, currentPal.accent2)),
    }, parent)
end

local function numericId(v)
    local n = tostring(v or ""):match("(%d+)")
    if n then return tonumber(n) end
    return nil
end

local function parseHex(s)
    s = tostring(s or ""):gsub("#", ""):gsub("0x", ""):gsub("%s", "")
    if #s ~= 6 then return nil end
    if not s:match("^%x+$") then return nil end
    local r = tonumber(s:sub(1, 2), 16)
    local g = tonumber(s:sub(3, 4), 16)
    local b = tonumber(s:sub(5, 6), 16)
    if not (r and g and b) then return nil end
    return Color3.fromRGB(r, g, b)
end

local function myChar()
    local c = LocalPlayer.Character
    if c and c.Parent then return c end
    return nil
end

---------------------------------------------------------------------
-- HTTP (для иконки в шапке; необязательно)
---------------------------------------------------------------------

local httpRequest
do
    local candidates = {
        http_request, request, syn_request, fluxus_request,
        (type(http) == "table" and type(http.request) == "function") and http.request or nil,
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then
            httpRequest = fn
            break
        end
    end
end

local function httpGet(url)
    if type(httpRequest) ~= "function" then return nil end
    local ok, res = pcall(httpRequest, { Url = url, Method = "GET" })
    if not ok or type(res) ~= "table" then return nil end
    local status = res.StatusCode or res.code or res.status_code
    local body = res.Body or res.body
    if status ~= nil and status ~= 200 then return nil end
    if type(body) ~= "string" then return nil end
    return body
end

local function loadIconAsset()
    if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then return nil end
    local ok, assetId = pcall(function()
        local path = "wc_dd_icon_" .. tostring(math.random(100000000, 999999999)) .. ".png"
        local data = httpGet(CONFIG.ICON_URL)
        if not data then return nil end
        writefile(path, data)
        local id = getcustomasset(path)
        pcall(function() delfile(path) end)
        return id
    end)
    if ok and assetId then return assetId end
    return nil
end

---------------------------------------------------------------------
-- GUI MOUNT
---------------------------------------------------------------------

local function mountGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "WC_DamageDummy"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if type(gethui) == "function" then
        local ok = pcall(function() gui.Parent = gethui() end)
        if ok and gui.Parent then return gui end
    end
    local okCore = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if okCore and gui.Parent then return gui end
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    return gui
end

local gui = mountGui()

---------------------------------------------------------------------
-- MAIN WINDOW
---------------------------------------------------------------------

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local main = mk("Frame", {
    Name = "Main",
    AnchorPoint = isTouch and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5),
    Position = isTouch and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(1, -(CONFIG.UI_WIDTH + 24), 0.5, 0),
    Size = UDim2.fromOffset(CONFIG.UI_WIDTH, CONFIG.UI_HEIGHT),
    BackgroundColor3 = currentPal.bg,
    BackgroundTransparency = currentPal.glassT,
    BorderSizePixel = 0,
    Active = false,
}, gui)
corner(main, 16)
local mainStroke = stroke(main, 1)

if isTouch then
    mk("UIScale", { Scale = 0.74 }, main)
end

---------------------------------------------------------------------
-- HEADER
---------------------------------------------------------------------

local header = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundTransparency = 1,
    Active = true,
}, main)

local iconBox = mk("Frame", {
    Position = UDim2.new(0, 14, 0, 12),
    Size = UDim2.fromOffset(34, 34),
    BorderSizePixel = 0,
}, header)
corner(iconBox, 10)
local iconGradient = gradient(iconBox)
local iconLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Font = Enum.Font.GothamBlack,
    TextSize = 18,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Text = "◎",
}, iconBox)

local title = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 58, 0, 10),
    Size = UDim2.new(1, -200, 0, 20),
    Font = Enum.Font.GothamBlack,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "DAMAGE DUMMY",
}, header)

local subtitle = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 58, 0, 31),
    Size = UDim2.new(1, -200, 0, 14),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "local damage test  •  client-only",
}, header)

local themeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -48, 0, 16),
    Size = UDim2.fromOffset(66, 26),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    AutoButtonColor = true,
    Text = string.upper(themeMode),
}, header)
corner(themeBtn, 8)

local closeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 16),
    Size = UDim2.fromOffset(26, 26),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Text = "✕",
}, header)
corner(closeBtn, 8)

-- градиентная полоса под шапкой
local gradLine = mk("Frame", {
    Position = UDim2.new(0, 14, 0, 56),
    Size = UDim2.new(1, -28, 0, 2),
    BorderSizePixel = 0,
}, main)
mk("UIGradient", {
    Rotation = 0,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 0.75),
    }),
}, gradLine)

---------------------------------------------------------------------
-- FOOTER
---------------------------------------------------------------------

local footer = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundTransparency = 1,
}, main)

local statusLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 0),
    Size = UDim2.new(1, -110, 1, 0),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "idle",
}, footer)

local versionLabel = mk("TextLabel", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 0),
    Size = UDim2.fromOffset(90, 28),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = "v" .. CONFIG.VERSION,
}, footer)

---------------------------------------------------------------------
-- TAB BAR + BODY
---------------------------------------------------------------------

local TAB_NAMES = { "SPAWN", "LOOK", "MOVE", "TEST" }
local currentTab = "SPAWN"

local tabBar = mk("Frame", {
    Position = UDim2.new(0, 12, 0, 66),
    Size = UDim2.new(1, -24, 0, 34),
    BackgroundColor3 = currentPal.panel,
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
}, main)
corner(tabBar, 10)

local body = mk("Frame", {
    Position = UDim2.new(0, 12, 0, 108),
    Size = UDim2.new(1, -24, 1, -140),
    BackgroundTransparency = 1,
}, main)

local tabButtons = {}
local tabFrames = {}

local function paintTabBar()
    for _, name in ipairs(TAB_NAMES) do
        local btn = tabButtons[name]
        if btn then
            if name == currentTab then
                btn.BackgroundColor3 = currentPal.accent
                btn.BackgroundTransparency = 0
                btn.TextColor3 = currentPal.btnText
            else
                btn.BackgroundColor3 = currentPal.panel
                btn.BackgroundTransparency = 1
                btn.TextColor3 = currentPal.subtext
            end
        end
    end
end

for i, name in ipairs(TAB_NAMES) do
    local btn = mk("TextButton", {
        Position = UDim2.new((i - 1) / #TAB_NAMES, 4, 0, 4),
        Size = UDim2.new(1 / #TAB_NAMES, -8, 1, -8),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Text = name,
    }, tabBar)
    corner(btn, 8)
    tabButtons[name] = btn
    btn.MouseButton1Click:Connect(function()
        currentTab = name
        paintTabBar()
        for _, other in ipairs(TAB_NAMES) do
            if tabFrames[other] then tabFrames[other].Visible = (other == name) end
        end
    end)
end

local function makeTab(name)
    local sf = mk("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.35,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = (name == currentTab),
    }, body)
    mk("UIListLayout", {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, sf)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 8),
    }, sf)
    tabFrames[name] = sf
    return sf
end

for _, name in ipairs(TAB_NAMES) do
    makeTab(name)
end

local orderCounter = 0
local function nextOrder()
    orderCounter = orderCounter + 1
    return orderCounter
end

---------------------------------------------------------------------
-- UI COMPONENTS
---------------------------------------------------------------------

local function paintButton(btn, kind)
    if kind == "accent" then
        btn.BackgroundColor3 = currentPal.accent
        btn.TextColor3 = currentPal.btnText
        btn.BackgroundTransparency = 0
    elseif kind == "danger" then
        btn.BackgroundColor3 = currentPal.danger
        btn.TextColor3 = currentPal.btnText
        btn.BackgroundTransparency = 0
    else
        btn.BackgroundColor3 = currentPal.panel
        btn.TextColor3 = currentPal.text
        btn.BackgroundTransparency = 0.1
    end
end

local function makeButton(parent, text, kind, onClick, order)
    local btn = mk("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        AutoButtonColor = true,
        Text = text,
        LayoutOrder = order or 0,
    }, parent)
    corner(btn, 10)
    if kind == "accent" then
        gradient(btn)
    end
    bind(function() paintButton(btn, kind) end)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

local function makeRow(parent, count, order)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = order or nextOrder(),
    }, parent)
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, row)
    local padShare = -(8 * (count - 1)) / count
    local children = 0
    local function add(text, kind, onClick)
        children = children + 1
        local slot = mk("Frame", {
            Size = UDim2.new(1 / count, padShare, 1, 0),
            BackgroundTransparency = 1,
            LayoutOrder = children,
        }, row)
        return makeButton(slot, text, kind, onClick)
    end
    return row, add
end

local function sectionLabel(parent, text)
    return mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.upper(text),
        LayoutOrder = nextOrder(),
    }, parent)
end

-- switch (ползунок) вместо галочек
local function makeSwitch(parent, label, value, onChange, order)
    local state = value == true
    local btn = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = order or nextOrder(),
    }, parent)
    corner(btn, 10)
    local lbl = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -70, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = label,
    }, btn)
    local track = mk("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(42, 22),
        BorderSizePixel = 0,
    }, btn)
    corner(track, 11)
    local knob = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BorderSizePixel = 0,
    }, track)
    corner(knob, 8)

    local function paint()
        if state then
            track.BackgroundColor3 = currentPal.accent
            track.BackgroundTransparency = 0
            knob.Position = UDim2.new(1, -11, 0.5, 0)
            knob.BackgroundColor3 = currentPal.btnText
        else
            track.BackgroundColor3 = currentPal.panel
            track.BackgroundTransparency = 0.15
            knob.Position = UDim2.new(0, 11, 0.5, 0)
            knob.BackgroundColor3 = currentPal.subtext
        end
    end

    local function toggle()
        state = not state
        paint()
        onChange(state)
        saveAll()
    end

    bind(function(pal)
        btn.BackgroundColor3 = pal.panel
        btn.BackgroundTransparency = 0.1
        lbl.TextColor3 = pal.text
        paint()
    end)

    btn.MouseButton1Click:Connect(toggle)
    paint()
    return btn
end

-- слайдер: крупная зона касания, значение в чипе
local function makeSlider(parent, label, min, max, step, value, onChange, order)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        LayoutOrder = order or nextOrder(),
    }, parent)
    local nameLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 2, 0, 0),
        Size = UDim2.new(1, -110, 0, 18),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
    }, row)
    local valueChip = mk("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -2, 0, 0),
        Size = UDim2.fromOffset(58, 22),
        BorderSizePixel = 0,
    }, row)
    corner(valueChip, 6)
    local valueLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        Text = tostring(value),
    }, valueChip)
    local hitArea = mk("TextButton", {
        Position = UDim2.new(0, 2, 0, 22),
        Size = UDim2.new(1, -4, 0, 26),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, row)
    local track = mk("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 8),
        BorderSizePixel = 0,
    }, hitArea)
    corner(track, 4)
    local trackStroke = stroke(track, 1)
    local fill = mk("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BorderSizePixel = 0,
    }, track)
    corner(fill, 4)
    local fillGrad = gradient(fill)
    local knob = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BorderSizePixel = 0,
        ZIndex = 2,
    }, track)
    corner(knob, 8)
    local knobStroke = stroke(knob, 2)

    local function apply(raw, fire)
        local steps = math.floor((raw - min) / step + 0.5)
        local v = math.clamp(min + steps * step, min, max)
        local rel = (v - min) / math.max(max - min, 1e-9)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valueLabel.Text = tostring(v)
        if fire then onChange(v) end
    end

    local dragging = false
    local function fromX(x)
        local rel = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
        apply(min + (max - min) * math.clamp(rel, 0, 1), true)
    end
    hitArea.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(io.Position.X)
        end
    end)
    hitArea.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(io)
        if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement
            or io.UserInputType == Enum.UserInputType.Touch) then
            fromX(io.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    bind(function(pal)
        nameLabel.TextColor3 = pal.subtext
        valueChip.BackgroundColor3 = pal.card
        valueLabel.TextColor3 = pal.text
        track.BackgroundColor3 = pal.panel
        trackStroke.Color = pal.stroke
        trackStroke.Transparency = 0.5
        fillGrad.Color = ColorSequence.new(
            ColorSequenceKeypoint.new(0, pal.accent),
            ColorSequenceKeypoint.new(1, pal.accent2))
        knob.BackgroundColor3 = pal.text
        knobStroke.Color = pal.accent
    end)

    apply(value, false)
end

local function makeSegment(parent, options, current, onPick, order)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = order or nextOrder(),
    }, parent)
    local selected = current
    local buttons = {}
    local function paint()
        for _, opt in ipairs(options) do
            local btn = buttons[opt]
            if btn then
                if opt == selected then
                    btn.BackgroundColor3 = currentPal.accent
                    btn.BackgroundTransparency = 0
                    btn.TextColor3 = currentPal.btnText
                else
                    btn.BackgroundColor3 = currentPal.panel
                    btn.BackgroundTransparency = 1
                    btn.TextColor3 = currentPal.subtext
                end
            end
        end
    end
    for i, opt in ipairs(options) do
        local btn = mk("TextButton", {
            Position = UDim2.new((i - 1) / #options, 3, 0, 0),
            Size = UDim2.new(1 / #options, -6, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            Text = opt,
        }, row)
        corner(btn, 10)
        buttons[opt] = btn
        btn.MouseButton1Click:Connect(function()
            selected = opt
            paint()
            onPick(opt)
            saveAll()
        end)
    end
    bind(paint)
    paint()
end

local function makeInput(parent, label, placeholder, value, onChange, order)
    local wrap = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundTransparency = 1,
        LayoutOrder = order or nextOrder(),
    }, parent)
    local nameLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 2, 0, 0),
        Size = UDim2.new(1, -4, 0, 16),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
    }, wrap)
    local box = mk("Frame", {
        Position = UDim2.new(0, 2, 0, 20),
        Size = UDim2.new(1, -4, 0, 34),
        BorderSizePixel = 0,
    }, wrap)
    corner(box, 10)
    local boxStroke = stroke(box, 1)
    local tb = mk("TextBox", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        PlaceholderText = placeholder,
        PlaceholderColor3 = currentPal.subtext,
        Text = value or "",
        ClearTextOnFocus = false,
    }, box)
    bind(function(pal)
        nameLabel.TextColor3 = pal.subtext
        box.BackgroundColor3 = pal.panel
        boxStroke.Color = pal.stroke
        boxStroke.Transparency = 0.5
        tb.TextColor3 = pal.text
        tb.PlaceholderColor3 = pal.subtext
    end)
    tb.Focused:Connect(function()
        boxStroke.Color = currentPal.accent
        boxStroke.Transparency = 0
    end)
    tb.FocusLost:Connect(function()
        boxStroke.Color = currentPal.stroke
        boxStroke.Transparency = 0.5
        onChange(tb.Text)
        saveAll()
    end)
    return wrap
end

local function makeHint(parent, text)
    local label = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextColor3 = currentPal.subtext,
        Text = text,
        LayoutOrder = nextOrder(),
    }, parent)
    bind(function(pal) label.TextColor3 = pal.subtext end)
    return label
end

bind(function(pal)
    main.BackgroundColor3 = pal.bg
    main.BackgroundTransparency = pal.glassT
    mainStroke.Color = pal.stroke
    mainStroke.Transparency = 0.45
    iconGradient.Color = ColorSequence.new(
        ColorSequenceKeypoint.new(0, pal.accent),
        ColorSequenceKeypoint.new(1, pal.accent2))
    title.TextColor3 = pal.text
    subtitle.TextColor3 = pal.subtext
    themeBtn.BackgroundColor3 = pal.panel
    themeBtn.TextColor3 = pal.text
    themeBtn.Text = string.upper(themeMode)
    closeBtn.BackgroundColor3 = pal.panel
    closeBtn.TextColor3 = pal.text
    gradLine.BackgroundColor3 = pal.accent
    tabBar.BackgroundColor3 = pal.panel
    tabBar.BackgroundTransparency = 0.3
    statusLabel.TextColor3 = pal.subtext
    versionLabel.TextColor3 = pal.subtext
end)

-- попытка подгрузить png-иконку в шапку
task.spawn(function()
    local assetId = loadIconAsset()
    if assetId and iconLabel.Parent then
        iconLabel.Text = ""
        mk("ImageLabel", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(1, -8, 1, -8),
            Image = assetId,
        }, iconBox)
    end
end)

---------------------------------------------------------------------
-- TOAST
---------------------------------------------------------------------

local toastFrame = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -24),
    Size = UDim2.new(0, 0, 0, 34),
    AutomaticSize = Enum.AutomaticSize.X,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 50,
}, gui)
corner(toastFrame, 10)
local toastStroke = stroke(toastFrame, 1)
local toastText = mk("TextLabel", {
    BackgroundTransparency = 1,
    Size = UDim2.new(0, 0, 1, 0),
    AutomaticSize = Enum.AutomaticSize.X,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Center,
    Text = "",
    ZIndex = 50,
}, toastFrame)
mk("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, toastFrame)

local toastToken = 0
local function notify(msg)
    toastToken = toastToken + 1
    local myToken = toastToken
    toastText.Text = msg
    toastFrame.Visible = true
    task.delay(2.4, function()
        if toastToken == myToken then
            toastFrame.Visible = false
        end
    end)
end

bind(function(pal)
    toastFrame.BackgroundColor3 = pal.bg
    toastFrame.BackgroundTransparency = 0.05
    toastStroke.Color = pal.stroke
    toastStroke.Transparency = 0.4
    toastText.TextColor3 = pal.text
end)

---------------------------------------------------------------------
-- STATUS
---------------------------------------------------------------------

local function updateStatus()
    if dummy and dummy.model and dummy.humanoid then
        statusLabel.Text = string.format("dummy: %d / %d hp  •  %s  •  %s",
            math.floor(dummy.humanoid.Health + 0.5),
            math.floor(dummy.humanoid.MaxHealth + 0.5),
            settings.motion, settings.rig)
    else
        statusLabel.Text = "манекена нет — SPAWN во вкладке SPAWN"
    end
end

---------------------------------------------------------------------
-- DUMMY ENGINE
---------------------------------------------------------------------

dummy = {
    model = nil,
    humanoid = nil,
    hrp = nil,
    head = nil,
    joints = nil,
    highlight = nil,
    hpGui = nil,
    hpFill = nil,
    spawnCFrame = nil,
    lastHealth = 0,
    totalDamage = 0,
    hitCount = 0,
    window = {},
    conns = {},
    phase = 0,
}

local function clearDummy()
    for _, c in ipairs(dummy.conns) do
        pcall(function() c:Disconnect() end)
    end
    dummy.conns = {}
    if dummy.model then pcall(function() dummy.model:Destroy() end) end
    dummy.model = nil
    dummy.humanoid = nil
    dummy.hrp = nil
    dummy.head = nil
    dummy.joints = nil
    dummy.highlight = nil
    dummy.hpGui = nil
    dummy.hpFill = nil
end

local function findJoint(model, names)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") then
            for _, n in ipairs(names) do
                if d.Name == n then return d end
            end
        end
    end
    return nil
end

-- R6: части + Motor6D (канонические C0/C1 как у стандартного rig)
local R6_PARTS = {
    { name = "HumanoidRootPart", size = Vector3.new(2, 2, 1), collide = false, hidden = true },
    { name = "Torso",            size = Vector3.new(2, 2, 1) },
    { name = "Head",             size = Vector3.new(2, 1, 1) },
    { name = "Right Arm",        size = Vector3.new(1, 2, 1) },
    { name = "Left Arm",         size = Vector3.new(1, 2, 1) },
    { name = "Right Leg",        size = Vector3.new(1, 2, 1) },
    { name = "Left Leg",         size = Vector3.new(1, 2, 1) },
}

local R6_JOINTS = {
    { name = "RootJoint",      p0 = "HumanoidRootPart", p1 = "Torso",
      c0 = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi),
      c1 = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi) },
    { name = "Right Shoulder", p0 = "Torso", p1 = "Right Arm",
      c0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0),
      c1 = CFrame.new(-0.5, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0) },
    { name = "Left Shoulder",  p0 = "Torso", p1 = "Left Arm",
      c0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0),
      c1 = CFrame.new(0.5, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0) },
    { name = "Right Hip",      p0 = "Torso", p1 = "Right Leg",
      c0 = CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0),
      c1 = CFrame.new(0.5, 1, 0) * CFrame.Angles(0, math.pi / 2, 0) },
    { name = "Left Hip",       p0 = "Torso", p1 = "Left Leg",
      c0 = CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0),
      c1 = CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -math.pi / 2, 0) },
    { name = "Neck",           p0 = "Torso", p1 = "Head",
      c0 = CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi),
      c1 = CFrame.new(0, -0.5, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi) },
}

local function buildR6(model, skin)
    local humanoid = Instance.new("Humanoid")
    humanoid.RigType = Enum.HumanoidRigType.R6
    humanoid.Parent = model

    local parts = {}
    for _, def in ipairs(R6_PARTS) do
        local p = Instance.new("Part")
        p.Name = def.name
        p.Size = def.size
        p.Material = Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.CanCollide = def.collide ~= false
        p.Anchored = false
        if def.hidden then p.Transparency = 1 end
        p.Color = skin
        p.Parent = model
        parts[def.name] = p
    end

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Head
    mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
    mesh.Parent = parts["Head"]

    for _, j in ipairs(R6_JOINTS) do
        local m = Instance.new("Motor6D")
        m.Name = j.name
        m.Part0 = parts[j.p0]
        m.Part1 = parts[j.p1]
        m.C0 = j.c0
        m.C1 = j.c1
        m.Parent = parts[j.p0]
    end

    return humanoid, parts["HumanoidRootPart"], parts["Head"]
end

-- R15: клон моего персонажа
local function buildR15Clone()
    local char = myChar()
    local charHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not charHrp then return nil, nil, "нет персонажа" end
    local rig
    local ok = pcall(function()
        char.Archivable = true
        rig = char:Clone()
        char.Archivable = false
    end)
    if not ok or not rig then return nil, nil, "клонирование не удалось" end
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            d:Destroy()
        end
    end
    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = Instance.new("Humanoid")
        humanoid.Parent = rig
    end
    local hrp = rig:FindFirstChild("HumanoidRootPart")
    local head = rig:FindFirstChild("Head")
    if not hrp then
        rig:Destroy()
        return nil, nil, "в клоне нет HumanoidRootPart"
    end
    return rig, humanoid, nil
end

local function fetchAccessory(id)
    if type(game.GetObjects) ~= "function" then return nil end
    local ok, objs = pcall(game.GetObjects, game, "rbxassetid://" .. tostring(id))
    if not ok or type(objs) ~= "table" then return nil end
    for _, obj in ipairs(objs) do
        if obj:IsA("Accessory") or obj:IsA("Hat") then return obj end
    end
    for _, obj in ipairs(objs) do
        local acc = obj:FindFirstChildWhichIsA("Accessory", true)
        if acc then return acc end
    end
    return nil
end

local function applyLook(model, humanoid)
    -- цвет кожи
    local skin = parseHex(settings.skin)
    if skin then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
                d.Color = skin
            end
        end
    end

    -- футболка
    local oldShirt = model:FindFirstChildOfClass("Shirt")
    local sid = numericId(settings.shirt)
    if sid == 0 then
        if oldShirt then oldShirt:Destroy() end
    elseif sid then
        if not oldShirt then
            oldShirt = Instance.new("Shirt")
            oldShirt.Parent = model
        end
        oldShirt.ShirtTemplate = "rbxassetid://" .. sid
    else
        local mine = myChar() and myChar():FindFirstChildOfClass("Shirt")
        if mine then
            if oldShirt then oldShirt:Destroy() end
            mine:Clone().Parent = model
        end
    end

    -- штаны
    local oldPants = model:FindFirstChildOfClass("Pants")
    local pid = numericId(settings.pants)
    if pid == 0 then
        if oldPants then oldPants:Destroy() end
    elseif pid then
        if not oldPants then
            oldPants = Instance.new("Pants")
            oldPants.Parent = model
        end
        oldPants.PantsTemplate = "rbxassetid://" .. pid
    else
        local mine = myChar() and myChar():FindFirstChildOfClass("Pants")
        if mine then
            if oldPants then oldPants:Destroy() end
            mine:Clone().Parent = model
        end
    end

    -- волосы и аксессуары
    for id in string.gmatch(tostring(settings.accessories), "%d+") do
        local acc = fetchAccessory(id)
        if acc then
            pcall(function() humanoid:AddAccessory(acc) end)
        else
            notify("аксессуар " .. id .. " не загрузился")
        end
    end
end

local function addHighlight(model)
    pcall(function()
        local hl = Instance.new("Highlight")
        hl.Name = "WC_Highlight"
        hl.FillTransparency = 0.88
        hl.OutlineTransparency = 0.3
        hl.FillColor = currentPal.accent
        hl.OutlineColor = currentPal.accent2
        hl.Parent = model
        dummy.highlight = hl
    end)
end

local function removeHighlight()
    if dummy.highlight then
        pcall(function() dummy.highlight:Destroy() end)
        dummy.highlight = nil
    end
end

local function updateHpBar()
    local fill = dummy.hpFill
    if not (fill and dummy.humanoid) then return end
    local rel = math.clamp(dummy.humanoid.Health / math.max(dummy.humanoid.MaxHealth, 1), 0, 1)
    fill.Size = UDim2.new(rel, 0, 1, 0)
    local col = currentPal.success
    if rel < 0.25 then col = currentPal.danger
    elseif rel < 0.55 then col = currentPal.accent end
    fill.BackgroundColor3 = col
end

local function addHealthBar(model, head)
    local bb = Instance.new("BillboardGui")
    bb.Name = "WC_HealthBar"
    bb.Adornee = head
    bb.Size = UDim2.fromOffset(92, 12)
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 140
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = currentPal.bg
    bg.BackgroundTransparency = 0.25
    bg.BorderSizePixel = 0
    bg.Parent = bb
    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 6)
    bgCorner.Parent = bg
    local fill = Instance.new("Frame")
    fill.Position = UDim2.new(0, 1, 0, 1)
    fill.Size = UDim2.new(1, -2, 1, -2)
    fill.BackgroundColor3 = currentPal.success
    fill.BorderSizePixel = 0
    fill.Parent = bg
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fill
    bb.Parent = model
    dummy.hpGui = bb
    dummy.hpFill = fill
    updateHpBar()
end

local function removeHealthBar()
    if dummy.hpGui then
        pcall(function() dummy.hpGui:Destroy() end)
        dummy.hpGui = nil
        dummy.hpFill = nil
    end
end

local function floatDamage(amount, headshot)
    local head = dummy.head
    local model = dummy.model
    if not (head and model) then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "WC_FloatDmg"
    bb.Adornee = head
    bb.Size = UDim2.fromOffset(170, 46)
    bb.StudsOffsetWorldSpace = Vector3.new(
        (math.random() - 0.5) * 2.2,
        2.7 + math.random() * 0.7,
        (math.random() - 0.5) * 2.2)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 200
    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.Font = Enum.Font.GothamBlack
    tl.TextSize = headshot and 20 or 18
    tl.Text = "-" .. string.format("%.0f", amount) .. (headshot and "  HS" or "")
    tl.TextColor3 = headshot and currentPal.accent2 or currentPal.danger
    tl.TextStrokeTransparency = 0.35
    tl.Parent = bb
    bb.Parent = model
    local ti = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    pcall(function()
        TweenService:Create(bb, ti, {
            StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 1.8, 0)
        }):Play()
        TweenService:Create(tl, ti, {
            TextTransparency = 1,
            TextStrokeTransparency = 1
        }):Play()
    end)
    task.delay(1.0, function() pcall(function() bb:Destroy() end) end)
end

---------------------------------------------------------------------
-- STATS + LOG
---------------------------------------------------------------------

local statLabels = { total = nil, dps = nil, hits = nil }
local logHolder = nil
local logCounter = 0
local logEntries = {}

local function updateStats()
    local now = os.clock()
    local sum = 0
    local i = 1
    while i <= #dummy.window do
        if now - dummy.window[i].t > 5 then
            table.remove(dummy.window, i)
        else
            sum = sum + dummy.window[i].d
            i = i + 1
        end
    end
    if statLabels.total then
        statLabels.total.Text = string.format("%.0f", dummy.totalDamage)
    end
    if statLabels.dps then
        statLabels.dps.Text = string.format("%.0f", sum / 5)
    end
    if statLabels.hits then
        statLabels.hits.Text = tostring(dummy.hitCount)
    end
end

-- цвет строки лога по содержимому
local function logColorFor(text)
    local head = string.sub(text, 1, 1)
    if head == "-" then return "danger" end
    if string.find(text, "spawn") or string.find(text, "healed") then return "success" end
    if string.find(text, "down") then return "danger" end
    return "subtext"
end

local function paintLogEntry(entry)
    local kind = entry:GetAttribute("wcColor") or "subtext"
    if kind == "danger" then
        entry.TextColor3 = currentPal.danger
    elseif kind == "success" then
        entry.TextColor3 = currentPal.success
    else
        entry.TextColor3 = currentPal.subtext
    end
end

local function logLine(text)
    if not logHolder then return end
    logCounter = logCounter + 1
    local entry = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        LayoutOrder = -logCounter,
    }, logHolder)
    entry:SetAttribute("wcColor", logColorFor(text))
    paintLogEntry(entry)
    table.insert(logEntries, entry)
    if #logEntries > 80 then
        local oldest = table.remove(logEntries, 1)
        pcall(function() oldest:Destroy() end)
    end
end

local function resetStats()
    dummy.totalDamage = 0
    dummy.hitCount = 0
    dummy.window = {}
    for _, entry in ipairs(logEntries) do
        pcall(function() entry:Destroy() end)
    end
    logEntries = {}
    updateStats()
end

---------------------------------------------------------------------
-- DAMAGE CORE (пассивный канал + hit-детектор)
---------------------------------------------------------------------

local lastLocalApply = 0      -- урон применили мы сами (applyHit)
local lastExternalDamage = 0  -- урон нанесло чужое оружие (пассивный)

local function registerHit(amount, meta)
    dummy.hitCount = dummy.hitCount + 1
    dummy.totalDamage = dummy.totalDamage + amount
    table.insert(dummy.window, { t = os.clock(), d = amount })
    updateStats()
    updateHpBar()
    if settings.floatDamage then
        floatDamage(amount, meta.headshot == true)
    end
    local tag = ""
    if meta.headshot then tag = tag .. "  HS" end
    if meta.emulated then tag = tag .. "  est" end
    logLine(string.format("-%.1f  %s  %.1fm%s  %s",
        amount,
        meta.part or "?",
        meta.distance or 0,
        tag,
        os.date("%H:%M:%S")))
end

-- применяем урон сами (hit-детектор / TEST HIT)
local function applyHit(amount, meta)
    local h = dummy.humanoid
    if not h or h.Health <= 0 then return end
    lastLocalApply = os.clock()
    dummy.lastHealth = math.max(0, h.Health - amount)
    h.Health = dummy.lastHealth
    registerHit(amount, meta)
end

-- пассивный канал: игра сама уронила манекен (клиентский damage)
local function wireDamage(humanoid)
    table.insert(dummy.conns, humanoid.HealthChanged:Connect(function(h)
        if dummy.humanoid ~= humanoid then return end
        if settings.godMode then
            if h < humanoid.MaxHealth then
                humanoid.Health = humanoid.MaxHealth
            end
            dummy.lastHealth = humanoid.MaxHealth
            updateHpBar()
            return
        end
        -- наш собственный applyHit уже залогирован активным каналом
        if os.clock() - lastLocalApply < 0.2 then
            dummy.lastHealth = h
            updateHpBar()
            return
        end
        local prev = dummy.lastHealth
        dummy.lastHealth = h
        local delta = prev - h
        if delta > 0.05 then
            lastExternalDamage = os.clock()
            registerHit(delta, { part = "external" })
        end
    end))
    table.insert(dummy.conns, humanoid.Died:Connect(function()
        logLine("dummy down  " .. os.date("%H:%M:%S"))
        if settings.respawn then
            task.delay(math.max(settings.respawnDelay, 0.5), function()
                if dummy.humanoid ~= humanoid then return end
                local cf = dummy.spawnCFrame
                if cf then spawnDummy(cf) end
            end)
        end
    end))
end

-- урон твоего оружия: атрибут / Value с именем Damage или DMG
local function weaponDamage()
    local c = myChar()
    local tool = c and c:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    for _, key in ipairs({ "Damage", "DMG", "damage", "dmg" }) do
        local v = tool:GetAttribute(key)
        if type(v) == "number" and v > 0 then return v end
    end
    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("NumberValue") or d:IsA("IntValue") then
            local n = string.lower(d.Name)
            if string.find(n, "damage") or string.find(n, "dmg") then
                local v = tonumber(d.Value)
                if v and v > 0 then return v end
            end
        end
    end
    return nil
end

-- hit-детектор: клик -> raycast от камеры -> попадание в манекен
local function doHitRay()
    if not (dummy.model and dummy.humanoid and dummy.humanoid.Health > 0) then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local mLoc = UserInputService:GetMouseLocation()
    if not mLoc then return end
    local okRay, res = pcall(function()
        local ray = camera:ViewportPointToRay(mLoc.X, mLoc.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local exclude = {}
        local c = myChar()
        if c then table.insert(exclude, c) end
        params.FilterDescendantsInstances = exclude
        return workspace:Raycast(ray.Origin, ray.Direction * 600, params)
    end)
    if not okRay or not res then return end
    local inst = res.Instance
    if not inst then return end
    local okIs, isDummy = pcall(function() return inst:IsDescendantOf(dummy.model) end)
    if not (okIs and isDummy) then return end

    -- оружие только что само засчитало урон? не дублируем
    if os.clock() - lastExternalDamage < 0.3 then return end

    local isHead = string.find(string.lower(inst.Name), "head") ~= nil
    local dmg = weaponDamage()
    local emulated = false
    if not dmg then
        dmg = settings.testDamage
        emulated = true
    end
    local headshot = false
    if isHead and settings.headshotMult then
        dmg = dmg * 2
        headshot = true
    end
    applyHit(dmg, {
        part = inst.Name,
        distance = res.Distance,
        headshot = headshot,
        emulated = emulated,
    })
end

-- клики мыши и тач (кроме нажатий по UI)
UserInputService.InputBegan:Connect(function(io, gameProcessed)
    if gameProcessed then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1
        or io.UserInputType == Enum.UserInputType.Touch then
        if not settings.hitDetector then return end
        task.defer(doHitRay)
    end
end)

---------------------------------------------------------------------
-- SPAWN
---------------------------------------------------------------------

function spawnDummy(cf)
    clearDummy()

    local skin = parseHex(settings.skin) or Color3.fromRGB(224, 224, 224)
    local displayName = tostring(settings.name or "")
    if displayName == "" then displayName = "Dummy" end

    local model = Instance.new("Model")
    model.Name = displayName

    local humanoid, hrp, head
    if settings.rig == "R15" then
        local rig, hum, err = buildR15Clone()
        if rig then
            model = rig
            humanoid = hum
            hrp = rig:FindFirstChild("HumanoidRootPart")
            head = rig:FindFirstChild("Head")
        else
            notify("R15 недоступен — строю R6")
            humanoid, hrp, head = buildR6(model, skin)
        end
    else
        humanoid, hrp, head = buildR6(model, skin)
    end

    if not (model and humanoid and hrp) then
        notify("спавн не удался")
        return
    end

    model.Name = displayName
    humanoid.DisplayName = displayName
    pcall(function()
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.DisplayName
    end)
    humanoid.MaxHealth = math.max(settings.maxHealth, 1)
    humanoid.Health = humanoid.MaxHealth
    humanoid.WalkSpeed = settings.walkspeed
    pcall(function()
        humanoid.UseJumpPower = true
        humanoid.JumpPower = settings.jumppower
    end)
    humanoid.BreakJointsOnDeath = false

    applyLook(model, humanoid)

    dummy.model = model
    dummy.humanoid = humanoid
    dummy.hrp = hrp
    dummy.head = head or hrp
    dummy.lastHealth = humanoid.Health
    dummy.joints = {
        rs = findJoint(model, { "Right Shoulder", "RightShoulder" }),
        ls = findJoint(model, { "Left Shoulder", "LeftShoulder" }),
        rh = findJoint(model, { "Right Hip", "RightHip" }),
        lh = findJoint(model, { "Left Hip", "LeftHip" }),
    }

    if settings.highlight then addHighlight(model) end
    if settings.healthBar and dummy.head then addHealthBar(model, dummy.head) end

    model.PrimaryPart = hrp
    model.Parent = workspace
    dummy.spawnCFrame = cf
    hrp.CFrame = cf

    wireDamage(humanoid)
    updateStats()
    updateHpBar()
    logLine("spawn  " .. os.date("%H:%M:%S"))
end

---------------------------------------------------------------------
-- SPAWN POSITION HELPERS
---------------------------------------------------------------------

local function charCFrame()
    local c = myChar()
    if c and c.PrimaryPart then return c.PrimaryPart.CFrame end
    return nil
end

local function raycastParams(excludeDummy)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if excludeDummy and dummy.model then table.insert(exclude, dummy.model) end
    local c = myChar()
    if c then table.insert(exclude, c) end
    params.FilterDescendantsInstances = exclude
    return params
end

local function groundPos(pos)
    local ok, res = pcall(function()
        return workspace:Raycast(
            pos + Vector3.new(0, 40, 0),
            Vector3.new(0, -160, 0),
            raycastParams(true))
    end)
    if ok and res then return res.Position end
    return pos
end

local function faceMe(pos)
    local c = charCFrame()
    if not c then return CFrame.new(pos) end
    return CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
end

local function spawnInFront()
    local c = charCFrame()
    if not c then
        notify("нет персонажа")
        return
    end
    local pos = groundPos((c * CFrame.new(0, 0, -5)).Position)
    spawnDummy(faceMe(pos + Vector3.new(0, 3, 0)))
end

local function spawnAtAim()
    local okMouse, hit = pcall(function()
        return LocalPlayer:GetMouse().Hit
    end)
    if not okMouse or not hit then
        spawnInFront()
        return
    end
    local pos = groundPos(hit.Position)
    spawnDummy(faceMe(pos + Vector3.new(0, 3, 0)))
end

local function teleportToMe()
    if not dummy.hrp then
        notify("манекена нет")
        return
    end
    local c = charCFrame()
    if not c then return end
    local pos = groundPos((c * CFrame.new(0, 0, -4)).Position)
    local cf = faceMe(pos + Vector3.new(0, 3, 0))
    dummy.spawnCFrame = cf
    dummy.hrp.CFrame = cf
end

local function deleteDummy()
    clearDummy()
    updateStatus()
end

local function applyLookNow()
    if dummy.hrp then
        local cf = dummy.hrp.CFrame
        spawnDummy(cf)
        notify("внешность применена")
    else
        notify("сначала спавн манекена")
    end
end

local function healDummy()
    if dummy.humanoid then
        dummy.humanoid.Health = dummy.humanoid.MaxHealth
        dummy.lastHealth = dummy.humanoid.MaxHealth
        updateHpBar()
        logLine("healed  " .. os.date("%H:%M:%S"))
        notify("манекен вылечен")
    else
        notify("манекена нет")
    end
end

local function testHit()
    if dummy.humanoid then
        applyHit(settings.testDamage, { part = "manual", distance = 0, emulated = true })
    else
        notify("манекена нет")
    end
end

local function setMaxHealth(v)
    settings.maxHealth = v
    if dummy.humanoid then
        dummy.humanoid.MaxHealth = v
        if dummy.humanoid.Health > v then
            dummy.humanoid.Health = v
        end
        dummy.lastHealth = dummy.humanoid.Health
        updateHpBar()
    end
    saveAll()
end

local function setGodMode(v)
    settings.godMode = v
    if v and dummy.humanoid then
        dummy.humanoid.Health = dummy.humanoid.MaxHealth
        dummy.lastHealth = dummy.humanoid.MaxHealth
    end
    saveAll()
end

local function setHighlight(v)
    settings.highlight = v
    if v and dummy.model and not dummy.highlight then
        addHighlight(dummy.model)
    elseif not v then
        removeHighlight()
    end
    saveAll()
end

local function setHealthBar(v)
    settings.healthBar = v
    if v and dummy.model and dummy.head and not dummy.hpGui then
        addHealthBar(dummy.model, dummy.head)
    elseif not v then
        removeHealthBar()
    end
    saveAll()
end

---------------------------------------------------------------------
-- MOTION LOOP (движение + процедурная анимация + статистика)
---------------------------------------------------------------------

local statAcc = 0
local followAcc = 0
local wanderAcc = 0

RunService.Heartbeat:Connect(function(dt)
    statAcc = statAcc + dt
    if statAcc >= 0.5 then
        statAcc = 0
        updateStats()
        updateStatus()
    end

    local h = dummy.humanoid
    local hrp = dummy.hrp
    if not (h and hrp) then return end
    if h.Health <= 0 then return end

    h.WalkSpeed = settings.walkspeed

    if settings.motion == "follow" then
        followAcc = followAcc - dt
        if followAcc <= 0 then
            followAcc = 0.5
            local c = myChar()
            local cHrp = c and c:FindFirstChild("HumanoidRootPart")
            if cHrp then pcall(function() h:MoveTo(cHrp.Position) end) end
        end
    elseif settings.motion == "wander" then
        wanderAcc = wanderAcc - dt
        if wanderAcc <= 0 then
            wanderAcc = 2 + math.random() * 3
            local base = dummy.spawnCFrame
            if base then
                local a = math.random() * math.pi * 2
                local r = math.random() * settings.wanderRadius
                pcall(function()
                    h:MoveTo(Vector3.new(
                        base.Position.X + math.cos(a) * r,
                        base.Position.Y,
                        base.Position.Z + math.sin(a) * r))
                end)
            end
        end
    end

    -- процедурная анимация: ходьба / лёгкий idle
    local vel = hrp.AssemblyLinearVelocity
    local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    local joints = dummy.joints
    local isR6 = h.RigType == Enum.HumanoidRigType.R6

    if speed > 0.8 then
        dummy.phase = dummy.phase + dt * math.clamp(speed, 4, 30) * 0.5
        local amp = math.clamp(speed / 16, 0.3, 1) * 0.7
        local s = math.sin(dummy.phase) * amp
        if joints then
            if isR6 then
                if joints.rs then joints.rs.Transform = CFrame.Angles(0, 0, s) end
                if joints.ls then joints.ls.Transform = CFrame.Angles(0, 0, -s) end
                if joints.rh then joints.rh.Transform = CFrame.Angles(0, 0, -s) end
                if joints.lh then joints.lh.Transform = CFrame.Angles(0, 0, s) end
            else
                if joints.rs then joints.rs.Transform = CFrame.Angles(s, 0, 0) end
                if joints.ls then joints.ls.Transform = CFrame.Angles(-s, 0, 0) end
                if joints.rh then joints.rh.Transform = CFrame.Angles(-s, 0, 0) end
                if joints.lh then joints.lh.Transform = CFrame.Angles(s, 0, 0) end
            end
        end
    else
        dummy.phase = dummy.phase + dt * 1.6
        local s = math.sin(dummy.phase) * 0.035
        if joints then
            if isR6 then
                if joints.rs then joints.rs.Transform = CFrame.Angles(0, 0, s) end
                if joints.ls then joints.ls.Transform = CFrame.Angles(0, 0, -s) end
            else
                if joints.rs then joints.rs.Transform = CFrame.Angles(s, 0, 0) end
                if joints.ls then joints.ls.Transform = CFrame.Angles(-s, 0, 0) end
            end
        end
    end
end)

---------------------------------------------------------------------
-- BUILD TABS
---------------------------------------------------------------------

-- SPAWN
do
    local sf = tabFrames.SPAWN
    sectionLabel(sf, "появление")
    local row1, add1 = makeRow(sf, 2)
    add1("SPAWN", "accent", spawnInFront)
    add1("AT AIM", "plain", spawnAtAim)
    local row2, add2 = makeRow(sf, 2)
    add2("TO ME", "plain", teleportToMe)
    add2("DELETE", "danger", deleteDummy)
    sectionLabel(sf, "поведение")
    makeSwitch(sf, "авто-респаун", settings.respawn, function(v) settings.respawn = v end)
    makeSlider(sf, "респаун, сек", 1, 10, 0.5, settings.respawnDelay,
        function(v) settings.respawnDelay = v end)
    makeSlider(sf, "радиус брожения", 5, 60, 1, settings.wanderRadius,
        function(v) settings.wanderRadius = v end)
    makeHint(sf, "SPAWN — манекен появляется перед тобой, AT AIM — в точку прицела. Манекен виден только на твоём клиенте.")
end

-- LOOK
do
    local sf = tabFrames.LOOK
    sectionLabel(sf, "тело")
    makeSegment(sf, { "R6", "R15" }, settings.rig,
        function(v) settings.rig = v end)
    makeInput(sf, "имя", "Dummy", settings.name,
        function(v) settings.name = v end)
    makeInput(sf, "цвет кожи — hex (например d9a066)", "d9a066", settings.skin,
        function(v) settings.skin = v end)
    sectionLabel(sf, "одежда и аксессуары")
    makeInput(sf, "футболка — id (пусто = твоя, 0 = снять)", "1839374", settings.shirt,
        function(v) settings.shirt = v end)
    makeInput(sf, "штаны — id (пусто = твои, 0 = снять)", "1148986", settings.pants,
        function(v) settings.pants = v end)
    makeInput(sf, "волосы / аксессуары — id через запятую", "13781923, 927184302", settings.accessories,
        function(v) settings.accessories = v end)
    makeSwitch(sf, "подсветка манекена", settings.highlight,
        function(v) setHighlight(v) end)
    local row, add = makeRow(sf, 1)
    add("APPLY LOOK", "accent", applyLookNow)
    makeHint(sf, "APPLY LOOK пересоздаёт манекен на его текущем месте с новыми настройками внешности. R15 — точная копия твоего персонажа.")
end

-- MOVE
do
    local sf = tabFrames.MOVE
    sectionLabel(sf, "режим движения")
    makeSegment(sf, { "stand", "wander", "follow" }, settings.motion,
        function(v) settings.motion = v end)
    sectionLabel(sf, "скорость")
    makeSlider(sf, "walkspeed", 0, 100, 1, settings.walkspeed,
        function(v) settings.walkspeed = v end)
    makeSlider(sf, "jumppower", 0, 200, 5, settings.jumppower,
        function(v) settings.jumppower = v end)
    makeHint(sf, "stand — стоит на месте; wander — бродит вокруг точки спавна; follow — ходит за тобой.")
end

-- TEST
do
    local sf = tabFrames.TEST
    sectionLabel(sf, "статистика")
    local statsRow = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
    }, sf)
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, statsRow)
    local captions = {
        { key = "total", text = "TOTAL" },
        { key = "dps",   text = "DPS 5s" },
        { key = "hits",  text = "HITS" },
    }
    for i, cap in ipairs(captions) do
        local chip = mk("Frame", {
            Size = UDim2.new(1 / 3, -(16 / 3), 1, 0),
            LayoutOrder = i,
        }, statsRow)
        corner(chip, 10)
        local chipStroke = stroke(chip, 1)
        local caption = mk("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 6),
            Size = UDim2.new(1, 0, 0, 12),
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = currentPal.subtext,
            Text = cap.text,
        }, chip)
        local value = mk("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 19),
            Size = UDim2.new(1, 0, 0, 26),
            Font = Enum.Font.GothamBold,
            TextSize = 20,
            TextColor3 = currentPal.accent,
            Text = "0",
        }, chip)
        statLabels[cap.key] = value
        bind(function(pal)
            chip.BackgroundColor3 = pal.card
            chip.BackgroundTransparency = 0.05
            chipStroke.Color = pal.stroke
            chipStroke.Transparency = 0.55
            caption.TextColor3 = pal.subtext
            value.TextColor3 = pal.accent
        end)
    end

    sectionLabel(sf, "урон")
    makeSwitch(sf, "hit-детектор (клик -> raycast -> урон)", settings.hitDetector,
        function(v) settings.hitDetector = v end)
    makeSwitch(sf, "headshot x2 (эмуляция)", settings.headshotMult,
        function(v) settings.headshotMult = v end)
    makeSwitch(sf, "всплывающие числа урона", settings.floatDamage,
        function(v) settings.floatDamage = v end)
    makeSwitch(sf, "полоска HP над головой", settings.healthBar,
        function(v) setHealthBar(v) end)
    makeSlider(sf, "TEST DAMAGE (если оружие не сообщает)", 1, 200, 1, settings.testDamage,
        function(v) settings.testDamage = v end)
    local row, add = makeRow(sf, 3)
    add("TEST HIT", "accent", testHit)
    add("HEAL", "plain", healDummy)
    add("RESET", "danger", resetStats)
    makeHint(sf, "Урон берётся из твоего Tool (атрибут или Value Damage/DMG). Если игра его не сообщает — применяется TEST DAMAGE, попадания помечаются est. god mode игнорирует весь урон.")

    sectionLabel(sf, "log")
    logHolder = mk("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 168),
        BackgroundColor3 = currentPal.card,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.35,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        LayoutOrder = nextOrder(),
    }, sf)
    corner(logHolder, 10)
    local logStroke = stroke(logHolder, 1)
    mk("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, logHolder)
    mk("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
    }, logHolder)
    bind(function(pal)
        logHolder.BackgroundColor3 = pal.card
        logHolder.BackgroundTransparency = 0.05
        logStroke.Color = pal.stroke
        logStroke.Transparency = 0.55
        for _, entry in ipairs(logEntries) do
            paintLogEntry(entry)
        end
    end)
end

---------------------------------------------------------------------
-- WINDOW BEHAVIOR: drag, toggle, theme, mobile
---------------------------------------------------------------------

do
    local dragging = false
    local dragStart, startPos
    header.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = io.Position
            startPos = main.Position
        end
    end)
    header.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(io)
        if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement
            or io.UserInputType == Enum.UserInputType.Touch) then
            local delta = io.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
end)

themeBtn.MouseButton1Click:Connect(function()
    themeMode = (themeMode == "dark") and "white" or "dark"
    currentPal = THEMES[themeMode]
    repaint()
    paintTabBar()
    saveAll()
    notify("тема: " .. themeMode)
end)

UserInputService.InputBegan:Connect(function(io, gameProcessed)
    if gameProcessed then return end
    if io.KeyCode == CONFIG.TOGGLE_KEY then
        main.Visible = not main.Visible
    end
end)

if UserInputService.TouchEnabled then
    local bubble = mk("TextButton", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -14, 1, -80),
        Size = UDim2.fromOffset(44, 44),
        Font = Enum.Font.GothamBlack,
        TextSize = 18,
        AutoButtonColor = true,
        Text = "D",
        ZIndex = 60,
    }, gui)
    corner(bubble, 22)
    local bubbleStroke = stroke(bubble, 1)
    bind(function(pal)
        bubble.BackgroundColor3 = pal.accent
        bubble.TextColor3 = pal.btnText
        bubble.BackgroundTransparency = 0.1
        bubbleStroke.Color = pal.accent2
        bubbleStroke.Transparency = 0.3
    end)
    bubble.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
    end)
end

---------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------

-- перекраска оверлеев живого манекена при смене темы
table.insert(repainters, function(pal)
    if dummy.highlight then
        pcall(function()
            dummy.highlight.FillColor = pal.accent
            dummy.highlight.OutlineColor = pal.accent2
        end)
    end
    if dummy.hpGui then
        pcall(function()
            local bg = dummy.hpGui:FindFirstChildOfClass("Frame")
            if bg then bg.BackgroundColor3 = pal.bg end
        end)
        updateHpBar()
    end
end)

currentPal = THEMES[themeMode] or THEMES.dark
repaint()
paintTabBar()
updateStats()
updateStatus()
notify("Damage Dummy " .. CONFIG.VERSION .. " — RightShift скрывает панель")

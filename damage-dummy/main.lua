--[[=====================================================================
    W H I T E C H E A T S   •   D A M A G E   D U M M Y
    version: 1.0.0

    Локальный (client-side) NPC-манекен для теста урона.
    Модель существует только на твоём клиенте: сервер её не видит,
    другие игроки видят, будто ты стреляешь в пустоту.

    Возможности:
      - R6-манекен (сборка с нуля) или клон твоего персонажа (R15/R6);
      - внешность: имя, цвет кожи, футболка и штаны по ID,
        волосы и аксессуары по ID;
      - движение: стоит / бродит / следует за тобой, WalkSpeed,
        JumpPower, радиус брожения;
      - тест урона: лог попаданий, суммарный урон, DPS за окно 5 сек,
        всплывающие числа урона, полоска HP над головой;
      - god mode, авто-респаун с задержкой, лечение, сброс статистики.

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
    VERSION    = "1.0.0",
    TOGGLE_KEY = Enum.KeyCode.RightShift,
    STATE_PATH = "whitecheats_damage_dummy.json",
    UI_WIDTH   = 520,
    UI_HEIGHT  = 500,
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
}

local themeMode = "dark"

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

-- forward declarations (заполняются ниже)
local dummy        -- состояние манекена
local spawnDummy   -- спавн / респаун

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

local main = mk("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(1, -(CONFIG.UI_WIDTH + 24), 0.5, 0),
    Size = UDim2.fromOffset(CONFIG.UI_WIDTH, CONFIG.UI_HEIGHT),
    BackgroundColor3 = currentPal.bg,
    BackgroundTransparency = currentPal.glassT,
    BorderSizePixel = 0,
    Active = false,
}, gui)
corner(main, 14)
local mainStroke = stroke(main, 1)

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
    mk("UIScale", { Scale = 0.66 }, main)
end

---------------------------------------------------------------------
-- HEADER
---------------------------------------------------------------------

local header = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundTransparency = 1,
    Active = true,
}, main)

local title = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 0),
    Size = UDim2.new(1, -200, 1, 0),
    Font = Enum.Font.GothamBlack,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "DAMAGE DUMMY",
}, header)

local versionChip = mk("TextLabel", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 8),
    Size = UDim2.fromOffset(50, 22),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    Text = "v" .. CONFIG.VERSION,
}, header)
corner(versionChip, 6)

local closeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -72, 0, 8),
    Size = UDim2.fromOffset(24, 22),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Text = "✕",
}, header)
corner(closeBtn, 6)

local themeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -104, 0, 8),
    Size = UDim2.fromOffset(58, 22),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    AutoButtonColor = false,
    Text = "THEME",
}, header)
corner(themeBtn, 6)

---------------------------------------------------------------------
-- FOOTER
---------------------------------------------------------------------

local footer = mk("Frame", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 24),
    BackgroundTransparency = 1,
}, main)

local statusLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 0),
    Size = UDim2.new(1, -28, 1, 0),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "idle",
}, footer)

---------------------------------------------------------------------
-- TAB BAR + BODY
---------------------------------------------------------------------

local TAB_NAMES = { "SPAWN", "LOOK", "MOVE", "TEST" }
local currentTab = "SPAWN"

local tabBar = mk("Frame", {
    Position = UDim2.new(0, 10, 0, 46),
    Size = UDim2.new(1, -20, 0, 32),
    BackgroundTransparency = 1,
}, main)

local body = mk("Frame", {
    Position = UDim2.new(0, 10, 0, 84),
    Size = UDim2.new(1, -20, 1, -114),
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
                btn.TextColor3 = currentPal.btnText
                btn.BackgroundTransparency = 0
            else
                btn.BackgroundColor3 = currentPal.panel
                btn.TextColor3 = currentPal.subtext
                btn.BackgroundTransparency = 0.1
            end
        end
    end
end

for i, name in ipairs(TAB_NAMES) do
    local btn = mk("TextButton", {
        Position = UDim2.new((i - 1) / #TAB_NAMES, 3, 0, 0),
        Size = UDim2.new(1 / #TAB_NAMES, -6, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        AutoButtonColor = false,
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
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, sf)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 6),
    }, sf)
    tabFrames[name] = sf
    return sf
end

for _, name in ipairs(TAB_NAMES) do
    makeTab(name)
end

---------------------------------------------------------------------
-- UI COMPONENTS
---------------------------------------------------------------------

local function paintButton(btn, kind)
    if kind == "accent" then
        btn.BackgroundColor3 = currentPal.accent
        btn.TextColor3 = currentPal.btnText
    elseif kind == "danger" then
        btn.BackgroundColor3 = currentPal.danger
        btn.TextColor3 = currentPal.btnText
    else
        btn.BackgroundColor3 = currentPal.panel
        btn.TextColor3 = currentPal.text
    end
    btn.BackgroundTransparency = (kind == "plain") and 0.1 or 0
end

local function makeButton(parent, text, kind, onClick, order)
    local btn = mk("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        AutoButtonColor = false,
        Text = text,
        LayoutOrder = order or 0,
    }, parent)
    corner(btn, 8)
    bind(function() paintButton(btn, kind) end)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

local function makeRow(parent, count, order)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
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

local function makeToggle(parent, label, value, onChange, order)
    local state = value == true
    local btn = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = order or 0,
    }, parent)
    corner(btn, 8)
    local dot = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.fromOffset(22, 30),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        Text = state and "●" or "○",
    }, btn)
    local lbl = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 36, 0, 0),
        Size = UDim2.new(1, -46, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = label,
    }, btn)
    bind(function(pal)
        btn.BackgroundColor3 = pal.panel
        btn.BackgroundTransparency = 0.1
        lbl.TextColor3 = pal.text
        dot.TextColor3 = state and pal.accent or pal.subtext
        dot.Text = state and "●" or "○"
    end)
    btn.MouseButton1Click:Connect(function()
        state = not state
        onChange(state)
        saveAll()
    end)
    return btn
end

local function makeSlider(parent, label, min, max, step, value, onChange, order)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
    }, parent)
    local nameLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 2, 0, 0),
        Size = UDim2.new(1, -60, 0, 18),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
    }, row)
    local valueLabel = mk("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -2, 0, 0),
        Size = UDim2.fromOffset(56, 18),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = tostring(value),
    }, row)
    local track = mk("Frame", {
        Position = UDim2.new(0, 2, 0, 28),
        Size = UDim2.new(1, -4, 0, 6),
        BackgroundColor3 = currentPal.panel,
        BorderSizePixel = 0,
    }, row)
    corner(track, 3)
    local trackStroke = stroke(track, 1)
    local fill = mk("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = currentPal.accent,
        BorderSizePixel = 0,
    }, track)
    corner(fill, 3)
    local knob = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = currentPal.text,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, track)
    corner(knob, 7)

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
    track.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(io.Position.X)
        end
    end)
    track.InputEnded:Connect(function(io)
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

    bind(function(pal)
        nameLabel.TextColor3 = pal.subtext
        valueLabel.TextColor3 = pal.text
        track.BackgroundColor3 = pal.panel
        trackStroke.Color = pal.stroke
        trackStroke.Transparency = 0.5
        fill.BackgroundColor3 = pal.accent
        knob.BackgroundColor3 = pal.text
    end)

    apply(value, false)
end

local function makeSegment(parent, options, current, onPick, order)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
    }, parent)
    local selected = current
    local buttons = {}
    local function paint()
        for _, opt in ipairs(options) do
            local btn = buttons[opt]
            if btn then
                if opt == selected then
                    btn.BackgroundColor3 = currentPal.accent
                    btn.TextColor3 = currentPal.btnText
                    btn.BackgroundTransparency = 0
                else
                    btn.BackgroundColor3 = currentPal.panel
                    btn.TextColor3 = currentPal.subtext
                    btn.BackgroundTransparency = 0.1
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
            Text = opt,
        }, row)
        corner(btn, 8)
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
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
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
        Size = UDim2.new(1, -4, 0, 28),
        BackgroundColor3 = currentPal.panel,
        BorderSizePixel = 0,
    }, wrap)
    corner(box, 8)
    local boxStroke = stroke(box, 1)
    local tb = mk("TextBox", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -20, 1, 0),
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
    tb.FocusLost:Connect(function()
        onChange(tb.Text)
        saveAll()
    end)
    return wrap
end

local function makeHint(parent, text, order)
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
        LayoutOrder = order or 0,
    }, parent)
    return label
end

bind(function(pal)
    main.BackgroundColor3 = pal.bg
    main.BackgroundTransparency = pal.glassT
    mainStroke.Color = pal.stroke
    mainStroke.Transparency = 0.45
    title.TextColor3 = pal.text
    versionChip.BackgroundColor3 = pal.panel
    versionChip.TextColor3 = pal.subtext
    themeBtn.BackgroundColor3 = pal.panel
    themeBtn.TextColor3 = pal.text
    closeBtn.BackgroundColor3 = pal.panel
    closeBtn.TextColor3 = pal.text
    statusLabel.TextColor3 = pal.subtext
end)

-- repaint подсказок
local hintPainters = {}
local function bindHint(label)
    table.insert(hintPainters, label)
end
table.insert(repainters, function(pal)
    for _, label in ipairs(hintPainters) do
        label.TextColor3 = pal.subtext
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
    BackgroundColor3 = currentPal.panel,
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
        statusLabel.Text = "манекена нет — кнопка SPAWN во вкладке SPAWN"
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
    local char = LocalPlayer.Character
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

local function myChar()
    local c = LocalPlayer.Character
    if c and c.Parent then return c end
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

local function floatDamage(amount)
    local head = dummy.head
    local model = dummy.model
    if not (head and model) then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "WC_FloatDmg"
    bb.Adornee = head
    bb.Size = UDim2.fromOffset(150, 42)
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
    tl.TextSize = 18
    tl.Text = "-" .. string.format("%.1f", amount)
    tl.TextColor3 = currentPal.danger
    tl.TextStrokeTransparency = 0.4
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

local function logLine(text)
    if not logHolder then return end
    logCounter = logCounter + 1
    local entry = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = currentPal.subtext,
        Text = text,
        LayoutOrder = -logCounter,
    }, logHolder)
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
-- DAMAGE WIRING + RESPAWN
---------------------------------------------------------------------

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
        local prev = dummy.lastHealth
        dummy.lastHealth = h
        local delta = prev - h
        if delta > 0.05 then
            dummy.hitCount = dummy.hitCount + 1
            dummy.totalDamage = dummy.totalDamage + delta
            table.insert(dummy.window, { t = os.clock(), d = delta })
            updateStats()
            updateHpBar()
            if settings.floatDamage then floatDamage(delta) end
            logLine(string.format("-%.1f  %s", delta, os.date("%H:%M:%S")))
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

local function raycastParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if dummy.model then table.insert(exclude, dummy.model) end
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
            raycastParams())
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
        notify("манекен вылечен")
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

    -- процедурная анимация: ходьба на месте / лёгкий idle
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
    local row1, add1 = makeRow(sf, 2, 1)
    add1("SPAWN", "accent", spawnInFront)
    add1("AT AIM", "plain", spawnAtAim)
    local row2, add2 = makeRow(sf, 2, 2)
    add2("TO ME", "plain", teleportToMe)
    add2("DELETE", "danger", deleteDummy)
    makeToggle(sf, "авто-респаун", settings.respawn, function(v) settings.respawn = v end, 3)
    makeSlider(sf, "респаун, сек", 1, 10, 0.5, settings.respawnDelay,
        function(v) settings.respawnDelay = v end, 4)
    makeSlider(sf, "радиус брожения", 5, 60, 1, settings.wanderRadius,
        function(v) settings.wanderRadius = v end, 5)
    local hint = makeHint(sf, "SPAWN — манекен появляется перед тобой, AT AIM — в точку прицела. Манекен виден только на твоём клиенте.", 6)
    bindHint(hint)
end

-- LOOK
do
    local sf = tabFrames.LOOK
    makeSegment(sf, { "R6", "R15" }, settings.rig,
        function(v) settings.rig = v end, 1)
    makeInput(sf, "имя", "Dummy", settings.name,
        function(v) settings.name = v end, 2)
    makeInput(sf, "футболка — id (пусто = твоя, 0 = снять)", "1839374", settings.shirt,
        function(v) settings.shirt = v end, 3)
    makeInput(sf, "штаны — id (пусто = твои, 0 = снять)", "1148986", settings.pants,
        function(v) settings.pants = v end, 4)
    makeInput(sf, "волосы / аксессуары — id через запятую", "13781923, 927184302", settings.accessories,
        function(v) settings.accessories = v end, 5)
    makeInput(sf, "цвет кожи — hex (например d9a066)", "d9a066", settings.skin,
        function(v) settings.skin = v end, 6)
    makeToggle(sf, "подсветка манекена", settings.highlight,
        function(v) setHighlight(v) end, 7)
    local row, add = makeRow(sf, 1, 8)
    add("APPLY LOOK", "accent", applyLookNow)
    local hint = makeHint(sf, "APPLY LOOK пересоздаёт манекен на его текущем месте с новыми настройками внешности. R15 — точная копия твоего персонажа.", 9)
    bindHint(hint)
end

-- MOVE
do
    local sf = tabFrames.MOVE
    makeSegment(sf, { "stand", "wander", "follow" }, settings.motion,
        function(v) settings.motion = v end, 1)
    makeSlider(sf, "walkspeed", 0, 100, 1, settings.walkspeed,
        function(v) settings.walkspeed = v end, 2)
    makeSlider(sf, "jumppower", 0, 200, 5, settings.jumppower,
        function(v) settings.jumppower = v end, 3)
    local hint = makeHint(sf, "stand — стоит на месте; wander — бродит вокруг точки спавна; follow — ходит за тобой.", 4)
    bindHint(hint)
end

-- TEST
do
    local sf = tabFrames.TEST
    local statsRow = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
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
        corner(chip, 8)
        local chipStroke = stroke(chip, 1)
        local caption = mk("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 4),
            Size = UDim2.new(1, 0, 0, 12),
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextColor3 = currentPal.subtext,
            Text = cap.text,
        }, chip)
        local value = mk("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            TextColor3 = currentPal.text,
            Text = "0",
        }, chip)
        statLabels[cap.key] = value
        bind(function(pal)
            chip.BackgroundColor3 = pal.card
            chip.BackgroundTransparency = 0.05
            chipStroke.Color = pal.stroke
            chipStroke.Transparency = 0.55
            caption.TextColor3 = pal.subtext
            value.TextColor3 = pal.text
        end)
    end

    makeSlider(sf, "max health", 10, 5000, 10, settings.maxHealth,
        function(v) setMaxHealth(v) end, 2)
    makeToggle(sf, "god mode — урон игнорируется", settings.godMode,
        function(v) setGodMode(v) end, 3)
    makeToggle(sf, "всплывающие числа урона", settings.floatDamage,
        function(v) settings.floatDamage = v end, 4)
    makeToggle(sf, "полоска HP над головой", settings.healthBar,
        function(v) setHealthBar(v) end, 5)

    local row, add = makeRow(sf, 2, 6)
    add("HEAL", "plain", healDummy)
    add("RESET STATS", "plain", resetStats)

    local hint = makeHint(sf, "Стреляй или бей манекен — урон считается локально: лог, TOTAL, DPS за последние 5 секунд.", 7)
    bindHint(hint)

    mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "LOG",
        LayoutOrder = 8,
    }, sf)

    logHolder = mk("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 150),
        BackgroundColor3 = currentPal.card,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.35,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        LayoutOrder = 9,
    }, sf)
    corner(logHolder, 8)
    local logStroke = stroke(logHolder, 1)
    mk("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, logHolder)
    mk("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
    }, logHolder)
    bind(function(pal)
        logHolder.BackgroundColor3 = pal.card
        logHolder.BackgroundTransparency = 0.05
        logStroke.Color = pal.stroke
        logStroke.Transparency = 0.55
    end)
    bind(function(pal)
        for _, entry in ipairs(logEntries) do
            entry.TextColor3 = pal.subtext
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
        AutoButtonColor = false,
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
notify("Damage Dummy " .. CONFIG.VERSION .. " готов — RightShift скрывает панель")

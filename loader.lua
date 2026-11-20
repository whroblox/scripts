--[[=====================================================================
    W H I T E C H E A T S  •  L O A D E R
    version: 1.0.0
    style: glass
    themes: dark / white / system / auto

    Loader автоматически собирает информацию об актуальных скриптах
    из репозитория: каждая папка скрипта содержит manifest.json
    (карточку). Папки с префиксом "_" — системные, в каталог не
    попадают. Если GitHub API недоступен, loader читает резервный
    catalog.json.

    Правила WhiteCheats для скриптов:
      - только client-side, никакого вреда игре и игрокам;
      - эмодзи в коде запрещены, разрешены символы и SVG-иконки.

    Запуск:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/whroblox/scripts/main/loader.lua"))()

    Управление:
      RightControl        — показать / скрыть окно
      кнопка THEME:       — листает темы dark -> white -> system -> auto
      кнопка ⟳            — обновить каталог скриптов
=====================================================================]]

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {
    REPO_OWNER     = "whroblox",   -- владелец репозитория
    REPO_NAME      = "scripts",
    BRANCH         = "main",
    API_BASE       = "https://api.github.com",
    RAW_BASE       = "https://raw.githubusercontent.com",
    LOADER_VERSION = "1.0.0",
    TOGGLE_KEY     = Enum.KeyCode.RightControl,
    STATE_PATH     = "whitecheats_state.json",
    UI_WIDTH       = 480,
    UI_HEIGHT      = 560,
}

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- THEMES (dark / white / system / auto)
---------------------------------------------------------------------

local THEMES = {
    dark = {
        title   = "DARK",
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
        shadow  = 0.45,
        glassT  = 0.06,
    },
    white = {
        title   = "WHITE",
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
        shadow  = 0.72,
        glassT  = 0.10,
    },
}

local THEME_MODES = { "dark", "white", "system", "auto" }
local MODE_LABELS = { dark = "DARK", white = "WHITE", system = "SYSTEM", auto = "AUTO" }

local function loadState()
    if type(readfile) ~= "function" then return nil end
    local ok, raw = pcall(readfile, CONFIG.STATE_PATH)
    if not ok or type(raw) ~= "string" then return nil end
    local okJson, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if okJson and type(data) == "table" then return data end
    return nil
end

local function saveState(s)
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(CONFIG.STATE_PATH, HttpService:JSONEncode(s))
    end)
end

local state = loadState() or {}
if type(state.mode) ~= "string" then state.mode = "auto" end

-- Roblox не даёт прочитать тему ОС напрямую, поэтому:
--   system -> последний ручной выбор пользователя, если он был; иначе как auto
--   auto   -> день (07:00-19:59) white, ночь dark
local function dayTheme()
    local hour = tonumber(os.date("%H")) or 12
    if hour >= 7 and hour < 20 then return "white" end
    return "dark"
end

local function resolveTheme(mode)
    if mode == "dark" or mode == "white" then return mode end
    if mode == "system" then
        if state.last == "dark" or state.last == "white" then return state.last end
        return dayTheme()
    end
    return dayTheme()
end

local currentPal = THEMES[resolveTheme(state.mode)] or THEMES.dark

local repainters = {}
local function bind(painter)
    table.insert(repainters, painter)
    pcall(painter, currentPal)
end

---------------------------------------------------------------------
-- HTTP
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
    if type(httpRequest) ~= "function" then
        error("executor does not expose an HTTP function", 0)
    end
    local res = httpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "WhiteCheats-Loader/" .. CONFIG.LOADER_VERSION,
            ["Accept"]     = "application/vnd.github+json",
        },
    })
    if type(res) ~= "table" then error("empty HTTP response", 0) end
    local status = res.StatusCode or res.code or res.status_code
    local body = res.Body or res.body
    if status ~= nil and status ~= 200 then error("HTTP " .. tostring(status), 0) end
    if type(body) ~= "string" then error("no HTTP body", 0) end
    return body
end

local function httpGetJson(url)
    return HttpService:JSONDecode(httpGet(url))
end

local function loadRemoteImage(url)
    if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then return nil end
    local ok, assetId = pcall(function()
        local path = "wc_icon_" .. tostring(math.random(100000000, 999999999)) .. ".png"
        writefile(path, httpGet(url))
        local id = getcustomasset(path)
        pcall(function() delfile(path) end)
        return id
    end)
    if ok and assetId then return assetId end
    return nil
end

---------------------------------------------------------------------
-- CATALOG (авто-сбор информации об актуальных скриптах)
---------------------------------------------------------------------

local function fetchCatalog()
    local scripts = {}
    local apiUrl = CONFIG.API_BASE .. "/repos/" .. CONFIG.REPO_OWNER .. "/" .. CONFIG.REPO_NAME
    local rawUrl = CONFIG.RAW_BASE .. "/" .. CONFIG.REPO_OWNER .. "/" .. CONFIG.REPO_NAME .. "/" .. CONFIG.BRANCH

    -- 1) GitHub API: перечисляем папки репозитория
    local okApi, listing = pcall(httpGetJson, apiUrl .. "/contents?ref=" .. CONFIG.BRANCH)
    if okApi and type(listing) == "table" then
        for _, item in ipairs(listing) do
            if type(item) == "table" and item.type == "dir" and string.sub(item.name, 1, 1) ~= "_" then
                local okManifest, manifest = pcall(httpGetJson, rawUrl .. "/" .. item.name .. "/manifest.json")
                if okManifest and type(manifest) == "table" and manifest.hidden ~= true then
                    manifest.id = manifest.id or item.name
                    manifest.folder = item.name
                    table.insert(scripts, manifest)
                end
            end
        end
        if #scripts > 0 then return scripts, "api" end
    end

    -- 2) Резервный каталог catalog.json
    local okCatalog, catalog = pcall(httpGetJson, rawUrl .. "/catalog.json")
    if okCatalog and type(catalog) == "table" and type(catalog.scripts) == "table" then
        for _, entry in ipairs(catalog.scripts) do
            if type(entry) == "table" and entry.hidden ~= true then
                entry.id = entry.id or entry.name
                table.insert(scripts, entry)
            end
        end
        return scripts, "catalog"
    end

    return nil, (not okApi) and "github api unavailable" or "catalog is empty"
end

---------------------------------------------------------------------
-- UI ROOT
---------------------------------------------------------------------

local GUI_NAME = "WhiteCheatsLoader"

local function killOld()
    local roots = {}
    local okHui, hui = pcall(function() return (type(gethui) == "function") and gethui() or nil end)
    if okHui and hui then table.insert(roots, hui) end
    pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
    pcall(function()
        local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then table.insert(roots, pg) end
    end)
    for _, r in ipairs(roots) do
        pcall(function()
            local old = r:FindFirstChild(GUI_NAME)
            if old then old:Destroy() end
        end)
    end
end

killOld()

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function mount()
    local roots = {}
    local okHui, hui = pcall(function() return (type(gethui) == "function") and gethui() or nil end)
    if okHui and hui then table.insert(roots, hui) end
    table.insert(roots, game:GetService("CoreGui"))
    pcall(function()
        local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then table.insert(roots, pg) end
    end)
    for _, parent in ipairs(roots) do
        local ok = pcall(function() gui.Parent = parent end)
        if ok and gui.Parent then return true end
    end
    return false
end

local function mk(class, props, parent)
    local inst = Instance.new(class)
    for key, value in pairs(props) do
        inst[key] = value
    end
    inst.Parent = parent
    return inst
end

-- стеклянный контейнер с тенью
local container = mk("Frame", {
    Name = "Container",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(CONFIG.UI_WIDTH, CONFIG.UI_HEIGHT),
}, gui)

local uiScale = mk("UIScale", { Scale = 1 }, container)

local shadow = mk("ImageLabel", {
    Name = "Shadow",
    BackgroundTransparency = 1,
    Image = "rbxassetid://1316045217",
    ImageColor3 = Color3.new(0, 0, 0),
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(10, 10, 118, 118),
    Size = UDim2.new(1, 70, 1, 70),
    Position = UDim2.new(0, -35, 0, -35),
    ZIndex = 0,
}, container)

local root = mk("Frame", {
    Name = "Root",
    Size = UDim2.new(1, 0, 1, 0),
    ZIndex = 1,
}, container)

mk("UICorner", { CornerRadius = UDim.new(0, 18) }, root)

local rootStroke = mk("UIStroke", {
    Thickness = 1,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, root)

local rootGradient = mk("UIGradient", { Rotation = 115 }, root)

bind(function(pal)
    root.BackgroundColor3 = pal.bg
    root.BackgroundTransparency = pal.glassT
    shadow.ImageTransparency = pal.shadow
end)
bind(function(pal)
    rootStroke.Color = pal.stroke
    rootStroke.Transparency = 0.35
end)
bind(function(pal)
    rootGradient.Color = ColorSequence.new(
        ColorSequenceKeypoint.new(0, pal.bg),
        ColorSequenceKeypoint.new(1, pal.panel)
    )
end)

---------------------------------------------------------------------
-- HEADER
---------------------------------------------------------------------

local header = mk("Frame", {
    Name = "Header",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 58),
}, root)

local brandDot = mk("Frame", {
    Size = UDim2.fromOffset(10, 10),
    Position = UDim2.new(0, 18, 0, 17),
}, header)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, brandDot)
bind(function(pal) brandDot.BackgroundColor3 = pal.accent end)

local title = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 36, 0, 9),
    Size = UDim2.new(0, 240, 0, 22),
    Font = Enum.Font.GothamBlack,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "WHITECHEATS",
}, header)
bind(function(pal) title.TextColor3 = pal.text end)

local subtitle = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 36, 0, 31),
    Size = UDim2.new(0, 240, 0, 14),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "WHITE SCRIPTS • ROBLOX",
}, header)
bind(function(pal) subtitle.TextColor3 = pal.subtext end)

local themeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -204, 0, 14),
    Size = UDim2.fromOffset(122, 30),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    AutoButtonColor = false,
    Text = "THEME: AUTO",
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, themeBtn)
local themeStroke = mk("UIStroke", { Thickness = 1 }, themeBtn)
bind(function(pal)
    themeBtn.BackgroundColor3 = pal.panel
    themeBtn.TextColor3 = pal.text
    themeStroke.Color = pal.stroke
    themeStroke.Transparency = 0.3
end)

local refreshBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -58, 0, 14),
    Size = UDim2.fromOffset(30, 30),
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    AutoButtonColor = false,
    Text = "⟳",
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, refreshBtn)
bind(function(pal)
    refreshBtn.BackgroundColor3 = pal.panel
    refreshBtn.TextColor3 = pal.accent
end)

local closeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 14),
    Size = UDim2.fromOffset(30, 30),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Text = "✕",
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, closeBtn)
bind(function(pal)
    closeBtn.BackgroundColor3 = pal.panel
    closeBtn.TextColor3 = pal.danger
end)

---------------------------------------------------------------------
-- LIST + FOOTER
---------------------------------------------------------------------

local list = mk("ScrollingFrame", {
    Name = "List",
    Position = UDim2.new(0, 10, 0, 66),
    Size = UDim2.new(1, -20, 1, -104),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageTransparency = 0.2,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, root)
bind(function(pal) list.ScrollBarImageColor3 = pal.accent end)

mk("UIListLayout", {
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

local footer = mk("Frame", {
    Name = "Footer",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 34),
}, root)

local statusLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 16, 0, 0),
    Size = UDim2.new(1, -130, 1, 0),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "STATUS: READY",
}, footer)
bind(function(pal) statusLabel.TextColor3 = pal.subtext end)

local versionLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -16, 0, 0),
    Size = UDim2.new(0, 110, 1, 0),
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = "AUTO • v1.0.0",
}, footer)
bind(function(pal) versionLabel.TextColor3 = pal.subtext end)

-- плавающая кнопка для мобильных (открыть/скрыть окно)
local bubble = mk("TextButton", {
    Name = "Bubble",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 18, 1, -18),
    Size = UDim2.fromOffset(42, 42),
    Font = Enum.Font.GothamBlack,
    TextSize = 16,
    AutoButtonColor = false,
    Text = "W",
}, gui)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, bubble)
local bubbleStroke = mk("UIStroke", { Thickness = 1 }, bubble)
bind(function(pal)
    bubble.BackgroundColor3 = pal.accent
    bubble.TextColor3 = pal.btnText
    bubbleStroke.Color = pal.btnText
    bubbleStroke.Transparency = 0.75
end)

---------------------------------------------------------------------
-- TOAST / STATUS
---------------------------------------------------------------------

local toastCount = 0

local function toast(message)
    toastCount = toastCount + 1
    local card = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -64 - (toastCount - 1) * 58),
        Size = UDim2.new(0, 300, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 10,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
    local cardStroke = mk("UIStroke", { Thickness = 1 }, card)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
    }, card)
    local label = mk("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextWrapped = true,
        Text = tostring(message),
        ZIndex = 10,
    }, card)
    bind(function(pal)
        card.BackgroundColor3 = pal.panel
        cardStroke.Color = pal.stroke
        cardStroke.Transparency = 0.3
        label.TextColor3 = pal.text
    end)
    card.BackgroundTransparency = 1
    label.TextTransparency = 1
    TweenService:Create(card, TweenInfo.new(0.25), { BackgroundTransparency = 0.08 }):Play()
    TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    task.delay(3, function()
        local out1 = TweenService:Create(card, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
        local out2 = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 })
        out1:Play()
        out2:Play()
        out1.Completed:Wait()
        card:Destroy()
        toastCount = math.max(0, toastCount - 1)
    end)
end

local function setStatus(message)
    statusLabel.Text = "STATUS: " .. string.upper(tostring(message))
end

---------------------------------------------------------------------
-- CARDS
---------------------------------------------------------------------

local busyButtons = {}

local function entryUrl(entry)
    return CONFIG.RAW_BASE .. "/" .. CONFIG.REPO_OWNER .. "/" .. CONFIG.REPO_NAME .. "/" .. CONFIG.BRANCH
        .. "/" .. (entry.folder or entry.id) .. "/" .. (entry.entry or "main.lua")
end

local function inject(entry, btn)
    if busyButtons[btn] then return end
    busyButtons[btn] = true
    btn.Text = "..."
    setStatus("injecting: " .. tostring(entry.name or entry.id))
    task.spawn(function()
        local ok, err = pcall(function()
            local code = httpGet(entryUrl(entry))
            local compile = loadstring or load
            local fn, compileErr = compile(code, "=" .. tostring(entry.name or entry.id))
            if type(fn) ~= "function" then
                error(compileErr or "compile failed", 0)
            end
            fn()
        end)
        if ok then
            btn.Text = "DONE"
            setStatus("injected: " .. tostring(entry.name or entry.id))
            toast(tostring(entry.name or entry.id) .. " — запуск выполнен")
        else
            btn.Text = "FAIL"
            setStatus("inject failed")
            toast("Ошибка запуска: " .. string.sub(tostring(err), 1, 120))
            warn("[WhiteCheats] inject error:", err)
        end
        task.delay(2.5, function()
            btn.Text = "INJECT"
            busyButtons[btn] = nil
        end)
    end)
end

local function makeCard(entry, order)
    local card = mk("Frame", {
        Name = "Card_" .. tostring(entry.id),
        Size = UDim2.new(1, -4, 0, 88),
        LayoutOrder = order,
    }, list)
    mk("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
    local cardStroke = mk("UIStroke", { Thickness = 1 }, card)
    bind(function(pal)
        card.BackgroundColor3 = pal.card
        card.BackgroundTransparency = 0.05
        cardStroke.Color = pal.stroke
        cardStroke.Transparency = 0.55
    end)

    -- иконка карточки
    local iconBox = mk("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(52, 52),
    }, card)
    mk("UICorner", { CornerRadius = UDim.new(0, 12) }, iconBox)
    local iconStroke = mk("UIStroke", { Thickness = 1 }, iconBox)
    local iconLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 22,
        Text = "✦",
    }, iconBox)
    bind(function(pal)
        iconBox.BackgroundColor3 = pal.panel
        iconStroke.Color = pal.accent
        iconStroke.Transparency = 0.55
        iconLabel.TextColor3 = pal.accent
    end)

    -- png-иконка из папки скрипта, если executor умеет getcustomasset
    if type(entry.icon) == "string" and string.sub(string.lower(entry.icon), -4) == ".png" then
        task.spawn(function()
            local url = CONFIG.RAW_BASE .. "/" .. CONFIG.REPO_OWNER .. "/" .. CONFIG.REPO_NAME .. "/" .. CONFIG.BRANCH
                .. "/" .. (entry.folder or entry.id) .. "/" .. entry.icon
            local assetId = loadRemoteImage(url)
            if assetId and iconLabel.Parent then
                iconLabel.Text = ""
                mk("ImageLabel", {
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    Size = UDim2.new(1, -12, 1, -12),
                    Image = assetId,
                }, iconBox)
            end
        end)
    end

    local nameLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 76, 0, 12),
        Size = UDim2.new(1, -186, 0, 18),
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(entry.name or entry.id or "script"),
    }, card)
    bind(function(pal) nameLabel.TextColor3 = pal.text end)

    local versionChip = mk("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 12),
        Size = UDim2.fromOffset(58, 18),
        Font = Enum.Font.Gotham,
        TextSize = 10,
        Text = "v" .. tostring(entry.version or "1.0"),
    }, card)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, versionChip)
    bind(function(pal)
        versionChip.BackgroundColor3 = pal.panel
        versionChip.TextColor3 = pal.subtext
    end)

    local descLabel = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 76, 0, 34),
        Size = UDim2.new(1, -186, 0, 40),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(entry.description or "без описания"),
    }, card)
    bind(function(pal) descLabel.TextColor3 = pal.subtext end)

    local injectBtn = mk("TextButton", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -14, 1, -14),
        Size = UDim2.fromOffset(82, 28),
        Font = Enum.Font.GothamBlack,
        TextSize = 12,
        AutoButtonColor = false,
        Text = "INJECT",
    }, card)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, injectBtn)
    local injectGradient = mk("UIGradient", { Rotation = 45 }, injectBtn)
    bind(function(pal)
        injectBtn.BackgroundColor3 = pal.accent
        injectBtn.TextColor3 = pal.btnText
        injectGradient.Color = ColorSequence.new(
            ColorSequenceKeypoint.new(0, pal.accent),
            ColorSequenceKeypoint.new(1, pal.accent2)
        )
    end)
    injectBtn.MouseButton1Click:Connect(function()
        inject(entry, injectBtn)
    end)
end

local function makeStateCard(titleText, hintText, order)
    local card = mk("Frame", {
        Name = "StateCard",
        Size = UDim2.new(1, -4, 0, 108),
        LayoutOrder = order or 999,
    }, list)
    mk("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
    local cardStroke = mk("UIStroke", { Thickness = 1 }, card)
    local titleL = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 22),
        Size = UDim2.new(1, -32, 0, 20),
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = titleText,
    }, card)
    local hintL = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 48),
        Size = UDim2.new(1, -32, 0, 40),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = hintText,
    }, card)
    bind(function(pal)
        card.BackgroundColor3 = pal.panel
        card.BackgroundTransparency = 0.35
        cardStroke.Color = pal.stroke
        cardStroke.Transparency = 0.45
        titleL.TextColor3 = pal.text
        hintL.TextColor3 = pal.subtext
    end)
end

local function clearCards()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function renderScripts(scripts)
    clearCards()
    if #scripts == 0 then
        makeStateCard("Пока нет активных скриптов", "Добавь папку скрипта с manifest.json в репозиторий и нажми ⟳")
        setStatus("catalog empty")
        return
    end
    table.sort(scripts, function(a, b)
        return string.lower(tostring(a.name or a.id or "")) < string.lower(tostring(b.name or b.id or ""))
    end)
    for index, entry in ipairs(scripts) do
        makeCard(entry, index)
    end
    setStatus(#scripts .. " script(s) loaded")
end

local refreshBusy = false

local function refreshCatalog()
    if refreshBusy then return end
    refreshBusy = true
    setStatus("loading catalog")
    clearCards()
    makeStateCard("Загрузка каталога", "Тянем актуальный список скриптов из репозитория")
    task.spawn(function()
        local ok, result, source = pcall(fetchCatalog)
        refreshBusy = false
        if not ok or not result then
            local reason = (type(result) == "string") and result or "unknown error"
            clearCards()
            makeStateCard("Каталог недоступен", reason)
            setStatus("catalog error")
            toast("Не удалось получить каталог: " .. reason)
            return
        end
        renderScripts(result)
        toast("Каталог обновлён • источник: " .. tostring(source))
    end)
end

---------------------------------------------------------------------
-- THEME SWITCH
---------------------------------------------------------------------

local function applyTheme()
    local resolved = resolveTheme(state.mode)
    if state.mode == "dark" or state.mode == "white" then
        state.last = state.mode
    end
    saveState(state)
    currentPal = THEMES[resolved] or THEMES.dark
    for _, painter in ipairs(repainters) do
        pcall(painter, currentPal)
    end
    versionLabel.Text = string.upper(resolved) .. " • v" .. CONFIG.LOADER_VERSION
end

local function updateThemeButton()
    themeBtn.Text = "THEME: " .. (MODE_LABELS[state.mode] or "AUTO")
end

local function cycleMode()
    local index = 1
    for i, mode in ipairs(THEME_MODES) do
        if mode == state.mode then
            index = i
            break
        end
    end
    state.mode = THEME_MODES[(index % #THEME_MODES) + 1]
    applyTheme()
    updateThemeButton()
    toast("Тема: " .. (MODE_LABELS[state.mode] or "AUTO"))
end

---------------------------------------------------------------------
-- VISIBILITY / DRAG / KEYBIND
---------------------------------------------------------------------

local visible = false

local function setVisible(target)
    visible = target
    if target then
        container.Visible = true
        uiScale.Scale = 0.92
        TweenService:Create(uiScale,
            TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Scale = 1 }):Play()
    else
        local tween = TweenService:Create(uiScale,
            TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
            { Scale = 0.92 })
        tween:Play()
        tween.Completed:Connect(function()
            if not visible then
                container.Visible = false
            end
        end)
    end
end

local function toggle()
    setVisible(not visible)
end

closeBtn.MouseButton1Click:Connect(function()
    setVisible(false)
end)

bubble.MouseButton1Click:Connect(toggle)
themeBtn.MouseButton1Click:Connect(cycleMode)
refreshBtn.MouseButton1Click:Connect(refreshCatalog)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == CONFIG.TOGGLE_KEY then
        toggle()
    end
end)

-- перетаскивание окна за шапку
local dragging = false
local dragStart, startPos

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = container.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        container.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- авто-перекраска для system/auto раз в минуту
task.spawn(function()
    while true do
        task.wait(60)
        if gui.Parent and (state.mode == "auto" or state.mode == "system") then
            applyTheme()
        end
    end
end)

---------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------

if not mount() then
    warn("[WhiteCheats] не удалось примонтировать интерфейс")
    return
end

applyTheme()
updateThemeButton()
refreshCatalog()
setVisible(true)

print("[WhiteCheats] loader v" .. CONFIG.LOADER_VERSION .. " готов • клавиша: RightControl")

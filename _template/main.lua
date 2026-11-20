--[[--------------------------------------------------------------------
    WhiteCheats • Script Template
    Заглушка: показывает, что шаблон подключился и работает.
    Только client-side. Эмодзи в коде запрещены — используем символы.
--------------------------------------------------------------------]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function showBadge()
    -- маленькая стеклянная плашка «шаблон подключён» на 3 секунды
    local ok, err = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "WhiteCheatsTemplateBadge"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 9998

        local frame = Instance.new("Frame")
        frame.AnchorPoint = Vector2.new(0.5, 1)
        frame.Position = UDim2.new(0.5, 0, 1, -24)
        frame.Size = UDim2.fromOffset(280, 44)
        frame.BackgroundColor3 = Color3.fromRGB(17, 17, 22)
        frame.BackgroundTransparency = 0.12
        frame.Parent = gui

        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, -16, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(235, 235, 245)
        label.Text = "WHITECHEATS • шаблон подключён"
        label.Parent = frame

        local okMount, hui = pcall(function()
            return (type(gethui) == "function") and gethui() or nil
        end)
        if okMount and hui then
            gui.Parent = hui
        else
            gui.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                or game:GetService("CoreGui")
        end

        task.delay(3, function()
            gui:Destroy()
        end)
    end)
    if not ok then
        warn("[WhiteCheats] template badge error:", err)
    end
end

print("[WhiteCheats] template connected • client-side only")
showBadge()

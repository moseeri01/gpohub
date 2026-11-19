-- moseeri gpo: hub window for Grand Piece Online (2026-11-19).
-- Window kit copied from moseeri nexus (NexusFarm.lua). Built by build.ps1 from src/head.lua + kit + core + impel + world + pages.
-- Lua 5.1 only. Every callback runs in pcall. Fires no game remotes: the Impel Down part walks, presses
-- proximity prompts and swings the held tool like a player. Settings in Workspace/gpohub/config.json.

local G = (getgenv and getgenv()) or _G
if G.__gpo_hub_stop then pcall(G.__gpo_hub_stop) end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local FOLDER = "gpohub"
local VERSION = "m_26"

-- Every thread the hub starts runs inside pcall. The game's anti-cheat listens to ScriptContext.Error and sends the
-- text of errors from scripts that are not its own to the server (read in the decompiled "anti" module), so an
-- error of ours must never surface. task.spawn / task.delay / task.defer below are these safe versions.
local hubErrors = {}
local rawTask = task
local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            hubErrors[#hubErrors + 1] = os.date("%H:%M:%S ") .. tostring(err):sub(1, 200)
            if #hubErrors > 20 then table.remove(hubErrors, 1) end
        end
    end
end
local task = setmetatable({
    spawn = function(fn, ...) return rawTask.spawn(guarded(fn), ...) end,
    delay = function(t, fn, ...) return rawTask.delay(t, guarded(fn), ...) end,
    defer = function(fn, ...) return rawTask.defer(guarded(fn), ...) end,
}, { __index = rawTask })

local F = {
    alive = true,
    conns = {},
    running = false,          -- Start / Stop on Home (never saved: always off after a load)
    status = "Idle",          -- one line: what the hub is doing or waiting for
    lastAction = "",
    cfg = {
        -- Home
        mode = "Impel Down", stopHours = 3, stopOnKick = true, keepStart = true, reloadHub = true,
        -- Combat
        preset = "Safe", useSword = true, useFruit = true, useGun = false, useStyle = true,
        normalHits = true, groupMobs = true, stunLock = true, useHaki = true,
        autoDodge = true, autoBlock = true, stayBehind = true, safeSpot = true, retreatHp = 30,
        hover = false, freezeMobs = false,
        -- Impel Down
        idDiff = "Nightmare", idSolo = true, idSecret = true, idRequeue = true, idBuy = "Nothing", idKeep = 200000,
        mobNames = "", mobRange = 80, mobSkills = false, fruitAlert = true,
        idCuffs = true, idChests = true, idLoot = true, idSkipJunk = true, idFight = true, idFightRange = 40, idSkills = false, idBosses = false, idMaze = true, idGoPad = true,
        -- Boss
        bossHop = false, bossList = { Juzo = true },
        bossRadiant = false, bossRoger = false, bossHawk = false,
        seaSerpent = false, seaMegalodon = false, seaSoulKing = false,
        -- Raids / event
        evSpooks = false, evBaal = false,
        -- Fishing
        fishSpot = "Rough Waters", fishBait = true, fishSell = true, fishKeepLeg = true, fishMegalodon = false,
        -- Level
        lvlTarget = 325, lvlQuest = true, lvlMove = true, lvlStats = "Sword / Defense", autoStats = false, lvlHaki = false, lvlBlock = false,
        -- Settings
        normalSpeed = true, sprint = true, geppo = true, stopNearPlayer = true, antiAfk = true, autoRejoin = false,
        discordAlert = false, pickUp = false, webhook = "", bossAlert = true, bossRange = 300, bossSkills = false,
    },
}

--------------------------------------------------------------------------------
-- files
--------------------------------------------------------------------------------
local canFiles = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
local function ensureFolder()
    if canFiles and type(isfolder) == "function" and type(makefolder) == "function" then
        pcall(function() if not isfolder(FOLDER) then makefolder(FOLDER) end end)
    end
end
local logLines = {}
local function log(msg)
    F.lastAction = os.date("%H:%M:%S ") .. tostring(msg)
    logLines[#logLines + 1] = F.lastAction
end
local function saveAll()
    if not canFiles then return end
    ensureFolder()
    pcall(function() writefile(FOLDER .. "/config.json", HttpService:JSONEncode({ cfg = F.cfg })) end)
end
local function loadAll()
    if not canFiles then return end
    pcall(function()
        if not isfile(FOLDER .. "/config.json") then return end
        local d = HttpService:JSONDecode(readfile(FOLDER .. "/config.json"))
        if type(d.cfg) == "table" then
            for k, v in pairs(d.cfg) do
                if F.cfg[k] ~= nil and type(v) == type(F.cfg[k]) then F.cfg[k] = v end
            end
        end
    end)
end
loadAll()
task.spawn(function()
    while F.alive do
        task.wait(5)
        while #hubErrors > 0 do logLines[#logLines + 1] = "hub error (caught): " .. table.remove(hubErrors, 1) end
        if #logLines > 0 and canFiles then
            ensureFolder()
            local chunk = table.concat(logLines, "\n") .. "\n"
            logLines = {}
            pcall(function()
                local old = isfile(FOLDER .. "/log.txt") and readfile(FOLDER .. "/log.txt") or ""
                writefile(FOLDER .. "/log.txt", old:sub(-60000) .. chunk)
            end)
        end
    end
end)

--------------------------------------------------------------------------------
-- UI: own window in the moseeri hub (AA) style - wide, tabs across the top, two columns of cards.
-- Same theme values as AA (UIRef.Theme). No MacLib.
--------------------------------------------------------------------------------
local UIS = game:GetService("UserInputService")
local T = {
    bg = Color3.fromRGB(11, 11, 13), headBg = Color3.fromRGB(4, 4, 5), card = Color3.fromRGB(17, 17, 21),
    line = Color3.fromRGB(30, 30, 37), text = Color3.fromRGB(212, 212, 218), value = Color3.fromRGB(180, 180, 190),
    mute = Color3.fromRGB(138, 138, 148), faint = Color3.fromRGB(88, 88, 98), accent = Color3.fromRGB(138, 180, 255),
    onAccent = Color3.fromRGB(11, 11, 13), off = Color3.fromRGB(44, 44, 52), good = Color3.fromRGB(143, 209, 158),
    bad = Color3.fromRGB(232, 104, 104), white = Color3.fromRGB(236, 236, 242),
}
local UI = { pages = {}, tabs = {}, refreshers = {} }

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function stroke(o, c) new("UIStroke", { Color = c or T.line, Thickness = 1 }, o) end
local function label(parent, text, size, color, font, props)
    local l = new("TextLabel", {
        BackgroundTransparency = 1, Text = text, TextSize = size or 13, TextColor3 = color or T.text,
        Font = font or Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
    for k, v in pairs(props or {}) do l[k] = v end
    return l
end

local guiParent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
pcall(function() local o = guiParent:FindFirstChild("MoseeriGPO") if o then o:Destroy() end end)
pcall(function() local o = guiParent:FindFirstChild("GPOHubToggle") if o then o:Destroy() end end)
local gui = new("ScreenGui", { Name = "MoseeriGPO", ResetOnSpawn = false, DisplayOrder = 998, IgnoreGuiInset = true })
local WIN_W, HEAD_H, TAB_H = 780, 92, 40
local win = new("Frame", { Size = UDim2.fromOffset(WIN_W, 300), Position = UDim2.new(0.5, -WIN_W / 2, 0, 150),
    BackgroundColor3 = T.bg, BorderSizePixel = 0, Active = true }, gui)
corner(win, 12)
stroke(win)
-- (11-14 test: a tap on an empty part of the window went through to the game and opened its Events page.
-- An invisible button under everything takes those taps)
new("TextButton", { Name = "Sink", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 0 }, win)
local scale = new("UIScale", { Scale = 1 }, win)
pcall(function()
    local vp = workspace.CurrentCamera.ViewportSize
    scale.Scale = math.clamp(math.min(vp.X * 0.62 / WIN_W, vp.Y * 0.8 / 460), 0.55, 1.2)
end)

-- header: spaced title, subtitle, a few stars, the ··· button hides the window
local head = new("Frame", { Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = T.headBg, BorderSizePixel = 0 }, win)
corner(head, 12)
new("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = T.headBg, BorderSizePixel = 0 }, head)
label(head, "M O S E E R I   G P O", 26, T.white, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -120, 0, 32) })
label(head, "Grand Piece Online · auto farm", 12, T.mute, Enum.Font.Gotham, { Position = UDim2.fromOffset(28, 56), Size = UDim2.new(1, -120, 0, 16) })
local rng = Random.new(7)
for _ = 1, 26 do
    local s = rng:NextInteger(1, 2)
    new("Frame", { Size = UDim2.fromOffset(s, s), Position = UDim2.new(rng:NextNumber(0.35, 0.98), 0, rng:NextNumber(0.1, 0.9), 0),
        BackgroundColor3 = T.white, BackgroundTransparency = rng:NextNumber(0.3, 0.8), BorderSizePixel = 0 }, head)
end
local dots = new("TextButton", { Size = UDim2.fromOffset(40, 28), Position = UDim2.new(1, -56, 0, 18), BackgroundTransparency = 1,
    Text = "···", TextSize = 20, TextColor3 = T.mute, Font = Enum.Font.GothamBold }, head)

-- drag by the header (mouse and touch)
do
    local dragging, start, startPos
    -- (11-14 test: the window slid on later taps - the drag only ends when THIS touch ends, and only the same
    -- touch moves it)
    local dragInput
    head.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, start, startPos, dragInput = true, input.Position, win.Position, input
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false dragInput = nil c:Disconnect() end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local same = (input == dragInput) or (input.UserInputType == Enum.UserInputType.MouseMovement and dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1)
        if same then
            local d = (input.Position - start) / scale.Scale
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false dragInput = nil end
    end)
end

-- tabs
local tabBar = new("Frame", { Size = UDim2.new(1, -40, 0, TAB_H), Position = UDim2.fromOffset(20, HEAD_H), BackgroundTransparency = 1 }, win)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)
new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, HEAD_H + TAB_H), BackgroundColor3 = T.line, BorderSizePixel = 0 }, win)
local body = new("Frame", { Size = UDim2.new(1, -36, 0, 10), Position = UDim2.fromOffset(18, HEAD_H + TAB_H + 10), BackgroundTransparency = 1 }, win)

local function fitHeight(page)
    local h = 0
    for _, col in ipairs(page.cols) do
        local ch = 0
        for _, c in ipairs(col:GetChildren()) do
            if c:IsA("Frame") then ch = ch + c.AbsoluteSize.Y / scale.Scale + 10 end
        end
        if ch > h then h = ch end
    end
    win.Size = UDim2.fromOffset(WIN_W, HEAD_H + TAB_H + 20 + h)
end
function UI.show(name)
    for n, p in pairs(UI.pages) do p.frame.Visible = (n == name) end
    for n, t in pairs(UI.tabs) do
        t.btn.TextColor3 = (n == name) and T.white or T.mute
        t.bar.Visible = (n == name)
    end
    UI.current = name
    task.delay(0.15, function() pcall(fitHeight, UI.pages[name]) end)
end
function UI.page(name, order)
    local btn = new("TextButton", { AutoButtonColor = false, BackgroundTransparency = 1, Text = name, TextSize = 14,
        Font = Enum.Font.GothamMedium, TextColor3 = T.mute, LayoutOrder = order, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X }, tabBar)
    local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = T.accent, BorderSizePixel = 0, Visible = false }, btn)
    UI.tabs[name] = { btn = btn, bar = bar }
    local frame = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, body)
    local cols = {}
    for i = 1, 2 do
        local col = new("Frame", { Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.new((i - 1) * 0.5, (i - 1) * 6, 0, 0), BackgroundTransparency = 1 }, frame)
        new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, col)
        cols[i] = col
    end
    local page = { frame = frame, cols = cols }
    UI.pages[name] = page
    btn.MouseButton1Click:Connect(function() UI.show(name) end)
    return page
end

-- a card: title + rows with a hairline between them
local cardN = 0
function UI.card(page, side, title)
    cardN = cardN + 1
    local c = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.card,
        BorderSizePixel = 0, LayoutOrder = cardN }, page.cols[side])
    corner(c, 10)
    new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }, c)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, c)
    label(c, title, 14, T.white, Enum.Font.GothamMedium, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0 })
    return { frame = c, n = 0 }
end
local function row(card, text, h)
    card.n = card.n + 1
    local r = new("Frame", { Size = UDim2.new(1, 0, 0, h or 38), BackgroundTransparency = 1, LayoutOrder = card.n }, card.frame)
    if card.n > 1 then new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line, BorderSizePixel = 0 }, r) end
    label(r, text, 13, T.text, Enum.Font.Gotham, { Size = UDim2.new(0.62, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
    return r
end

-- switch
function UI.toggle(card, text, get, setv)
    local r = row(card, text)
    local word = label(r, "", 11, T.faint, Enum.Font.GothamMedium, { Size = UDim2.fromOffset(30, 20), Position = UDim2.new(1, -84, 0.5, -10), TextXAlignment = Enum.TextXAlignment.Right })
    local sw = new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -46, 0.5, -12),
        BackgroundColor3 = T.off, BorderSizePixel = 0 }, r)
    corner(sw, 12)
    local knob = new("Frame", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = T.white, BorderSizePixel = 0 }, sw)
    corner(knob, 8)
    local function paint()
        local on = get() and true or false
        sw.BackgroundColor3 = on and T.accent or T.off
        knob.Position = on and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3)
        word.Text = on and "ON" or "OFF"
        word.TextColor3 = on and T.accent or T.faint
    end
    sw.MouseButton1Click:Connect(function() pcall(setv, not get()) paint() end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end
-- choice: the value on the right, a tap goes to the next option
function UI.choice(card, text, options, get, setv)
    local r = row(card, text)
    local b = new("TextButton", { AutoButtonColor = false, BackgroundColor3 = T.off, BorderSizePixel = 0, Size = UDim2.new(0.45, 0, 0, 26), Position = UDim2.new(0.55, 0, 0.5, -13),
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.white, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }, r)
    corner(b, 6)
    local function paint() b.Text = tostring(get()) .. "  ›" end
    b.MouseButton1Click:Connect(function()
        local cur, i = tostring(get()), 0
        for k, o in ipairs(options) do if tostring(o) == cur then i = k end end
        pcall(setv, options[i % #options + 1])
        paint()
    end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end
-- number with - and +
function UI.stepper(card, text, lo, hi, get, setv, step)
    local r = row(card, text)
    local box = new("Frame", { Size = UDim2.fromOffset(104, 26), Position = UDim2.new(1, -104, 0.5, -13), BackgroundTransparency = 1 }, r)
    local v = label(box, "", 13, T.value, Enum.Font.GothamMedium, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
    local function btn(txt, x, d)
        local b = new("TextButton", { AutoButtonColor = false, Text = txt, TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = T.text,
            BackgroundColor3 = T.off, Size = UDim2.fromOffset(26, 26), Position = UDim2.new(x, x == 0 and 0 or -26, 0, 0), BorderSizePixel = 0 }, box)
        corner(b, 6)
        b.MouseButton1Click:Connect(function() pcall(setv, math.clamp((tonumber(get()) or lo) + d, lo, hi)) v.Text = tostring(get()) end)
    end
    btn("−", 0, -(step or 1))
    btn("+", 1, (step or 1))
    v.Text = tostring(get())
    UI.refreshers[#UI.refreshers + 1] = function() v.Text = tostring(get()) end
end
-- outlined accent button, like AA "Setup ›"
function UI.button(card, text, btnText, fn)
    local r = row(card, text)
    local b = new("TextButton", { AutoButtonColor = false, Text = btnText .. "  ›", TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = T.accent,
        BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 28), Position = UDim2.new(1, -110, 0.5, -14) }, r)
    corner(b, 7)
    stroke(b, T.accent)
    b.MouseButton1Click:Connect(function() task.spawn(function() pcall(fn) end) end)
end
-- label + live value
function UI.info(card, text, getText)
    local r = row(card, text)
    local v = label(r, "", 13, T.value, Enum.Font.Gotham, { Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0.4, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
    UI.refreshers[#UI.refreshers + 1] = function() local ok, s = pcall(getText) v.Text = ok and tostring(s) or "-" end
end
function UI.note(card, text)
    card.n = card.n + 1
    label(card.frame, text, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, LayoutOrder = card.n, TextYAlignment = Enum.TextYAlignment.Top })
end

-- pills: several on/off choices in one row (wraps)
function UI.pills(card, options, isOn, toggleOne)
    card.n = card.n + 1
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = card.n }, card.frame)
    new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, holder)
    new("UIGridLayout", { CellSize = UDim2.fromOffset(84, 26), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
    local paints = {}
    for i, o in ipairs(options) do
        local b = new("TextButton", { AutoButtonColor = false, Text = o, TextSize = 12, Font = Enum.Font.GothamMedium, LayoutOrder = i, BorderSizePixel = 0 }, holder)
        corner(b, 13)
        local function paint()
            local on = isOn(o)
            b.BackgroundColor3 = on and T.accent or T.off
            b.TextColor3 = on and T.onAccent or T.mute
        end
        b.MouseButton1Click:Connect(function() pcall(toggleOne, o) paint() end)
        paint()
        paints[#paints + 1] = paint
    end
    UI.refreshers[#UI.refreshers + 1] = function() for _, p in ipairs(paints) do p() end end
end
-- text box on the right of a row
function UI.input(card, text, placeholder, get, setv)
    local r = row(card, text)
    local box = new("TextBox", { Size = UDim2.new(0.5, 0, 0, 26), Position = UDim2.new(0.5, 0, 0.5, -13), BackgroundColor3 = T.off, BorderSizePixel = 0,
        Text = tostring(get() or ""), PlaceholderText = placeholder, PlaceholderColor3 = T.faint, TextColor3 = T.text, Font = Enum.Font.Gotham,
        TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, r)
    corner(box, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
    box.FocusLost:Connect(function() pcall(setv, box.Text) end)
end

local function notify(msg)
    log(msg)
    pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "moseeri gpo", Text = tostring(msg), Duration = 4 }) end)
end
local function cfgSet(key) return function(v) F.cfg[key] = v saveAll() end end
local function cfgGet(key) return function() return F.cfg[key] end end

--------------------------------------------------------------------------------
-- core: shared moves for every mode (2026-11-19). Walk only (Humanoid:MoveTo along a path), press
-- proximity prompts, swing the held tool. The game checks speed / noclip on the server
-- (SpeedBypass / NoclipBypass attributes seen in recordings), so nothing here teleports or flies.
--------------------------------------------------------------------------------
local C = {}
F.core = C
do
    local PFS = game:GetService("PathfindingService")
    local VIM = nil
    pcall(function() VIM = game:GetService("VirtualInputManager") end)
    C.VIM = VIM

    function C.char() return LP.Character end
    function C.root() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") end
    function C.hum() local c = LP.Character return c and c:FindFirstChildOfClass("Humanoid") end
    function C.alive() local h = C.hum() return h ~= nil and h.Health > 0 end
    function C.hpPct() local h = C.hum() return h and h.MaxHealth > 0 and (h.Health / h.MaxHealth * 100) or 0 end

    function C.where(o)
        if o:IsA("BasePart") then return o.Position end
        if o:IsA("Model") then local ok, cf = pcall(function() return o:GetPivot() end) return ok and cf.Position or nil end
        if o:IsA("Attachment") then return o.WorldPosition end
        return nil
    end
    function C.promptPos(p)
        local a = p.Parent
        while a and a ~= workspace do
            local v = C.where(a)
            if v then return v end
            a = a.Parent
        end
        return nil
    end

    -- another player close by (Settings: stop when a player is near)
    function C.playerNear(dist)
        local r = C.root()
        if not r then return nil end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local pr = p.Character:FindFirstChild("HumanoidRootPart")
                if pr and (pr.Position - r.Position).Magnitude < dist then return p end
            end
        end
        return nil
    end

    -- The game's own input layer (read from the decompiled Backpack scripts, m_8 probe):
    --   Backpack.Movements : double W  -> InputCallbacks.Callbacks.Run.HoldingRun = true ; Run:PC_Activate()   (sprint, WalkSpeed 25)
    --   Backpack.MeleeScript: mouse 1  -> while held: if InputCallbacks.Utils.canAutoM1() then Callbacks.Attack:PC_Activate()
    --   key J -> Callbacks.Buso:PC_Activate() ; key Q -> Callbacks.Dash:PC_Activate()
    -- The hub calls the same functions, so the game sends its own calls exactly as for a key press.
    -- The Backpack (and this module) is new after every respawn, so it is looked up each time.
    function C.input()
        local bp = LP:FindFirstChild("Backpack")
        local m = bp and bp:FindFirstChild("InputCallbacks")
        if not m then return nil end
        if C.icMod ~= m then
            local ok, t = pcall(require, m)
            C.icMod = m
            C.ic = (ok and type(t) == "table" and type(t.Callbacks) == "table") and t or nil
            log(C.ic and "input: game callbacks ready" or ("input: cannot use game callbacks (" .. tostring(t):sub(1, 80) .. ")"))
        end
        return C.ic
    end
    function C.sprint(on)
        local ic = C.input()
        local run = ic and ic.Callbacks.Run
        if not run then return end
        if not on then
            if C.sprintOn then C.sprintOn = false pcall(function() run.HoldingRun = false end) end
            return
        end
        local c = LP.Character
        if (c and c:GetAttribute("MovementSprintActive")) or os.clock() - (C.sprintAt or 0) < 1 then return end
        C.sprintAt = os.clock()
        C.sprintOn = true
        if not C.sprintLogged then C.sprintLogged = true log("sprint: asking the game to run") end
        task.spawn(function()
            local ok, e = pcall(function()
                run.HoldingRun = true
                run:PC_Activate()
            end)
            if not ok and not C.sprintErr then C.sprintErr = true log("sprint error: " .. tostring(e):sub(1, 120)) end
        end)
    end

    -- A Seat on the way makes the character sit down and every walk stops (loop tick 20:38: state "Seated" at
    -- 5953,12,-10132 on the pad route - it jumped off, touched the seat and sat again, for minutes). While the hub
    -- walks, sitting is switched off on our own Humanoid and switched back on afterwards.
    function C.noSit(on)
        local h = C.hum()
        if not h then return end
        pcall(function()
            if on and h.Sit then h.Sit = false end
            h:SetStateEnabled(Enum.HumanoidStateType.Seated, not on)
        end)
    end

    -- walk to pos; false on timeout, stuck, stop() or Start turned off. Long walks sprint (Settings).
    function C.walkTo(pos, near, limit, stop)
        C.noSit(true)
        local r0 = C.root()
        C.wantSprint = (F.cfg.sprint and r0 ~= nil and (r0.Position - pos).Magnitude > 30) or false
        local ok, res = pcall(C.walkInner, pos, near, limit, stop)
        C.wantSprint = false
        C.sprint(false)
        C.noSit(false)
        return ok and res or false
    end
    function C.walkInner(pos, near, limit, stop)
        local h, r = C.hum(), C.root()
        if not h or not r then return false end
        near = near or 4
        local t0 = os.clock()
        local points = { pos }
        local pathState = "no path call"
        -- why a walk failed goes to the log (at most one line every 3 s)
        local function fail(why)
            if os.clock() - (C.failAt or 0) > 3 then
                C.failAt = os.clock()
                local rr = C.root()
                log(string.format("walk failed: %s (path %s, %.0f left, speed %s)", why, pathState,
                    rr and (rr.Position - pos).Magnitude or -1, tostring(h.WalkSpeed)))
            end
            return false
        end
        pcall(function()
            local path = PFS:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
            path:ComputeAsync(r.Position, pos)
            pathState = tostring(path.Status):gsub("Enum.PathStatus.", "")
            if path.Status == Enum.PathStatus.Success then
                points = {}
                for _, w in ipairs(path:GetWaypoints()) do points[#points + 1] = w end
            end
        end)
        -- Path waypoints lie on the ground, the root part about 3 studs above it. Measured in 3D the first waypoint
        -- (our own feet) was never "reached" and the walk stood still (remote test 20:30: WalkToPoint = own position).
        -- So: arrival is measured flat (X / Z), and the first waypoint of a real path is skipped.
        local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
        for i, w in ipairs(points) do
            local target = typeof(w) == "Vector3" and w or w.Position
            if i == 1 and #points > 1 then target = nil end
            if target then
            if typeof(w) ~= "Vector3" and w.Action == Enum.PathWaypointAction.Jump then h.Jump = true end
            local lastPos, stuck = r.Position, 0
            while F.alive and F.running and C.alive() do
                r = C.root()
                if not r then return false end
                if flat(r.Position, pos) <= near and math.abs(r.Position.Y - pos.Y) < 12 then return true end
                if flat(r.Position, target) <= 3 then break end
                if os.clock() - t0 > (limit or 20) then return fail("timeout") end
                if stop and stop() then return false end
                h:MoveTo(target)
                if C.wantSprint then C.sprint(true) end
                task.wait(0.25)
                if Vector3.new(r.Position.X - lastPos.X, 0, r.Position.Z - lastPos.Z).Magnitude < 0.5 then
                    stuck = stuck + 1
                    if stuck >= 4 and stuck % 4 == 0 then C.sidestep(target) elseif stuck >= 7 then C.overObstacle() elseif stuck >= 3 then C.jump() end
                    if stuck >= 28 then return fail("not moving for 7 s") end
                else stuck = 0 end
                lastPos = r.Position
            end
            end
        end
        r = C.root()
        return r ~= nil and flat(r.Position, pos) <= near + 2
    end

    -- jump the way a player does: the game's Movements script owns jumping (it switches JumpPower between 0 and
    -- 50 and allows one jump a second), so Humanoid.Jump = true is ignored most of the time. A Space key press
    -- goes through that script.
    function C.jump()
        if os.clock() - (C.jumpAt or 0) < 1.15 then return end
        C.jumpAt = os.clock()
        if VIM then
            task.spawn(function()
                pcall(function()
                    VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                    task.wait(0.08)
                    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                end)
            end)
        else
            local h = C.hum()
            if h then h.Jump = true end
        end
    end
    -- Geppo (sky walk) = the game's own move: Callbacks.Geppo:PC_Activate() while in the air pushes the character
    -- along its move direction and up; the game grants its own jump / fly allowance for it. Needs Rokushiki /
    -- Black Leg / Kamishiki or the skyWalk skill, stamina, not cuffed; in combat 5 in a row then 2 s on the ground
    -- (read in the decompiled Geppo script). Used only to get over something the walk is stuck on.
    function C.geppo()
        local ic = C.input()
        local g = ic and ic.Callbacks.Geppo
        if not g then return false end
        task.spawn(function() pcall(function() g:PC_Activate() end) end)
        return true
    end
    function C.overObstacle()
        if not F.cfg.geppo or os.clock() - (C.hopAt or 0) < 3 then return end
        C.hopAt = os.clock()
        C.jumpAt = 0
        C.jump()
        task.wait(0.3)
        local used = 0
        for _ = 1, 3 do
            local h = C.hum()
            if not h or h.FloorMaterial ~= Enum.Material.Air then break end
            if C.geppo() then used = used + 1 end
            task.wait(0.4)
        end
        if used > 0 and not C.geppoLogged then C.geppoLogged = true log("geppo: used to get over an obstacle") end
    end
    -- stuck against an edge (door frame, pillar): step sideways for a moment, left and right in turn, a bit
    -- further each time. Loop tick 20:35: stood at 5953,9,-10132 before route point 14 (5957,10,-10143), already on
    -- the right height, 3.6 studs left of the recorded line -> blocked by the side of an opening.
    function C.sidestep(toward)
        local h, r = C.hum(), C.root()
        if not h or not r then return end
        local dir = Vector3.new(toward.X - r.Position.X, 0, toward.Z - r.Position.Z)
        if dir.Magnitude < 0.5 then return end
        dir = dir.Unit
        C.sideN = (C.sideN or 0) + 1
        local side = (C.sideN % 2 == 0) and 1 or -1
        local reach = 4 + 2 * math.floor((C.sideN - 1) / 2)
        local perp = Vector3.new(-dir.Z, 0, dir.X) * side * math.min(reach, 12)
        h:MoveTo(r.Position + perp - dir * 1.5)
        task.wait(0.55)
    end
    -- straight walk to a point, no path search; jumps when it stops moving (steps, ledges)
    function C.walkStraight(pos, near, limit)
        local t0, lastPos, stuck = os.clock(), nil, 0
        while F.alive and F.running and C.alive() do
            local h, r = C.hum(), C.root()
            if not h or not r then return false end
            local flat = Vector3.new(pos.X, r.Position.Y, pos.Z)
            if (r.Position - flat).Magnitude <= (near or 4) then return true end
            if os.clock() - t0 > (limit or 12) then return false end
            h:MoveTo(pos)
            if C.wantSprint then C.sprint(true) end
            task.wait(0.2)
            if lastPos and Vector3.new(r.Position.X - lastPos.X, 0, r.Position.Z - lastPos.Z).Magnitude < 0.4 then
                stuck = stuck + 1
                if stuck >= 4 and stuck % 4 == 0 then C.sidestep(pos) elseif stuck >= 6 then C.overObstacle() elseif stuck >= 2 then C.jump() end
                if stuck >= 40 then return false end
            else
                if stuck == 0 then C.sideN = 0 end
                stuck = 0
            end
            lastPos = r.Position
        end
        return false
    end
    -- follow a recorded hand route (list of Vector3): start at the route point nearest to us, then on to the end
    function C.followRoute(points, near)
        local r = C.root()
        if not r then return false end
        local first, bestD = 1, math.huge
        for i, p in ipairs(points) do
            local d = (p - r.Position).Magnitude
            if d < bestD then first, bestD = i, d end
        end
        if first < #points then first = first + 1 end   -- the nearest point may be behind us
        C.wantSprint = F.cfg.sprint and true or false
        C.noSit(true)
        local ok = true
        for i = first, #points do
            if not C.walkTo(points[i], i == #points and (near or 4) or 6, 20) then
                ok = false
                local rr = C.root()
                if os.clock() - (C.failAt or 0) > 3 and rr then
                    C.failAt = os.clock()
                    log(string.format("route: stuck before point %d of %d @ %.0f,%.0f,%.0f", i, #points, rr.Position.X, rr.Position.Y, rr.Position.Z))
                end
                break
            end
        end
        C.wantSprint = false
        C.sprint(false)
        C.noSit(false)
        return ok
    end

    function C.key(k, hold)
        if not VIM then return end
        pcall(function()
            VIM:SendKeyEvent(true, k, false, game)
            task.wait(hold or 0.1)
            VIM:SendKeyEvent(false, k, false, game)
        end)
    end

    -- press a prompt: fireproximityprompt when the executor has it, else hold E next to it
    function C.press(p)
        if type(fireproximityprompt) == "function" and pcall(fireproximityprompt, p) then task.wait(0.3) return true end
        if not VIM then return false end
        C.key(Enum.KeyCode.E, (p.HoldDuration or 0) + 0.15)
        task.wait(0.3)
        return true
    end
    function C.usePrompt(p, what)
        local pos = C.promptPos(p)
        if not pos then return false end
        F.status = "Walking to " .. what .. " (" .. tostring(p.ObjectText) .. ")"
        local reach = math.max(2, (p.MaxActivationDistance or 10) - 2)
        if C.walkTo(pos, reach, 25, function() return not p.Parent end) and p.Parent then
            C.press(p)
            log(what .. ": " .. tostring(p.ObjectText))
            return true
        end
        return false
    end

    -- mobs: Workspace.NPCs, alive, and no ProximityPrompt (friendly NPCs like Bomi / Robo carry one)
    function C.isMob(m)
        if not m:IsA("Model") then return false end
        local h, hr = m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart")
        if not h or not hr or h.Health <= 0 then return false end
        if m:FindFirstChildWhichIsA("ProximityPrompt", true) then return false end
        return true
    end
    function C.nearestMob(range, accept)
        local npcs, r = workspace:FindFirstChild("NPCs"), C.root()
        if not npcs or not r then return nil end
        local best, bestD = nil, range
        for _, m in ipairs(npcs:GetChildren()) do
            if C.isMob(m) and (not accept or accept(m)) then
                local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
                if d < bestD then best, bestD = m, d end
            end
        end
        return best, bestD
    end

    -- Weapons are Tools with attribute Category = "Weapons" (scans): swords have no MeleeTool flag, fighting styles
    -- have MeleeTool = true, fruits also devilFruit = true. The hub used to look for a tool named "Melee" only;
    -- an account with a named style (Rokushiki ...) held nothing and canAutoM1() was false (Vera fight, 20:48).
    -- Order: keep a weapon already in hand; else sword, else fighting style, else fruit.
    local function weaponRank(t)
        if not t:IsA("Tool") or t:GetAttribute("Category") ~= "Weapons" then return nil end
        if t:GetAttribute("devilFruit") then return 3 end
        if t:GetAttribute("MeleeTool") then return 2 end
        return 1
    end
    function C.holdWeapon()
        local c = LP.Character
        if not c then return nil end
        local held = c:FindFirstChildOfClass("Tool")
        if held and weaponRank(held) then return held end
        local bp = LP:FindFirstChild("Backpack")
        local pick, best = nil, 99
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                local rk = weaponRank(t)
                if rk and rk < best then pick, best = t, rk end
            end
            pick = pick or bp:FindFirstChild("Melee")
        end
        if pick and C.hum() then
            pcall(function() C.hum():EquipTool(pick) end)
            if C.lastEquip ~= pick.Name then C.lastEquip = pick.Name log("equip: " .. pick.Name) end
            task.wait(0.3)
        end
        return c:FindFirstChildOfClass("Tool")
    end

    local SKILL_KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C }
    local lastSkill, skillN = 0, 0

    -- M1 has three ways (tool:Activate, an injected mouse click, the executor s own mouse1click). The game s swing
    -- call comes from Backpack.MeleeScript (recorded). First live raid (m_2): 5 s of Activate and of clicks showed no
    -- damage, with no way to tell "no swing" from "swing out of reach". So now two proofs are kept apart:
    --   swing  = the character s M1 attributes change (M1DashRecoverySwingId / LastLandedM1SwingId, seen in records)
    --   damage = target hp drops or leaderstats.Damage rises
    -- A way that swings is kept and the hub steps closer; a way that does not swing is swapped after 4 s.
    local ATK = { method = 1, names = { "game M1 call", "mouse click", "mouse1click" }, mark = nil, proven = false, swings = false, tries = 0, reach = 5 }
    C.atk = ATK
    local function dmgStat()
        local ls = LP:FindFirstChild("leaderstats")
        local d = ls and ls:FindFirstChild("Damage")
        return d and tonumber(d.Value) or 0
    end
    local function swingMark()
        local c = LP.Character
        if not c then return "" end
        return tostring(c:GetAttribute("M1DashRecoverySwingId")) .. "|" .. tostring(c:GetAttribute("LastLandedM1SwingId"))
    end
    -- a screen point for the click that is not on the hub window (screen centre first: the game aims with the mouse)
    local SPOTS = { { 0.5, 0.5 }, { 0.5, 0.3 }, { 0.3, 0.5 }, { 0.7, 0.5 }, { 0.15, 0.35 }, { 0.85, 0.35 } }
    local function clickPoint()
        local cam = workspace.CurrentCamera
        local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
        for _, sp in ipairs(SPOTS) do
            local x, y = v.X * sp[1], v.Y * sp[2]
            local onWin = false
            if win.Visible then
                local p, sz = win.AbsolutePosition, win.AbsoluteSize
                onWin = x >= p.X - 20 and x <= p.X + sz.X + 20 and y >= p.Y - 60 and y <= p.Y + sz.Y + 60
            end
            if not onWin then return x, y end
        end
        return 30, v.Y * 0.35
    end
    local function swing(tool)
        if ATK.method == 1 then
            -- the same call MeleeScript makes while mouse 1 is held (tool:Activate does nothing in this game)
            local ic = C.input()
            local atk = ic and ic.Callbacks.Attack
            if atk then
                local can = "?"
                pcall(function() can = ic.Utils.canAutoM1() end)
                ATK.can = can
                if can == true then task.spawn(function() pcall(function() atk:PC_Activate() end) end) end
            end
        elseif ATK.method == 2 then
            if not VIM then return end
            local x, y = clickPoint()
            pcall(function()
                VIM:SendMouseMoveEvent(x, y, game)
                VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
                task.wait(0.05)
                VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
        elseif type(mouse1click) == "function" then
            pcall(mouse1click)
        end
    end
    -- turn on the spot to face pos (position unchanged)
    local function face(pos)
        local r = C.root()
        if not r then return end
        local flat = Vector3.new(pos.X, r.Position.Y, pos.Z)
        if (flat - r.Position).Magnitude > 0.5 then pcall(function() r.CFrame = CFrame.lookAt(r.Position, flat) end) end
    end
    -- skills send the aim CFrame from the client (recorded), so point the camera and mouse at the target first
    local function aim(pos)
        pcall(function()
            local cam = workspace.CurrentCamera
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
            if VIM then VIM:SendMouseMoveEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, game) end
        end)
    end

    -- one attack beat on a mob: close in, face it, swing, maybe a skill
    function C.attack(m, useSkills)
        local hr, h = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
        if not hr or not h then return end
        F.status = "Fighting " .. m.Name .. " (" .. math.floor(h.Health) .. " hp)"
        -- Chase: a target that keeps moving (Vera, 20:50: 1 min without a hit, always 7-26 studs away) cannot be
        -- caught with a path search per step. Close targets are followed directly, re-aimed every 0.15 s, for up to
        -- 1.2 s per beat; only far ones use the path walk.
        local r = C.root()
        local d0 = r and (hr.Position - r.Position).Magnitude or 999
        if d0 > 45 then
            C.walkTo(hr.Position, ATK.reach, 4, function() return h.Health <= 0 end)
        elseif d0 > ATK.reach + 1 then
            local hm = C.hum()
            C.noSit(true)
            local t0 = os.clock()
            while hm and F.alive and F.running and h.Health > 0 and os.clock() - t0 < 1.2 do
                r = C.root()
                if not r or (hr.Position - r.Position).Magnitude <= ATK.reach then break end
                hm:MoveTo(hr.Position)
                if F.cfg.sprint and (hr.Position - r.Position).Magnitude > 15 then C.sprint(true) end
                task.wait(0.15)
            end
            C.noSit(false)
        end
        r = C.root()
        local dist = r and (hr.Position - r.Position).Magnitude or 999
        local close = dist <= 9
        face(hr.Position)
        local tool = C.holdWeapon()
        if close then
            local mk = ATK.mark
            if mk == nil or mk.m ~= m then
                mk = { m = m, hp = h.Health, dmg = dmgStat(), sw = swingMark(), t = os.clock(), swung = false }
                ATK.mark = mk
            end
            if swingMark() ~= mk.sw then
                mk.swung = true
                if not ATK.swings then
                    ATK.swings = true
                    log("swing seen with " .. ATK.names[ATK.method])
                end
            end
            if h.Health < mk.hp - 0.5 or dmgStat() > mk.dmg then
                if not ATK.proven then
                    ATK.proven = true
                    log(string.format("attack works: %s (dist %.1f, tool %s)", ATK.names[ATK.method], dist, tool and tool.Name or "none"))
                end
                ATK.mark = nil
            elseif not ATK.proven and os.clock() - mk.t > 4 then
                local what = string.format("dist %.1f, tool %s, target hp %.0f, canAutoM1 %s", dist, tool and tool.Name or "none", h.Health, tostring(ATK.can))
                if mk.swung then
                    -- it swings but nothing lands: stand closer instead of changing the way
                    ATK.reach = math.max(2.5, ATK.reach - 1)
                    log("swings but no damage in 4 s (" .. what .. ") - reach now " .. ATK.reach)
                else
                    ATK.method = ATK.method % #ATK.names + 1
                    ATK.tries = ATK.tries + 1
                    log("no swing in 4 s with the last way (" .. what .. ") - now: " .. ATK.names[ATK.method])
                end
                ATK.mark = nil
            end
        end
        swing(tool)
        -- no skills until a swing way is proven (or every way was tried), so the proof is not a skill s damage
        if useSkills and close and (ATK.proven or ATK.tries >= #ATK.names) and os.clock() - lastSkill > 4 then
            lastSkill = os.clock()
            skillN = skillN % #SKILL_KEYS + 1
            aim(hr.Position)
            C.key(SKILL_KEYS[skillN])
        end
        task.wait(0.25)
    end
end

-- Anti AFK (Settings): the usual Idled nudge
F.conns[#F.conns + 1] = LP.Idled:Connect(function()
    if not F.cfg.antiAfk then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end)

--------------------------------------------------------------------------------
-- Impel Down (id_1, 2026-11-19) - only what the recorder has seen in real runs:
--   cuffs  : char has "Cuffed"; prompt "Use" on "<me>'s Handcuff Key" in Workspace.Effects
--   chests : prompt "Open" on "Common Chest" / "Rare Chest" in Workspace.Effects
--   loot   : drops are Models in Workspace.Effects with attribute brItem=true, prompt "Grab"
--   guards : Workspace.NPCs."Impel Guard" (63 hp, sword + gun, come in groups)
--   stage  : ReplicatedStorage.matchEvents("waveInfo", text, nil, "ImpelDown") - listened to, never fired
-- Queue, difficulty vote, maze route, the end of the run and dying are NOT handled (never recorded).
--------------------------------------------------------------------------------
do
    local ID = { PLACE = 11424731604, WORLD = 7465136166, PAD = Vector3.new(5876, 9.6, -10213),prompts = {}, stage = "-", done = { chests = 0, loot = 0, keys = 0 } }
    F.impel = ID
    local JUNK = { ["Wooden Plank"] = true }
    function ID.inRaid() return game.PlaceId == ID.PLACE end

    task.spawn(function()
        local ev = game:GetService("ReplicatedStorage"):WaitForChild("matchEvents", 30)
        if not ev or not F.alive then return end
        F.conns[#F.conns + 1] = ev.OnClientEvent:Connect(function(kind, text, _, mode)
            if kind == "waveInfo" and type(text) == "string" then
                text = text:gsub("<[^>]+>", "")   -- some texts carry <font> tags
                ID.stage = text
                log("impel stage: " .. text .. " (" .. tostring(mode) .. ")")
            end
        end)
    end)

    -- prompts in Workspace.Effects kept in a set (no scan every tick)
    local function addPrompt(p) if p:IsA("ProximityPrompt") then ID.prompts[p] = true end end
    task.spawn(function()
        if not ID.inRaid() then return end
        local fx = workspace:WaitForChild("Effects", 30)
        if not fx or not F.alive then return end
        for _, d in ipairs(fx:GetDescendants()) do addPrompt(d) end
        F.conns[#F.conns + 1] = fx.DescendantAdded:Connect(addPrompt)
        F.conns[#F.conns + 1] = fx.DescendantRemoving:Connect(function(d) ID.prompts[d] = nil end)
    end)

    local function kindOf(p)
        local act, obj = p.ActionText or "", p.ObjectText or ""
        if act == "Use" and obj == (LP.Name .. "'s Handcuff Key") then return "key" end
        if act == "Open" and obj:match("Chest$") then return "chest" end
        if act == "Grab" then
            local m = p:FindFirstAncestorOfClass("Model")
            if m and m:GetAttribute("brItem") == true then
                if F.cfg.idSkipJunk and JUNK[obj] then return nil end
                return "loot"
            end
        end
        return nil
    end
    local function nearestPrompt(want, maxDist)
        local r = C.root()
        if not r then return nil end
        local best, bestD = nil, maxDist
        for p in pairs(ID.prompts) do
            local again = ID.pressed[p]
            if p.Parent and p.Enabled and kindOf(p) == want and not (again and os.clock() - again < 8) then
                local pos = C.promptPos(p)
                local d = pos and (pos - r.Position).Magnitude
                if d and d < bestD then best, bestD = p, d end
            end
        end
        return best
    end
    -- other enemies recorded in the raid: Blugori, Kelvin, Santa, Kramprus, Snow Wolf (bosses / event) - only with the switch
    ID.KEYSPOT = Vector3.new(3026.3, 2075.9, -13411.0)
    -- hand route from the Impel Base spawn to the raid pad (recorded 17:45, Af_terdark)
    ID.PADROUTE = {
        Vector3.new(5913.8, 5.4, -9792.2), Vector3.new(5914.7, 5.4, -9817.8), Vector3.new(5916.3, 5.4, -9860.5), Vector3.new(5917.3, 5.4, -9886.0),
        Vector3.new(5918.2, 5.3, -9911.2), Vector3.new(5919.2, 5.3, -9937.7), Vector3.new(5920.8, 5.3, -9980.3), Vector3.new(5921.8, 6.3, -10006.1),
        Vector3.new(5926.5, 9.8, -10029.9), Vector3.new(5931.9, 8.3, -10053.5), Vector3.new(5941.2, 8.3, -10076.3), Vector3.new(5942.2, 8.3, -10101.9),
        Vector3.new(5954.1, 5.3, -10122.4), Vector3.new(5956.6, 9.6, -10142.6), Vector3.new(5939.3, 9.6, -10161.3), Vector3.new(5906.0, 9.6, -10188.2),
        Vector3.new(5887.8, 9.6, -10206.2), Vector3.new(5878.7, 9.6, -10215.6), Vector3.new(5876.0, 9.6, -10213.0),
    }
    -- a pressed prompt is left alone for 8 s (m_2 pressed the same chest several times) and counted once
    ID.pressed = setmetatable({}, { __mode = "k" })
    local function use(p, what, counter)
        local first = ID.pressed[p] == nil
        if C.usePrompt(p, what) then
            ID.pressed[p] = os.clock()
            if first then ID.done[counter] = ID.done[counter] + 1 end
        end
    end
    function ID.count() local n = 0 for _ in pairs(ID.prompts) do n = n + 1 end return n end
    local function isGuard(m) return F.cfg.idBosses or m.Name == "Impel Guard" end

    -- maze (m_1). Floor 1 maze = a 75-stud grid: in the recorded run chests and corridor centre lines sit on
    -- x = 2540.1 + 75i, z = -14214 - 75j, and "END OF MAZE REACHED" came at 2990,-15281. Owner: walls change every
    -- run, the way out stays. So: search as we go - at each grid point rays tell which of the 4 neighbours are
    -- open, take the unvisited one nearest the exit, back up at dead ends. Walking only (server checks noclip / fly).
    local MZ = { X0 = 2540.1, Z0 = -14214, STEP = 75, exit = Vector3.new(2990.1, 2075.7, -15281),
        visited = {}, bad = {}, stack = {}, hops = 0, fails = 0, gaveUp = false }
    ID.maze = MZ
    local DIRS = { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }   -- +j runs toward the exit (-Z)
    local function nodeOf(pos) return math.floor((pos.X - MZ.X0) / MZ.STEP + 0.5), math.floor((MZ.Z0 - pos.Z) / MZ.STEP + 0.5) end
    local function nodePos(i, j, y) return Vector3.new(MZ.X0 + i * MZ.STEP, y, MZ.Z0 - j * MZ.STEP) end
    local function nkey(i, j) return i .. "," .. j end
    local rayParams = nil
    -- nothing solid between two points (see-through / walk-through parts are skipped)
    local function clear(from, to)
        if not rayParams then
            rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
        end
        local ignore = { C.char() }
        for _, n in ipairs({ "Effects", "NPCs", "PlayerCharacters", "Projectiles", "Ragdolls" }) do
            local f = workspace:FindFirstChild(n)
            if f then ignore[#ignore + 1] = f end
        end
        rayParams.FilterDescendantsInstances = ignore
        local origin = from
        for _ = 1, 6 do
            local dir = to - origin
            if dir.Magnitude < 1 then return true end
            local hit = workspace:Raycast(origin, dir, rayParams)
            if not hit then return true end
            if hit.Instance.CanCollide then return false end
            origin = hit.Position + dir.Unit * 0.2
        end
        return false
    end
    function ID.inMaze()
        if ID.stage:find("END OF MAZE", 1, true) then return false end
        if ID.stage:find("MAZE", 1, true) then return true end
        local r = C.root()   -- hub loaded mid-run: no stage text yet, go by the recorded maze area
        if ID.stage ~= "-" or not r then return false end
        local p = r.Position
        return p.Z < -14030 and p.Z > -15290 and p.X > 2500 and p.X < 3560
    end
    local function mazeStep()
        local r = C.root()
        if not r or MZ.gaveUp then
            if MZ.gaveUp then F.status = "Maze: no way found - walk by hand" end
            return
        end
        local y = r.Position.Y
        local i, j = nodeOf(r.Position)
        local k = nkey(i, j)
        local here = nodePos(i, j, y)
        local ei, ej = nodeOf(MZ.exit)
        if i == ei and j >= ej then
            F.status = "Maze: last steps to the exit"
            C.walkTo(Vector3.new(MZ.exit.X, y, MZ.exit.Z - 20), 4, 15)
            return
        end
        if (r.Position - here).Magnitude > 8 then
            F.status = "Maze: to grid point " .. k
            if not C.walkTo(here, 4, 12) then
                MZ.fails = MZ.fails + 1
                if MZ.fails >= 6 then MZ.gaveUp = true log("maze: cannot reach grid point " .. k .. " - gave up") end
            end
            return
        end
        MZ.fails = 0
        MZ.visited[k] = true
        if MZ.stack[#MZ.stack] ~= k then MZ.stack[#MZ.stack + 1] = k end
        local best, bestD, openTxt = nil, math.huge, ""
        for _, d in ipairs(DIRS) do
            local ni, nj = i + d[1], j + d[2]
            local nk = nkey(ni, nj)
            local np = nodePos(ni, nj, y)
            if not MZ.bad[k .. ">" .. nk] and clear(r.Position, np) then
                openTxt = openTxt .. " " .. nk
                if not MZ.visited[nk] then
                    local dist = math.abs(ni - ei) + math.abs(nj - ej)
                    if dist < bestD then best, bestD = { nk, np }, dist end
                end
            end
        end
        MZ.hops = MZ.hops + 1
        if best then
            F.status = "Maze: " .. k .. " -> " .. best[1]
            log("maze " .. k .. " open:" .. openTxt .. " go " .. best[1])
            if not C.walkTo(best[2], 4, 15) then
                MZ.bad[k .. ">" .. best[1]] = true
                log("maze: could not reach " .. best[1])
            end
            return
        end
        table.remove(MZ.stack)   -- dead end: one point back
        local prev = MZ.stack[#MZ.stack]
        if not prev then
            MZ.gaveUp = true
            log("maze: search ran out at " .. k .. " open:" .. openTxt)
            return
        end
        local pi, pj = prev:match("^(-?%d+),(-?%d+)$")
        F.status = "Maze: dead end at " .. k .. ", back to " .. prev
        log("maze dead end " .. k .. " back " .. prev)
        C.walkTo(nodePos(tonumber(pi), tonumber(pj), y), 4, 15)
    end

    local function step()
        local c = C.char()
        if c and c:FindFirstChild("Cuffed") and F.cfg.idCuffs then
            local p = nearestPrompt("key", 1000)
            if p then use(p, "key", "keys") return end
            -- the key is not loaded yet (the game streams in nearby things only): go where it lay in the recorded
            -- run (3026,2076,-13411); if it is not there either, say so and wait for the owner
            local r = C.root()
            if r and not ID.keySpotTried and (r.Position - ID.KEYSPOT).Magnitude < 800 then
                F.status = "Cuffed - key not loaded, walking to the recorded key spot"
                C.walkTo(ID.KEYSPOT, 6, 40, function() return nearestPrompt("key", 1000) ~= nil end)
                r = C.root()
                if r and (r.Position - ID.KEYSPOT).Magnitude < 12 then ID.keySpotTried = true end
                return
            end
            F.status = "Cuffed - key not found (prompts known: " .. ID.count() .. ")"
            return
        end
        -- low HP: stop walking into fights (loot and chests go on); no safe spot is known yet, so it does not run away
        local low = C.hpPct() < F.cfg.retreatHp
        if low then F.status = "Low HP - not fighting (Combat: Retreat below HP)" end
        if F.cfg.idFight and not low then
            local g = C.nearestMob(F.cfg.idFightRange, isGuard)
            if g then C.attack(g, F.cfg.idSkills) return end
        end
        if F.cfg.idLoot then
            local p = nearestPrompt("loot", 120)
            if p then use(p, "drop", "loot") return end
        end
        if F.cfg.idChests then
            -- in the maze only chests close by, or the walk to each one fights the walls
            local p = nearestPrompt("chest", (F.cfg.idMaze and ID.inMaze()) and 60 or 300)
            if p then use(p, "chest", "chests") return end
        end
        if F.cfg.idMaze and ID.inMaze() then mazeStep() return end
        F.status = "Nothing near - walk on by hand (stage: " .. ID.stage .. ")"
    end

    task.spawn(function()
        while F.alive do
            if F.running and F.cfg.mode == "Impel Down" then
                if not ID.inRaid() then
                    -- raid pad at Impel Base (main sea place): both recorded hand runs ended at 5876,9.6,-10213 just
                    -- before the teleport into the raid. Walk there (no teleport: the server tracks teleports).
                    local r = C.root()
                    local d = r and (r.Position - ID.PAD).Magnitude
                    if not (F.cfg.idGoPad and game.PlaceId == ID.WORLD and d and C.alive()) then
                        F.status = "Not in Impel Down - queue and pick the difficulty by hand"
                    elseif d <= 6 then
                        F.status = "On the raid pad - waiting for the raid (pick the difficulty by hand)"
                    elseif d > 1500 then
                        F.status = "Raid pad is far (" .. math.floor(d) .. ") - set spawn at Impel Base (Robo) first"
                    else
                        F.status = "Walking to the raid pad (" .. math.floor(d) .. ")"
                        if not ID.padLogged then ID.padLogged = true log("impel: walking to the raid pad, " .. math.floor(d) .. " away") end
                        -- near the recorded route: follow it (path search got stuck on a step 244 away, m_8 log)
                        local nearRoute = false
                        for _, p in ipairs(ID.PADROUTE) do
                            if (p - r.Position).Magnitude < 60 then nearRoute = true break end
                        end
                        if nearRoute then
                            pcall(C.followRoute, ID.PADROUTE, 4)
                        else
                            pcall(C.walkTo, ID.PADROUTE[1], 8, 40)
                        end
                    end
                elseif C.alive() then
                    local ok, err = pcall(step)
                    if not ok then log("impel error: " .. tostring(err)) end
                else
                    F.status = "Dead / respawning"
                end
            end
            task.wait(0.2)
        end
    end)
end
--------------------------------------------------------------------------------
-- session (s_1, 2026-11-19): counters read from what the server already sends us (listen only), plus two helpers.
--   drops  : ReplicatedStorage.Events.note("New Item <Rare=Epic><Name>")              (recorded)
--   floors : ReplicatedStorage.matchEvents("waveInfo", text, nil, "ImpelDown")        (recorded)
--   haki   : note "You have unlocked BUSO, press J to activate!" comes after each spawn -> press J (only while Start is on)
--   stop   : Home "Stop after (hours)" turns Start off. Start is never saved, so the clock restarts in every place.
-- Counters for today are kept in gpohub/session.json because the hub reloads on every teleport.
--------------------------------------------------------------------------------
do
    local S = { drops = {}, rare = {}, raids = 0, day = os.date("%Y-%m-%d"), floor = "-", bosses = 0, areas = 0, raidT = nil, since = nil, lastJob = nil, bossSeen = "-" }
    F.session = S
    local RS = game:GetService("ReplicatedStorage")
    local FILE = FOLDER .. "/session.json"
    local ORDER = { "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

    local function save()
        if not canFiles then return end
        ensureFolder()
        pcall(function()
            writefile(FILE, HttpService:JSONEncode({ day = S.day, raids = S.raids, drops = S.drops, rare = S.rare, lastJob = S.lastJob }))
        end)
    end
    pcall(function()
        if not (canFiles and isfile(FILE)) then return end
        local d = HttpService:JSONDecode(readfile(FILE))
        if type(d) ~= "table" or d.day ~= S.day then return end
        S.raids = tonumber(d.raids) or 0
        if type(d.drops) == "table" then S.drops = d.drops end
        if type(d.rare) == "table" then S.rare = d.rare end
        S.lastJob = d.lastJob
    end)
    -- one raid = one server (JobId) of the Impel Down place
    if F.impel.inRaid() then
        S.raidT = os.clock()
        if S.lastJob ~= game.JobId then
            S.raids = S.raids + 1
            S.lastJob = game.JobId
            save()
        end
    end

    function S.raidLine()
        if not S.raidT then return "not in a raid" end
        local t = math.floor(os.clock() - S.raidT)
        return string.format("%d:%02d  floor %s  bosses %d", math.floor(t / 60), t % 60, S.floor, S.bosses)
    end
    function S.rareLine()
        local out = {}
        for _, r in ipairs(ORDER) do
            if S.rare[r] then out[#out + 1] = r .. " " .. S.rare[r] end
        end
        return #out > 0 and table.concat(out, ", ") or "none yet"
    end

    local lastHaki = 0
    local function onNote(text)
        if type(text) ~= "string" then return end
        local rar, name = text:match("New Item <Rare=(%a+)><(.+)>")
        if rar and name then
            S.rare[rar] = (S.rare[rar] or 0) + 1
            if name ~= "Wooden Plank" then
                table.insert(S.drops, 1, os.date("%H:%M ") .. name .. " (" .. rar .. ")")
                while #S.drops > 30 do table.remove(S.drops) end
            end
            log("drop: " .. name .. " (" .. rar .. ")")
            save()
            return
        end
        if text:find("press J to activate", 1, true) and F.running and F.cfg.useHaki and os.clock() - lastHaki > 15 then
            lastHaki = os.clock()
            task.delay(1.5, function()
                if F.alive and F.running then
                    local ic = C.input()
                    local buso = ic and ic.Callbacks.Buso
                    if buso then
                        pcall(function() buso:PC_Activate() end)
                        log("haki: asked the game to turn Buso on")
                    else
                        C.key(Enum.KeyCode.J)
                        log("haki: pressed J")
                    end
                end
            end)
        end
    end
    task.spawn(function()
        local evs = RS:WaitForChild("Events", 30)
        local note = evs and evs:WaitForChild("note", 30)
        if note and F.alive and note:IsA("RemoteEvent") then
            F.conns[#F.conns + 1] = note.OnClientEvent:Connect(function(text) pcall(S.onNote, text) end)
        end
    end)
    task.spawn(function()
        local ev = RS:WaitForChild("matchEvents", 30)
        if not ev or not F.alive or not ev:IsA("RemoteEvent") then return end
        F.conns[#F.conns + 1] = ev.OnClientEvent:Connect(function(kind, text)
            if kind ~= "waveInfo" or type(text) ~= "string" then return end
            local plain = text:gsub("<[^>]+>", "")
            local fl = plain:match("FLOOR%s+(%d+)")
            if fl then S.floor = fl end
            if plain:find("BOSS DEFEATED", 1, true) then S.bosses = S.bosses + 1 end
            if plain:find("CLEARED", 1, true) then S.areas = S.areas + 1 end
        end)
    end)

    -- every new status line goes to the log (numbers ignored when comparing), so a run can be read afterwards
    task.spawn(function()
        local last = ""
        while F.alive do
            local s = tostring(F.status)
            local shape = s:gsub("%-?%d+%.?%d*", "#")
            if F.running and shape ~= last then
                last = shape
                local r = C.root()
                log("status: " .. s .. (r and string.format("  @ %.0f,%.0f,%.0f", r.Position.X, r.Position.Y, r.Position.Z) or ""))
            end
            task.wait(0.5)
        end
    end)

    -- one-time probe (m_7): the Watch dump covers ReplicatedStorage / ReplicatedFirst only. The scripts that take
    -- the player s input (Backpack: Movements, MeleeScript, ImpelClient ...) and the game s own windows
    -- (PlayerGui: Matchmake, ImpelDownUI ...; PlayerScripts) live under the player. Read them once per place into
    -- gpohub/src/<placeId>/ with an index. Only reads (decompile), sends nothing.
    task.delay(12, function()
        if not F.alive or type(decompile) ~= "function" or not canFiles then return end
        local dir = FOLDER .. "/src/" .. tostring(game.PlaceId)
        if isfile(dir .. "/_index.txt") then return end
        pcall(function()
            if type(makefolder) == "function" then
                if not isfolder(FOLDER .. "/src") then makefolder(FOLDER .. "/src") end
                if not isfolder(dir) then makefolder(dir) end
            end
        end)
        local list, seen = {}, {}
        for _, rootName in ipairs({ "Backpack", "PlayerScripts", "PlayerGui" }) do
            local root = LP:FindFirstChild(rootName)
            if root then
                for _, d in ipairs(root:GetDescendants()) do
                    if (d:IsA("LocalScript") or d:IsA("ModuleScript")) and not seen[d] and not d:FindFirstAncestor("MoseeriGPO") then
                        seen[d] = true
                        list[#list + 1] = d
                    end
                end
            end
        end
        local index, ok_n = { "# " .. #list .. " scripts under the player | PlaceId " .. tostring(game.PlaceId) .. " | " .. os.date("%Y-%m-%d %H:%M:%S") }, 0
        for i, sc in ipairs(list) do
            if not F.alive or i > 500 then break end
            local okd, src = pcall(decompile, sc)
            local name = string.format("%04d_%s.lua", i, sc.Name:gsub("[^%w%-]", "_"):sub(1, 40))
            if okd and type(src) == "string" and #src > 0 then
                pcall(writefile, dir .. "/" .. name, "-- " .. sc:GetFullName() .. "\n" .. src)
                ok_n = ok_n + 1
                index[#index + 1] = name .. " | " .. #src .. " bytes | " .. sc.ClassName .. " " .. sc:GetFullName()
            else
                index[#index + 1] = name .. " | FAILED | " .. sc.ClassName .. " " .. sc:GetFullName()
            end
            if i % 5 == 0 then task.wait() end
        end
        pcall(writefile, dir .. "/_index.txt", table.concat(index, "\n") .. "\n")
        log("probe: read " .. ok_n .. " of " .. #list .. " player scripts into " .. dir)
    end)

    -- quest NPC positions (m_8): the game's own quest tracker asks the server for them once at start with
    -- Events.Quest:InvokeServer({"getQuestLocations"}) and gets a table  NPC name -> CFrame  (read in the decompiled
    -- QuestTracker). Same call here, once per place, saved to gpohub/quest_locations_<placeId>.json.
    S.locations = {}
    task.delay(15, function()
        if not F.alive then return end
        local file = FOLDER .. "/quest_locations_" .. tostring(game.PlaceId) .. ".json"
        local okr = pcall(function()
            if canFiles and isfile(file) then
                local d = HttpService:JSONDecode(readfile(file))
                for name, p in pairs(d) do S.locations[name] = Vector3.new(p[1], p[2], p[3]) end
            end
        end)
        if okr and next(S.locations) then return end
        local evs = RS:FindFirstChild("Events")
        local q = evs and evs:FindFirstChild("Quest")
        if not (q and q:IsA("RemoteFunction")) then return end
        local okc, res = pcall(function() return q:InvokeServer({ "getQuestLocations" }) end)
        if not okc or type(res) ~= "table" then
            log("quest locations: no answer (" .. tostring(res):sub(1, 60) .. ")")
            return
        end
        local out, n = {}, 0
        for name, v in pairs(res) do
            local pos = (typeof(v) == "CFrame" and v.Position) or (typeof(v) == "Vector3" and v) or nil
            if pos and type(name) == "string" then
                S.locations[name] = pos
                out[name] = { math.floor(pos.X * 10) / 10, math.floor(pos.Y * 10) / 10, math.floor(pos.Z * 10) / 10 }
                n = n + 1
            end
        end
        if canFiles and n > 0 then
            ensureFolder()
            pcall(function() writefile(file, HttpService:JSONEncode(out)) end)
        end
        log("quest locations: " .. n .. " NPC positions from the game")
    end)

    -- account values: the game keeps them in ReplicatedStorage["Stats" .. name] (seen in scans and in the game's
    -- own GameUtils.GetStatsFolder). Read only.
    local function folder() return RS:FindFirstChild("Stats" .. LP.Name) end
    function S.stat(name, sub)
        local f = folder()
        local s = f and f:FindFirstChild(sub or "Stats")
        local v = s and s:FindFirstChild(name)
        return v and v.Value
    end
    local function num(v)
        local s = tostring(math.floor(tonumber(v) or 0))
        local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        return (out:gsub("^,", ""))
    end
    function S.accountLine(which)
        if not folder() then return "loading" end
        if which == 1 then return "Lv " .. tostring(S.stat("Level") or "?") .. "   Peli " .. num(S.stat("Peli")) end
        if which == 2 then return tostring(S.stat("DF") or "-") .. " / " .. tostring(S.stat("FightingStyle") or "-") .. " / " .. tostring(S.stat("Race", "Customization") or "-") end
        if which == 3 then
            return "Str " .. tostring(S.stat("Strength") or 0) .. "  Def " .. tostring(S.stat("Defense") or 0) .. "  Stam " .. tostring(S.stat("Stamina") or 0)
                .. "  Swd " .. tostring(S.stat("SwordMastery") or 0) .. "  Gun " .. tostring(S.stat("GunMastery") or 0) .. "  DF " .. tostring(S.stat("DevilFruitMastery") or 0)
        end
        return "free points " .. tostring(S.stat("SkillPoints") or 0) .. "   Impel points " .. num(S.stat("Impel Down", "DungeonPoints"))
    end

    -- auto stat points (Level page, off by default). Same call as the game's own + button:
    -- Events.stats:FireServer(<stat name>, nil, <amount>)  (read in the game's Statistics script). One point at a
    -- time into the lower of the two chosen stats; stops itself if the points do not go down.
    local SPLIT = {
        ["Sword / Defense"] = { "SwordMastery", "Defense" },
        ["Fruit / Defense"] = { "DevilFruitMastery", "Defense" },
        ["Sword / Fruit"] = { "SwordMastery", "DevilFruitMastery" },
    }
    S.statFails = 0
    task.spawn(function()
        while F.alive do
            task.wait(1.5)
            local pair = SPLIT[F.cfg.lvlStats]
            local sp = tonumber(S.stat("SkillPoints")) or 0
            if F.running and F.cfg.autoStats and pair and sp > 0 and S.statFails < 5 then
                local ev = RS:FindFirstChild("Events")
                ev = ev and ev:FindFirstChild("stats")
                local a, b = tonumber(S.stat(pair[1])) or 0, tonumber(S.stat(pair[2])) or 0
                local pick = a <= b and pair[1] or pair[2]
                if ev and ev:IsA("RemoteEvent") then
                    pcall(function() ev:FireServer(pick, nil, 1) end)
                    task.wait(1)
                    if (tonumber(S.stat("SkillPoints")) or 0) < sp then
                        S.statFails = 0
                        log("stat point -> " .. pick)
                    else
                        S.statFails = S.statFails + 1
                        if S.statFails >= 5 then log("stat points: not going down (cap or refused) - auto stat stopped") end
                    end
                end
            end
        end
    end)

    -- Discord alert (Settings): Epic and better drops go to the owner's own webhook. The URL is typed into the hub
    -- and lives only in gpohub/config.json; it is never logged.
    local ALERT = { Epic = true, Legendary = true, Mythical = true }
    function S.alert(text)
        local url = tostring(F.cfg.webhook or "")
        if not F.cfg.discordAlert or not url:match("^https://discord") then return end
        local req = request or http_request
        if type(req) ~= "function" then return end
        task.spawn(function()
            pcall(req, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({ content = "[gpo] " .. LP.Name .. ": " .. text }) })
        end)
    end
    S.onNote = function(text)
        onNote(text)
        if type(text) ~= "string" then return end
        local rar, name = text:match("New Item <Rare=(%a+)><(.+)>")
        if rar and ALERT[rar] then S.alert(name .. " (" .. rar .. ")") end
    end

    -- Start survives a teleport (Home: Keep Start on): gpohub/run.json holds when Start was pressed; the hub is
    -- queued again with queue_on_teleport, and the "Stop after" clock keeps counting from the first press.
    local RUN = FOLDER .. "/run.json"
    local function saveRun()
        if not canFiles then return end
        ensureFolder()
        pcall(function() writefile(RUN, HttpService:JSONEncode({ running = F.running, since = S.since })) end)
    end
    pcall(function()
        if F.cfg.reloadHub and type(queue_on_teleport) == "function" then
            queue_on_teleport('loadstring(game:HttpGet("https://raw.githubusercontent.com/moseeri01/gpohub/main/gpo_hub.lua?t=" .. tostring(os.time())))()')
        end
    end)
    pcall(function()
        if not (F.cfg.keepStart and canFiles and isfile(RUN)) then return end
        local d = HttpService:JSONDecode(readfile(RUN))
        if type(d) ~= "table" or d.running ~= true or type(d.since) ~= "number" then return end
        if os.time() - d.since >= F.cfg.stopHours * 3600 then return end
        task.delay(8, function()
            if not F.alive or F.running then return end
            S.since = d.since
            F.running = true
            F.status = "Resumed after teleport"
            log("resume: Start kept on (" .. F.cfg.mode .. ")")
        end)
    end)
    task.spawn(function()
        task.wait(10)   -- after the resume check above
        while F.alive do
            if F.running then
                if not S.since then S.since = os.time() saveRun() end
                if os.time() - S.since > F.cfg.stopHours * 3600 then
                    F.running = false
                    S.since = nil
                    saveRun()
                    F.status = "Stopped: ran " .. F.cfg.stopHours .. " h (Home: Stop after)"
                    log("stop: time limit")
                end
            elseif S.since then
                S.since = nil
                saveRun()
            end
            task.wait(2)
        end
    end)
end


--------------------------------------------------------------------------------
-- open-world parts that need no recorded remote calls (2026-11-19):
--   mob farm     : fight mobs in Workspace.NPCs by name, walking only; HP retreat; pause near players
--   daily quests : read ReplicatedStorage.Remotes.DailyQuestsChanged (server -> us, listen only)
--   fruit alert  : read ReplicatedStorage.Events.fruitspawn / fruitSpawnTime (listen only, raw text first)
-- Taking / handing in quests, fishing, selling, daily reward claims and stat points need one recorded
-- hand run each (watch.lua with "My calls (hook)" on) before they can be written.
--------------------------------------------------------------------------------
do
    local W = { kills = 0, daily = nil, dailyAt = nil, fruits = {}, home = nil }
    F.world = W
    local RS = game:GetService("ReplicatedStorage")

    local function short(v, n)
        local s
        if type(v) == "table" then
            local ok, j = pcall(function() return HttpService:JSONEncode(v) end)
            s = ok and j or "{table}"
        else s = tostring(v) end
        n = n or 120
        return #s > n and (s:sub(1, n) .. "...") or s
    end

    -- listen to a RemoteEvent by path once it exists
    local function listen(parent, name, fn)
        task.spawn(function()
            local ev = parent and parent:WaitForChild(name, 30)
            if ev and F.alive and ev:IsA("RemoteEvent") then
                F.conns[#F.conns + 1] = ev.OnClientEvent:Connect(function(...) pcall(fn, ...) end)
            end
        end)
    end

    -- daily quests
    task.spawn(function()
        local remotes = RS:WaitForChild("Remotes", 30)
        listen(remotes, "DailyQuestsChanged", function(data)
            if type(data) ~= "table" then return end
            W.daily = data
            W.dailyAt = os.date("%H:%M")
        end)
    end)
    -- text lines for the Level page; field names inside each quest were never seen, so try the usual ones
    function W.dailyLines()
        local d = W.daily
        if not d then return { "waiting for the game to send them (changes when a quest moves)" } end
        local cur = type(d.Current) == "table" and d.Current or {}
        local out = {}
        local qs = type(cur.Quests) == "table" and cur.Quests or {}
        for i, q in ipairs(qs) do
            if type(q) == "table" then
                local name = q.Name or q.Title or q.Description or q.Id or q.Type
                local have = q.Progress or q.Current or q.Count
                local need = q.Goal or q.Required or q.Target or q.Amount
                if name then
                    out[#out + 1] = i .. ". " .. tostring(name) .. ((have and need) and ("  " .. tostring(have) .. "/" .. tostring(need)) or "")
                else
                    out[#out + 1] = i .. ". " .. short(q, 90)
                end
            end
        end
        out[#out + 1] = "done " .. tostring(cur.Completed) .. " | claimed " .. tostring(cur.Claimed) .. " | at " .. tostring(W.dailyAt)
        return out
    end

    -- fruit alert
    local function onFruit(tag)
        return function(...)
            local line = os.date("%H:%M ") .. tag .. " " .. short({ ... }, 140)
            table.insert(W.fruits, 1, line)
            if #W.fruits > 5 then table.remove(W.fruits) end
            log("fruit: " .. line)
            if F.cfg.fruitAlert then notify("Fruit news: " .. short({ ... }, 80)) end
        end
    end
    task.spawn(function()
        local ev = RS:WaitForChild("Events", 30)
        listen(ev, "fruitspawn", onFruit("spawn"))
    end)
    listen(RS, "fruitSpawnTime", onFruit("timer"))

    -- mob farm
    local function wanted()
        local list = {}
        for name in tostring(F.cfg.mobNames or ""):gmatch("[^,]+") do
            local n = name:match("^%s*(.-)%s*$")
            if n ~= "" then list[n:lower()] = true end
        end
        return list
    end
    local function step()
        local h = C.hum()
        if not h then return end
        if F.cfg.stopNearPlayer then
            local p = C.playerNear(60)
            if p then F.status = "Paused - player " .. p.Name .. " is near" return end
        end
        local r = C.root()
        if not W.home and r then W.home = r.Position end
        -- low HP: walk back to where the farm started and wait to heal
        if C.hpPct() < F.cfg.retreatHp then
            F.status = "Low HP - backing off to heal"
            if W.home then C.walkTo(W.home, 6, 15) end
            while F.alive and F.running and C.alive() and C.hpPct() < 80 do task.wait(1) end
            return
        end
        local names = wanted()
        local any = next(names) == nil
        local m = C.nearestMob(F.cfg.mobRange, function(mob) return any or names[mob.Name:lower()] == true end)
        if not m then
            F.status = any and "No mob in range" or ("No " .. F.cfg.mobNames .. " in range")
            if W.home and r and (r.Position - W.home).Magnitude > 20 then C.walkTo(W.home, 6, 15) end
            return
        end
        local mh = m:FindFirstChildOfClass("Humanoid")
        local t0 = os.clock()
        while F.alive and F.running and C.alive() and mh and mh.Health > 0 and m.Parent and os.clock() - t0 < 45 do
            if C.hpPct() < F.cfg.retreatHp then return end
            C.attack(m, F.cfg.mobSkills)
        end
        if mh and mh.Health <= 0 then W.kills = W.kills + 1 log("killed " .. m.Name) end
    end

    task.spawn(function()
        while F.alive do
            if F.running and F.cfg.mode == "Mobs" then
                if C.alive() then
                    local ok, err = pcall(step)
                    if not ok then log("mobs error: " .. tostring(err)) end
                else
                    F.status = "Dead / respawning"
                    W.home = nil
                end
            elseif not F.running then
                W.home = nil
            end
            task.wait(0.2)
        end
    end)
end
--------------------------------------------------------------------------------
-- world bosses (b_1, 2026-11-19): only what needs no recorded call.
--   alert : a ticked boss shows up in Workspace.NPCs (the game streams in nearby NPCs only, so this fires when
--           the boss is loaded near you, not server-wide)
--   fight : Home Mode "Boss" walks to a ticked boss within Boss "Look within" and fights it with the shared core
-- Pill labels are matched as lower-case text inside the NPC name ("Ghost Prin." -> "ghost prin"); the real NPC
-- names were never recorded, so a label that never matches needs its name from a scan.
-- Timers, spawn spots, summon chains, sea bosses and server hop are NOT here (no data).
--------------------------------------------------------------------------------
do
    local B = { seen = {} }
    F.boss = B
    local function ticked(name)
        local low = name:lower()
        for label, on in pairs(F.cfg.bossList) do
            if on then
                local key = tostring(label):lower():gsub("%.", "")
                if low:find(key, 1, true) then return true end
            end
        end
        return false
    end
    local function check(m)
        if not F.cfg.bossAlert or B.seen[m] or not m:IsA("Model") or not ticked(m.Name) then return end
        B.seen[m] = true
        F.session.bossSeen = os.date("%H:%M ") .. m.Name
        notify("Boss here: " .. m.Name)
        F.session.alert("boss here: " .. m.Name)
    end
    task.spawn(function()
        local npcs = workspace:WaitForChild("NPCs", 30)
        if not npcs or not F.alive then return end
        for _, m in ipairs(npcs:GetChildren()) do pcall(check, m) end
        F.conns[#F.conns + 1] = npcs.ChildAdded:Connect(function(m) task.wait(0.5) pcall(check, m) end)
        F.conns[#F.conns + 1] = npcs.ChildRemoved:Connect(function(m) B.seen[m] = nil end)
    end)

    local function step()
        if F.cfg.stopNearPlayer then
            local p = C.playerNear(60)
            if p then F.status = "Paused - player " .. p.Name .. " is near" return end
        end
        if C.hpPct() < F.cfg.retreatHp then
            F.status = "Low HP - not fighting (Combat: Retreat below HP)"
            return
        end
        local m = C.nearestMob(F.cfg.bossRange, function(mob) return ticked(mob.Name) end)
        if not m then F.status = "No ticked boss within " .. F.cfg.bossRange return end
        C.attack(m, F.cfg.bossSkills)
    end
    task.spawn(function()
        while F.alive do
            if F.running and F.cfg.mode == "Boss" then
                if C.alive() then
                    local ok, err = pcall(step)
                    if not ok then log("boss error: " .. tostring(err)) end
                else
                    F.status = "Dead / respawning"
                end
            end
            task.wait(0.2)
        end
    end)
end

--------------------------------------------------------------------------------
-- remote (r_1, 2026-11-19): lets the owner's assistant test without the owner clicking. Local files only:
--   gpohub/cmd.txt   : one command per line, read every 2 s and then emptied
--       start | stop | reload | mode <Mode name> | set <cfgKey> <value> | goto <x> <y> <z> | cancel
--   gpohub/state.json: written every 2 s - version, status, position, hp, nearby mobs, hit method
-- Nothing here talks to the game; goto uses the same walking as everything else.
--------------------------------------------------------------------------------
do
    local R = { goal = nil, focused = "unknown" }
    F.remote = R
    pcall(function()
        local UIS2 = game:GetService("UserInputService")
        F.conns[#F.conns + 1] = UIS2.WindowFocused:Connect(function() R.focused = "yes" end)
        F.conns[#F.conns + 1] = UIS2.WindowFocusReleased:Connect(function() R.focused = "no" end)
    end)
    local CMD, STATE = FOLDER .. "/cmd.txt", FOLDER .. "/state.json"
    local LOADER = "https://raw.githubusercontent.com/moseeri01/gpohub/main/gpo_hub.lua"

    local function setCfg(key, value)
        local cur = F.cfg[key]
        if cur == nil then log("remote: no setting " .. tostring(key)) return end
        if type(cur) == "boolean" then F.cfg[key] = (value == "true" or value == "on" or value == "1")
        elseif type(cur) == "number" then F.cfg[key] = tonumber(value) or cur
        elseif type(cur) == "string" then F.cfg[key] = value
        else log("remote: cannot set " .. key) return end
        saveAll()
        log("remote: " .. key .. " = " .. tostring(F.cfg[key]))
    end
    local function run(line)
        local cmd, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
        if not cmd then return end
        cmd = cmd:lower()
        if cmd == "start" then
            F.running = true
            F.status = "Starting"
            log("remote: start " .. F.cfg.mode)
        elseif cmd == "stop" then
            F.running = false
            R.goal = nil
            if F.cfg.mode == "Goto" then F.cfg.mode = R.prevMode or "Impel Down" end
            F.status = "Idle"
            log("remote: stop")
        elseif cmd == "cancel" then
            R.goal = nil
        elseif cmd == "reset" then
            -- owner allowed it (20:45): when the character is wedged, reset it the way the Roblox menu does
            -- (health to 0 on our own Humanoid) and let the game respawn it at the spawn point
            F.running = false
            R.goal = nil
            local h = C.hum()
            log("remote: reset character" .. (h and "" or " (no humanoid)"))
            if h then pcall(function() h.Health = 0 end) end
        elseif cmd == "mode" and rest ~= "" then
            F.cfg.mode = rest
            saveAll()
            log("remote: mode " .. rest)
        elseif cmd == "set" then
            local k, v = rest:match("^(%S+)%s+(.+)$")
            if k then setCfg(k, v) end
        elseif cmd == "goto" then
            local x, y, z = rest:match("^(-?[%d%.]+)[%s,]+(-?[%d%.]+)[%s,]+(-?[%d%.]+)$")
            if x then
                R.goal = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                if F.cfg.mode ~= "Goto" then R.prevMode = F.cfg.mode end
                F.cfg.mode = "Goto"
                F.running = true
                log("remote: goto " .. rest)
            end
        elseif cmd == "reload" then
            -- "reload <commit>" loads that exact commit of the public repo: the plain main URL is cached by GitHub
            -- for about 5 minutes (a ?t= suffix does not skip it - seen 20:26, m_15 came back after m_16 was pushed)
            local url = LOADER .. "?t=" .. tostring(os.time())
            if rest:match("^[0-9a-f]+$") and #rest >= 7 and #rest <= 40 then
                url = "https://raw.githubusercontent.com/moseeri01/gpohub/" .. rest .. "/gpo_hub.lua"
            end
            log("remote: reload " .. rest)
            local ok, src = pcall(function() return game:HttpGet(url) end)
            local fn = ok and type(src) == "string" and #src > 1000 and loadstring(src) or nil
            if fn then task.spawn(fn) else log("remote: reload failed") end
        else
            log("remote: unknown command " .. line:sub(1, 60))
        end
    end

    local function state()
        local r, h = C.root(), C.hum()
        local mobs = {}
        local npcs = workspace:FindFirstChild("NPCs")
        if npcs and r then
            for _, m in ipairs(npcs:GetChildren()) do
                local hr, mh = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
                if hr and mh then
                    local d = (hr.Position - r.Position).Magnitude
                    if d < 600 then
                        mobs[#mobs + 1] = { n = m.Name, d = math.floor(d), hp = math.floor(mh.Health), max = math.floor(mh.MaxHealth),
                            mob = C.isMob(m), p = { math.floor(hr.Position.X), math.floor(hr.Position.Y), math.floor(hr.Position.Z) } }
                    end
                end
            end
            table.sort(mobs, function(a, b) return a.d < b.d end)
            while #mobs > 25 do table.remove(mobs) end
        end
        local c = LP.Character
        local a = C.atk
        -- fixed movement diagnostics (m_16): why a walk does not move
        local diag = {}
        pcall(function()
            local UIS2, GS = game:GetService("UserInputService"), game:GetService("GuiService")
            diag.state = h and tostring(h:GetState()):gsub("Enum.HumanoidStateType.", "") or nil
            diag.sit, diag.platform, diag.jumpPower = h and h.Sit, h and h.PlatformStand, h and h.JumpPower
            diag.anchored = r and r.Anchored
            diag.moveDir = h and string.format("%.2f,%.2f,%.2f", h.MoveDirection.X, h.MoveDirection.Y, h.MoveDirection.Z)
            diag.vel = r and string.format("%.1f,%.1f,%.1f", r.AssemblyLinearVelocity.X, r.AssemblyLinearVelocity.Y, r.AssemblyLinearVelocity.Z)
            diag.walkTo = h and string.format("%.0f,%.0f,%.0f", h.WalkToPoint.X, h.WalkToPoint.Y, h.WalkToPoint.Z)
            diag.menuOpen = GS.MenuIsOpen
            diag.textBox = UIS2:GetFocusedTextBox() ~= nil
            diag.focused = R.focused
            local marks = {}
            if c then
                for _, n in ipairs({ "Stun", "Cuffed", "Blocking", "ragcarry", "Block", "Grabbed", "Carried" }) do
                    if c:FindFirstChild(n) then marks[#marks + 1] = n end
                end
                local at = {}
                for k, v in pairs(c:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v):sub(1, 20) end
                diag.attrs = table.concat(at, " ")
            end
            diag.marks = table.concat(marks, " ")
            -- what is around the character: 8 rays at waist height (studs to the first solid part + its name),
            -- one at head height forward of each, and the part under the feet
            if r then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                local ign = { c }
                for _, n in ipairs({ "Effects", "PlayerCharacters", "Projectiles" }) do
                    local f = workspace:FindFirstChild(n)
                    if f then ign[#ign + 1] = f end
                end
                rp.FilterDescendantsInstances = ign
                local names = { "+X", "+X-Z", "-Z", "-X-Z", "-X", "-X+Z", "+Z", "+X+Z" }
                local dirs = { Vector3.new(1, 0, 0), Vector3.new(1, 0, -1), Vector3.new(0, 0, -1), Vector3.new(-1, 0, -1),
                    Vector3.new(-1, 0, 0), Vector3.new(-1, 0, 1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 1) }
                local out = {}
                for i, d in ipairs(dirs) do
                    local function cast(from)
                        local hit = workspace:Raycast(from, d.Unit * 25, rp)
                        if not hit then return "open" end
                        return string.format("%.0f %s%s", (hit.Position - from).Magnitude, hit.Instance.Name:sub(1, 14), hit.Instance.CanCollide and "" or "(nc)")
                    end
                    out[#out + 1] = names[i] .. ": " .. cast(r.Position) .. " / hi " .. cast(r.Position + Vector3.new(0, 4, 0)) .. " / lo " .. cast(r.Position - Vector3.new(0, 2, 0))
                end
                local dn = workspace:Raycast(r.Position, Vector3.new(0, -12, 0), rp)
                out[#out + 1] = "down: " .. (dn and string.format("%.1f %s [%s]", (dn.Position - r.Position).Magnitude, dn.Instance:GetFullName():sub(-60), dn.Instance.ClassName) or "nothing")
                local up = workspace:Raycast(r.Position, Vector3.new(0, 20, 0), rp)
                out[#out + 1] = "up: " .. (up and string.format("%.1f %s", (up.Position - r.Position).Magnitude, up.Instance.Name) or "open")
                diag.rays = out
            end
            diag.moveWay = C.moveWay
        end)
        return {
            diag = diag,
            t = os.date("%H:%M:%S"), version = VERSION, place = game.PlaceId, running = F.running, mode = F.cfg.mode, status = F.status,
            last = F.lastAction, pos = r and { math.floor(r.Position.X), math.floor(r.Position.Y), math.floor(r.Position.Z) } or nil,
            hp = h and math.floor(h.Health) or nil, maxhp = h and math.floor(h.MaxHealth) or nil, speed = h and h.WalkSpeed or nil,
            floor = h and tostring(h.FloorMaterial) or nil, sprint = c and c:GetAttribute("MovementSprintActive") or false,
            combat = c and c:FindFirstChild("inCombat") ~= nil or false, tool = c and c:FindFirstChildOfClass("Tool") and c:FindFirstChildOfClass("Tool").Name or nil,
            atk = a and { method = a.names[a.method], proven = a.proven, swings = a.swings, reach = a.reach, can = tostring(a.can) } or nil,
            goal = R.goal and { R.goal.X, R.goal.Y, R.goal.Z } or nil, mobs = mobs,
        }
    end

    task.spawn(function()
        while F.alive do
            if canFiles then
                pcall(function()
                    if isfile(CMD) then
                        local text = readfile(CMD)
                        if text and text:match("%S") then
                            writefile(CMD, "")
                            for line in text:gmatch("[^\r\n]+") do run(line) end
                        end
                    end
                end)
                pcall(function() writefile(STATE, HttpService:JSONEncode(state())) end)
            end
            task.wait(2)
        end
    end)

    -- goto: walk to the point in hops; ends when it is there
    task.spawn(function()
        while F.alive do
            if F.running and F.cfg.mode == "Goto" and R.goal and C.alive() then
                local r = C.root()
                local d = r and (r.Position - R.goal).Magnitude or 0
                if d <= 8 then
                    log(string.format("remote: goto reached (%.0f away)", d))
                    R.goal = nil
                    F.running = false
                    F.cfg.mode = R.prevMode or "Impel Down"
                    F.status = "Goto done"
                else
                    F.status = "Goto (" .. math.floor(d) .. " left)"
                    C.walkTo(R.goal, 6, 30)
                end
            end
            task.wait(0.3)
        end
    end)
end


--------------------------------------------------------------------------------
-- pages (settings only - the farm logic is added per mode later)
--------------------------------------------------------------------------------
-- a row for something not built yet
function UI.soon(card, text)
    UI.info(card, text, function() return "soon" end)
end
-- risk word after the label, so it is readable without colours
local function risk(text, level) return text .. "  [" .. level .. " risk]" end
local function setIn(tbl) return function(name) F.cfg[tbl][name] = not F.cfg[tbl][name] or nil saveAll() end end
local function isIn(tbl) return function(name) return F.cfg[tbl][name] == true end end

-- Home
local home = UI.page("Home", 1)
local run = UI.card(home, 1, "Run")
UI.toggle(run, "Start / Stop", function() return F.running end, function(v)
    F.running = v
    local ready = F.cfg.mode == "Impel Down" or F.cfg.mode == "Mobs" or F.cfg.mode == "Boss"
    F.status = v and (ready and "Starting" or ("No farm logic yet (" .. F.cfg.mode .. ")")) or "Idle"
    log(v and ("start " .. F.cfg.mode) or "stop")
end)
UI.choice(run, "Mode", { "Impel Down", "Mobs", "Boss", "Raids", "Fishing", "Level" }, cfgGet("mode"), cfgSet("mode"))
UI.stepper(run, "Stop after (hours)", 1, 12, cfgGet("stopHours"), cfgSet("stopHours"))
UI.toggle(run, "Stop if kicked / warned", cfgGet("stopOnKick"), cfgSet("stopOnKick"))
UI.toggle(run, "Keep Start on after a teleport", cfgGet("keepStart"), cfgSet("keepStart"))
UI.toggle(run, "Reload hub after a teleport", cfgGet("reloadHub"), cfgSet("reloadHub"))
-- Reload = stop this hub and run the newest one from GitHub (no rejoin needed). The ?t= part skips GitHub's
-- 5-minute cache. Close = stop and remove the window; the loader brings it back.
local LOADER = "https://raw.githubusercontent.com/moseeri01/gpohub/main/gpo_hub.lua"
local function reloadHub()
    log("reload asked from the window")
    local ok, src = pcall(function() return game:HttpGet(LOADER .. "?t=" .. tostring(os.time())) end)
    if not ok or type(src) ~= "string" or #src < 1000 then notify("Reload failed: could not download") return end
    local fn = loadstring(src)
    if not fn then notify("Reload failed: the download does not run") return end
    task.spawn(fn)   -- the new hub stops this one first (G.__gpo_hub_stop)
end
UI.button(run, "Reload hub (newest version)", "Reload", reloadHub)
UI.button(run, "Close hub", "Close", function() if G.__gpo_hub_stop then G.__gpo_hub_stop() end end)
local st = UI.card(home, 2, "Status")
UI.info(st, "Now", function() return F.status end)
UI.info(st, "Mode", function() return F.cfg.mode end)
UI.info(st, "Last action", function() return F.lastAction ~= "" and F.lastAction or "-" end)
UI.info(st, "Version", function() return VERSION end)
local acc = UI.card(home, 1, "Account")
UI.info(acc, "Player", function() return LP and LP.Name or "-" end)
UI.info(acc, "Level / Peli", function() return F.session.accountLine(1) end)
UI.info(acc, "Fruit / style / race", function() return F.session.accountLine(2) end)
UI.info(acc, "Stats", function() return F.session.accountLine(3) end)
UI.info(acc, "Points", function() return F.session.accountLine(4) end)
local dr = UI.card(home, 2, "Session")
UI.info(dr, "Raids today", function() return tostring(F.session.raids) end)
UI.info(dr, "This raid", function() return F.session.raidLine() end)
UI.info(dr, "Drops today", function() return F.session.rareLine() end)
for i = 1, 3 do
    UI.info(dr, i == 1 and "Last drops" or "", function() return F.session.drops[i] or "-" end)
end

-- Combat (shared by every mode)
local combat = UI.page("Combat", 2)
local atk = UI.card(combat, 1, "Attack")
UI.note(atk, "Use skills from")
UI.pills(atk, { "Sword", "Fruit", "Gun", "Style" },
    function(o) return F.cfg["use" .. o] == true end,
    function(o) F.cfg["use" .. o] = not F.cfg["use" .. o] saveAll() end)
UI.toggle(atk, "Normal hits between skills", cfgGet("normalHits"), cfgSet("normalHits"))
UI.toggle(atk, "Group mobs before big skills", cfgGet("groupMobs"), cfgSet("groupMobs"))
UI.toggle(atk, "Stun lock combo", cfgGet("stunLock"), cfgSet("stunLock"))
UI.toggle(atk, "Use Haki", cfgGet("useHaki"), cfgSet("useHaki"))
local def = UI.card(combat, 2, "Defense")
UI.toggle(def, "Auto dodge", cfgGet("autoDodge"), cfgSet("autoDodge"))
UI.toggle(def, "Auto block", cfgGet("autoBlock"), cfgSet("autoBlock"))
UI.toggle(def, "Stay behind target", cfgGet("stayBehind"), cfgSet("stayBehind"))
UI.toggle(def, "Use safe spot if known", cfgGet("safeSpot"), cfgSet("safeSpot"))
UI.stepper(def, "Retreat below HP %", 0, 90, cfgGet("retreatHp"), cfgSet("retreatHp"), 10)
local rk = UI.card(combat, 2, "Risky - off by default")
UI.toggle(rk, risk("Hover above target", "high"), cfgGet("hover"), cfgSet("hover"))
UI.toggle(rk, risk("Freeze mobs", "high"), cfgGet("freezeMobs"), cfgSet("freezeMobs"))
UI.note(rk, "Only if the game allows it. Test on the new account first.")

-- Impel Down
local impel = UI.page("Impel Down", 3)
local idnow = UI.card(impel, 1, "Inside the raid (works now)")
UI.toggle(idnow, "Free myself from the cuffs", cfgGet("idCuffs"), cfgSet("idCuffs"))
UI.toggle(idnow, "Open chests", cfgGet("idChests"), cfgSet("idChests"))
UI.toggle(idnow, "Grab drops", cfgGet("idLoot"), cfgSet("idLoot"))
UI.toggle(idnow, "Skip Wooden Plank", cfgGet("idSkipJunk"), cfgSet("idSkipJunk"))
UI.toggle(idnow, "Fight Impel Guards", cfgGet("idFight"), cfgSet("idFight"))
UI.stepper(idnow, "Fight guards within", 10, 120, cfgGet("idFightRange"), cfgSet("idFightRange"), 10)
UI.toggle(idnow, "Use skills Z / X / C", cfgGet("idSkills"), cfgSet("idSkills"))
UI.toggle(idnow, "Fight every enemy (bosses too)", cfgGet("idBosses"), cfgSet("idBosses"))
UI.toggle(idnow, "Walk the maze (floor 1)", cfgGet("idMaze"), cfgSet("idMaze"))
UI.note(idnow, "Home: Mode Impel Down + Start. Walks only. Queue, maze route and the end are still by hand.")
local idst = UI.card(impel, 2, "This run")
UI.info(idst, "Stage", function() return F.impel and F.impel.stage or "-" end)
UI.info(idst, "Chests / drops", function() return F.impel and (F.impel.done.chests .. " / " .. F.impel.done.loot) or "-" end)
UI.info(idst, "Maze", function()
    local m = F.impel and F.impel.maze
    if not m then return "-" end
    return m.gaveUp and "gave up - walk by hand" or (m.hops .. " grid points")
end)
UI.info(idst, "Hit method", function()
    local a = F.core and F.core.atk
    return a and (a.names[a.method] .. (a.proven and " (works)" or " (not proven)")) or "-"
end)
UI.info(idst, "Press method", function() return type(fireproximityprompt) == "function" and "fireproximityprompt" or "hold E" end)
local raid = UI.card(impel, 1, "Raid")
UI.toggle(raid, "Walk to the raid pad (works now)", cfgGet("idGoPad"), cfgSet("idGoPad"))
UI.choice(raid, "Difficulty", { "Normal", "Hard", "Nightmare", "Nightmare+" }, cfgGet("idDiff"), cfgSet("idDiff"))
UI.toggle(raid, "Solo only", cfgGet("idSolo"), cfgSet("idSolo"))
UI.toggle(raid, "Open Secret Room (floor 2)", cfgGet("idSecret"), cfgSet("idSecret"))
UI.toggle(raid, "Queue again after clear", cfgGet("idRequeue"), cfgSet("idRequeue"))
local shop = UI.card(impel, 2, "Impel Shop")
UI.soon(shop, "Points")
UI.choice(shop, "Auto buy", { "Nothing", "Mythical Fruit Chest", "Legendary Fruit Chest", "Race Reroll" }, cfgGet("idBuy"), cfgSet("idBuy"))
UI.stepper(shop, "Keep points until", 0, 500000, cfgGet("idKeep"), cfgSet("idKeep"), 10000)
local fl = UI.card(impel, 2, "Floors")
UI.note(fl, "1 maze - 2 Sphinx - 3 Jailer Han - 4 Blugori - 5 Vera")

-- Boss
local boss = UI.page("Boss", 4)
local wb = UI.card(boss, 1, "World bosses (respawn)")
UI.pills(wb, { "Juzo", "Ryuma", "Borj", "Ghost Prin.", "Crab King", "Zeke", "Gravito" }, isIn("bossList"), setIn("bossList"))
UI.toggle(wb, "Alert when a ticked boss is near", cfgGet("bossAlert"), cfgSet("bossAlert"))
UI.stepper(wb, "Look within", 50, 600, cfgGet("bossRange"), cfgSet("bossRange"), 50)
UI.toggle(wb, "Use skills Z / X / C", cfgGet("bossSkills"), cfgSet("bossSkills"))
UI.info(wb, "Last seen", function() return F.session.bossSeen end)
UI.note(wb, "Home: Mode Boss + Start walks to a ticked boss and fights. Sees only bosses loaded near you.")
UI.toggle(wb, risk("Server hop to find boss", "mid"), cfgGet("bossHop"), cfgSet("bossHop"))
local sc = UI.card(boss, 1, "Summon chains")
UI.soon(sc, "Moria / Donmingo / Zhen / Musashi")
local tw = UI.card(boss, 2, "Timed world bosses")
UI.toggle(tw, "Radiant Admiral (30 min)", cfgGet("bossRadiant"), cfgSet("bossRadiant"))
UI.toggle(tw, "Roger (90 min)", cfgGet("bossRoger"), cfgSet("bossRoger"))
UI.toggle(tw, "Hawk Eye (120 min)", cfgGet("bossHawk"), cfgSet("bossHawk"))
local sea = UI.card(boss, 2, "Sea")
UI.toggle(sea, "Sea Serpent / Kraken", cfgGet("seaSerpent"), cfgSet("seaSerpent"))
UI.toggle(sea, "Megalodon", cfgGet("seaMegalodon"), cfgSet("seaMegalodon"))
UI.toggle(sea, "Soul King (hourly)", cfgGet("seaSoulKing"), cfgSet("seaSoulKing"))

-- Raids
local raids = UI.page("Raids", 5)
local orr = UI.card(raids, 1, "Other raids")
UI.soon(orr, "Colosseum")
UI.soon(orr, "Factory Raid")
UI.soon(orr, "Whole Cake Tower")
UI.soon(orr, "Dragon Emperor Dungeon")
local ev = UI.card(raids, 2, "Event - Halloween (to Dec 19)")
UI.toggle(ev, risk("Spooksville haunts", "high"), cfgGet("evSpooks"), cfgSet("evSpooks"))
UI.toggle(ev, risk("Ba'al chain", "high"), cfgGet("evBaal"), cfgSet("evBaal"))
UI.note(ev, "Event drops are trade-locked 6 h for dev review.")

-- Fishing
local fishing = UI.page("Fishing", 6)
local fi = UI.card(fishing, 1, "Fishing")
UI.choice(fi, "Spot", { "Rough Waters", "Shells Town", "Logue Town", "Desert Kingdom", "Where I stand" }, cfgGet("fishSpot"), cfgSet("fishSpot"))
UI.toggle(fi, "Auto buy bait", cfgGet("fishBait"), cfgSet("fishBait"))
UI.toggle(fi, "Auto sell fish", cfgGet("fishSell"), cfgSet("fishSell"))
UI.toggle(fi, "Keep Legendary", cfgGet("fishKeepLeg"), cfgSet("fishKeepLeg"))
local fs = UI.card(fishing, 2, "Session")
UI.soon(fs, "Fish caught / Peli earned")
UI.toggle(fs, "Fight Megalodon if it spawns", cfgGet("fishMegalodon"), cfgSet("fishMegalodon"))

-- Level
local level = UI.page("Level", 7)
local mf = UI.card(level, 1, "Mob farm (works now)")
UI.toggle(mf, "Walk to mobs and fight", function() return F.running and F.cfg.mode == "Mobs" end, function(v)
    if v then F.cfg.mode = "Mobs" saveAll() end
    F.running = v
    F.status = v and "Starting" or "Idle"
    log(v and "start Mobs" or "stop")
end)
UI.input(mf, "Mob names", "blank = any mob, or: Bandit, Marine", cfgGet("mobNames"), cfgSet("mobNames"))
UI.stepper(mf, "Look within", 20, 300, cfgGet("mobRange"), cfgSet("mobRange"), 20)
UI.toggle(mf, "Use skills Z / X / C", cfgGet("mobSkills"), cfgSet("mobSkills"))
UI.info(mf, "Kills", function() return F.world and tostring(F.world.kills) or "0" end)
UI.note(mf, "Stand near the mobs first. Walks only, no quests yet. Same as Home: Mode Mobs + Start.")
local dq = UI.card(level, 2, "Daily quests (read only)")
for i = 1, 4 do
    UI.info(dq, i == 4 and "Status" or ("Quest " .. i), function()
        local lines = F.world and F.world.dailyLines() or {}
        if i == 4 then return lines[#lines] or "-" end
        if #lines == 1 then return i == 1 and lines[1] or "-" end
        return (i <= #lines - 1 and lines[i]) or "-"
    end)
end
local lf = UI.card(level, 1, "Level farm")
UI.stepper(lf, "Target level", 25, 675, cfgGet("lvlTarget"), cfgSet("lvlTarget"), 25)
UI.toggle(lf, "Auto quest", cfgGet("lvlQuest"), cfgSet("lvlQuest"))
UI.toggle(lf, "Move island by level", cfgGet("lvlMove"), cfgSet("lvlMove"))
UI.toggle(lf, risk("Spend skill points (works now)", "low"), cfgGet("autoStats"), cfgSet("autoStats"))
UI.choice(lf, "Split points", { "Sword / Defense", "Fruit / Defense", "Sword / Fruit" }, cfgGet("lvlStats"), cfgSet("lvlStats"))
local un = UI.card(level, 2, "Unlocks")
UI.toggle(un, "Train Armament Haki", cfgGet("lvlHaki"), cfgSet("lvlHaki"))
UI.toggle(un, "Perfect block x200", cfgGet("lvlBlock"), cfgSet("lvlBlock"))

-- Settings
local settings = UI.page("Settings", 8)
local sf = UI.card(settings, 1, "Safety")
UI.toggle(sf, "Move at normal speed only", cfgGet("normalSpeed"), cfgSet("normalSpeed"))
UI.toggle(sf, "Sprint on long walks (game's own run)", cfgGet("sprint"), cfgSet("sprint"))
UI.toggle(sf, "Geppo over obstacles when stuck", cfgGet("geppo"), cfgSet("geppo"))
UI.toggle(sf, "Stop when a player is near", cfgGet("stopNearPlayer"), cfgSet("stopNearPlayer"))
UI.toggle(sf, "Anti AFK", cfgGet("antiAfk"), cfgSet("antiAfk"))
UI.toggle(sf, "Auto rejoin", cfgGet("autoRejoin"), cfgSet("autoRejoin"))
local ex = UI.card(settings, 2, "Extras")
UI.toggle(ex, "Discord alert: Epic+ drop / boss", cfgGet("discordAlert"), cfgSet("discordAlert"))
UI.input(ex, "Webhook", "paste your Discord webhook URL", function() return F.cfg.webhook ~= "" and "(saved)" or "" end, function(v)
    if type(v) == "string" and v:match("^https://discord") then F.cfg.webhook = v saveAll() end
end)
UI.button(ex, "Test alert", "Send", function() F.session.alert("test from the hub") end)
UI.toggle(ex, "Pick up fruits / chests", cfgGet("pickUp"), cfgSet("pickUp"))
UI.soon(ex, "Redeem codes")
local fa = UI.card(settings, 1, "Fruit news (read only)")
UI.toggle(fa, "Pop-up when the game announces a fruit", cfgGet("fruitAlert"), cfgSet("fruitAlert"))
UI.info(fa, "Last", function() return F.world and F.world.fruits[1] or "nothing yet" end)
UI.info(fa, "Before", function() return F.world and F.world.fruits[2] or "-" end)


-- small toggle button (the window's ... hides it, this brings it back)
local tb = new("TextButton", { Name = "Toggle", Size = UDim2.fromOffset(52, 30), Position = UDim2.new(1, -260, 0, 120),
    BackgroundColor3 = T.headBg, BackgroundTransparency = 0.1, TextColor3 = T.accent, Font = Enum.Font.GothamBold, TextSize = 14, Text = "GP" }, gui)
corner(tb, 8)
stroke(tb, T.accent)
local function setShown(v) win.Visible = v end
tb.MouseButton1Click:Connect(function() setShown(not win.Visible) end)
dots.MouseButton1Click:Connect(function() setShown(false) end)
F.conns[#F.conns + 1] = UIS.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then setShown(not win.Visible) end
end)

gui.Parent = guiParent
UI.show("Home")

task.spawn(function()
    while F.alive do
        if win.Visible then
            for _, f in ipairs(UI.refreshers) do pcall(f) end
        end
        task.wait(1)
    end
end)

G.__gpo_hub_stop = function()
    F.alive = false
    F.running = false
    pcall(function() F.core.sprint(false) end)
    for _, c in ipairs(F.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
G.__gpo_hub = F

ensureFolder()
log("loaded " .. VERSION)
notify("Ready. Ctrl or the GP button shows / hides the window.")

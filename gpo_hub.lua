-- moseeri gpo: hub window for Grand Piece Online (2026-11-19).
-- Window kit copied from moseeri nexus (NexusFarm.lua). Built by build.ps1 from src/head.lua + kit + impel + pages.
-- Lua 5.1 only. Every callback runs in pcall. Fires no game remotes: the Impel Down part walks, presses
-- proximity prompts and swings the held tool like a player. Settings in Workspace/gpohub/config.json.

local G = (getgenv and getgenv()) or _G
if G.__gpo_hub_stop then pcall(G.__gpo_hub_stop) end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local FOLDER = "gpohub"
local VERSION = "id_1"

local F = {
    alive = true,
    conns = {},
    running = false,          -- Start / Stop on Home (never saved: always off after a load)
    status = "Idle",          -- one line: what the hub is doing or waiting for
    lastAction = "",
    cfg = {
        -- Home
        mode = "Impel Down", stopHours = 3, stopOnKick = true,
        -- Combat
        preset = "Safe", useSword = true, useFruit = true, useGun = false, useStyle = true,
        normalHits = true, groupMobs = true, stunLock = true, useHaki = true,
        autoDodge = true, autoBlock = true, stayBehind = true, safeSpot = true, retreatHp = 30,
        hover = false, freezeMobs = false,
        -- Impel Down
        idDiff = "Nightmare", idSolo = true, idSecret = true, idRequeue = true, idBuy = "Nothing", idKeep = 200000,
        idCuffs = true, idChests = true, idLoot = true, idSkipJunk = true, idFight = true, idFightRange = 40, idSkills = false,
        -- Boss
        bossHop = false, bossList = { Juzo = true },
        bossRadiant = false, bossRoger = false, bossHawk = false,
        seaSerpent = false, seaMegalodon = false, seaSoulKing = false,
        -- Raids / event
        evSpooks = false, evBaal = false,
        -- Fishing
        fishSpot = "Rough Waters", fishBait = true, fishSell = true, fishKeepLeg = true, fishMegalodon = false,
        -- Level
        lvlTarget = 325, lvlQuest = true, lvlMove = true, lvlStats = "Sword / Defense", lvlHaki = false, lvlBlock = false,
        -- Settings
        normalSpeed = true, stopNearPlayer = true, antiAfk = true, autoRejoin = false,
        discordAlert = false, pickUp = false,
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
-- Impel Down engine (id_1, 2026-11-19) - only what the recorder has seen in real runs:
--   cuffs  : char has "Cuffed"; prompt "Use" on "<me>'s Handcuff Key" in Workspace.Effects
--   chests : prompt "Open" on "Common Chest" / "Rare Chest" in Workspace.Effects
--   loot   : drops are Models in Workspace.Effects with attribute brItem=true, prompt "Grab"
--   guards : Workspace.NPCs."Impel Guard" (63 hp, sword + gun, come in groups)
--   stage  : ReplicatedStorage.matchEvents("waveInfo", text, nil, "ImpelDown") - listened to, never fired
-- Moves only by walking (Humanoid:MoveTo along a path). Nothing is teleported. The maze route, the vote,
-- the end of the run and dying are NOT handled yet (never recorded).
--------------------------------------------------------------------------------
do
    local ID = { PLACE = 11424731604, prompts = {}, stage = "-", busy = false, done = { chests = 0, loot = 0, keys = 0 } }
    F.impel = ID
    local RS = game:GetService("ReplicatedStorage")
    local PFS = game:GetService("PathfindingService")
    local VIM = nil
    pcall(function() VIM = game:GetService("VirtualInputManager") end)
    local JUNK = { ["Wooden Plank"] = true }

    function ID.inRaid() return game.PlaceId == ID.PLACE end
    local function char() return LP.Character end
    local function root() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
    local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end
    local function alive() local h = hum() return h and h.Health > 0 end
    local function where(o)
        if o:IsA("BasePart") then return o.Position end
        if o:IsA("Model") then local ok, cf = pcall(function() return o:GetPivot() end) return ok and cf.Position or nil end
        if o:IsA("Attachment") then return o.WorldPosition end
        return nil
    end
    local function promptPos(p)
        local a = p.Parent
        while a and a ~= workspace do
            local v = where(a)
            if v then return v end
            a = a.Parent
        end
        return nil
    end

    -- stage text from the server (listen only)
    task.spawn(function()
        local ev = RS:WaitForChild("matchEvents", 30)
        if not ev or not F.alive then return end
        F.conns[#F.conns + 1] = ev.OnClientEvent:Connect(function(kind, text, _, mode)
            if kind == "waveInfo" and type(text) == "string" then
                ID.stage = text
                log("impel stage: " .. text .. " (" .. tostring(mode) .. ")")
            end
        end)
    end)

    -- keep a list of prompts in Workspace.Effects instead of scanning every tick
    local function addPrompt(p) if p:IsA("ProximityPrompt") then ID.prompts[p] = true end end
    task.spawn(function()
        if not ID.inRaid() then return end
        local fx = workspace:WaitForChild("Effects", 30)
        if not fx or not F.alive then return end
        for _, d in ipairs(fx:GetDescendants()) do addPrompt(d) end
        F.conns[#F.conns + 1] = fx.DescendantAdded:Connect(addPrompt)
        F.conns[#F.conns + 1] = fx.DescendantRemoving:Connect(function(d) ID.prompts[d] = nil end)
    end)

    -- which job a prompt is: "key" / "chest" / "loot" / nil
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
        local r = root()
        if not r then return nil end
        local best, bestD = nil, maxDist or 400
        for p in pairs(ID.prompts) do
            if p.Parent and p.Enabled and kindOf(p) == want then
                local pos = promptPos(p)
                local d = pos and (pos - r.Position).Magnitude
                if d and d < bestD then best, bestD = p, d end
            end
        end
        return best, bestD
    end

    -- walk (never teleport). Gives up after `limit` seconds or when stop() says so.
    function ID.walkTo(pos, near, limit, stop)
        local h, r = hum(), root()
        if not h or not r then return false end
        near = near or 4
        local t0 = os.clock()
        local points = { pos }
        local ok = pcall(function()
            local path = PFS:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
            path:ComputeAsync(r.Position, pos)
            if path.Status == Enum.PathStatus.Success then
                points = {}
                for _, w in ipairs(path:GetWaypoints()) do points[#points + 1] = w end
            end
        end)
        if not ok then points = { pos } end
        for _, w in ipairs(points) do
            local target = typeof(w) == "Vector3" and w or w.Position
            if typeof(w) ~= "Vector3" and w.Action == Enum.PathWaypointAction.Jump then h.Jump = true end
            local lastPos, stuck = r.Position, 0
            while F.alive and F.running and alive() do
                r = root()
                if not r then return false end
                if (r.Position - pos).Magnitude <= near then return true end
                if (r.Position - target).Magnitude <= 3 then break end
                if os.clock() - t0 > (limit or 20) then return false end
                if stop and stop() then return false end
                h:MoveTo(target)
                task.wait(0.25)
                if (r.Position - lastPos).Magnitude < 0.5 then
                    stuck = stuck + 1
                    if stuck == 6 then h.Jump = true end
                    if stuck >= 12 then return false end
                else stuck = 0 end
                lastPos = r.Position
            end
        end
        r = root()
        return r ~= nil and (r.Position - pos).Magnitude <= near + 2
    end

    -- press a prompt: fireproximityprompt when the executor has it, else hold E next to it
    function ID.press(p)
        if type(fireproximityprompt) == "function" then
            local ok = pcall(fireproximityprompt, p)
            if ok then task.wait(0.3) return true end
        end
        if not VIM then return false end
        pcall(function()
            VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait((p.HoldDuration or 0) + 0.15)
            VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end)
        task.wait(0.3)
        return true
    end
    local function usePrompt(p, what)
        local pos = promptPos(p)
        if not pos then ID.prompts[p] = nil return end
        F.status = "Walking to " .. what .. " (" .. tostring(p.ObjectText) .. ")"
        local reach = math.max(2, (p.MaxActivationDistance or 10) - 2)
        if ID.walkTo(pos, reach, 25, function() return not p.Parent end) and p.Parent then
            ID.press(p)
            log(what .. ": " .. tostring(p.ObjectText))
            return true
        end
        return false
    end

    -- guards
    local function nearestGuard(maxDist)
        local npcs, r = workspace:FindFirstChild("NPCs"), root()
        if not npcs or not r then return nil end
        local best, bestD = nil, maxDist
        for _, m in ipairs(npcs:GetChildren()) do
            if m.Name == "Impel Guard" then
                local h, hr = m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart")
                if h and hr and h.Health > 0 then
                    local d = (hr.Position - r.Position).Magnitude
                    if d < bestD then best, bestD = m, d end
                end
            end
        end
        return best, bestD
    end
    local function holdWeapon()
        local c = char()
        if not c then return nil end
        local t = c:FindFirstChildOfClass("Tool")
        if t then return t end
        local bp = LP:FindFirstChild("Backpack")
        local pick = bp and (bp:FindFirstChild("Melee"))
        if pick and hum() then pcall(function() hum():EquipTool(pick) end) task.wait(0.2) end
        return c:FindFirstChildOfClass("Tool")
    end
    local SKILL_KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C }
    local lastSkill, skillN = 0, 0
    local function fight(m)
        local hr, h = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
        if not hr or not h then return end
        F.status = "Fighting Impel Guard (" .. math.floor(h.Health) .. " hp)"
        local r = root()
        if r and (hr.Position - r.Position).Magnitude > 6 then
            ID.walkTo(hr.Position, 5, 4, function() return h.Health <= 0 end)
        end
        local tool = holdWeapon()
        if tool then pcall(function() tool:Activate() end) end
        if F.cfg.idSkills and VIM and os.clock() - lastSkill > 4 then
            lastSkill = os.clock()
            skillN = skillN % #SKILL_KEYS + 1
            local k = SKILL_KEYS[skillN]
            pcall(function()
                VIM:SendKeyEvent(true, k, false, game)
                task.wait(0.1)
                VIM:SendKeyEvent(false, k, false, game)
            end)
        end
        task.wait(0.25)
    end

    -- one decision per tick, most urgent first
    local function step()
        local c = char()
        if c and c:FindFirstChild("Cuffed") and F.cfg.idCuffs then
            local p = nearestPrompt("key", 1000)
            if p then if usePrompt(p, "key") then ID.done.keys = ID.done.keys + 1 end return end
            F.status = "Cuffed - key not found yet"
            return
        end
        if F.cfg.idFight then
            local g = nearestGuard(F.cfg.idFightRange)
            if g then fight(g) return end
        end
        if F.cfg.idLoot then
            local p = nearestPrompt("loot", 120)
            if p then if usePrompt(p, "loot") then ID.done.loot = ID.done.loot + 1 end return end
        end
        if F.cfg.idChests then
            local p = nearestPrompt("chest", 300)
            if p then if usePrompt(p, "chest") then ID.done.chests = ID.done.chests + 1 end return end
        end
        F.status = "Nothing near - walk on by hand (stage: " .. ID.stage .. ")"
    end

    task.spawn(function()
        while F.alive do
            if F.running and F.cfg.mode == "Impel Down" then
                if not ID.inRaid() then
                    F.status = "Not in Impel Down - queue and pick the difficulty by hand"
                elseif alive() then
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
    F.status = v and (F.cfg.mode == "Impel Down" and "Starting" or ("No farm logic yet (" .. F.cfg.mode .. ")")) or "Idle"
    log(v and ("start " .. F.cfg.mode) or "stop")
end)
UI.choice(run, "Mode", { "Impel Down", "Boss", "Raids", "Fishing", "Level" }, cfgGet("mode"), cfgSet("mode"))
UI.stepper(run, "Stop after (hours)", 1, 12, cfgGet("stopHours"), cfgSet("stopHours"))
UI.toggle(run, "Stop if kicked / warned", cfgGet("stopOnKick"), cfgSet("stopOnKick"))
local st = UI.card(home, 2, "Status")
UI.info(st, "Now", function() return F.status end)
UI.info(st, "Mode", function() return F.cfg.mode end)
UI.info(st, "Last action", function() return F.lastAction ~= "" and F.lastAction or "-" end)
UI.info(st, "Version", function() return VERSION end)
local acc = UI.card(home, 1, "Account")
UI.info(acc, "Player", function() return LP and LP.Name or "-" end)
UI.soon(acc, "Level / Peli")
local dr = UI.card(home, 2, "Session")
UI.soon(dr, "Runs / time per run")
UI.soon(dr, "Drops")

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
UI.note(idnow, "Home: Mode Impel Down + Start. Walks only. Queue, maze route and the end are still by hand.")
local idst = UI.card(impel, 2, "This run")
UI.info(idst, "Stage", function() return F.impel and F.impel.stage or "-" end)
UI.info(idst, "Chests / drops", function() return F.impel and (F.impel.done.chests .. " / " .. F.impel.done.loot) or "-" end)
UI.info(idst, "Press method", function() return type(fireproximityprompt) == "function" and "fireproximityprompt" or "hold E" end)
local raid = UI.card(impel, 1, "Raid")
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
local lf = UI.card(level, 1, "Level farm")
UI.stepper(lf, "Target level", 25, 675, cfgGet("lvlTarget"), cfgSet("lvlTarget"), 25)
UI.toggle(lf, "Auto quest", cfgGet("lvlQuest"), cfgSet("lvlQuest"))
UI.toggle(lf, "Move island by level", cfgGet("lvlMove"), cfgSet("lvlMove"))
UI.choice(lf, "Auto stat points", { "Off", "Sword / Defense", "Fruit / Defense", "Sword / Fruit" }, cfgGet("lvlStats"), cfgSet("lvlStats"))
local un = UI.card(level, 2, "Unlocks")
UI.toggle(un, "Train Armament Haki", cfgGet("lvlHaki"), cfgSet("lvlHaki"))
UI.toggle(un, "Perfect block x200", cfgGet("lvlBlock"), cfgSet("lvlBlock"))
UI.soon(un, "Daily quests")

-- Settings
local settings = UI.page("Settings", 8)
local sf = UI.card(settings, 1, "Safety")
UI.toggle(sf, "Move at normal speed only", cfgGet("normalSpeed"), cfgSet("normalSpeed"))
UI.toggle(sf, "Stop when a player is near", cfgGet("stopNearPlayer"), cfgSet("stopNearPlayer"))
UI.toggle(sf, "Anti AFK", cfgGet("antiAfk"), cfgSet("antiAfk"))
UI.toggle(sf, "Auto rejoin", cfgGet("autoRejoin"), cfgSet("autoRejoin"))
local ex = UI.card(settings, 2, "Extras")
UI.toggle(ex, "Discord alert on rare drop", cfgGet("discordAlert"), cfgSet("discordAlert"))
UI.toggle(ex, "Pick up fruits / chests", cfgGet("pickUp"), cfgSet("pickUp"))
UI.soon(ex, "Redeem codes")


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
    for _, c in ipairs(F.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
G.__gpo_hub = F

ensureFolder()
log("loaded " .. VERSION)
notify("Ready. Ctrl or the GP button shows / hides the window.")

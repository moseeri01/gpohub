-- moseeri gpo v2 (rewrite started 2026-11-20). Read LESSONS.md before changing anything.
-- Built by build2.ps1 from v2/base.lua + v2/kit.lua + v2/remote.lua + v2/modes/*.lua + v2/ui.lua -> gpo2.lua.
-- Lua 5.1. Every thread runs in pcall (the game's anti module reports errors of foreign scripts).
-- Files live in the executor workspace folder "gpo2" (v1 used "gpohub"; the two never share files).

if game.GameId ~= 648454481 then return end   -- Grand Piece Online only

local G = (getgenv and getgenv()) or _G

-- one hub only: each start takes a number, older copies (v1 or v2) are stopped
G.__gpo2_seq = (G.__gpo2_seq or 0) + 1
local MY_SEQ = G.__gpo2_seq
if G.__gpo_hub_stop then pcall(G.__gpo_hub_stop) end   -- v1 hub, and any older v2 (v2 sets the same name)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
local LP = Players.LocalPlayer
while not LP do task.wait(0.2) LP = Players.LocalPlayer end
task.wait(0.3)
if G.__gpo2_seq ~= MY_SEQ then return end

local FOLDER = "gpo2"
local VERSION = "v2_1"
local REPO_RAW = "https://raw.githubusercontent.com/moseeri01/gpohub/"

-- exact build: gpo2/want.txt (written at push time) names the commit; GitHub main is cached ~5 min.
-- Only the first load in a game session follows want.txt; after that a commit was chosen (here, or by the
-- remote command "reload <commit>") and is kept until the next teleport.
do
    local okw, want = pcall(function() return isfile and isfile(FOLDER .. "/want.txt") and readfile(FOLDER .. "/want.txt") or nil end)
    want = okw and type(want) == "string" and want:match("^%s*([0-9a-f]+)%s*$") or nil
    if want and #want >= 7 and not G.__gpo2_commit and not G.__gpo2_dev then
        G.__gpo2_commit = want
        local okd, src = pcall(function() return game:HttpGet(REPO_RAW .. want .. "/gpo2.lua") end)
        local fn = okd and type(src) == "string" and #src > 1000 and loadstring(src) or nil
        if fn then task.spawn(fn) return end
    end
end

-- safe task: every spawned function runs in pcall, errors go to our log instead of the game's error stream
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
    running = false,      -- Start / Stop (never saved)
    status = "Idle",
    lastAction = "",
    modes = {},           -- name -> { run = function() ... end } (filled by v2/modes/*.lua)
    cfg = {
        mode = "Quest",
        reloadOnTeleport = true,
    },
}
function F.isAlive() return F.alive and G.__gpo2_seq == MY_SEQ end

--------------------------------------------------------------------------------
-- files: config.json, log.txt
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
local function setStatus(s)
    if F.status ~= s then F.status = s log("status: " .. s) end
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
local function flushLog()
    while #hubErrors > 0 do logLines[#logLines + 1] = "hub error (caught): " .. table.remove(hubErrors, 1) end
    if #logLines == 0 or not canFiles then return end
    ensureFolder()
    local chunk = table.concat(logLines, "\n") .. "\n"
    logLines = {}
    pcall(function()
        local old = isfile(FOLDER .. "/log.txt") and readfile(FOLDER .. "/log.txt") or ""
        writefile(FOLDER .. "/log.txt", old:sub(-60000) .. chunk)
    end)
end
task.spawn(function()
    while F.isAlive() do task.wait(3) flushLog() end
end)
log("start " .. VERSION .. " seq " .. MY_SEQ .. (G.__gpo2_commit and (" commit " .. G.__gpo2_commit:sub(1, 7)) or ""))

--------------------------------------------------------------------------------
-- character + account (read only)
--------------------------------------------------------------------------------
local A = {}
function A.char() return LP.Character end
function A.root() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") end
function A.hum() local c = LP.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function statsFolder() return RS:FindFirstChild("Stats" .. LP.Name) end
function A.stat(name, sub)
    local f = statsFolder()
    local s = f and f:FindFirstChild(sub or "Stats")
    local v = s and s:FindFirstChild(name)
    return v and v.Value
end
function A.level() return tonumber(A.stat("Level")) or 0 end
function A.quest()
    local cur, pr = A.stat("CurrentQuest", "Quest"), A.stat("QuestProgress", "Quest")
    return cur and tostring(cur) or "", tonumber(pr) or 0
end
function A.posText()
    local r = A.root()
    if not r then return "-" end
    local p = r.Position
    return string.format("%d,%d,%d", p.X, p.Y, p.Z)
end

-- come back after a teleport (the executor runs this line in the next server)
local function queueReload()
    if not F.cfg.reloadOnTeleport or type(queue_on_teleport) ~= "function" or G.__gpo2_queued then return end
    G.__gpo2_queued = true
    pcall(queue_on_teleport, 'loadstring(game:HttpGet("' .. REPO_RAW .. 'main/gpo2.lua?t=" .. tostring(os.time())))()')
end
queueReload()

-- Window kit: copied from v1 src/kit.lua (itself from the Nexus hub) on 2026-11-20. Same window names as v1, so v2 replaces the v1 window.
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
label(head, "Grand Piece Online · v2", 12, T.mute, Enum.Font.Gotham, { Position = UDim2.fromOffset(28, 56), Size = UDim2.new(1, -120, 0, 16) })
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
-- remote: lets Claude drive tests from the PC.
--   gpo2/cmd.txt    : one command per line, read every 2 s, then emptied
--   gpo2/state.json : written every 2 s
-- Commands: ping | start | stop | mode <name> | reload [commit] | dev | close
--------------------------------------------------------------------------------
local R = {}
do
    local CMD, STATE = FOLDER .. "/cmd.txt", FOLDER .. "/state.json"

    local function writeState()
        local h = A.hum()
        local q, qp = A.quest()
        local st = {
            version = VERSION, seq = MY_SEQ, commit = G.__gpo2_commit, dev = G.__gpo2_dev and true or false,
            time = os.date("%H:%M:%S"), running = F.running, mode = F.cfg.mode, status = F.status,
            last = F.lastAction, pos = A.posText(), level = A.level(), quest = q, questProgress = qp,
            hp = h and math.floor(h.Health) or 0, maxHp = h and math.floor(h.MaxHealth) or 0,
            placeId = game.PlaceId, jobId = game.JobId,
        }
        pcall(function() writefile(STATE, HttpService:JSONEncode(st)) end)
    end

    local function loadAndRun(src, why)
        local fn = type(src) == "string" and #src > 1000 and loadstring(src) or nil
        if not fn then log(why .. ": could not load the source") return end
        log(why .. ": starting the new copy (it stops this one)")
        flushLog()
        task.spawn(fn)
    end

    local function handle(line)
        local cmd, arg = line:match("^%s*(%S+)%s*(.-)%s*$")
        if not cmd then return end
        cmd = cmd:lower()
        log("cmd: " .. line)
        if cmd == "ping" then
            log("pong " .. VERSION .. " " .. F.status)
        elseif cmd == "start" then
            F.start()
        elseif cmd == "stop" then
            F.stop()
        elseif cmd == "mode" then
            if F.modes[arg] then F.cfg.mode = arg saveAll() log("mode = " .. arg) else log("no mode named " .. arg) end
        elseif cmd == "reload" then
            local ref = (arg ~= "" and arg) or "main"
            if ref ~= "main" then G.__gpo2_commit = ref end
            G.__gpo2_dev = nil
            local ok, src = pcall(function() return game:HttpGet(REPO_RAW .. ref .. "/gpo2.lua?t=" .. tostring(os.time())) end)
            loadAndRun(ok and src, "reload " .. ref)
        elseif cmd == "dev" then
            -- local test build written by build2.ps1 (no push needed)
            local ok, src = pcall(function() return readfile(FOLDER .. "/dev.lua") end)
            G.__gpo2_dev = true
            loadAndRun(ok and src, "dev")
        elseif cmd == "close" then
            F.close()
        else
            log("unknown command: " .. cmd)
        end
    end

    task.spawn(function()
        if not canFiles then return end
        ensureFolder()
        -- commands written while no hub was running are old: drop them
        pcall(function() writefile(CMD, "") end)
        while F.isAlive() do
            task.wait(2)
            if not F.isAlive() then break end
            local ok, text = pcall(function() return isfile(CMD) and readfile(CMD) or "" end)
            if ok and type(text) == "string" and text:match("%S") then
                pcall(function() writefile(CMD, "") end)
                for line in text:gmatch("[^\r\n]+") do pcall(handle, line) end
            end
            writeState()
        end
    end)
end

--------------------------------------------------------------------------------
-- mode Quest (level farm): take quest -> beat the mobs -> hand in -> repeat.
-- Step 1 of the rewrite: empty. Filled in step 4 once move + fight pass in the real game.
--------------------------------------------------------------------------------
F.modes.Quest = {
    order = 1,
    run = function()
        setStatus("Quest: not written yet (step 4)")
        while F.running and F.isAlive() do task.wait(1) end
    end,
}

--------------------------------------------------------------------------------
-- runner + window. Start runs the chosen mode in one thread; Stop ends it at the mode's next check.
--------------------------------------------------------------------------------
local runThread = 0
function F.start()
    if F.running then return end
    local m = F.modes[F.cfg.mode]
    if not m then log("start: no mode " .. tostring(F.cfg.mode)) return end
    F.running = true
    runThread = runThread + 1
    local mine = runThread
    log("start mode " .. F.cfg.mode)
    task.spawn(function()
        local ok, err = pcall(m.run)
        if not ok then log("mode " .. F.cfg.mode .. " error: " .. tostring(err):sub(1, 200)) end
        if runThread == mine then F.running = false setStatus("Idle") end
    end)
end
function F.stop()
    if not F.running then return end
    F.running = false
    log("stop")
    setStatus("Idle")
end
function F.close()
    F.running = false
    F.alive = false
    for _, c in ipairs(F.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    log("closed")
    flushLog()
end
-- a newer copy (v1 or v2) calls this to stop us
G.__gpo_hub_stop = F.close

local modeNames = {}
for name, m in pairs(F.modes) do modeNames[#modeNames + 1] = { name = name, order = m.order or 99 } end
table.sort(modeNames, function(a, b) return a.order < b.order end)
for i, m in ipairs(modeNames) do modeNames[i] = m.name end

-- Home
local home = UI.page("Home", 1)
local run = UI.card(home, 1, "Run")
UI.choice(run, "Mode", modeNames, cfgGet("mode"), cfgSet("mode"))
UI.button(run, "Farm", "Start / Stop", function() if F.running then F.stop() else F.start() end end)
UI.info(run, "Running", function() return F.running and "yes" or "no" end)
UI.info(run, "Status", function() return F.status end)
UI.info(run, "Last", function() return F.lastAction end)

local acc = UI.card(home, 2, "Account")
UI.info(acc, "Level", function() return A.level() end)
UI.info(acc, "Quest", function() local q, p = A.quest() return q ~= "" and (q .. " (" .. p .. ")") or "none" end)
UI.info(acc, "HP", function() local h = A.hum() return h and string.format("%d / %d", h.Health, h.MaxHealth) or "-" end)
UI.info(acc, "Position", function() return A.posText() end)

-- Settings
local set = UI.page("Settings", 2)
local hub = UI.card(set, 1, "Hub")
UI.toggle(hub, "Load again after teleport", cfgGet("reloadOnTeleport"), cfgSet("reloadOnTeleport"))
UI.info(hub, "Version", function() return VERSION .. (G.__gpo2_dev and " (dev)" or "") end)
UI.button(hub, "Load newest build", "Reload", function()
    G.__gpo2_dev = nil
    local ok, src = pcall(function() return game:HttpGet(REPO_RAW .. "main/gpo2.lua?t=" .. tostring(os.time())) end)
    local fn = ok and type(src) == "string" and #src > 1000 and loadstring(src) or nil
    if fn then flushLog() task.spawn(fn) else notify("reload failed") end
end)
UI.button(hub, "Close the hub", "Close", function() F.close() end)

-- toggle key: the ··· button hides the window, RightControl shows / hides it
dots.MouseButton1Click:Connect(function() win.Visible = false notify("RightControl shows the window") end)
F.conns[#F.conns + 1] = UIS.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.RightControl then win.Visible = not win.Visible end
end)

gui.Parent = guiParent
UI.show("Home")
task.spawn(function()
    while F.isAlive() do
        if win.Visible then for _, f in ipairs(UI.refreshers) do pcall(f) end end
        task.wait(0.5)
    end
end)
log("window ready")


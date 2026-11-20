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
local VERSION = "v2_14"
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
        hover = false, hoverHeight = 7,
        questPick = "",
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

-- the server's own movement check moves the client through a "MovementCorrection" JSON attribute (read in the
-- MovementGuard code, MG:439-460). Its logic is server-side and unknown, so every value it writes is logged.
do
    local function watch(o, who)
        if not o then return end
        F.conns[#F.conns + 1] = o:GetAttributeChangedSignal("MovementCorrection"):Connect(function()
            F.corrections = (F.corrections or 0) + 1
            log("SERVER CORRECTION (" .. who .. "): " .. tostring(o:GetAttribute("MovementCorrection")):sub(1, 200))
        end)
    end
    watch(LP, "player")
    watch(LP.Character, "character")
    -- v2_12: deaths outside a fight (backing off, walking) were not logged anywhere (Rae test 10:02-10:07, 3 deaths)
    F.deaths = 0
    local lastAlivePos = nil
    task.spawn(function()
        while F.isAlive() do
            local r = A.root()
            if r then lastAlivePos = r.Position end
            task.wait(1)
        end
    end)
    F.conns[#F.conns + 1] = LP.CharacterAdded:Connect(function(c)
        F.deaths = F.deaths + 1
        log(string.format("DIED / respawned (%d this session)%s | status was: %s", F.deaths,
            lastAlivePos and string.format(" | last spot %d,%d,%d", lastAlivePos.X, lastAlivePos.Y, lastAlivePos.Z) or "", tostring(F.status)))
        watch(c, "character")
    end)
end

-- after a pull-back: the game's MovementGuard shows "Movement corrected | <reason>" on screen (MG notification).
-- Read any such text from PlayerGui shortly after, so the log says which rule fired.
function A.correctionText()
    local found = nil
    pcall(function()
        for _, o in ipairs(LP.PlayerGui:GetDescendants()) do
            if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Visible then
                local t = o.Text
                -- v2_10: "Movement" alone matched an unrelated "Ocean Movement" label
                if type(t) == "string" and t:find("orrect") then
                    found = t:gsub("<[^>]->", ""):sub(1, 120)
                    break
                end
            end
        end
    end)
    return found
end
-- v2_13 sea test 10:46: the game showed red text "Greater Flight Strike: ... is Distance from Floor: >15" while we
-- hovered 6 studs over the sea. The text is not in any client script we dumped = it comes from the server: a flight
-- check (distance from the floor, the sea bed counts) that counts strikes. Every such text is logged and counted;
-- hover / sea code stops on a new strike.
F.strikes = 0
task.spawn(function()
    local last = ""
    while F.isAlive() do
        task.wait(1)
        if F.running then
            pcall(function()
                for _, o in ipairs(LP.PlayerGui:GetDescendants()) do
                    if o:IsA("TextLabel") and o.Visible then
                        local t = o.Text
                        -- ("Strike" alone matched an unrelated "Striker" label, 10:49)
                        if type(t) == "string" and (t:find("Strike:") or t:find("Distance from Floor")) and t ~= last then
                            last = t
                            F.strikes = F.strikes + 1
                            log("GAME STRIKE NOTICE (" .. F.strikes .. "): " .. t:gsub("<[^>]->", ""):sub(1, 200) .. " | status: " .. tostring(F.status) .. " @ " .. A.posText())
                        end
                    end
                end
            end)
        end
    end
end)

function A.logPullReason(tag)
    task.spawn(function()
        for _ = 1, 6 do
            local t = A.correctionText()
            if t then log(tag .. " reason on screen: " .. t) return end
            task.wait(0.25)
        end
        log(tag .. " reason on screen: none found")
    end)
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
-- move: walk to a point like a player. Path search + Humanoid:MoveTo along the waypoints, arrival measured flat
-- (X/Z). Stuck -> Space jump, step sideways, jump + Geppo hop, new path. Never teleports, never changes WalkSpeed.
-- Every walk ends with one log line: result, distance, time, average speed, how many jumps / hops / re-paths,
-- and any pull-back seen (a jump of > 8 studs between two frames that we did not make = MovementGuard "Correct").
--------------------------------------------------------------------------------
local M = {}
do
    local PFS = game:GetService("PathfindingService")
    local RunService = game:GetService("RunService")
    local VIM = nil
    pcall(function() VIM = game:GetService("VirtualInputManager") end)

    local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
    M.flat = flat

    -- the game's own input callbacks (Backpack.InputCallbacks); the Backpack is new after every respawn
    function M.input()
        local bp = LP:FindFirstChild("Backpack")
        local m = bp and bp:FindFirstChild("InputCallbacks")
        if not m then return nil end
        if M.icMod ~= m then
            local ok, t = pcall(require, m)
            M.icMod = m
            M.ic = (ok and type(t) == "table" and type(t.Callbacks) == "table") and t or nil
            log(M.ic and "input: game callbacks ready" or "input: game callbacks missing")
        end
        return M.ic
    end

    -- jump through the game's Movements script (it owns JumpPower; Humanoid.Jump is mostly ignored)
    function M.jump()
        if os.clock() - (M.jumpAt or 0) < 1.15 then return false end
        M.jumpAt = os.clock()
        if VIM then
            task.spawn(function()
                VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.08)
                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
        else
            local h = A.hum()
            if h then h.Jump = true end
        end
        return true
    end
    function M.geppo()
        local ic = M.input()
        local g = ic and ic.Callbacks.Geppo
        if not g then return false end
        task.spawn(function() g:PC_Activate() end)
        return true
    end
    function M.inAir()
        local h = A.hum()
        return h ~= nil and h.FloorMaterial == Enum.Material.Air
    end
    -- jump, then up to 3 Geppo while in the air (gets over walls and ledges)
    function M.hop()
        M.jumpAt = 0
        M.jump()
        task.wait(0.3)
        local used = 0
        for _ = 1, 3 do
            if not M.inAir() then break end
            if M.geppo() then used = used + 1 end
            task.wait(0.35)
        end
        return used
    end
    function M.sidestep(toward, n)
        local h, r = A.hum(), A.root()
        if not h or not r then return end
        local dir = Vector3.new(toward.X - r.Position.X, 0, toward.Z - r.Position.Z)
        if dir.Magnitude < 0.5 then return end
        dir = dir.Unit
        local side = (n % 2 == 0) and 1 or -1
        local reach = math.min(4 + 2 * math.floor((n - 1) / 2), 12)
        h:MoveTo(r.Position + Vector3.new(-dir.Z, 0, dir.X) * side * reach - dir * 1.5)
        task.wait(0.55)
    end

    -- seats on the road make the character sit and stop: no sitting while we walk
    local function noSit(on)
        local h = A.hum()
        if not h then return end
        pcall(function()
            if on and h.Sit then h.Sit = false end
            h:SetStateEnabled(Enum.HumanoidStateType.Seated, not on)
        end)
    end

    local function computePath(from, to)
        local pts, state = nil, "?"
        pcall(function()
            local path = PFS:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
            path:ComputeAsync(from, to)
            state = tostring(path.Status):gsub("Enum.PathStatus.", "")
            if path.Status == Enum.PathStatus.Success then
                pts = {}
                for _, w in ipairs(path:GetWaypoints()) do pts[#pts + 1] = w end
            end
        end)
        return pts, state
    end

    -- walk to pos. opts: near (default 4), limit seconds (default 10 + 1 per 12 studs), stop() -> true to cancel.
    -- Returns ok, why.
    function M.walkTo(pos, opts)
        opts = opts or {}
        local near = opts.near or 4
        local h, r = A.hum(), A.root()
        if not h or not r or h.Health <= 0 then return false, "no character" end
        local start, t0 = r.Position, os.clock()
        local dist0 = flat(start, pos)
        -- v2_2 test 07:41: paths wind (10-12 studs/s average at 15 walk speed) and can detour far, so the hard cap
        -- is wide; the real stop is "no progress": the distance left has not shrunk by 5 studs in 20 s
        local limit = opts.limit or (30 + dist0 / 5)
        local best, bestAt = dist0, os.clock()
        local st = { jumps = 0, hops = 0, sides = 0, repaths = 0, pulls = 0, maxPull = 0 }

        -- pull-back watch
        local lastP = r.Position
        local hb = RunService.Heartbeat:Connect(function()
            local rr = A.root()
            if not rr then return end
            local p = rr.Position
            local d = (p - lastP).Magnitude
            if d > 8 then
                st.pulls = st.pulls + 1
                if d > st.maxPull then st.maxPull = d end
                if st.pulls <= 3 then A.logPullReason("walk pull") log(string.format("move: PULLED %.0f studs (%.0f,%.0f,%.0f -> %.0f,%.0f,%.0f)", d, lastP.X, lastP.Y, lastP.Z, p.X, p.Y, p.Z)) end
            end
            lastP = p
        end)

        noSit(true)
        local ok, why = false, "?"
        local okRun, err = pcall(function()
            local stuckTotal = 0
            while true do
                r = A.root()
                h = A.hum()
                if not r or not h or h.Health <= 0 then why = "died" return end
                if flat(r.Position, pos) <= near then ok, why = true, "arrived" return end
                local pts, pstate = computePath(r.Position, pos)
                local list = {}
                if pts then
                    for i = 2, #pts do list[#list + 1] = pts[i] end   -- waypoint 1 = our own feet
                else
                    list[1] = { Position = pos, Action = Enum.PathWaypointAction.Walk }
                    if st.repaths == 0 then log("move: no path (" .. pstate .. "), walking straight") end
                end
                local blocked = false
                for _, w in ipairs(list) do
                    local target = w.Position
                    if w.Action == Enum.PathWaypointAction.Jump then if M.jump() then st.jumps = st.jumps + 1 end end
                    local last, stuck = r.Position, 0
                    while true do
                        if not F.isAlive() or not F.running then why = "stopped" return end
                        if opts.stop and opts.stop() then why = "cancelled" return end
                        r, h = A.root(), A.hum()
                        if not r or not h or h.Health <= 0 then why = "died" return end
                        if flat(r.Position, pos) <= near then ok, why = true, "arrived" return end
                        if flat(r.Position, target) <= 3 then bestAt = os.clock() break end   -- a path point reached counts as progress (detours)
                        if os.clock() - t0 > limit then why = "timeout" return end
                        local left = flat(r.Position, pos)
                        if left < best - 5 then best, bestAt = left, os.clock()
                        elseif os.clock() - bestAt > 20 then why = string.format("no progress for 20 s (%.0f left)", left) return end
                        h:MoveTo(target)
                        task.wait(0.25)
                        if flat(r.Position, last) < 0.5 then
                            stuck = stuck + 1
                            stuckTotal = stuckTotal + 1
                            if stuck == 2 or stuck == 5 then if M.jump() then st.jumps = st.jumps + 1 end
                            elseif stuck == 3 or stuck == 6 then st.sides = st.sides + 1 M.sidestep(target, st.sides)
                            elseif stuck == 8 then st.hops = st.hops + 1 M.hop()
                            elseif stuck >= 10 then blocked = true break end
                        else stuck = 0 end
                        last = r.Position
                    end
                    if blocked then break end
                end
                if not blocked then
                    r = A.root()
                    if r and flat(r.Position, pos) <= near + 2 then ok, why = true, "arrived" return end
                end
                st.repaths = st.repaths + 1
                if st.repaths > 4 then why = "stuck (5 paths tried)" return end
            end
        end)
        if not okRun then why = "error: " .. tostring(err):sub(1, 120) end
        hb:Disconnect()
        noSit(false)

        r = A.root()
        local dt = os.clock() - t0
        local moved = r and flat(r.Position, start) or 0
        local left = r and flat(r.Position, pos) or -1
        log(string.format("move: %s | %.0f -> %.0f studs left in %.1f s (%.1f studs/s) | jumps %d, sidesteps %d, hops %d, new paths %d | pulled back %d (max %.0f)",
            why, dist0, left, dt, moved / math.max(dt, 0.1), st.jumps, st.sides, st.hops, st.repaths, st.pulls, st.maxPull))
        return ok, why, st
    end
end

-- "Move test" mode: walks the list in F.moveList (filled by the remote commands goto / route), one line per point
F.moveList = {}
F.modes["Move test"] = {
    order = 9,
    run = function()
        local list = F.moveList
        if #list == 0 then setStatus("Move test: no points (remote: goto x y z / route ...)") task.wait(1) return end
        local pass = 0
        for i, p in ipairs(list) do
            if not F.running then break end
            setStatus(string.format("Move test: point %d/%d %s", i, #list, p.name or ""))
            local ok, why
            if p.water then ok, why = F.fight.waterWalk(p.pos, { near = 8 })
            elseif p.sea then ok, why = F.fight.seaGlide(p.pos, { near = 8 })
            elseif p.glide then ok, why = F.fight.glideTo(p.pos, { near = 5 }) else ok, why = M.walkTo(p.pos, { near = 5 }) end
            if ok then pass = pass + 1 end
            log(string.format("movetest: point %d %s -> %s", i, p.name or "", why))
            if not ok and why ~= "timeout" and why:find("stuck") == nil then break end
            task.wait(0.5)
        end
        log(string.format("movetest: done, %d of %d points reached", pass, #list))
    end,
}

--------------------------------------------------------------------------------
-- fight: pick the nearest enemy, close in, face it, M1 through the game's own Attack call (proven in v1 with
-- Magu-Magu, hits landed at 0.8-4.3 studs), hold F to block when own HP drops fast, back off when HP is low.
-- No skills yet, no hover yet (added after this works). Counters for the test line: swings, "air swings"
-- (swung while the target was out of reach), damage dealt, HP lost, blocks, retreats.
--------------------------------------------------------------------------------
local Fi = { reach = 4.5 }
do
    local VIM = nil
    pcall(function() VIM = game:GetService("VirtualInputManager") end)
    local flat = M.flat

    -- quest givers carry no prompt, so their names come from the game's own quest table (asked once)
    local questNames = nil
    local function isQuestGiver(name)
        if questNames == nil then
            questNames = {}
            pcall(function()
                local t = RS.Events.Quest:InvokeServer({ "getQuestLocations" })
                if type(t) == "table" then for k in pairs(t) do questNames[tostring(k)] = true end end
            end)
        end
        return questNames[name] == true
    end
    function Fi.isMob(m)
        if not m:IsA("Model") then return false end
        local h, hr = m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart")
        if not h or not hr or h.Health <= 0 then return false end
        if m:FindFirstChildWhichIsA("ProximityPrompt", true) then return false end
        if Players:GetPlayerFromCharacter(m) then return false end
        return not isQuestGiver(m.Name)
    end
    -- nearest enemy within range of `around` (default: us); accept(m) filters further
    function Fi.nearest(range, around, accept)
        local npcs, r = workspace:FindFirstChild("NPCs"), A.root()
        if not npcs or not r then return nil end
        around = around or r.Position
        local best, bestD = nil, range
        for _, m in ipairs(npcs:GetChildren()) do
            if Fi.isMob(m) and (not accept or accept(m)) then
                local hr = m.HumanoidRootPart
                if (hr.Position - around).Magnitude <= range then
                    local d = (hr.Position - r.Position).Magnitude
                    if d < bestD then best, bestD = m, d end
                end
            end
        end
        return best, bestD
    end

    -- weapon: keep a weapon in hand; else the best one in the Backpack (v1 order: the stat behind it decides)
    local function weaponRank(t)
        if not t:IsA("Tool") or t:GetAttribute("Category") ~= "Weapons" then return nil end
        if t:GetAttribute("devilFruit") then return 30 - (tonumber(A.stat("DevilFruitMastery")) or 0) / 10 end
        if t:GetAttribute("MeleeTool") then return 20 - (tonumber(A.stat("Strength")) or 0) / 10 end
        return 15 - (tonumber(A.stat("SwordMastery")) or 0) / 10
    end
    function Fi.holdWeapon()
        local c = A.char()
        if not c then return nil end
        local held = c:FindFirstChildOfClass("Tool")
        if held and weaponRank(held) then return held end
        local bp = LP:FindFirstChild("Backpack")
        local pick, best = nil, 99
        for _, t in ipairs(bp and bp:GetChildren() or {}) do
            local rk = weaponRank(t)
            if rk and rk < best then pick, best = t, rk end
        end
        if pick and A.hum() then
            pcall(function() A.hum():EquipTool(pick) end)
            log("fight: equip " .. pick.Name)
            task.wait(0.3)
        end
        return c:FindFirstChildOfClass("Tool")
    end

    local function face(pos)
        local r = A.root()
        if not r then return end
        local to = Vector3.new(pos.X, r.Position.Y, pos.Z)
        if (to - r.Position).Magnitude > 0.5 then pcall(function() r.CFrame = CFrame.lookAt(r.Position, to) end) end
    end
    local function holdKey(k, secs)
        if not VIM then return end
        task.spawn(function()
            VIM:SendKeyEvent(true, k, false, game)
            task.wait(secs)
            VIM:SendKeyEvent(false, k, false, game)
        end)
    end

    -- own HP over the last 1.2 s (block decision)
    local hpHist = {}
    task.spawn(function()
        while F.isAlive() do
            local h = A.hum()
            if h then
                local now = os.clock()
                hpHist[#hpHist + 1] = { now, h.Health }
                while #hpHist > 1 and now - hpHist[1][1] > 1.2 do table.remove(hpHist, 1) end
            end
            task.wait(0.2)
        end
    end)
    local function hpDrop()
        local h = A.hum()
        if not h then return 0 end
        local top = h.Health
        for _, e in ipairs(hpHist) do if e[2] > top then top = e[2] end end
        return top - h.Health
    end

    Fi.st = { swings = 0, airSwings = 0, blocks = 0, retreats = 0 }
    local function swing()
        local ic = M.input()
        local atk = ic and ic.Callbacks.Attack
        if not atk then return false end
        local can = false
        pcall(function() can = ic.Utils.canAutoM1() end)
        if can ~= true then return false end
        task.spawn(function() atk:PC_Activate() end)
        return true
    end

    -- skills (v2_5): v2_4 test 08:01 - M1 alone with Magu-Magu took 90 s and did not kill a 450 hp Zombie (the
    -- account has its points in Defense / Stamina, the fruit's damage is in its skills). v1 killed the same Zombies
    -- in 3-15 s with skills on. Same way as v1: point the camera at the target (skills aim from the client), hold
    -- the key 0.6 s (fruit skills charge while held, fire on release), one key every 1.5 s.
    local SKILL_KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.E, Enum.KeyCode.R }
    local skillN, lastSkill = 0, 0
    Fi.st.skills = 0
    function Fi.skill(pos)
        if not VIM or os.clock() - lastSkill < 1.5 then return false end
        lastSkill = os.clock()
        skillN = skillN % #SKILL_KEYS + 1
        pcall(function()
            local cam = workspace.CurrentCamera
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
            VIM:SendMouseMoveEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, game)
        end)
        Fi.st.skills = Fi.st.skills + 1
        VIM:SendKeyEvent(true, SKILL_KEYS[skillN], false, game)
        task.wait(0.6)
        VIM:SendKeyEvent(false, SKILL_KEYS[skillN], false, game)
        task.wait(0.3)
        return true
    end

    -- hover (v2_6, owner 11-20: float near the mob, no visible Geppo pose). Read in the game code (MovementGuard
    -- Rules R:304-340): "hover" = in the air with |vertical speed| <= 3 for 2 s, and it only writes a warning;
    -- what pulls back is horizontal speed (> 25 studs/s sprinting, burst 16.5 studs per 0.5 s) or > 24 studs in
    -- one 0.05 s sample. Geppo gives no air allowance, so it is not used here. So: an AlignPosition holds us
    -- H studs over the target, capped at 22 studs/s, with a slow up-down bob (peak ~6 studs/s) so the vertical
    -- speed never stays under 3 for 2 s. No HipHeight / Gravity / WalkSpeed change (the anti module checks those).
    local HV = { n = 0, pulls = 0 }
    Fi.hv = HV
    function Fi.hoverOff()
        if HV.ap then pcall(function() HV.ap:Destroy() end) pcall(function() HV.att:Destroy() end) end
        HV.ap, HV.att, HV.target, HV.dir = nil, nil, nil, nil
        pcall(function() A.hum():Move(Vector3.zero, false) end)
    end
    -- nothing solid between a and b (characters, mobs and effects ignored); a box sweep about the size of the body
    function Fi.clearLine(a, b, ignore)
        local ok, clear = pcall(function()
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects"), ignore }
            local dir = b - a
            if dir.Magnitude < 1 then return true end
            local hit = workspace:Blockcast(CFrame.lookAt(a, b), Vector3.new(3, 4, 1), dir, rp)
            return hit == nil
        end)
        return ok and clear
    end
    -- glide (hover travel) to a ground point; returns ok, why. Logs time, average speed, run share, pulls.
    function Fi.glideTo(pos, opts)
        opts = opts or {}
        local r = A.root()
        if not r then return false, "no character" end
        local t0, start, p0 = os.clock(), r.Position, HV.pulls
        local s0, w0 = HV.sprintTicks or 0, HV.walkTicks or 0
        local dist0 = M.flat(start, pos)
        local ok, why = false, "timeout"
        local char0 = A.char()
        while F.running and F.isAlive() do
            if A.char() ~= char0 then why = "died" break end
            r = A.root()
            if not r then why = "no character" break end
            if M.flat(r.Position, pos) <= (opts.near or 4) then ok, why = true, "arrived" break end
            if os.clock() - t0 > (opts.limit or (10 + dist0 / 10)) then break end
            Fi.hoverOn(pos)
            task.wait(0.2)
        end
        Fi.hoverOff()
        local dt = os.clock() - t0
        local sT, wT = (HV.sprintTicks or 0) - s0, (HV.walkTicks or 0) - w0
        log(string.format("glide: %s | %.0f studs in %.1f s (%.1f studs/s) | run state %d%% | pulls %d",
            why, dist0, dt, dist0 / math.max(dt, 0.1), (sT + wT) > 0 and math.floor(sT / (sT + wT) * 100) or 0, HV.pulls - p0))
        return ok, why
    end
    -- sea glide: hover travel over water (and over land in the way) to a far point. Returns ok, why.
    -- Progress line every 30 s. Stops when the distance left has not shrunk by 15 studs in 25 s ("blocked").
    function Fi.seaGlide(pos, opts)
        opts = opts or {}
        local r = A.root()
        if not r then return false, "no character" end
        if HV.ocean == nil then
            HV.ocean = false
            pcall(function()
                local om = require(RS.Modules.OceanModule)
                if type(om.HeightLookup) == "function" then
                    HV.ocean = function(x, z) local ok, y = pcall(om.HeightLookup, x, z) return ok and tonumber(y) or 0 end
                end
            end)
            log("sea: ocean height from the game " .. (HV.ocean and string.format("ok (%.1f here)", HV.ocean(r.Position.X, r.Position.Z)) or "NOT available - using y 0"))
        end
        local t0, start, p0, c0 = os.clock(), r.Position, HV.pulls, HV.climbs or 0
        local dist0 = M.flat(start, pos)
        local best, bestAt, lastLog = dist0, os.clock(), os.clock()
        local lowest, hp0 = r.Position.Y, A.hum() and A.hum().Health or 0
        local ok, why = false, "stopped"
        local char0 = A.char()
        local strikes0 = F.strikes
        while F.running and F.isAlive() do
            if A.char() ~= char0 then why = "died" break end
            r = A.root()
            local h = A.hum()
            if not r or not h or h.Health <= 0 then why = "died" break end
            local left = M.flat(r.Position, pos)
            lowest = math.min(lowest, r.Position.Y)
            if left <= (opts.near or 8) then ok, why = true, "arrived" break end
            if F.strikes > strikes0 then why = "game flight strike - stopped" break end
            if left < best - 15 then best, bestAt = left, os.clock()
            elseif os.clock() - bestAt > 25 then why = string.format("blocked (%.0f left)", left) break end
            if os.clock() - t0 > (opts.limit or (60 + dist0 / 8)) then why = "timeout" break end
            if os.clock() - lastLog > 30 then
                lastLog = os.clock()
                log(string.format("sea: %.0f left | y %.0f (floor %.0f) | hp %d | %s | pulls %d, climbs %d | corrections %d",
                    left, r.Position.Y, HV.seaFloor or 0, h.Health, tostring(h:GetState()):gsub("Enum.HumanoidStateType.", ""), HV.pulls - p0, (HV.climbs or 0) - c0, F.corrections or 0))
            end
            HV.sea = true
            Fi.hoverOn(pos)
            task.wait(0.2)
        end
        HV.sea, HV.seaTarget = false, nil
        Fi.hoverOff()
        r = A.root()
        local dt = os.clock() - t0
        local moved = r and M.flat(r.Position, start) or 0
        log(string.format("sea: %s | %.0f of %.0f studs in %.0f s (%.1f studs/s) | lowest y %.0f | hp %d -> %d | pulls %d, climbs %d",
            why, moved, dist0, dt, moved / math.max(dt, 0.1), lowest, hp0, A.hum() and A.hum().Health or 0, HV.pulls - p0, (HV.climbs or 0) - c0))
        return ok, why
    end
    -- water walk (v2_14, owner 11-20): cross the sea ON the surface like a Magu player - plain Humanoid:MoveTo,
    -- no AlignPosition, no hover. The game's own WaterLogia script holds a logia user on the water.
    -- Stops at once on: a game strike notice, sinking / swimming, HP loss over 15 %, no progress for 15 s.
    function Fi.waterWalk(pos, opts)
        opts = opts or {}
        local r, h = A.root(), A.hum()
        if not r or not h then return false, "no character" end
        Fi.hoverOff()
        if HV.ocean == nil then
            HV.ocean = false
            pcall(function()
                local om = require(RS.Modules.OceanModule)
                if type(om.HeightLookup) == "function" then
                    HV.ocean = function(x, z) local ok, y = pcall(om.HeightLookup, x, z) return ok and tonumber(y) or 0 end
                end
            end)
        end
        local t0, start, hp0, strikes0, pulls = os.clock(), r.Position, h.Health, F.strikes, 0
        local dist0 = M.flat(start, pos)
        local best, bestAt, lastLog, lastP = dist0, os.clock(), os.clock(), r.Position
        local lowest, onWater = r.Position.Y, 0
        local ok, why = false, "stopped"
        local char0 = A.char()
        while F.running and F.isAlive() do
            if A.char() ~= char0 then why = "died" break end
            r, h = A.root(), A.hum()
            if not r or not h or h.Health <= 0 then why = "died" break end
            local p = r.Position
            local left = M.flat(p, pos)
            local sea = HV.ocean and HV.ocean(p.X, p.Z) or 0
            lowest = math.min(lowest, p.Y)
            if (p - lastP).Magnitude > 8 then pulls = pulls + 1 log(string.format("water: PULLED %.0f studs (%.0f,%.0f,%.0f -> %.0f,%.0f,%.0f)", (p - lastP).Magnitude, lastP.X, lastP.Y, lastP.Z, p.X, p.Y, p.Z)) end
            lastP = p
            if left <= (opts.near or 8) then ok, why = true, "arrived" break end
            if F.strikes > strikes0 then why = "GAME STRIKE - stopped" break end
            if h:GetState() == Enum.HumanoidStateType.Swimming then why = "swimming (not held on the water)" break end
            if p.Y < sea - 6 then why = string.format("sinking (y %.0f, sea %.0f)", p.Y, sea) break end
            if h.Health < hp0 - h.MaxHealth * 0.15 then why = string.format("losing HP (%d -> %d)", hp0, h.Health) break end
            if left < best - 8 then best, bestAt = left, os.clock()
            elseif os.clock() - bestAt > 15 then why = string.format("blocked (%.0f left)", left) break end
            if os.clock() - t0 > (opts.limit or (60 + dist0 / 8)) then why = "timeout" break end
            if math.abs(p.Y - sea) < 6 then onWater = onWater + 1 end
            if os.clock() - lastLog > 15 then
                lastLog = os.clock()
                log(string.format("water: %.0f left | y %.1f (sea %.1f) | floor %s | hp %d | %s | strikes %d, corrections %d",
                    left, p.Y, sea, h.FloorMaterial.Name, h.Health, tostring(h:GetState()):gsub("Enum.HumanoidStateType.", ""), F.strikes - strikes0, F.corrections or 0))
            end
            local d = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z)
            h:MoveTo(p + d.Unit * math.min(left, 30))
            task.wait(0.25)
        end
        pcall(function() local rr = A.root() if rr then A.hum():MoveTo(rr.Position) end end)
        r = A.root()
        local dt = os.clock() - t0
        local moved = r and M.flat(r.Position, start) or 0
        log(string.format("water: %s | %.0f of %.0f studs in %.0f s (%.1f studs/s) | on water %.0f s | lowest y %.1f | hp %d -> %d | pulls %d | strikes %d",
            why, moved, dist0, dt, moved / math.max(dt, 0.1), onWater * 0.25, lowest, hp0, A.hum() and A.hum().Health or 0, pulls, F.strikes - strikes0))
        return ok, why
    end
    function Fi.hoverOn(target)
        HV.target, HV.t = target, os.clock()
        local r = A.root()
        if not r then return end
        if HV.ap and HV.ap.Parent == r then return end
        Fi.hoverOff()
        HV.target = target
        pcall(function()
            local att = Instance.new("Attachment")
            att.Name = "RootRigAttachment2"
            att.Parent = r
            local ap = Instance.new("AlignPosition")
            ap.Name = "Align"
            ap.Mode = Enum.PositionAlignmentMode.OneAttachment
            ap.Attachment0 = att
            ap.MaxForce = 1e6
            ap.MaxVelocity = 22
            ap.Responsiveness = 30
            ap.Position = r.Position
            ap.Parent = r
            HV.att, HV.ap = att, ap
            HV.n = HV.n + 1
            HV.lastP = r.Position
        end)
    end
    -- v2_7: the guard's speed limit is RunSpeed 25 only while the character has MovementSprintActive = true
    -- (Rules R:30, MG:233), else GroundSpeed 16. v2_6 glided at 22 without it -> the 20-studs "pulls" down to the
    -- ground (y 66 -> 57) were most likely the guard's Correct back to the last ground spot. So: ask the game to run
    -- (the same Run call as a double W) and glide at 24 only while the attribute is on, else 15.
    local function sprinting()
        local c = A.char()
        return c ~= nil and c:GetAttribute("MovementSprintActive") == true
    end
    Fi.sprinting = sprinting
    local function askRun()
        if sprinting() or os.clock() - (HV.runAt or 0) < 1 then return end
        HV.runAt = os.clock()
        local ic = M.input()
        local run = ic and ic.Callbacks.Run
        if not run then return end
        task.spawn(function() run.HoldingRun = true run:PC_Activate() end)
    end
    F.conns[#F.conns + 1] = game:GetService("RunService").Heartbeat:Connect(function()
        if not HV.ap then return end
        local tg = HV.target
        -- target = a mob (fight) or a Vector3 point on the ground (glide travel)
        local goal
        if typeof(tg) == "Vector3" then
            goal = tg
        else
            local hr = tg and tg:FindFirstChild("HumanoidRootPart")
            local th = tg and tg:FindFirstChildOfClass("Humanoid")
            if hr and th and th.Health > 0 then goal = hr.Position end
        end
        -- ends by itself: Stop, target gone, or no beat for 1.5 s
        if not F.running or not goal or os.clock() - HV.t > 1.5 then Fi.hoverOff() return end
        -- a game flight strike while hovering: hover goes off for good (until the owner turns it on again)
        if F.strikes > (HV.strikesSeen or 0) then
            HV.strikesSeen = F.strikes
            if F.cfg.hover then F.cfg.hover = false log("hover: switched OFF after a game strike notice") end
            Fi.hoverOff()
            return
        end
        -- owner 11-20: steady height, no bob (the guard's hover rule only writes a warning, MG:1013)
        local r, h = A.root(), A.hum()
        -- v2_8 probe: AutoRun is on but the game never starts running while MoveDirection is 0 (the AlignPosition
        -- moves us, not the Humanoid). Give the Humanoid the same direction as walk input (Humanoid:Move), so the
        -- game's own AutoRun / Run sees a moving player.
        if r and h then
            local dir = Vector3.new(goal.X - r.Position.X, 0, goal.Z - r.Position.Z)
            HV.dir = dir.Magnitude > 3 and dir.Unit or Vector3.zero   -- applied in the render step below
        end
        askRun()
        local sp = sprinting()
        HV.ap.MaxVelocity = sp and 24 or 15
        if sp then HV.sprintTicks = (HV.sprintTicks or 0) + 1 else HV.walkTicks = (HV.walkTicks or 0) + 1 end
        if HV.sea and r and typeof(tg) == "Vector3" then
            -- sea travel (v2_13, owner: "float like walking on water"): keep H studs over whatever is below -
            -- the ocean surface (the game's own OceanModule.HeightLookup) or land / a ship / a rock - looking
            -- 14 studs ahead too, and climb when something solid is in the way
            if os.clock() - (HV.seaAt or 0) > 0.1 then
                HV.seaAt = os.clock()
                local p = r.Position
                local dir = Vector3.new(goal.X - p.X, 0, goal.Z - p.Z)
                local left = dir.Magnitude
                dir = left > 0.5 and dir.Unit or Vector3.zero
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
                rp.IgnoreWater = true
                local function floorAt(q)
                    local y = HV.ocean and HV.ocean(q.X, q.Z) or 0
                    local hit = workspace:Raycast(Vector3.new(q.X, p.Y + 30, q.Z), Vector3.new(0, -400, 0), rp)
                    if hit and hit.Position.Y > y then y = hit.Position.Y end
                    return y
                end
                local H = F.cfg.seaHeight or 6
                local floorY = math.max(floorAt(p), floorAt(p + dir * 14))
                local step = math.min(left, 40)
                local wall = workspace:Blockcast(CFrame.new(p), Vector3.new(3, 4, 3), dir * 14, rp)
                local ty = floorY + H
                if wall then ty = math.max(ty, p.Y + 12) step = 2 HV.climbs = (HV.climbs or 0) + 1 end
                HV.seaFloor = floorY
                HV.seaTarget = Vector3.new(p.X + dir.X * step, ty, p.Z + dir.Z * step)
            end
            if HV.seaTarget then HV.ap.Position = HV.seaTarget end
        else
            HV.ap.Position = goal + Vector3.new(0, F.cfg.hoverHeight or 7, 0)
        end
        if r and HV.lastP then
            local d = (r.Position - HV.lastP).Magnitude
            if d > 8 then
                HV.pulls = HV.pulls + 1
                A.logPullReason("hover pull")
                log(string.format("hover: PULLED %.0f studs (%.0f,%.0f,%.0f -> %.0f,%.0f,%.0f)", d, HV.lastP.X, HV.lastP.Y, HV.lastP.Z, r.Position.X, r.Position.Y, r.Position.Z))
            end
        end
        HV.lastP = r and r.Position
    end)

    -- the player control script calls Humanoid:Move(keyboard input) every render step; ours runs right after it
    pcall(function()
        local RunS = game:GetService("RunService")
        pcall(function() RunS:UnbindFromRenderStep("gpo2_move") end)
        RunS:BindToRenderStep("gpo2_move", Enum.RenderPriority.Character.Value + 1, function()
            if HV.ap and HV.dir then
                local h = A.hum()
                if h then h:Move(HV.dir, false) end
            end
        end)
    end)

    -- back off: walk away from the enemy and wait until HP is back above `back` %
    function Fi.retreat(from, back)
        Fi.st.retreats = Fi.st.retreats + 1
        Fi.hoverOff()
        local r = A.root()
        if not r then return end
        local away = Vector3.new(r.Position.X - from.X, 0, r.Position.Z - from.Z)
        away = away.Magnitude > 1 and away.Unit or Vector3.new(1, 0, 0)
        log(string.format("fight: low HP (%d%%), backing off", A.hum() and A.hum().Health / A.hum().MaxHealth * 100 or 0))
        M.walkTo(r.Position + away * 60, { near = 6, limit = 12 })
        local t0 = os.clock()
        while F.running and F.isAlive() and os.clock() - t0 < 40 do
            local h = A.hum()
            if not h or h.Health <= 0 or h.Health >= h.MaxHealth * back / 100 then break end
            task.wait(0.5)
        end
    end

    -- fight one enemy until it dies, we die, Stop, or it is lost. Returns "killed" / "died" / "lost" / "stopped" / "retreat"
    function Fi.kill(m, opts)
        opts = opts or {}
        local hr, mh = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
        if not hr or not mh then return "lost" end
        local t0, lastSeenClose = os.clock(), os.clock()
        -- a respawn gives a new character with full HP: v2_4 counted two deaths as "retreat", so check the object
        local char0 = A.char()
        while true do
            if not F.running or not F.isAlive() then return "stopped" end
            local h, r = A.hum(), A.root()
            if A.char() ~= char0 or not h or not r or h.Health <= 0 then return "died" end
            if not m.Parent or mh.Health <= 0 then return "killed" end
            if os.clock() - t0 > (opts.limit or 90) then return "lost" end
            if h.Health < h.MaxHealth * (opts.retreatHp or 30) / 100 then Fi.retreat(hr.Position, opts.backHp or 75) return "retreat" end
            F.status = string.format("Fighting %s (%d hp)", m.Name, mh.Health)

            local d = (hr.Position - r.Position).Magnitude
            -- v2_7: glide up to 150 studs. v2_8 test 08:47: a straight glide stuck on a cliff wall for a minute ->
            -- glide only with a clear line from us to the hover spot; else walk (the path goes around)
            local hovering = opts.hover and F.cfg.hover and (d <= 12 or (d <= 150 and Fi.clearLine(r.Position, hr.Position + Vector3.new(0, F.cfg.hoverHeight or 7, 0), m)))
            if hovering then
                Fi.hoverOn(m)          -- the AlignPosition carries us there (22 studs/s max)
                task.wait(0.1)
            elseif d > 40 then
                M.walkTo(hr.Position, { near = Fi.reach, limit = 15, stop = function() return mh.Health <= 0 or not m.Parent end })
            elseif d > Fi.reach then
                -- close chase: follow directly, re-aim every 0.15 s, up to 1.2 s
                local c0 = os.clock()
                while F.running and mh.Health > 0 and os.clock() - c0 < 1.2 do
                    r = A.root()
                    if not r or (hr.Position - r.Position).Magnitude <= Fi.reach then break end
                    h:MoveTo(hr.Position)
                    task.wait(0.15)
                end
            end
            r = A.root()
            if not r then return "died" end
            -- hovering: reach is measured flat (we are hoverHeight studs above the target on purpose)
            d = hovering and flat(hr.Position, r.Position) or (hr.Position - r.Position).Magnitude
            if d <= Fi.reach + 2 then lastSeenClose = os.clock() end
            if os.clock() - lastSeenClose > 25 then return "lost" end

            face(hr.Position)
            Fi.holdWeapon()
            local drop = hpDrop()
            if d <= 9 and drop >= h.MaxHealth * 0.06 and os.clock() - (Fi.lastBlock or 0) > 2 then
                Fi.lastBlock = os.clock()
                Fi.st.blocks = Fi.st.blocks + 1
                holdKey(Enum.KeyCode.F, 0.8)
                hpHist = {}
                task.wait(0.85)
            elseif opts.skills ~= false and d <= 12 and Fi.skill(hr.Position) then
                -- skill used (no M1 right before it: an M1 keeps the game from casting)
            elseif d <= Fi.reach + 2 then
                -- v2_5 test: 10 of 18 swings went out while chasing (out of reach) -> swing only when in reach
                if swing() then Fi.st.swings = Fi.st.swings + 1 end
                task.wait(0.25)
            else
                Fi.st.airSwings = Fi.st.airSwings + 1   -- now counts "wanted to swing, too far"
                task.wait(0.1)
            end
        end
    end
end
F.fight = Fi

-- "Fight test" mode: kill enemies around the spot where Start was pressed (range F.cfg.fightRange), until
-- F.cfg.fightCount kills; one line per enemy, one summary line
F.cfg.fightRange = F.cfg.fightRange or 120
F.cfg.fightCount = F.cfg.fightCount or 10
F.modes["Fight test"] = {
    order = 8,
    run = function()
        local r = A.root()
        if not r then return end
        local home = r.Position
        local kills, deaths, t0 = 0, 0, os.clock()
        local s0 = { swings = Fi.st.swings, air = Fi.st.airSwings, blocks = Fi.st.blocks, retreats = Fi.st.retreats, pulls = Fi.hv.pulls,
            spT = Fi.hv.sprintTicks or 0, wkT = Fi.hv.walkTicks or 0, corr = F.corrections or 0 }
        local idleSince = nil
        while F.running and F.isAlive() and kills < F.cfg.fightCount do
            local h = A.hum()
            if not h or h.Health <= 0 then
                deaths = deaths + 1
                log("fighttest: died - stopping")
                break
            end
            -- v2_6 test 08:29: a test started at 45/665 HP (left standing among Zombies after the last one) and died.
            -- Below 60 % before a new target: back off first and heal.
            local m = Fi.nearest(F.cfg.fightRange, home)
            if m and h.Health < h.MaxHealth * 0.6 then
                Fi.retreat(m.HumanoidRootPart.Position, 80)
            elseif not m then
                idleSince = idleSince or os.clock()
                setStatus("Fight test: no enemy in range, waiting")
                if os.clock() - idleSince > 60 then log("fighttest: no enemy for 60 s - stopping") break end
                -- go back near the start spot while waiting
                local rr = A.root()
                if rr and M.flat(rr.Position, home) > 30 then M.walkTo(home, { near = 10 }) end
                task.wait(1)
            else
                idleSince = nil
                local mh = m:FindFirstChildOfClass("Humanoid")
                local name, mhp, hpBefore, sw0, air0, k0 = m.Name, mh and mh.MaxHealth or 0, h.Health, Fi.st.swings, Fi.st.airSwings, os.clock()
                local sk0 = Fi.st.skills
                local res = Fi.kill(m, { retreatHp = 30, backHp = 75, hover = F.cfg.hover })
                if res == "killed" then kills = kills + 1 end
                if res == "died" then deaths = deaths + 1 end
                local hh = A.hum()
                log(string.format("fighttest: %s (%d hp, %d left) -> %s in %.1f s | swings %d, out of reach %d, skills %d | own hp %d -> %d",
                    name, mhp, mh and m.Parent and mh.Health or 0, res, os.clock() - k0, Fi.st.swings - sw0, Fi.st.airSwings - air0, Fi.st.skills - sk0, hpBefore, hh and hh.Health or 0))
                if res == "died" then break end
            end
        end
        Fi.hoverOff()
        local spT, wkT = (Fi.hv.sprintTicks or 0) - s0.spT, (Fi.hv.walkTicks or 0) - s0.wkT
        log(string.format("fighttest: done | kills %d, deaths %d in %.0f s | swings %d, too far %d, blocks %d, retreats %d | hover %s h%d, pulls %d, run state %d%% of hover time | server corrections %d",
            kills, deaths, os.clock() - t0, Fi.st.swings - s0.swings, Fi.st.airSwings - s0.air, Fi.st.blocks - s0.blocks, Fi.st.retreats - s0.retreats,
            tostring(F.cfg.hover), F.cfg.hoverHeight, Fi.hv.pulls - s0.pulls, (spT + wkT) > 0 and math.floor(spT / (spT + wkT) * 100) or 0, (F.corrections or 0) - s0.corr))
    end,
}

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
        elseif cmd == "goto" or cmd == "route" then
            -- goto x y z  |  route x,y,z;x,y,z;...  -> runs mode "Move test" over those points
            local list = {}
            for part in (cmd == "goto" and arg or arg:gsub(";", "|")):gmatch("[^|]+") do
                local x, y, z = part:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
                if x then list[#list + 1] = { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = "#" .. (#list + 1) } end
            end
            if #list == 0 then log(cmd .. ": no points read") return end
            F.stop()
            task.wait(0.3)
            F.moveList = list
            F.cfg.mode = "Move test"
            log(string.format("%s: %d points", cmd, #list))
            F.start()
        elseif cmd == "fight" then
            -- fight [count] [range] -> mode "Fight test" around the current spot
            -- fight [count] [range] [hover|walk]
            local n, rg = arg:match("^(%d*)%s*(%d*)")
            F.stop()
            task.wait(0.3)
            F.cfg.fightCount = tonumber(n) or 10
            F.cfg.fightRange = tonumber(rg) or 120
            if arg:find("hover") then F.cfg.hover = true elseif arg:find("walk") then F.cfg.hover = false end
            F.cfg.mode = "Fight test"
            log(string.format("fight: %d kills, range %d", F.cfg.fightCount, F.cfg.fightRange))
            F.start()
        elseif cmd == "set" then
            -- set <cfg key> <value>: numbers, true/false or text, same type as the current value only
            local k, v = arg:match("^(%S+)%s+(.+)$")
            local cur = k and F.cfg[k]
            if cur == nil then log("set: no setting " .. tostring(k)) return end
            local nv = v
            if type(cur) == "number" then nv = tonumber(v) elseif type(cur) == "boolean" then nv = (v == "true" or v == "on") end
            if nv == nil then log("set: bad value " .. v) return end
            F.cfg[k] = nv
            saveAll()
            log("set " .. k .. " = " .. tostring(nv))
        elseif cmd == "water" then
            -- water x,y,z;x,y,z...: walk ON the sea surface through these points (mode "Move test")
            local list = {}
            for part in arg:gmatch("[^;]+") do
                local x, y, z = part:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
                if x then list[#list + 1] = { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = "water #" .. (#list + 1), water = true } end
            end
            if #list == 0 then log("water: no points read") return end
            F.stop()
            task.wait(0.3)
            F.moveList = list
            F.cfg.mode = "Move test"
            F.start()
        elseif cmd == "glide" or cmd == "sea" then
            -- glide x y z: hover travel to a ground point | sea x y z: hover travel over water (mode "Move test")
            local x, y, z = arg:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
            if not x then log(cmd .. ": no point read") return end
            F.stop()
            task.wait(0.3)
            F.moveList = { { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = cmd, glide = cmd == "glide", sea = cmd == "sea" } }
            F.cfg.mode = "Move test"
            F.start()
        elseif cmd == "quest" then
            -- quest <exact quest name> | quest auto
            F.cfg.questPick = (arg == "auto") and "" or arg
            saveAll()
            log("quest pick = " .. (F.cfg.questPick == "" and "auto" or F.cfg.questPick))
        elseif cmd == "dumptalks" then
            -- dumptalks: decompile every ModuleScript under ReplicatedStorage.Modules.NPCInteractions (the NPC talk
            -- scripts with QuestInfo) into gpo2/talks/, plus index.txt with every name and path. Also lists NPC models
            -- in Workspace.NPCs with their attributes and child names (index_npcs.txt) - some quests may sit there.
            if type(decompile) ~= "function" then log("dumptalks: this executor has no decompile") return end
            local root = RS.Modules:FindFirstChild("NPCInteractions")
            if not root then log("dumptalks: NPCInteractions not found") return end
            pcall(function() if not isfolder(FOLDER .. "/talks") then makefolder(FOLDER .. "/talks") end end)
            local index, n, fails = {}, 0, 0
            for _, o in ipairs(root:GetDescendants()) do
                if o:IsA("ModuleScript") then
                    local p = o:GetFullName():gsub("^ReplicatedStorage%.Modules%.NPCInteractions%.", "")
                    local ok, src = pcall(decompile, o)
                    if ok and type(src) == "string" then
                        n = n + 1
                        pcall(writefile, FOLDER .. "/talks/" .. p:gsub("[^%w%.%-_ ]", "_") .. ".lua", "-- " .. o:GetFullName() .. "\n" .. src)
                    else fails = fails + 1 end
                    index[#index + 1] = p .. (ok and "" or "  (decompile failed)")
                    if n % 20 == 0 then task.wait() end
                end
            end
            pcall(writefile, FOLDER .. "/talks/index.txt", table.concat(index, "\n"))
            local npcs, lines = workspace:FindFirstChild("NPCs"), {}
            for _, m in ipairs(npcs and npcs:GetChildren() or {}) do
                local attrs = {}
                for k, v in pairs(m:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end
                local kids = {}
                for _, c in ipairs(m:GetChildren()) do kids[#kids + 1] = c.Name .. ":" .. c.ClassName end
                lines[#lines + 1] = m.Name .. " | attrs: " .. table.concat(attrs, ", ") .. " | children: " .. table.concat(kids, ", ")
            end
            pcall(writefile, FOLDER .. "/talks/index_npcs.txt", table.concat(lines, "\n"))
            log(string.format("dumptalks: %d modules written, %d failed, %d NPC models listed", n, fails, #lines))
        elseif cmd == "probe" then
            -- probe: run-state facts (AutoRun game setting, sprint attribute, HoldingRun, _G.running, MoveDirection)
            local c, h = A.char(), A.hum()
            local auto = A.stat("AutoRun", "Settings")
            local ic = M.input()
            local blk, cap = "?", "?"
            pcall(function()
                local gib = require(RS.Modules.Client.GameplayInputBlocker)
                blk, cap = tostring(gib.IsBlocked()), tostring(gib.IsCaptured())
            end)
            local UIS2 = game:GetService("UserInputService")
            log(string.format("probe: input blocked %s (captured %s), keys down %d, mouse down %d", blk, cap, #UIS2:GetKeysPressed(), #UIS2:GetMouseButtonsPressed()))
            log(string.format("probe: AutoRun setting %s | MovementSprintActive %s | HoldingRun %s | _G.running %s | WalkSpeed %s | MoveDirection %s | state %s",
                tostring(auto), tostring(c and c:GetAttribute("MovementSprintActive")), tostring(ic and ic.Callbacks.Run.HoldingRun),
                tostring((type(getrenv) == "function" and getrenv()._G or {}).running), tostring(h and h.WalkSpeed), tostring(h and h.MoveDirection), tostring(h and h:GetState())))
        elseif cmd == "ui" then
            -- ui on / ui off: hide the window so a screenshot shows the game
            pcall(function() win.Visible = (arg ~= "off") end)
        elseif cmd == "scan" then
            -- scan [range]: every model with a Humanoid within range, nearest first, and why it is / is not an enemy
            local rg = tonumber(arg) or 200
            local r = A.root()
            if not r then log("scan: no character") return end
            local rows = {}
            local function look(m, where)
                if not m:IsA("Model") then return end
                local h, hr = m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart")
                if not h or not hr or m == A.char() then return end
                local d = (hr.Position - r.Position).Magnitude
                if d > rg then return end
                local why = F.fight.isMob(m) and "ENEMY" or (h.Health <= 0 and "dead" or (m:FindFirstChildWhichIsA("ProximityPrompt", true) and "prompt" or (Players:GetPlayerFromCharacter(m) and "player" or "quest giver?")))
                rows[#rows + 1] = { d = d, s = string.format("%s [%s] %.0f studs, hp %d, %s", m.Name, where, d, h.Health, why) }
            end
            local npcs = workspace:FindFirstChild("NPCs")
            log("scan: workspace.NPCs " .. (npcs and (#npcs:GetChildren() .. " children") or "MISSING"))
            for _, m in ipairs(npcs and npcs:GetChildren() or {}) do look(m, "NPCs") end
            for _, m in ipairs(workspace:GetChildren()) do if m ~= npcs then look(m, "ws") end end
            table.sort(rows, function(a, b) return a.d < b.d end)
            for i = 1, math.min(#rows, 15) do log("scan: " .. rows[i].s) end
            log(string.format("scan: %d with a Humanoid within %d studs", #rows, rg))
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

-- GENERATED by tools/make_route.js from the game's own tables (QuestTracker.Recommended + NPC talk scripts).
-- f / t = level from / until, q = exact quest name, n = quest NPC, m = mob, b = boss that must be killed once, a = amount, y = quest type.
local ROUTE = {
    { f = 80, t = 325, q = "Road to Armament", n = "Ray", m = "Yeti", b = "", a = 25, y = "Defeat" },
    { f = 1, t = 3, q = "Help Daph", n = "Daph", m = "Bandit", b = "", a = 5, y = "Defeat" },
    { f = 3, t = 5, q = "Find Sarah's necklace", n = "Sarah", m = "Necklace", b = "", a = 1, y = "Find" },
    { f = 5, t = 9, q = "Help Ronny", n = "Ronny", m = "Bandit Boss", b = "", a = 1, y = "Defeat" },
    { f = 7, t = 15, q = "Deliver water to Devontai", n = "Haku", m = "Water Bucket", b = "", a = 1, y = "Deliver" },
    { f = 9, t = 15, q = "Help Noah", n = "Noah", m = "Desert Bandit", b = "", a = 7, y = "Defeat" },
    { f = 15, t = 20, q = "Take down Lucid", n = "Tyrone", m = "Lucid", b = "Lucid", a = 1, y = "Defeat" },
    { f = 20, t = 25, q = "Help Robert", n = "Robert", m = "Corrupt Marine", b = "", a = 8, y = "Defeat" },
    { f = 25, t = 29, q = "Help Kevin", n = "Kevin", m = "Shell's Bandit", b = "", a = 8, y = "Defeat" },
    { f = 29, t = 40, q = "Serve Justice", n = "Gozen", m = "Axe Hand Logan", b = "Axe Hand Logan", a = 1, y = "Defeat" },
    { f = 30, t = 40, q = "Help Zen", n = "Zen", m = "Zou Inhabitant", b = "", a = 7, y = "Defeat" },
    { f = 40, t = 50, q = "Help Rice", n = "Chef Rice", m = "Krieg Pirate", b = "", a = 8, y = "Defeat" },
    { f = 50, t = 55, q = "Help Nami", n = "Aria", m = "Star Clown", b = "Star Clown", a = 1, y = "Defeat" },
    { f = 55, t = 65, q = "Help gonny", n = "Gonny", m = "Monkey", b = "", a = 10, y = "Defeat" },
    { f = 65, t = 70, q = "Help max", n = "Max", m = "Gorilla King", b = "Gorilla King", a = 1, y = "Defeat" },
    { f = 70, t = 80, q = "Help Waby", n = "Waby", m = "Saw Shark Pirate", b = "", a = 10, y = "Defeat" },
    { f = 80, t = 105, q = "Help Vi", n = "Vi", m = "Saw Shark", b = "Saw Shark", a = 1, y = "Defeat" },
    { f = 105, t = 110, q = "Help vego", n = "Vego", m = "Sky District Bandit", b = "", a = 5, y = "Defeat" },
    { f = 110, t = 125, q = "Help zhen", n = "Zhen", m = "Castle Guard", b = "", a = 5, y = "Defeat" },
    { f = 125, t = 135, q = "Help raze", n = "Raze", m = "Sky Guardian", b = "", a = 10, y = "Defeat" },
    { f = 135, t = 140, q = "Help bibby", n = "Bibby", m = "Malcolm's Undermen", b = "", a = 6, y = "Defeat" },
    { f = 135, t = 140, q = "Help musk", n = "Musk", m = "Head Guardian", b = "Head Guardian", a = 1, y = "Defeat" },
    { f = 140, t = 155, q = "Help rae", n = "Rae", m = "Bruno", b = "Bruno", a = 1, y = "Defeat" },
    { f = 140, t = 155, q = "Help viva", n = "Viva", m = "Malcolm", b = "Malcolm", a = 1, y = "Defeat" },
    { f = 155, t = 160, q = "Help jeff", n = "Jeff", m = "Thunder God", b = "Thunder God", a = 1, y = "Defeat" },
    { f = 160, t = 180, q = "Help Miska", n = "Miska", m = "Gravito's Undermen", b = "", a = 4, y = "Defeat" },
    { f = 180, t = 190, q = "Help Yourg", n = "Yourg", m = "Gravito's Guards", b = "", a = 3, y = "Defeat" },
    { f = 190, t = 210, q = "Help Zanny", n = "Zanny", m = "Gravito", b = "Gravito", a = 1, y = "Defeat" },
    { f = 190, t = 210, q = "Help becky", n = "Becky", m = "Fishman Karate User", b = "", a = 5, y = "Defeat" },
    { f = 210, t = 230, q = "Help jenny", n = "Jenny", m = "Ryu", b = "Ryu", a = 1, y = "Defeat" },
    { f = 230, t = 240, q = "Help janny", n = "Janny", m = "Neptune", b = "Neptune", a = 1, y = "Defeat" },
    { f = 240, t = 250, q = "Help Wane", n = "Wane", m = "Marine Fort Sniper", b = "", a = 2, y = "Defeat" },
    { f = 250, t = 260, q = "Help Pichu", n = "Pichu", m = "Marine Fort Gunner", b = "", a = 4, y = "Defeat" },
    { f = 260, t = 265, q = "Help Higa", n = "Higa", m = "Marine Fort Kiribachi User", b = "", a = 1, y = "Defeat" },
    { f = 265, t = 325, q = "Help Admiral Frosty", n = "Admiral Frosty", m = "Captain Zhen", b = "Captain Zhen", a = 1, y = "Defeat" },
    { f = 265, t = 325, q = "Help Frutose", n = "Frutose", m = "Flame Admiral Zeke", b = "Flame Admiral Zeke", a = 1, y = "Defeat" },
    { f = 325, t = 330, q = "Help Zerus", n = "Zerus", m = "Crab Minion", b = "", a = 5, y = "Defeat" },
    { f = 330, t = 350, q = "Help Abdul", n = "Abdul", m = "Pharaoh Akshan", b = "Pharaoh Akshan", a = 1, y = "Awaken" },
    { f = 330, t = 350, q = "Help Samira", n = "Samira", m = "Pharaoh Akshan", b = "Pharaoh Akshan", a = 1, y = "Defeat" },
    { f = 330, t = 350, q = "Help Fhan", n = "Fhan", m = "Crab King Cho", b = "Crab King Cho", a = 1, y = "Defeat" },
    { f = 350, t = 355, q = "Help Poro", n = "Poro", m = "Zombie", b = "", a = 10, y = "Defeat" },
    { f = 350, t = 445, q = "Help Eli", n = "Eli", m = "Borj", b = "Moria", a = 1, y = "Defeat" },
    { f = 350, t = 445, q = "Help Jag", n = "Jag", m = "Ryuma", b = "Moria", a = 1, y = "Defeat" },
    { f = 355, t = 405, q = "Help Marine Scout Rae", n = "Marine Scout Rae", m = "Zombie Knight", b = "", a = 6, y = "Defeat" },
    { f = 405, t = 445, q = "Help Admiral Yon", n = "Admiral Yon", m = "Moria", b = "Moria", a = 1, y = "Defeat" },
    { f = 425, t = 445, q = "Help PJ", n = "PJ", m = "Crazy Wolf", b = "", a = 6, y = "Defeat" },
    { f = 425, t = 445, q = "Help Niki", n = "Niki", m = "Bellom", b = "Bellom", a = 1, y = "Defeat" },
    { f = 445, t = 465, q = "Help Ian", n = "Ian", m = "Donmingo Family", b = "Pica", a = 4, y = "Defeat" },
    { f = 445, t = 565, q = "Help Marine Scout Milli", n = "Marine Scout Milli", m = "Pica", b = "Pica", a = 1, y = "Defeat" },
    { f = 465, t = 485, q = "Help Warren", n = "Warren", m = "Scientist", b = "", a = 15, y = "Defeat" },
    { f = 485, t = 565, q = "Help Admiral Jackson", n = "Admiral Jackson", m = "Law", b = "Law", a = 1, y = "Defeat" },
    { f = 505, t = 565, q = "Help Somi", n = "Somi", m = "Donmingo", b = "Donmingo", a = 1, y = "Defeat" },
    { f = 540, t = 600, q = "Clear the Forest", n = "Mason", m = "Banana Chocolate Homie", b = "", a = 0, y = "" },
    { f = 600, t = 625, q = "Clear the Chess Guards", n = "Jess", m = "Chess Soldier", b = "", a = 30, y = "Defeat" },
    { f = 625, t = 635, q = "Free the Captive", n = "Gwen", m = "Juice Empress", b = "Juice Empress", a = 1, y = "Defeat" },
    { f = 635, t = 650, q = "End Big Mama", n = "Lucas", m = "Big Mama", b = "Big Mama", a = 1, y = "Defeat" },
    { f = 650, t = 675, q = "Shatter the Mirror", n = "Jerome", m = "Mochi Emperor", b = "Mochi Emperor", a = 1, y = "Defeat" },
    { f = 325, t = 675, q = "Go to the second sea", n = "Gatekeeper Puff", m = "", b = "", a = 0, y = "" },
}

-- LOCALQ: q = quest name, n = NPC, m = mob, a = amount (Defeat quests only, from the NPC talk scripts)
local LOCALQ = {
    { q = "Help Anty", n = "Anty", m = "Civilian", a = 10 },
    { q = "Help Vi", n = "Vi", m = "Saw Shark", a = 1 },
    { q = "Help Waby", n = "Waby", m = "Saw Shark Pirate", a = 10 },
    { q = "Help Rice", n = "Chef Rice", m = "Krieg Pirate", a = 8 },
    { q = "Help Nami", n = "Aria", m = "Star Clown", a = 1 },
    { q = "Help crim", n = "City Criminal", m = "Kingdom Guards", a = 6 },
    { q = "Help Dabo", n = "Dabo", m = "Mini Bunny", a = 10 },
    { q = "Help Mythra", n = "Mythra", m = "Blo The Bunny", a = 1 },
    { q = "Help Fhan", n = "Fhan", m = "Crab King Cho", a = 1 },
    { q = "Help becky", n = "Becky", m = "Fishman Karate User", a = 5 },
    { q = "Help janny", n = "Janny", m = "Neptune", a = 1 },
    { q = "Help jenny", n = "Jenny", m = "Ryu", a = 1 },
    { q = "Help Miska", n = "Miska", m = "Gravito's Undermen", a = 4 },
    { q = "Help Yourg", n = "Yourg", m = "Gravito's Guards", a = 3 },
    { q = "Help Zanny", n = "Zanny", m = "Gravito", a = 1 },
    { q = "Road to Armament", n = "Ray", m = "Yeti", a = 25 },
    { q = "Help Admiral Frosty", n = "Admiral Frosty", m = "Captain Zhen", a = 1 },
    { q = "Help Frutose", n = "Frutose", m = "Flame Admiral Zeke", a = 1 },
    { q = "Help Higa", n = "Higa", m = "Marine Fort Kiribachi User", a = 1 },
    { q = "Help Pichu", n = "Pichu", m = "Marine Fort Gunner", a = 4 },
    { q = "Help Wane", n = "Wane", m = "Marine Fort Sniper", a = 2 },
    { q = "Help Zen", n = "Zen", m = "Zou Inhabitant", a = 7 },
    { q = "Help Anty", n = "Anty", m = "Donmingo", a = 1 },
    { q = "Help Anty", n = "Anty", m = "Kraken", a = 3 },
    { q = "Help Anty", n = "Anty", m = "Pharaoh Akshan", a = 1 },
    { q = "Help Anty", n = "Anty", m = "Moria", a = 1 },
    { q = "Help Anty", n = "Anty", m = "Lucy", a = 1 },
    { q = "Help Anty", n = "Anty", m = "Hawk Eye", a = 1 },
    { q = "Help Anty", n = "Anty", m = "Radiant Admiral", a = 1 },
    { q = "Help Admiral Jackson", n = "Admiral Jackson", m = "Law", a = 1 },
    { q = "Help Ian", n = "Ian", m = "Donmingo Family", a = 4 },
    { q = "Help Marine Scout Milli", n = "Marine Scout Milli", m = "Pica", a = 1 },
    { q = "Help Niki", n = "Niki", m = "Bellom", a = 1 },
    { q = "Help PJ", n = "PJ", m = "Crazy Wolf", a = 6 },
    { q = "Help Somi", n = "Somi", m = "Donmingo", a = 1 },
    { q = "Help Warren", n = "Warren", m = "Scientist", a = 15 },
    { q = "Help Samira", n = "Samira", m = "Pharaoh Akshan", a = 1 },
    { q = "Help Noah", n = "Noah", m = "Desert Bandit", a = 7 },
    { q = "Take down Lucid", n = "Tyrone", m = "Lucid", a = 1 },
    { q = "hunt egirl", n = "Santa (HURT)", m = "Kramprus", a = 1 },
    { q = "Serve Justice", n = "Gozen", m = "Axe Hand Logan", a = 1 },
    { q = "Help Kevin", n = "Kevin", m = "Shell's Bandit", a = 8 },
    { q = "Help Robert", n = "Robert", m = "Corrupt Marine", a = 8 },
    { q = "Help bibby", n = "Bibby", m = "Malcolm's Undermen", a = 6 },
    { q = "Help jeff", n = "Jeff", m = "Thunder God", a = 1 },
    { q = "Help musk", n = "Musk", m = "Head Guardian", a = 1 },
    { q = "Help rae", n = "Rae", m = "Bruno", a = 1 },
    { q = "Help raze", n = "Raze", m = "Sky Guardian", a = 10 },
    { q = "Help vego", n = "Vego", m = "Sky District Bandit", a = 5 },
    { q = "Help viva", n = "Viva", m = "Malcolm", a = 1 },
    { q = "Help zhen", n = "Zhen", m = "Castle Guard", a = 5 },
    { q = "Help gonny", n = "Gonny", m = "Monkey", a = 10 },
    { q = "Help max", n = "Max", m = "Gorilla King", a = 1 },
    { q = "Help Daph", n = "Daph", m = "Bandit", a = 5 },
    { q = "Help Ronny", n = "Ronny", m = "Bandit Boss", a = 1 },
    { q = "Help Admiral Yon", n = "Admiral Yon", m = "Moria", a = 1 },
    { q = "Help Eli", n = "Eli", m = "Borj", a = 1 },
    { q = "Help Jag", n = "Jag", m = "Ryuma", a = 1 },
    { q = "Help Marine Scout Rae", n = "Marine Scout Rae", m = "Zombie Knight", a = 6 },
    { q = "Help Poro", n = "Poro", m = "Zombie", a = 10 },
    { q = "Help Vak", n = "Vak", m = "Civilian", a = 10 },
    { q = "Free the Captive", n = "Gwen", m = "Juice Empress", a = 1 },
    { q = "Shatter the Mirror", n = "Jerome", m = "Mochi Emperor", a = 1 },
    { q = "Clear the Chess Guards", n = "Jess", m = "Chess Soldier", a = 30 },
    { q = "End Big Mama", n = "Lucas", m = "Big Mama", a = 1 },
    { q = "Guard at the Glass", n = "Mira", m = "Biscuit Commander", a = 1 },
    { q = "The Forest Outcast", n = "Silas", m = "Pedro", a = 1 },
    { q = "Help Zaki", n = "Zaki", m = "Civilian", a = 10 },
    { q = "Help Zerus", n = "Zerus", m = "Crab Minion", a = 5 },
}
--------------------------------------------------------------------------------
-- mode Quest (level farm): pick a quest -> walk to its NPC -> take it -> beat its mobs -> repeat.
-- The game ends a Defeat quest by itself when the count is reached (CurrentQuest goes back to "None", v1 log
-- 11-20 07:22-07:29 "-QUEST COMPLETED-"), so there is no hand-in walk.
-- Quest pick: the level route step (ROUTE, v2/data/route_data.lua) when its NPC is on this island (< 1500 studs),
-- else the best Defeat quest of this island (LOCALQ) whose mob is loaded nearby.
-- v1 lesson: never wait for a mob that does not come (Zombie Knight, 05:19-06:52): no mob for 60 s -> quit the
-- quest and skip it for 5 minutes.
-- Every state change is one log line ("quest: ...").
--------------------------------------------------------------------------------
do
    -- skip list and deaths per quest survive a hub reload (v2_12 10:24: after a reload it went straight back to
    -- the quest that had just killed it twice); they reset on a new server (teleport)
    G.__gpo2_qskip = G.__gpo2_qskip or {}
    G.__gpo2_qdeaths = G.__gpo2_qdeaths or {}
    local Q = { done = 0, skip = G.__gpo2_qskip, deathsBy = G.__gpo2_qdeaths, state = "-", noMobSince = nil, questStart = nil }
    F.quest = Q
    local Fi = F.fight

    local function setState(s, why)
        if Q.state ~= s then
            Q.state = s
            log("quest: " .. s .. (why and (" - " .. why) or ""))
        end
    end

    -- NPC positions: the model in Workspace.NPCs when loaded, else the game's own quest location table
    local locs = nil
    local function npcPos(name)
        local npcs = workspace:FindFirstChild("NPCs")
        local m = npcs and npcs:FindFirstChild(name)
        if m then
            local ok, cf = pcall(function() return m:GetPivot() end)
            if ok then return cf.Position end
        end
        if locs == nil then
            locs = {}
            pcall(function()
                local t = RS.Events.Quest:InvokeServer({ "getQuestLocations" })
                if type(t) == "table" then
                    for k, v in pairs(t) do
                        if typeof(v) == "Vector3" then locs[tostring(k)] = v
                        elseif typeof(v) == "CFrame" then locs[tostring(k)] = v.Position
                        elseif type(v) == "table" and tonumber(v[1]) then locs[tostring(k)] = Vector3.new(v[1], v[2], v[3]) end
                    end
                end
            end)
            local n = 0
            for _ in pairs(locs) do n = n + 1 end
            log("quest: " .. n .. " quest NPC positions from the game")
        end
        return locs[name]
    end

    local function nameMatch(mobName, want)
        local n, w = mobName:lower(), want:lower()
        return n == w or n == w .. "s" or n .. "s" == w
    end
    -- mobs of this name loaded within range of `around`: count + nearest to us
    local function mobsOf(want, around, range)
        local npcs, r = workspace:FindFirstChild("NPCs"), A.root()
        if not npcs or not r then return 0, nil end
        local cnt, best, bd = 0, nil, math.huge
        for _, m in ipairs(npcs:GetChildren()) do
            if nameMatch(m.Name, want) and Fi.isMob(m) then
                local p = m.HumanoidRootPart.Position
                if (p - around).Magnitude <= range then
                    cnt = cnt + 1
                    local d = (p - r.Position).Magnitude
                    if d < bd then best, bd = m, d end
                end
            end
        end
        return cnt, best
    end

    local function routeStep(level)
        local plain, gate = nil, nil
        for _, s in ipairs(ROUTE) do
            if level >= s.f and level < s.t then
                if s.b == "" and s.y == "Defeat" then plain = plain or s else gate = gate or s end
            end
        end
        return plain   -- boss gates / find / deliver quests are not done by this mode yet
    end
    local function entryFor(qname)
        for _, o in ipairs(LOCALQ) do if o.q == qname then return o end end
        for _, s in ipairs(ROUTE) do if s.q == qname and s.y == "Defeat" then return { q = s.q, n = s.n, m = s.m, a = s.a } end end
        return nil
    end
    -- choose the quest to do now
    local function pick()
        local r = A.root()
        if not r then return nil end
        local cur = A.quest()
        if cur ~= "" and cur ~= "None" then
            local e = entryFor(cur)
            if e then return e, "already taken" end
        end
        -- a quest chosen by hand (remote "quest <name>" / later the Quest page) wins while its NPC is on this island
        if F.cfg.questPick ~= "" and not (Q.skip[F.cfg.questPick] and Q.skip[F.cfg.questPick] > os.clock()) then
            local e = entryFor(F.cfg.questPick)
            local p = e and npcPos(e.n)
            if p and (p - r.Position).Magnitude < 1500 then return e, "chosen" end
        end
        local s = routeStep(A.level())
        if s and not Q.skip[s.q] or (s and Q.skip[s.q] < os.clock()) then
            local p = npcPos(s.n)
            if p and (p - r.Position).Magnitude < 1500 then return { q = s.q, n = s.n, m = s.m, a = s.a }, "level route" end
        end
        -- best quest of this island: NPC known and < 1500, amount > 1 (amount 1 = a boss), mob loaded near its NPC
        local best, bs = nil, math.huge
        for _, o in ipairs(LOCALQ) do
            if o.a > 1 and not (Q.skip[o.q] and Q.skip[o.q] > os.clock()) then
                local p = npcPos(o.n)
                if p then
                    local d = (p - r.Position).Magnitude
                    if d < 1500 then
                        local cnt = mobsOf(o.m, p, 400)
                        if cnt > 0 then
                            local score = d - math.min(cnt, o.a) * 40   -- near, with many mobs up
                            if score < bs then best, bs = o, score end
                        end
                    end
                end
            end
        end
        if best then return best, "best quest on this island" end
        -- v2_12 test 10:19: after a respawn at the dock nothing near Poro was loaded (the game streams far parts
        -- out), so no quest had mobs "up" and the mode stood still. Then: the nearest quest NPC of this island
        -- (amount > 1, not skipped); its mobs load once we are there, and the 60 s no-mob rule still applies.
        local near, nd = nil, 1500
        for _, o in ipairs(LOCALQ) do
            if o.a > 1 and not (Q.skip[o.q] and Q.skip[o.q] > os.clock()) then
                local p = npcPos(o.n)
                if p and (p - r.Position).Magnitude < nd then near, nd = o, (p - r.Position).Magnitude end
            end
        end
        if near then return near, "nearest quest NPC (mobs not loaded from here)" end
        return nil
    end

    local lastQuest = ""   -- the quest seen last tick ("" after a quit, so a quit is not counted as done)
    local function takeQuest(e)
        local ok, err = pcall(function()
            local qf = require(RS.Modules.NPCInteractions.QuestFunctions)
            qf:QuestHandle(e.q, "takequest")
        end)
        task.wait(1.2)
        local cur = A.quest()
        if cur == e.q then
            Q.questStart, Q.questKills, Q.lastTaken = os.clock(), 0, e.q
            log("quest: took " .. e.q .. " from " .. e.n .. " (" .. e.m .. " x" .. e.a .. ")")
            return true
        end
        log("quest: take " .. e.q .. " failed -> now " .. tostring(cur) .. (ok and "" or (" (" .. tostring(err):sub(1, 80) .. ")")))
        return false
    end
    local function quit(why, e)
        pcall(function() RS.Events.Quest:InvokeServer({ "quit" }) end)
        if e then Q.skip[e.q] = os.clock() + 300 end
        lastQuest = ""   -- a quit is not a finished quest
        log("quest: quit " .. (e and e.q or "?") .. " - " .. why .. " (skipped 5 min)")
    end

    local function tick()
        local h, r = A.hum(), A.root()
        if not h or not r or h.Health <= 0 then setState("dead / respawning") task.wait(1) return end
        if A.level() <= 0 then setState("waiting for account data") task.wait(1) return end

        local cur, prog = A.quest()
        -- v2_12: deaths per quest (Help Marine Scout Rae 10:09-10:13: 2 deaths in 4 min on Zombie Knights at
        -- 675) -> 2 deaths on one quest = quit it and skip it 30 min
        if (F.deaths or 0) > (Q.seenDeaths or 0) then
            Q.seenDeaths = F.deaths
            local q = (cur ~= "" and cur ~= "None") and cur or Q.lastTaken
            if q then
                Q.deathsBy[q] = (Q.deathsBy[q] or 0) + 1
                log(string.format("quest: death %d on %s", Q.deathsBy[q], q))
                if Q.deathsBy[q] >= 2 then
                    Q.deathsBy[q] = 0
                    if cur == q then pcall(function() RS.Events.Quest:InvokeServer({ "quit" }) end) end
                    Q.skip[q] = os.clock() + 1800
                    lastQuest = ""   -- a quit is not a finished quest
                    log("quest: " .. q .. " killed us twice - quit and skip it 30 min")
                    return
                end
            end
        end
        -- a quest that just ended
        if lastQuest ~= "" and lastQuest ~= "None" and (cur == "" or cur == "None") then
            Q.done = Q.done + 1
            local e0 = entryFor(lastQuest)
            local dt = os.clock() - (Q.questStart or os.clock())
            local peli = tonumber(A.stat("Peli")) or 0
            log(string.format("quest: DONE %s in %.0f s (%d done this run) | Peli now %d (+%d since last)", lastQuest, dt, Q.done, peli, peli - (Q.lastPeli or peli)))
            Q.lastPeli = peli
        end
        lastQuest = cur

        -- heal between fights
        if h.Health < h.MaxHealth * 0.5 then
            setState("healing", string.format("HP %d%%", h.Health / h.MaxHealth * 100))
            local near = Fi.nearest(80)
            if near then Fi.retreat(near.HumanoidRootPart.Position, 80) else task.wait(1) end
            return
        end

        local e, why = pick()
        if not e then setState("no quest here", "no route NPC on this island and no quest mob loaded") task.wait(2) return end
        local npc = npcPos(e.n)

        if cur == "" or cur == "None" then
            if not npc then setState("NPC unknown", e.n) task.wait(2) return end
            local d = M.flat(r.Position, npc)
            if d > 9 then
                setState("to NPC " .. e.n, string.format("%s, %.0f studs (%s)", e.q, d, why))
                M.walkTo(npc, { near = 7 })
                return
            end
            setState("taking " .. e.q)
            if not takeQuest(e) then Q.skip[e.q] = os.clock() + 60 end
            return
        end
        if cur ~= e.q then
            -- a quest we do not know (taken by hand, or not a Defeat quest): drop it
            quit("not a quest this mode can do", { q = cur })
            return
        end

        -- fight the quest's mobs
        local cnt, m = mobsOf(e.m, npc or r.Position, 500)
        if not m then
            Q.noMobSince = Q.noMobSince or os.clock()
            local waited = os.clock() - Q.noMobSince
            if waited > 60 then Q.noMobSince = nil quit("no " .. e.m .. " for 60 s", e) return end
            setState("no " .. e.m .. " loaded", string.format("waiting %.0f s", waited))
            if npc and M.flat(r.Position, npc) > 60 then M.walkTo(npc, { near = 20 }) else task.wait(1) end
            return
        end
        Q.noMobSince = nil
        setState("fighting " .. e.m, string.format("%s %d/%d, %d up", e.q, prog, e.a, cnt))
        F.status = string.format("Quest %s %d/%d - %s", e.q, prog, e.a, m.Name)
        local res = Fi.kill(m, { hover = F.cfg.hover, retreatHp = 30, backHp = 75 })
        if res == "killed" then Q.questKills = (Q.questKills or 0) + 1 end
        if res == "died" then log("quest: died fighting " .. e.m) end
    end

    F.modes.Quest = {
        order = 1,
        run = function()
            Q.state, lastQuest = "-", A.quest()
            Q.seenDeaths = F.deaths or 0
            Q.questStart = os.clock()   -- a quest already running when the hub (re)started: time from now
            log("quest: start (level " .. A.level() .. ", quest now " .. lastQuest .. ")")
            while F.running and F.isAlive() do
                local ok, err = pcall(tick)
                if not ok then log("quest error: " .. tostring(err):sub(1, 160)) task.wait(1) end
                task.wait(0.1)
            end
            Fi.hoverOff()
            log(string.format("quest: stop (%d quests done)", Q.done))
        end,
    }
end
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
    pcall(function() F.fight.hoverOff() end)
    pcall(function() game:GetService("RunService"):UnbindFromRenderStep("gpo2_move") end)
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

local fightCard = UI.card(home, 2, "Fight")
UI.toggle(fightCard, "Hover over the target", cfgGet("hover"), cfgSet("hover"))
UI.stepper(fightCard, "Hover height", 3, 10, cfgGet("hoverHeight"), cfgSet("hoverHeight"))
UI.info(fightCard, "Server corrections", function() return F.corrections or 0 end)

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


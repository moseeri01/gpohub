-- moseeri gpo v2 (rewrite started 2026-11-20). Read LESSONS.md before changing anything.
-- Built by build2.ps1 from v2/base.lua + v2/kit.lua + v2/remote.lua + v2/modes/*.lua + v2/ui.lua -> gpo2.lua.
-- Lua 5.1. Every thread runs in pcall (the game's anti module reports errors of foreign scripts).
-- Files live in the executor workspace folder "gpo2" (v1 used "gpohub"; the two never share files).

if game.GameId ~= 648454481 then return end   -- Grand Piece Online only

local G = (getgenv and getgenv()) or _G

-- one hub only: each start takes a number, older copies (v1 or v2) are stopped
-- (v2_41: the water platform of the copy we replace is cloned BEFORE that copy stops, so a reload on the water has no gap)
pcall(function()
    local old = workspace:FindFirstChild("gpo2_plat")
    local stale = workspace:FindFirstChild("gpo2_plat_keep")
    if stale then stale:Destroy() end
    if old then local k = old:Clone() k.Name = "gpo2_plat_keep" k.Parent = workspace end
end)
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
local VERSION = "v2_43"
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
        hover = false, hoverHeight = 7, hoverSpeed = 15, useSkills = true, autoBlock = true, retreatHp = 30, sprint = true, hoverSkipKeys = "",
        questPick = "", fishSellEvery = 20, fishAutoSell = true, seaSpeed = 30, takeQuest = true, plat = false, fishCraft = "Common", fishAutoCraft = false, fishKeepLegendary = true, fishBait = "", stopHours = 8,
        privateCode = "", autoRejoin = true, autoStart = false, sea = "Second Sea",
        flyOver = false, ignoreStrikes = false,   -- test account only: hover over walls on a trip, keep going after a game strike
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

-- game console lines about movement (v2_20): the MovementGuard only "warn"s for some rules and its on-screen note
-- may sit in CoreGui, so its own console text is the proof of which rule fired. LogService.MessageOut is a plain
-- signal (no hook). Kept: lines with movement / guard words, at most one per second.
F.guardLines = 0
pcall(function()
    local lastAt = 0
    F.conns[#F.conns + 1] = game:GetService("LogService").MessageOut:Connect(function(msg, kind)
        if type(msg) ~= "string" then return end
        local m = msg:lower()
        if not (m:find("movement") or m:find("correct") or m:find("hover") or m:find("noclip") or m:find("displacement") or m:find("ascent") or m:find("guard") or m:find("flight") or m:find("strike")) then return end
        if m:find("gpo2") then return end
        F.guardLines = F.guardLines + 1
        if os.clock() - lastAt < 1 then return end
        lastAt = os.clock()
        log("GAME CONSOLE (" .. tostring(kind):gsub("Enum.MessageType.", "") .. "): " .. msg:sub(1, 220))
    end)
end)

-- the guard tells the player through PlayerScripts.LocalNotification (a BindableEvent, MG:1174): every text is logged
task.spawn(function()
    local ps = LP:WaitForChild("PlayerScripts", 20)
    local ln = ps and ps:WaitForChild("LocalNotification", 20)
    if not ln then log("guard watch: no LocalNotification event") return end
    F.conns[#F.conns + 1] = ln.Event:Connect(function(...)
        local t = {}
        for _, v in ipairs({ ... }) do t[#t + 1] = tostring(v) end
        F.guardNotes = (F.guardNotes or 0) + 1
        log("GAME NOTICE: " .. table.concat(t, " | "):gsub("<[^>]->", ""):sub(1, 200))
    end)
    log("guard watch: listening to LocalNotification")
end)
-- what the character carries at a pull (stun / ragdoll markers the game adds as children or attributes)
function A.pullFacts()
    local c, out = LP.Character, {}
    if not c then return "no character" end
    for _, ch in ipairs(c:GetChildren()) do
        local n = ch.Name
        if not ch:IsA("BasePart") and not ch:IsA("Accessory") and not ch:IsA("Tool") and not ch:IsA("Script") and not ch:IsA("LocalScript") and n ~= "Humanoid" and not ch:IsA("Clothing") and not ch:IsA("BodyColors") then
            out[#out + 1] = n
        end
    end
    local at = {}
    for k, v in pairs(c:GetAttributes()) do if v ~= false and v ~= 0 and v ~= "" then at[#at + 1] = k .. "=" .. tostring(v):sub(1, 12) end end
    return "children: " .. table.concat(out, ","):sub(1, 160) .. " | attrs: " .. table.concat(at, ","):sub(1, 200)
end

-- anti AFK (v2_17, changed v2_21): Roblox kicks after 20 idle minutes (Error 278). The usual VirtualUser nudge
-- (CaptureController) took the keyboard away: after the first nudge W sent through the VirtualInputManager no longer
-- moved the character (14:24-14:29, "keys down 0"). Now the nudge is a VirtualInputManager key tap (F15, bound to
-- nothing) - input sent this way already counts as activity (no Idled while farming with skill keys).
F.conns[#F.conns + 1] = LP.Idled:Connect(function()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
    end)
    F.afkNudges = (F.afkNudges or 0) + 1
    if F.afkNudges <= 3 or F.afkNudges % 20 == 0 then log("anti-afk: idle nudge " .. F.afkNudges) end
end)

-- come back after a teleport (the executor runs this line in the next server)
local function queueReload()
    if not F.cfg.reloadOnTeleport or type(queue_on_teleport) ~= "function" or G.__gpo2_queued then return end
    G.__gpo2_queued = true
    pcall(queue_on_teleport, 'loadstring(game:HttpGet("' .. REPO_RAW .. 'main/gpo2.lua?t=" .. tostring(os.time())))()')
end
queueReload()

-- rejoin (v2_17): back into the game after a disconnect. With a private server code the way in is the menu place
-- (1730877806): the code box there calls Events.reserved:InvokeServer(code) (menu script, v1 h_15).
local MENU_PLACE = 1730877806
function F.rejoin()
    log("rejoin: teleport to " .. ((F.cfg.privateCode ~= "") and "the menu (private code set)" or "this place"))
    flushLog()
    local TS = game:GetService("TeleportService")
    pcall(function() TS:Teleport((F.cfg.privateCode ~= "") and MENU_PLACE or game.PlaceId, LP) end)
end
-- Roblox error box (idle kick 278, lost connection 277 / 279): rejoin by itself when Settings allows it
pcall(function()
    F.conns[#F.conns + 1] = game:GetService("GuiService").ErrorMessageChanged:Connect(function(msg)
        if type(msg) ~= "string" or msg == "" then return end
        log("roblox error: " .. msg:sub(1, 160))
        if not F.cfg.autoRejoin or F.rejoining then return end
        if msg:lower():find("kick") or msg:lower():find("ban") or msg:lower():find("exploit") then log("rejoin: not done - looks like a kick / ban") return end
        F.rejoining = true
        task.spawn(function()
            for i = 1, 5 do task.wait(5 + i * 5) F.rejoin() end
        end)
    end)
end)
if game.PlaceId == MENU_PLACE then
    -- the game menu (v2_18, steps seen in game 2026-11-20 12:32-12:35): "Press any key" -> Start.Menu ->
    --   with a code: Private Servers button -> ServerCodeBox (text + Enter) -> chooseType "Regular" -> "Second Sea"
    --   without:     Play button ("Set Sail") -> the sea prompt when it shows
    -- Buttons are pressed with the executor s firesignal on the button s own click signal.
    task.spawn(function()
        local PG = LP:WaitForChild("PlayerGui", 30)
        local function at(path)
            local o = PG
            for part in path:gmatch("[^%.]+") do o = o and o:FindFirstChild(part) end
            return o
        end
        local function press(path)
            local o = at(path)
            if not o or type(firesignal) ~= "function" then log("menu: cannot press " .. path) return false end
            for _, sig in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }) do pcall(firesignal, o[sig]) end
            log("menu: pressed " .. path)
            return true
        end
        task.wait(8)
        local VIM = game:GetService("VirtualInputManager")
        for _ = 1, 5 do
            local menu = at("Start.Menu")
            if menu and menu.Visible then break end
            pcall(function()
                local v = workspace.CurrentCamera.ViewportSize
                VIM:SendMouseButtonEvent(v.X * 0.5, v.Y * 0.85, 0, true, game, 0) task.wait(0.1)
                VIM:SendMouseButtonEvent(v.X * 0.5, v.Y * 0.85, 0, false, game, 0) task.wait(0.3)
                VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game) task.wait(0.1)
                VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
            task.wait(3)
        end
        local sea = F.cfg.sea
        if F.cfg.privateCode ~= "" then
            press("Start.Menu.Main.List.PrivateServersButton")
            task.wait(2.5)
            local box = at("PrivateServers.PrivateServersPanel.ServerCodeBox.TextBox")
            if box then
                box:CaptureFocus() box.Text = F.cfg.privateCode box:ReleaseFocus(true)
                log("menu: private code typed")
            else log("menu: code box not found") end
            task.wait(2.5)
            press("chooseType.Frame.Options.Regular")
        else
            press("Start.Menu.Main.PlayButton")
        end
        for _ = 1, 6 do
            task.wait(2.5)
            if at("ConfirmationPrompt.Main.OptionsFrame." .. sea) then press("ConfirmationPrompt.Main.OptionsFrame." .. sea) break end
        end
        flushLog()
    end)
elseif F.cfg.autoStart then
    -- Start again by itself after a (re)join (set by "set autoStart true")
    task.delay(12, function()
        if F.isAlive() and not F.running and F.cfg.mode ~= "Move test" and F.start then log("autostart: " .. F.cfg.mode) F.start() end
    end)
end

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
    label(c, title, 15, T.accent, Enum.Font.GothamMedium, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 0 })
    return { frame = c, n = 0 }
end
local function row(card, text, h)
    card.n = card.n + 1
    local r = new("Frame", { Size = UDim2.new(1, 0, 0, h or 38), BackgroundTransparency = 1, LayoutOrder = card.n }, card.frame)
    if card.n > 1 then new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line, BorderSizePixel = 0 }, r) end
    label(r, text, 14, T.text, Enum.Font.Gotham, { Size = UDim2.new(0.62, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
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
-- dropdown: label on the left, the picked item on the right; a click opens the list under the row, a pick closes it
function UI.dropdown(card, text, height, getItems, getKey, onPick)
    local r = row(card, text)
    local b = new("TextButton", { AutoButtonColor = false, BackgroundColor3 = T.off, BorderSizePixel = 0, Size = UDim2.new(0.78, 0, 0, 28), Position = UDim2.new(0.22, 0, 0.5, -14),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.white, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" }, r)
    corner(b, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 24) }, b)
    local arrow = label(b, "v", 12, T.mute, Enum.Font.GothamBold, { Size = UDim2.fromOffset(14, 28), Position = UDim2.new(1, 6, 0, 0) })
    card.n = card.n + 1
    local sf = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = card.n, Visible = false,
        ScrollBarThickness = 4, ScrollBarImageColor3 = T.faint, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y }, card.frame)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
    local rows, sig = {}, ""
    local paint
    local function setOpen(on)
        sf.Visible = on
        arrow.Text = on and "^" or "v"
        if UI.current then UI.show(UI.current) end      -- the window height follows
    end
    paint = function()
        local items = getItems()
        local cur = getKey()
        local s = {}
        -- (v2_39) an item may be a group header ({ header = true, text = }) or carry sub (a second small line),
        -- right (text at the right edge), dim (greyed) and short (the text shown in the closed row)
        for i, it in ipairs(items) do s[i] = it.text .. "~" .. tostring(it.sub) .. "~" .. tostring(it.right) .. "~" .. tostring(it.dim) end
        s = table.concat(s, "|")
        if s ~= sig then
            sig = s
            for _, x in ipairs(rows) do x.btn:Destroy() end
            rows = {}
            for i, it in ipairs(items) do
                if it.header then
                    local hd = label(sf, it.text, 11, T.mute, Enum.Font.GothamBold, { Size = UDim2.new(1, -8, 0, 22), LayoutOrder = i })
                    new("UIPadding", { PaddingLeft = UDim.new(0, 4) }, hd)
                    rows[#rows + 1] = { btn = hd }
                else
                    local x = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = T.off, BorderSizePixel = 0,
                        Size = UDim2.new(1, -8, 0, it.sub and 42 or 26), LayoutOrder = i }, sf)
                    corner(x, 5)
                    local main = label(x, it.text, 13, it.dim and T.mute or T.text, Enum.Font.GothamMedium, { Size = UDim2.new(1, -20, 0, 20),
                        Position = UDim2.new(0, 10, 0, 3), TextTruncate = Enum.TextTruncate.AtEnd })
                    local sub, right = nil, nil
                    if it.sub then
                        sub = label(x, it.sub, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(0.6, -10, 0, 16), Position = UDim2.new(0, 10, 0, 22),
                            TextTruncate = Enum.TextTruncate.AtEnd })
                    end
                    if it.right then
                        right = label(x, it.right, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(0.4, -10, 0, 16), Position = UDim2.new(0.6, 0, 0, it.sub and 22 or 5),
                            TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
                    end
                    x.MouseButton1Click:Connect(function() pcall(onPick, it.key) setOpen(false) paint() end)
                    rows[#rows + 1] = { btn = x, key = it.key, main = main, sub = sub, right = right, dim = it.dim }
                end
            end
        end
        local shown = "-"
        for _, it in ipairs(items) do if not it.header and it.key == cur then shown = it.short or it.text end end
        b.Text = shown
        for _, x in ipairs(rows) do
            if x.main then
                local on = x.key == cur
                x.btn.BackgroundColor3 = on and T.accent or T.off
                x.main.TextColor3 = on and T.onAccent or (x.dim and T.mute or T.text)
                if x.sub then x.sub.TextColor3 = on and T.onAccent or T.mute end
                if x.right then x.right.TextColor3 = on and T.onAccent or T.mute end
            end
        end
    end
    UI.dropdowns = UI.dropdowns or {}
    UI.dropdowns[text] = setOpen      -- (remote: open <label>, for screenshots)
    b.MouseButton1Click:Connect(function() setOpen(not sf.Visible) end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end
-- list: a scrolling column of rows to click; the picked row is lit. getItems() -> { { key = , text = }, ... }
function UI.list(card, height, getItems, getKey, onPick)
    card.n = card.n + 1
    local sf = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = card.n,
        ScrollBarThickness = 4, ScrollBarImageColor3 = T.faint, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y }, card.frame)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
    local rows, sig = {}, ""
    local function paint()
        local items = getItems()
        local s = {}
        for i, it in ipairs(items) do s[i] = it.text end
        s = table.concat(s, "|")
        if s ~= sig then
            sig = s
            for _, b in ipairs(rows) do b:Destroy() end
            rows = {}
            for i, it in ipairs(items) do
                local b = new("TextButton", { AutoButtonColor = false, Text = "  " .. it.text, TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = T.text,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, BackgroundColor3 = T.off, BorderSizePixel = 0,
                    Size = UDim2.new(1, -8, 0, 26), LayoutOrder = i }, sf)
                corner(b, 5)
                b:SetAttribute("key", it.key)
                b.MouseButton1Click:Connect(function() pcall(onPick, it.key) paint() end)
                rows[i] = b
            end
        end
        local cur = getKey()
        for _, b in ipairs(rows) do
            local on = b:GetAttribute("key") == cur
            b.BackgroundColor3 = on and T.accent or T.off
            b.TextColor3 = on and T.onAccent or T.text
            b.Font = on and Enum.Font.GothamMedium or Enum.Font.Gotham
        end
    end
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end
-- slider: a bar to drag (or click), the value on the right
function UI.slider(card, text, lo, hi, get, setv, unit)
    local r = row(card, text)
    local val = label(r, "", 12, T.value, Enum.Font.GothamMedium, { Size = UDim2.fromOffset(58, 20), Position = UDim2.new(1, -58, 0.5, -10), TextXAlignment = Enum.TextXAlignment.Right })
    local track = new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(120, 8), Position = UDim2.new(1, -186, 0.5, -4), BackgroundColor3 = T.off, BorderSizePixel = 0 }, r)
    corner(track, 4)
    local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, track)
    corner(fill, 4)
    local knob = new("Frame", { Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = T.white, BorderSizePixel = 0 }, track)
    corner(knob, 7)
    local function paint()
        local v = tonumber(get()) or lo
        local f = math.clamp((v - lo) / (hi - lo), 0, 1)
        fill.Size = UDim2.new(f, 0, 1, 0)
        knob.Position = UDim2.new(f, 0, 0.5, 0)
        val.Text = tostring(v) .. (unit or "")
    end
    local dragging = false
    local function at(x)
        local f = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        pcall(setv, math.floor(lo + f * (hi - lo) + 0.5))
        paint()
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true at(input.Position.X) end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then at(input.Position.X) end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
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
    local v = label(r, "", 14, T.white, Enum.Font.GothamMedium, { Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0.4, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
    UI.refreshers[#UI.refreshers + 1] = function() local ok, s = pcall(getText) v.Text = ok and tostring(s) or "-" end
end
function UI.note(card, text)
    card.n = card.n + 1
    -- (v2_19: AutomaticSize did not grow a wrapped label - notes were cut after one line; the height is measured)
    local w = (WIN_W - 36) / 2 - 6 - 28
    local h = 16
    pcall(function()
        h = game:GetService("TextService"):GetTextSize(text, 12, Enum.Font.Gotham, Vector2.new(w, 1000)).Y + 6
    end)
    label(card.frame, text, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, h),
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

    -- sprint by key for other travel code (water walk): hold W, steer with the camera toward M.sprintTarget
    local SK = { on = false }
    function M.sprintOn()
        if SK.on or not (F.cfg.sprint and VIM) then return SK.on end
        local cam = workspace.CurrentCamera
        SK.on, SK.oldType = true, cam.CameraType
        SK.conn = RunService.RenderStepped:Connect(function()
            local rr = A.root()
            local tg = M.sprintTarget
            if not (rr and tg) then return end
            local d = Vector3.new(tg.X - rr.Position.X, 0, tg.Z - rr.Position.Z)
            if d.Magnitude < 0.5 then return end
            d = d.Unit
            cam.CFrame = CFrame.lookAt(rr.Position - d * 14 + Vector3.new(0, 7, 0), rr.Position + d * 6)
        end)
        pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
        pcall(function()
            VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game) task.wait(0.06)
            VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game) task.wait(0.08)
            VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        end)
        return true
    end
    function M.sprintOff()
        if not SK.on then return end
        SK.on = false
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game) end)
        if SK.conn then SK.conn:Disconnect() SK.conn = nil end
        pcall(function() workspace.CurrentCamera.CameraType = SK.oldType or Enum.CameraType.Custom end)
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
        local lastP, lastT = r.Position, os.clock()
        local hb = RunService.Heartbeat:Connect(function()
            local rr = A.root()
            if not rr then return end
            local p = rr.Position
            local d = (p - lastP).Magnitude
            local cc = A.char()
            if d > 8 and cc and (cc:GetAttribute("SpeedBypass") or cc:GetAttribute("FlyBypass")) then
                -- the game moved us itself (own skill lunge, see fight.lua v2_20): not a pull-back
            elseif d > 8 then
                st.pulls = st.pulls + 1
                if d > st.maxPull then st.maxPull = d end
                if st.pulls <= 3 then
                    local hh = A.hum()
                    log("walk pull facts: " .. A.pullFacts())
                    log(string.format("move: PULLED %.0f studs (%.0f,%.0f,%.0f -> %.0f,%.0f,%.0f) | frame %.3f s | walk for %.1f s | floor %s | state %s",
                        d, lastP.X, lastP.Y, lastP.Z, p.X, p.Y, p.Z, os.clock() - lastT, os.clock() - t0, hh and hh.FloorMaterial.Name or "?", hh and tostring(hh:GetState()):gsub("Enum.HumanoidStateType.", "") or "?"))
                end
            end
            lastP = p
            lastT = os.clock()
        end)

        noSit(true)
        local ok, why = false, "?"
        -- sprint (v2_20): the game only runs while W is really held (Run:PC_Activate alone leaves 16; v1 "key walk").
        -- So long walks hold W through the VirtualInputManager and steer by pointing the camera at the next path
        -- point (the character runs camera-forward). The guard allows 25 studs/s while MovementSprintActive is on.
        -- Key mode ends for this walk the first time it gets stuck (then Humanoid:MoveTo with sidestep / hop),
        -- and near the goal (MoveTo is more exact).
        local key = { on = false, dead = not (F.cfg.sprint and VIM and dist0 > 40), steer = nil }
        local cam = workspace.CurrentCamera
        local function keyOff()
            if not key.on then return end
            key.on = false
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game) end)
            if key.conn then key.conn:Disconnect() key.conn = nil end
            pcall(function() cam.CameraType = key.oldType or Enum.CameraType.Custom end)
        end
        local function keyOn()
            if key.on or key.dead then return end
            key.on, key.oldType = true, cam.CameraType
            key.conn = RunService.RenderStepped:Connect(function()
                local rr = A.root()
                if not (rr and key.steer) then return end
                local d = Vector3.new(key.steer.X - rr.Position.X, 0, key.steer.Z - rr.Position.Z)
                if d.Magnitude < 0.5 then return end
                d = d.Unit
                cam.CFrame = CFrame.lookAt(rr.Position - d * 14 + Vector3.new(0, 7, 0), rr.Position + d * 6)
            end)
            pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
            pcall(function()
                VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game) task.wait(0.06)
                VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game) task.wait(0.08)
                VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
            end)
        end
        local sprintTicks, allTicks = 0, 0
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
                        allTicks = allTicks + 1
                        local cc = A.char()
                        if cc and cc:GetAttribute("MovementSprintActive") == true then sprintTicks = sprintTicks + 1 end
                        if not key.dead and flat(r.Position, pos) < 14 then key.dead = true keyOff() end
                        if not key.dead then key.steer = target keyOn() else h:MoveTo(target) end
                        task.wait(0.25)
                        if flat(r.Position, last) < 0.5 then
                            stuck = stuck + 1
                            stuckTotal = stuckTotal + 1
                            if stuck == 2 or stuck == 5 then if M.jump() then st.jumps = st.jumps + 1 end
                            elseif stuck == 3 or stuck == 6 then key.dead = true keyOff() st.sides = st.sides + 1 M.sidestep(target, st.sides)
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
        keyOff()
        hb:Disconnect()
        noSit(false)

        r = A.root()
        local dt = os.clock() - t0
        local moved = r and flat(r.Position, start) or 0
        local left = r and flat(r.Position, pos) or -1
        log(string.format("move: %s | %.0f -> %.0f studs left in %.1f s (%.1f studs/s) | jumps %d, sidesteps %d, hops %d, new paths %d | pulled back %d (max %.0f) | sprint %d%%",
            why, dist0, left, dt, moved / math.max(dt, 0.1), st.jumps, st.sides, st.hops, st.repaths, st.pulls, st.maxPull, allTicks > 0 and math.floor(sprintTicks / allTicks * 100) or 0))
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
            if p.nav then
                ok, why = F.nav.go(p.pos, { near = 10 })
                if ok and p.save then F.nav.saveRoute(p.save) end
            elseif p.navroute then
                ok, why = F.nav.followRoute(p.navroute)
            elseif p.gate then
                local g = F.fight.findGate("Thriller Bark", 90)
                ok, why = g ~= nil, g and string.format("opening near %d,%d", g.X, g.Z) or "no opening found"
            elseif p.travel then ok, why = F.fight.travel(p.pos, { near = 10 })
            elseif p.water then ok, why = F.fight.waterWalk(p.pos, { near = 8 })
            elseif p.plat then ok, why = F.fight.platWalk(p.pos, { near = p.near or 6, home = p.home, limit = p.limit })
            elseif p.seahold then
                local at = F.fight.seaHold(p.pos, p.home, 90)
                ok, why = true, at and string.format("first strike after %.1f s", at) or "no strike in 90 s"
            elseif p.sea then ok, why = F.fight.seaGlide(p.pos, { near = p.near or 8, keep = p.keep, limit = p.limit })
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
    -- v2_23 (owner 17:10: "it does not stay floating, it still comes down"): some Magu skills move the user (a
    -- lunge that ends on the ground). Each key is measured: how far it moved us, how far down, whether we
    -- touched the ground, the damage it did. Keys named in cfg.hoverSkipKeys are not used while floating.
    Fi.keyStats = {}
    function Fi.skill(pos, targetHum, floating)
        if not VIM or os.clock() - lastSkill < 1.5 then return false end
        local key
        for _ = 1, #SKILL_KEYS do
            skillN = skillN % #SKILL_KEYS + 1
            local k = SKILL_KEYS[skillN]
            if not (floating and F.cfg.hoverSkipKeys:find(k.Name, 1, true)) then key = k break end
        end
        if not key then return false end
        lastSkill = os.clock()
        pcall(function()
            local cam = workspace.CurrentCamera
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
            VIM:SendMouseMoveEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, game)
        end)
        Fi.st.skills = Fi.st.skills + 1
        local r0 = A.root()
        local p0, hp0 = r0 and r0.Position, targetHum and targetHum.Health or 0
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.6)
        VIM:SendKeyEvent(false, key, false, game)
        -- measure for 1.2 s in its own thread
        task.spawn(function()
            local move, down, ground = 0, 0, false
            for _ = 1, 12 do
                task.wait(0.1)
                local r, h = A.root(), A.hum()
                if r and p0 then
                    move = math.max(move, M.flat(r.Position, p0))
                    down = math.max(down, p0.Y - r.Position.Y)
                end
                if h and h.FloorMaterial ~= Enum.Material.Air then ground = true end
            end
            local ks = Fi.keyStats[key.Name] or { n = 0, move = 0, down = 0, ground = 0, dmg = 0 }
            Fi.keyStats[key.Name] = ks
            ks.n = ks.n + 1
            ks.move, ks.down = ks.move + move, ks.down + down
            if ground and floating then ks.ground = ks.ground + 1 end
            if targetHum then ks.dmg = ks.dmg + math.max(0, hp0 - targetHum.Health) end
        end)
        task.wait(0.3)
        return true
    end
    function Fi.keyReport()
        local out = {}
        for _, k in ipairs(SKILL_KEYS) do
            local ks = Fi.keyStats[k.Name]
            if ks and ks.n > 0 then
                out[#out + 1] = string.format("%s x%d: moved %.0f, down %.0f, on ground %d%%, dmg %.0f", k.Name, ks.n, ks.move / ks.n, ks.down / ks.n, ks.ground / ks.n * 100, ks.dmg / ks.n)
            end
        end
        return table.concat(out, " | ")
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
        if Fi.platOn then Fi.platOn() Fi.plat.goal = nil end      -- (v2_38: the local platform is the safety net under the glide)
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
            if F.strikes > strikes0 and not F.cfg.ignoreStrikes then why = "game flight strike - stopped" break end
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
        -- (v2_38: a route point in the middle of the sea - the hover stays on for the next leg)
        if ok and opts.keep then
            log(string.format("sea: passed a route point after %.0f s, %.0f studs", os.clock() - t0, dist0))
            return ok, why
        end
        -- (v2_41: come down first - 20:00 the glide was switched off 470 studs up and the character fell into the sea)
        r = A.root()
        if r and A.hum() and A.hum().Health > 0 and A.char() == char0 and HV.seaFloor and r.Position.Y - HV.seaFloor > 14 then
            local here, td = r.Position, os.clock()
            log(string.format("sea: %.0f studs above the floor at the end - coming down before the hover goes off", r.Position.Y - HV.seaFloor))
            HV.sea = true
            while F.isAlive() and A.char() == char0 and os.clock() - td < 40 do
                r = A.root()
                if not r or r.Position.Y - (HV.seaFloor or r.Position.Y) < 11 then break end
                Fi.hoverOn(Vector3.new(here.X, 0, here.Z))
                task.wait(0.2)
            end
        end
        -- (v2_37: never switch the hover off over open water unless the game's Logia mode holds us - 19:07 the demo
        -- ended beside the pier and the character drowned.) No ground within 15 studs below = fly back to the start.
        r = A.root()
        if r and A.hum() and A.hum().Health > 0 and A.char() == char0 and Fi.logiaOn() ~= true and not (Fi.plat and Fi.plat.on) then
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("Effects") }
            rp.IgnoreWater = true
            if not workspace:Raycast(r.Position, Vector3.new(0, -15, 0), rp) then
                log(string.format("sea: no ground under the end point (%s) - flying back to the start", why))
                local tb = os.clock()
                HV.sea = true
                while F.isAlive() and A.char() == char0 and os.clock() - tb < 60 do
                    r = A.root()
                    if not r or M.flat(r.Position, start) < 4 then break end
                    Fi.hoverOn(start)
                    task.wait(0.2)
                end
                ok, why = false, why .. " - no ground there, came back"
            end
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
    -- sea hold (v2_38, owner 19:14 "measure it"): hover at one point over the water until the game's first flight
    -- strike (or maxSec), then fly straight back to `home` (a point over ground). Returns seconds to the first strike or nil.
    function Fi.seaHold(pos, home, maxSec)
        local s0, t0, firstAt = F.strikes, os.clock(), nil
        local g0, c0 = F.guardNotes or 0, F.corrections or 0
        local lastLog = os.clock()
        while F.running and F.isAlive() and os.clock() - t0 < maxSec do
            local r, h = A.root(), A.hum()
            if not r or not h or h.Health <= 0 then break end
            if F.strikes > s0 then firstAt = os.clock() - t0 break end
            if os.clock() - lastLog > 10 then
                lastLog = os.clock()
                log(string.format("seahold: %.0f s over the water | y %.0f (floor %.0f) | strikes 0 | notices %d | corrections %d | hp %d",
                    os.clock() - t0, r.Position.Y, HV.seaFloor or 0, (F.guardNotes or 0) - g0, (F.corrections or 0) - c0, h.Health))
            end
            HV.sea = true
            Fi.hoverOn(pos)
            task.wait(0.2)
        end
        log(firstAt and string.format("seahold: FIRST STRIKE after %.1f s - flying back", firstAt) or string.format("seahold: no strike in %.0f s - flying back", os.clock() - t0))
        local tb = os.clock()
        while F.isAlive() and os.clock() - tb < 40 do
            local r = A.root()
            if not r or M.flat(r.Position, home) < 4 then break end
            HV.sea = true
            Fi.hoverOn(home)
            task.wait(0.2)
        end
        HV.sea, HV.seaTarget = false, nil
        Fi.hoverOff()
        log(string.format("seahold: back at %s after %.1f s | strikes in total %d", A.posText(), os.clock() - tb, F.strikes - s0))
        return firstAt
    end
    -- water walk (v2_14, owner 11-20): cross the sea ON the surface like a Magu player - plain Humanoid:MoveTo,
    -- no AlignPosition, no hover. The game's own WaterLogia script holds a logia user on the water.
    -- Stops at once on: a game strike notice, sinking / swimming, HP loss over 15 %, no progress for 15 s.
    -- (v2_36, 19:01: the owner pressed Go with the game's Logia mode switched OFF - the character sank and drowned.)
    -- The game's own setting (the Logia button above the hotbar) = ReplicatedStorage.Stats<name>.Settings.Logia.
    -- nil = could not read it.
    function Fi.logiaOn()
        local v = nil
        pcall(function() v = RS["Stats" .. LP.Name].Settings.Logia.Value end)
        return v
    end
    function Fi.waterWalk(pos, opts)
        opts = opts or {}
        local r, h = A.root(), A.hum()
        if not r or not h then return false, "no character" end
        if Fi.logiaOn() == false and not opts.plat then
            log("water: Logia mode is OFF (button above the hotbar) - not stepping on the water")
            return false, "Logia mode is OFF - switch it on with the Logia button"
        end
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
        local hpWater = nil
        local keyDead, keyCheck = false, nil
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
            if F.strikes > strikes0 and not F.cfg.ignoreStrikes and not opts.noStop then why = "GAME STRIKE - stopped" break end
            if h:GetState() == Enum.HumanoidStateType.Swimming then why = "swimming (not held on the water)" break end
            if p.Y < sea - 6 then why = string.format("sinking (y %.0f, sea %.0f)", p.Y, sea) break end
            -- (HP loss only matters on the water = the fruit does not hold us; on land mobs hit us at the start, 14:00)
            if math.abs(p.Y - sea) < (opts.plat and 16 or 6) and not opts.noStop then
                if h.Health < (hpWater or h.Health) - h.MaxHealth * (opts.plat and 0.1 or 0.15) then why = string.format("losing HP on the water (%d -> %d)", hpWater, h.Health) break end
                hpWater = hpWater or h.Health
            else hpWater = nil end
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
            -- v2_20: run on the water too (W held, camera steering) while far from the goal
            -- (if the held key does not move us - keyboard taken away, 14:29 - plain MoveTo for the rest of this walk)
            if not keyDead and keyCheck and os.clock() - keyCheck.t > 1.5 then
                if M.flat(p, keyCheck.p) < 3 then keyDead = true M.sprintOff() log("water: W key gives no movement - walking with MoveTo") end
                keyCheck = { t = os.clock(), p = p }
            end
            keyCheck = keyCheck or { t = os.clock(), p = p }
            if left > 40 and not keyDead then
                M.sprintTarget = pos
                if not M.sprintOn() then h:MoveTo(p + d.Unit * math.min(left, 30)) end
            else
                M.sprintOff()
                h:MoveTo(p + d.Unit * math.min(left, 30))
            end
            task.wait(0.25)
        end
        M.sprintOff()
        pcall(function() local rr = A.root() if rr then A.hum():MoveTo(rr.Position) end end)
        r = A.root()
        local dt = os.clock() - t0
        local moved = r and M.flat(r.Position, start) or 0
        log(string.format("water: %s | %.0f of %.0f studs in %.0f s (%.1f studs/s) | on water %.0f s | lowest y %.1f | hp %d -> %d | pulls %d | strikes %d",
            why, moved, dist0, dt, moved / math.max(dt, 0.1), onWater * 0.25, lowest, hp0, A.hum() and A.hum().Health or 0, pulls, F.strikes - strikes0))
        return ok, why
    end
    -- platform walk (v2_38, owner 19:25: "what if it is done like walking?"): a part that exists only on this client
    -- sits under the feet a little above the sea and follows the character, so the Humanoid walks / runs on it like
    -- on ground (the game's own run state, 22 studs/s). No hover, no game remote. Over real ground the part does not
    -- collide. Near a goal that lies higher (a pier, a shore) the part rises under the feet up to that height.
    -- The part is never taken away over water, so a stop in mid sea does not drop the character.
    local PL = { on = false, lift = 0 }
    Fi.plat = PL
    function Fi.platOn()
        if HV.ocean == nil then
            HV.ocean = false
            pcall(function()
                local om = require(RS.Modules.OceanModule)
                if type(om.HeightLookup) == "function" then
                    HV.ocean = function(x, z) local ok, y = pcall(om.HeightLookup, x, z) return ok and tonumber(y) or 0 end
                end
            end)
        end
        if PL.on and PL.part and PL.part.Parent then return end
        local keep = workspace:FindFirstChild("gpo2_plat_keep")      -- handed over by base.lua at a reload
        local part = keep or Instance.new("Part")
        part.Name = "gpo2_plat"
        part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
        part.Size = Vector3.new(30, 14, 30)      -- (v2_41: 14 thick - at 20:01 a fall from y 470 went straight through the 1-stud part and the character drowned)
        part.Transparency = 0.75
        part.Material = Enum.Material.SmoothPlastic
        part.Parent = workspace
        PL.part, PL.on, PL.lift, PL.over = part, true, 0, "?"
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.IgnoreWater = true
        PL.conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
            if not F.isAlive() or not part.Parent then
                if PL.conn then PL.conn:Disconnect() end
                pcall(function() part:Destroy() end)
                PL.on = false
                return
            end
            local r = A.root()
            if not r then return end
            local p = r.Position
            local sea = HV.ocean and HV.ocean(p.X, p.Z) or 0
            local H = F.cfg.platHeight or 5
            local g = PL.goal
            local want = 0
            if g and M.flat(p, g) < 45 and g.Y - 2.7 > sea + H then want = g.Y - 2.7 - (sea + H) end
            if PL.lift < want then PL.lift = math.min(want, PL.lift + dt * 6) elseif PL.lift > want then PL.lift = math.max(want, PL.lift - dt * 6) end
            local top = sea + H + PL.lift
            rp.FilterDescendantsInstances = { A.char(), part, workspace:FindFirstChild("Effects") }
            local hit = workspace:Raycast(Vector3.new(p.X, p.Y + 2, p.Z), Vector3.new(0, -60, 0), rp)
            local land = hit and hit.Position.Y > top - 1.2
            PL.over = land and "land" or "water"
            part.CanCollide = not land
            part.CFrame = CFrame.new(p.X, top - 7, p.Z)
        end)
        log("plat: on (a local part under the feet, " .. (F.cfg.platHeight or 5) .. " studs above the sea)")
    end
    -- off: only over real ground or with the game's Logia mode on (anything else = the character sinks)
    function Fi.platOff(force)
        if not PL.on then return true end
        -- (v2_43: no Logia exception - 20:17 the owner switched it off over water with Logia mode reading ON and sank)
        if not force and PL.over ~= "land" then return false, "over water - go on land first" end
        if PL.conn then PL.conn:Disconnect() PL.conn = nil end
        pcall(function() PL.part:Destroy() end)
        PL.on, PL.part = false, nil
        log("plat: off")
        return true
    end
    -- a reload on the water, or the switch was left on: the platform is back at once
    if workspace:FindFirstChild("gpo2_plat_keep") or F.cfg.plat then pcall(Fi.platOn) end
    -- walk on the platform to pos; on HP loss / a game strike walk back to opts.home (a point on land)
    function Fi.platWalk(pos, opts)
        opts = opts or {}
        Fi.platOn()
        PL.goal = pos
        local ok, why = Fi.waterWalk(pos, { near = opts.near or 6, limit = opts.limit, plat = true })
        if not ok and opts.home and (why:find("HP") or why:find("STRIKE")) then
            log("plat: " .. why .. " - walking back to the start")
            PL.goal = opts.home
            local okB, whyB = Fi.waterWalk(opts.home, { near = 6, plat = true, noStop = true })
            why = why .. " - walked back (" .. tostring(whyB) .. ")"
        end
        return ok, why
    end
    -- travel to a far point, across the sea if needed: water walk straight at it; when blocked (a shore, a cliff,
    -- an island in the way) try the land path walk; if that does not get closer, go around: water walk to a point
    -- 350 studs sideways (left, then right, wider each time) and on again. Returns ok, why.
    function Fi.travel(pos, opts)
        opts = opts or {}
        local t0 = os.clock()
        local r = A.root()
        if not r then return false, "no character" end
        local dist0 = M.flat(r.Position, pos)
        local detours, why = 0, "?"
        local badAng = {}
        log(string.format("travel: start, %.0f studs to %d,%d,%d", dist0, pos.X, pos.Y, pos.Z))
        while F.running and F.isAlive() do
            local ok, w = Fi.waterWalk(pos, { near = opts.near or 10, limit = 3600 })
            if ok then why = "arrived" break end
            why = w
            if not w:find("blocked") then break end
            r = A.root()
            if not r then why = "no character" break end
            local before = M.flat(r.Position, pos)
            -- v2_16 (owner 11-20: test account, strikes accepted): fly over what blocks - hover up and over,
            -- 500 studs along the line, then back down onto the water. Off unless cfg.flyOver.
            if F.cfg.flyOver and before > 1200 then
                local d = Vector3.new(pos.X - r.Position.X, 0, pos.Z - r.Position.Z).Unit
                local s0 = F.strikes
                local okF, wF = Fi.seaGlide(r.Position + d * 500, { near = 30, limit = 240 })
                local r2 = A.root()
                log(string.format("travel: fly-over %s, %.0f -> %.0f left, strikes +%d", tostring(wF), before, r2 and M.flat(r2.Position, pos) or -1, F.strikes - s0))
                task.wait(2)   -- drop onto the water (when it got closer, the check below goes on without a detour)
            end
            -- the land path walk only near the goal (a path search over thousands of studs finds nothing and the
            -- straight walk just pushed the cliff for 20 s)
            local okL, wL = false, "skipped (far)"
            if before < 1200 then okL, wL = M.walkTo(pos, { near = opts.near or 10 }) end
            if okL then why = "arrived" break end
            r = A.root()
            if not r or not F.running then why = "stopped" break end
            local after = M.flat(r.Position, pos)
            log(string.format("travel: land walk %s, %.0f -> %.0f left", tostring(wL), before, after))
            if after < before - 40 then
                -- the land walk got closer: keep going from here
            else
                detours = detours + 1
                if detours > 40 then why = "no way found after 40 detours" break end
                -- v2_15 trip 11:21: left / right in turn walked back and forth along a cliff. Now: rays over the
                -- water in steps of 30 degrees away from the goal line; take the first open one (300 studs free),
                -- trying the side used last time first, so it follows the shore one way round.
                local d = Vector3.new(pos.X - r.Position.X, 0, pos.Z - r.Position.Z).Unit
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
                rp.IgnoreWater = true
                local from = r.Position + Vector3.new(0, 3, 0)
                local side0 = Fi.detourSide or 1
                local pick, pickA
                for _, a in ipairs({ 30, 60, 90, 120, 150 }) do
                    for _, s in ipairs({ side0, -side0 }) do
                        local ang = math.rad(a * s)
                        local v = Vector3.new(d.X * math.cos(ang) - d.Z * math.sin(ang), 0, d.X * math.sin(ang) + d.Z * math.cos(ang))
                        if not (badAng[a * s]) and not workspace:Raycast(from, v * 300, rp) then pick, pickA = v, a * s break end
                    end
                    if pick then break end
                end
                if not pick then
                    if next(badAng) then badAng = {} else why = "closed in on every side" break end
                end
                if pick then
                Fi.detourSide = pickA > 0 and 1 or -1
                local via = r.Position + pick * 280
                log(string.format("travel: detour %d, %d degrees, via %d,%d", detours, pickA, via.X, via.Z))
                local okD = Fi.waterWalk(via, { near = 25, limit = 60 })
                local r3 = A.root()
                -- v2_21 (Rose Kingdom shore 15:01): the same blocked detour was tried 20 times - a detour that
                -- does not move us 60 studs is not offered again until another one works
                if not okD and r3 and M.flat(r3.Position, r.Position) < 60 then badAng[pickA] = true else badAng = {} end
                end
            end
        end
        r = A.root()
        log(string.format("travel: %s | %.0f studs planned, %.0f left, %.0f s, detours %d, strikes total %d, deaths %d",
            why, dist0, r and M.flat(r.Position, pos) or -1, os.clock() - t0, detours, F.strikes, F.deaths or 0))
        return why == "arrived", why
    end
    -- gate search (v2_21): Thriller Bark sits inside a wall (Workspace.Islands["Thriller Bark"].Wall, ~159 high;
    -- flying over it = kicked). Walk on the water along the wall, 70 studs off it, and look for a stretch where a
    -- ray toward the wall line finds no wall for 500 studs = an opening. Only wall parts are seen by these rays
    -- (they stream in as we get near). Every step goes to gpo2/gate.txt. Returns the opening point or nil.
    function Fi.findGate(island, maxSteps)
        local isl = workspace:FindFirstChild("Islands") and workspace.Islands:FindFirstChild(island or "Thriller Bark")
        if not isl then log("gate: island not found") return nil end
        local out = {}
        local function note(s) out[#out + 1] = os.date("%H:%M:%S ") .. s log("gate: " .. s) pcall(writefile, FOLDER .. "/gate.txt", table.concat(out, "\n")) end
        local function wallRay(from, dir, len)
            local walls = {}
            for _, c in ipairs(isl:GetChildren()) do if c.Name == "Wall" then walls[#walls + 1] = c end end
            if #walls == 0 then return nil end
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Include
            rp.FilterDescendantsInstances = walls
            return workspace:Raycast(from, dir * len, rp)
        end
        local function eye() local r = A.root() return r and Vector3.new(r.Position.X, 20, r.Position.Z) end
        -- nearest wall around us
        local function nearestWall(len)
            local e = eye()
            local best
            for a = 0, 345, 15 do
                local d = Vector3.new(math.cos(math.rad(a)), 0, math.sin(math.rad(a)))
                local hit = e and wallRay(e, d, len)
                if hit and (not best or hit.Distance < best.Distance) then best = { Distance = hit.Distance, Position = hit.Position, dir = d } end
            end
            return best
        end
        local w = nearestWall(1500)
        local tries = 0
        while not w and tries < 12 and F.running do
            -- no wall loaded near: walk away from the island centre (the quest NPC area) and look again
            tries = tries + 1
            local r = A.root()
            local away = Vector3.new(r.Position.X - 10300, 0, r.Position.Z + 7100)
            away = away.Magnitude > 1 and away.Unit or Vector3.new(-1, 0, 0)
            note(string.format("no wall within 1500 of %d,%d - walking out (%d)", r.Position.X, r.Position.Z, tries))
            Fi.waterWalk(r.Position + away * 400, { near = 30, limit = 60 })
            w = nearestWall(1500)
        end
        if not w then note("no wall found") return nil end
        note(string.format("first wall %.0f studs away at %d,%d", w.Distance, w.Position.X, w.Position.Z))
        local toWall = w.dir                       -- direction from us to the wall
        -- first get next to it (v2_21 first run: the wall was 565 away, the 500-stud check called that an opening)
        do
            local goal = w.Position - toWall * 70
            local okA, wA = Fi.waterWalk(Vector3.new(goal.X, 0, goal.Z), { near = 30, limit = 120 })
            note("walked to the wall: " .. (okA and "ok" or tostring(wA)))
        end
        local side = 1
        local OFF, STEP = 70, 160
        local blockedRow = 0
        for i = 1, maxSteps or 90 do
            if not F.running or not F.isAlive() then note("stopped") return nil end
            local e = eye()
            if not e then note("no character") return nil end
            -- is the wall still there, straight and a little ahead?
            local tan = Vector3.new(-toWall.Z, 0, toWall.X) * side
            local hit = wallRay(e, toWall, 500)
            local ahead = wallRay(e + tan * 60, toWall, 500)
            if not hit and not ahead then
                -- look again with a fan (the wall may curve away)
                local near = nearestWall(500)
                if not near then
                    note(string.format("OPENING? no wall within 500 at %d,%d (step %d) - going through", e.X, e.Z, i))
                    local okT, wT = Fi.waterWalk(e + toWall * 450, { near = 30, limit = 90 })
                    local r2 = A.root()
                    local back = r2 and wallRay(Vector3.new(r2.Position.X, 20, r2.Position.Z), -toWall, 900)
                    note(string.format("through: %s, now %d,%d, wall behind us %s", tostring(wT), r2 and r2.Position.X or 0, r2 and r2.Position.Z or 0, back and string.format("%.0f studs", back.Distance) or "not seen"))
                    return r2 and r2.Position or nil
                end
                toWall = near.dir
                hit = near
            end
            local h2 = hit or ahead
            local dist = h2.Distance
            if hit and hit.Normal then
                local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
                if n.Magnitude > 0.3 then toWall = -n.Unit end      -- face the wall squarely
            end
            tan = Vector3.new(-toWall.Z, 0, toWall.X) * side
            -- next point: along the wall, corrected to stay OFF studs from it
            local target = e + tan * STEP + toWall * (dist - OFF)
            local okW, wW = Fi.waterWalk(Vector3.new(target.X, 0, target.Z), { near = 25, limit = 45 })
            local r2 = A.root()
            note(string.format("step %d: wall %.0f away, went %s -> %d,%d", i, dist, okW and "ok" or tostring(wW), r2 and r2.Position.X or 0, r2 and r2.Position.Z or 0))
            if not okW then
                blockedRow = blockedRow + 1
                if tostring(wW):find("STRIKE") or tostring(wW):find("died") or tostring(wW):find("sink") then return nil end
                if blockedRow >= 3 then
                    -- land in the way on this side: turn round and follow the wall the other way (once)
                    if side == 1 then side = -1 blockedRow = 0 note("blocked 3 times - following the wall the other way")
                    else note("blocked both ways") return nil end
                end
            else blockedRow = 0 end
        end
        note("no opening after all steps")
        return nil
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
            HV.lastT, HV.onAt = os.clock(), os.clock()
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
        -- v2_23: when the target dies we used to drop at once and climb again for the next one ("it still comes
        -- down", owner 17:10). Now the float holds its place for up to 1.5 s until the next target is set.
        if not F.running or os.clock() - HV.t > 1.5 then Fi.hoverOff() return end
        if not goal then HV.lastP = A.root() and A.root().Position HV.lastT = os.clock() return end
        -- a game flight strike while hovering: hover goes off for good (until the owner turns it on again)
        if F.strikes > (HV.strikesSeen or 0) and F.cfg.ignoreStrikes then HV.strikesSeen = F.strikes end
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
            -- v2_20: no walk input while the AlignPosition carries us (it added the walk speed to the glide and
            -- never gave the run state anyway); only the sea / sprint glide sets HV.dir
            HV.dir = HV.sprintGlide and (dir.Magnitude > 3 and dir.Unit or Vector3.zero) or nil
        end
        askRun()
        local sp = sprinting()
        -- v2_24: the owner sets the float speed with a slider (Fight page) to find the limit himself.
        -- Known from the game code: above 16 studs/s without the run state the guard corrects (pull to the ground).
        HV.ap.MaxVelocity = (HV.sea and F.cfg.seaSpeed) or F.cfg.hoverSpeed or 15      -- (v2_38: own speed for sea travel)
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
                local H = F.cfg.seaHeight or 8
                local floorY = math.max(floorAt(p), floorAt(p + dir * 14))
                local step = math.min(left, 40)
                -- (a Blockcast that starts touching the wall reports nothing - v2_16 never climbed; rays from a
                -- little behind us, at foot, body and head height)
                local wall = nil
                for _, dy in ipairs({ -2, 0, 2.5 }) do
                    wall = wall or workspace:Raycast(p - dir * 3 + Vector3.new(0, dy, 0), dir * 20, rp)
                end
                local ty = floorY + H
                if wall then ty = math.max(ty, p.Y + 12) step = 2 HV.climbs = (HV.climbs or 0) + 1 end
                HV.seaFloor = floorY
                HV.seaTarget = Vector3.new(p.X + dir.X * step, ty, p.Z + dir.Z * step)
            end
            if HV.seaTarget then HV.ap.Position = HV.seaTarget end
        else
            -- v2_20: the "snap" (1 frame, ~20 studs, up 9 then onto the ground, about once per quest) is NOT the
            -- guard: no LocalNotification, and at that moment the character carries the game s own FlyBypass +
            -- SpeedBypass (68) attributes = one of our own Magu skills moves the user (a lunge that lands ~18 studs
            -- on). Nothing to fix; the pull counters skip moves made under those attributes. Height stays steady.
            HV.ap.Position = goal + Vector3.new(0, F.cfg.hoverHeight or 7, 0)
        end
        if r and HV.lastP then
            local d = (r.Position - HV.lastP).Magnitude
            local cc = A.char()
            if d > 8 and cc and (cc:GetAttribute("SpeedBypass") or cc:GetAttribute("FlyBypass")) then
                HV.skillMoves = (HV.skillMoves or 0) + 1      -- the game moved us (own skill)
            elseif d > 8 then
                HV.pulls = HV.pulls + 1
                log("hover pull facts: hp drop 1 s " .. math.floor(hpDrop()) .. " | " .. A.pullFacts())
                local hh = A.hum()
                log(string.format("hover: PULLED %.0f studs (%.0f,%.0f,%.0f -> %.0f,%.0f,%.0f) | frame %.3f s | hover on for %.1f s | floor %s | state %s | vel y %.0f",
                    d, HV.lastP.X, HV.lastP.Y, HV.lastP.Z, r.Position.X, r.Position.Y, r.Position.Z, os.clock() - (HV.lastT or os.clock()),
                    os.clock() - (HV.onAt or os.clock()), hh and hh.FloorMaterial.Name or "?", hh and tostring(hh:GetState()):gsub("Enum.HumanoidStateType.", "") or "?", r.AssemblyLinearVelocity.Y))
            end
        end
        HV.lastP = r and r.Position
        HV.lastT = os.clock()
        local hh = A.hum()
        if hh and not HV.sea then
            if hh.FloorMaterial == Enum.Material.Air then HV.airTicks = (HV.airTicks or 0) + 1 else HV.groundTicks = (HV.groundTicks or 0) + 1 end
        end
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
            if h.Health < h.MaxHealth * (F.cfg.retreatHp or opts.retreatHp or 30) / 100 then Fi.retreat(hr.Position, opts.backHp or 75) return "retreat" end
            F.status = string.format("Fighting %s (%d hp)", m.Name, mh.Health)

            local d = (hr.Position - r.Position).Magnitude
            -- v2_7: glide up to 150 studs. v2_8 test 08:47: a straight glide stuck on a cliff wall for a minute ->
            -- glide only with a clear line from us to the hover spot; else walk (the path goes around)
            local hovering = opts.hover and F.cfg.hover and (d <= 12 or (d <= 150 and Fi.clearLine(r.Position, hr.Position + Vector3.new(0, F.cfg.hoverHeight or 7, 0), m)))
            if hovering then
                Fi.hoverOn(m)          -- the AlignPosition carries us there (22 studs/s max)
                task.wait(0.1)
            elseif d > 150 then
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
            if F.cfg.autoBlock and d <= 9 and drop >= h.MaxHealth * 0.06 and os.clock() - (Fi.lastBlock or 0) > 2 then
                Fi.lastBlock = os.clock()
                Fi.st.blocks = Fi.st.blocks + 1
                holdKey(Enum.KeyCode.F, 0.8)
                hpHist = {}
                task.wait(0.85)
            elseif F.cfg.useSkills and opts.skills ~= false and d <= 12 and Fi.skill(hr.Position, mh, hovering) then
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
-- nav (v2_22): ONE way to get anywhere on foot, on land and on the water (owner 11-20: "find a way to walk, not
-- fix one thing after another"). Replaces the guessed detours of Fi.travel.
--
-- Method ("follow the edge", Bug2):
--   GO     : walk straight at the goal.
--   blocked: remember how far from the goal we were (hitDist), pick a side, and
--   FOLLOW : walk along the edge of whatever blocks (wall, cliff, rock, island), keeping it at arm's length,
--            until we are back on the straight start->goal line, closer to the goal than hitDist, with free
--            space toward the goal. Then GO again.
--   If the edge brings us back to where we first hit it, the other side is tried; after both: "no way".
-- What counts as blocking: something solid within reach at body height that is too steep to walk up (a slope we
-- can walk is not an obstacle) and too high to jump (a low ledge is jumped).
-- The walked points are kept (Nav.trail) and saved by Nav.saveRoute, so the next trip can replay them.
-- Safety on the water as in Fi.waterWalk: stops on a game strike notice, swimming / sinking, HP loss on water.
--------------------------------------------------------------------------------
local Nav = { trail = {} }
do
    local Fi = F.fight
    local flat = M.flat
    local function rp()
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Exclude
        p.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
        p.IgnoreWater = true
        return p
    end
    local function rot(v, deg)
        local a = math.rad(deg)
        return Vector3.new(v.X * math.cos(a) - v.Z * math.sin(a), 0, v.X * math.sin(a) + v.Z * math.cos(a))
    end
    -- free distance from pos along dir (up to len): the nearest thing that really blocks at knee / chest / head.
    -- Walkable slopes (normal.Y > 0.35) and things only at knee height (jumpable) do not block.
    local function free(pos, dir, len, params)
        local best = len
        local low, high = false, false
        for i, dy in ipairs({ -1.5, 1, 3.5 }) do
            local hit = workspace:Raycast(pos + Vector3.new(0, dy, 0), dir * len, params)
            if hit and hit.Normal.Y <= 0.35 then
                if i == 1 then low = hit.Distance else high = true if hit.Distance < best then best = hit.Distance end end
            end
        end
        return best, (low and not high) and low or nil      -- free distance, distance of a jumpable ledge
    end
    -- one walking step toward `to` (up to 1.2 s); returns how far we really moved (flat)
    local function step(to)
        local h, r = A.hum(), A.root()
        if not h or not r then return 0 end
        local p0 = r.Position
        h:MoveTo(to)
        local t0 = os.clock()
        while os.clock() - t0 < 1.2 do
            task.wait(0.15)
            r = A.root()
            if not r or flat(r.Position, to) < 3 then break end
        end
        r = A.root()
        return r and flat(r.Position, p0) or 0
    end
    local function onLine(p, a, b)          -- flat distance from p to the line a->b
        local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
        local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
        if ab.Magnitude < 1 then return ap.Magnitude end
        return math.abs(ab.X * ap.Z - ab.Z * ap.X) / ab.Magnitude
    end

    -- walk to pos; opts.near (default 10), opts.limit seconds. Returns ok, why.
    function Nav.go(pos, opts)
        opts = opts or {}
        local near = opts.near or 10
        local r, h = A.root(), A.hum()
        if not r or not h then return false, "no character" end
        Fi.hoverOff()
        local params = rp()
        local start, t0 = r.Position, os.clock()
        local dist0 = flat(start, pos)
        local limit = opts.limit or (120 + dist0 / 6)
        local strikes0, char0 = F.strikes, A.char()
        local state, side = "GO", 1
        local hitDist, hitPos, toWall, followLen, triedOther = nil, nil, nil, 0, false
        local stuck, lastLog, hpWater = 0, os.clock(), nil
        local st = { follows = 0, jumps = 0, followStuds = 0 }
        Nav.trail = { start }
        local function mark(p) if flat(p, Nav.trail[#Nav.trail]) > 60 then Nav.trail[#Nav.trail + 1] = p end end
        local ok, why = false, "stopped"
        local ocean = Fi.hv.ocean
        while F.running and F.isAlive() do
            if A.char() ~= char0 then why = "died" break end
            r, h = A.root(), A.hum()
            if not r or not h or h.Health <= 0 then why = "died" break end
            local p = r.Position
            local left = flat(p, pos)
            mark(p)
            if left <= near then ok, why = true, "arrived" break end
            if F.strikes > strikes0 and not F.cfg.ignoreStrikes then why = "GAME STRIKE - stopped" break end
            if os.clock() - t0 > limit then why = "timeout" break end
            local sea = ocean and ocean(p.X, p.Z) or -3
            local water = math.abs(p.Y - sea) < 6
            if h:GetState() == Enum.HumanoidStateType.Swimming then why = "swimming (not held on the water)" break end
            if p.Y < sea - 6 then why = "sinking" break end
            if water then
                if h.Health < (hpWater or h.Health) - h.MaxHealth * 0.15 then why = "losing HP on the water" break end
                hpWater = hpWater or h.Health
            else hpWater = nil end
            if os.clock() - lastLog > 30 then
                lastLog = os.clock()
                log(string.format("nav: %s | %.0f left | %d,%d,%d | %s | follows %d (%.0f studs)", state, left, p.X, p.Y, p.Z, water and "water" or "land", st.follows, st.followStuds))
            end
            local reach = water and 30 or 9          -- how far ahead must be free
            local arm = water and 22 or 6            -- distance kept from the edge while following
            local stepLen = water and 40 or 14
            local toGoal = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Unit

            if state == "GO" then
                local fr, ledge = free(p, toGoal, reach, params)
                if fr >= reach - 0.5 then
                    if ledge and ledge < 5 then if M.jump() then st.jumps = st.jumps + 1 end end
                    local moved = step(p + toGoal * math.min(left, stepLen))
                    stuck = (moved < 1.5) and stuck + 1 or 0
                    if stuck >= 3 then
                        -- nothing seen by the rays but we do not move (rail, invisible part): treat as blocked here
                        fr = 0
                        stuck = 0
                    end
                end
                if fr < reach - 0.5 then
                    state, hitDist, hitPos, toWall, followLen = "FOLLOW", left, p, toGoal, 0
                    st.follows = st.follows + 1
                    log(string.format("nav: blocked at %d,%d,%d (%.0f left) - following the edge, side %d", p.X, p.Y, p.Z, left, side))
                end
            else
                -- FOLLOW: keep the edge on the toWall side. Turn so that: wall ahead -> turn away; wall lost -> turn toward it.
                local tan = rot(toWall, -90 * side)
                local wallFree = free(p, toWall, arm * 2.5, params)
                local aheadFree, ledge = free(p, tan, stepLen, params)
                if aheadFree < stepLen * 0.6 then
                    toWall = tan                           -- inside corner: the thing ahead becomes the wall
                elseif wallFree >= arm * 2.5 - 0.5 then
                    toWall = rot(toWall, 35 * side)        -- lost the wall (outside corner): swing toward it
                    step(p + rot(toWall, -90 * side) * (stepLen * 0.5))
                    followLen = followLen + stepLen * 0.5
                else
                    if ledge and ledge < 5 then if M.jump() then st.jumps = st.jumps + 1 end end
                    local target = p + tan * math.min(aheadFree - 2, stepLen) + toWall * (wallFree - arm)
                    local moved = step(target)
                    followLen = followLen + moved
                    st.followStuds = st.followStuds + moved
                    stuck = (moved < 1.5) and stuck + 1 or 0
                    if stuck >= 3 then toWall = tan stuck = 0 end
                end
                r = A.root()
                p = r and r.Position or p
                left = flat(p, pos)
                -- leave the edge: back on the start->goal line, clearly closer than where we hit it, way to the goal free
                if followLen > 25 and left < hitDist - 15 and onLine(p, start, pos) < (water and 30 or 10) then
                    local g = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Unit
                    if free(p, g, reach, params) >= reach - 0.5 then
                        state = "GO"
                        log(string.format("nav: left the edge at %d,%d,%d after %.0f studs (%.0f left)", p.X, p.Y, p.Z, followLen, left))
                    end
                -- also leave when the goal is simply in view (free line all the way, up to 300 studs)
                elseif followLen > 25 and left < 300 and free(p, Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Unit, left, params) >= left - 1 then
                    state = "GO"
                    log(string.format("nav: goal in view at %d,%d,%d (%.0f left)", p.X, p.Y, p.Z, left))
                elseif followLen > 200 and flat(p, hitPos) < (water and 45 or 15) then
                    -- came all the way round to where we hit it
                    if triedOther then why = "no way round (both sides)" break end
                    triedOther, side, followLen, toWall = true, -side, 0, Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Unit
                    log("nav: back at the hit point - trying the other side")
                end
            end
        end
        pcall(function() local rr = A.root() if rr then A.hum():MoveTo(rr.Position) end end)
        r = A.root()
        if r then Nav.trail[#Nav.trail + 1] = r.Position end
        log(string.format("nav: %s | %.0f studs planned, %.0f left, %.0f s | edges followed %d (%.0f studs), jumps %d | strikes %d",
            why, dist0, r and flat(r.Position, pos) or -1, os.clock() - t0, st.follows, st.followStuds, st.jumps, F.strikes - strikes0))
        return ok, why
    end

    -- routes: gpo2/routes.json = { "<name>": [[x,y,z], ...] }. A saved route is replayed point by point with Nav.go.
    local ROUTES = FOLDER .. "/routes.json"
    local function loadRoutes()
        local t = {}
        pcall(function() if isfile(ROUTES) then t = HttpService:JSONDecode(readfile(ROUTES)) end end)
        return type(t) == "table" and t or {}
    end
    function Nav.saveRoute(name)
        local t = loadRoutes()
        local pts = {}
        for _, v in ipairs(Nav.trail) do pts[#pts + 1] = { math.floor(v.X), math.floor(v.Y), math.floor(v.Z) } end
        t[name] = pts
        pcall(function() writefile(ROUTES, HttpService:JSONEncode(t)) end)
        log("nav: route '" .. name .. "' saved, " .. #pts .. " points")
    end
    function Nav.followRoute(name)
        local pts = loadRoutes()[name]
        if type(pts) ~= "table" or #pts == 0 then return false, "no route " .. name end
        -- start at the route point nearest to us
        local r = A.root()
        local first, bd = 1, math.huge
        for i, v in ipairs(pts) do
            local d = flat(r.Position, Vector3.new(v[1], v[2], v[3]))
            if d < bd then first, bd = i, d end
        end
        for i = first, #pts do
            local v = pts[i]
            local ok, why = Nav.go(Vector3.new(v[1], v[2], v[3]), { near = (i == #pts) and 10 or 25 })
            if not ok then return false, "route " .. name .. " point " .. i .. ": " .. tostring(why) end
        end
        return true, "arrived"
    end
end
F.nav = Nav

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
        elseif cmd == "rejoin" then
            F.rejoin()
        elseif cmd == "press" then
            -- press <part of a button's path or text>: fire that visible button's click (menu place)
            local want = arg:lower()
            for _, o in ipairs(LP.PlayerGui:GetDescendants()) do
                if (o:IsA("TextButton") or o:IsA("ImageButton")) and (o:GetFullName():lower():find(want, 1, true) or (o:IsA("TextButton") and o.Text:lower():find(want, 1, true))) then
                    local how = "none"
                    if type(firesignal) == "function" then
                        pcall(firesignal, o.MouseButton1Click) pcall(firesignal, o.Activated) pcall(firesignal, o.MouseButton1Down) pcall(firesignal, o.MouseButton1Up)
                        how = "firesignal"
                    end
                    log("press: " .. o:GetFullName():sub(-70) .. " via " .. how)
                    return
                end
            end
            log("press: no button matches " .. arg)
        elseif cmd == "rays" then
            -- rays x z: what is in the way toward x,z - 12 rays (every 30 degrees from the goal line), 600 studs
            local x, z = arg:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
            local r = A.root()
            if not x or not r then log("rays: need x z") return end
            local d = Vector3.new(tonumber(x) - r.Position.X, 0, tonumber(z) - r.Position.Z).Unit
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
            rp.IgnoreWater = true
            for a = 0, 330, 30 do
                local ang = math.rad(a)
                local v = Vector3.new(d.X * math.cos(ang) - d.Z * math.sin(ang), 0, d.X * math.sin(ang) + d.Z * math.cos(ang))
                local hit = workspace:Raycast(r.Position + Vector3.new(0, 3, 0), v * 600, rp)
                if hit then
                    local p = hit.Instance
                    log(string.format("rays: %3d deg hit at %.0f studs: %s (%s) size %d,%d,%d transp %.1f collide %s",
                        a, hit.Distance, p:GetFullName():sub(1, 70), p.ClassName, p.Size.X, p.Size.Y, p.Size.Z, p.Transparency, tostring(p.CanCollide)))
                else log(string.format("rays: %3d deg open (600)", a)) end
            end
        elseif cmd == "walls" then
            -- walls <island>: every part of Workspace.Islands.<island>.Wall -> gpo2/walls.txt (pos, size, yaw)
            local isl = workspace:FindFirstChild("Islands") and workspace.Islands:FindFirstChild(arg)
            local wall = isl and isl:FindFirstChild("Wall")
            if not wall then
                local names = {}
                for _, c in ipairs(isl and isl:GetChildren() or (workspace:FindFirstChild("Islands") and workspace.Islands:GetChildren()) or {}) do names[#names + 1] = c.Name end
                log("walls: not found; children: " .. table.concat(names, ", "):sub(1, 300))
                return
            end
            local out = {}
            for _, p in ipairs(isl:GetDescendants()) do
                -- every part under any child named "Wall" (there are several, some empty until streamed in)
                if p:IsA("BasePart") and p:FindFirstAncestor("Wall") then
                    local _, yaw = p.CFrame:ToOrientation()
                    out[#out + 1] = string.format("%s|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.1f|%s", p.Name, p.Position.X, p.Position.Y, p.Position.Z, p.Size.X, p.Size.Y, p.Size.Z, math.deg(yaw), tostring(p.CanCollide))
                end
            end
            pcall(writefile, FOLDER .. "/walls.txt", table.concat(out, "\n"))
            log("walls: " .. #out .. " parts written")
        elseif cmd == "nav" or cmd == "navroute" then
            -- nav x y z [route name to save] : edge-following walk (land + water) | navroute <name> : replay a saved route
            F.stop()
            task.wait(0.3)
            if cmd == "navroute" then
                F.moveList = { { pos = Vector3.zero, name = "route " .. arg, navroute = arg } }
            else
                local x, y, z, nm = arg:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)%s*(.*)$")
                if not x then log("nav: no point read") return end
                F.moveList = { { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = "nav", nav = true, save = (nm ~= "" and nm or nil) } }
            end
            F.cfg.mode = "Move test"
            F.start()
        elseif cmd == "reset" then
            -- reset: the game s own "Reset Character" (Humanoid health 0) - a new spawn. Never the Revive button.
            local h = A.hum()
            if h then log("reset: character reset at " .. A.posText()) h.Health = 0 end
        elseif cmd == "keys" then
            -- keys: per skill key - how it moves us and its damage; share of hover time spent in the air
            local hv = F.fight.hv
            local air, gr = hv.airTicks or 0, hv.groundTicks or 0
            log("keys: " .. F.fight.keyReport())
            log(string.format("keys: hover time in the air %d%% (%d / %d ticks), skill moves %d, skip list [%s]", (air + gr) > 0 and math.floor(air / (air + gr) * 100) or 0, air, air + gr, hv.skillMoves or 0, F.cfg.hoverSkipKeys))
        elseif cmd == "sellfish" then
            -- sellfish: sell at the Fish Buyer now (runs inside the running Fishing mode thread-safe enough for a test)
            task.spawn(function() F.fishing.sell() end)
        elseif cmd == "craftbait" then
            -- craftbait <Common|Rare|Legendary>: craft at Blacksmith Sen now (test)
            task.spawn(function() F.fishing.craft(arg ~= "" and arg or "Common") end)
        elseif cmd == "seademo" or cmd == "seatime" then
            -- seademo [studs]: hover out over open water and back to the exact start, at hover speed 15, strikes ignored
            -- for this one trip so the hover is never switched off over deep water (owner 19:06 / 19:15 wants to see it)
            local rr = A.root()
            if not rr then return end
            local n = math.clamp(tonumber(arg) or 50, 10, 80)
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("Effects") }
            rp.IgnoreWater = true
            local home = rr.Position
            if not workspace:Raycast(home, Vector3.new(0, -12, 0), rp) then log("seademo: no ground under the start - not starting") return end
            -- a direction whose whole line (every 10 studs) is over open water and has nothing in the way
            local d = nil
            for a = 0, 345, 15 do
                local c = Vector3.new(math.cos(math.rad(a)), 0, math.sin(math.rad(a)))
                local open = true
                for s = 15, n, 5 do
                    local q = home + c * s
                    local hit = workspace:Raycast(Vector3.new(q.X, home.Y + 30, q.Z), Vector3.new(0, -60, 0), rp)
                    if hit then open = false break end
                end
                if open and not workspace:Raycast(home + Vector3.new(0, 2, 0), c * n, rp)
                    and workspace:Raycast(home - c * 6, Vector3.new(0, -12, 0), rp) and workspace:Raycast(home - c * 2, Vector3.new(0, -12, 0), rp) then d = c break end
            end
            if not d then log("seademo: no open water line of " .. n .. " studs from here") return end
            -- land 2 studs behind the start: the back point is 6 studs inland, reached within 4
            local back = home - d * 6
            if not (workspace:Raycast(back, Vector3.new(0, -12, 0), rp) and workspace:Raycast(home - d * 2, Vector3.new(0, -12, 0), rp)) then
                log("seademo: no ground 2-6 studs behind the start - step back from the edge first") return
            end
            F.stop()
            task.wait(0.3)
            local wasI, wasS = F.cfg.ignoreStrikes, F.cfg.hoverSpeed
            F.cfg.ignoreStrikes, F.cfg.hoverSpeed = true, 15
            local s0 = F.strikes
            log(string.format("seademo: start %s, out %d studs toward %.0f,%.0f, Logia mode %s", A.posText(), n, d.X * 100, d.Z * 100, tostring(F.fight.logiaOn())))
            if cmd == "seatime" then
                -- seatime [studs] : hold over the water until the first strike (max 90 s), then back
                F.moveList = { { pos = home + d * n, name = "hold over the water", seahold = true, home = back } }
            else
                F.moveList = { { pos = home + d * n, name = "demo out", sea = true, near = 4 }, { pos = back, name = "demo back", sea = true, near = 4 } }
            end
            F.cfg.mode = "Move test"
            F.start()
            task.spawn(function()
                task.wait(1)
                while F.running and F.isAlive() do task.wait(0.3) end
                F.cfg.ignoreStrikes, F.cfg.hoverSpeed = wasI, wasS
                log(string.format("seademo: done, game strikes during the trip %d, now at %s", F.strikes - s0, A.posText()))
            end)
        elseif cmd == "searoute" then
            -- searoute x,y,z;x,y,z...: hover over the sea through these points without switching the hover off in
            -- between; game strikes do not stop it (stopping in mid sea = drowning). The last point must be on land.
            local list = {}
            for part in arg:gmatch("[^;]+") do
                local x, y, z = part:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
                if x then list[#list + 1] = { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = "sea #" .. (#list + 1), sea = true, keep = true, near = 25, limit = 3600 } end
            end
            if #list == 0 then log("searoute: no points read") return end
            list[#list].keep, list[#list].near = nil, 6
            F.stop()
            task.wait(0.3)
            local was, s0, t0 = F.cfg.ignoreStrikes, F.strikes, os.clock()
            F.cfg.ignoreStrikes = true
            F.moveList = list
            F.cfg.mode = "Move test"
            F.start()
            task.spawn(function()
                task.wait(1)
                while F.running and F.isAlive() do task.wait(0.5) end
                F.cfg.ignoreStrikes = was
                log(string.format("searoute: ended after %.0f s, game strikes %d, now at %s", os.clock() - t0, F.strikes - s0, A.posText()))
            end)
        elseif cmd == "platwalk" then
            -- platwalk x,y,z;x,y,z...: walk on the local platform through these points (mode "Move test");
            -- HP loss / a game strike = walk back to where we stand now
            local rr = A.root()
            if not rr then return end
            local list, home = {}, rr.Position
            for part in arg:gmatch("[^;]+") do
                local x, y, z = part:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
                if x then list[#list + 1] = { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = "plat #" .. (#list + 1), plat = true, home = home, limit = 3600 } end
            end
            if #list == 0 then log("platwalk: no points read") return end
            F.stop()
            task.wait(0.3)
            F.moveList = list
            F.cfg.mode = "Move test"
            F.start()
        elseif cmd == "open" then
            -- open <dropdown label>: open that dropdown in the window (for screenshots)
            local fn = UI.dropdowns and UI.dropdowns[arg]
            if fn then fn(true) else log("open: no dropdown " .. arg) end
        elseif cmd == "fishinfo" then
            local fs_ = F.fishing
            local sp = fs_.sen()
            local npcs = workspace:FindFirstChild("NPCs")
            local fb = npcs and npcs:FindFirstChild("Fish Buyer")
            local bpos = fb and fb:GetPivot().Position
            log(string.format("fishinfo: Sen %s | Fish Buyer %s | bait C %d R %d L %d | Tigerfin %d, Blue-Lip Grouper %d | Crafting gui %s, FishSellerGui %s",
                sp and string.format("%.0f,%.0f,%.0f", sp.X, sp.Y, sp.Z) or "not loaded", bpos and string.format("%.0f,%.0f,%.0f", bpos.X, bpos.Y, bpos.Z) or "not loaded",
                fs_.count("Common Fish Bait"), fs_.count("Rare Fish Bait"), fs_.count("Legendary Fish Bait"), fs_.count("Tigerfin"), fs_.count("Blue-Lip Grouper"),
                tostring(LP.PlayerGui:FindFirstChild("Crafting") ~= nil), tostring(LP.PlayerGui:FindFirstChild("FishSellerGui") ~= nil)))
        elseif cmd == "gate" then
            -- gate: follow the island wall on the water and look for the opening (mode "Move test")
            F.stop()
            task.wait(0.3)
            local rr = A.root()
            F.moveList = { { pos = rr and rr.Position or Vector3.zero, name = "gate search", gate = true } }
            F.cfg.mode = "Move test"
            F.start()
        elseif cmd == "travel" then
            -- travel x y z: cross the sea on the surface + land walk to a far point (mode "Move test")
            local x, y, z = arg:match("(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)[,%s]+(%-?[%d%.]+)")
            if not x then log("travel: no point read") return end
            F.stop()
            task.wait(0.3)
            F.moveList = { { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), name = "travel", travel = true } }
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
            -- ui <page name>: show the window on that page (for screenshots of each tab)
            pcall(function()
                win.Visible = (arg ~= "off")
                if UI.pages[arg] then UI.show(arg) end
            end)
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
-- mode Fishing (v2_29, first version): cast -> wait for the bite -> play the catch bar -> again, at the spot where
-- the character stands. Everything is done with the rod tool's own Activated / Deactivated (= left mouse down /
-- up for the game's fishing script); the game sends its own calls. Nothing fires a game remote.
-- Facts from the game code (ReplicatedStorage.Fishing.Assets.Client, read 2026-11-20):
--   cast   = hold click (charge up to 1.5 s) and release; needs a selected bait with count > 0, feet on the ground,
--            the bobble must land on open water (not on an island / ship) and we must not move afterwards
--   bite   = attribute "Caught" on workspace.Effects["<name>'s hook"]; PlayerGui.FishingUIBill appears
--   bar    = FishingUIBill.Frame: Player (our bar), Goal (the fish), Time.Fill (progress), InfoText ("HOLD CLICK" /
--            "RELEASE CLICK" / empty when on target). Hold = our bar goes up, release = down. On target within
--            0.125 of the scale: +1 per second, off: -0.75; starts at 2 of 7.5; at 0 the fish is lost.
-- Not known from the code (this mode logs them): whether tool:Activate() counts as the click on this executor,
-- how long a bite takes, what the bait list looks like. Selling and bait crafting come after this works.
--------------------------------------------------------------------------------
do
    local Fs = { casts = 0, bites = 0, wins = 0, losses = 0, noHook = 0 }
    F.fishing = Fs
    local RunS = game:GetService("RunService")
    local VIM = game:GetService("VirtualInputManager")

    local function setState(s)
        if Fs.state ~= s then Fs.state = s setStatus("Fishing: " .. s) end
    end
    local function rod()
        local c, bp = A.char(), LP:FindFirstChild("Backpack")
        local held = c and c:FindFirstChildOfClass("Tool")
        if held and held.Name:find("Rod") then return held end
        for _, t in ipairs(bp and bp:GetChildren() or {}) do
            if t:IsA("Tool") and t.Name:find("Rod") then
                A.hum():EquipTool(t)
                task.wait(0.6)
                log("fishing: equip " .. t.Name)
                return A.char():FindFirstChildOfClass("Tool")
            end
        end
        return nil
    end
    -- bait buttons the game shows while the rod is held (FishingBaitGui.Main.List.<bait name>)
    local function baitInfo()
        local g = LP.PlayerGui:FindFirstChild("FishingBaitGui")
        local list = g and g:FindFirstChild("List", true)
        local out = {}
        for _, b in ipairs(list and list:GetChildren() or {}) do
            if b:IsA("GuiButton") then
                local texts = {}
                for _, d in ipairs(b:GetDescendants()) do if d:IsA("TextLabel") and d.Text ~= "" then texts[#texts + 1] = d.Text end end
                out[#out + 1] = { button = b, name = b.Name, text = table.concat(texts, " ") }
            end
        end
        return out, g
    end
    local function pickBait()
        local list, g = baitInfo()
        if #list == 0 then log("fishing: no bait buttons found (FishingBaitGui " .. (g and "present" or "missing") .. ")") return false end
        if not Fs.baitLogged then
            Fs.baitLogged = true
            local s = {}
            for _, b in ipairs(list) do s[#s + 1] = b.name .. " [" .. b.text .. "]" end
            log("fishing: baits: " .. table.concat(s, " | "))
        end
        -- the wanted bait (Settings later); default = the first whose text holds a number above 0, else the first
        local want = nil
        for _, b in ipairs(list) do
            if F.cfg.fishBait ~= "" and b.name == F.cfg.fishBait then want = b break end
        end
        if not want then
            for _, b in ipairs(list) do
                local n = tonumber(b.text:match("(%d+)"))
                if n and n > 0 then want = b break end
            end
        end
        want = want or list[1]
        if type(firesignal) == "function" then
            pcall(firesignal, want.button.MouseButton1Click)
            pcall(firesignal, want.button.Activated)
        end
        if Fs.bait ~= want.name then Fs.bait = want.name log("fishing: bait " .. want.name .. " [" .. want.text .. "]") end
        return true
    end
    -- a direction with open water 45 studs out (no ground above the water plane there)
    local function waterY()
        local y = -3
        pcall(function() y = workspace.Env.WaterStuff.Falls.Position.Y end)
        return y
    end
    local function waterDir()
        local r = A.root()
        local wy = waterY()
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { A.char(), workspace:FindFirstChild("Effects"), workspace:FindFirstChild("NPCs") }
        rp.IgnoreWater = true
        local best, bestClear = nil, -1
        for a = 0, 330, 30 do
            local d = Vector3.new(math.cos(math.rad(a)), 0, math.sin(math.rad(a)))
            local clear = 0
            for _, dist in ipairs({ 25, 45, 65 }) do
                local q = r.Position + d * dist
                local hit = workspace:Raycast(Vector3.new(q.X, r.Position.Y + 40, q.Z), Vector3.new(0, -300, 0), rp)
                if not hit or hit.Position.Y < wy - 1 then clear = clear + 1 end
            end
            -- nothing in the way of the throw either
            if clear == 3 and workspace:Raycast(r.Position + Vector3.new(0, 2, 0), d * 45, rp) then clear = 1 end
            if clear > bestClear then best, bestClear = d, clear end
        end
        return best, bestClear == 3, wy
    end
    local function hook() return workspace:FindFirstChild("Effects") and workspace.Effects:FindFirstChild(LP.Name .. "'s hook") end

    -- hold / release the click of the rod (method 1 = the tool's own Activate, 2 = a virtual mouse button)
    Fs.method = 1
    local held = false
    local function click(tool, down)
        if down == held then return end
        held = down
        if Fs.method == 1 then
            if down then tool:Activate() else tool:Deactivate() end
        else
            local v = workspace.CurrentCamera.ViewportSize
            VIM:SendMouseButtonEvent(v.X / 2, v.Y / 2, 0, down, game, 0)
        end
    end

    local function cast(tool, dir, wy)
        local r = A.root()
        local target = Vector3.new(r.Position.X + dir.X * 45, wy, r.Position.Z + dir.Z * 45)
        pcall(function() r.CFrame = CFrame.lookAt(r.Position, Vector3.new(target.X, r.Position.Y, target.Z)) end)
        -- the game aims at the mouse point: look at the water point and put the mouse on it
        local cam = workspace.CurrentCamera
        pcall(function()
            cam.CFrame = CFrame.lookAt(r.Position - dir * 12 + Vector3.new(0, 9, 0), target)
            task.wait(0.15)
            local sp = cam:WorldToViewportPoint(target)
            VIM:SendMouseMoveEvent(sp.X, sp.Y, game)
        end)
        task.wait(0.2)
        Fs.casts = Fs.casts + 1
        click(tool, true)
        task.wait(0.9)
        click(tool, false)
    end

    -- the catch bar: follow the fish. Hold when the goal is above our bar (smaller Y), with a little look-ahead.
    local function playBar(tool, gui)
        local frame = gui:FindFirstChild("Frame")
        local pl, goal = frame and frame:FindFirstChild("Player"), frame and frame:FindFirstChild("Goal")
        local fill = frame and frame:FindFirstChild("Time") and frame.Time:FindFirstChild("Fill")
        if not (pl and goal) then log("fishing: bar parts not found") return "no bar" end
        local t0, lastY, lastT, onT, total, lastFill = os.clock(), pl.Position.Y.Scale, os.clock(), 0, 0, 0
        while gui.Parent and F.running and F.isAlive() and os.clock() - t0 < 90 do
            local now = os.clock()
            local py, gy = pl.Position.Y.Scale, goal.Position.Y.Scale
            local vy = (py - lastY) / math.max(now - lastT, 0.001)
            lastY, lastT = py, now
            local ahead = py + vy * 0.12
            click(tool, gy < ahead - 0.01)
            total = total + 1
            if math.abs(py - gy) <= 0.125 then onT = onT + 1 end
            if fill then lastFill = fill.Size.X.Scale end
            RunS.Heartbeat:Wait()
        end
        click(tool, false)
        return string.format("bar %.1f s, on target %d%%, fill at end %.2f", os.clock() - t0, total > 0 and onT / total * 100 or 0, lastFill), lastFill
    end

    -- selling (v2_30). Game code (GUIS.FishSellerGui.FishShopClient): the Fish Buyer's talk only switches
    -- PlayerGui.FishSellerGui on; each fish row (Main.Items.List.<fish>) has Sell / SellAll buttons (their
    -- Activated signal) that open the game's ConfirmationPrompt; its Accept makes the game sell. We press those
    -- buttons with firesignal - the game sends its own shop call. Legendary fish (10,000+ Peli) are kept when
    -- cfg.fishKeepLegendary is on (they make Legendary bait).
    local function fire(btn)
        if type(firesignal) ~= "function" or not btn then return false end
        for _, sig in ipairs({ "Activated", "MouseButton1Click" }) do pcall(function() firesignal(btn[sig]) end) end
        return true
    end
    local function buyer()
        local npcs = workspace:FindFirstChild("NPCs")
        local m = npcs and npcs:FindFirstChild("Fish Buyer")
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end
    function Fs.sell()
        local bp = buyer()
        if not bp then log("fishing: no Fish Buyer loaded near - cannot sell here") return false end
        local r = A.root()
        if M.flat(r.Position, bp) > 8 then
            setState("walking to the Fish Buyer")
            local c = A.char()
            local t = c and c:FindFirstChildOfClass("Tool")
            if t then A.hum():UnequipTools() task.wait(0.3) end
            M.walkTo(bp, { near = 6 })
        end
        local gui = LP.PlayerGui:FindFirstChild("FishSellerGui")
        if not gui then log("fishing: FishSellerGui not found") return false end
        setState("selling fish")
        local peli0 = tonumber(A.stat("Peli")) or 0
        gui.Enabled = true
        task.wait(1.2)
        local list = gui:FindFirstChild("List", true)
        local sold, kept = 0, 0
        for _, row in ipairs(list and list:GetChildren() or {}) do
            if not F.isAlive() then break end
            local sa = row:IsA("GuiObject") and row.Visible and row:FindFirstChild("SellAll")
            if sa then
                local price = tonumber((row:FindFirstChild("Price") and row.Price.Text or ""):match("(%d+)")) or 0
                local tier = price >= 10000 and "Legendary" or (price >= 1000 and "Rare" or "Common")
                -- kept: legendary fish (switch), and the fish that make the bait picked under "Craft bait" while that bait is not full
                local forBait = F.cfg.fishAutoCraft and F.cfg.fishCraft == tier and Fs.count and Fs.TIER and Fs.count(Fs.TIER[tier].bait) < 300
                if (F.cfg.fishKeepLegendary and tier == "Legendary") or forBait then
                    kept = kept + 1
                else
                    fire(sa)
                    local prompt, t0 = nil, os.clock()
                    while not prompt and os.clock() - t0 < 3 do prompt = LP.PlayerGui:FindFirstChild("ConfirmationPrompt") task.wait(0.1) end
                    local acc = prompt and prompt:FindFirstChild("Accept", true)
                    if not acc and prompt then
                        -- the yes button may carry another name: take the first option button
                        local of = prompt:FindFirstChild("OptionsFrame", true)
                        for _, b in ipairs(of and of:GetChildren() or {}) do if b:IsA("GuiButton") then acc = acc or b end end
                    end
                    if acc then
                        fire(acc)
                        local t1 = os.clock()
                        while prompt.Parent and os.clock() - t1 < 3 do task.wait(0.1) end
                        sold = sold + 1
                        log(string.format("fishing: sold all %s (%d Peli each)", row.Name, price))
                    else
                        log("fishing: no confirmation prompt for " .. row.Name)
                    end
                    task.wait(0.4)
                end
            end
        end
        gui.Enabled = false
        task.wait(0.8)
        local gain = (tonumber(A.stat("Peli")) or 0) - peli0
        Fs.soldPeli = (Fs.soldPeli or 0) + gain
        log(string.format("fishing: sale done - %d kinds sold, %d kept, +%d Peli", sold, kept, gain))
        return sold > 0
    end

    -- bait crafting (v2_33). Game code (GUIS.Crafting.CraftingClient, read 2026-11-20): Blacksmith Sen's talk only
    -- switches PlayerGui.Crafting on. Blueprint row Main.Blueprints.List["<bait>"] -> fish slot
    -- Main.Requirements.List.Items["<tier> Fish"] -> the fish to use in Main.Requirements.Selection(.List) ->
    -- Main.Requirements.Craft -> the game's own prompt PlayerGui.craftCountSelector (Accept = "Craft Selected",
    -- Decline = "Craft 1"). We press those buttons; the game sends its own crafting call. One fish kind per craft,
    -- bait cap 300. NOT yet seen in game: whether the server wants Sen's talk first, and the slider override.
    local TIER = {
        Common = { bait = "Common Fish Bait", fish = "Common Fish" },
        Rare = { bait = "Rare Fish Bait", fish = "Rare Fish" },
        Legendary = { bait = "Legendary Fish Bait", fish = "Legendary Fish" },
    }
    Fs.TIER = TIER
    local RS = game:GetService("ReplicatedStorage")
    local INV = nil
    task.spawn(function() pcall(function() INV = require(RS.Modules.Client.Managers.InventorySnapshotManager) end) end)
    -- (v2_34: calling the game's module from the window's refresh thread took away that thread's right to write to
    -- the hub window - every row after it stayed empty. Counts are read by throw-away threads into a cache.)
    local cache = { ["Common Fish Bait"] = 0, ["Rare Fish Bait"] = 0, ["Legendary Fish Bait"] = 0 }
    task.spawn(function()
        while F.isAlive() do
            if INV then
                for name in pairs(cache) do
                    task.spawn(function() pcall(function() cache[name] = tonumber(INV:GetCount(name)) or 0 end) end)
                end
            end
            task.wait(0.5)
        end
    end)
    local function count(name)
        if cache[name] == nil then cache[name] = 0 task.wait(0.7) end      -- a new name: wait for one read
        return cache[name] or 0
    end
    Fs.count = count
    local function sen()
        local npcs = workspace:FindFirstChild("NPCs")
        local m = npcs and npcs:FindFirstChild("Blacksmith Sen")
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil, m
    end
    Fs.sen = sen
    local function path(root, ...)
        local o = root
        for _, n in ipairs({ ... }) do
            o = o and o:FindFirstChild(n)
        end
        return o
    end
    function Fs.craft(tierName)
        local t = TIER[tierName]
        if not t then return false end
        local sp, npc = sen()
        if not sp then log("fishing: Blacksmith Sen is not loaded near - cannot craft bait here") return false end
        local have0 = count(t.bait)
        if have0 >= 300 then log("fishing: " .. t.bait .. " is full (300)") return true end
        local r = A.root()
        if M.flat(r.Position, sp) > 8 then
            setState("walking to Blacksmith Sen")
            local c = A.char()
            if c and c:FindFirstChildOfClass("Tool") then A.hum():UnequipTools() task.wait(0.3) end
            M.walkTo(sp, { near = 6 })
        end
        local gui = LP.PlayerGui:FindFirstChild("Crafting")
        local main = gui and gui:FindFirstChild("Main")
        if not main then log("fishing: Crafting window not found") return false end
        setState("crafting " .. t.bait)
        pcall(function() gui.CraftingClient.Crafter.Value = npc end)
        gui.Enabled = true
        task.wait(1.2)
        local made = 0
        for round = 1, 8 do
            if not F.isAlive() then break end
            local bp = path(main, "Blueprints", "List", t.bait)
            if not bp then log("fishing: blueprint row '" .. t.bait .. "' not in the list") break end
            fire(bp)
            task.wait(0.6)
            local slot = path(main, "Requirements", "List", "Items", t.fish)
            if not slot then log("fishing: fish slot '" .. t.fish .. "' not found") break end
            fire(slot)
            task.wait(0.6)
            local sel = path(main, "Requirements", "Selection")
            local holder = sel and (sel:FindFirstChild("List") or sel)
            local best, bestN = nil, 0
            for _, e in ipairs(holder and holder:GetChildren() or {}) do
                if e:IsA("GuiObject") then
                    local txt = e:IsA("TextButton") and e.Text or ""
                    for _, d in ipairs(e:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("x%s*%d") then txt = d.Text end end
                    local n = tonumber(txt:match("x%s*(%d+)")) or count(e.Name)
                    if n > bestN then best, bestN = e, n end
                end
            end
            if round == 1 then log(string.format("fishing: craft window - slot %s, fish choices best %s x%d", slot.ClassName, best and best.Name or "none", bestN)) end
            if not best then break end
            fire(best)
            task.wait(0.5)
            local before = count(t.bait)
            fire(path(main, "Requirements", "Craft"))
            local prompt, t0 = nil, os.clock()
            while not prompt and os.clock() - t0 < 2 do prompt = LP.PlayerGui:FindFirstChild("craftCountSelector") task.wait(0.1) end
            if prompt then
                -- ask for the most the game allows (the slider's own End value)
                pcall(function()
                    local sl = path(prompt, "Main", "Slider")
                    local top = sl and sl:GetAttribute("End")
                    local S = require(RS.Modules.Client.Slider).Sliders
                    for _, o in pairs(S) do pcall(function() o:OverrideValue(top) end) end
                end)
                task.wait(0.3)
                fire(path(prompt, "Main", "OptionsFrame", "Accept"))
            end
            local t1 = os.clock()
            while count(t.bait) == before and os.clock() - t1 < 6 do task.wait(0.2) end
            local got = count(t.bait) - before
            log(string.format("fishing: craft round %d - %s x%d used, +%d %s (prompt %s)", round, best.Name, bestN, got, t.bait, prompt and "yes" or "no"))
            if got <= 0 then break end
            made = made + got
            if count(t.bait) >= 300 then break end
            task.wait(0.6)
        end
        gui.Enabled = false
        task.wait(0.6)
        Fs.crafted = (Fs.crafted or 0) + made
        log(string.format("fishing: crafting done - +%d %s (now %d)", made, t.bait, count(t.bait)))
        return made > 0
    end

    F.cfg.fishKeepLegendary = (F.cfg.fishKeepLegendary == nil) and true or F.cfg.fishKeepLegendary
    if F.cfg.fishAutoSell == nil then F.cfg.fishAutoSell = true end
    if F.cfg.fishAutoCraft == nil then F.cfg.fishAutoCraft = false end
    if not F.cfg.fishCraft or F.cfg.fishCraft == "Off" then F.cfg.fishCraft = "Common" end
    F.cfg.fishSellEvery = F.cfg.fishSellEvery or 20
    F.cfg.fishBait = F.cfg.fishBait or ""
    F.modes.Fishing = {
        order = 5,
        run = function()
            log("fishing: start at " .. A.posText())
            local fails = 0
            local spot = A.root() and A.root().Position
            local soldAt = Fs.wins
            while F.running and F.isAlive() do
                -- every cfg.fishSellEvery catches: sell at the Fish Buyer (when one is on this island), come back
                local every = math.max(F.cfg.fishSellEvery, 5)
                local wantCraft = F.cfg.fishAutoCraft and Fs.sen()
                local wantSell = F.cfg.fishAutoSell and buyer()
                if Fs.wins - soldAt >= every and (wantCraft or wantSell) then
                    soldAt = Fs.wins
                    if wantCraft then Fs.craft(F.cfg.fishCraft) end
                    if wantSell then Fs.sell() end
                    if spot and A.root() and M.flat(A.root().Position, spot) > 4 then
                        setState("back to the fishing spot")
                        M.walkTo(spot, { near = 3 })
                    end
                end
                local h = A.hum()
                if not h or h.Health <= 0 then setState("dead / respawning") task.wait(2)
                else
                    local tool = rod()
                    if not tool then setState("no fishing rod in the backpack") task.wait(3)
                    else
                        if not pickBait() then setState("no bait list") task.wait(3) end
                        local dir, open, wy = waterDir()
                        if not open then
                            setState("no open water within 65 studs of this spot")
                            task.wait(3)
                        else
                            setState("casting")
                            cast(tool, dir, wy)
                            -- the bobble must show up
                            local hk, t0 = nil, os.clock()
                            while not hk and os.clock() - t0 < 5 do hk = hook() task.wait(0.2) end
                            if not hk then
                                Fs.noHook = Fs.noHook + 1
                                fails = fails + 1
                                log(string.format("fishing: no bobble after the cast (click method %d, try %d)", Fs.method, fails))
                                if fails % 2 == 0 then Fs.method = (Fs.method == 1) and 2 or 1 log("fishing: switching click method to " .. Fs.method) end
                                if fails >= 8 then setState("cannot cast here (8 tries) - stopping") F.running = false end
                                task.wait(1.5)
                            else
                                fails = 0
                                setState("waiting for a bite")
                                local w0 = os.clock()
                                local gui
                                while F.running and hk.Parent and os.clock() - w0 < 120 do
                                    gui = LP.PlayerGui:FindFirstChild("FishingUIBill")
                                    if gui or hk:GetAttribute("Caught") then break end
                                    task.wait(0.1)
                                end
                                gui = gui or LP.PlayerGui:FindFirstChild("FishingUIBill") or (hk.Parent and LP.PlayerGui:WaitForChild("FishingUIBill", 3))
                                if gui then
                                    Fs.bites = Fs.bites + 1
                                    setState("fish on - playing the bar")
                                    local res, endFill = playBar(tool, gui)
                                    if (endFill or 0) > 0.85 then Fs.wins = Fs.wins + 1 else Fs.losses = Fs.losses + 1 end
                                    log(string.format("fishing: bite after %.0f s | %s | caught %d, lost %d, casts %d", os.clock() - w0 - 0, res, Fs.wins, Fs.losses, Fs.casts))
                                    task.wait(2.5)
                                else
                                    log(string.format("fishing: no bite (%.0f s, bobble %s) - casting again", os.clock() - w0, hk.Parent and "still out" or "came back"))
                                    click(tool, true) task.wait(0.1) click(tool, false)   -- reel in
                                    task.wait(2)
                                end
                            end
                        end
                    end
                end
                task.wait(0.2)
            end
            log(string.format("fishing: stop | casts %d, bites %d, caught %d, lost %d, no bobble %d", Fs.casts, Fs.bites, Fs.wins, Fs.losses, Fs.noHook))
        end,
    }
end

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

    Q.npcPos = npcPos
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
            if p then return e, "chosen" end      -- v2_27: also on another island (the tick travels there)
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
        -- face the NPC first (turning on the spot)
        pcall(function()
            local r, p = A.root(), npcPos(e.n)
            if r and p then r.CFrame = CFrame.lookAt(r.Position, Vector3.new(p.X, r.Position.Y, p.Z)) end
        end)
        task.wait(0.3)
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
            if d > 1500 then
                -- v2_27: the picked quest is on another island. Known way out of Thriller Bark (found 11-20): the dock,
                -- then west through the gap in the wall, then on the water (the fruit must hold us) to the island.
                -- Two failed trips = back to Auto, so it does not walk the sea for ever.
                setState("travelling to " .. e.n, string.format("%s, %.0f studs", e.q, d))
                local DOCK, OUT = Vector3.new(9445, 15, -7042), Vector3.new(8800, 0, -7042)
                local inside = M.flat(r.Position, DOCK) < 2500 and M.flat(r.Position, OUT) > 250
                local okT, whyT
                if Fi.logiaOn() == true then
                    if inside then
                        M.walkTo(DOCK, { near = 8 })
                        Fi.waterWalk(OUT, { near = 30, limit = 120 })
                    end
                    okT, whyT = Fi.travel(npc, { near = 40 })
                else
                    -- (v2_42) no fruit / Logia off: the sea glide over the local platform, speed from Level > Sea travel
                    if inside then
                        if not (Fi.plat and Fi.plat.on and Fi.plat.over == "water") then M.walkTo(DOCK, { near = 8 }) end
                        Fi.seaGlide(OUT, { near = 25, keep = true, limit = 600 })
                    end
                    okT, whyT = Fi.seaGlide(npc, { near = 40, limit = 3600 })
                end
                local r2 = A.root()
                if not okT and r2 and M.flat(r2.Position, npc) > 1500 then
                    Q.travelFail = (Q.travelFail or 0) + 1
                    log("quest: trip to " .. e.n .. " failed (" .. tostring(whyT) .. "), try " .. Q.travelFail)
                    if Q.travelFail >= 2 then
                        Q.travelFail = 0
                        F.cfg.questPick = ""
                        saveAll()
                        log("quest: two failed trips - quest pick back to Auto")
                    end
                else Q.travelFail = 0 end
                return
            end
            -- (v2_42, owner 20:20: "a switch for taking quests") off = no walk to the NPC, no take: just fight this quest's mobs
            if F.cfg.takeQuest ~= false then
            if d > 5 then
                setState("to NPC " .. e.n, string.format("%s, %.0f studs (%s)", e.q, d, why))
                -- v2_22 (15:49-15:58): after a death it respawned where no path leads to the chosen NPC and tried the
                -- same walk for 9 minutes. Three failed walks to an NPC = skip that quest for 10 minutes.
                local okW = M.walkTo(npc, { near = 3.5 })      -- (v2_42: right up to the NPC - it stopped 7-9 studs short)
                Q.walkFail = Q.walkFail or {}
                if okW then Q.walkFail[e.q] = 0
                else
                    Q.walkFail[e.q] = (Q.walkFail[e.q] or 0) + 1
                    if Q.walkFail[e.q] >= 3 then
                        Q.walkFail[e.q] = 0
                        Q.skip[e.q] = os.clock() + 600
                        log("quest: cannot walk to " .. e.n .. " (3 tries) - skip " .. e.q .. " 10 min")
                    end
                end
                return
            end
            setState("taking " .. e.q)
            if not takeQuest(e) then Q.skip[e.q] = os.clock() + 60 end
            return
            end
        end
        if cur ~= e.q and cur ~= "" and cur ~= "None" then
            -- a quest we do not know (taken by hand, or not a Defeat quest): drop it
            quit("not a quest this mode can do", { q = cur })
            return
        end

        -- fight the quest's mobs
        local cnt, m = mobsOf(e.m, npc or r.Position, 500)
        if not m then
            Q.noMobSince = Q.noMobSince or os.clock()
            local waited = os.clock() - Q.noMobSince
            if waited > 60 and cur ~= "" and cur ~= "None" then Q.noMobSince = nil quit("no " .. e.m .. " for 60 s", e) return end
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

-- session numbers for the Home page (since Start was first pressed in this hub)
local SS = { t0 = nil, peli0 = nil, deaths0 = 0 }
local function ssBegin()
    if SS.t0 then return end
    SS.t0, SS.peli0, SS.deaths0 = os.time(), tonumber(A.stat("Peli")) or 0, F.deaths or 0
end
local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
do
    local start0 = F.start
    F.start = function() ssBegin() return start0() end
end

-- v2_27 window (owner 11-20 18:00: "use the old UI, put the new things into it"; 18:15: quest list on the Level tab).
-- The v1 window as it was - same 8 tabs in the same order, same cards and row names on Home - with the v2
-- systems behind it. Rows of v1 that have no working system in v2 are left out (owner: few buttons, only what is
-- needed); tabs whose mode is not rebuilt yet keep their place and say so in one line.
--   Home      : Run / Status / Account / Session   (v1 cards)
--   Combat    : Attack / Defense / Float           (v1 "Risky" card = the float that now works)
--   Level     : the quest farm (which quest, now)
--   Settings  : server, hub
--   Impel Down, Boss, Raids, Fishing : not rebuilt in v2 yet

-- quests of THIS island for the Quest picker (refreshed every 5 s)
local questNames = { "Auto" }
local questAt = 0
local function questList()
    if os.clock() - questAt < 5 then return questNames end
    questAt = os.clock()
    local r = A.root()
    local names = { "Auto" }
    if r and F.quest and F.quest.npcPos then
        for _, o in ipairs(LOCALQ) do
            if o.a > 1 then
                local p = F.quest.npcPos(o.n)
                if p and (p - r.Position).Magnitude < 1500 then names[#names + 1] = o.q end
            end
        end
    end
    while #questNames > 0 do table.remove(questNames) end
    for i, n in ipairs(names) do questNames[i] = n end
    return questNames
end
-- v2_32 (owner 18:36: "Reload gave an older version"): GitHub serves main/gpo2.lua from a cache for ~5 minutes, so
-- right after a push "main" is still the old file. Reload now asks GitHub for the newest commit id and loads the
-- file of exactly that commit (never cached); gpo2/want.txt (written on this PC at push time) is used first.
local function reloadHub()
    G.__gpo2_dev = nil
    local sha = nil
    pcall(function()
        local w = isfile and isfile(FOLDER .. "/want.txt") and readfile(FOLDER .. "/want.txt") or ""
        sha = w:match("^%s*([0-9a-f]+)%s*$")
    end)
    pcall(function()
        local body = game:HttpGet("https://api.github.com/repos/moseeri01/gpohub/commits?path=gpo2.lua&per_page=1&t=" .. tostring(os.time()))
        local list = HttpService:JSONDecode(body)
        local s = type(list) == "table" and list[1] and list[1].sha
        if type(s) == "string" and #s >= 7 then sha = s end
    end)
    local ref = (sha and #sha >= 7) and sha or "main"
    local ok, src = pcall(function() return game:HttpGet(REPO_RAW .. ref .. "/gpo2.lua?t=" .. tostring(os.time())) end)
    local fn = ok and type(src) == "string" and #src > 1000 and loadstring(src) or nil
    if fn then
        if ref ~= "main" then G.__gpo2_commit = ref end
        log("reload: loading " .. ref:sub(1, 7))
        flushLog()
        task.spawn(fn)
    else notify("reload failed") end
end
-- "Stop after (hours)" from v1: counts from the first Start of this hub
task.spawn(function()
    while F.isAlive() do
        task.wait(20)
        if F.running and SS.t0 and os.time() - SS.t0 > F.cfg.stopHours * 3600 then
            log("stop: ran " .. F.cfg.stopHours .. " h (Home: Stop after)")
            F.stop()
        end
    end
end)

-- 1 Home (v1 layout)
local home = UI.page("Home", 1)
local run = UI.card(home, 1, "Run")
-- Start / Stop runs the mode chosen in the next row; OFF stops whatever runs (quests, fishing, a test)
UI.toggle(run, "Start / Stop", function() return F.running end, function(on)
    if on then
        if F.cfg.mode ~= "Quest" and F.cfg.mode ~= "Fishing" then F.cfg.mode = "Quest" end
        F.start()
    else F.stop() end
end)
UI.choice(run, "Mode", { "Quest", "Fishing" }, function() return (F.cfg.mode == "Fishing") and "Fishing" or "Quest" end, function(v)
    if F.running then F.stop() end
    F.cfg.mode = v
    saveAll()
end)
UI.stepper(run, "Stop after (hours)", 1, 24, cfgGet("stopHours"), cfgSet("stopHours"))
UI.toggle(run, "Keep Start on after a teleport", cfgGet("autoStart"), cfgSet("autoStart"))
UI.toggle(run, "Reload hub after a teleport", cfgGet("reloadOnTeleport"), cfgSet("reloadOnTeleport"))
UI.button(run, "Reload hub (newest version)", "Reload", reloadHub)
UI.button(run, "Close hub", "Close", function() F.close() end)

local stat = UI.card(home, 2, "Status")
UI.info(stat, "Now", function() return F.running and (F.quest and F.quest.state ~= "-" and F.quest.state or F.status) or "stopped" end)
UI.info(stat, "Quest", function() local qn, p = A.quest() return (qn ~= "" and qn ~= "None") and (qn .. "  " .. p) or "none" end)
UI.info(stat, "Last action", function() return F.lastAction end)
UI.info(stat, "Version", function() return VERSION .. (G.__gpo2_dev and " (test build)" or "") end)

local acc = UI.card(home, 1, "Account")
UI.info(acc, "Player", function() return LP.Name end)
UI.info(acc, "Level / Peli", function() return "Lv " .. A.level() .. "   Peli " .. comma(A.stat("Peli")) end)
UI.info(acc, "Fruit / style / race", function()
    return tostring(A.stat("DF") or "-") .. " / " .. tostring(A.stat("FightingStyle") or "-") .. " / " .. tostring(A.stat("Race", "Customization") or "-")
end)
UI.info(acc, "Stats", function()
    return "Str " .. tostring(A.stat("Strength") or 0) .. "  Def " .. tostring(A.stat("Defense") or 0) .. "  Stam " .. tostring(A.stat("Stamina") or 0)
        .. "  DF " .. tostring(A.stat("DevilFruitMastery") or 0)
end)
UI.info(acc, "Points", function() return "free points " .. tostring(A.stat("SkillPoints") or 0) end)

local ses = UI.card(home, 2, "Session")
UI.info(ses, "Time farming", function()
    if not SS.t0 then return "-" end
    local s = os.time() - SS.t0
    return string.format("%d h %02d min", s / 3600, s % 3600 / 60)
end)
UI.info(ses, "Quests done", function() return F.quest and F.quest.done or 0 end)
UI.info(ses, "Peli earned", function()
    if not SS.peli0 then return "-" end
    local gain = (tonumber(A.stat("Peli")) or 0) - SS.peli0
    local hrs = math.max((os.time() - SS.t0) / 3600, 1 / 60)
    return "+" .. comma(gain) .. "  (" .. comma(gain / hrs) .. " / h)"
end)
UI.info(ses, "Deaths", function() return (F.deaths or 0) - SS.deaths0 end)

-- 2 Combat (v1: Attack / Defense / Risky)
local cb = UI.page("Combat", 3)
local fa = UI.card(cb, 1, "Attack")
UI.toggle(fa, "Use skills", cfgGet("useSkills"), cfgSet("useSkills"))
local fd = UI.card(cb, 2, "Defense")
UI.toggle(fd, "Auto block", cfgGet("autoBlock"), cfgSet("autoBlock"))
UI.stepper(fd, "Retreat below HP %", 10, 80, cfgGet("retreatHp"), cfgSet("retreatHp"), 5)
local fl = UI.card(cb, 2, "Float")
UI.toggle(fl, "Hover above target", cfgGet("hover"), cfgSet("hover"))
UI.stepper(fl, "Hover height", 3, 10, cfgGet("hoverHeight"), cfgSet("hoverHeight"))
UI.slider(fl, "Hover speed", 8, 60, cfgGet("hoverSpeed"), cfgSet("hoverSpeed"), " /s")
UI.info(fl, "Pulled back / game notices", function() return (F.fight.hv.pulls or 0) .. "  /  " .. ((F.guardNotes or 0) + (F.strikes or 0)) end)
UI.note(fl, "Speed 15 is the tested safe value. If the counters go up, that speed is too fast.")

-- 3-6 modes of v1 that are not rebuilt in v2 yet: the tab stays, one line says so
for i, name in ipairs({ "Impel Down", "Boss", "Raids" }) do
    local pg = UI.page(name, 3 + i)
    local c = UI.card(pg, 1, name)
    UI.note(c, "Not rebuilt in v2 yet. The old hub (v1) still has this page.")
end

-- 7 Fishing (v2_31, owner 18:35: "make the fishing page - I cannot turn it off")
local fpg = UI.page("Fishing", 7)
local fc = UI.card(fpg, 1, "Fishing")
UI.toggle(fc, "Fish here (on / off)", function() return F.running and F.cfg.mode == "Fishing" end, function(on)
    if on then
        if F.running then F.stop() task.wait(0.4) end
        F.cfg.mode = "Fishing"
        F.start()
    else
        F.stop()
    end
end)
UI.info(fc, "Doing now", function() return (F.running and F.cfg.mode == "Fishing") and (F.fishing.state or "-") or "stopped" end)
local BAITS = { Auto = "", Common = "Common Fish Bait", Rare = "Rare Fish Bait", Legendary = "Legendary Fish Bait" }
UI.dropdown(fc, "Bait to use", 112, function()
    return { { key = "", text = "Auto  -  first bait I have" }, { key = "Common Fish Bait", text = "Common Fish Bait" },
        { key = "Rare Fish Bait", text = "Rare Fish Bait" }, { key = "Legendary Fish Bait", text = "Legendary Fish Bait" } }
end, function() return F.cfg.fishBait end, function(k) F.cfg.fishBait = k saveAll() end)
UI.info(fc, "Bait: Common / Rare / Legendary", function()
    local c = F.fishing.count
    if not c then return "-" end
    return c("Common Fish Bait") .. " / " .. c("Rare Fish Bait") .. " / " .. c("Legendary Fish Bait")
end)
UI.note(fc, "Stand next to open water with a rod and bait, then switch on. It casts, waits and plays the catch bar by itself.")
local fsell = UI.card(fpg, 1, "Selling")
UI.toggle(fsell, "Auto sell", cfgGet("fishAutoSell"), cfgSet("fishAutoSell"))
UI.stepper(fsell, "Go after this many fish", 5, 40, cfgGet("fishSellEvery"), cfgSet("fishSellEvery"), 5)
UI.toggle(fsell, "Keep legendary fish", cfgGet("fishKeepLegendary"), cfgSet("fishKeepLegendary"))
UI.button(fsell, "Sell now", "Sell", function() F.fishing.sell() end)
UI.note(fsell, "Selling needs a Fish Buyer on this island.")
local fcr = UI.card(fpg, 2, "Bait crafting")
UI.toggle(fcr, "Auto craft", cfgGet("fishAutoCraft"), cfgSet("fishAutoCraft"))
UI.dropdown(fcr, "Bait to craft", 84, function()
    return { { key = "Common", text = "Common Fish Bait  (1 common fish)" },
        { key = "Rare", text = "Rare Fish Bait  (2 rare fish)" }, { key = "Legendary", text = "Legendary Fish Bait  (1 legendary fish)" } }
end, function() return F.cfg.fishCraft end, function(k) F.cfg.fishCraft = k saveAll() end)
UI.button(fcr, "Craft now", "Craft", function() task.spawn(F.fishing.craft, F.cfg.fishCraft) end)
UI.info(fcr, "Crafted this session", function() return F.fishing.crafted or 0 end)
UI.note(fcr, "Needs Blacksmith Sen on this island. With Auto craft on, fish of the picked level are kept for bait (max 300), the rest is sold. The game has no bait shop in this sea: bait only comes from crafting.")
local fst = UI.card(fpg, 2, "This session")
UI.info(fst, "Caught / lost", function() return (F.fishing.wins or 0) .. "  /  " .. (F.fishing.losses or 0) end)
UI.info(fst, "Casts", function() return F.fishing.casts or 0 end)
UI.info(fst, "Peli from selling", function() return "+" .. comma(F.fishing.soldPeli or 0) end)

-- 7 Level (the quest farm)
local lv = UI.page("Level", 2)          -- v2_28: right after Home (owner)
local lq = UI.card(lv, 1, "Level farm")
-- v2_27 (owner 18:15: "show the list in order; the one I pick, go there and farm it"): every quest of this sea the
-- hub can do, sorted by its level, one click = pick. A quest on another island makes the hub travel there first.
local QEXP = { ["Help Abdul"] = 10000, ["Help Anty"] = 700, ["Help Vi"] = 2000, ["Help Waby"] = 750, ["Help Rice"] = 525, ["Deliver Bean Coffee"] = 800, ["Help Nami"] = 1200, ["Help Captain Malik"] = 700, ["Deliver Civilian Cargo"] = 800, ["Help crim"] = 1000, ["Help Dabo"] = 3000, ["Help Mythra"] = 7000, ["Help Fhan"] = 4000, ["Help becky"] = 2800, ["Help janny"] = 3000, ["Help jenny"] = 1500, ["Deliver to Snaytona"] = 1000, ["Help Miska"] = 2600, ["Help Yourg"] = 1800, ["Help Zanny"] = 3000, ["Deliver to Ego"] = 150, ["Help Admiral Frosty"] = 6000, ["Help Frutose"] = 9000, ["Help Higa"] = 4200, ["Help Pichu"] = 1200, ["Help Wane"] = 2800, ["Help Zhen's Crewmate"] = 4500, ["Help Zen"] = 400, ["Deliver letter to Dave"] = 20, ["Help Admiral Jackson"] = 50000, ["Help Ian"] = 35000, ["Help Marine Scout Milli"] = 55000, ["Help Niki"] = 30000, ["Help PJ"] = 12000, ["Gear2"] = 2000, ["Help Somi"] = 60000, ["Help Warren"] = 40000, ["Help Samira"] = 10000, ["Help Noah"] = 125, ["Find Tina's Clay pot"] = 15, ["Take down Lucid"] = 200, ["hunt egirl"] = 4500, ["Serve Justice"] = 800, ["Help Kevin"] = 200, ["Help Robert"] = 175, ["Find Tysoncat"] = 45, ["Help bibby"] = 1200, ["Help jeff"] = 2000, ["Help musk"] = 1100, ["Help rae"] = 1800, ["Help raze"] = 1400, ["Help vego"] = 750, ["Help viva"] = 1900, ["Help zhen"] = 1700, ["Help gonny"] = 650, ["Help max"] = 800, ["Help Daph"] = 60, ["Help Ronny"] = 80, ["Find Sarah's necklace"] = 90, ["Help Admiral Yon"] = 20000, ["Help Eli"] = 12000, ["Help Jag"] = 12000, ["Help Marine Scout Rae"] = 10000, ["Help Mur"] = 2000, ["Help Poro"] = 800, ["Help Vak"] = 700, ["Deliver water to Devontai"] = 100, ["Free the Captive"] = 18000, ["Shatter the Mirror"] = 30000, ["Clear the Chess Guards"] = 25000, ["End Big Mama"] = 45000, ["Guard at the Glass"] = 25000, ["The Forest Outcast"] = 20000, ["Help Zaki"] = 700, ["Help Zerus"] = 2500 }
-- v2_39 (owner 19:52: "easier to read when picking"): this island first, other islands under their own header,
-- two lines per quest (level + name / mob x amount), EXP or the distance at the right, quests above our level dimmed
local function questRows()
    local rows = { { key = "", text = "Auto  -  best quest on this island" } }
    if not (F.quest and F.quest.npcPos) then return rows end
    local r = A.root()
    local lvl = tonumber(A.level()) or 0
    local here, far = {}, {}
    for _, o in ipairs(LOCALQ) do
        if o.a > 1 and o.m ~= "Kraken" then          -- ("Help Anty / Kraken x3" is a misread awakening step)
            local p = F.quest.npcPos(o.n)
            if p then
                local lvFrom, lvTo = 999, 999
                for _, s in ipairs(ROUTE) do if s.q == o.q then lvFrom, lvTo = s.f, s.t break end end
                local dist = r and (p - r.Position).Magnitude or 0
                local lvText = lvFrom < 999 and ("Lv " .. lvFrom .. "-" .. lvTo) or "Side"
                local it = { f = lvFrom, key = o.q, text = lvText .. "   " .. o.q, short = lvText .. "  " .. o.q, sub = o.m .. " x" .. o.a,
                    dim = lvFrom < 999 and lvFrom > lvl }
                if dist > 1500 then
                    it.right = comma(math.floor(dist / 100 + 0.5) * 100) .. " studs away"
                    far[#far + 1] = it
                else
                    it.right = QEXP[o.q] and (comma(QEXP[o.q]) .. " EXP") or nil
                    here[#here + 1] = it
                end
            end
        end
    end
    local function byLv(a, b) return a.f < b.f end
    table.sort(here, byLv)
    table.sort(far, byLv)
    if #here > 0 then rows[#rows + 1] = { header = true, text = "THIS ISLAND" } end
    for _, it in ipairs(here) do rows[#rows + 1] = it end
    if #far > 0 then rows[#rows + 1] = { header = true, text = "OTHER ISLANDS  (travel first)" } end
    for _, it in ipairs(far) do rows[#rows + 1] = it end
    return rows
end
UI.dropdown(lq, "Quest", 300, questRows, function() return F.cfg.questPick end, function(key)
    F.cfg.questPick = key
    saveAll()
    log("quest picked in the window: " .. (key == "" and "Auto" or key))
end)
UI.toggle(lq, "Take quests", function() return F.cfg.takeQuest ~= false end, function(on) F.cfg.takeQuest = on saveAll() end)
UI.note(lq, "Off = no walk to the NPC: it only fights the mobs of the picked quest (Auto = the best quest of this island).")
local ln = UI.card(lv, 2, "Now")
UI.info(ln, "Picked", function() return F.cfg.questPick == "" and "Auto" or F.cfg.questPick end)
UI.info(ln, "Step", function() return F.quest and F.quest.state or "-" end)
UI.info(ln, "Skipped for now", function()
    local n = 0
    for _, t in pairs(F.quest and F.quest.skip or {}) do if t > os.clock() then n = n + 1 end end
    return n
end)

-- Sea travel (v2_35, owner 19:05: "make the button first"): walk ON the water to a place. Only places that were
-- reached in game are listed (the way out of Thriller Bark, Rose Kingdom) + the NPC of the quest picked on this page.
-- Needs a fruit that stands on water (Logia). Runs as mode "Move test" with the same pieces as the remote commands.
local SEA = { key = "out" }
local SEA_DOCK, SEA_OUT = Vector3.new(9445, 15, -7042), Vector3.new(8800, 0, -7042)
local SEA_PLACES = {
    { key = "out", text = "Thriller Bark (gap in the wall)", pos = Vector3.new(8800, 0, -7042) },
    { key = "rose", text = "Rose Kingdom", pos = Vector3.new(6953, 63, 9940) },
    { key = "quest", text = "NPC of the picked quest" },
}
local function seaGo()
    local r = A.root()
    if not r then return end
    local goal, name = nil, ""
    for _, pl in ipairs(SEA_PLACES) do if pl.key == SEA.key then goal, name = pl.pos, pl.text end end
    if SEA.key == "quest" then
        goal = nil
        for _, o in ipairs(LOCALQ) do
            if o.q == F.cfg.questPick and F.quest and F.quest.npcPos then goal = F.quest.npcPos(o.n) name = o.n end
        end
        if not goal then SEA.msg = "pick a quest in the list first (not Auto)" notify("Pick a quest in the list first (not Auto)") return end
    end
    local list = {}
    -- inside the wall of Thriller Bark: the dock first, then west through the gap
    if M.flat(r.Position, SEA_DOCK) < 2500 and M.flat(r.Position, SEA_OUT) > 250 then
        -- (v2_43: already on the water = no walk back to the dock first; that walk was the slow part the owner saw)
        local pl = F.fight.plat
        if not (pl and pl.on and pl.over == "water") then list[#list + 1] = { pos = SEA_DOCK, name = "Thriller Bark dock" } end
        list[#list + 1] = { pos = SEA_OUT, name = "gap in the wall", sea = true, keep = true, near = 25, limit = 600 }
    end
    -- (v2_40: from inside the wall the gap is already in the list; from anywhere else the goal itself is the trip)
    if goal and not (SEA.key == "out" and #list > 0) then
        if M.flat(r.Position, goal) < 60 then SEA.msg = "already there" notify("Already there") return end
        list[#list + 1] = { pos = goal, name = name, sea = true, near = SEA.key == "out" and 25 or 6, limit = 3600 }
    end
    list[#list].keep = nil
    SEA.msg = nil
    SEA.goal, SEA.name = list[#list].pos, list[#list].name
    log("sea travel (window): " .. SEA.name)
    task.spawn(function()
        if F.running then F.stop() task.wait(0.4) end
        F.moveList = list
        F.cfg.mode = "Move test"
        F.start()
    end)
end
local st = UI.card(lv, 2, "Sea travel")
UI.dropdown(st, "Go to", 84, function() return SEA_PLACES end, function() return SEA.key end, function(k) SEA.key = k end)
-- (owner 20:12: "make it something I can switch on and off") the platform itself; Cross the water switches it on too
UI.toggle(st, "Stand on water", function() return F.fight.plat.on end, function(on)
    if on then F.fight.platOn() F.cfg.plat = true saveAll() SEA.msg = nil
    else
        local ok, why = F.fight.platOff()
        if ok then F.cfg.plat = false saveAll() SEA.msg = nil else SEA.msg = why notify("Cannot switch off: " .. tostring(why)) end
    end
end)
-- (owner 19:03: "an on / off switch is better")
UI.toggle(st, "Cross the water", function() return F.running and F.cfg.mode == "Move test" end, function(on)
    if on then seaGo() elseif F.running and F.cfg.mode == "Move test" then F.stop() end
end)
UI.slider(st, "Speed", 15, 60, cfgGet("seaSpeed"), cfgSet("seaSpeed"), " /s")
UI.info(st, "Now", function()
    if not (F.running and F.cfg.mode == "Move test") then return SEA.msg or "not travelling" end
    local r = A.root()
    return (SEA.name or "-") .. (r and SEA.goal and string.format("   %d studs left", M.flat(r.Position, SEA.goal)) or "")
end)
UI.note(st, "Glides low over the sea on a platform only you have - works without a fruit. Speed 15 is the tested value; faster is at your own risk. After arriving, switch Start on again on Home.")

-- 8 Settings
local set = UI.page("Settings", 8)
local sv = UI.card(set, 1, "Private server")
UI.input(sv, "Code", "code from the game menu", function() return F.cfg.privateCode end, function(v)
    if type(v) == "string" then F.cfg.privateCode = (v:gsub("%s", "")) saveAll() end
end)
UI.toggle(sv, "Auto rejoin", cfgGet("autoRejoin"), cfgSet("autoRejoin"))
local mv = UI.card(set, 2, "Moving")
UI.toggle(mv, "Sprint (hold W)", cfgGet("sprint"), cfgSet("sprint"))
UI.note(mv, "Right Ctrl hides / shows this window.")

-- toggle key: the ··· button hides the window, RightControl shows / hides it
dots.MouseButton1Click:Connect(function() win.Visible = false notify("RightControl shows the window") end)
F.conns[#F.conns + 1] = UIS.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.RightControl then win.Visible = not win.Visible end
end)

gui.Parent = guiParent
UI.show("Home")
task.spawn(function()
    while F.isAlive() do
        if win.Visible then
            -- (v2_34: one line in the log for a row that fails, and for the first full pass - rows stayed empty in v2_33)
            for i, f in ipairs(UI.refreshers) do
                UI.refreshAt = i
                local ok, err = xpcall(f, debug.traceback)
                UI.refreshBad = UI.refreshBad or {}
                if not ok and not UI.refreshBad[i] then UI.refreshBad[i] = true log("ui: row " .. i .. " of " .. #UI.refreshers .. " failed: " .. tostring(err):sub(1, 400)) end
            end
            if not UI.refreshDone then UI.refreshDone = true log("ui: first full refresh, " .. #UI.refreshers .. " rows") end
        end
        task.wait(0.5)
    end
end)
log("window ready")


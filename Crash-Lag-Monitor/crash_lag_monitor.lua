-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- Crash Guard v2.0
-- by Sam Wilson
--
-- WHAT THIS ACTUALLY DOES (read this first):
-- This does NOT raise the game's streaming-memory limit - that's
-- what fastman92 Limit Adjuster's [STREAMING] section is for, and
-- you should keep that fix in place. This script is a SEPARATE,
-- complementary layer:
--   1. Counts vehicles of the same model near you in real time and
--      warns you in chat BEFORE you likely hit the crash threshold,
--      instead of crashing with zero warning.
--   2. Watches your FPS for a sudden drop WHILE vehicle counts are
--      already elevated - a second, independent signal, since a
--      crash is sometimes preceded by a stutter as the engine
--      struggles to keep up, even if vehicle count alone hasn't
--      crossed the warning line yet.
--   3. Keeps a persistent log of every warning that's fired, so you
--      can review afterward which model/count combination preceded
--      a crash, instead of relying on memory.
--   4. Watches moonloader.log for OTHER scripts dying or failing to
--      load, and alerts you immediately in chat when it happens.
--      IMPORTANT CONTEXT: MoonLoader already isolates Lua scripts
--      from each other - if one script errors, it stops itself and
--      logs it, but does NOT crash the game or other scripts (that's
--      only true of CLEO scripts). This feature can't reach into
--      another script and fix its bug - no MoonLoader script can do
--      that to another. What it CAN do is turn "a script silently
--      died and you find out eventually" into "you're told the
--      moment it happens", by reading the same log file MoonLoader
--      already writes.
--   5. Manages Lua's OWN memory (garbage collection) - this is a
--      small, separate pool from the game engine's asset/streaming
--      memory. It genuinely helps Lua run leaner, but it is NOT
--      the fix for the vehicle-crash issue - that's the ini.
-- It cannot stop a crash from a hard engine limit - it gives you
-- an early, two-signal warning, keeps a record of what led up to
-- past warnings, and keeps the Lua side of things clean.
--
-- Commands:
--   /cgstatus          show current same-model vehicle counts + FPS
--   /cgthreshold <n>   set how many same-model vehicles trigger
--                      a warning (default 5)
--   /cgclean            force an immediate deep garbage-collection
--                      pass and report how much Lua memory it freed
--   /cgmenu             open the settings/status window
--   /cglog              show the last warnings from the persistent log
--------------------------------------------------------------
script_name("Crash Guard")
script_author("Sam Wilson")
script_version("2.0")
--------------------------------------------------------------

local imgui = require("imgui")

local WARN_THRESHOLD   = 5      -- same-model vehicle count that triggers a warning
local CHECK_INTERVAL    = 5000   -- ms between vehicle-count checks
local GC_INTERVAL        = 15000  -- ms between incremental GC steps
local WARN_COOLDOWN      = 20000  -- ms - don't repeat the same warning faster than this
local FPS_DROP_RATIO     = 0.5    -- warn if FPS falls below this fraction of its recent average
local FPS_SAMPLE_WINDOW  = 10     -- how many recent FPS samples to average

local lastWarnTime = {} -- [modelId] = NowSeconds() of last warning, to avoid spam
local fpsHistory    = {} -- rolling window of recent frame-time-derived FPS samples
-- Game time advances independently of how much CPU time this script consumes.
-- NowSeconds() is process CPU time and is not suitable for frame-interval timing.
local function NowSeconds()
    return getGameTimer() / 1000
end

local lastFrameTime = NowSeconds()
local currentFPS    = 60

-- FIX: a slow-moving baseline, separate from `currentFPS` (which is already the
-- short windowed average). The drop check needs something to compare a dip
-- AGAINST - comparing the already-smoothed `currentFPS` to a hardcoded "60"
-- ignored the user's actual typical framerate entirely (someone normally at
-- 200 FPS never got warned until below 30; someone normally at 35 FPS was
-- permanently flagged even with zero real drop). This baseline updates slowly
-- (small alpha) so a sudden dip shows up clearly against it. Verified with a
-- real Lua run: a simulated drop from a 150fps baseline to a sustained 70fps
-- (53% real drop) was NOT detected by the old fixed-60 comparison, but IS
-- detected correctly against this baseline; a stable 35fps baseline with zero
-- actual drop correctly stays silent in both versions.
local baselineFPS    = 60
local baselineReady  = false -- true once the sample window has filled once
local BASELINE_ALPHA = 0.02  -- slow-moving: ~50 samples to mostly converge
local monitoringOn  = imgui.ImBool(true)
local windowOpen    = imgui.ImBool(false)
local thresholdBox  = imgui.ImInt(WARN_THRESHOLD)

local LOG_FILE = getGameDirectory() .. "/moonloader/CrashGuard_log.txt"

--------------------------------------------------------------
-- Persistent warning log. Every write is guarded - if the file can't
-- be opened for any reason, logging is skipped silently rather than
-- erroring, since a logging failure should never be able to take
-- down the actual monitoring this tool exists to do.
--------------------------------------------------------------
local function LogWarning(line)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. line .. "\n")
        f:close()
    end
end

local function ReadRecentLog(maxLines)
    local f = io.open(LOG_FILE, "r")
    if not f then return {} end

    local all = {}
    for line in f:lines() do
        table.insert(all, line)
    end
    f:close()

    local out = {}
    local startIdx = math.max(1, #all - maxLines + 1)
    for i = startIdx, #all do
        table.insert(out, all[i])
    end
    return out
end

--------------------------------------------------------------
-- Count vehicles in a bounded sphere around the local character.
-- MoonLoader exposes findAllRandomVehiclesInSphere(pos, radius,
-- findNext, passWrecked); the first call uses findNext=false and
-- subsequent calls use true until the native reports no more cars.
--------------------------------------------------------------
local VEHICLE_SCAN_RADIUS = 250 -- world units around the local character
local MAX_VEHICLES_PER_SCAN = 512

local function CountVehiclesByModel()
    local counts = {}
    local total = 0

    if type(getCharCoordinates) ~= "function"
        or type(findAllRandomVehiclesInSphere) ~= "function"
        or type(getCarModel) ~= "function" then
        return counts, total, false
    end

    local posOk, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if not posOk or type(x) ~= "number"
        or type(y) ~= "number" or type(z) ~= "number" then
        return counts, total, false
    end

    local findOk, found, vehicle = pcall(
        findAllRandomVehiclesInSphere,
        x, y, z, VEHICLE_SCAN_RADIUS, false, true
    )
    if not findOk then
        return counts, total, false
    end

    local seen = {}
    local scanned = 0
    while found and vehicle and vehicle ~= -1
        and scanned < MAX_VEHICLES_PER_SCAN do
        -- A defensive duplicate guard prevents a broken iterator from
        -- creating an endless loop inside a monitoring pass.
        if seen[vehicle] then break end
        seen[vehicle] = true
        scanned = scanned + 1

        local modelOk, model = pcall(getCarModel, vehicle)
        if modelOk and type(model) == "number" then
            counts[model] = (counts[model] or 0) + 1
            total = total + 1
        end

        local nextOk
        nextOk, found, vehicle = pcall(
            findAllRandomVehiclesInSphere,
            x, y, z, VEHICLE_SCAN_RADIUS, true, true
        )
        if not nextOk then
            return counts, total, false
        end
    end

    return counts, total, true
end

--------------------------------------------------------------
-- FPS tracking - pure timing math, no new natives needed. Each call
-- records the time since the last call as one frame, keeps a rolling
-- window of samples, and reports both the instantaneous and the
-- windowed-average FPS.
--------------------------------------------------------------
local function UpdateFPS()
    local now = NowSeconds()
    local delta = now - lastFrameTime
    lastFrameTime = now

    if delta <= 0 then return end
    local instantFPS = 1 / delta

    table.insert(fpsHistory, instantFPS)
    if #fpsHistory > FPS_SAMPLE_WINDOW then
        table.remove(fpsHistory, 1)
    end

    local sum = 0
    for _, v in ipairs(fpsHistory) do sum = sum + v end
    currentFPS = sum / #fpsHistory

    if not baselineReady then
        -- Warm-up: seed the baseline from the first full window instead of
        -- drifting slowly up from the arbitrary 60, which would give wrong
        -- comparisons for the first several seconds of every session.
        if #fpsHistory >= FPS_SAMPLE_WINDOW then
            baselineFPS   = currentFPS
            baselineReady = true
        end
    else
        baselineFPS = baselineFPS + (currentFPS - baselineFPS) * BASELINE_ALPHA
    end
end

--------------------------------------------------------------
-- Script Watchdog - tails moonloader.log and alerts when another
-- script dies or fails to load. Read-only: this only ever reads that
-- log file, never touches any other script's own file.
--------------------------------------------------------------
local ML_LOG_CANDIDATES = {
    getGameDirectory() .. "/moonloader.log",
    getGameDirectory() .. "/moonloader/moonloader.log",
}

local mlLogPath = nil
local mlLogLastLineCount = 0
local recentScriptDeaths = {} -- most recent first, for the UI list
local watchdogOn = imgui.ImBool(true)

local function FindMoonloaderLog()
    for _, candidate in ipairs(ML_LOG_CANDIDATES) do
        if doesFileExist(candidate) then
            return candidate
        end
    end
    return nil
end

-- Reads moonloader.log, returns only the lines added since the last
-- call (by comparing total line counts - simple and safe, no seek/
-- partial-read complexity, acceptable since this file is read
-- periodically, not on every tick).
local function ReadNewLogLines()
    if not mlLogPath then
        mlLogPath = FindMoonloaderLog()
        if not mlLogPath then return {} end
    end

    local f = io.open(mlLogPath, "r")
    if not f then return {} end

    local all = {}
    for line in f:lines() do
        table.insert(all, line)
    end
    f:close()

    local newLines = {}
    if #all > mlLogLastLineCount then
        for i = mlLogLastLineCount + 1, #all do
            table.insert(newLines, all[i])
        end
    end
    mlLogLastLineCount = #all
    return newLines
end

local function CheckOtherScriptsHealth()
    local newLines = ReadNewLogLines()
    for _, line in ipairs(newLines) do
        local diedScript = line:match("%(error%)%s*([^:]+):%s*Script died due to an error")
        local missingLib = line:match("no file '.-moonloader[\\/](.-)%.lua'")

        if diedScript then
            local msg = "Script crashed: " .. diedScript
            sampAddChatMessage("{FF4444}[CrashGuard/Watchdog]{FFFFFF} " .. msg, -1)
            LogWarning("watchdog: " .. msg)
            table.insert(recentScriptDeaths, 1, msg)
            if #recentScriptDeaths > 20 then table.remove(recentScriptDeaths) end
        elseif missingLib then
            local msg = "Missing dependency: " .. missingLib
            sampAddChatMessage("{FFAA00}[CrashGuard/Watchdog]{FFFFFF} " .. msg, -1)
            LogWarning("watchdog: " .. msg)
            table.insert(recentScriptDeaths, 1, msg)
            if #recentScriptDeaths > 20 then table.remove(recentScriptDeaths) end
        end
    end
end

--------------------------------------------------------------
-- Chat commands
--------------------------------------------------------------
local function RegisterCommands()
    sampRegisterChatCommand("cgstatus", function()
        local counts, total, scanAvailable = CountVehiclesByModel()
        if not scanAvailable then
            sampAddChatMessage("{FFAA00}[CrashGuard]{FFFFFF} Nearby vehicle scan is unavailable in this host build.", -1)
            return
        end
        local luaMemKB = collectgarbage("count")

        sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} " .. total ..
            " vehicles found within " .. VEHICLE_SCAN_RADIUS ..
            " units. FPS: " .. string.format("%.0f", currentFPS), -1)
        sampAddChatMessage("{FFFFFF}  Lua memory: " .. string.format("%.1f", luaMemKB / 1024) .. " MB (small - this is not the streaming/engine memory).", -1)

        local shown = 0
        for model, count in pairs(counts) do
            if count >= 2 then
                local color = (count >= WARN_THRESHOLD) and "{FF4444}" or "{FFFFFF}"
                sampAddChatMessage(color .. "  Model " .. model .. ": " .. count .. " within scan radius", -1)
                shown = shown + 1
            end
        end
        if shown == 0 then
            sampAddChatMessage("{FFFFFF}  No model has 2+ copies within the scan radius.", -1)
        end
    end)

    sampRegisterChatCommand("cgthreshold", function(arg)
        -- FIX: validate AFTER flooring. The old order (check "n > 0" first, then
        -- floor) let "0.5" through: 0.5 > 0 passes, math.floor(0.5) is 0, and a
        -- threshold of 0 makes EVERY loaded vehicle model trigger a warning.
        local n = tonumber(arg)
        local floored = n and math.floor(n)
        if floored and floored > 0 then
            WARN_THRESHOLD = floored
            -- FIX: keep the GUI input box in sync - it was only ever written by
            -- the GUI itself, so a threshold changed via chat left the settings
            -- window showing the old number until the user touched the box.
            thresholdBox.v = WARN_THRESHOLD
            sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} Warning threshold set to " .. WARN_THRESHOLD .. ".", -1)
        else
            sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} Usage: /cgthreshold <number>  (current: " .. WARN_THRESHOLD .. ")", -1)
        end
    end)

    sampRegisterChatCommand("cgclean", function()
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        local freedKB = before - after
        sampAddChatMessage(
            "{FFFF00}[CrashGuard]{FFFFFF} Freed " .. string.format("%.1f", freedKB / 1024) ..
            " MB of Lua memory. (Small pool - won't fix engine-level vehicle crashes.)",
            -1
        )
    end)

    sampRegisterChatCommand("cgmenu", function()
        windowOpen.v = not windowOpen.v
        imgui.Process = windowOpen.v
    end)

    sampRegisterChatCommand("cgwatchdog", function()
        watchdogOn.v = not watchdogOn.v
        sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} Other-script watchdog: " ..
            (watchdogOn.v and "ON" or "OFF"), -1)
    end)

    sampRegisterChatCommand("cglog", function()
        local lines = ReadRecentLog(10)
        if #lines == 0 then
            sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} No warnings logged yet.", -1)
            return
        end
        sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} Last " .. #lines .. " logged warning(s):", -1)
        for _, line in ipairs(lines) do
            sampAddChatMessage("{FFFFFF}  " .. line, -1)
        end
    end)
end

--------------------------------------------------------------
function main()
    while not isSampAvailable() do wait(100) end

    RegisterCommands()
    sampAddChatMessage("{FFFF00}[CrashGuard]{FFFFFF} Active. Warns at " .. WARN_THRESHOLD ..
        "+ vehicles of the same model, watches other scripts for crashes. " ..
        "/cgstatus /cgthreshold /cgclean /cgmenu /cglog /cgwatchdog", -1)

    -- Tune the collector to run more incrementally instead of one
    -- big stop-the-world pass, so it doesn't cause a hitch.
    pcall(function()
        collectgarbage("setpause", 100)
        collectgarbage("setstepmul", 400)
    end)

    local checkTimer = NowSeconds()
    local gcTimer     = NowSeconds()
    local watchdogTimer = NowSeconds()
    lastFrameTime     = NowSeconds() -- reset here, not at script-load time,
                                     -- since isSampAvailable() can take a
                                     -- while and would otherwise skew the
                                     -- very first FPS sample

    -- Prime the watchdog with the log's current size so it only
    -- reports NEW script deaths from this point on, not every script
    -- that ever died in a previous session.
    pcall(ReadNewLogLines)

    while true do
        wait(0)

        UpdateFPS()

        if isSampAvailable() and monitoringOn.v then
            -- Vehicle-count early warning
            if NowSeconds() - checkTimer > (CHECK_INTERVAL / 1000) then
                checkTimer = NowSeconds()

                pcall(function()
                    local counts, total, scanAvailable = CountVehiclesByModel()
                    if not scanAvailable then return end
                    for model, count in pairs(counts) do
                        if count >= WARN_THRESHOLD then
                            local last = lastWarnTime[model] or 0
                            if NowSeconds() - last > (WARN_COOLDOWN / 1000) then
                                lastWarnTime[model] = NowSeconds()

                                -- Second signal: is FPS already noticeably
                                -- down from its recent average? If so this
                                -- is a stronger warning - a stutter plus a
                                -- high count is a worse sign than either
                                -- alone.
                                -- FIX: compare against the user's own slow-moving
                                -- baseline, not a hardcoded 60 (see note above UpdateFPS).
                                local fpsLow = baselineReady and currentFPS < (baselineFPS * FPS_DROP_RATIO)
                                local msg = (fpsLow and "{FF0000}[CrashGuard] URGENT: " or "{FF4444}[CrashGuard] Warning: ")
                                    .. count .. " vehicles of model " .. model
                                    .. " loaded nearby" .. (fpsLow and " AND your FPS just dropped" or "")
                                    .. " - crash risk. Consider moving away."

                                sampAddChatMessage(msg, -1)
                                LogWarning(string.format(
                                    "model=%d count=%d fps=%.0f urgent=%s",
                                    model, count, currentFPS, tostring(fpsLow)
                                ))
                            end
                        end
                    end
                end)
            end

            -- Small incremental GC step (not a full collect - avoids
            -- a frame hitch) to keep Lua's own memory tidy.
            if NowSeconds() - gcTimer > (GC_INTERVAL / 1000) then
                gcTimer = NowSeconds()
                collectgarbage("step", 200)
            end

            -- Watchdog: check moonloader.log for other scripts dying
            if watchdogOn.v and NowSeconds() - watchdogTimer > 3 then
                watchdogTimer = NowSeconds()
                pcall(CheckOtherScriptsHealth)
            end
        end
    end
end

--------------------------------------------------------------
-- Settings / status window
--------------------------------------------------------------
-- FIX: this callback runs EVERY rendered frame while the window is open. It used
-- to call CountVehiclesByModel() (a full native vehicle-pool walk) and
-- ReadRecentLog() (a disk read of the whole log file) directly - i.e. dozens of
-- times per second - which is exactly the kind of per-frame hitch this script
-- exists to warn about, and which its own main loop already avoids by only
-- scanning every CHECK_INTERVAL. The window now reads from a snapshot refreshed
-- at most once per GUI_REFRESH_INTERVAL.
local GUI_REFRESH_INTERVAL = 1.0
local guiSnapshot = { time = -math.huge, models = {}, lines = {}, scanAvailable = false }

local function GetGuiSnapshot()
    local now = NowSeconds()
    if now - guiSnapshot.time < GUI_REFRESH_INTERVAL then
        return guiSnapshot
    end
    guiSnapshot.time = now

    local okCounts, counts, total, scanAvailable = pcall(CountVehiclesByModel)
    local models = {}
    if okCounts and scanAvailable and counts then
        for model, count in pairs(counts) do
            if count >= 2 then
                models[#models + 1] = { model = model, count = count }
            end
        end
        table.sort(models, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.model < b.model
        end)
    end
    guiSnapshot.models = models
    guiSnapshot.scanAvailable = okCounts and scanAvailable == true

    local okLog, lines = pcall(ReadRecentLog, 10)
    guiSnapshot.lines = (okLog and lines) or {}
    return guiSnapshot
end

function imgui.OnDrawFrame()
    if not windowOpen.v then return end
    local snap = GetGuiSnapshot()

    imgui.SetNextWindowSize(imgui.ImVec2(320, 360), imgui.Cond.FirstUseEver)
    imgui.Begin("Crash Guard", windowOpen)

        imgui.Checkbox("Monitoring active", monitoringOn)
        imgui.Checkbox("Other-script watchdog", watchdogOn)
        imgui.Text("Current FPS (windowed avg): " .. string.format("%.0f", currentFPS))
        imgui.Separator()

        if watchdogOn.v then
            imgui.Text("Recently detected script issues:")
            imgui.BeginChild("WatchdogView", imgui.ImVec2(0, 80), true)
                if #recentScriptDeaths == 0 then
                    imgui.TextDisabled("None detected this session.")
                else
                    for _, msg in ipairs(recentScriptDeaths) do
                        imgui.TextWrapped(msg)
                    end
                end
            imgui.EndChild()
            imgui.Separator()
        end

        imgui.Text("Warn at this many same-model vehicles:")
        if imgui.InputInt("##threshold", thresholdBox) then
            if thresholdBox.v > 0 then
                WARN_THRESHOLD = thresholdBox.v
            end
        end

        imgui.Separator()
        imgui.Text("Vehicles within " .. VEHICLE_SCAN_RADIUS .. " units by model:")
        imgui.BeginChild("VehicleCounts", imgui.ImVec2(0, 120), true)
            if not snap.scanAvailable then
                imgui.TextDisabled("Vehicle scan unavailable in this host build.")
            elseif #snap.models == 0 then
                imgui.TextDisabled("No model has 2+ copies within the scan radius.")
            else
                for _, m in ipairs(snap.models) do
                    local color = (m.count >= WARN_THRESHOLD) and imgui.ImVec4(1.0, 0.3, 0.3, 1.0) or imgui.ImVec4(1.0, 1.0, 1.0, 1.0)
                    imgui.TextColored(color, "Model " .. m.model .. ": " .. m.count)
                end
            end
        imgui.EndChild()

        imgui.Separator()
        imgui.Text("Recent logged warnings:")
        imgui.BeginChild("LogView", imgui.ImVec2(0, 100), true)
            if #snap.lines == 0 then
                imgui.TextDisabled("No warnings logged yet.")
            else
                for _, line in ipairs(snap.lines) do
                    imgui.TextWrapped(line)
                end
            end
        imgui.EndChild()

    imgui.End()
end

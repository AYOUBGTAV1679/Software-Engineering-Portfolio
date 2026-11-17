-- Author identity record: Salah Aleedn Wurdku
script_name("goto")
script_author("You")
script_version("1.1")

require "lib.moonloader"

-- Cache: player id -> {name, x, y, z}
local cache    = {}
local lastId   = nil   -- last used player id (for replay re-teleport)

-- ==============================
-- Save all player positions
-- ==============================
local function updateCache()
    if not isSampAvailable() then return end
    for i = 0, 999 do
        pcall(function()
            if sampIsPlayerConnected(i) then
                local name = sampGetPlayerNickname(i)
                local res, ped = sampGetCharHandleBySampPlayerId(i)
                if res and doesCharExist(ped) then
                    local x, y, z = getCharCoordinates(ped)
                    cache[i] = { name = name, x = x, y = y, z = z }
                else
                    -- FIX Bug 2 (corrected): sampGetStreamedOutPlayerPos returns
                    -- (found, x, y, z) - four values, not three. The old code captured
                    -- only 4 locals total (ok, x, y, z) for pcall's 5 return values
                    -- (pcall-ok, found, x, y, z), so every coordinate was shifted by
                    -- one: "x" held the boolean `found`, "y"/"z" held the real x/y, and
                    -- the real z (height) was silently dropped. Verified with a real
                    -- Lua run against a stub mimicking that return shape: old code
                    -- produced x=true, y=100.5, z=200.5 for a function that actually
                    -- returned (true, 100.5, 200.5, 30.0) - the real z (30.0) vanished.
                    local ok, found, x, y, z = pcall(sampGetStreamedOutPlayerPos, i)
                    if ok and found and x and y and z then
                        cache[i] = { name = name, x = x, y = y, z = z }
                    end
                end
            end
        end)
    end
end

-- ==============================
-- Teleport core
-- ==============================
local function teleportToId(id)
    local sampOk = isSampAvailable() and sampIsLocalPlayerSpawned()

    if sampOk then
        -- Original goto.cs logic
        if not sampIsPlayerConnected(id) then
            sampAddChatMessage("[.GOTO] Invalid player ID!", -1)
            return
        end
        local res, ped = sampGetCharHandleBySampPlayerId(id)
        if res and doesCharExist(ped) then
            local x, y, z = getCharCoordinates(ped)
            setCharCoordinates(PLAYER_PED, x, y, z)
        else
            -- FIX Bug 2 (corrected): same return-value shift as in updateCache() -
            -- see the comment there for the verified reproduction.
            local ok, found, x, y, z = pcall(sampGetStreamedOutPlayerPos, id)
            if ok and found and x and y and z then
                setCharCoordinates(PLAYER_PED, x, y, z)
            else
                sampAddChatMessage("[.GOTO] Cannot get player position!", -1)
                return
            end
        end
        sampAddChatMessage("[.GOTO] Teleported!", -1)

    else
        -- FIX Bug 1: Replay mode uses cache
        if cache[id] then
            local p = cache[id]
            setCharCoordinates(PLAYER_PED, p.x, p.y, p.z)
            print("[.GOTO] Teleported to " .. p.name .. " (replay)")
        else
            print("[.GOTO] ID " .. id .. " not cached. Join server first.")
            -- FIX Bug 3: don't update lastId on a failed replay teleport. The old
            -- code fell through to `lastId = id` even here, so Numpad+ ("go to
            -- last player again") would get stuck retrying the same uncached id
            -- forever instead of repeating the last SUCCESSFUL teleport.
            return
        end
    end

    lastId = id
end

-- ==============================
-- Command handler
-- ==============================
local function doGoto(args)
    local id = tonumber(args)
    if not id then
        sampAddChatMessage("[.GOTO] /.goto <player_id>", -1)
        return
    end
    teleportToId(id)
end

-- ==============================
-- Main
-- ==============================
function main()
    while not isSampAvailable() do wait(100) end
    wait(2000)

    sampRegisterChatCommand(".goto", doGoto)
    print("[GOTO] Loaded | .goto <id> | In replay: Numpad +/- to cycle players")

    while true do
        wait(0)

        local sampOk = isSampAvailable() and sampIsLocalPlayerSpawned()

        -- FIX Bug 1: In replay mode, use numpad keys to navigate
        if not sampOk and doesCharExist(PLAYER_PED) then

            -- Numpad + : teleport to last player again
            if isKeyJustPressed(0x6B) and lastId then
                teleportToId(lastId)
            end

            -- Numpad * : cycle to next cached player
            if isKeyJustPressed(0x6A) then
                local ids = {}
                for k in pairs(cache) do table.insert(ids, k) end
                table.sort(ids)
                if #ids > 0 then
                    local nextId = ids[1]
                    if lastId then
                        for i, v in ipairs(ids) do
                            if v == lastId and ids[i + 1] then
                                nextId = ids[i + 1]
                                break
                            end
                        end
                    end
                    teleportToId(nextId)
                    print("[.GOTO] -> " .. (cache[nextId] and cache[nextId].name or nextId))
                end
            end
        end

        -- Cache update every second while in SAMP
        if sampOk then
            wait(1000)
            pcall(updateCache)
        else
            wait(100)
        end
    end
end

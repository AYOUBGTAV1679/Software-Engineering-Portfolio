-- Author identity record: Salah Aleedn Wurdku
--[[
================================================================================
  RP RESPOND AI | SA-MP / MoonLoader | SAMP 0.3.7
  Designer : Sam Wilson | Version : 10.0
  /jrp /jrpset /jrplast /jrpchar /jrpauto /jrphelp /jrpbase
================================================================================
--]]

script_name("RP Respond AI")
script_version("10.0")
script_author("Sam Wilson")

require("sampfuncs")
local ClassifyProviderError = require 'provider_error_classifier'
local PrefetchEpoch = require 'prefetch_epoch'
local imgui  = require("imgui")
local io     = require("io")
local os     = require("os")
local lanes = nil
pcall(function() lanes = require("lanes").configure() end)

-- lib.samp.events: safe chat reading, no bitstream crash
local ok_ev, sampev = pcall(require, "lib.samp.events")
if not ok_ev then sampev = nil end


-- Encoding
local ok_enc, encoding = pcall(require, "encoding")
if ok_enc and encoding then
    encoding.default = "CP1251"
    u8 = encoding.UTF8
else
    u8 = setmetatable({
        decode = function(_, s) return s end,
        encode = function(_, s) return s end,
    }, { __call = function(_, s) return s end })
end

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local API_KEY    = "YOUR_GROQ_KEY_HERE"
local API_KEY_OR = ""      -- OpenRouter key (optional) - openrouter.ai
local USE_OR     = false   -- set true to use OpenRouter instead of Groq

-- Groq models (rotate on error)
local MODELS = {
    "llama-3.1-8b-instant",
    "gemma2-9b-it",
    "llama-3.3-70b-versatile",
}
-- OpenRouter free models (no daily limit shown, very generous)
local MODELS_OR = {
    "meta-llama/llama-3.1-8b-instruct:free",
    "google/gemma-2-9b-it:free",
    "mistralai/mistral-7b-instruct:free",
}
local MODEL     = USE_OR and MODELS_OR[1] or MODELS[1]
local model_idx = 1
local TIMEOUT = 15

-- os.clock() measures process CPU time, not elapsed wall time. Use the host's
-- monotonic game timer for request deadlines, with a seconds-resolution fallback.
local function NowMilliseconds()
    if type(getGameTimer) == "function" then
        local ok, value = pcall(getGameTimer)
        if ok and type(value) == "number" then return value end
    end
    return os.time() * 1000
end

--------------------------------------------------------------------------------
-- PATHS
--------------------------------------------------------------------------------
local SAVE_DIR     = getWorkingDirectory() .. "\\rp_respond_ai\\"
local HISTORY_FILE = SAVE_DIR .. "history.dat"
local CUSTOMS_FILE = SAVE_DIR .. "customs.dat"
local CHAR_FILE    = SAVE_DIR .. "character.txt"
local BASE_DIR     = SAVE_DIR .. "bases\\"
local BASE_MAX     = 10

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local last_text      = ""
local last_type      = "me"
local last_sender    = ""
local is_loading     = false
local my_last_was_me = false
local my_name        = ""
local player_char    = ""

local generated      = {}
local status_msg     = ""
local response_mode  = "rp"   -- "rp" = /me /do,  "chat" = verbal reply

local chat_context = {}
local CTX_MAX      = 6

local cache     = {}
local cache_ord = {}
local CACHE_MAX = 30

local prefetch_key    = ""
local prefetch_busy   = false
local prefetch_epoch  = PrefetchEpoch.new()
local response_epoch  = PrefetchEpoch.new()
local prefetch_done   = false
local prefetch_result = nil

local history = {}
local customs = {}
local bases   = {}

local font_loaded = false

-- HTTP result queue: lanes thread puts result here, main thread reads it
local http_queue = {}
local http_lanes = {} -- active worker handles, keyed by request ID

-- Prefetch and interactive responses have separate freshness domains.
local function InvalidatePrefetch()
    prefetch_epoch:invalidate()
    prefetch_key = ""
    prefetch_busy = false
    prefetch_done = false
    prefetch_result = nil
end

--------------------------------------------------------------------------------
-- WINDOWS
--------------------------------------------------------------------------------
local w_main    = imgui.ImBool(false)
local w_smart   = imgui.ImBool(false)
local w_hist    = imgui.ImBool(false)
local w_cust    = imgui.ImBool(false)
local w_char    = imgui.ImBool(false)
local w_savenew = imgui.ImBool(false)
local w_auto    = imgui.ImBool(false)
local w_help    = imgui.ImBool(false)
local w_base    = imgui.ImBool(false)
local w_basenew  = imgui.ImBool(false)
local w_chatlog  = imgui.ImBool(false)  -- chat log picker
imgui.Process    = false

-- chat log: stores last 30 IC lines with sender info
local chat_log      = {}
local CHATLOG_MAX   = 30
local chat_selected = -1  -- index of selected line

local smart_text   = ""
local smart_label  = ""
local buf_char     = imgui.ImBuffer(256)
local buf_snname   = imgui.ImBuffer(64)
local buf_sntext   = imgui.ImBuffer(512)
local buf_bnname   = imgui.ImBuffer(64)
local buf_bncont   = imgui.ImBuffer(2048)
local cur_base_idx = 0
local scrx, scry   = 800, 600

--------------------------------------------------------------------------------
-- UTIL
--------------------------------------------------------------------------------
local function Say(msg)
    sampAddChatMessage("{4DA6FF}[RPRespond]{FFFFFF} " .. tostring(msg), -1)
end

local function UI(s)
    if not s or s == "" then return s end
    local r = s
    pcall(function() r = u8(s) end)
    return r
end

local function SyncUI()
    imgui.Process = w_main.v or w_smart.v or w_hist.v or w_cust.v
                 or w_char.v or w_savenew.v or w_help.v
                 or w_base.v or w_basenew.v or w_chatlog.v
end

local function Delay(text)
    return math.max(400, math.min(2000, #text * 50)) + math.random(-100, 100)
end

local function TL(t)
    if t == "do" then return "/do"
    elseif t == "dialog" then return "[Dialog]"
    else return "/me" end
end

local function IsOOC(text)
    if not text then return false end
    return text:match("^%(%(") or text:match("^//") or text:match("^%[OOC%]")
end

--------------------------------------------------------------------------------
-- DISK I/O
--------------------------------------------------------------------------------
local function EnsureDir()
    if not doesDirectoryExist(SAVE_DIR) then createDirectory(SAVE_DIR) end
    if not doesDirectoryExist(BASE_DIR)  then createDirectory(BASE_DIR)  end
end

local function SaveData(path, tbl)
    pcall(function()
        EnsureDir()
        local f = io.open(path, "w")
        if not f then return end
        f:write("return {\n")
        for _, e in ipairs(tbl) do
            f:write("  {\n")
            for k, v in pairs(e) do
                if type(v) == "string" then
                    local s = v:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")
                    f:write('    ' .. k .. ' = "' .. s .. '",\n')
                end
            end
            f:write("  },\n")
        end
        f:write("}\n")
        f:close()
    end)
end

local function LoadData(path)
    local ok, r = pcall(function()
        local c = loadfile(path)
        return c and c() or {}
    end)
    return (ok and r) or {}
end

local function SaveChar(t)
    pcall(function()
        EnsureDir()
        local f = io.open(CHAR_FILE, "w")
        if f then f:write(t or ""); f:close() end
    end)
end

local function LoadChar()
    local r = ""
    pcall(function()
        local f = io.open(CHAR_FILE, "r")
        if f then r = f:read("*all") or ""; f:close() end
    end)
    return r
end

local function SaveBase(idx, name, content)
    pcall(function()
        EnsureDir()
        local f = io.open(BASE_DIR .. "base_" .. idx .. ".dat", "w")
        if not f then return end
        local n = (name or ""):gsub("\\","\\\\"):gsub('"','\\"')
        local c = (content or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")
        f:write('return { name = "' .. n .. '", content = "' .. c .. '" }\n')
        f:close()
    end)
end

local function LoadBases()
    local result = {}
    for i = 1, BASE_MAX do
        pcall(function()
            local path = BASE_DIR .. "base_" .. i .. ".dat"
            local chunk = loadfile(path)
            if chunk then
                local d = chunk()
                if d and d.name then result[i] = d end
            end
        end)
    end
    return result
end

local function DeleteBase(idx)
    pcall(os.remove, BASE_DIR .. "base_" .. idx .. ".dat")
    bases[idx] = nil
end

--------------------------------------------------------------------------------
-- CACHE
--------------------------------------------------------------------------------
local function CK(cmd, mode, text)
    -- Responses can differ by provider and model; keep their cache entries separate.
    local provider = USE_OR and "openrouter" or "groq"
    return provider .. ":" .. MODEL .. ":" .. cmd .. ":" .. mode .. ":" .. text:lower():gsub("%s+", " ")
end

local function CGe(k) return cache[k] end

local function CSe(k, v)
    if cache[k] then return end
    if #cache_ord >= CACHE_MAX then
        cache[table.remove(cache_ord, 1)] = nil
    end
    cache[k] = v
    cache_ord[#cache_ord+1] = k
end

--------------------------------------------------------------------------------
-- HISTORY
--------------------------------------------------------------------------------
local function AddHist(sender, atype, action, label, reply)
    table.insert(history, 1, {
        time   = os.date("%H:%M"),
        sender = sender or "?",
        atype  = atype  or "me",
        action = action or "",
        label  = label  or "Reply",
        reply  = reply  or "",
    })
    if #history > 20 then table.remove(history) end
    SaveData(HISTORY_FILE, history)
end

--------------------------------------------------------------------------------
-- PARSE RESPONSE
--------------------------------------------------------------------------------
local function ParseResp(raw)
    local entries = {}
    local text = tostring(raw or ""):gsub("\r", "")

    for line in (text .. "\n"):gmatch("([^\n]+)\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")

        local sep, sep_len = nil, 1
        local p = line:find("|", 1, true)
        if p then sep = p; sep_len = 1 end
        if not sep then
            p = line:find("\xc2\xa7", 1, true)
            if p then sep = p; sep_len = 2 end
        end
        if not sep then
            p = line:find(":%s*/")
            if p then sep = p; sep_len = 1 end
        end

        if sep then
            local label = line:sub(1, sep-1)
                :gsub("^%s+",""):gsub("%s+$","")
                :gsub("[^%a%s]",""):gsub("^%s+",""):gsub("%s+$","")
            local body  = line:sub(sep + sep_len):gsub("^%s+",""):gsub("%s+$","")
            if not body:match("^/") then
                local sl = body:find("/")
                if sl then body = body:sub(sl) end
            end
            if label ~= "" and body ~= "" and #label < 25 then
                entries[#entries+1] = { label = label, text = body }
            end
        end
    end

    if #entries == 0 then
        for line in (text .. "\n"):gmatch("([^\n]+)\n") do
            line = line:gsub("^%s+",""):gsub("%s+$","")
            if line:match("^/me") or line:match("^/do") then
                entries[#entries+1] = { label = "Auto", text = line }
            end
        end
    end

    if #entries == 0 and text:gsub("%s","") ~= "" then
        entries[1] = { label = "Auto", text = text:gsub("\n"," "):sub(1,150) }
    end

    return entries
end

--------------------------------------------------------------------------------
-- JSON ESCAPE
--------------------------------------------------------------------------------
local function JE(s)
    local str = tostring(s or "")
    pcall(function() str = u8(str) end)
    return str
        :gsub("\\", "\\\\")
        :gsub('"',  '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "")
        :gsub("\t", "\\t")
end

--------------------------------------------------------------------------------
-- SYSTEM PROMPTS
--------------------------------------------------------------------------------
local SYS_MULTI_ME = [[You are an expert SA-MP roleplay writer for a serious Russian criminal/law enforcement RP server.
Another player performed a /me action on the character. Write 5 highly realistic /me responses in RUSSIAN.

Each response must:
- Use vivid, detailed body language with specific physical descriptions
- Sound completely natural for an experienced RP player
- Be immersive and cinematic — not generic
- Be 10-20 Russian words
- Start with /me

Format (pipe | as separator):
Auto|/me text
Cooperative|/me text
Neutral|/me text
Resistant|/me text
Aggressive|/me text

Auto = most realistic natural human reaction
Cooperative = calm compliance, professional demeanor, slight tension visible
Neutral = controlled blank expression, minimal movement, cold professionalism
Resistant = visible reluctance, tense muscles, slow deliberate movements
Aggressive = sharp defiant reaction, jaw clenches, eyes narrow, body tenses

Only the 5 lines. Nothing else.]]

local SYS_MULTI_DO = [[You are an expert SA-MP roleplay narrator for a serious Russian criminal/law enforcement RP server.
Write 4 realistic /do environment descriptions in RUSSIAN for the given question.

Each description must:
- Be specific, atmospheric, and detailed
- Sound like a professional film narrator
- Describe physical reality precisely
- Be 10-20 Russian words
- Start with /do

Format (pipe | as separator):
Auto|/do text
Neutral|/do text
Cooperative|/do text
Resistant|/do text

Auto = most realistic and likely state
Neutral = ambiguous, partially obscured, unclear
Cooperative = confirms favorable outcome
Resistant = denies or opposite of expected

Only the 4 lines. Nothing else.]]

local SYS_AUTO_ME = [[Expert SA-MP roleplay writer for serious Russian RP server.
Write ONE highly realistic /me response in RUSSIAN. Vivid body language, cinematic, 10-20 words.
Format: Auto|/me text. Nothing else.]]

local SYS_AUTO_DO = [[Expert SA-MP roleplay narrator for serious Russian RP server.
Write ONE highly specific and atmospheric /do environment description in RUSSIAN. 10-20 words.
Format: Auto|/do text. Nothing else.]]

local SYS_DIALOG = [[You are an expert SA-MP roleplay dialogue writer for a serious Russian law enforcement and criminal RP server.
Another player said something to the character. Write 4 highly formal and realistic verbal IC responses in RUSSIAN.

The responses must:
- Sound like real formal spoken Russian in a serious RP context
- Be appropriately professional, legal, or authoritative in tone
- Reference the specific content of what was said
- Be complete sentences, 10-25 Russian words each
- NO /me prefix — these are spoken words only
- Use formal register (official, legal language when appropriate)

Format (pipe | as separator):
Cooperative|response text
Neutral|response text
Resistant|response text
Aggressive|response text

Cooperative = calm professional acknowledgment, formal agreement or compliance
Neutral = measured official response, neither confirming nor denying
Resistant = firm legal pushback, citing rights or procedure
Aggressive = sharp authoritative refusal, asserting position firmly

Only the 4 lines. Nothing else.]]

local function GetSys(cmd)
    if cmd == "DIALOG"   then return SYS_DIALOG
    elseif cmd == "AUTO_DO" then return SYS_AUTO_DO
    elseif cmd == "AUTO_ME" then return SYS_AUTO_ME
    elseif cmd == "DO"   then return SYS_MULTI_DO
    else                      return SYS_MULTI_ME end
end

local function BuildPrompt(text)
    local parts = { text }
    if player_char ~= "" then
        parts[#parts+1] = "Character: " .. player_char
    end
    for i = 1, BASE_MAX do
        if bases[i] and bases[i].content and bases[i].content ~= "" then
            parts[#parts+1] = "Rules[" .. (bases[i].name or i) .. "]: "
                .. bases[i].content:sub(1, 600)
        end
    end
    if #chat_context > 0 then
        parts[#parts+1] = "Recent chat:\n" .. table.concat(chat_context, "\n")
    end
    return table.concat(parts, "\n")
end

--------------------------------------------------------------------------------
-- HTTP via lanes linda (thread-safe queue)
-- lanes is initialized in main() AFTER isSampAvailable to prevent focus loss
-- The lane runs requests.request in background, result posted to linda
-- Main lua_thread polls linda with wait(0) — zero blocking, zero crash
--------------------------------------------------------------------------------
local function DoHttpRequest(cmd, mode, text, request_id, request_provider, request_model)
    if not lanes then
        http_queue[request_id] = { err = "lanes not ready" }
        return
    end

    local sys    = GetSys(cmd)
    local prompt = BuildPrompt(text)
    local body = string.format(
        '{"model":"%s","max_tokens":400,"temperature":0.7,"messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}]}',
        request_model, JE(sys), JE(prompt)
    )

    -- Resolve the provider at request creation time. Keep endpoint and key paired.
    local api_key = request_provider and API_KEY_OR or API_KEY
    local api_url = request_provider
        and "https://openrouter.ai/api/v1/chat/completions"
        or  "https://api.groq.com/openai/v1/chat/completions"
    local pkg_path  = package.path
    local pkg_cpath = package.cpath

    local setupOk, setupError = pcall(function()
        local linda = lanes.linda()
        local worker = lanes.gen("*", {
            package = { path = pkg_path, cpath = pkg_cpath }
        }, function(ld, bdy, key, url)
            -- Keep dependency loading inside pcall too: a missing requests
            -- module must report an error instead of silently killing the lane.
            local ok, res = pcall(function()
                local requests = require("requests")
                return requests.post(
                    url,
                    {
                        headers = {
                            ["Content-Type"]  = "application/json",
                            ["Authorization"] = "Bearer " .. key,
                        },
                        data = bdy,
                    }
                )
            end)
            if ok then
                local responseText = type(res) == "table" and res.text or ""
                ld:send("result", tostring(responseText or ""))
            else
                ld:send("result", "ERROR:" .. tostring(res))
            end
        end)

        -- Retain the lane handle so a deadline can request cancellation.
        http_lanes[request_id] = worker(linda, body, api_key, api_url)

        lua_thread.create(function()
            local startedAt = NowMilliseconds()
            while true do
                local key, val = linda:receive(0, "result")
                if key == "result" then
                    http_lanes[request_id] = nil
                    http_queue[request_id] = { text = tostring(val or "") }
                    return
                end
                local lane = http_lanes[request_id]
                if lane then
                    local laneStatus = lane.status
                    if laneStatus == "error" or laneStatus == "cancelled" or laneStatus == "killed" then
                        local laneError = laneStatus
                        if laneStatus == "error" then
                            local _, joinError = lane:join(0)
                            laneError = tostring(joinError or "worker failed")
                        end
                        http_lanes[request_id] = nil
                        http_queue[request_id] = { err = "HTTP worker " .. laneStatus .. ": " .. laneError }
                        return
                    end
                end
                if NowMilliseconds() - startedAt >= TIMEOUT * 1000 then
                    local lane = http_lanes[request_id]
                    http_lanes[request_id] = nil
                    -- Cancellation is cooperative; do not force-kill a worker
                    -- that may be inside a native call or holding native resources.
                    if lane then pcall(function() lane:cancel("hard", 0) end) end
                    http_queue[request_id] = { err = "Timeout" }
                    return
                end
                wait(0)
            end
        end)
    end)

    if not setupOk then
        http_lanes[request_id] = nil
        http_queue[request_id] = { err = "Could not start HTTP worker: " .. tostring(setupError) }
    end
end

local req_id = 0
local function NextId()
    req_id = req_id + 1
    return req_id
end

-- Parse Groq response text → extract content
local function ExtractContent(raw)
    local mi = raw:find('"message"', 1, true)
    if not mi then return nil end
    local ci = raw:find('"content"', mi, true)
    if not ci then return nil end
    local qi = raw:find(':"', ci, true)
    if not qi then return nil end

    local i = qi + 2
    local buf = {}
    while i <= #raw do
        local ch = raw:sub(i, i)
        -- FIX: the old lookbehind ("is the previous byte a backslash?") is both
        -- wrong and unnecessary. The escape branch below always consumes a
        -- backslash pair in one jump (i = i + 2), so the main loop can NEVER
        -- land on a '"' that is actually the second half of an escaped '\"'.
        -- That made the lookbehind misfire specifically when content ends in a
        -- literal backslash: JSON encodes that as \\" (escaped-backslash, then
        -- the REAL closing quote), and the old check saw the escape pair's own
        -- second backslash sitting right before that real quote and wrongly
        -- treated it as "escaped," consuming past the end of the string and
        -- appending the start of the next JSON field to the output. Verified
        -- against a real Groq-shaped response ending in content \\": the old
        -- code returned 'He drew his blade\"},' instead of 'He drew his blade\'.
        if ch == '"' then break
        elseif ch == '\\' then
            local nx = raw:sub(i+1, i+1)
            if     nx == 'n'  then buf[#buf+1] = '\n'
            elseif nx == '"'  then buf[#buf+1] = '"'
            elseif nx == '\\' then buf[#buf+1] = '\\'
            else                   buf[#buf+1] = nx end
            i = i + 2
        else
            buf[#buf+1] = ch
            i = i + 1
        end
    end
    return table.concat(buf)
end

-- High-level: send request and call callback when done
local function SendRequest(cmd, mode, text, on_done, on_err)
    -- A request must keep the provider/model pair it started with. The user
    -- can change providers while a worker is still running.
    local request_provider = USE_OR
    local request_model = MODEL
    local request_info = { use_or = request_provider, model = request_model }
    local function reportError(message)
        if on_err then on_err(message, request_info) end
    end

    local active_key = request_provider and API_KEY_OR or API_KEY
    local missing_key = not active_key or active_key == ""
        or (not request_provider and active_key == "YOUR_GROQ_KEY_HERE")
    if missing_key then
        reportError(request_provider and "Set API_KEY_OR in the script first" or "Set API_KEY in the script first")
        return
    end

    local id = NextId()
    DoHttpRequest(cmd, mode, text, id, request_provider, request_model)

    lua_thread.create(function()
        local startedAt = NowMilliseconds()
        while true do
            if http_queue[id] then
                local r = http_queue[id]
                http_queue[id] = nil
                if r.err then
                    reportError(r.err)
                elseif r.text then
                    if r.text:match("^ERROR:") then
                        reportError(r.text:sub(7))
                    else
                        local val = ExtractContent(r.text)
                        if val and val ~= "" then
                            local decoded = val
                            pcall(function() decoded = u8:decode(val) end)
                            if on_done then on_done(decoded) end
                        else
                            local providerError = ClassifyProviderError(r.text)
                            if providerError then
                                reportError(providerError)
                            else
                                reportError("Parse error: " .. r.text:sub(1,80))
                            end
                        end
                    end
                end
                return
            end
            if NowMilliseconds() - startedAt >= (TIMEOUT + 2) * 1000 then
                http_queue[id] = nil
                reportError("Timeout")
                return
            end
            wait(0)
        end
    end)
end

--------------------------------------------------------------------------------
-- SEND HELPERS
--------------------------------------------------------------------------------
local function GetCmd(type_, multi)
    if type_ == "dialog" then return "DIALOG"
    elseif type_ == "do" then return multi and "DO" or "AUTO_DO"
    else return multi and "ME" or "AUTO_ME" end
end

local function SendToServer(multi, cb)
    if is_loading then return end
    local cmd = GetCmd(last_type, multi)
    local ck  = CK(cmd, last_type, last_text)
    local c   = CGe(ck)
    if c then
        generated  = ParseResp(c)
        status_msg = "Cache - " .. #generated .. " responses"
        if cb then cb() end
        return
    end
    is_loading = true
    status_msg = "Thinking..."
    generated  = {}
    local requestEpoch = response_epoch:begin()
    SendRequest(cmd, last_type, last_text,
        function(result)
            if not response_epoch:is_current(requestEpoch) then return end
            is_loading = false
            CSe(ck, result)
            generated  = ParseResp(result)
            status_msg = #generated > 0
                and ("Ready - " .. #generated .. " responses")
                or  "No responses - try again"
            if cb then cb() end
        end,
        function(err, request_info)
            if not response_epoch:is_current(requestEpoch) then return end
            is_loading = false
            local err_str = tostring(err)
            -- Rotate only if this failed request still belongs to the active
            -- provider/model. A late response must not alter a newer selection.
            local selectionUnchanged = request_info
                and request_info.use_or == USE_OR
                and request_info.model == MODEL
            local lowerError = err_str:lower()
            local isModelAvailabilityError = lowerError:find("rate limit", 1, true)
                or lowerError:find("model unavailable", 1, true)
                or lowerError:find("rate_limit", 1, true)
                or lowerError:find("decommissioned", 1, true)
                or lowerError:find("model_not_found", 1, true)
                or lowerError:find("unknown model", 1, true)
                or lowerError:find("model does not exist", 1, true)
                or lowerError:find("does not exist", 1, true)
                or lowerError:find("no endpoints found for model", 1, true)
            if isModelAvailabilityError and selectionUnchanged then
                local active_models = request_info.use_or and MODELS_OR or MODELS
                model_idx = model_idx + 1
                if model_idx > #active_models then model_idx = 1 end
                MODEL = active_models[model_idx]
                -- Any prefetch started for the previous model must not become
                -- the visible suggestion for this newly selected model.
                InvalidatePrefetch()
                status_msg = "Rate limit - switching to: " .. MODEL
                Say("Rate limit - trying: " .. MODEL)
            elseif isModelAvailabilityError then
                status_msg = "Request failed for the previous provider/model selection."
            else
                status_msg = "Error: " .. err_str:sub(1, 60)
            end
        end
    )
end

local function TryPrefetch(mode, text)
    local cmd = GetCmd(mode, true)
    local ck  = CK(cmd, mode, text)
    local cached = CGe(ck)
    if cached then
        -- A cached result for the current key supersedes any older in-flight
        -- prefetch. Its callback must not overwrite this ready result later.
        InvalidatePrefetch()
        prefetch_key    = ck
        prefetch_done   = true
        prefetch_result = cached
        return
    end
    if prefetch_busy or prefetch_key == ck then return end

    local requestEpoch = prefetch_epoch:begin()
    prefetch_key  = ck
    prefetch_busy = true
    prefetch_done = false
    prefetch_result = nil
    SendRequest(cmd, mode, text,
        function(r)
            if not prefetch_epoch:is_current(requestEpoch) then return end
            CSe(ck, r)
            prefetch_result = r
            prefetch_done   = true
            prefetch_busy   = false
        end,
        function()
            if not prefetch_epoch:is_current(requestEpoch) then return end
            prefetch_busy = false
            prefetch_key  = ""
            prefetch_done = false
            prefetch_result = nil
        end
    )
end

local function SendAutoSmart()
    if last_text == "" then status_msg = "Nothing - use /jrpset"; return end
    if is_loading then return end
    local cmd = GetCmd(last_type, false)
    local ck  = CK(cmd, last_type, last_text)
    local c   = CGe(ck)
    if c then
        local e = ParseResp(c)
        if e[1] then
            smart_label = e[1].label
            smart_text  = e[1].text
            w_smart.v   = true
            SyncUI()
        end
        return
    end
    is_loading = true
    status_msg = "Thinking (Auto)..."
    local requestEpoch = response_epoch:begin()
    SendRequest(cmd, last_type, last_text,
        function(r)
            if not response_epoch:is_current(requestEpoch) then return end
            is_loading = false
            CSe(ck, r)
            local e = ParseResp(r)
            if e[1] then
                smart_label = e[1].label
                smart_text  = e[1].text
                w_smart.v   = true
                SyncUI()
                status_msg = "Auto ready"
            else
                status_msg = "No response"
            end
        end,
        function(err)
            if not response_epoch:is_current(requestEpoch) then return end
            is_loading = false
            status_msg = "Error: " .. tostring(err)
        end
    )
end

--------------------------------------------------------------------------------
-- CHAT MONITOR
--------------------------------------------------------------------------------
local function AddCtx(line)
    if not line or line == "" or IsOOC(line) then return end
    chat_context[#chat_context+1] = line
    if #chat_context > CTX_MAX then table.remove(chat_context, 1) end
end

-- Track users who seem to use RP scripts (respond too fast, consistent patterns)
local rp_script_users = {}
local last_response_time = {}

local function CleanText(text)
    if not text then return "" end
    -- remove SAMP color codes {RRGGBB}
    text = text:gsub("{%x%x%x%x%x%x}", "")
    -- remove leading dash (server chat format: "- Text")
    text = text:gsub("^%s*%-%s*", "")
    -- remove trailing (Name) or (Name) [id] — leftover from /do detection
    text = text:gsub("%s*%(([%a][%w_]+)%)%s*%[%d+%]%s*$", "")
    text = text:gsub("%s*%(([%a][%w_]+)%)%s*$", "")
    -- remove trailing dot
    text = text:gsub("%.%s*$", "")
    -- trim
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function AddChatLog(sender, atype, text)
    if not text or text == "" then return end
    table.insert(chat_log, 1, {
        sender = sender or "?",
        atype  = atype  or "me",
        text   = text,
        time   = os.date("%H:%M:%S"),
        is_rp  = (rp_script_users[sender] == true),
    })
    if #chat_log > CHATLOG_MAX then table.remove(chat_log) end
end

-- Called when WE send a chat message
-- If another player responds within 3 seconds, flag them as possible RP script user
local function TrackResponse(sender)
    local now = NowMilliseconds()
    for s, t in pairs(last_response_time) do
        if sender ~= s and (now - t) < 3000 then
            rp_script_users[sender] = true
        end
    end
    last_response_time[sender] = now
end

local function IsMe(name)
    if not name or name == "" then return false end
    if my_name == "" then return false end
    -- compare lowercase, both with spaces and underscores
    local a  = name:lower()
    local a2 = a:gsub("_"," "):gsub(" ","")
    local b  = my_name:lower()
    local b2 = b:gsub("_"," "):gsub(" ","")
    return a == b or a2 == b2
        or a:gsub("_","") == b:gsub("_","")
end

local function ResetPF()
    -- A context/provider change makes every outstanding interactive response
    -- stale too. Clear the flag so the new context can start its own request.
    response_epoch:invalidate()
    is_loading = false
    InvalidatePrefetch()
end

local function TriggerAuto()
    if not w_auto.v or w_main.v then return end
    lua_thread.create(function()
        wait(300)
        if w_main.v then return end
        w_main.v = true; generated = {}; status_msg = ""; SyncUI()
        if prefetch_done and prefetch_result then
            local cmd = GetCmd(last_type, true)
            local ck  = CK(cmd, last_type, last_text)
            CSe(ck, prefetch_result)
            generated  = ParseResp(prefetch_result)
            status_msg = "Prefetch ready - " .. #generated .. " responses"
        else
            SendToServer(true, nil)
        end
    end)
end

local function ParseChat(text)
    if not text or text == "" then return end
    if text:match("^%[%d") then return end
    if IsOOC(text) then return end

    -- Dialog: "Text (Name_Surname) [id]"
    -- Matches: Ты нарушил протокол (Marton_Wilson) [29]
    local db, dn = text:match("^(.-)%s*%(([%a][%w_]+)%)%s*%[%d+%]%s*$")
    if db and dn and #dn >= 3 and db ~= "" then
        AddCtx(text)
        if IsMe(dn) then my_last_was_me = true; return end
        my_last_was_me = false
        last_text = CleanText(db)
        last_type = "dialog"; last_sender = dn
        AddChatLog(dn, "dialog", last_text)
        TrackResponse(dn)
        ResetPF()
        TryPrefetch("dialog", last_text)
        TriggerAuto(); return
    end

    -- /do: "Text (Name)" — NO [id] at end, pure environment description
    -- Must NOT match dialog format "Text (Name) [id]"
    local ob, on_ = text:match("^(.+)%s+%(([%w_]+)%)%s*$")
    -- Extra check: make sure there's no [number] before the (Name)
    local is_pure_do = ob and on_ and #on_ >= 3
        and on_:match("^[%a][%w_]+$")
        and not ob:find("%(")
        and not text:match("%[%d+%]%s*$")  -- no [id] at end
    if is_pure_do then
        AddCtx(text)
        if IsMe(on_) then my_last_was_me = true; return end
        my_last_was_me = false
        last_text = CleanText(ob)
        last_type = "do"; last_sender = on_
        AddChatLog(on_, "do", last_text)
        TrackResponse(on_)
        ResetPF(); TryPrefetch("do", last_text); TriggerAuto(); return
    end

    -- /me: "Name_Surname action"
    local mn, ma = text:match("^([%a][%w_]-)%s+(.+)$")
    if mn and ma and #mn >= 3 and mn:match("_")
    and not text:match("%)%s*$") and not text:match("^%[") then
        AddCtx(text)
        if IsMe(mn) then my_last_was_me = true; return end
        my_last_was_me = false
        last_text = CleanText(ma)
        last_type = "me"; last_sender = mn
        AddChatLog(mn, "me", last_text)
        TrackResponse(mn)
        ResetPF(); TryPrefetch("me", last_text); TriggerAuto(); return
    end

    AddCtx(text)
end

-- Safe chat reading via lib.samp.events (no bitstream crash)
-- Falls back to onReceiveRpc if sampev not available
if sampev then
    function sampev.onServerMessage(color, text)
        if text then ParseChat(text) end
    end
else
    function onReceiveRpc(id, bs)
        if id == 93 then
            pcall(function()
                raknetBitStreamReadInt32(bs)
                local len = raknetBitStreamReadInt32(bs)
                if not len or len <= 0 or len > 512 then return end
                local msg = raknetBitStreamReadString(bs, len)
                if msg then ParseChat(msg) end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- FONT
--------------------------------------------------------------------------------
function imgui.BeforeDrawFrame()
    if font_loaded then return end
    font_loaded = true
    pcall(function()
        local io_f   = imgui.GetIO().Fonts
        local glyphs = io_f:GetGlyphRangesCyrillic()
        io_f:Clear()
        for _, p in ipairs({
            getFolderPath(0x14) .. "\\arial.ttf",
            getFolderPath(0x14) .. "\\verdana.ttf",
        }) do
            if doesFileExist(p) then
                io_f:AddFontFromFileTTF(p, 14, nil, glyphs)
                imgui.RebuildFonts()
                break
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- THEME
--------------------------------------------------------------------------------
local function Theme()
    imgui.SwitchContext()
    local s = imgui.GetStyle()
    local c = s.Colors; local C = imgui.Col; local V = imgui.ImVec4
    s.WindowRounding=6; s.FrameRounding=4; s.GrabRounding=4
    s.ChildWindowRounding=4; s.ItemSpacing=imgui.ImVec2(6,5)
    s.WindowTitleAlign=imgui.ImVec2(0.5,0.5)
    c[C.Text]=V(1,1,1,1); c[C.WindowBg]=V(.08,.08,.10,.97)
    c[C.ChildWindowBg]=V(.11,.11,.14,1); c[C.Border]=V(.20,.55,1,.80)
    c[C.FrameBg]=V(.14,.14,.18,1); c[C.FrameBgHovered]=V(.20,.40,.80,.70)
    c[C.FrameBgActive]=V(.20,.50,1,1); c[C.TitleBg]=V(.05,.20,.55,1)
    c[C.TitleBgActive]=V(.10,.30,.75,1); c[C.Button]=V(.15,.35,.75,1)
    c[C.ButtonHovered]=V(.20,.50,1,1); c[C.ButtonActive]=V(.10,.25,.60,1)
    c[C.Header]=V(.15,.35,.75,1); c[C.HeaderHovered]=V(.20,.50,1,1)
    c[C.HeaderActive]=V(.10,.25,.60,1); c[C.Separator]=V(.20,.55,1,.50)
    c[C.ScrollbarGrab]=V(.15,.35,.75,1); c[C.ScrollbarGrabHovered]=V(.20,.50,1,1)
    c[C.CheckMark]=V(.30,.70,1,1); c[C.SliderGrab]=V(.20,.50,1,1)
    c[C.TextSelectedBg]=V(.20,.50,1,.40); c[C.CloseButton]=V(.15,.35,.75,1)
    c[C.CloseButtonHovered]=V(.80,.20,.20,1); c[C.CloseButtonActive]=V(.60,.10,.10,1)
end

local LCOL = {
    Auto=0xFF4DA6FF, Cooperative=0xFF44FF88, Neutral=0xFFCCCCCC,
    Resistant=0xFFFF8800, Aggressive=0xFFFF4444, Reply=0xFFAAAAAA,
}
local function CV(h)
    return bit.band(bit.rshift(h,16),0xFF)/255,
           bit.band(bit.rshift(h,8),0xFF)/255,
           bit.band(h,0xFF)/255
end
local function LC(l) return LCOL[l] or 0xFFAAAAAA end

--------------------------------------------------------------------------------
-- REPLY ROW
--------------------------------------------------------------------------------
local function ReplyRow(i, entry, onclick)
    local safe = (entry.label or ""):gsub("[^\32-\126]","?")
    local r,g,b = CV(LC(safe))
    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(r*.35,g*.35,b*.35,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r*.60,g*.60,b*.60,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(r*.25,g*.25,b*.25,1))
    imgui.Button(safe, imgui.ImVec2(95,22))
    imgui.PopStyleColor(3)
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.12,.12,.16,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.20,.40,.80,.30))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.20,.50,1,.50))
    local bw = imgui.GetWindowWidth() - 95 - 22
    if imgui.Button(UI(entry.text) .. "##r"..i, imgui.ImVec2(bw,22)) then
        if onclick then onclick(entry) end
    end
    imgui.PopStyleColor(3)
    imgui.Spacing()
end

local function SendReply(entry)
    local txt = entry.text
    local d   = Delay(txt)
    lua_thread.create(function()
        wait(d)
        sampSendChat(txt)
        Say("Sent [" .. entry.label .. "] " .. d .. "ms")
        AddHist(last_sender, last_type, last_text, entry.label, txt)
        w_main.v = false; w_smart.v = false; SyncUI()
    end)
end

--------------------------------------------------------------------------------
-- IMGUI
--------------------------------------------------------------------------------
function imgui.OnDrawFrame()

    -- AUTO-SMART
    if w_smart.v then
        imgui.SetNextWindowSize(imgui.ImVec2(560,160), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-280,scry/2-80), imgui.Cond.Always)
        imgui.Begin("  Auto-Smart  |  RP Respond AI  ", w_smart,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
        imgui.TextColored(imgui.ImVec4(.3,.8,1,1), "Suggested response:")
        imgui.Spacing()
        imgui.BeginChild("##sc", imgui.ImVec2(-1,40), true)
            local r,g,b = CV(LC(smart_label))
            imgui.TextColored(imgui.ImVec4(r,g,b,1), "[" .. smart_label .. "]")
            imgui.SameLine()
            imgui.Text(UI(smart_text))
        imgui.EndChild()
        imgui.Spacing()
        local bw = (imgui.GetWindowWidth()-24)/2
        imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.10,.45,.15,1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.15,.65,.20,1))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.08,.30,.10,1))
        if imgui.Button("Send", imgui.ImVec2(bw,28)) then
            w_smart.v = false; SyncUI()
            SendReply({ label = smart_label, text = smart_text })
        end
        imgui.PopStyleColor(3)
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.40,.10,.10,1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.65,.15,.15,1))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.25,.08,.08,1))
        if imgui.Button("Choose other", imgui.ImVec2(bw,28)) then
            w_smart.v = false; w_main.v = true; SyncUI()
            SendToServer(true, nil)
        end
        imgui.PopStyleColor(3)
        imgui.End()
        if not w_smart.v then SyncUI() end
    end

    -- SAVE REPLY
    if w_savenew.v then
        imgui.SetNextWindowSize(imgui.ImVec2(500,200), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-250,scry/2-100), imgui.Cond.Always)
        imgui.Begin("  Save Reply  ", w_savenew,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
        imgui.Text("Name:"); imgui.PushItemWidth(-1)
        imgui.InputText("##snn", buf_snname); imgui.PopItemWidth(); imgui.Spacing()
        imgui.Text("Reply text:"); imgui.PushItemWidth(-1)
        imgui.InputText("##snt", buf_sntext); imgui.PopItemWidth(); imgui.Spacing()
        local bw2 = (imgui.GetWindowWidth()-24)/2
        if imgui.Button("Save##sn", imgui.ImVec2(bw2,26)) then
            local nm = tostring(buf_snname.v or ""):gsub("^%s+",""):gsub("%s+$","")
            local tx = tostring(buf_sntext.v or ""):gsub("^%s+",""):gsub("%s+$","")
            if nm ~= "" and tx ~= "" then
                customs[#customs+1] = { name=nm, atype=last_type, text=tx }
                SaveData(CUSTOMS_FILE, customs)
                Say("Saved: " .. nm)
                w_savenew.v = false; SyncUI()
            else Say("Fill both fields") end
        end
        imgui.SameLine()
        if imgui.Button("Cancel##sn", imgui.ImVec2(bw2,26)) then
            w_savenew.v = false; SyncUI()
        end
        imgui.End()
    end

    -- CHARACTER
    if w_char.v then
        imgui.SetNextWindowSize(imgui.ImVec2(520,180), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-260,scry/2-90), imgui.Cond.Always)
        imgui.Begin("  Character  |  RP Respond AI  ", w_char,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
        imgui.Text("Character description (English):")
        imgui.PushItemWidth(-1)
        imgui.InputText("##chb", buf_char); imgui.PopItemWidth(); imgui.Spacing()
        imgui.TextDisabled("Example: calm FBI agent, formal speech, never shows emotions")
        imgui.Spacing()
        local bw3 = (imgui.GetWindowWidth()-24)/3
        if imgui.Button("Save##ch", imgui.ImVec2(bw3,26)) then
            player_char = tostring(buf_char.v or ""):gsub("^%s+",""):gsub("%s+$","")
            SaveChar(player_char); Say("Character: " .. player_char:sub(1,50))
            w_char.v = false; SyncUI()
        end
        imgui.SameLine()
        if imgui.Button("Clear##ch", imgui.ImVec2(bw3,26)) then
            player_char = ""; SaveChar(""); buf_char = imgui.ImBuffer(256)
            Say("Character cleared"); w_char.v = false; SyncUI()
        end
        imgui.SameLine()
        if imgui.Button("Cancel##ch", imgui.ImVec2(bw3,26)) then
            w_char.v = false; SyncUI()
        end
        imgui.End()
    end

    -- BASE NEW/EDIT
    if w_basenew.v then
        imgui.SetNextWindowSize(imgui.ImVec2(560,360), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-280,scry/2-180), imgui.Cond.Always)
        imgui.Begin("  Knowledge Base  |  RP Respond AI  ", w_basenew,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
        imgui.Text("Base name:"); imgui.PushItemWidth(200)
        imgui.InputText("##bnn", buf_bnname); imgui.PopItemWidth(); imgui.Spacing()
        imgui.Text("Content (AI reads before responding):")
        imgui.PushItemWidth(-1)
        imgui.InputTextMultiline("##bnc", buf_bncont, imgui.ImVec2(-1,200))
        imgui.PopItemWidth(); imgui.Spacing()
        local bw4 = (imgui.GetWindowWidth()-24)/2
        if imgui.Button("Save base##bn", imgui.ImVec2(bw4,26)) then
            local nm = tostring(buf_bnname.v or ""):gsub("^%s+",""):gsub("%s+$","")
            local ct = tostring(buf_bncont.v or ""):gsub("^%s+",""):gsub("%s+$","")
            if nm ~= "" and ct ~= "" then
                local idx = cur_base_idx > 0 and cur_base_idx or (#bases + 1)
                if idx > BASE_MAX then idx = BASE_MAX end
                bases[idx] = { name=nm, content=ct }
                SaveBase(idx, nm, ct)
                Say("Base " .. idx .. " saved: " .. nm)
                w_basenew.v = false; SyncUI()
            else Say("Fill both fields") end
        end
        imgui.SameLine()
        if imgui.Button("Cancel##bn", imgui.ImVec2(bw4,26)) then
            w_basenew.v = false; SyncUI()
        end
        imgui.End()
    end

    -- BASES LIST
    if w_base.v then
        imgui.SetNextWindowSize(imgui.ImVec2(640,440), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-320,scry/2-220), imgui.Cond.FirstUseEver)
        imgui.Begin("  Knowledge Bases  |  RP Respond AI  ", w_base, 0)
        imgui.TextDisabled("AI reads these before every response. Max 10 bases.")
        imgui.Spacing()
        if imgui.Button("+ New base", imgui.ImVec2(140,24)) then
            cur_base_idx=0; buf_bnname=imgui.ImBuffer(64); buf_bncont=imgui.ImBuffer(2048)
            w_basenew.v=true; SyncUI()
        end
        imgui.Separator(); imgui.Spacing()
        imgui.BeginChild("##bl", imgui.ImVec2(-1,-1), false)
        for i = 1, BASE_MAX do
            local b = bases[i]
            if b then
                local r2,g2,b2 = CV(0xFF4DA6FF)
                imgui.TextColored(imgui.ImVec4(r2,g2,b2,1), "[" .. i .. "] " .. (b.name or ""))
                imgui.SameLine(280)
                imgui.TextDisabled(tostring(b.content or ""):sub(1,35) .. "...")
                imgui.SameLine()
                if imgui.Button("Edit##be"..i, imgui.ImVec2(50,20)) then
                    cur_base_idx=i
                    buf_bnname=imgui.ImBuffer(b.name or "", 64)
                    buf_bncont=imgui.ImBuffer(b.content or "", 2048)
                    w_basenew.v=true; SyncUI()
                end
                imgui.SameLine()
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.5,.1,.1,1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.7,.1,.1,1))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.3,0,0,1))
                if imgui.Button("X##bd"..i, imgui.ImVec2(22,20)) then DeleteBase(i) end
                imgui.PopStyleColor(3); imgui.Spacing()
            end
        end
        imgui.EndChild()
        imgui.End()
        if not w_base.v then SyncUI() end
    end

    -- HISTORY
    if w_hist.v then
        imgui.SetNextWindowSize(imgui.ImVec2(680,420), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-340,scry/2-210), imgui.Cond.FirstUseEver)
        imgui.Begin("  Reply History  |  RP Respond AI  ", w_hist, 0)
        if #history == 0 then imgui.TextDisabled("No history yet")
        else
            imgui.BeginChild("##hi", imgui.ImVec2(-1,-1), false)
            for i, h in ipairs(history) do
                imgui.TextDisabled((h.time or "") .. "  " .. (h.sender or "?"))
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(.5,.5,.9,1), "[" .. (h.atype or "me") .. "]")
                imgui.TextDisabled("  " .. UI(h.action or ""))
                ReplyRow(i, { label=h.label or "Reply", text=h.reply or "" },
                    function(e)
                        last_type = h.atype or "me"; SendReply(e)
                        w_hist.v = false; SyncUI()
                    end)
                imgui.Separator()
            end
            imgui.EndChild()
        end
        imgui.End()
        if not w_hist.v then SyncUI() end
    end

    -- SAVED REPLIES
    if w_cust.v then
        imgui.SetNextWindowSize(imgui.ImVec2(620,400), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-310,scry/2-200), imgui.Cond.FirstUseEver)
        imgui.Begin("  Saved Replies  |  RP Respond AI  ", w_cust, 0)
        if imgui.Button("+ Add new", imgui.ImVec2(130,24)) then
            buf_snname=imgui.ImBuffer(64); buf_sntext=imgui.ImBuffer(512)
            w_savenew.v=true; SyncUI()
        end
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        if #customs == 0 then imgui.TextDisabled("No saved replies")
        else
            imgui.BeginChild("##cu", imgui.ImVec2(-1,-1), false)
            local del = nil
            for i, c in ipairs(customs) do
                local r2,g2,b2 = CV(0xFF4DA6FF)
                imgui.TextColored(imgui.ImVec4(r2,g2,b2,1), c.name)
                imgui.SameLine(); imgui.TextDisabled("[" .. (c.atype or "me") .. "]")
                imgui.SameLine()
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.12,.12,.16,0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.20,.40,.80,.30))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.20,.50,1,.50))
                if imgui.Button(UI(c.text) .. "##cs"..i, imgui.ImVec2(imgui.GetWindowWidth()-230,22)) then
                    last_type = c.atype or "me"
                    SendReply({ label=c.name, text=c.text })
                    w_cust.v = false; SyncUI()
                end
                imgui.PopStyleColor(3); imgui.SameLine()
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.5,.1,.1,1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.7,.1,.1,1))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.3,0,0,1))
                if imgui.Button("X##dl"..i, imgui.ImVec2(22,22)) then del = i end
                imgui.PopStyleColor(3); imgui.Spacing()
            end
            if del then table.remove(customs, del); SaveData(CUSTOMS_FILE, customs) end
            imgui.EndChild()
        end
        imgui.End()
        if not w_cust.v then SyncUI() end
    end

    -- HELP
    if w_help.v then
        imgui.SetNextWindowSize(imgui.ImVec2(580,460), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(scrx/2-290,scry/2-230), imgui.Cond.Always)
        imgui.Begin("  Help  |  RP Respond AI 10.0  ", w_help,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
        local function CR(cmd, desc)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(.40,.85,1,1))
            imgui.Text(cmd); imgui.PopStyleColor()
            imgui.SameLine(170); imgui.TextDisabled(desc)
        end
        imgui.TextColored(imgui.ImVec4(.3,.8,1,1), "Commands")
        imgui.Separator(); imgui.Spacing()
        CR("/jrp",             "Open / close menu")
        CR("/jrpset me text",  "Set /me action manually")
        CR("/jrpset do text",  "Set /do question manually")
        CR("/jrplast",         "Show last detected")
        CR("/jrpchar",         "Character editor")
        CR("/jrpchar text",    "Set character directly")
        CR("/jrpchar clear",   "Clear character")
        CR("/jrpbase",         "Knowledge bases")
        CR("/jrphistory",      "Reply history")
        CR("/jrpsave name",    "Save as preset")
        CR("/jrpsaved",        "Saved replies")
        CR("/jrpauto",         "Toggle auto-open")
        imgui.Spacing(); imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(.3,.8,1,1), "Chat Detection")
        imgui.Separator(); imgui.Spacing()
        imgui.TextDisabled("/me  ->  Sam_Wilson передал документы")
        imgui.TextDisabled("/do  ->  Окно открыто (Sam_Wilson)")
        imgui.TextDisabled("Chat ->  Покажи документы (Sam_Wilson) [29]")
        imgui.TextDisabled("OOC  ->  (( ignored )) or // ignored")
        imgui.Spacing(); imgui.Spacing()
        imgui.TextDisabled("API: Groq (free)  |  v10.0  |  Sam Wilson")
        imgui.Spacing()
        if imgui.Button("Close##hp", imgui.ImVec2(-1,26)) then
            w_help.v = false; SyncUI()
        end
        imgui.End()
        if not w_help.v then SyncUI() end
    end

    -- CHAT LOG WINDOW
    if w_chatlog.v then
        local cw_w = math.min(720, scrx - 40)
        local cw_h = math.min(460, scry - 60)
        imgui.SetNextWindowSize(imgui.ImVec2(cw_w, cw_h), imgui.Cond.Always)
        imgui.SetNextWindowPos(
            imgui.ImVec2(scrx/2 - cw_w/2, scry/2 - cw_h/2),
            imgui.Cond.Always
        )
        imgui.Begin("  Chat Log  |  Click to select & respond  ", w_chatlog,
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

        -- type colors
        local type_col = {
            me     = imgui.ImVec4(.4,.8,1,1),
            do_    = imgui.ImVec4(.8,.9,.4,1),
            dialog = imgui.ImVec4(.9,.7,.2,1),
        }

        imgui.TextDisabled("Click any line to select it, then press Respond")
        imgui.Separator(); imgui.Spacing()

        if #chat_log == 0 then
            imgui.TextDisabled("No chat lines detected yet")
        else
            imgui.BeginChild("##cl", imgui.ImVec2(-1, cw_h - 115), true)
            for i, entry in ipairs(chat_log) do
                local is_sel = (chat_selected == i)

                -- highlight selected row
                if is_sel then
                    imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(.15,.25,.50,.80))
                end

                local tc = type_col[entry.atype] or type_col.me
                imgui.TextColored(tc, "[" .. (entry.atype or "me") .. "]")
                imgui.SameLine()
                imgui.TextDisabled(entry.time or "")
                imgui.SameLine()
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.12,.12,.16, is_sel and .6 or 0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.20,.40,.80,.40))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.20,.50,1,.60))
                local rp_tag = entry.is_rp and " [RP]" or ""
                local line_label = entry.sender .. rp_tag .. ": " .. UI(entry.text)
                if imgui.Button(line_label .. "##cl"..i,
                    imgui.ImVec2(imgui.GetWindowWidth() - 80, 22)) then
                    chat_selected = i
                    -- auto-set last_text/type/sender
                    last_text   = entry.text
                    last_type   = entry.atype
                    last_sender = entry.sender
                    ResetPF()
                    TryPrefetch(last_type, last_text)
                end
                imgui.PopStyleColor(3)
                if is_sel then imgui.PopStyleColor() end
                imgui.Spacing()
            end
            imgui.EndChild()
        end

        imgui.Spacing()
        -- action buttons
        local btn_w = (imgui.GetWindowWidth() - 24) / 3
        local has_sel = (chat_selected >= 1 and chat_log[chat_selected] ~= nil)

        -- response mode toggle: RP or Chat
        if not has_sel then
            imgui.BeginChild("##clmode", imgui.ImVec2(-1, 30), false)
            imgui.EndChild()
        else
            local sel = chat_log[chat_selected]
            -- toggle: force type override
            if not sel.mode_override then sel.mode_override = "auto" end

            imgui.BeginChild("##clmode", imgui.ImVec2(-1, 30), false)
            -- RP button
            local rp_active = (sel.mode_override == "rp" or sel.mode_override == "auto")
            if rp_active then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(.10,.40,.15,1))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(.15,.15,.18,1))
            end
            if imgui.Button("RP (/me /do)", imgui.ImVec2(btn_w, 24)) then
                sel.mode_override = "rp"
                -- force type to me or do
                if sel.atype == "dialog" then last_type = "me"
                else last_type = sel.atype end
                ResetPF()
                TryPrefetch(last_type, last_text)
            end
            imgui.PopStyleColor()
            imgui.SameLine()

            -- Chat button
            local chat_active = (sel.mode_override == "chat")
            if chat_active then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(.40,.25,.05,1))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(.15,.15,.18,1))
            end
            if imgui.Button("Chat (verbal)", imgui.ImVec2(btn_w, 24)) then
                sel.mode_override = "chat"
                last_type = "dialog"
                ResetPF()
                TryPrefetch(last_type, last_text)
            end
            imgui.PopStyleColor()
            imgui.SameLine()

            imgui.TextDisabled(sel.mode_override == "chat" and "Mode: verbal reply" or "Mode: RP action")
            imgui.EndChild()
        end
        imgui.Spacing()

        if not has_sel then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(.15,.15,.18,1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.15,.15,.18,1))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.15,.15,.18,1))
            imgui.Button("Auto-Smart##cl", imgui.ImVec2(btn_w, 30))
            imgui.SameLine()
            imgui.Button("Response List##cl", imgui.ImVec2(btn_w, 30))
            imgui.PopStyleColor(3)
        else
            imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.10,.40,.15,1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.15,.60,.22,1))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.08,.28,.10,1))
            if imgui.Button("Auto-Smart##cl", imgui.ImVec2(btn_w, 30)) then
                local sel = chat_log[chat_selected]
                if sel and sel.mode_override == "chat" then
                    last_type = "dialog"
                elseif sel and sel.mode_override == "rp" then
                    last_type = sel.atype == "dialog" and "me" or sel.atype
                end
                w_chatlog.v = false; SyncUI()
                SendAutoSmart()
                w_main.v = false
            end
            imgui.PopStyleColor(3)
            imgui.SameLine()
            if imgui.Button("Response List##cl", imgui.ImVec2(btn_w, 30)) then
                local sel = chat_log[chat_selected]
                if sel and sel.mode_override == "chat" then
                    last_type = "dialog"
                elseif sel and sel.mode_override == "rp" then
                    last_type = sel.atype == "dialog" and "me" or sel.atype
                end
                w_chatlog.v = false
                w_main.v = true
                generated = {}; status_msg = ""
                SyncUI()
                if prefetch_done and prefetch_result then
                    local cmd = GetCmd(last_type, true)
                    local ck  = CK(cmd, last_type, last_text)
                    CSe(ck, prefetch_result)
                    generated  = ParseResp(prefetch_result)
                    status_msg = "Prefetch ready - " .. #generated .. " responses"
                else
                    SendToServer(true, nil)
                end
            end
        end
        imgui.SameLine()
        if imgui.Button("Close##clw", imgui.ImVec2(btn_w, 30)) then
            w_chatlog.v = false; chat_selected = -1; SyncUI()
        end

        imgui.End()
        if not w_chatlog.v then SyncUI() end
    end

    -- MAIN WINDOW
    if not w_main.v then return end

    -- adaptive size for 1280x720 and higher
    local win_w = math.min(700, scrx - 40)
    local win_h = math.min(540, scry - 60)
    imgui.SetNextWindowSize(imgui.ImVec2(win_w, win_h), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(scrx/2 - win_w/2, scry/2 - win_h/2), imgui.Cond.FirstUseEver)
    imgui.Begin("  RP Respond AI 10.0  |  Sam Wilson  ", w_main, imgui.WindowFlags.NoResize)

    -- info
    imgui.BeginChild("##inf", imgui.ImVec2(-1, player_char ~= "" and 75 or 52), true)
        local tc = last_type == "dialog" and imgui.ImVec4(.9,.7,.2,1) or imgui.ImVec4(.4,.8,1,1)
        imgui.TextColored(tc, "Type: " .. TL(last_type))
        imgui.SameLine(); imgui.TextDisabled("  From: " .. last_sender)
        imgui.TextDisabled(UI(last_text ~= "" and last_text or "(nothing detected yet)"))
        local mode_label = response_mode == "chat" and "Chat (verbal)" or "RP (/me /do)"
        imgui.SameLine(imgui.GetWindowWidth() - 120)
        imgui.TextColored(
            response_mode == "chat" and imgui.ImVec4(1,.6,.2,1) or imgui.ImVec4(.3,.8,1,1),
            mode_label
        )
        if player_char ~= "" then
            imgui.TextColored(imgui.ImVec4(.4,.9,.5,1), "Char: " .. player_char:sub(1,80))
        end
    imgui.EndChild()
    imgui.Spacing()

    -- row 1
    local b1 = (imgui.GetWindowWidth()-30)/3
    if is_loading then
        imgui.TextDisabled("Thinking...")
    else
        imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.10,.40,.15,1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.15,.60,.22,1))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.08,.28,.10,1))
        if imgui.Button("Auto-Smart", imgui.ImVec2(b1,28)) then
            if response_mode == "chat" then last_type = "dialog" end
            SendAutoSmart()
        end
        imgui.PopStyleColor(3); imgui.SameLine()
        if imgui.Button("Auto Response", imgui.ImVec2(b1,28)) then
            if last_text ~= "" then
                if response_mode == "chat" then last_type = "dialog" end
                SendToServer(false, nil)
            else status_msg = "Nothing - use /jrpset" end
        end
        imgui.SameLine()
        local ll = prefetch_done and "Response List *" or "Response List"
        if imgui.Button(ll, imgui.ImVec2(b1,28)) then
            if last_text ~= "" then
                if response_mode == "chat" then last_type = "dialog" end
                if prefetch_done and prefetch_result then
                    local cmd = GetCmd(last_type, true)
                    local ck  = CK(cmd, last_type, last_text)
                    CSe(ck, prefetch_result)
                    generated  = ParseResp(prefetch_result)
                    status_msg = "Prefetch ready - " .. #generated .. " responses"
                else SendToServer(true, nil) end
            else status_msg = "Nothing - use /jrpset" end
        end
    end
    imgui.Spacing()

    -- row 2
    local b2 = (imgui.GetWindowWidth()-36)/4
    local b2b = (imgui.GetWindowWidth()-42)/5
    if imgui.Button("History", imgui.ImVec2(b2b,24)) then w_hist.v=true; SyncUI() end
    imgui.SameLine()
    if imgui.Button("Saved", imgui.ImVec2(b2b,24)) then w_cust.v=true; SyncUI() end
    imgui.SameLine()
    if imgui.Button("Character", imgui.ImVec2(b2b,24)) then
        buf_char=imgui.ImBuffer(player_char,256); w_char.v=true; SyncUI()
    end
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.40,.25,.05,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.65,.40,.10,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.25,.15,.03,1))
    if imgui.Button("Bases", imgui.ImVec2(b2b,24)) then w_base.v=true; SyncUI() end
    imgui.PopStyleColor(3)
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.20,.10,.40,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.35,.15,.65,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.12,.06,.25,1))
    local chatlog_lbl = #chat_log > 0 and ("Chat [" .. #chat_log .. "]") or "Chat Log"
    if imgui.Button(chatlog_lbl, imgui.ImVec2(b2b,24)) then
        w_chatlog.v = true; SyncUI()
    end
    imgui.PopStyleColor(3)
    imgui.Spacing()

    -- Response mode toggle: RP or Chat
    imgui.Spacing()
    local mode_bw = (imgui.GetWindowWidth() - 30) / 2
    local rp_active   = (response_mode == "rp")
    local chat_active = (response_mode == "chat")

    -- RP Mode button
    imgui.PushStyleColor(imgui.Col.Button,
        rp_active and imgui.ImVec4(.08,.38,.12,1) or imgui.ImVec4(.12,.16,.20,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.12,.55,.18,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.06,.25,.08,1))
    if imgui.Button(
        (rp_active and "[ RP Mode  /me /do ]" or "  RP Mode  /me /do  "),
        imgui.ImVec2(mode_bw, 28)) then
        response_mode = "rp"
        generated = {}; status_msg = ""
        if last_text ~= "" then
            if last_type == "dialog" then last_type = "me" end
            ResetPF(); TryPrefetch(last_type, last_text)
        end
    end
    imgui.PopStyleColor(3)
    imgui.SameLine()

    -- Chat Mode button
    imgui.PushStyleColor(imgui.Col.Button,
        chat_active and imgui.ImVec4(.45,.18,.04,1) or imgui.ImVec4(.12,.16,.20,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.65,.35,.08,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.28,.10,.02,1))
    if imgui.Button(
        (chat_active and "[ Chat Mode  verbal ]" or "  Chat Mode  verbal  "),
        imgui.ImVec2(mode_bw, 28)) then
        response_mode = "chat"
        generated = {}; status_msg = ""
        last_type = "dialog"
        ResetPF(); TryPrefetch(last_type, last_text)
    end
    imgui.PopStyleColor(3)

    imgui.Spacing()
    imgui.Checkbox("Auto-open on /me or /do", w_auto)
    if w_auto.v then imgui.SameLine(); imgui.TextColored(imgui.ImVec4(.4,1,.4,1), "  ON") end
    imgui.SameLine(imgui.GetWindowWidth()-80)
    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(.25,.25,.10,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(.50,.50,.15,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(.18,.18,.08,1))
    if imgui.Button("? Help", imgui.ImVec2(70,22)) then w_help.v=true; SyncUI() end
    imgui.PopStyleColor(3)

    imgui.Spacing()
    imgui.TextDisabled(status_msg)
    imgui.Separator(); imgui.Spacing()

    imgui.BeginChild("##rep", imgui.ImVec2(-1,-36), true)
    if #generated == 0 then
        local hint = prefetch_done and "* Prefetch ready - click Response List"
                                    or "Press a button above to generate responses"
        local w = imgui.GetWindowWidth()
        imgui.SetCursorPosY(imgui.GetWindowHeight()/2 - 10)
        imgui.SetCursorPosX(w/2 - imgui.CalcTextSize(hint).x/2)
        imgui.TextDisabled(hint)
    else
        for i, e in ipairs(generated) do
            ReplyRow(i, e, function(en) SendReply(en) end)
        end
    end
    imgui.EndChild()

    imgui.Spacing()
    if imgui.Button("Close", imgui.ImVec2(-1,26)) then
        w_main.v = false; SyncUI()
    end
    imgui.End()
    if not w_main.v then SyncUI() end
end

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------
function main()
    repeat wait(0) until isSampAvailable()


    math.randomseed(os.time())
    scrx, scry = getScreenResolution()
    Theme()
    EnsureDir()

    history     = LoadData(HISTORY_FILE)
    customs     = LoadData(CUSTOMS_FILE)
    player_char = LoadChar()
    bases       = LoadBases()

    wait(500)
    pcall(function()
        my_name = sampGetLocalPlayerNickname() or ""
    end)

    local active_key = USE_OR and API_KEY_OR or API_KEY
    local missing_key = not active_key or active_key == ""
        or (not USE_OR and active_key == "YOUR_GROQ_KEY_HERE")
    if missing_key then
        Say(USE_OR and "WARNING: Set API_KEY_OR in the script" or "WARNING: Set API_KEY in the script")
    else
        Say("RP Respond AI 10.0  |  Sam Wilson  |  /jrp")
    end
    if player_char ~= "" then Say("Character: " .. player_char:sub(1,50)) end

    local nb = 0
    for i = 1, BASE_MAX do if bases[i] then nb = nb + 1 end end
    if nb > 0 then Say("Active bases: " .. nb) end

    sampRegisterChatCommand("jrp", function()
        if my_last_was_me then Say("Last message was yours."); return end
        w_main.v = not w_main.v; SyncUI()
        if w_main.v then
            generated = {}; status_msg = ""
            if last_text == "" then
                status_msg = "Nothing detected - use /jrpset"
            elseif prefetch_done and prefetch_result then
                local cmd = GetCmd(last_type, true)
                local ck  = CK(cmd, last_type, last_text)
                CSe(ck, prefetch_result)
                generated  = ParseResp(prefetch_result)
                status_msg = "Prefetch ready - " .. #generated .. " responses"
            else
                SendToServer(true, nil)
            end
        end
    end)

    sampRegisterChatCommand("jrpset", function(arg)
        if not arg or arg == "" then
            Say("Usage: /jrpset me text  |  /jrpset do text"); return
        end
        local t, txt = arg:match("^(%S+)%s+(.+)$")
        if t == "do" and txt then
            last_type="do"; last_text=CleanText(txt); last_sender="manual"
        elseif t == "me" and txt then
            last_type="me"; last_text=CleanText(txt); last_sender="manual"
        else
            last_type="me"; last_text=CleanText(arg); last_sender="manual"
        end
        my_last_was_me=false; ResetPF(); generated={}; status_msg=""
        TryPrefetch(last_type, last_text)
        Say("Set - type /jrp"); w_main.v=true; SyncUI()
    end)

    sampRegisterChatCommand("jrplast", function()
        if last_text == "" then Say("Nothing detected")
        else Say(TL(last_type) .. " from " .. last_sender .. ": " .. last_text) end
    end)

    sampRegisterChatCommand("jrpchar", function(arg)
        if not arg or arg == "" then
            buf_char=imgui.ImBuffer(player_char,256); w_char.v=true; SyncUI(); return
        end
        if arg == "clear" then
            player_char=""; SaveChar(""); Say("Character cleared"); return
        end
        player_char=arg; SaveChar(player_char); Say("Character: " .. player_char)
    end)

    sampRegisterChatCommand("jrpbase", function()
        w_base.v=true; SyncUI()
    end)

    sampRegisterChatCommand("jrphistory", function()
        w_hist.v=true; SyncUI()
    end)

    sampRegisterChatCommand("jrpsave", function(arg)
        if not arg or arg == "" then
            buf_snname=imgui.ImBuffer(64); buf_sntext=imgui.ImBuffer(512)
            w_savenew.v=true; SyncUI(); return
        end
        if last_text == "" then Say("No text - use /jrpset first"); return end
        customs[#customs+1] = { name=arg, atype=last_type, text=last_text }
        SaveData(CUSTOMS_FILE, customs); Say("Saved: " .. arg)
    end)

    sampRegisterChatCommand("jrpsaved", function()
        w_cust.v=true; SyncUI()
    end)

    sampRegisterChatCommand("jrpauto", function()
        w_auto.v = not w_auto.v
        Say(w_auto.v and "Auto-open ON" or "Auto-open OFF")
    end)

    sampRegisterChatCommand("jrphelp", function()
        w_help.v=true; SyncUI()
    end)

    -- /jrpor: toggle between Groq and OpenRouter
    sampRegisterChatCommand("jrpor", function(arg)
        if arg == "set" then
            -- /jrpor set gsk_xxx  or  /jrpor set sk-or-xxx
            Say("Usage: /jrpor groq  or  /jrpor or")
            return
        end
        if arg == "or" then
            if API_KEY_OR == "" then
                Say("Set API_KEY_OR in script first - openrouter.ai")
                return
            end
            USE_OR = true
            model_idx = 1
            MODEL = MODELS_OR[1]
            ResetPF()
            Say("Switched to OpenRouter: " .. MODEL)
        else
            USE_OR = false
            model_idx = 1
            MODEL = MODELS[1]
            ResetPF()
            Say("Switched to Groq: " .. MODEL)
        end
    end)

    while true do wait(0) end
end

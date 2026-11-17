-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- lua_code_checker.rules.unverified_require (Lua port)
--
-- Flags: require('some.module') where 'some.module' is not in a
-- known allowlist of modules that ship with a standard MoonLoader +
-- SAMPFUNCS setup. A missing require() kills the ENTIRE script at
-- load time, before any of its other (working) code runs.
--------------------------------------------------------------

local M = {}

local KNOWN_SAFE = {}
for _, lib in ipairs({
    "moonloader", "sampfuncs", "imgui", "mimgui", "lfs",
    "vkeys", "encoding", "socket", "ffi",
}) do
    KNOWN_SAFE[lib] = true
end

local function stripQuotes(s)
    local result = s:gsub('^["\']', ""):gsub('["\']$', "")
    return result
end

function M.check(tokens, filename)
    local findings = {}
    local n = #tokens

    for i, tok in ipairs(tokens) do
        if tok.type == "identifier" and tok.value == "require" then
            local j = i + 1
            if j <= n and tokens[j].value == "(" then
                j = j + 1
            end
            if j <= n and tokens[j].type == "string" then
                local raw = stripQuotes(tokens[j].value)
                local anySafe = false
                for seg in (raw .. "."):gmatch("([^.]*)%.") do
                    if KNOWN_SAFE[seg:lower()] then
                        anySafe = true
                        break
                    end
                end
                if not anySafe then
                    findings[#findings + 1] = {
                        file = filename,
                        line = tok.line,
                        rule = "unverified-require",
                        severity = "warning",
                        message = "require '" .. raw .. "' is not in the base MoonLoader/SAMPFUNCS " ..
                            "module set. If this library isn't installed on the target machine, the " ..
                            "ENTIRE script fails to load - confirm it's actually present before " ..
                            "shipping, or wrap the require in pcall() so only the dependent feature is affected.",
                    }
                end
            end
        end
    end

    return findings
end

return M

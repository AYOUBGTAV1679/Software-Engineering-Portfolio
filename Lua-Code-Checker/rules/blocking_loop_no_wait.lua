-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- lua_code_checker.rules.blocking_loop_no_wait (Lua port)
--
-- Flags: while loops, and numeric for loops with a non-trivial bound,
-- whose body contains no call to wait(...) anywhere.
--
-- Carries all 4 real-world calibration rounds from the Python version:
--   v1: flagged every loop -> 63 false positives against real code
--   v2: narrowed to while + non-trivial numeric for
--   v3: fixed an arbitrary small-bound threshold and a multi-segment
--       require check (ported in unverified_require.lua)
--   v4: while-loops only flagged if nothing in the body "self-advances"
--       the condition (enumeration/probe idioms are safe); disclosed
--       blind spot: a reassigned condition var that might never
--       actually resolve is treated as safe, same as the Python version.
--------------------------------------------------------------

local M = {}

local function checkWhileSelfAdvancing(tokens, whileIdx, doIdx, bodyEndIdx)
    local conditionVars = {}
    local hasAny = false
    for idx = whileIdx + 1, doIdx - 1 do
        local t = tokens[idx]
        if t.type == "identifier" then
            conditionVars[t.value] = true
            hasAny = true
        end
    end
    if not hasAny then
        return true, "while-loop condition depends entirely on external calls."
    end

    for idx = doIdx + 1, bodyEndIdx - 1 do
        local t = tokens[idx]
        if t.type == "identifier" and conditionVars[t.value] then
            local nxt = tokens[idx + 1]
            local nxt2 = tokens[idx + 2]
            if nxt and nxt.value == "=" and (not nxt2 or nxt2.value ~= "=") then
                return false, "" -- self-advancing
            end
        end
    end

    return true, "while-loop condition depends on external/runtime state that nothing in its body appears to change directly."
end

local function shouldFlagKind(tokens, forIdx, doIdx, bodyEndIdx, loopKind)
    if loopKind == "while" then
        return checkWhileSelfAdvancing(tokens, forIdx, doIdx, bodyEndIdx)
    end

    local hasIn = false
    local commaPositions = {}
    for idx = forIdx, doIdx - 1 do
        local t = tokens[idx]
        if t.value == "in" then hasIn = true end
        if t.value == "," then commaPositions[#commaPositions + 1] = idx end
    end
    if hasIn then
        return false, "" -- generic-for, safe
    end
    if #commaPositions == 0 then
        return false, "" -- malformed/can't tell, don't guess
    end

    local boundStart = commaPositions[1] + 1
    local boundEnd = (commaPositions[2] or doIdx) - 1

    if boundStart == boundEnd and tokens[boundStart].type == "number" then
        return false, "" -- literal numeric bound always terminates
    end

    return true, "Its upper bound isn't a small fixed constant, so confirm it can't grow unbounded."
end

function M.check(tokens, filename)
    local findings = {}
    local n = #tokens
    local i = 1

    while i <= n do
        local tok = tokens[i]

        if tok.type == "keyword" and (tok.value == "while" or tok.value == "for") then
            local loopLine = tok.line
            local loopKind = tok.value

            local j = i + 1
            local depth = 0
            local doIdx = nil
            while j <= n do
                local t = tokens[j]
                if t.type == "keyword" and (t.value == "if" or t.value == "for" or t.value == "while" or t.value == "function") then
                    depth = depth + 1
                end
                if t.type == "keyword" and t.value == "do" and depth == 0 then
                    doIdx = j
                    break
                end
                if t.type == "keyword" and t.value == "end" then
                    depth = depth - 1
                end
                j = j + 1
            end

            if not doIdx then
                i = i + 1
                goto continue
            end

            local k = doIdx + 1
            local blockDepth = 1
            local hasWait = false

            while k <= n and blockDepth > 0 do
                local t = tokens[k]
                if t.type == "keyword" and (t.value == "if" or t.value == "for" or t.value == "while" or t.value == "function") then
                    blockDepth = blockDepth + 1
                end
                if t.type == "keyword" and t.value == "end" then
                    blockDepth = blockDepth - 1
                end
                if t.type == "identifier" and t.value == "wait" then
                    if k + 1 <= n and tokens[k + 1].value == "(" then
                        hasWait = true
                    end
                end
                k = k + 1
            end

            local shouldCheck, note = shouldFlagKind(tokens, i, doIdx, k, loopKind)
            if not shouldCheck then
                i = k
                goto continue
            end

            if not hasWait then
                findings[#findings + 1] = {
                    file = filename,
                    line = loopLine,
                    rule = "blocking-loop-no-wait",
                    severity = "warning",
                    message = loopKind .. " loop has no wait() call anywhere in its body. " ..
                        note .. " If its condition depends on runtime state and that state " ..
                        "never changes, this can freeze the entire game with no timeout.",
                }
            end

            i = k
            goto continue
        end

        i = i + 1
        ::continue::
    end

    return findings
end

return M

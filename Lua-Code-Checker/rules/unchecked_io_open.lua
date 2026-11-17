-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- lua_code_checker.rules.unchecked_io_open (Lua port)
--
-- Flags: local f = io.open(path, mode) ... f:write(...) / f:read(...)
--        with no "if f then" guard in between, and the chained form
--        io.open(...):write(...).
--------------------------------------------------------------

local M = {}

local function checkUsageGuarded(tokens, openParenIdx, n, varName, openLine, filename)
    local findings = {}
    local depth = 0
    local j = openParenIdx
    local started = false

    while j <= n do
        if tokens[j].value == "(" then
            depth = depth + 1
            started = true
        elseif tokens[j].value == ")" then
            depth = depth - 1
            if started and depth == 0 then
                j = j + 1
                break
            end
        end
        j = j + 1
    end

    local scanLimit = math.min(n, j + 400)
    while j <= scanLimit do
        local t = tokens[j]

        if t.type == "keyword" and t.value == "if" then
            local k = j + 1
            if k <= scanLimit and tokens[k] and tokens[k].value == "not" then
                k = k + 1
            end
            if k <= scanLimit and tokens[k] and tokens[k].value == varName then
                return {} -- guarded
            end
        end

        if t.type == "identifier" and t.value == varName then
            local nxt = (j + 1 <= scanLimit) and tokens[j + 1] or nil
            if nxt and nxt.value == ":" then
                local methodName = (tokens[j + 2] and tokens[j + 2].value) or "?"
                findings[#findings + 1] = {
                    file = filename,
                    line = t.line,
                    rule = "unchecked-io-open",
                    severity = "error",
                    message = "'" .. varName .. "' from io.open() at line " .. openLine ..
                        " is used here (:" .. methodName .. "(...)) without a prior 'if " ..
                        varName .. " then' check. If the file failed to open, this crashes the script.",
                }
                return findings
            end
            if nxt and (nxt.value == "==" or nxt.value == "~=") then
                return {} -- comparison guard - assume handled
            end
        end

        j = j + 1
    end

    return findings
end

function M.check(tokens, filename)
    local findings = {}
    local n = #tokens
    local i = 1

    while i <= n do
        local tok = tokens[i]

        if tok.type == "keyword" and tok.value == "local" and i + 6 <= n then
            local nameTok = tokens[i + 1]
            if nameTok.type == "identifier" then
                local j = i + 2
                if j <= n and tokens[j].value == "=" then
                    j = j + 1
                    if (j + 3 <= n
                            and tokens[j].value == "io"
                            and tokens[j + 1].value == "."
                            and tokens[j + 2].value == "open"
                            and tokens[j + 3].value == "(") then
                        local varName = nameTok.value
                        local openLine = tok.line
                        local extra = checkUsageGuarded(tokens, j, n, varName, openLine, filename)
                        for _, f in ipairs(extra) do findings[#findings + 1] = f end
                    end
                end
            end
        end

        if (tok.type == "identifier" and tok.value == "io"
                and i + 2 <= n and tokens[i + 1].value == "." and tokens[i + 2].value == "open") then
            local depth = 0
            local j = i + 3
            local started = false
            while j <= n do
                if tokens[j].value == "(" then
                    depth = depth + 1
                    started = true
                elseif tokens[j].value == ")" then
                    depth = depth - 1
                    if started and depth == 0 then
                        j = j + 1
                        break
                    end
                end
                j = j + 1
            end
            if j <= n and tokens[j].value == ":" then
                findings[#findings + 1] = {
                    file = filename,
                    line = tok.line,
                    rule = "unchecked-io-open",
                    severity = "error",
                    message = "io.open(...) result is used directly (chained method call) " ..
                        "without checking whether the open succeeded. If it fails, this crashes the whole script.",
                }
            end
        end

        i = i + 1
    end

    return findings
end

return M

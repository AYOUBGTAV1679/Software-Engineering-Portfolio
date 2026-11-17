-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- lua_code_checker.autofix (Lua port)
--
-- Deliberately narrow: only the standalone unverified-require form
-- gets auto-fixed (wrapped in pcall). Everything else stays a flagged
-- warning for a human to fix deliberately - the other three rules
-- (unchecked-io-open, io-popen-usage, blocking-loop-no-wait) depend
-- on context and intent that a mechanical rewrite can't know.
--------------------------------------------------------------

local M = {}

function M.applyRequireAutofix(source, findings)
    local lines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end

    local applied = {}

    local requireLines = {}
    for _, f in ipairs(findings) do
        if f.rule == "unverified-require" then
            requireLines[f.line] = true
        end
    end

    for idx, line in ipairs(lines) do
        if requireLines[idx] then
            local indent, arg = line:match('^(%s*)require%s*%(%s*(["\'][^"\']+["\'])%s*%)%s*$')
            if indent and arg then
                local newLine = indent .. "pcall(function() require(" .. arg .. ") end)"
                applied[#applied + 1] = { line = idx, before = line, after = newLine }
                lines[idx] = newLine
            else
                local indent2, arg2 = line:match('^(%s*)require%s+(["\'][^"\']+["\'])%s*$')
                if indent2 and arg2 then
                    local newLine = indent2 .. "pcall(function() require(" .. arg2 .. ") end)"
                    applied[#applied + 1] = { line = idx, before = line, after = newLine }
                    lines[idx] = newLine
                end
                -- assigned form (local x = require(...)) or anything else:
                -- intentionally left untouched.
            end
        end
    end

    return table.concat(lines, "\n"), applied
end

return M

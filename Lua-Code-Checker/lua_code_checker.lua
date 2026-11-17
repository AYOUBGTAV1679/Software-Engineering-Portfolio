-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- sw-lint (Lua port) - static analysis for MoonLoader/SA-MP Lua
-- scripts, self-hosted: written in the same language it analyzes.
--
-- Usage:
--   lua lua_code_checker.lua file1.lua [file2.lua ...]
--   lua lua_code_checker.lua --fix file.lua
--
-- Same four rules as the Python version, same real-world calibration
-- history (see README.md). This port adds nothing new rule-wise - it's
-- a faithful re-implementation, re-verified against the same
-- regression test.
--------------------------------------------------------------

-- Keep module loading reliable when invoked with either Unix or Windows paths.
local scriptDir = (arg and arg[0] and arg[0]:match("^(.*[/\\\\])")) or "./"
package.path = scriptDir .. "?.lua;" .. scriptDir .. "?/init.lua;" .. package.path

local tokenizer = require("tokenizer")
local ruleIoOpen   = require("rules.unchecked_io_open")
local rulePopen    = require("rules.io_popen_usage")
local ruleLoop     = require("rules.blocking_loop_no_wait")
local ruleRequire  = require("rules.unverified_require")
local autofix      = require("autofix")

local RULES = { ruleIoOpen, rulePopen, ruleLoop, ruleRequire }

local SEVERITY_ORDER = { error = 0, warning = 1, info = 2 }
local SEVERITY_LABEL = { error = "ERROR", warning = "WARN ", info = "INFO " }

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function lintFile(path)
    local source = readFile(path)
    if not source then return nil end

    local tokens = tokenizer.tokenize(source)

    local findings = {}
    for _, rule in ipairs(RULES) do
        local ruleFindings = rule.check(tokens, path)
        for _, f in ipairs(ruleFindings) do
            findings[#findings + 1] = f
        end
    end

    table.sort(findings, function(a, b)
        if a.line ~= b.line then return a.line < b.line end
        return (SEVERITY_ORDER[a.severity] or 9) < (SEVERITY_ORDER[b.severity] or 9)
    end)

    return findings, source
end

local function printFindings(findings)
    if #findings == 0 then
        print("  (clean - no findings)")
        return
    end
    for _, f in ipairs(findings) do
        local label = SEVERITY_LABEL[f.severity] or f.severity:upper()
        print(string.format("  [%s] line %5d  (%s)", label, f.line, f.rule))
        print("           " .. f.message)
    end
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function main()
    local paths = {}
    local doFix = false

    for _, a in ipairs(arg or {}) do
        if a == "--fix" then
            doFix = true
        else
            paths[#paths + 1] = a
        end
    end

    if #paths == 0 then
        io.stderr:write("usage: lua lua_code_checker.lua [--fix] file1.lua [file2.lua ...]\n")
        os.exit(2)
    end

    local totalErrors, totalWarnings, totalInfo = 0, 0, 0

    for _, path in ipairs(paths) do
        print("\n" .. path)
        local findings, source = lintFile(path)

        if not findings then
            print("  (could not open file)")
        else
            printFindings(findings)
            for _, f in ipairs(findings) do
                if f.severity == "error" then totalErrors = totalErrors + 1
                elseif f.severity == "warning" then totalWarnings = totalWarnings + 1
                else totalInfo = totalInfo + 1 end
            end

            if doFix then
                local fixedSource, applied = autofix.applyRequireAutofix(source, findings)
                if #applied > 0 then
                    local outPath = path:gsub("%.lua$", "") .. ".fixed.lua"
                    local outFile = io.open(outPath, "w")
                    if outFile then
                        outFile:write(fixedSource)
                        outFile:close()
                        print("  --fix: wrote " .. outPath .. " (" .. #applied .. " change(s)):")
                        for _, change in ipairs(applied) do
                            print("    line " .. change.line .. ": " ..
                                trim(change.before) .. "  ->  " .. trim(change.after))
                        end
                    else
                        print("  --fix: could not write " .. outPath)
                    end
                else
                    print("  --fix: nothing in this file matched the safe auto-fixable pattern.")
                end
            end
        end
    end

    print("\n" .. string.rep("-", 60))
    print(string.format("Scanned %d file(s): %d error(s), %d warning(s), %d info.",
        #paths, totalErrors, totalWarnings, totalInfo))

    os.exit(totalErrors > 0 and 1 or 0)
end

main()

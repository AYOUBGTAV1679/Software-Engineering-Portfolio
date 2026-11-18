-- Focused regressions for module resolution, token locations, and rule boundaries.
local tokenizer = require("tokenizer")
local requireRule = require("rules.unverified_require")
local popenRule = require("rules.io_popen_usage")
local loopRule = require("rules.blocking_loop_no_wait")
local autofix = require("autofix")

local passed = 0
local function check(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function findingsFor(rule, source)
    return rule.check(tokenizer.tokenize(source), "regression.lua")
end

check("known module root remains accepted with a submodule", function()
    assert(#findingsFor(requireRule, 'require("moonloader.some_submodule")') == 0)
end)

check("known word in a later segment does not allowlist unknown root", function()
    local findings = findingsFor(requireRule, 'require("custom.moonloader.untrusted")')
    assert(#findings == 1)
    assert(findings[1].rule == "unverified-require")
end)

check("escaped newline in a short string advances source line", function()
    local source = 'local text = "first\\' .. "\n" ..
        'second"\nrequire("custom.moonloader.untrusted")'
    local tokens = tokenizer.tokenize(source)
    local requireLine
    for _, token in ipairs(tokens) do
        if token.type == "identifier" and token.value == "require" then
            requireLine = token.line
            break
        end
    end
    assert(requireLine == 3, "expected the require token on line 3")
end)

check("io.popen function invocation is reported", function()
    local findings = findingsFor(popenRule, 'local f = io.popen("command")')
    assert(#findings == 1)
    assert(findings[1].rule == "io-popen-usage")
end)

check("io.popen function reference without invocation is not reported", function()
    assert(#findingsFor(popenRule, 'local openProcess = io.popen') == 0)
end)

check("wait after a nested do block is still seen by outer loop rule", function()
    local source = [[
while connected do
    do
        local snapshot = true
    end
    wait(0)
end
]]
    assert(#findingsFor(loopRule, source) == 0)
end)

check("nested do block does not hide a genuinely non-yielding loop", function()
    local source = [[
while connected do
    do
        local snapshot = true
    end
end
]]
    local findings = findingsFor(loopRule, source)
    assert(#findings == 1)
    assert(findings[1].rule == "blocking-loop-no-wait")
end)

check("safe autofix changes only standalone require calls", function()
    local source = 'require("optional_module")\nlocal module = require("assigned_module")'
    local findings = {
        { rule = "unverified-require", line = 1 },
        { rule = "unverified-require", line = 2 },
    }
    local fixed, applied = autofix.applyRequireAutofix(source, findings)
    assert(#applied == 1)
    assert(fixed:find('pcall(function() require("optional_module") end)', 1, true))
    assert(fixed:find('local module = require("assigned_module")', 1, true))
end)

print(string.format("Lua Code Checker regression tests: %d checks passed", passed))

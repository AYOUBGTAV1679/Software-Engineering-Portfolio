-- Focused regression checks for lexer line tracking and require allowlisting.
local tokenizer = require("tokenizer")
local requireRule = require("rules.unverified_require")

local function findingsFor(source)
    return requireRule.check(tokenizer.tokenize(source), "regression.lua")
end

-- A known module root remains accepted even when it has a submodule.
assert(#findingsFor('require("moonloader.some_submodule")') == 0,
    "known top-level module root should remain allowlisted")

-- A known word in a later segment must not allowlist an unknown root.
local unknownFindings = findingsFor('require("custom.moonloader.untrusted")')
assert(#unknownFindings == 1,
    "unknown root module must be reported even if a later segment is known")
assert(unknownFindings[1].rule == "unverified-require",
    "unexpected rule for unknown root module")

-- An escaped newline inside a short string advances the source line number.
local multilineSource = 'local text = "first\\' .. "\n" ..
    'second"\nrequire("custom.moonloader.untrusted")'
local tokens = tokenizer.tokenize(multilineSource)
local requireLine
for _, token in ipairs(tokens) do
    if token.type == "identifier" and token.value == "require" then
        requireLine = token.line
        break
    end
end
assert(requireLine == 3,
    "token line tracking after an escaped newline should report line 3")

print("Lua Code Checker regression tests passed.")

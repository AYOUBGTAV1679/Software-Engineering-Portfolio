-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- lua_code_checker.rules.io_popen_usage (Lua port)
--
-- Flags: any call to io.popen(...). On Windows this spawns a real
-- cmd.exe process - can flash a visible console window and trigger
-- anti-cheat termination in a game-client script.
--------------------------------------------------------------

local M = {}

function M.check(tokens, filename)
    local findings = {}
    local n = #tokens

    for i, tok in ipairs(tokens) do
        local nextCallToken = i + 3
        while tokens[nextCallToken]
            and (tokens[nextCallToken].type == "newline"
                or tokens[nextCallToken].type == "comment") do
            nextCallToken = nextCallToken + 1
        end

        if (tok.type == "identifier" and tok.value == "io"
                and i + 2 <= n
                and tokens[i + 1].value == "."
                and tokens[i + 2].value == "popen"
                and tokens[nextCallToken]
                and tokens[nextCallToken].value == "(") then
            findings[#findings + 1] = {
                file = filename,
                line = tok.line,
                rule = "io-popen-usage",
                severity = "error",
                message = "io.popen() spawns a real external process (cmd.exe on Windows). " ..
                    "In a game-client script this can flash a visible console window and may " ..
                    "cause anti-cheat systems to silently terminate the game. Prefer engine-native " ..
                    "file listing (e.g. findFirstFile/findNextFile/findClose) instead.",
            }
        end
    end

    return findings
end

return M

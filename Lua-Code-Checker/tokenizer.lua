-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- lua_code_checker.tokenizer (Lua port of tokenizer.py)
--------------------------------------------------------------

local KEYWORDS = {}
for _, kw in ipairs({
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
}) do
    KEYWORDS[kw] = true
end

local M = {}
M.KEYWORDS = KEYWORDS

local function countNewlines(s)
    local n = 0
    for _ in s:gmatch("\n") do n = n + 1 end
    return n
end

function M.tokenize(source)
    local tokens = {}
    local i = 1
    local n = #source
    local line = 1

    local function peek(offset)
        local j = i + (offset or 0)
        if j > n then return "" end
        return source:sub(j, j)
    end

    local function push(ttype, value, atLine)
        tokens[#tokens + 1] = { type = ttype, value = value, line = atLine or line }
    end

    while i <= n do
        local c = source:sub(i, i)

        if c == "\n" then
            push("newline", "\n", line)
            line = line + 1
            i = i + 1

        elseif c == " " or c == "\t" or c == "\r" then
            i = i + 1

        elseif c == "-" and peek(1) == "-" then
            local startLine = line
            i = i + 2
            if peek() == "[" then
                local level = 0
                local j = i + 1
                while j <= n and source:sub(j, j) == "=" do
                    level = level + 1
                    j = j + 1
                end
                if j <= n and source:sub(j, j) == "[" then
                    local close = "]" .. string.rep("=", level) .. "]"
                    local closeStart, closeEnd = source:find(close, j + 1, true)
                    local text
                    if not closeStart then
                        text = source:sub(i)
                        i = n + 1
                    else
                        text = source:sub(i, closeEnd)
                        i = closeEnd + 1
                    end
                    line = line + countNewlines(text)
                    push("comment", text, startLine)
                    goto continue
                end
            end
            local eol = source:find("\n", i, true)
            local text
            if not eol then
                text = source:sub(i)
                i = n + 1
            else
                text = source:sub(i, eol - 1)
                i = eol
            end
            push("comment", text, startLine)

        elseif c == "[" and (peek(1) == "[" or peek(1) == "=") then
            local j = i + 1
            local level = 0
            while j <= n and source:sub(j, j) == "=" do
                level = level + 1
                j = j + 1
            end
            if j <= n and source:sub(j, j) == "[" then
                local startLine = line
                local close = "]" .. string.rep("=", level) .. "]"
                local closeStart, closeEnd = source:find(close, j + 1, true)
                local text
                if not closeStart then
                    text = source:sub(i)
                    i = n + 1
                else
                    text = source:sub(i, closeEnd)
                    i = closeEnd + 1
                end
                line = line + countNewlines(text)
                push("string", text, startLine)
            else
                push("operator", c, line)
                i = i + 1
            end

        elseif c == '"' or c == "'" then
            local quote = c
            local startLine = line
            local j = i + 1
            local buf = { c }
            while j <= n do
                local ch = source:sub(j, j)
                buf[#buf + 1] = ch
                if ch == "\\" and j + 1 <= n then
                    local escaped = source:sub(j + 1, j + 1)
                    buf[#buf + 1] = escaped
                    if escaped == "\n" then
                        line = line + 1
                    end
                    j = j + 2
                    goto innercontinue
                end
                if ch == quote then
                    j = j + 1
                    break
                end
                if ch == "\n" then line = line + 1 end
                j = j + 1
                ::innercontinue::
            end
            push("string", table.concat(buf), startLine)
            i = j

        elseif c:match("%d") or (c == "." and peek(1):match("%d")) then
            local j = i
            while j <= n and source:sub(j, j):match("[%w.xX]") do
                j = j + 1
            end
            push("number", source:sub(i, j - 1), line)
            i = j

        elseif c:match("[%a_]") then
            local j = i
            while j <= n and source:sub(j, j):match("[%w_]") do
                j = j + 1
            end
            local word = source:sub(i, j - 1)
            push(KEYWORDS[word] and "keyword" or "identifier", word, line)
            i = j

        else
            push("operator", c, line)
            i = i + 1
        end

        ::continue::
    end

    return tokens
end

return M

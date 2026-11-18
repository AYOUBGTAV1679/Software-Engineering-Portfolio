-- crash_guard_log_cursor
-- Track appended log lines and detect truncation/replacement through the
-- previous checkpoint line, not only the current line count.
local M = {}

function M.collectNewLines(allLines, previousCount, previousLastLine)
    if type(allLines) ~= "table" then
        return {}, 0, nil, true
    end

    local count = tonumber(previousCount) or 0
    count = math.max(0, math.floor(count))
    local reset = count > #allLines
    if not reset and count > 0 and previousLastLine ~= nil then
        reset = allLines[count] ~= previousLastLine
    end

    local firstNew = reset and 1 or count + 1
    local added = {}
    for i = firstNew, #allLines do
        added[#added + 1] = allLines[i]
    end
    return added, #allLines, allLines[#allLines], reset
end

return M

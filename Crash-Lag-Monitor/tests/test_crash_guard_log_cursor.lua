package.path = "./?.lua;" .. package.path

local cursor = require("crash_guard_log_cursor")
local passed = 0

local function check(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function same(actual, expected)
    assert(#actual == #expected, "line count differs")
    for i = 1, #expected do
        assert(actual[i] == expected[i], "line " .. i .. " differs")
    end
end

check("first read returns all existing lines", function()
    local added, count, last, reset = cursor.collectNewLines({"boot", "ready"}, 0, nil)
    same(added, {"boot", "ready"})
    assert(count == 2 and last == "ready" and not reset)
end)

check("append-only read returns only the new suffix", function()
    local added, count, last, reset = cursor.collectNewLines({"boot", "ready", "joined"}, 2, "ready")
    same(added, {"joined"})
    assert(count == 3 and last == "joined" and not reset)
end)

check("unchanged log returns no duplicate lines", function()
    local added, count, last, reset = cursor.collectNewLines({"boot", "ready"}, 2, "ready")
    same(added, {})
    assert(count == 2 and last == "ready" and not reset)
end)

check("shorter truncated log resets and replays its current contents", function()
    local added, count, last, reset = cursor.collectNewLines({"new boot"}, 5, "old final line")
    same(added, {"new boot"})
    assert(count == 1 and last == "new boot" and reset)
end)

check("replacement with same or greater line count is detected", function()
    local added, count, last, reset = cursor.collectNewLines(
        {"rotated boot", "new error", "new tail"}, 2, "old checkpoint")
    same(added, {"rotated boot", "new error", "new tail"})
    assert(count == 3 and last == "new tail" and reset)
end)

check("empty file clears the old checkpoint", function()
    local added, count, last, reset = cursor.collectNewLines({}, 3, "old tail")
    same(added, {})
    assert(count == 0 and last == nil and reset)
end)

check("same checkpoint line preserves a valid append cursor", function()
    local added, count, last, reset = cursor.collectNewLines(
        {"one", "two", "same checkpoint", "new tail"}, 3, "same checkpoint")
    same(added, {"new tail"})
    assert(count == 4 and last == "new tail" and not reset)
end)

print(string.format("Crash Guard log-cursor regression suite: %d checks passed", passed))

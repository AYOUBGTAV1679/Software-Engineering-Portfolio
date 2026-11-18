package.path = "./?.lua;" .. package.path

local writer = require("crash_guard_log_writer")
local passed = 0

local function check(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function fakeFile(writeFn, closeFn)
    local file = { closed = false, written = nil }
    function file:write(record)
        self.written = record
        if writeFn then return writeFn(self, record) end
        return self
    end
    function file:close()
        self.closed = true
        if closeFn then return closeFn(self) end
        return true
    end
    return file
end

check("successful append writes the exact record and closes", function()
    local file = fakeFile()
    local ok = writer.append(function(path, mode)
        assert(path == "warnings.log" and mode == "a")
        return file
    end, "warnings.log", "warning\n")
    assert(ok)
    assert(file.written == "warning\n" and file.closed)
end)

check("open returning nil reports failure", function()
    local ok, err = writer.append(function() return nil, "access denied" end,
        "warnings.log", "warning\n")
    assert(not ok and err:find("access denied", 1, true))
end)

check("open throwing is contained", function()
    local ok, err = writer.append(function() error("open fault") end,
        "warnings.log", "warning\n")
    assert(not ok and err:find("open fault", 1, true))
end)

check("write returning nil still closes the handle", function()
    local file = fakeFile(function() return nil, "disk full" end)
    local ok, err = writer.append(function() return file end,
        "warnings.log", "warning\n")
    assert(not ok and err:find("disk full", 1, true))
    assert(file.closed)
end)

check("write throwing still closes the handle", function()
    local file = fakeFile(function() error("write fault") end)
    local ok, err = writer.append(function() return file end,
        "warnings.log", "warning\n")
    assert(not ok and err:find("write fault", 1, true))
    assert(file.closed)
end)

check("close returning nil reports failure", function()
    local file = fakeFile(nil, function() return nil, "close failed" end)
    local ok, err = writer.append(function() return file end,
        "warnings.log", "warning\n")
    assert(not ok and err:find("close failed", 1, true))
    assert(file.closed)
end)

check("close throwing is contained", function()
    local file = fakeFile(nil, function() error("close fault") end)
    local ok, err = writer.append(function() return file end,
        "warnings.log", "warning\n")
    assert(not ok and err:find("close fault", 1, true))
    assert(file.closed)
end)

print(string.format("Crash Guard log-writer regression suite: %d checks passed", passed))

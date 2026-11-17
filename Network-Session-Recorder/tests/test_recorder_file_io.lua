package.path = "./?.lua;" .. package.path

local fileIO = require("recorder_file_io")
local passed = 0

local function fakeFile(options)
	options = options or {}
	local file = {
		writes = {},
		flushCalls = 0,
		closeCalls = 0,
		closed = false
	}
	function file:write(data)
		if options.writeThrows then error(options.writeThrows) end
		if options.writeError then return nil, options.writeError end
		self.writes[#self.writes + 1] = data
		return self
	end
	function file:flush()
		self.flushCalls = self.flushCalls + 1
		if options.flushThrows then error(options.flushThrows) end
		if options.flushError then return nil, options.flushError end
		return true
	end
	function file:close()
		self.closeCalls = self.closeCalls + 1
		if options.closeThrows then error(options.closeThrows) end
		if options.closeError then return nil, options.closeError end
		self.closed = true
		return true
	end
	return file
end

local function check(name, callback)
	local ok, err = pcall(callback)
	assert(ok, name .. ": " .. tostring(err))
	passed = passed + 1
	print("PASS " .. name)
end

check("successful write", function()
	local file = fakeFile()
	assert(fileIO.write(file, "event\\n"))
	assert(file.writes[1] == "event\\n")
end)

check("reported write error", function()
	local ok, err = fileIO.write(fakeFile({writeError = "disk full"}), "event")
	assert(not ok and err:find("disk full", 1, true))
end)

check("thrown write error", function()
	local ok, err = fileIO.write(fakeFile({writeThrows = "write exploded"}), "event")
	assert(not ok and err:find("write exploded", 1, true))
end)

check("successful finalization flushes and closes", function()
	local file = fakeFile()
	assert(fileIO.finalize(file))
	assert(file.flushCalls == 1 and file.closeCalls == 1 and file.closed)
end)

check("flush error still attempts close", function()
	local file = fakeFile({flushError = "disk full"})
	local ok, err = fileIO.finalize(file)
	assert(not ok and err:find("flush failed", 1, true))
	assert(file.flushCalls == 1 and file.closeCalls == 1 and file.closed)
end)

check("thrown flush error still attempts close", function()
	local file = fakeFile({flushThrows = "flush exploded"})
	local ok, err = fileIO.finalize(file)
	assert(not ok and err:find("flush exploded", 1, true))
	assert(file.closeCalls == 1 and file.closed)
end)

check("close error is reported", function()
	local file = fakeFile({closeError = "device error"})
	local ok, err = fileIO.finalize(file)
	assert(not ok and err:find("close failed", 1, true))
	assert(file.flushCalls == 1 and file.closeCalls == 1)
end)

check("both finalization errors are retained", function()
	local file = fakeFile({flushError = "flush issue", closeError = "close issue"})
	local ok, err = fileIO.finalize(file)
	assert(not ok)
	assert(err:find("flush issue", 1, true) and err:find("close issue", 1, true))
	assert(file.closeCalls == 1)
end)

check("nil handle is already finalized", function()
	assert(fileIO.finalize(nil))
end)

print(string.format("Recorder file-I/O regression suite: %d checks passed", passed))

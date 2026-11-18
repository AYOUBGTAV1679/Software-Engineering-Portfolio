package.path = "./?.lua;" .. package.path

local RecorderEpoch = require("recorder_epoch")
local passed = 0

local function check(name, callback)
	local ok, err = pcall(callback)
	assert(ok, name .. ": " .. tostring(err))
	passed = passed + 1
	print("PASS " .. name)
end

check("first connection handshake remains current", function()
	local state = RecorderEpoch.new()
	local token = state:begin()
	assert(state:is_current(token))
end)

check("new INITGAME invalidates older delayed callback", function()
	local state = RecorderEpoch.new()
	local oldToken = state:begin()
	local newToken = state:begin()
	assert(not state:is_current(oldToken))
	assert(state:is_current(newToken))
end)

check("multiple reconnects accept only the latest callback", function()
	local state = RecorderEpoch.new()
	local tokens = {}
	for i = 1, 5 do tokens[i] = state:begin() end
	for i = 1, 4 do assert(not state:is_current(tokens[i])) end
	assert(state:is_current(tokens[5]))
end)

check("current callback stays valid until a newer INITGAME", function()
	local state = RecorderEpoch.new()
	local token = state:begin()
	assert(state:is_current(token))
	assert(state:is_current(token))
	state:begin()
	assert(not state:is_current(token))
end)

print(string.format("Recorder handshake epoch regression suite: %d checks passed", passed))

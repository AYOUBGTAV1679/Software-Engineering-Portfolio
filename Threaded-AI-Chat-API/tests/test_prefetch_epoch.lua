package.path = "./?.lua;" .. package.path

local PrefetchEpoch = require("prefetch_epoch")
local passed = 0

local function check(name, callback)
	local ok, err = pcall(callback)
	assert(ok, name .. ": " .. tostring(err))
	passed = passed + 1
	print("PASS " .. name)
end

check("new request receives current token", function()
	local state = PrefetchEpoch.new()
	local token = state:begin()
	assert(state:is_current(token))
end)

check("reset invalidates pending callback", function()
	local state = PrefetchEpoch.new()
	local token = state:begin()
	state:invalidate()
	assert(not state:is_current(token))
end)

check("new request supersedes previous request", function()
	local state = PrefetchEpoch.new()
	local oldToken = state:begin()
	local newToken = state:begin()
	assert(not state:is_current(oldToken))
	assert(state:is_current(newToken))
end)

check("cached result invalidation rejects older response", function()
	local state = PrefetchEpoch.new()
	local pending = state:begin()
	state:invalidate()
	assert(not state:is_current(pending))
end)

check("later reset also invalidates replacement request", function()
	local state = PrefetchEpoch.new()
	local first = state:begin()
	state:invalidate()
	local second = state:begin()
	state:invalidate()
	assert(not state:is_current(first))
	assert(not state:is_current(second))
end)

check("interactive response epoch rejects callbacks after context reset", function()
	local state = PrefetchEpoch.new()
	local request = state:begin()
	state:invalidate()
	assert(not state:is_current(request))
end)

check("prefetch and interactive response epochs are independent", function()
	local prefetch = PrefetchEpoch.new()
	local response = PrefetchEpoch.new()
	local prefetchToken = prefetch:begin()
	local responseToken = response:begin()
	response:invalidate()
	assert(prefetch:is_current(prefetchToken))
	assert(not response:is_current(responseToken))
end)

print(string.format("AI async epoch regression suite: %d checks passed", passed))

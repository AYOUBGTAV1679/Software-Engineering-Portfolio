package.path = "./?.lua;" .. package.path

local VideoTiming = require("video_timing")
local passed = 0

local function check(name, callback)
	local ok, err = pcall(callback)
	assert(ok, name .. ": " .. tostring(err))
	passed = passed + 1
	print("PASS " .. name)
end

local function near(actual, expected)
	assert(math.abs(actual - expected) < 0.000001,
		string.format("expected %.8f, got %.8f", expected, actual))
end

check("first frame uses fallback and accepts its timestamp", function()
	local delay, valid = VideoTiming.next_delay(nil, 0)
	near(delay, 1 / 30)
	assert(valid)
end)

check("variable frame interval follows presentation timestamps", function()
	local delay, valid = VideoTiming.next_delay(1.0, 1.04)
	near(delay, 0.04)
	assert(valid)
end)

check("duplicate timestamps use fallback", function()
	local delay, valid = VideoTiming.next_delay(2.5, 2.5)
	near(delay, 1 / 30)
	assert(valid)
end)

check("backward timestamps use fallback", function()
	local delay, valid = VideoTiming.next_delay(3.0, 2.9)
	near(delay, 1 / 30)
	assert(valid)
end)

check("large timestamp gaps use fallback", function()
	local delay, valid = VideoTiming.next_delay(0, 8)
	near(delay, 1 / 30)
	assert(valid)
end)

check("missing and non-finite timestamps are rejected", function()
	local delay, valid = VideoTiming.next_delay(0, 0 / 0)
	near(delay, 1 / 30)
	assert(not valid)
	local infiniteDelay, infiniteValid = VideoTiming.next_delay(0, math.huge)
	near(infiniteDelay, 1 / 30)
	assert(not infiniteValid)
end)

print(string.format("Video timing regression suite: %d checks passed", passed))

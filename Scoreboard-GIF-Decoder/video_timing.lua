-- Selects the next video-frame interval from presentation timestamps.
-- Native video remains experimental; this module is pure Lua and independently testable.
local M = {}

local FALLBACK_DELAY = 1 / 30
local MAX_PTS_DELTA = 5

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

function M.next_delay(previousPts, currentPts)
	local validCurrent = isFiniteNumber(currentPts)
	if validCurrent and isFiniteNumber(previousPts) then
		local delta = currentPts - previousPts
		if delta > 0 and delta <= MAX_PTS_DELTA then
			return delta, true
		end
	end
	return FALLBACK_DELAY, validCurrent
end

return M

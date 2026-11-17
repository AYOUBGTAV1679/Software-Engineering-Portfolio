-- Generation tokens prevent stale asynchronous prefetch callbacks from
-- mutating state after the current chat context has changed.
local M = {}

function M.new()
	local generation = 0
	local state = {}

	function state:begin()
		generation = generation + 1
		return generation
	end

	function state:invalidate()
		generation = generation + 1
		return generation
	end

	function state:is_current(token)
		return token == generation
	end

	return state
end

return M

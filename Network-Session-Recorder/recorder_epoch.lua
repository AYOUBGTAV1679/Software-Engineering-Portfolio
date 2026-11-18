-- Generation tokens prevent delayed connection-handshake callbacks from
-- an older INITGAME event from mutating the current recorder cache.
local M = {}

function M.new()
	local generation = 0
	local state = {}

	function state:begin()
		generation = generation + 1
		return generation
	end

	function state:is_current(token)
		return token == generation
	end

	return state
end

return M

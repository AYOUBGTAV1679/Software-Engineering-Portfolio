-- Generation tokens prevent delayed connection-handshake callbacks from
-- an older INITGAME event from mutating the current recorder cache.
local M = {}

function M.new()
	local generation = 0
	local includedGeneration = nil
	local state = {}

	function state:begin()
		generation = generation + 1
		return generation
	end

	function state:current()
		return generation
	end

	function state:is_current(token)
		return token == generation
	end

	function state:needs_init(token)
		return token == generation and includedGeneration ~= token
	end

	function state:mark_included(token)
		if token == generation then
			includedGeneration = token
			return true
		end
		return false
	end

	return state
end

return M

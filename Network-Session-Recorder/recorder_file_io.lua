-- Checked file operations used by the session recorder.
-- Kept independent of MoonLoader so failure paths can be tested with fake handles.
local M = {}

function M.write(file, data)
	local ok, result, err = pcall(function()
		return file:write(data)
	end)
	if not ok then return nil, tostring(result) end
	if not result then return nil, tostring(err or "write failed") end
	return true
end

function M.flush(file)
	local ok, result, err = pcall(function()
		return file:flush()
	end)
	if not ok then return nil, tostring(result) end
	if not result then return nil, tostring(err or "flush failed") end
	return true
end

function M.close(file)
	local ok, result, err = pcall(function()
		return file:close()
	end)
	if not ok then return nil, tostring(result) end
	if not result then return nil, tostring(err or "close failed") end
	return true
end

function M.finalize(file)
	if file == nil then return true end

	-- Always try to close, even when flushing has failed.
	local flushOk, flushError = M.flush(file)
	local closeOk, closeError = M.close(file)
	if not flushOk or not closeOk then
		local errors = {}
		if not flushOk then errors[#errors + 1] = "flush failed: " .. tostring(flushError) end
		if not closeOk then errors[#errors + 1] = "close failed: " .. tostring(closeError) end
		return nil, table.concat(errors, "; ")
	end
	return true
end

return M

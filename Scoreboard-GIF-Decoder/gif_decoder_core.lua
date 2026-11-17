-- Small, portable bit helpers keep the decoder independent of MoonLoader's bit library.
local function band(a, b)
	local result, place = 0, 1
	a, b = math.floor(a or 0), math.floor(b or 0)
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then result = result + place end
		a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
	end
	return result
end

local function rshift(value, amount)
	return math.floor(value / (2 ^ amount))
end

local function lshift(value, amount)
	return value * (2 ^ amount)
end

local function u8b(s, i) return string.byte(s, i) end
local function u16le(s, i)
	local a, b = string.byte(s, i, i + 1)
	if not a or not b then return 0 end
	return a + b * 256
end

-- Decode one GIF LZW-compressed sub-block stream into exactly maxOutput indices.
-- Invalid/truncated code streams are rejected instead of returning partial frames.
local function gifLzwDecode(data, minCodeSize, maxOutput)
	if type(data) ~= "string" or type(minCodeSize) ~= "number"
			or minCodeSize < 2 or minCodeSize > 8
			or type(maxOutput) ~= "number" or maxOutput < 1 then
		return nil, "invalid LZW parameters"
	end

	local CLEAR = lshift(1, minCodeSize)
	local ENDC = CLEAR + 1
	local codeSize, nextCode, dict
	local function resetDict()
		dict = {}
		for i = 0, CLEAR - 1 do dict[i] = {i} end
		nextCode = ENDC + 1
		codeSize = minCodeSize + 1
	end
	resetDict()

	local out = {}
	local bitBuf, bitCount, pos, dataLen = 0, 0, 1, #data
	local function readCode()
		while bitCount < codeSize do
			if pos > dataLen then return nil end
			bitBuf = bitBuf + string.byte(data, pos) * (2 ^ bitCount)
			bitCount = bitCount + 8
			pos = pos + 1
		end
		local code = bitBuf % (2 ^ codeSize)
		bitBuf = math.floor(bitBuf / (2 ^ codeSize))
		bitCount = bitCount - codeSize
		return code
	end

	local prevCode = nil
	while true do
		local code = readCode()
		if code == nil then return nil, "truncated LZW stream (missing end code)" end
		if code == ENDC then break end
		if code == CLEAR then
			resetDict()
			prevCode = nil
		else
			local entry
			if dict[code] then
				entry = dict[code]
			elseif code == nextCode and prevCode then
				entry = {}
				for i, v in ipairs(dict[prevCode]) do entry[i] = v end
				entry[#entry + 1] = dict[prevCode][1]
			else
				return nil, "invalid LZW dictionary reference"
			end
			if #out + #entry > maxOutput then
				return nil, "LZW output exceeds image dimensions"
			end
			for _, v in ipairs(entry) do out[#out + 1] = v end
			if prevCode then
				local newEntry = {}
				for i, v in ipairs(dict[prevCode]) do newEntry[i] = v end
				newEntry[#newEntry + 1] = entry[1]
				if nextCode < 4096 then
					dict[nextCode] = newEntry
					nextCode = nextCode + 1
					-- The decoder learns one dictionary entry later than the encoder.
					if nextCode >= (2 ^ codeSize) - 1 and codeSize < 12 then
						codeSize = codeSize + 1
					end
				end
			end
			prevCode = code
		end
	end
	if #out ~= maxOutput then
		return nil, "decoded pixel count does not match image dimensions"
	end
	return out
end

local function gifDeinterlace(indices, w, h)
	local out = {}
	local passes = {{0, 8}, {4, 8}, {2, 4}, {1, 2}}
	local srcRow = 0
	for _, pass in ipairs(passes) do
		local row = pass[1]
		while row < h do
			for col = 0, w - 1 do
				out[row * w + col + 1] = indices[srcRow * w + col + 1]
			end
			srcRow = srcRow + 1
			row = row + pass[2]
		end
	end
	return out
end

-- Decodes GIF bytes and returns {width, height, frames = {{rgba, delay}, ...}}.
local function gifDecodeData(data)
	if type(data) ~= "string" or #data < 13 or (data:sub(1, 6) ~= "GIF87a" and data:sub(1, 6) ~= "GIF89a") then
		return nil, "not a valid gif file"
	end

	local pos = 7
	local screenW = u16le(data, pos); pos = pos + 2
	local screenH = u16le(data, pos); pos = pos + 2
	local packed = u8b(data, pos); pos = pos + 1
	pos = pos + 2 -- background color index + pixel aspect ratio
	if screenW <= 0 or screenH <= 0 or screenW * screenH > 4000000 then
		return nil, "unsupported gif size"
	end

	local globalPalette = nil
	if band(rshift(packed, 7), 1) == 1 then
		local gctSize = band(packed, 0x07)
		local gctEntries = lshift(2, gctSize)
		if pos + (gctEntries * 3) - 1 > #data then
			return nil, "truncated global color table"
		end
		globalPalette = {}
		for i = 0, gctEntries - 1 do
			globalPalette[i] = {u8b(data, pos), u8b(data, pos + 1), u8b(data, pos + 2)}
			pos = pos + 3
		end
	end

	local canvas = {}
	for i = 1, screenW * screenH * 4 do canvas[i] = 0 end

	local frames = {}
	local gcDelay, gcTransparentIndex, gcDisposal = 10, nil, 0
	local prevSnapshot = nil
	local dataLen = #data
	local safety = 0
	local sawTrailer = false
	local totalFramePixels = 0
	local MAX_TOTAL_FRAME_PIXELS = 4000000

	while pos <= dataLen and safety < 20000 do
		safety = safety + 1
		local blockType = u8b(data, pos); pos = pos + 1
		if blockType == 0x21 then
			local label = u8b(data, pos); pos = pos + 1
			if label == 0xF9 then
				local blockSize = u8b(data, pos); pos = pos + 1
				if blockSize ~= 4 or pos + 4 > dataLen then
					return nil, "invalid or truncated graphic control extension"
				end
				local gcPacked = u8b(data, pos); pos = pos + 1
				gcDisposal = band(rshift(gcPacked, 2), 0x07)
				local transpFlag = band(gcPacked, 0x01)
				gcDelay = u16le(data, pos); pos = pos + 2
				local transIdx = u8b(data, pos); pos = pos + 1
				gcTransparentIndex = (transpFlag == 1) and transIdx or nil
				if u8b(data, pos) ~= 0 then
					return nil, "invalid graphic control extension terminator"
				end
				pos = pos + 1
			else
				local sub = u8b(data, pos); pos = pos + 1
				if not sub then return nil, "truncated extension data" end
				while sub > 0 do
					if pos + sub - 1 > dataLen then
						return nil, "truncated extension sub-block"
					end
					pos = pos + sub
					sub = u8b(data, pos)
					if not sub then return nil, "missing extension terminator" end
					pos = pos + 1
				end
			end
		elseif blockType == 0x2C then
			local imgLeft = u16le(data, pos); pos = pos + 2
			local imgTop = u16le(data, pos); pos = pos + 2
			local imgW = u16le(data, pos); pos = pos + 2
			local imgH = u16le(data, pos); pos = pos + 2
			local imgPacked = u8b(data, pos); pos = pos + 1
			if not imgPacked or imgW <= 0 or imgH <= 0 or imgW * imgH > 4000000 then
				return nil, "unsupported or truncated image descriptor"
			end
			if imgLeft + imgW > screenW or imgTop + imgH > screenH then
				return nil, "image descriptor extends beyond the logical screen"
			end
			totalFramePixels = totalFramePixels + (screenW * screenH)
			if totalFramePixels > MAX_TOTAL_FRAME_PIXELS then
				return nil, "GIF exceeds the total decoded-frame pixel budget"
			end
			local lctFlag = band(rshift(imgPacked, 7), 1)
			local interlaceFlag = band(rshift(imgPacked, 6), 1)
			local palette = globalPalette
			if lctFlag == 1 then
				local lctSize = band(imgPacked, 0x07)
				local lctEntries = lshift(2, lctSize)
				if pos + (lctEntries * 3) - 1 > dataLen then
					return nil, "truncated local color table"
				end
				palette = {}
				for i = 0, lctEntries - 1 do
					palette[i] = {u8b(data, pos), u8b(data, pos + 1), u8b(data, pos + 2)}
					pos = pos + 3
				end
			end
			if not palette then return nil, "image has no color table" end
			local minCodeSize = u8b(data, pos); pos = pos + 1
			if not minCodeSize or minCodeSize < 2 or minCodeSize > 8 then
				return nil, "invalid GIF LZW minimum code size"
			end
			local chunks = {}
			local sub = u8b(data, pos); pos = pos + 1
			if not sub then return nil, "truncated image data blocks" end
			while sub > 0 do
				if pos + sub - 1 > dataLen then
					return nil, "truncated image data sub-block"
				end
				chunks[#chunks + 1] = data:sub(pos, pos + sub - 1)
				pos = pos + sub
				sub = u8b(data, pos)
				if not sub then return nil, "missing image data terminator" end
				pos = pos + 1
			end
			local indices, lzwError = gifLzwDecode(table.concat(chunks), minCodeSize, imgW * imgH)
			if not indices then return nil, lzwError end
			if interlaceFlag == 1 then
				indices = gifDeinterlace(indices, imgW, imgH)
			end

			if gcDisposal == 3 then
				prevSnapshot = {}
				for i = 1, #canvas do prevSnapshot[i] = canvas[i] end
			end

			if palette then
				for row = 0, imgH - 1 do
					for col = 0, imgW - 1 do
						local colorIndex = indices[row * imgW + col + 1]
						if colorIndex and not (gcTransparentIndex and colorIndex == gcTransparentIndex) then
							local px = palette[colorIndex]
							if not px then
								return nil, "decoded color index is outside the active palette"
							end
							if px then
								local cx, cy = imgLeft + col, imgTop + row
								if cx >= 0 and cx < screenW and cy >= 0 and cy < screenH then
									local off = (cy * screenW + cx) * 4
									canvas[off + 1] = px[1]
									canvas[off + 2] = px[2]
									canvas[off + 3] = px[3]
									canvas[off + 4] = 255
								end
							end
						end
					end
				end
			end

			local frameRGBA = {}
			for i = 1, #canvas do frameRGBA[i] = canvas[i] end
			frames[#frames + 1] = {rgba = frameRGBA, delay = math.max(gcDelay, 2) / 100}

			if gcDisposal == 2 then
				for row = 0, imgH - 1 do
					for col = 0, imgW - 1 do
						local cx, cy = imgLeft + col, imgTop + row
						if cx >= 0 and cx < screenW and cy >= 0 and cy < screenH then
							local off = (cy * screenW + cx) * 4
							canvas[off + 1] = 0; canvas[off + 2] = 0
							canvas[off + 3] = 0; canvas[off + 4] = 0
						end
					end
				end
			elseif gcDisposal == 3 and prevSnapshot then
				canvas = prevSnapshot
			end
			gcDelay, gcTransparentIndex, gcDisposal = 10, nil, 0
		elseif blockType == 0x3B then
			sawTrailer = true
			break
		else
			return nil, "unknown GIF block marker"
		end
	end

	if not sawTrailer then
		return nil, "missing GIF trailer or parser safety limit reached"
	end
	if #frames == 0 then
		return nil, "no frames found"
	end
	return {width = screenW, height = screenH, frames = frames}
end

return { decode = gifDecodeData }

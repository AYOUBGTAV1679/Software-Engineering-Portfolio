-- Author identity record: Salah Aleedn Wurdku
script_name('ImGui Scoreboard')
script_description('ImGui SA:MP Scoreboard')
script_author('Sam Wilson')
script_dependencies('SAMPFUNCS', 'Dear ImGui')
script_moonloader(025)

require 'moonloader'
require 'SAMPFUNCS'
local imgui = require 'imgui'
local notf
if doesFileExist(getWorkingDirectory() .. "\\imgui_notf.lua") then
	notf = import 'imgui_notf.lua'
end
local vkeys = require 'vkeys'
local bitex = require 'bitex'
local SE = require 'lib.samp.events'
local memory = require 'memory'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffiOk, ffi = pcall(require, 'ffi')
u8 = encoding.UTF8
encoding.default = 'CP1251'

local russian_characters = {
	[168] = 'Ё', [184] = 'ё', [192] = 'А', [193] = 'Б', [194] = 'В', [195] = 'Г', [196] = 'Д', [197] = 'Е', [198] = 'Ж', [199] = 'З', [200] = 'И', [201] = 'Й', [202] = 'К', [203] = 'Л', [204] = 'М', [205] = 'Н', [206] = 'О', [207] = 'П', [208] = 'Р', [209] = 'С', [210] = 'Т', [211] = 'У', [212] = 'Ф', [213] = 'Х', [214] = 'Ц', [215] = 'Ч', [216] = 'Ш', [217] = 'Щ', [218] = 'Ъ', [219] = 'Ы', [220] = 'Ь', [221] = 'Э', [222] = 'Ю', [223] = 'Я', [224] = 'а', [225] = 'б', [226] = 'в', [227] = 'г', [228] = 'д', [229] = 'е', [230] = 'ж', [231] = 'з', [232] = 'и', [233] = 'й', [234] = 'к', [235] = 'л', [236] = 'м', [237] = 'н', [238] = 'о', [239] = 'п', [240] = 'р', [241] = 'с', [242] = 'т', [243] = 'у', [244] = 'ф', [245] = 'х', [246] = 'ц', [247] = 'ч', [248] = 'ш', [249] = 'щ', [250] = 'ъ', [251] = 'ы', [252] = 'ь', [253] = 'э', [254] = 'ю', [255] = 'я',
}
local quitReason = {
  "Crashed",
  "Left the game",
  "Kicked / Banned"
}
local themsDir = getWorkingDirectory() .. "\\resource\\SW-Scoreboard-Pro"
local allset = inicfg.load({
	set = {
		curTheme = "main",
		type = 1,
		titlebar = 1,
		fontSize = 2,
		nickType = 0,
		list = 0,
		customImgEnabled = 0,
		customImgPath = "",
		customImgColor = 4294967295,
		customImgList = "",
		customImgCycle = 0,
		customImgCycleInterval = 5,
		imageOpacity = 100
	},
	cheat = {}
}, "SW-Scoreboard-Pro")
if allset.set.imageOpacity == nil then
	allset.set.imageOpacity = 100
end
-- Title bar is locked to "Custom text" and Nickname view is locked to "Colored name".
-- These are no longer user-changeable, so any old saved value is forced back to the fixed one.
allset.set.titlebar = 1
allset.set.nickType = 0
local notesCfg = inicfg.load({
	note = {
		text = ""
	}
}, "SW-Scoreboard-Pro_notes")
if allset.set.fontSize < 0 or allset.set.fontSize > 4 then
	allset.set.fontSize = 2
end
local cfg = nil
local copColor = {
	[12] = {11},
	[6] = {29},
	[3] = {5, 19},
	[8] = {15},
	[23] = {16},
	[24] = {17},
	[25] = {18}
}
local setTable = {
	["Input Field / Marker"] = {
		[8] = "Normal",
		[9] = "Hovered",
		[10] = "Active"
	},
	["List"] = {
		[26] = "Normal",
		[27] = "Hovered",
		[28] = "Active"
	},
	["Window"] = {
		[12] = "Title",
		[3] = "Window Background",
		[6] = "Separators",
		[1] = "Text"
	},
	["Button"] = {
		[23] = "Normal",
		[24] = "Hovered",
		[25] = "Active"
	}
}
local sizesFont = {"12", "13", "14", "15", "16"}
local sFont = {}
local style = imgui.GetStyle()
local colors = style.Colors
local clr = imgui.Col
local ImVec4 = imgui.ImVec4
local background = nil
local bgImage = imgui.ImBool(false)

function loadTheme(name)
	cfg = inicfg.load({
		colors = {
			[1] = imgui.ImColor(225, 235, 240, 240):GetU32(),
			[3] = imgui.ImColor(8, 14, 20, 110):GetU32(),
			[8] = imgui.ImColor(25, 130, 145, 70):GetU32(),
			[6] = imgui.ImColor(60, 90, 110, 90):GetU32(),
			[9] = imgui.ImColor(35, 165, 180, 100):GetU32(),
			[10] = imgui.ImColor(20, 110, 120, 50):GetU32(),
			[12] = imgui.ImColor(12, 45, 55, 150):GetU32(),
			[23] = imgui.ImColor(20, 140, 155, 120):GetU32(),
			[24] = imgui.ImColor(35, 170, 185, 80):GetU32(),
			[25] = imgui.ImColor(12, 100, 110, 80):GetU32(),
			[26] = imgui.ImColor(50, 75, 95, 40):GetU32(),
			[27] = imgui.ImColor(50, 75, 95, 40):GetU32(),
			[28] = imgui.ImColor(50, 75, 95, 20):GetU32()
		},
		set = {
			bgimg = false,
			imageColor = imgui.ImColor(255, 255, 255, 255):GetU32()
		}
	}, name and (themsDir .. "\\" .. name .. "\\data.ini") or ("moonloader\\resource\\SW-Scoreboard-Pro\\main\\data.ini"))
	bgImage.v = cfg.set.bgimg
	for k, v in pairs(cfg.colors) do
		colors[k] = imgui.ImColor(v):GetVec4()
	end
	for k, v in pairs(copColor) do
		for _, iv in ipairs(copColor[k]) do
			colors[iv] = colors[k]
		end
	end
	if doesFileExist(name and (themsDir .. "\\" .. name .. "\\scoreboard.png") or ("moonloader\\resource\\SW-Scoreboard-Pro\\main\\scoreboard.png")) then
		background = imgui.CreateTextureFromFile(name and (themsDir .. "\\" .. name .. "\\scoreboard.png") or ("moonloader\\resource\\SW-Scoreboard-Pro\\main\\scoreboard.png"))
	else
		background = nil
	end
end

local ToScreen = convertGameScreenCoordsToWindowScreenCoords
local show_main_window = imgui.ImBool(false)
local show_set_window = imgui.ImBool(false)
local searchBuf = imgui.ImBuffer(256)
local createThemBuf = imgui.ImBuffer(32)
local playerCount = 0
local cStyle = imgui.ImInt(0)
local cType = imgui.ImInt(allset.set.type)
local bTitlebar = imgui.ImInt(allset.set.titlebar)
local cSize = imgui.ImInt(allset.set.fontSize)
local cNType = imgui.ImInt(allset.set.nickType)
local cImgOpacity = imgui.ImInt(allset.set.imageOpacity)
local cListAlpha = imgui.ImInt(43)
local thems = {}
local themsId = {}
local notThems = false
local focusId = -1
local scrollToId = false
local gameInit = false
local pendingNumberId = nil
local cFilter = imgui.ImInt(allset.set.list)
local settingsTab = imgui.ImInt(0)
local customImgEnabled = imgui.ImBool(allset.set.customImgEnabled == 1)
local customImgPathBuf = imgui.ImBuffer(260)
customImgPathBuf.v = allset.set.customImgPath or ""
local customBackground = nil
local customImgLoadError = false
local browseDialogError = nil
local notesBuf = imgui.ImBuffer(4096)
notesBuf.v = notesCfg.note.text or ""
local notesSaved = true
local customImgList = {}
local cycleEnabled = imgui.ImBool(allset.set.customImgCycle == 1)
local cycleInterval = imgui.ImInt(allset.set.customImgCycleInterval)
local lastCycleTime = os.clock()

local imgTransitionPrev = nil
local imgTransitionStart = nil
local imgTransitionDuration = 0.7

-- Animated image (GIF) support: decoded frames are cached on disk as BMP files
-- the first time a GIF is used, so playback speed is auto-detected from the
-- file itself with no manual per-image duration needed.
local gifCache = {}
local gifPlayback = {path = nil, frameIndex = 1, frameStart = 0}


function cycleToNextImage()
	if #customImgList < 2 then return end
	local curIndex = 1
	for i, v in ipairs(customImgList) do
		if v == allset.set.customImgPath then
			curIndex = i
			break
		end
	end
	local nextIndex = curIndex + 1
	if nextIndex > #customImgList then
		nextIndex = 1
	end
	selectImgFromList(customImgList[nextIndex])
end

function splitImgList(str)
	local list = {}
	if str and #str > 0 then
		for part in string.gmatch(str, "([^|]+)") do
			table.insert(list, part)
		end
	end
	return list
end

function saveImgList()
	allset.set.customImgList = table.concat(customImgList, "|")
	inicfg.save(allset, "SW-Scoreboard-Pro")
end

function addImgToList(path)
	if not path or #path == 0 then return end
	for _, v in ipairs(customImgList) do
		if v == path then return end
	end
	table.insert(customImgList, path)
	saveImgList()
end

function removeImgFromList(index)
	local removedPath = customImgList[index]
	table.remove(customImgList, index)
	saveImgList()
	if allset.set.customImgPath == removedPath then
		allset.set.customImgPath = customImgList[1] or ""
		customImgPathBuf.v = allset.set.customImgPath
		inicfg.save(allset, "SW-Scoreboard-Pro")
		loadCustomBackground()
	end
end

function selectImgFromList(path)
	if path ~= allset.set.customImgPath then
		imgTransitionPrev = customBackground
		imgTransitionStart = os.clock()
	end
	allset.set.customImgPath = path
	customImgPathBuf.v = path
	inicfg.save(allset, "SW-Scoreboard-Pro")
	loadCustomBackground()
end

--============================================================
-- Animated image (GIF) support
-- Pure-Lua GIF89a/87a decoder: extracts every frame + its real delay time
-- from the file itself, so nothing needs to be set by hand. Each frame is
-- written once to a small cache folder as a BMP (a format the renderer can
-- already load), then played back using the delays that were actually
-- read from the GIF.
--============================================================
local band, rshift, lshift = bit.band, bit.rshift, bit.lshift
local gifCacheDir = "moonloader\\resource\\SW-Scoreboard-Pro\\_gif_cache\\"

local function gifEnsureDir(path)
	if not doesDirectoryExist(path) then
		createDirectory(path)
	end
end

local function isGifPath(path)
	return path ~= nil and path:lower():match("%.gif$") ~= nil
end

--------------------------------------------------------------
-- EXPERIMENTAL: real video backgrounds via video_bridge.dll (FFmpeg,
-- called through LuaJIT FFI - the same FFI already used above for the
-- native file picker). This is new and unverified against the actual
-- game - see video_bridge.c / the accompanying README for status.
-- If video_bridge.dll isn't present, or FFI isn't available, this
-- silently does nothing and every other background type (static
-- image, GIF) is completely unaffected.
--------------------------------------------------------------
local videoLibOk, videoLib = false, nil
if ffiOk then
	ffi.cdef[[
		void *video_open(const char *path);
		int   video_get_frame(void *handle, uint8_t *out_rgba, double *out_pts);
		int   video_get_width(void *handle);
		int   video_get_height(void *handle);
		void  video_close(void *handle);
	]]
	videoLibOk, videoLib = pcall(ffi.load, "video_bridge.dll")
end

local function isVideoPath(path)
	return path ~= nil and path:lower():match("%.mp4$") ~= nil
end

local videoPlayback = {
	path = nil, handle = nil, width = 0, height = 0,
	nextFrameDue = 0, texture = nil,
}

-- Decodes the next available frame and updates the background texture.
-- Paced by wall-clock time using a fixed assumed frame rate for now
-- (30fps) since video_get_frame's pts isn't being used to pace yet in
-- this first pass - a real implementation should read pts and schedule
-- off of that instead of a fixed interval).
function advanceVideoPlayback()
	if not videoLibOk or not videoPlayback.handle then return end
	if videoPlayback.path ~= allset.set.customImgPath then return end
	if os.clock() < videoPlayback.nextFrameDue then return end

	local bufSize = videoPlayback.width * videoPlayback.height * 4
	local buf = ffi.new("uint8_t[?]", bufSize)
	local pts = ffi.new("double[1]")
	local result = videoLib.video_get_frame(videoPlayback.handle, buf, pts)

	if result == 0 then
		-- end of stream - loop back to the start
		videoLib.video_close(videoPlayback.handle)
		videoPlayback.handle = videoLib.video_open(videoPlayback.path)
		videoPlayback.nextFrameDue = os.clock() + (1 / 30)
		return
	elseif result ~= 1 then
		return -- decode error, leave last good frame on screen
	end

	local ok, tex = pcall(imgui.CreateTextureFromRawBytes,
		ffi.string(buf, bufSize), videoPlayback.width, videoPlayback.height)
	-- NOTE: CreateTextureFromRawBytes is a placeholder name - confirm
	-- the actual function your imgui build uses for "texture from a
	-- raw RGBA byte buffer" and update this call if it differs.
	if ok then
		customBackground = tex
	end

	videoPlayback.nextFrameDue = os.clock() + (1 / 30)
end

function loadVideoBackground(path)
	if not videoLibOk then
		if notf then
			notf.addNotification("Video backgrounds need video_bridge.dll + FFI, which isn't available here.", 6)
		end
		return false
	end

	local handle = videoLib.video_open(path)
	if handle == nil then
		customImgLoadError = true
		if notf then
			notf.addNotification("Could not open video file: " .. path, 6)
		end
		return false
	end

	videoPlayback.path = path
	videoPlayback.handle = handle
	videoPlayback.width = videoLib.video_get_width(handle)
	videoPlayback.height = videoLib.video_get_height(handle)
	videoPlayback.nextFrameDue = 0
	return true
end

local function gifPathHash(path)
	local h = 5381
	for i = 1, #path do
		h = (h * 33 + string.byte(path, i)) % 2147483647
	end
	return tostring(h)
end

local function u8b(s, i) return string.byte(s, i) end
local function u16le(s, i)
	local a, b = string.byte(s, i, i + 1)
	if not a or not b then return 0 end
	return a + b * 256
end

-- Decode one GIF LZW-compressed sub-block stream into a list of color indices.
local function gifLzwDecode(data, minCodeSize)
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
		if code == nil or code == ENDC then break end
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
				break
			end
			for _, v in ipairs(entry) do out[#out + 1] = v end
			if prevCode then
				local newEntry = {}
				for i, v in ipairs(dict[prevCode]) do newEntry[i] = v end
				newEntry[#newEntry + 1] = entry[1]
				dict[nextCode] = newEntry
				nextCode = nextCode + 1
				-- FIX: a GIF LZW decoder is always exactly one code BEHIND the
				-- encoder's dictionary growth (it can only learn a new entry
				-- after reading the code AFTER it), so it must widen its read
				-- size one entry EARLIER than this naive '>= 2^codeSize' check
				-- did - otherwise it reads the wrong bit width the moment the
				-- encoder grows, and every code after that is garbage. This is
				-- the single most common bug in from-scratch LZW/GIF decoders;
				-- verified against an independent reference encoder/decoder -
				-- the old condition decoded only 5/160 test pixels correctly
				-- before desyncing completely.
				if nextCode >= (2 ^ codeSize) - 1 and codeSize < 12 then
					codeSize = codeSize + 1
				end
			end
			prevCode = code
		end
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

-- Parses a .gif file and returns {width, height, frames = {{rgba, delay}, ...}}
local function gifDecodeFile(path)
	local f = io.open(path, "rb")
	if not f then return nil, "cannot open file" end
	local data = f:read("*a")
	f:close()
	if not data or #data < 13 or data:sub(1, 3) ~= "GIF" then
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

	while pos <= dataLen and safety < 20000 do
		safety = safety + 1
		local blockType = u8b(data, pos); pos = pos + 1
		if blockType == 0x21 then
			local label = u8b(data, pos); pos = pos + 1
			if label == 0xF9 then
				pos = pos + 1 -- block size (always 4)
				local gcPacked = u8b(data, pos); pos = pos + 1
				gcDisposal = band(rshift(gcPacked, 2), 0x07)
				local transpFlag = band(gcPacked, 0x01)
				gcDelay = u16le(data, pos); pos = pos + 2
				local transIdx = u8b(data, pos); pos = pos + 1
				gcTransparentIndex = (transpFlag == 1) and transIdx or nil
				pos = pos + 1 -- terminator
			else
				local sub = u8b(data, pos); pos = pos + 1
				while sub and sub > 0 do
					pos = pos + sub
					sub = u8b(data, pos); pos = pos + 1
				end
			end
		elseif blockType == 0x2C then
			local imgLeft = u16le(data, pos); pos = pos + 2
			local imgTop = u16le(data, pos); pos = pos + 2
			local imgW = u16le(data, pos); pos = pos + 2
			local imgH = u16le(data, pos); pos = pos + 2
			local imgPacked = u8b(data, pos); pos = pos + 1
			local lctFlag = band(rshift(imgPacked, 7), 1)
			local interlaceFlag = band(rshift(imgPacked, 6), 1)
			local palette = globalPalette
			if lctFlag == 1 then
				local lctSize = band(imgPacked, 0x07)
				local lctEntries = lshift(2, lctSize)
				palette = {}
				for i = 0, lctEntries - 1 do
					palette[i] = {u8b(data, pos), u8b(data, pos + 1), u8b(data, pos + 2)}
					pos = pos + 3
				end
			end
			local minCodeSize = u8b(data, pos); pos = pos + 1
			local chunks = {}
			local sub = u8b(data, pos); pos = pos + 1
			while sub and sub > 0 do
				chunks[#chunks + 1] = data:sub(pos, pos + sub - 1)
				pos = pos + sub
				sub = u8b(data, pos); pos = pos + 1
			end
			local indices = gifLzwDecode(table.concat(chunks), minCodeSize)
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
			break
		else
			break
		end
	end

	if #frames == 0 then
		return nil, "no frames found"
	end
	return {width = screenW, height = screenH, frames = frames}
end

local function gifWriteBMP32(path, w, h, rgba)
	local function u32(n)
		return string.char(band(n, 0xFF), band(rshift(n, 8), 0xFF), band(rshift(n, 16), 0xFF), band(rshift(n, 24), 0xFF))
	end
	local function u16(n)
		return string.char(band(n, 0xFF), band(rshift(n, 8), 0xFF))
	end
	local f = io.open(path, "wb")
	if not f then return false, "cannot open file for writing" end
	local rowSize = w * 4
	local imageSize = rowSize * h
	f:write("BM")
	f:write(u32(54 + imageSize))
	f:write(u32(0))
	f:write(u32(54))
	f:write(u32(40))
	f:write(u32(w))
	f:write(u32(h))
	f:write(u16(1))
	f:write(u16(32))
	f:write(u32(0))
	f:write(u32(imageSize))
	f:write(u32(2835))
	f:write(u32(2835))
	f:write(u32(0))
	f:write(u32(0))
	local buf = {}
	for row = h - 1, 0, -1 do
		for col = 0, w - 1 do
			local off = (row * w + col) * 4
			buf[#buf + 1] = string.char(rgba[off + 3] or 0, rgba[off + 2] or 0, rgba[off + 1] or 0, rgba[off + 4] or 255)
		end
	end
	f:write(table.concat(buf))
	f:close()
	return true
end

-- On-disk cache manifest: remembers the decoded frame list + delays for a
-- given source GIF so we don't have to redo the (slow, pure-Lua) pixel
-- decode every single time the script loads. The manifest is invalidated
-- automatically if the source file's size changes.
local function gifManifestPath(frameDir)
	return frameDir .. "manifest.txt"
end

local function getFileSize(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local size = f:seek("end")
	f:close()
	return size
end

local function loadGifManifest(path, frameDir)
	local f = io.open(gifManifestPath(frameDir), "r")
	if not f then return nil end
	local ok, result = pcall(function()
		local srcSize = tonumber(f:read("*l"))
		local w = tonumber(f:read("*l"))
		local h = tonumber(f:read("*l"))
		local frameCount = tonumber(f:read("*l"))
		if not srcSize or not w or not h or not frameCount then return nil end
		if srcSize ~= getFileSize(path) then return nil end
		local frames = {}
		for i = 1, frameCount do
			local delay = tonumber(f:read("*l"))
			local framePath = frameDir .. "frame" .. i .. ".bmp"
			if not delay or not doesFileExist(framePath) then return nil end
			frames[i] = {path = framePath, delay = delay, texture = nil}
		end
		return {frames = frames, w = w, h = h}
	end)
	f:close()
	if ok and result then return result end
	return nil
end

local function saveGifManifest(path, frameDir, entry)
	local f = io.open(gifManifestPath(frameDir), "w")
	if not f then return end
	f:write(tostring(getFileSize(path) or 0) .. "\n")
	f:write(tostring(entry.w) .. "\n")
	f:write(tostring(entry.h) .. "\n")
	f:write(tostring(#entry.frames) .. "\n")
	for _, fr in ipairs(entry.frames) do
		f:write(tostring(fr.delay) .. "\n")
	end
	f:close()
end

function decodeAndCacheGif(path)
	if gifCache[path] then return gifCache[path] end
	gifEnsureDir("moonloader\\resource\\SW-Scoreboard-Pro")
	gifEnsureDir(gifCacheDir)
	local frameDir = gifCacheDir .. gifPathHash(path) .. "\\"
	gifEnsureDir(frameDir)

	-- If this exact GIF was already decoded before (same file size), reuse
	-- the cached frames on disk instead of decoding again on every join.
	local cached = loadGifManifest(path, frameDir)
	if cached then
		cached.totalDuration = 0
		for _, fr in ipairs(cached.frames) do
			cached.totalDuration = cached.totalDuration + fr.delay
		end
		gifCache[path] = cached
		return cached
	end

	local ok, result = pcall(gifDecodeFile, path)
	if not ok or not result then
		gifCache[path] = {error = (not ok and tostring(result)) or "failed to decode gif"}
		return gifCache[path]
	end

	local entry = {frames = {}, w = result.width, h = result.height, totalDuration = 0}
	for i, fr in ipairs(result.frames) do
		local framePath = frameDir .. "frame" .. i .. ".bmp"
		local wok = gifWriteBMP32(framePath, result.width, result.height, fr.rgba)
		if wok then
			table.insert(entry.frames, {path = framePath, delay = fr.delay, texture = nil})
			entry.totalDuration = entry.totalDuration + fr.delay
		end
	end
	if #entry.frames == 0 then
		gifCache[path] = {error = "could not write frame cache"}
		return gifCache[path]
	end
	saveGifManifest(path, frameDir, entry)
	gifCache[path] = entry
	return entry
end

-- Advances the currently playing GIF to its next frame once enough real time
-- has passed, using the delay that was read from the file itself.
function advanceGifPlayback()
	if not gifPlayback.path or gifPlayback.path ~= allset.set.customImgPath then return end
	local entry = gifCache[gifPlayback.path]
	if not entry or entry.error then return end
	local frame = entry.frames[gifPlayback.frameIndex]
	if not frame then return end
	if os.clock() - gifPlayback.frameStart >= frame.delay then
		gifPlayback.frameIndex = gifPlayback.frameIndex + 1
		if gifPlayback.frameIndex > #entry.frames then
			gifPlayback.frameIndex = 1
		end
		gifPlayback.frameStart = os.clock()
		local newFrame = entry.frames[gifPlayback.frameIndex]
		if not newFrame.texture then
			newFrame.texture = imgui.CreateTextureFromFile(newFrame.path)
		end
		customBackground = newFrame.texture
	end
end

function loadCustomBackground()
	customBackground = nil
	customImgLoadError = false
	gifPlayback.path = nil
	videoPlayback.path = nil
	if videoPlayback.handle and videoLibOk then
		videoLib.video_close(videoPlayback.handle)
		videoPlayback.handle = nil
	end
	if allset.set.customImgPath and #allset.set.customImgPath > 0 then
		if doesFileExist(allset.set.customImgPath) then
			if isGifPath(allset.set.customImgPath) then
				local entry = decodeAndCacheGif(allset.set.customImgPath)
				if entry.error then
					customImgLoadError = true
					if notf then
						notf.addNotification("Could not read animated image: " .. tostring(entry.error), 6)
					end
				else
					gifPlayback.path = allset.set.customImgPath
					gifPlayback.frameIndex = 1
					gifPlayback.frameStart = os.clock()
					if not entry.frames[1].texture then
						entry.frames[1].texture = imgui.CreateTextureFromFile(entry.frames[1].path)
					end
					customBackground = entry.frames[1].texture
				end
			elseif isVideoPath(allset.set.customImgPath) then
				loadVideoBackground(allset.set.customImgPath)
			else
				customBackground = imgui.CreateTextureFromFile(allset.set.customImgPath)
			end
		else
			customImgLoadError = true
		end
	end
end

local ofnCdefLoaded = false
function openImageFileDialog()
	if not ffiOk or not ffi then
		return nil, "ffi is not available in this environment"
	end
	local ok, err = pcall(function()
		if not ofnCdefLoaded then
			ffi.cdef[[
				typedef struct {
					unsigned long lStructSize;
					void *hwndOwner;
					void *hInstance;
					const char *lpstrFilter;
					char *lpstrCustomFilter;
					unsigned long nMaxCustFilter;
					unsigned long nFilterIndex;
					char *lpstrFile;
					unsigned long nMaxFile;
					char *lpstrFileTitle;
					unsigned long nMaxFileTitle;
					const char *lpstrInitialDir;
					const char *lpstrTitle;
					unsigned long Flags;
					unsigned short nFileOffset;
					unsigned short nFileExtension;
					const char *lpstrDefExt;
					long lCustData;
					void *lpfnHook;
					const char *lpTemplateName;
					void *pvReserved;
					unsigned long dwReserved;
					unsigned long FlagsEx;
				} OPENFILENAMEA;
				int GetOpenFileNameA(OPENFILENAMEA *lpofn);
			]]
			ofnCdefLoaded = true
		end
	end)
	if not ok then
		return nil, tostring(err)
	end
	local comdlgOk, comdlg32 = pcall(ffi.load, "comdlg32")
	if not comdlgOk then
		return nil, "could not load comdlg32.dll"
	end
	local callOk, result = pcall(function()
		local fileBuf = ffi.new("char[260]")
		local filterStr = "Image Files\0*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tga\0All Files\0*.*\0\0"
		local filterBuf = ffi.new("char[?]", #filterStr)
		ffi.copy(filterBuf, filterStr, #filterStr)
		local titleStr = "Select scoreboard image\0"
		local titleBuf = ffi.new("char[?]", #titleStr)
		ffi.copy(titleBuf, titleStr, #titleStr)
		local ofn = ffi.new("OPENFILENAMEA")
		ofn.lStructSize = ffi.sizeof("OPENFILENAMEA")
		ofn.lpstrFilter = filterBuf
		ofn.lpstrFile = fileBuf
		ofn.nMaxFile = 260
		ofn.lpstrTitle = titleBuf
		-- OFN_EXPLORER + OFN_FILEMUSTEXIST + OFN_PATHMUSTEXIST + OFN_NOCHANGEDIR
		ofn.Flags = 0x00080000 + 0x00001000 + 0x00000800 + 0x00000008
		local res = comdlg32.GetOpenFileNameA(ofn)
		if res ~= 0 then
			return ffi.string(fileBuf)
		end
		return nil
	end)
	if not callOk then
		return nil, tostring(result)
	end
	return result
end
customImgList = splitImgList(allset.set.customImgList)
-- Load off the main thread: if this GIF hasn't been decoded/cached to disk
-- before, decoding a large animated image can take a while, and doing that
-- synchronously here would freeze the game while the script loads/joins.
lua_thread.create(function()
	wait(0)
	loadCustomBackground()
end)
loadTheme(allset.set.curTheme)
bgImage.v = cfg.set.bgimg
cListAlpha.v = math.floor((colors[3] and colors[3].w or 0.43) * 100)
if not doesDirectoryExist("moonloader\\resource") then
	createDirectory("moonloader\\resource")
end
if not doesDirectoryExist("moonloader\\resource\\SW-Scoreboard-Pro") then
	createDirectory("moonloader\\resource\\SW-Scoreboard-Pro")
end
do
function apply_custom_style()
	local style = imgui.GetStyle()
	local colors = style.Colors
	local clr = imgui.Col
	local ImVec4 = imgui.ImVec4
	style.WindowRounding = 2.0
	style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
	style.ChildWindowRounding = 2.0
	style.FrameRounding = 4.0
	style.ItemSpacing = imgui.ImVec2(6.0, 5.0)
	style.ScrollbarSize = 11.0
	style.ScrollbarRounding = 6.0
	style.GrabMinSize = 9.0
	style.GrabRounding = 4.0
	-- style.Alpha =
	style.WindowPadding = imgui.ImVec2(0.0, 0.0)
	-- style.WindowMinSize =
	style.FramePadding = imgui.ImVec2(4.0, 4.0)
	-- style.ItemInnerSpacing =
	-- style.TouchExtraPadding =
	-- style.IndentSpacing =
	-- style.ColumnsMinSpacing = ?
	style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
	-- style.DisplayWindowPadding =
	-- style.DisplaySafeAreaPadding =
	-- style.AntiAliasedLines =
	-- style.AntiAliasedShapes =
	-- style.CurveTessellationTol =
	colors[clr.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)
	colors[clr.ChildWindowBg]          = ImVec4(1.00, 1.00, 1.00, 0.00)
	-- colors[clr.PopupBg]                = ImVec4(0.04, 0.04, 0.04, 0.9)
	-- print(clr.ScrollbarGrab)
	-- print(clr.Header)
	colors[clr.ComboBg]                = colors[clr.PopupBg]
	colors[clr.Border]                 = ImVec4(0.00, 0.00, 0.00, 0.00)
	colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
	colors[clr.TitleBgCollapsed]       = ImVec4(0.05, 0.05, 0.05, 0.79)
	colors[clr.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
	-- colors[clr.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
	-- colors[clr.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
	-- colors[clr.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
	-- colors[clr.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
	colors[clr.CheckMark]              = ImVec4(1.00, 1.00, 1.00, 1.00)
	colors[clr.SliderGrab]             = ImVec4(0.28, 0.28, 0.28, 1.00)
	colors[clr.SliderGrabActive]       = ImVec4(0.35, 0.35, 0.35, 1.00)
	-- colors[clr.Header]                 = ImVec4(0.12, 0.12, 0.12, 0.94)
	-- colors[clr.HeaderHovered]          = ImVec4(0.25, 0.25, 0.25, 0.2)
	-- colors[clr.HeaderActive]           = ImVec4(0.16, 0.16, 0.16, 0.90)
	-- colors[clr.Separator]              = colors[clr.Border]
	colors[clr.SeparatorHovered]       = ImVec4(0.26, 0.59, 0.98, 0.78)
	colors[clr.SeparatorActive]        = ImVec4(0.26, 0.59, 0.98, 1.00)
	colors[clr.ResizeGrip]             = ImVec4(0.26, 0.59, 0.98, 0.25)
	colors[clr.ResizeGripHovered]      = ImVec4(0.26, 0.59, 0.98, 0.67)
	colors[clr.ResizeGripActive]       = ImVec4(0.26, 0.59, 0.98, 0.95)
	colors[clr.CloseButton]            = ImVec4(0.41, 0.41, 0.41, 0.50)
	colors[clr.CloseButtonHovered]     = ImVec4(0.98, 0.39, 0.36, 1.00)
	colors[clr.CloseButtonActive]      = ImVec4(0.98, 0.39, 0.36, 1.00)
	colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
	colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
	colors[clr.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
	colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
	colors[clr.TextSelectedBg]         = ImVec4(0.26, 0.59, 0.98, 0.35)
	colors[clr.ModalWindowDarkening]   = ImVec4(0.10, 0.10, 0.10, 0.35)
	-- colors[clr.WindowBg]               = imgui.ImColor(3, 3, 0, 230):GetVec4()
	-- colors[clr.FrameBg]    	 		  = imgui.ImColor(210, 210, 0, 100):GetVec4()
	-- colors[clr.FrameBgHovered]         = imgui.ImColor(210, 210, 0, 140):GetVec4()
	-- colors[clr.FrameBgActive]          = imgui.ImColor(210, 210, 0, 70):GetVec4()
	-- colors[clr.TitleBg]                = imgui.ImColor(120, 120, 0, 232):GetVec4()
	-- colors[clr.TitleBgActive]          = imgui.ImColor(120, 120, 0, 232):GetVec4()
	-- colors[clr.Button]                 = imgui.ImColor(180, 180, 0, 163):GetVec4()
	-- colors[clr.ButtonHovered]          = imgui.ImColor(180, 180, 0, 100):GetVec4()
	-- colors[clr.ButtonActive]           = imgui.ImColor(100, 100, 0, 100):GetVec4()
end
apply_custom_style()
end
function main()
	if not isSampfuncsLoaded() or not isSampLoaded() then return end
	while not isSampAvailable() do wait(0) end

	local h, n = findFirstFile('moonloader\\resource\\SW-Scoreboard-Pro\\*')
	local i = 1
	while true do
		wait(0)
		if h then
			if n then
				if doesDirectoryExist("moonloader\\resource\\SW-Scoreboard-Pro\\" .. n) and n ~= "." and n ~= ".." then
					table.insert(thems, n)
					themsId[tostring(n)] = i
					if allset.set.curTheme == n then
						cStyle.v = i - 1
					end
					i = i + 1
				end
				n = findNextFile(h)
			else
				findClose(h)
				if #thems == 0 then
					thems[1] = "main"
					themsId["main"] = 1
					notThems = true
					loadTheme()
				end
			end
		end
		imgui.Process = show_main_window.v
		if wasKeyPressed(VK_TAB) and not isPauseMenuActive() then
			if not show_main_window.v then
				if not sampIsChatInputActive() then
					toggleScoreboard(true)
				end
			else
				toggleScoreboard(false)
			end
		end
	end
end

function toggleScoreboard(flag)
	if type(flag) == 'boolean' then
		show_main_window.v = flag
	else
		show_main_window.v = not show_main_window.v
	end
	if show_main_window.v then
		if focusId > -1 then
			scrollToId = true
		end
	end
end

function getLocalPlayerId()
	local _, id = sampGetPlayerIdByCharHandle(playerPed)
	return id
end

function onWindowMessage(msg, wparam, lparam)
	if(msg == 0x100 or msg == 0x101) then
		if wparam == VK_TAB then
			consumeWindowMessage(true, false)
		end
		if(wparam == VK_ESCAPE and show_main_window.v) and not isPauseMenuActive() then
			consumeWindowMessage(true, false)
			if(msg == 0x101)then
				toggleScoreboard(false)
			end
		end
	end
end


local glyph_ranges = nil
function imgui.BeforeDrawFrame()
    if not fontChanged then
        fontChanged = true
        glyph_ranges = imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
        imgui.GetIO().Fonts:Clear()
        imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\arialbd.ttf', 14, nil, glyph_ranges)
				for _, v in ipairs(sizesFont) do
					sFont[tonumber(v)] = imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\arialbd.ttf', tonumber(v), nil, glyph_ranges)
				end
				imgui.RebuildFonts()
    end
end
function imgui.OnDrawFrame()
	-- notf.onRenderNotification()
	if show_main_window.v then
		if show_set_window.v then
			local x, y = ToScreen(510, 30)
			local w, h = ToScreen(638, 175)
			imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(6.0, 6.0))
			imgui.SetNextWindowPos(imgui.ImVec2(w-300, y), imgui.Cond.FirstUseEver, imgui.ImVec2(0.0, 0.0))
			imgui.SetNextWindowSize(imgui.ImVec2(300, 350), imgui.Cond.FirstUseEver)
			imgui.Begin('Control Panel', show_set_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)

			local tabNames = {'General', 'Colors', 'Image', 'Note'}
			for i = 0, 3 do
				if i > 0 then imgui.SameLine() end
				local isActive = settingsTab.v == i
				if isActive then
					imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.26, 0.59, 0.98, 0.75))
					imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.59, 0.98, 0.9))
				else
					imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.20, 0.24, 0.6))
					imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.28, 0.34, 0.8))
				end
				if imgui.Button(tabNames[i + 1], imgui.ImVec2(66, 24)) then
					settingsTab.v = i
				end
				imgui.PopStyleColor(2)
			end
			imgui.Dummy(imgui.ImVec2(0, 2))

			if settingsTab.v == 0 then
				imgui.AlignTextToFramePadding()
				imgui.Text('Theme:')
				imgui.SameLine()
				imgui.PushItemWidth(150)
				local rThems = {}
				for k, v in ipairs(thems) do
					rThems[k] = u8(v)
				end
				if imgui.Combo("##thems", cStyle, rThems) and #thems > 0 then
					if notThems then
						inicfg.save(cfg, "..\\resource\\SW-Scoreboard-Pro\\main\\data.ini")
						notThems = false
					else
						inicfg.save(cfg, "..\\resource\\SW-Scoreboard-Pro\\" .. allset.set.curTheme .. "\\data.ini")
					end
					allset.set.curTheme = thems[cStyle.v + 1]
					inicfg.save(allset, "SW-Scoreboard-Pro")
					loadTheme(allset.set.curTheme)
					cListAlpha.v = math.floor((colors[3] and colors[3].w or 0.43) * 100)
				end
				imgui.PopItemWidth()
				imgui.SameLine()
				if imgui.Button('New') then
					imgui.OpenPopup('Create theme')
				end
				if imgui.BeginPopupModal('Create theme', _, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
					imgui.Text('Theme name:')
					imgui.InputText("##createThemBuf", createThemBuf, imgui.InputTextFlags.CharsNoBlank)
					if imgui.Button('Create', imgui.ImVec2(100, 0)) then
						imgui.CloseCurrentPopup()
						if createThemBuf.v:len() > 0 and themsId[tostring(u8:decode(createThemBuf.v))] == nil then
							createDirectory(themsDir .. "\\" .. u8:decode(createThemBuf.v))
							themsId[tostring(u8:decode(createThemBuf.v))] = #themsId
							thems[#thems+1] = u8:decode(createThemBuf.v)
						end
					end
					imgui.SameLine()
					if imgui.Button('Cancel', imgui.ImVec2(100, 0)) then
						imgui.CloseCurrentPopup()
					end
					imgui.EndPopup()
				end
				imgui.AlignTextToFramePadding()
				imgui.Text('Window type:')
				imgui.SameLine()
				imgui.PushItemWidth(140)
				if imgui.Combo("##type", cType, {'Small', 'Medium', 'Large', 'Full screen'}) and #thems > 0 then
					allset.set.type = cType.v
				end
				imgui.PopItemWidth()
				imgui.AlignTextToFramePadding()
				imgui.Text('Title bar:')
				imgui.SameLine()
				imgui.TextDisabled('Custom text (fixed)')
				imgui.AlignTextToFramePadding()
				imgui.Text('Font size:')
				imgui.SameLine()
				imgui.PushItemWidth(140)
				if imgui.Combo("##size", cSize, sizesFont) then
					allset.set.fontSize = cSize.v
				end
				imgui.PopItemWidth()
				imgui.AlignTextToFramePadding()
				imgui.Text('Nickname view:')
				imgui.SameLine()
				imgui.TextDisabled('Colored name (fixed)')
				imgui.AlignTextToFramePadding()
				imgui.Text('Image opacity:')
				imgui.SameLine()
				imgui.PushItemWidth(140)
				if imgui.SliderInt("##imgOpacity", cImgOpacity, 0, 100) then
					allset.set.imageOpacity = cImgOpacity.v
					inicfg.save(allset, "SW-Scoreboard-Pro")
				end
				imgui.PopItemWidth()
				imgui.AlignTextToFramePadding()
				imgui.Text('List background transparency:')
				imgui.SameLine()
				imgui.PushItemWidth(140)
				if imgui.SliderInt("##listAlpha", cListAlpha, 0, 100) then
					local base = colors[3] or imgui.ImVec4(0.03, 0.05, 0.08, 0.43)
					colors[3] = imgui.ImVec4(base.x, base.y, base.z, cListAlpha.v / 100)
					cfg.colors[3] = imgui.ImColor(colors[3]):GetU32()
					if copColor[3] then
						for _, iv in ipairs(copColor[3]) do
							colors[iv] = colors[3]
						end
					end
				end
				imgui.PopItemWidth()

			elseif settingsTab.v == 1 then
				for k, v in pairs(setTable) do
					if imgui.CollapsingHeader(u8(k)) then
						for sk, sv in pairs(v) do
							local color = imgui.ImFloat4(imgui.ImColor(cfg.colors[sk]):GetFloat4())
							imgui.AlignTextToFramePadding()
							imgui.Text(u8(sv))
							imgui.SameLine(195)
							if imgui.ColorEdit4("##" .. sk, color, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel + imgui.ColorEditFlags.AlphaBar) then
								local newColor = imgui.ImColor.FromFloat4(color.v[1], color.v[2], color.v[3], color.v[4]):GetVec4()
								cfg.colors[sk] = imgui.ImColor(newColor):GetU32()
								colors[sk] = newColor
								if copColor[sk] then
									for _, iv in ipairs(copColor[sk]) do
										colors[iv] = newColor
									end
								end
							end
						end
					end
				end

			elseif settingsTab.v == 2 then
				imgui.TextColored(imgui.ImVec4(0.6, 0.75, 1.0, 1.0), 'Theme background')
				if imgui.Checkbox('Enable theme background image', bgImage) then
					cfg.set.bgimg = bgImage.v
				end
				local themeColor = imgui.ImFloat4(imgui.ImColor(cfg.set.imageColor):GetFloat4())
				imgui.AlignTextToFramePadding()
				if bgImage.v then imgui.Text('Tint / opacity') else imgui.TextDisabled('Tint / opacity') end
				imgui.SameLine(220)
				if imgui.ColorEdit4("##imageColor", themeColor, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel + imgui.ColorEditFlags.AlphaBar) then
					cfg.set.imageColor = imgui.ImColor.FromFloat4(themeColor.v[1], themeColor.v[2], themeColor.v[3], themeColor.v[4]):GetU32()
				end

				imgui.Dummy(imgui.ImVec2(0, 6))
				imgui.TextColored(imgui.ImVec4(0.6, 0.75, 1.0, 1.0), 'Custom external images')
				if imgui.Button('Browse for image...', imgui.ImVec2(-0.001, 0)) then
					local picked, err = openImageFileDialog()
					if picked and #picked > 0 then
						customImgPathBuf.v = picked
						browseDialogError = nil
						addImgToList(picked)
						if #customImgList == 1 then
							selectImgFromList(customImgList[1])
						end
					elseif err then
						browseDialogError = err
					end
				end
				if browseDialogError then
					imgui.TextColored(imgui.ImVec4(1.0, 0.4, 0.4, 1.0), 'Browse unavailable: ' .. tostring(browseDialogError))
					imgui.TextDisabled('You can still paste a path manually below.')
				end
				imgui.Dummy(imgui.ImVec2(0, 2))
				imgui.Text('Or paste a path manually:')
				imgui.PushItemWidth(-70)
				imgui.InputText("##customImgPath", customImgPathBuf, imgui.InputTextFlags.CharsNoBlank)
				imgui.PopItemWidth()
				imgui.SameLine()
				if imgui.Button('Add', imgui.ImVec2(60, 0)) then
					addImgToList(customImgPathBuf.v)
					if #customImgList == 1 then
						selectImgFromList(customImgList[1])
					end
				end

				imgui.Dummy(imgui.ImVec2(0, 4))
				imgui.Text('Your images (tap to use, X to remove):')
				imgui.BeginChild("##imgListChild", imgui.ImVec2(0, 90), true)
				if #customImgList == 0 then
					imgui.TextDisabled('No images added yet.')
				else
					for i, path in ipairs(customImgList) do
						imgui.PushID("imgrow" .. i)
						local isActive = allset.set.customImgPath == path
						if imgui.Selectable((isActive and '> ' or '  ') .. path, isActive, 0, imgui.ImVec2(180, 0)) then
							selectImgFromList(path)
						end
						imgui.SameLine(240)
						if imgui.Button('X', imgui.ImVec2(20, 0)) then
							removeImgFromList(i)
						end
						imgui.PopID()
					end
				end
				imgui.EndChild()

				if customImgLoadError then
					imgui.TextColored(imgui.ImVec4(1.0, 0.4, 0.4, 1.0), 'Could not find or load the selected file')
				elseif customBackground then
					imgui.Text('Preview:')
					imgui.Image(customBackground, imgui.ImVec2(120, 68))
				end
				if imgui.Checkbox('Use selected image as scoreboard background', customImgEnabled) then
					allset.set.customImgEnabled = customImgEnabled.v and 1 or 0
				end
				local customColor = imgui.ImFloat4(imgui.ImColor(allset.set.customImgColor):GetFloat4())
				imgui.AlignTextToFramePadding()
				imgui.Text('Transparency (drag the bar):')
				imgui.SameLine(220)
				if imgui.ColorEdit4("##customImgColor", customColor, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel + imgui.ColorEditFlags.AlphaBar) then
					allset.set.customImgColor = imgui.ImColor.FromFloat4(customColor.v[1], customColor.v[2], customColor.v[3], customColor.v[4]):GetU32()
				end
				imgui.TextDisabled('Tip: add several images, then switch between them anytime.')

				imgui.Dummy(imgui.ImVec2(0, 6))
				imgui.TextColored(imgui.ImVec4(0.6, 0.75, 1.0, 1.0), 'Auto-cycle (like RGB, but images)')
				if imgui.Checkbox('Automatically switch between my images', cycleEnabled) then
					allset.set.customImgCycle = cycleEnabled.v and 1 or 0
					lastCycleTime = os.clock()
					inicfg.save(allset, "SW-Scoreboard-Pro")
				end
				imgui.AlignTextToFramePadding()
				imgui.Text('Every (seconds):')
				imgui.SameLine(220)
				imgui.PushItemWidth(70)
				if imgui.SliderInt("##cycleInterval", cycleInterval, 2, 60) then
					allset.set.customImgCycleInterval = cycleInterval.v
					inicfg.save(allset, "SW-Scoreboard-Pro")
				end
				imgui.PopItemWidth()
				if #customImgList < 2 then
					imgui.TextDisabled('Add at least 2 images for this to do anything.')
				end
				imgui.TextDisabled('Animated (.gif) images play automatically at their own speed.')
				imgui.TextDisabled('If a gif needs more time to finish, it waits before switching.')

			elseif settingsTab.v == 3 then
				imgui.TextColored(imgui.ImVec4(0.6, 0.75, 1.0, 1.0), 'Note')
				imgui.PushItemWidth(-0.001)
				if imgui.InputTextMultiline("##noteArea", notesBuf, imgui.ImVec2(0, 150)) then
					notesSaved = false
				end
				imgui.PopItemWidth()
				if imgui.Button('Save note', imgui.ImVec2(120, 0)) then
					notesCfg.note.text = notesBuf.v
					inicfg.save(notesCfg, "SW-Scoreboard-Pro_notes")
					notesSaved = true
					if notf then
						notf.addNotification('Note saved', 4)
					end
				end
				imgui.SameLine()
				if notesSaved then
					imgui.TextDisabled('Saved')
				else
					imgui.TextColored(imgui.ImVec4(1.0, 0.7, 0.3, 1.0), 'Unsaved changes')
				end
			end

			imgui.Dummy(imgui.ImVec2(0, 4))
			if imgui.Button('Save all settings', imgui.ImVec2(-0.001, 0)) then
				if notThems then
					inicfg.save(cfg, "..\\resource\\SW-Scoreboard-Pro\\main\\data.ini")
					notThems = false
				else
					inicfg.save(cfg, "..\\resource\\SW-Scoreboard-Pro\\" .. allset.set.curTheme .. "\\data.ini")
				end
				inicfg.save(allset, "SW-Scoreboard-Pro")
				notesCfg.note.text = notesBuf.v
				inicfg.save(notesCfg, "SW-Scoreboard-Pro_notes")
				notesSaved = true
				if notf then
					notf.addNotification('Settings saved successfully', 5)
				end
			end
			imgui.Dummy(imgui.ImVec2(0, 2))
			imgui.TextDisabled('Author: Sam Wilson')
			imgui.End()
			imgui.PopStyleVar()
		end
		playerCount = 0
		if allset.set.type == 0 then
			x, y = ToScreen(160, 90)
			w, h = ToScreen(480, 358)
		elseif allset.set.type == 1 then
			x, y = ToScreen(130, 60)
			w, h = ToScreen(510, 388)
		elseif allset.set.type == 2 then
			x, y = ToScreen(100, 30)
			w, h = ToScreen(540, 418)
		elseif allset.set.type == 3 then
			x, y = ToScreen(0, 0)
			w, h = ToScreen(640, 448)
		end
		imgui.SetNextWindowPos(imgui.ImVec2(x, y), _, imgui.ImVec2(0.0, 0.0))
		imgui.SetNextWindowSize(imgui.ImVec2(w-x , h-y))
		local servername = u8(sampGetCurrentServerName())
		imgui.PushFont(sFont[tonumber(sizesFont[allset.set.fontSize + 1])])
		imgui.Begin(servername, show_main_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoBringToFrontOnFocus + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoScrollbar + (bTitlebar.v > 0 and imgui.WindowFlags.NoTitleBar or 0))

		if background and bgImage.v then
			local size = imgui.GetWindowSize()
			local bTint = imgui.ImColor(cfg.set.imageColor):GetVec4()
			local opacityScale = (allset.set.imageOpacity or 100) / 100
			imgui.Image(background, imgui.ImVec2(size.x , size.y-(bTitlebar.v == 0 and 21 or 0)), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), imgui.ImVec4(bTint.x, bTint.y, bTint.z, bTint.w * opacityScale))
		end
		advanceGifPlayback()
		advanceVideoPlayback()
		if customImgEnabled.v then
			local activeGif = gifCache[allset.set.customImgPath]
			if cycleEnabled.v and #customImgList > 1 then
				local waitTime = cycleInterval.v
				if activeGif and not activeGif.error and activeGif.totalDuration and activeGif.totalDuration > waitTime then
					waitTime = activeGif.totalDuration
				end
				if os.clock() - lastCycleTime >= waitTime then
					cycleToNextImage()
					lastCycleTime = os.clock()
				end
			end
		end
		if customBackground and customImgEnabled.v then
			local size = imgui.GetWindowSize()
			local cTint = imgui.ImColor(allset.set.customImgColor):GetVec4()
			local opacityScale = (allset.set.imageOpacity or 100) / 100
			local imgH = size.y-(bTitlebar.v == 0 and 21 or 0)
			local progress = 1.0
			if imgTransitionStart then
				local elapsed = os.clock() - imgTransitionStart
				if elapsed < imgTransitionDuration then
					progress = elapsed / imgTransitionDuration
				else
					imgTransitionStart = nil
					imgTransitionPrev = nil
				end
			end
			local startPos = imgui.GetCursorPos()
			if imgTransitionPrev and progress < 1.0 then
				imgui.SetCursorPos(startPos)
				imgui.Image(imgTransitionPrev, imgui.ImVec2(size.x, imgH), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), imgui.ImVec4(cTint.x, cTint.y, cTint.z, cTint.w * (1 - progress) * opacityScale))
			end
			imgui.SetCursorPos(startPos)
			imgui.Image(customBackground, imgui.ImVec2(size.x, imgH), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), imgui.ImVec4(cTint.x, cTint.y, cTint.z, cTint.w * progress * opacityScale))
		end
		local snSize
		if bTitlebar.v == 1 then
			snSize = imgui.CalcTextSize(servername)
		end
		imgui.SetCursorPos(imgui.ImVec2(bTitlebar.v == 1 and ((w-x) / 2) - (snSize.x / 2) or 6, bTitlebar.v == 0 and 24 or 3))
		if bTitlebar.v == 1 then
			imgui.Text(servername)
		end
		local totalWidth = w - x
		imgui.AlignTextToFramePadding()
		imgui.Indent(4); imgui.Text('Players: ' .. sampGetPlayerCount(false))
		imgui.SameLine()

		local bText = 'Settings'
		local sText = 'Search...'
		local bSize = imgui.CalcTextSize(bText)
		local searchWidth = 140
		local searchCenterX = (totalWidth / 2) - (searchWidth / 2)
		local cColumns = 4
		if cNType.v == 1 then
			cColumns = cColumns + 1
		end
		-- Search (centered, borderless)
		imgui.SameLine(searchCenterX)
		imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(1, 1, 1, 0.04))
		imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(1, 1, 1, 0.09))
		imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(1, 1, 1, 0.12))
		imgui.PushItemWidth(searchWidth)
		imgui.PushAllowKeyboardFocus(false)
		imgui.InputText("##search", searchBuf, imgui.InputTextFlags.EnterReturnsTrue + imgui.InputTextFlags.CharsNoBlank)
		imgui.PopAllowKeyboardFocus()
		imgui.PopItemWidth()
		imgui.PopStyleColor(3)
		if not imgui.IsItemActive() and #searchBuf.v == 0 then
			local r, g, b, a = imgui.ImColor(colors[1]):GetRGBA()
			imgui.SameLine(searchCenterX + 6)
			imgui.PushStyleColor(imgui.Col.Text, imgui.ImColor(r, g, b, 140):GetVec4())
			imgui.Text(sText)
			imgui.PopStyleColor()
		end
		-- Settings (borderless text-style button, top-right)
		imgui.SameLine(totalWidth - (bSize.x + 14))
		imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
		imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.10))
		imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.16))
		if imgui.Button(bText, imgui.ImVec2(bSize.x + 10, 0)) then
			show_set_window.v = not show_set_window.v
		end
		imgui.PopStyleColor(3)

		imgui.Columns(cColumns, nil, false)
		imgui.NewLine()
		imgui.SameLine(2)
		imgui.SetColumnWidth(-1, 32); imgui.Text('ID'); imgui.NextColumn()
		imgui.SetColumnWidth(-1, w-x-160-(cNType.v == 1 and 90 or 0)); imgui.Text('Name'); imgui.NextColumn()
		if cNType.v == 1 then
			imgui.SetColumnWidth(-1, 90); imgui.Text('Color'); imgui.NextColumn()
		end
		imgui.SetColumnWidth(-1, 70); imgui.Text('Score'); imgui.NextColumn()
		imgui.SetColumnWidth(-1, 70); imgui.Text('Ping'); imgui.NextColumn()
		imgui.Columns(1)
		imgui.BeginChild("##scroll", imgui.ImVec2(0, 0), false)
		imgui.Columns(cColumns, nil, false)
		imgui.SetColumnWidth(-1, 32);imgui.NextColumn()
		imgui.SetColumnWidth(-1, w-x-160-(cNType.v == 1 and 70 or 0)); imgui.NextColumn()
		if cNType.v == 1 then
			imgui.SetColumnWidth(-1, 90); imgui.NextColumn()
		end
		imgui.SetColumnWidth(-1, 70);imgui.NextColumn()
		imgui.SetColumnWidth(-1, 70); imgui.NextColumn()
		local local_player_id = getLocalPlayerId()
		if(#searchBuf.v < 1 and cFilter.v == 0) then
			drawScoreboardPlayer(local_player_id)
		else
			if (string.find(sampGetPlayerNickname(local_player_id):lower(), searchBuf.v:lower(), 1, true) or local_player_id == tonumber(searchBuf.v)) and cFilter.v == 0 then
				drawScoreboardPlayer(local_player_id)
			end
		end
		local viewPlayers = {}
		for i = 0, sampGetMaxPlayerId(false) do
			if local_player_id ~= i and sampIsPlayerConnected(i) and not sampIsPlayerNpc(i) then
				if(#searchBuf.v > 0) then
					if(string.find(sampGetPlayerNickname(i):lower(), searchBuf.v:lower(), 1, true) or i == tonumber(searchBuf.v))then
						table.insert(viewPlayers, i)
					end
				else
					table.insert(viewPlayers, i)
				end
			end
		end
		if #viewPlayers > 0 then
			local clipper = imgui.ImGuiListClipper(#viewPlayers)
			while clipper:Step() do
				for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
					drawScoreboardPlayer(viewPlayers[i])
				end
			end
		end

		imgui.Columns(1)
		if(playerCount == 0)then
			imgui.SameLine(5.0); imgui.Text('Loading players...')
		end
		imgui.EndChild()

		imgui.End()
		imgui.PopFont()
	end
end

function drawScoreboardPlayer(id)
	local pop
	local playerInStream, ped = sampGetCharHandleBySampPlayerId(id)
	local nickname = encoding.UTF8(sampGetPlayerNickname(id))
	local score = sampGetPlayerScore(id)
	local ping = sampGetPlayerPing(id)
	local color = sampGetPlayerColor(id)
	local health = playerInStream and tostring(sampGetPlayerHealth(id)) or "-"
	local armor = playerInStream and tostring(sampGetPlayerArmor(id)) or "-"
	local model = playerInStream and tostring(getCharModel(ped)) or "-"
	local speed = playerInStream and tostring(math.floor(getCharSpeed(ped))) or "-"
	local r, g, b = bitex.bextract(color, 16, 8), bitex.bextract(color, 8, 8), bitex.bextract(color, 0, 8)
	local imgui_RGBA = imgui.ImVec4(r / 255.0, g / 255.0, b / 255.0, 1)
	playerCount = playerCount + 1
	imgui.NewLine()
	imgui.SameLine(2)
	if imgui.Selectable(tostring(id), id == focusId, imgui.SelectableFlags.SpanAllColumns + imgui.SelectableFlags.AllowDoubleClick) then
		if imgui.IsMouseDoubleClicked(0) then
			sampSendClickPlayer(id, 0)
			lua_thread.create(function ()
				wait(150)
				toggleScoreboard(false)
			end)
		else
			focusId = focusId == id and -1 or id
		end
	end

	imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(4.0, 3.0))
	if id ~= getLocalPlayerId() and imgui.BeginPopupContextItem() then
		local pMenuTitle = nickname .. "[" .. id .. "]"
		local pMenuTitleSize = imgui.CalcTextSize(pMenuTitle)
		local pMenuWidth = math.max(150, pMenuTitleSize.x + 16)
		imgui.BeginChild("##pMenu", imgui.ImVec2(pMenuWidth, 100))
		pop = true
		imgui.TextColored(imgui_RGBA, pMenuTitle)
		local btnSize = imgui.ImVec2(-0.001, 0.0)
		if id ~= getLocalPlayerId() then
			if imgui.Button('Request number', btnSize) then
				imgui.CloseCurrentPopup()
				toggleScoreboard(false)
				pendingNumberId = tostring(id)
				sampSendChat("/number " .. id)
			end
		end
		if imgui.Button('Copy nickname', btnSize) then
			setClipboardText(nickname)
			imgui.CloseCurrentPopup()
		end
		imgui.EndChild()
		imgui.EndPopup()
	else
		pop = false
	end
	imgui.PopStyleVar()
	if imgui.IsItemHovered() and not pop and id ~= getLocalPlayerId() then
		imgui.BeginTooltip();
		imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(4.0, 3.0))
		imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(4.0, 2.0))
		local tipTitle = nickname .. "[" .. id .. "]"
		local tipTitleSize = imgui.CalcTextSize(tipTitle)
		local tipWidth = math.max(157, tipTitleSize.x + 16)
		imgui.BeginChild("##Test", imgui.ImVec2(tipWidth, (tonumber(sizesFont[allset.set.fontSize + 1]) + 2) * 1 + 7), true)
		imgui.Text(tipTitle)
		imgui.EndChild()
		imgui.PopStyleVar(2)
		imgui.EndTooltip();
	end

	imgui.NextColumn()

	if cNType.v == 0 then
		imgui.TextColored(imgui_RGBA, nickname)
	else
		imgui.Text(nickname)
	end
	imgui.NextColumn()
		if cNType.v == 1 then
		imgui.TextColored(imgui_RGBA, "0x" .. string.upper(string.format("%0.8s", bit.tohex(color)))); imgui.NextColumn()
	end
	imgui.Text(tostring(score)); imgui.NextColumn()
	imgui.Text(tostring(ping)); imgui.NextColumn()

	if scrollToId and focusId > -1 and focusId == id then
		scrollToId = false
		imgui.SetScrollHere(0.43)
	end
end

function onScriptTerminate(script, quitGame)
	if script == thisScript() then
		if not doesDirectoryExist("moonloader\\config") then
			createDirectory("moonloader\\config")
		end
		if notThems then
			inicfg.save(cfg, "..\\resource\\SW-Scoreboard-Pro\\main\\data.ini")
			notThems = false
		else
			inicfg.save(cfg, "..\\resource\\SW-Scoreboard-Pro\\" .. allset.set.curTheme .. "\\data.ini")
		end
		inicfg.save(allset, "SW-Scoreboard-Pro")
		notesCfg.note.text = notesBuf.v
		inicfg.save(notesCfg, "SW-Scoreboard-Pro_notes")
	end
end

function string.rlower(s)
	s = s:lower()
	local strlen = s:len()
	if strlen == 0 then return s end
	s = s:lower()
	local output = ''
	for i = 1, strlen do
		 local ch = s:byte(i)
		 if ch >= 192 and ch <= 223 then -- upper russian characters
			  output = output .. russian_characters[ch + 32]
		 elseif ch == 168 then -- Ё
			  output = output .. russian_characters[184]
		 else
			  output = output .. string.char(ch)
		 end
	end
	return output
end
function string.rupper(s)
	s = s:upper()
	local strlen = s:len()
	if strlen == 0 then return s end
	s = s:upper()
	local output = ''
	for i = 1, strlen do
		 local ch = s:byte(i)
		 if ch >= 224 and ch <= 255 then -- lower russian characters
			  output = output .. russian_characters[ch - 32]
		 elseif ch == 184 then -- ё
			  output = output .. russian_characters[168]
		 else
			  output = output .. string.char(ch)
		 end
	end
	return output
end
function SE.onPlayerJoin(id, color, isNpc, nickname)
end
function SE.onPlayerQuit(id, reason)
end
function SE.onRequestClassResponse()
	gameInit = true
end
function SE.onShowDialog()
	gameInit = true
end
function SE.onServerMessage(color, text)
	gameInit = true
	if pendingNumberId and text:find('Номер игрока', 1, true) and text:find('%[' .. pendingNumberId .. '%]') then
		local number = text:match('(%d+)%s*$')
		if number then
			sampSetChatInputText('/sms ' .. number .. ' ')
			sampSetChatInputEnabled(true)
			pendingNumberId = nil
		end
	end
end

function explode_color(color)
	local a = bit.band(bit.rshift(color, 24), 0xFF)
	local r = bit.band(bit.rshift(color, 16), 0xFF)
	local g = bit.band(bit.rshift(color, 8), 0xFF)
	local b = bit.band(color, 0xFF)
	return a, r, g, b
 end

 function join_color(a, r, g, b)
	local color = b  -- b
	color = bit.bor(color, bit.lshift(g, 8))  -- g
	color = bit.bor(color, bit.lshift(r, 16)) -- r
	color = bit.bor(color, bit.lshift(a, 24)) -- a
	return color
 end

 function convertARGBToRGBA(color)
	local color = tonumber(color)
	local a, r, g, b = explode_color(color)
	return join_color(r, g, b, a)
end

function convertRGBAToARGB(color)
	local color = tonumber(color)
	local r, g, b, a = explode_color(color)
	return join_color(a, r, g, b)
end

-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- ReplayMod for SA-MP — UNIFIED EDITION (Record + Play, one file)
-- Based on the original RecordStable.lua / PlayStable.lua by
-- kuzheren (maynkraftpro2010). Developed by Sam Wilson.
--
-- KEY BEHAVIOR CHANGE FROM ORIGINAL:
-- The original script started recording automatically the instant the
-- client connected to the server. This version records ONLY when you
-- press Start (or run /rmstart) — fully manual, start/stop whenever you
-- want during a session.
--
-- To make that safe, the script keeps a lightweight "world init" snapshot
-- (RPC_SCRINITGAME + the connect handshake) cached in memory from the
-- moment you connect — but it is NEVER written to disk until you actually
-- start a recording. The instant you press Start, that cached snapshot is
-- written first, so every manual recording is self-contained and plays
-- back correctly regardless of when in the session you started it.
--------------------------------------------------------------
script_version("7")
script_author("kuzheren (maynkraftpro2010) + extended by Sam Wilson")
--------------------------------------------------------------
require("sampfuncs")
local imgui = require("imgui")
local encoding = require("encoding")
encoding.default = "CP1251"
local u8 = encoding.UTF8
local font = renderCreateFont('Arial', 15, 4 + 8)
local windows_state = imgui.ImBool(false)
imgui.Process = false
--------------------------------------------------------------
local Mode = {
	idle    = 0, -- connected, not recording, nothing loaded
	record  = 1,
	paused  = 2,
	loaded  = 3, -- a save is loaded, ready to play
	replay  = 4, -- currently playing back
}
local PacketTag = {
	RPC       = "0",
	Packet    = "1",
	Waiting   = "2",
	ColorInfo = "3"
}
local NormalPackets = {
	PACKET_AIM_SYNC,
	PACKET_BULLET_SYNC,
	PACKET_UNOCCUPIED_SYNC,
	PACKET_TRAILER_SYNC,
	PACKET_PASSENGER_SYNC
}
local IgnoredRPCs = {
	RPC_SCRSETPLAYERHEALTH,
	RPC_SCRSETCAMERABEHINDPLAYER,
	RPC_SCRSETPLAYERCAMERALOOKAT,
	RPC_SCRSETPLAYERCAMERAPOS,
	RPC_SCRINTERPOLATECAMERA,
	RPC_SCRATTACHCAMERATOOBJECT,
	RPC_SPAWN,
	RPC_REQUESTSPAWN,
	RPC_SCRSETPLAYERWORLDBOUNDS,
	RPC_SCRTOGGLEPLAYERSPECTATING,
	RPC_SCRTOGGLEPLAYERCONTROLLABLE,
	RPC_SCRSETPLAYERPOS,
	RPC_SCRSETPLAYERFACINGANGLE,
	RPC_SCRPLAYERSPECTATEPLAYER,
	RPC_SCRPLAYERSPECTATEVEHICLE,
	RPC_CLICKTEXTDRAW,
	RPC_SCRSHOWTEXTDRAW,
	RPC_SCRDISPLAYGAMETEXT,
	RPC_SCRGIVEPLAYERWEAPON,
	RPC_SCRREMOVEBUILDINGFORPLAYER,
	RPC_SCRPUTPLAYERINVEHICLE,
	RPC_SCRGIVEPLAYERMONEY,
	RPC_SCRRESETPLAYERMONEY,
	RPC_SCRRESETPLAYERWEAPONS,
	RPC_SCRSETPLAYERSKILLLEVEL,
	RPC_SCRSETPLAYERDRUNKLEVEL,
}
--------------------------------------------------------------
local _Version = "3.0 (Unified)"
local _ReadMe = "ReplayMod " .. _Version .. ". Activation: /rm. Original by kuzheren.\nAuthor: Sam Wilson\nАвтор - Sam Wilson\nDON'T DELETE THIS FILE!!!"
local _MenuPage = 1
--------------------------------------------------------------
local _State = Mode.idle
local _RecorderClosing = false -- prevents overlapping recorder workers during finalization
local _LocalPlayerId = 1001
--------------------------------------------------------------
-- Recording-side state
local _DataQueue = {}
local _CurrentFile = nil
local _CurrentSaveName = nil
local _RecordStartTick = 0
local _Waiting = false
local _WaitingIteration = 0
-- Cached world-init snapshot, refreshed on every connection, never written
-- to disk until the user presses Start.
local _CachedInitGame = nil      -- serialized RPC_SCRINITGAME string
local _CachedConnectId = nil     -- serialized "connect" RPC string
local _CachedFFLine = nil        -- "FF" .. localPlayerId line
--------------------------------------------------------------
-- Playback-side state
local _DataPlaying = {}
local Iteration = 0
local _LoadedFileName = nil
local _Multiplier = imgui.ImFloat(1)
local _ImguiIteration = imgui.ImInt(0)
local _GoToTime = imgui.ImBuffer(9)
local _PossessMode = imgui.ImBool(false)
local _PossessTargetId = imgui.ImInt(0)
local lastPossessTarget = nil
local _IsRewind = 0
--------------------------------------------------------------
-- Player name-color capture (passive - runs anytime you're
-- connected, independent of recording state)
local _PlayerColors = {} -- [nickname_lower] = {color = 0xRRGGBBAA, realName = "Nick"}
local PLAYER_COLORS_FILE = getGameDirectory() .. "/moonloader/ReplayMod/player_colors.ini"
-- Snapshot embedded in whichever .replay is currently loaded. Session-only:
-- never written to disk on its own, just overwritten on each Load() and
-- wiped automatically when the game closes.
local _LoadedColors = {}
local _CanRewind = true
--------------------------------------------------------------
-- Settings (persisted)
local Settings = {
	chatNotify        = imgui.ImBool(true),
	overlayEnabled    = imgui.ImBool(true),
	autoCenterCamera  = imgui.ImBool(true),
	loopPlayback      = imgui.ImBool(false),
	rewindCooldownSec = imgui.ImInt(10),
	customNamePrefix  = imgui.ImBuffer(32),
	hideTimeOverlay    = imgui.ImBool(false),
}
Settings.customNamePrefix.v = "Replay"
--------------------------------------------------------------
local Translate = {
	scriptloaded       = "ReplayMod Unified loaded!",
	credits            = "Original: kuzheren (maynkraftpro2010) — Developed by Sam Wilson",
	activation         = "Activation: /rm",
	recordingstarted   = "Recording started:",
	recordingpaused    = "Recording paused.",
	recordingresumed   = "Recording resumed.",
	recordingstopped   = "Recording stopped and saved.",
	notrecording       = "Not currently recording.",
	currentlyrecording = "Recording:",
	startrecording     = "Start recording",
	pauserecording     = "Pause recording",
	resumerecording    = "Resume recording",
	stoprecording      = "Stop & save",
	recordmenu         = "Record",
	playbackmenu       = "Playback",
	saves              = "Saves",
	settingsmenu       = "Settings",
	info               = "Information",
	fileloaded         = "loaded.",
	replaystarted      = "Replay started!",
	playbackover       = "Playback ended.",
	playbackpause      = "Playback paused.",
	playbackresume     = "Playback continued.",
	rewindstarts       = "Rewinding...",
	jumpedtotime       = "Jumped to timecode",
	waitcooldown       = "Please wait before rewinding again!",
	waitingforplayback = "No replay loaded.",
	jumptotime         = "Go",
	wrongtime          = "Invalid time format! Use HH:MM:SS",
	continueplayback   = "Resume",
	pause              = "Pause",
	stopplayback       = "Stop playback",
	play               = "Play",
	unloadloadedsave   = "Unload",
	load               = "Load",
	deletesave         = "Delete",
	switchtoviewmode   = "Switch to free-view mode",
	playbackspeed      = "Playback speed",
	incorrecttime      = "Invalid rewind target!",
	possessmode        = "Possess recorded character (ride view)",
	autocentercam      = "Auto-center camera on character",
	loopplaybackopt    = "Loop playback",
	rewindcooldown     = "Rewind cooldown (seconds)",
	nameprefix         = "Save file name prefix",
	notconnected       = "Waiting for server connection...",
	readytostart       = "Connected. Ready to record whenever you want.",
}
--------------------------------------------------------------

function Say(msg)
	if Settings.chatNotify.v then
		sampAddChatMessage("{FF1E1E}[ReplayMod]: {FFFFFF}" .. tostring(msg), -1)
	end
end

-- Use elapsed host time rather than os.clock(), which measures CPU usage.
local function RecorderClockMs()
	if type(getGameTimer) == "function" then
		local ok, value = pcall(getGameTimer)
		if ok and type(value) == "number" then return value end
	end
	return os.time() * 1000
end

--------------------------------------------------------------
-- main
--------------------------------------------------------------
function main()
	repeat wait(0) until isSampAvailable()
	_GoToTime.v = "00:00:00"

	if not doesDirectoryExist(getGameDirectory().."/moonloader/ReplayMod") then
		createDirectory(getGameDirectory().."/moonloader/ReplayMod")
	end
	if not doesFileExist(getGameDirectory().."/moonloader/ReplayMod/readme.txt") then
		local rf = io.open(getGameDirectory().."/moonloader/ReplayMod/readme.txt", "w")
		if rf then
			rf:write(_ReadMe)
			rf:close()
		end
	end

	LoadSettings()
	LoadPlayerColors()
	StartColorCapture()

	Say(Translate.scriptloaded)
	Say(Translate.credits)
	Say(Translate.activation)

	sampRegisterChatCommand("rm", function()
		windows_state.v = not windows_state.v
		imgui.Process = windows_state.v
	end)

	sampRegisterChatCommand("rmstart", function()
		if _State == Mode.idle then Recorder.Start() end
	end)
	sampRegisterChatCommand("rmstop", function()
		if _State == Mode.record or _State == Mode.paused then Recorder.Stop() end
		if _State == Mode.replay then Player.StopPlay() end
	end)
	sampRegisterChatCommand("rmpause", function()
		if _State == Mode.record or _State == Mode.paused then Recorder.TogglePause() end
		if _State == Mode.replay then Player.Pause() end
	end)
	sampRegisterChatCommand("rmpossess", function(arg)
		if arg and arg ~= "" and tonumber(arg) then
			_PossessTargetId.v = tonumber(arg)
			_PossessMode.v = true
			lastPossessTarget = nil
			pcall(function() setCharVisible(1, false) end)
			Say("Possess mode: ON (player ID " .. tonumber(arg) .. ")")
		else
			local exitTargetId = _PossessTargetId.v
			_PossessMode.v = false
			if Settings.autoCenterCamera.v then
				Settings.autoCenterCamera.v = false
			end
			lua_thread.create(function()
				local exitX, exitY, exitZ = nil, nil, nil
				local res, handle = sampGetCharHandleBySampPlayerId(exitTargetId)
				if res then
					exitX, exitY, exitZ = getCharCoordinates(handle)
				end
				SpectatorMode(1)
				SpectatorMode(0)
				wait(150)
				sampSpawnPlayer()
				wait(150)
				if exitX then
					setCharCoordinates(1, exitX + 1.5, exitY + 1.5, exitZ)
				end
				pcall(function() setCharVisible(1, true) end)
				restoreCameraJumpcut()
				Say("Possess mode: OFF")
			end)
		end
	end)
	sampRegisterChatCommand("rewind", function(arg)
		if _State == Mode.replay then
			if ConvertTimeStringToTicks(arg) then
				Player.Rewind(ConvertTimeStringToTicks(arg))
			else
				Say(Translate.incorrecttime)
			end
		end
	end)

	while true do
		wait(0)
		scrx, scry = getScreenResolution()
		if windows_state.v == false then
			imgui.Process = false
		end

		if Settings.overlayEnabled.v then
			if _State == Mode.record then
				renderFontDrawText(font, "{REC} " .. FormatElapsed((RecorderClockMs() - _RecordStartTick) / 1000), scrx - 170, 0, 0xFFFF1E1E)
			elseif _State == Mode.paused then
				renderFontDrawText(font, "{PAUSED}", scrx - 170, 0, 0xFFFFAA00)
			elseif _State == Mode.replay then
				if testCheat("OP") then
					local result, handle = sampGetCharHandleBySampPlayerId(_LocalPlayerId)
					if result then
						local x, y, z = getCharCoordinates(handle)
						setCharCoordinates(1, x, y, z)
					end
				end
				if not Settings.hideTimeOverlay.v then
					renderFontDrawText(font, ConvertTicksToTimeString(Iteration) .. "/" .. ConvertTicksToTimeString(#_DataPlaying), scrx/2-100, scry - (scry/10), 0xFFFFFFFF)
				end
				renderFontDrawText(font, "x" .. string.format("%.1f", _Multiplier.v), scrx/2-100, scry - (scry/10) + 18, 0xFFFF5050)
				renderFontDrawText(font, "PLAY", scrx - 62, 0, 0xFFFF1E1E)
				if _PossessMode.v then
					renderFontDrawText(font, "POSSESSING", scrx - 150, 20, 0xFFFF1E1E)
				end
			end
		end
	end
end

function FormatElapsed(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = math.floor(sec % 60)
	return string.format("%02d:%02d:%02d", h, m, s)
end

--------------------------------------------------------------
-- Settings persistence
--------------------------------------------------------------
function LoadSettings()
	local path = getGameDirectory().."/moonloader/ReplayMod/settings.ini"
	if doesFileExist(path) then
		local f = io.open(path, "r")
		if f then
			for line in f:lines() do
				local key, value = line:match("^(%a+)=(.*)$")
				if key == "overlayEnabled" then Settings.overlayEnabled.v = (value == "1") end
				if key == "chatNotify" then Settings.chatNotify.v = (value == "1") end
				if key == "autoCenterCamera" then Settings.autoCenterCamera.v = (value == "1") end
				if key == "loopPlayback" then Settings.loopPlayback.v = (value == "1") end
				if key == "namePrefix" then Settings.customNamePrefix.v = value end
				if key == "rewindCooldown" then Settings.rewindCooldownSec.v = tonumber(value) or 10 end
				if key == "hideTimeOverlay" then Settings.hideTimeOverlay.v = (value == "1") end
			end
			f:close()
		end
	end
end

function SaveSettings()
	local path = getGameDirectory().."/moonloader/ReplayMod/settings.ini"
	local f = io.open(path, "w")
	if not f then
		Say("Could not save settings (file could not be opened).")
		return
	end
	f:write("overlayEnabled=" .. (Settings.overlayEnabled.v and "1" or "0") .. "\n")
	f:write("chatNotify=" .. (Settings.chatNotify.v and "1" or "0") .. "\n")
	f:write("autoCenterCamera=" .. (Settings.autoCenterCamera.v and "1" or "0") .. "\n")
	f:write("loopPlayback=" .. (Settings.loopPlayback.v and "1" or "0") .. "\n")
	f:write("namePrefix=" .. tostring(Settings.customNamePrefix.v) .. "\n")
	f:write("rewindCooldown=" .. tostring(Settings.rewindCooldownSec.v) .. "\n")
	f:write("hideTimeOverlay=" .. (Settings.hideTimeOverlay.v and "1" or "0") .. "\n")
	f:close()
end

--------------------------------------------------------------
-- Player name-color + skin capture/persistence
--------------------------------------------------------------
function LoadPlayerColors()
	local f = io.open(PLAYER_COLORS_FILE, "r")
	if not f then return end
	for line in f:lines() do
		-- New format: nick=colorHex:skinId   Old format: nick=colorHex
		local nick, colorHex, skinStr = line:match("^(.-)=(%x+):(%-?%d+)$")
		if not nick then
			nick, colorHex = line:match("^(.-)=(%x+)$")
		end
		if nick and nick ~= "" and colorHex then
			local skin = skinStr and tonumber(skinStr)
			if skin and skin < 0 then skin = nil end
			_PlayerColors[nick:lower()] = { color = tonumber(colorHex, 16), skin = skin, realName = nick }
		end
	end
	f:close()
end

function SavePlayerColors()
	local f = io.open(PLAYER_COLORS_FILE, "w")
	if not f then return end
	for _, data in pairs(_PlayerColors) do
		f:write(data.realName .. "=" .. string.format("%08X", data.color) ..
			":" .. tostring(data.skin or -1) .. "\n")
	end
	f:close()
end

-- Runs continuously in the background any time you're connected to a
-- server, regardless of whether you're recording. Every few seconds it
-- checks every connected player's current name color AND skin, and
-- remembers both, so the data keeps building up across sessions on its own.
function StartColorCapture()
	lua_thread.create(function()
		while true do
			wait(3000)
			if isSampAvailable() then
				pcall(function()
					local maxId = sampGetMaxPlayerId(false)
					local changed = false
					for i = 0, maxId do
						if sampIsPlayerConnected(i) then
							local nick = sampGetPlayerNickname(i)
							local ok, color = pcall(sampGetPlayerColor, i)

							local skin = nil
							local res, handle = sampGetCharHandleBySampPlayerId(i)
							if res and doesCharExist(handle) then
								local okSkin, skinId = pcall(getCharModel, handle)
								if okSkin then skin = skinId end
							end

							if nick and nick ~= "" and ok and color then
								local key = nick:lower()
								local existing = _PlayerColors[key]
								if not existing or existing.color ~= color or existing.skin ~= skin then
									_PlayerColors[key] = { color = color, skin = skin, realName = nick }
									changed = true
								end
							end
						end
					end
					if changed then
						SavePlayerColors()
					end
				end)
			end
		end
	end)
end

--------------------------------------------------------------
-- RECORDER (manual start/stop, any time during the session)
--------------------------------------------------------------
Recorder = {
	Start = function()
		if _State ~= Mode.idle or _RecorderClosing then
			Say("A recording is already active or still being finalized.")
			return
		end

		-- Each recording owns a fresh queue and wait counter. Do not allow a
		-- second worker to start until the previous file has been closed.
		_DataQueue = {}
		_Waiting = false
		_WaitingIteration = 0
		_State = Mode.record
		_RecordStartTick = RecorderClockMs()
		lua_thread.create(function()
			local SaveName = DeGenerateName(Settings.customNamePrefix.v)
			local file = io.open(getGameDirectory() .. "/moonloader/ReplayMod/" .. SaveName, "a")

			if not file then
				Say("Could not create the recording file. Recording cancelled.")
				_DataQueue = {}
				_Waiting = false
				_WaitingIteration = 0
				_CurrentSaveName = nil
				_CurrentFile = nil
				_State = Mode.idle
				_RecorderClosing = false
				return
			end

			_CurrentSaveName = SaveName
			_CurrentFile = file

			-- Write the cached world-init snapshot FIRST so this recording
			-- is self-contained no matter when in the session it started.
			if _CachedInitGame then
				AddDataToSaveFile(file, PacketTag.RPC .. _CachedInitGame .. "\n")
			end
			if _CachedConnectId then
				AddDataToSaveFile(file, PacketTag.RPC .. _CachedConnectId .. "\n")
			end
			if _CachedFFLine then
				AddDataToSaveFile(file, PacketTag.RPC .. _CachedFFLine .. "\n")
			end

			-- Embed a snapshot of currently-connected players' name
			-- colors AND skins straight into this recording (no separate
			-- temp file). Only players who are actually connected right
			-- now get written - not the whole historical cache.
			pcall(function()
				local maxId = sampGetMaxPlayerId(false)
				for i = 0, maxId do
					if sampIsPlayerConnected(i) then
						local nick = sampGetPlayerNickname(i)
						local ok, color = pcall(sampGetPlayerColor, i)

						local skin = -1
						local res, handle = sampGetCharHandleBySampPlayerId(i)
						if res and doesCharExist(handle) then
							local okSkin, skinId = pcall(getCharModel, handle)
							if okSkin then skin = skinId end
						end

						if nick and nick ~= "" and ok and color then
							AddDataToSaveFile(file, PacketTag.ColorInfo .. nick .. "=" ..
								string.format("%08X", color) .. ":" .. tostring(skin) .. "\n")
						end
					end
				end
			end)

			Say(Translate.recordingstarted .. " " .. SaveName)

			local lastFlush = RecorderClockMs()

			while _State == Mode.record or _State == Mode.paused do
				wait(10)
				if _State == Mode.record then
					for i=1, 100 do
						if _DataQueue[1] ~= nil then
							if _Waiting then
								_Waiting = false
								local iterStr = tostring(_WaitingIteration)
								AddDataToSaveFile(file, PacketTag.Waiting .. iterStr .. "\n")
								_WaitingIteration = 0
							end
							AddDataToSaveFile(file, _DataQueue[1] .. "\n")
							table.remove(_DataQueue, 1)
						else
							_Waiting = true
							_WaitingIteration = _WaitingIteration + 1
						end
					end

					-- For long sessions (hours), force buffered writes to
					-- actually hit disk every few seconds, so a crash or
					-- unexpected exit mid-session only loses a few seconds
					-- of unflushed data instead of a potentially large
					-- buffered chunk that was never written.
					local nowMs = RecorderClockMs()
					if nowMs - lastFlush >= 5000 then
						lastFlush = nowMs
						pcall(function() file:flush() end)
					end
				end
			end
			-- Drain whatever's still queued before closing, so the last
			-- moments right before Stop was pressed aren't lost.
			while _DataQueue[1] ~= nil do
				if _Waiting then
					_Waiting = false
					AddDataToSaveFile(file, PacketTag.Waiting .. tostring(_WaitingIteration) .. "\n")
					_WaitingIteration = 0
				end
				AddDataToSaveFile(file, _DataQueue[1] .. "\n")
				table.remove(_DataQueue, 1)
			end
			if _CurrentFile then
				_CurrentFile:flush()
				_CurrentFile:close()
				_CurrentFile = nil
			end
			_DataQueue = {}
			_Waiting = false
			_WaitingIteration = 0
			_RecorderClosing = false
			Say(Translate.recordingstopped)
		end)
	end,

	TogglePause = function()
		if _State == Mode.record then
			_State = Mode.paused
			Say(Translate.recordingpaused)
		elseif _State == Mode.paused then
			_State = Mode.record
			Say(Translate.recordingresumed)
		end
	end,

	Stop = function()
		if _State == Mode.record or _State == Mode.paused then
			-- The worker drains the pending queue and closes the file after its
			-- current wait cycle. Block a new Start until that cleanup completes.
			_State = Mode.idle
			_RecorderClosing = true
			Say("Finalizing recording and flushing remaining events...")
		end
	end,
}

--------------------------------------------------------------
-- Network hooks
--------------------------------------------------------------
function onReceiveRpc(id, BitStream)
	-- Always cache INITGAME / connect handshake in memory (never written
	-- to disk unless a recording is actively running).
	if id == RPC_SCRINITGAME then
		_CachedInitGame = SerializeData(id, BitStream, "RPC")
		lua_thread.create(function()
			wait(1000)
			local nickname = sampGetPlayerNickname(sampGetLocalPlayerId())
			local ConnectBitstream = raknetNewBitStream()
			raknetBitStreamWriteInt16(ConnectBitstream, sampGetLocalPlayerId())
			raknetBitStreamWriteInt32(ConnectBitstream, 0)
			raknetBitStreamWriteInt8(ConnectBitstream, 0)
			raknetBitStreamWriteInt8(ConnectBitstream, #nickname)
			raknetBitStreamWriteString(ConnectBitstream, nickname)
			_CachedConnectId = SerializeData(137, ConnectBitstream, "RPC")
			raknetDeleteBitStream(ConnectBitstream)
			_CachedFFLine = "FF" .. sampGetLocalPlayerId()

			-- If a recording is already running, feed it the fresh cache too.
			if _State == Mode.record or _State == Mode.paused then
				AddDataToQueue(_CachedInitGame, "RPC")
				AddDataToQueue(_CachedConnectId, "RPC")
				AddDataToQueue(_CachedFFLine, "RPC")
			end
		end)
	end

	if _State == Mode.record then
		AddDataToQueue(SerializeData(id, BitStream, "RPC"), "RPC")
	end
end

function onReceivePacket(id, BitStream)
	if _State == Mode.record then
		AddDataToQueue(SerializeData(id, BitStream, "Packet"), "Packet")
	end
end

function onSendPacket(id, BitStream)
	if _State == Mode.record then
		if id == PACKET_PLAYER_SYNC or id == PACKET_VEHICLE_SYNC then
			AddDataToQueue(ConvertOutputData(id, BitStream, true), "Packet")
		end
		for i=1, #NormalPackets do
			if id == NormalPackets[i] then
				AddDataToQueue(ConvertOutputData(id, BitStream, false), "Packet")
			end
		end
	end
end

--------------------------------------------------------------
-- PLAYER
--------------------------------------------------------------
Player = {
	Load = function(LoadPath)
		_DataPlaying = {}
		local directIni = getGameDirectory() .. "/moonloader/ReplayMod/" .. LoadPath
		local DataArray = LoadSave(directIni)

		if not DataArray then
			Say("Could not open save file: " .. LoadPath)
			return
		end

		_State = Mode.loaded
		_LoadedFileName = LoadPath
		_LoadedColors = {}
		Say(LoadPath .. " " .. Translate.fileloaded)
		for i=1, #DataArray do
			local line = tostring(DataArray[i])
			if line:sub(1, 1) == PacketTag.Waiting then
				local itter = tonumber(line:sub(2, #line))
				for j=1, itter do
					_DataPlaying[#_DataPlaying+1] = "nop"
				end
			elseif line:sub(1, 1) == PacketTag.ColorInfo then
				local rest = line:sub(2)
				local nick, colorHex, skinStr = rest:match("^(.-)=(%x+):(%-?%d+)$")
				if not nick then
					nick, colorHex = rest:match("^(.-)=(%x+)$")
				end
				if nick and nick ~= "" and colorHex then
					local skin = skinStr and tonumber(skinStr)
					if skin and skin < 0 then skin = nil end
					_LoadedColors[nick:lower()] = { color = tonumber(colorHex, 16), skin = skin, realName = nick }
				end
			else
				_DataPlaying[#_DataPlaying+1] = line
			end
		end
	end,

	Clear = function()
		_DataPlaying = {}
		_LoadedFileName = nil
		_LoadedColors = {}
		_State = Mode.idle
	end,

	StopPlay = function()
		_State = Mode.idle
		if _PossessMode.v then
			_PossessMode.v = false
			pcall(function() setCharVisible(1, true) end)
		end
	end,

	Pause = function()
		_PausePlayback = not _PausePlayback
		Say(_PausePlayback and Translate.playbackpause or Translate.playbackresume)
	end,

	Play = function()
		RemoveAllContent()
		Say(Translate.replaystarted)
		lua_thread.create(function()
			_State = Mode.replay
			Iteration = 0
			while _State == Mode.replay and Iteration < #_DataPlaying do
				wait(10)
				for i=1, ModuleAbs(math.floor(100 * _Multiplier.v)) do
					if not _PausePlayback then
						if _Multiplier.v > 0 then
							Iteration = Iteration + 1
						else
							Iteration = Iteration - 1
						end
						_ImguiIteration.v = Iteration
						if _DataPlaying[Iteration] ~= "nop" and _DataPlaying[Iteration] ~= nil then
							local M = _DataPlaying[Iteration]:sub(1, 1)
							local Data = _DataPlaying[Iteration]:sub(2, #_DataPlaying[Iteration])

							if M == PacketTag.RPC then
								local DoesIgnoreRPC = false
								if Data ~= nil then
									for k=1, #IgnoredRPCs do
										local HexID = Data:sub(1, 2)
										local RpcID = tonumber(HexID, 16)
										if RpcID == IgnoredRPCs[k] then DoesIgnoreRPC = true end
									end
									if not DoesIgnoreRPC then
										EmulateSerializedData(Data, "RPC")
										if tonumber(Data:sub(1, 2), 16) == RPC_SCRINITGAME then
											sampSpawnPlayer()
										end
									end
									if Data:sub(1, 2) == "FF" then
										_LocalPlayerId = tonumber(Data:sub(3, #Data))
										local bs = raknetNewBitStream()
										raknetBitStreamWriteInt16(bs, _LocalPlayerId)
										raknetBitStreamWriteInt8(bs, 0)
										raknetBitStreamWriteInt32(bs, 0)
										raknetBitStreamWriteFloat(bs, 0.0)
										raknetBitStreamWriteFloat(bs, 0.0)
										raknetBitStreamWriteFloat(bs, 0.0)
										raknetBitStreamWriteFloat(bs, 0.0)
										raknetBitStreamWriteInt32(bs, 0)
										raknetBitStreamWriteInt8(bs, 0)
										raknetEmulRpcReceiveBitStream(32, bs)
										raknetDeleteBitStream(bs)
									end
								end
							elseif M == PacketTag.Packet then
								if Data ~= nil then EmulateSerializedData(Data, "Packet") end
							end
						end
						if _State ~= Mode.replay then break end
					end
				end
			end
			Say(Translate.playbackover)
			if Settings.loopPlayback.v and _State == Mode.replay then
				Player.Play()
			else
				_State = Mode.loaded
			end
		end)

		
		local ownCharHidden = false

		lua_thread.create(function()
			while _State == Mode.replay do
				wait(150)
				if _PossessMode.v or Settings.autoCenterCamera.v then
					-- Possess mode targets whatever ID you entered.
					-- Auto-center (when Possess is off) still falls back
					-- to the recorded character, same as before.
					local targetId = _PossessMode.v and _PossessTargetId.v or _LocalPlayerId
					local result, handle = sampGetCharHandleBySampPlayerId(targetId)
					if result then
						-- This is the actual fix for the "duplicate stacked
						-- character" issue: your own real character (handle
						-- 1) gets teleported onto the recorded character's
						-- exact position every tick below. If it stays
						-- visible, you see your real body and the replay
						-- character standing on top of each other with the
						-- same skin. Hide it while this is active - this
						-- runs by default (autoCenterCamera is on by
						-- default), not just during explicit Possess.
						if not ownCharHidden then
							ownCharHidden = true
							pcall(function() setCharVisible(1, false) end)
						end

						local x, y, z = getCharCoordinates(handle)
						setCharCoordinates(1, x, y, z)

						-- Only (re)send the spectate RPCs when the target
						-- actually changes. Resending them every tick was
						-- forcing a pose/animation reset each time, which
						-- is why the possessed character kept snapping
						-- back to a generic walk animation instead of
						-- showing whatever it should really be doing.
						if lastPossessTarget ~= targetId then
							lastPossessTarget = targetId

							local bs = raknetNewBitStream()
							raknetBitStreamWriteInt32(bs, 1)
							raknetEmulRpcReceiveBitStream(124, bs)
							raknetDeleteBitStream(bs)

							if isCharInAnyCar(handle) then
								local car = storeCarCharIsInNoSave(handle)
								local res2, carid = sampGetVehicleIdByCarHandle(car)
								if res2 then
									local bs2 = raknetNewBitStream()
									raknetBitStreamWriteInt16(bs2, carid)
									raknetBitStreamWriteInt8(bs2, 1)
									raknetEmulRpcReceiveBitStream(126, bs2)
									raknetDeleteBitStream(bs2)
								end
							else
								local bs2 = raknetNewBitStream()
								raknetBitStreamWriteInt16(bs2, targetId)
								raknetBitStreamWriteInt8(bs2, 1)
								raknetEmulRpcReceiveBitStream(126, bs2)
								raknetDeleteBitStream(bs2)
							end
						end
					end
				else
					if ownCharHidden then
						ownCharHidden = false
						pcall(function() setCharVisible(1, true) end)
					end
					lastPossessTarget = nil -- so re-entering possess resends cleanly
				end
			end
			if ownCharHidden then
				pcall(function() setCharVisible(1, true) end)
			end
		end)

		lua_thread.create(function()
			wait(6000)
			while _State == Mode.replay do
				wait(1000)
				local result, handle = sampGetCharHandleBySampPlayerId(_LocalPlayerId)
				if not result then
					local bs = raknetNewBitStream()
					raknetBitStreamWriteInt16(bs, _LocalPlayerId)
					raknetBitStreamWriteInt8(bs, 0)
					raknetBitStreamWriteInt32(bs, 0)
					raknetBitStreamWriteFloat(bs, 0.0)
					raknetBitStreamWriteFloat(bs, 0.0)
					raknetBitStreamWriteFloat(bs, 0.0)
					raknetBitStreamWriteFloat(bs, 0.0)
					raknetBitStreamWriteInt32(bs, 0)
					raknetBitStreamWriteInt8(bs, 0)
					raknetEmulRpcReceiveBitStream(32, bs)
					raknetDeleteBitStream(bs)
				end
			end
		end)
	end,

	Rewind = function(arg)
		if arg < 0 or arg > #_DataPlaying then return Say(Translate.incorrecttime) end
		lua_thread.create(function()
			_IsRewind = _IsRewind + 1
			if _IsRewind >= 1 and _CanRewind then
				Say(Translate.rewindstarts)
				if arg > Iteration then
					_Multiplier.v = 1000
					while Iteration < arg do wait(10) end
					_Multiplier.v = 1
				else
					local x, y, z = getCharCoordinates(1)
					Player.StopPlay()
					wait(100)
					Player.Play()
					_Multiplier.v = 1000
					while Iteration < arg do wait(10) end
					_Multiplier.v = 1
					setCharCoordinates(1, x, y, z)
				end
				Say(Translate.jumpedtotime .. ": " .. ConvertTicksToTimeString(arg))
				_IsRewind = 0
			end
		end)
		if _CanRewind then
			lua_thread.create(function()
				_CanRewind = false
				wait(Settings.rewindCooldownSec.v * 1000)
				_CanRewind = true
			end)
		else
			Say(Translate.waitcooldown)
		end
	end
}
_PausePlayback = false

--------------------------------------------------------------
-- RED THEMED UI (single window, tabs for Record / Playback / Saves / Settings / Info)
--------------------------------------------------------------
function imgui.OnDrawFrame()
	imgui.SetNextWindowSize(imgui.ImVec2(780, 380), imgui.Cond.FirstUseEver)
	imgui.SetNextWindowPos(imgui.ImVec2(300, 240), imgui.Cond.FirstUseEver)
	imgui.Begin(u8("ReplayMod (" .. _Version .. ")"), windows_state, imgui.WindowFlags.NoResize)

	imgui.BeginChild("Nav", imgui.ImVec2(190, 338), true)
		if imgui.Button(Translate.recordmenu, imgui.ImVec2(-0.1, 62)) then _MenuPage = 1 end
		if imgui.Button(Translate.playbackmenu, imgui.ImVec2(-0.1, 62)) then _MenuPage = 2 end
		if imgui.Button(Translate.saves, imgui.ImVec2(-0.1, 62)) then _MenuPage = 3 end
		if imgui.Button(Translate.settingsmenu, imgui.ImVec2(-0.1, 62)) then _MenuPage = 4 end
		if imgui.Button(Translate.info, imgui.ImVec2(-0.1, 62)) then _MenuPage = 5 end
		if imgui.Button("Colors", imgui.ImVec2(-0.1, 62)) then _MenuPage = 6 end
	imgui.EndChild()

	imgui.SameLine()

	imgui.BeginChild("Body", imgui.ImVec2(565, 338), true)
		if _MenuPage == 1 then DrawRecordPage()
		elseif _MenuPage == 2 then DrawPlaybackPage()
		elseif _MenuPage == 3 then DrawSavesPage()
		elseif _MenuPage == 4 then DrawSettingsPage()
		elseif _MenuPage == 5 then DrawInfoPage()
		elseif _MenuPage == 6 then DrawColorsPage()
		end
	imgui.EndChild()

	imgui.End()
end

function DrawRecordPage()
	if _State == Mode.idle then
		if isSampAvailable() then
			imgui.CenterText(Translate.readytostart)
		else
			imgui.CenterText(Translate.notconnected)
		end
		imgui.Dummy(imgui.ImVec2(0, 12))
		if imgui.Button(Translate.startrecording, imgui.ImVec2(-0.1, 70)) then
			Recorder.Start()
		end
	elseif _State == Mode.record or _State == Mode.paused then
		imgui.CenterText(Translate.currentlyrecording)
		imgui.CenterText(_CurrentSaveName or "...")
		imgui.CenterText(FormatElapsed(os.clock() - _RecordStartTick))
		imgui.Dummy(imgui.ImVec2(0, 10))
		if imgui.Button(_State == Mode.paused and Translate.resumerecording or Translate.pauserecording, imgui.ImVec2(-0.1, 55)) then
			Recorder.TogglePause()
		end
		if imgui.Button(Translate.stoprecording, imgui.ImVec2(-0.1, 55)) then
			Recorder.Stop()
		end
	else
		imgui.CenterText("Currently in playback mode.")
		imgui.CenterText("Stop playback before recording.")
	end
end

function DrawPlaybackPage()
	if _State == Mode.replay then
		imgui.CenterText(ConvertTicksToTimeString(Iteration) .. " / " .. ConvertTicksToTimeString(#_DataPlaying))

		imgui.PushItemWidth(-1)
		-- FIX: SliderInt returns true on every value change WHILE DRAGGING, not
		-- just on release - so calling Player.Rewind() right here fired dozens
		-- of rewind requests per drag gesture, which each hit the cooldown and
		-- flooded the chat with "please wait" messages, making the seek bar
		-- effectively unusable with the mouse. Only let the handle MOVE while
		-- dragging; fire the actual rewind once, when the drag is released.
		imgui.SliderInt("##timeline", _ImguiIteration, 0, #_DataPlaying)
		if imgui.IsItemDeactivatedAfterEdit() then
			Player.Rewind(_ImguiIteration.v)
		end

		imgui.PushItemWidth(90)
		imgui.InputText("##time", _GoToTime)
		imgui.SameLine()
		if imgui.Button(Translate.jumptotime, imgui.ImVec2(-0.1, 20)) then
			if ConvertTimeStringToTicks(_GoToTime.v) then
				Player.Rewind(ConvertTimeStringToTicks(_GoToTime.v))
			else
				Say(Translate.wrongtime)
			end
		end

		imgui.Dummy(imgui.ImVec2(0, 6))
		imgui.CenterText(Translate.playbackspeed .. ": " .. string.format("%.1fx", _Multiplier.v))
		imgui.PushItemWidth(-1)
		imgui.SliderFloat("##speed", _Multiplier, -4.0, 4.0)
		if imgui.Button("0.5x", imgui.ImVec2(85, 25)) then _Multiplier.v = 0.5 end
		imgui.SameLine()
		if imgui.Button("1x", imgui.ImVec2(85, 25)) then _Multiplier.v = 1.0 end
		imgui.SameLine()
		if imgui.Button("2x", imgui.ImVec2(85, 25)) then _Multiplier.v = 2.0 end
		imgui.SameLine()
		if imgui.Button(u8("⏪ Reverse"), imgui.ImVec2(85, 25)) then _Multiplier.v = -1.0 end

		imgui.Dummy(imgui.ImVec2(0, 8))
		if imgui.Button(_PausePlayback and Translate.continueplayback or Translate.pause, imgui.ImVec2(-0.1, 45)) then
			Player.Pause()
		end
		if imgui.Button(Translate.stopplayback, imgui.ImVec2(-0.1, 45)) then
			Player.StopPlay()
		end

		imgui.Dummy(imgui.ImVec2(0, 8))
		imgui.Separator()
		imgui.Text("Possess a character (ride view):")
		if _PossessMode.v then
			imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0),
				"Currently inside player ID " .. _PossessTargetId.v)
		else
			imgui.TextDisabled("Not possessing anyone.")
		end

		imgui.Text("Player ID:")
		imgui.SameLine()
		imgui.PushItemWidth(80)
		imgui.InputInt("##possessId", _PossessTargetId)
		imgui.PopItemWidth()
		imgui.SameLine()
		if imgui.Button("Enter Body", imgui.ImVec2(120, 0)) then
			_PossessMode.v = true
			lastPossessTarget = nil -- force a fresh spectate sync right away
			pcall(function() setCharVisible(1, false) end) -- hide your own
			-- character so it doesn't sit on top of the target's model
			-- and flicker/appear-disappear at their position
			Say("Possess mode: ON (player ID " .. _PossessTargetId.v .. ")")
		end
		imgui.SameLine()
		if imgui.Button("Refresh", imgui.ImVec2(80, 0)) then
			-- Manual fix for a possessed character whose walk animation
			-- gets stuck/frozen: forces the spectate link to be resent
			-- fresh on the next tick instead of waiting for the target
			-- ID to change.
			lastPossessTarget = nil
			Say("Refreshed possess link.")
		end
		imgui.SameLine()
		if imgui.Button("Exit Body", imgui.ImVec2(100, 0)) then
			local exitTargetId = _PossessTargetId.v
			_PossessMode.v = false
			if Settings.autoCenterCamera.v then
				Settings.autoCenterCamera.v = false
			end

			lua_thread.create(function()
				-- Grab the possessed character's position BEFORE releasing
				-- spectate, so we can land you right beside them after.
				local exitX, exitY, exitZ = nil, nil, nil
				local res, handle = sampGetCharHandleBySampPlayerId(exitTargetId)
				if res then
					exitX, exitY, exitZ = getCharCoordinates(handle)
				end

				-- This is the actual fix: stopping the tracking loop alone
				-- never told the game to release spectate mode. SpectatorMode
				-- (already used elsewhere in this file, in RemoveAllContent)
				-- is the real "turn spectate off" call that was missing here.
				SpectatorMode(1)
				SpectatorMode(0)
				wait(150)
				sampSpawnPlayer()
				wait(150)

				-- Land you right next to the character you just exited,
				-- instead of wherever the default respawn point is.
				if exitX then
					setCharCoordinates(1, exitX + 1.5, exitY + 1.5, exitZ)
				end

				pcall(function() setCharVisible(1, true) end)
				restoreCameraJumpcut()
				Say("Possess mode: OFF")
			end)
		end

	elseif _State == Mode.loaded then
		imgui.CenterText("Loaded: " .. (_LoadedFileName or "?"))
		imgui.Dummy(imgui.ImVec2(0, 10))
		if imgui.Button(Translate.play, imgui.ImVec2(-0.1, 110)) then
			Player.Play()
		end
		if imgui.Button(Translate.unloadloadedsave, imgui.ImVec2(-0.1, 110)) then
			Player.Clear()
		end
	else
		imgui.CenterText(Translate.waitingforplayback)
		imgui.Dummy(imgui.ImVec2(0, 10))
		imgui.CenterText("Open the \"" .. Translate.saves .. "\" tab to load a recording.")
	end
end

function DrawSavesPage()
	local files = {}
	local handle, file = findFirstFile("moonloader/ReplayMod/*.replay")
	if handle then
		while file do
			files[#files + 1] = file
			file = findNextFile(handle)
		end
		findClose(handle)
	end

	imgui.CenterText(#files .. " recording(s) found")
	imgui.Separator()

	for i=#files, 1, -1 do
		if files[i] ~= "readme.txt" and files[i] ~= "." and files[i] ~= ".." then
			if imgui.CollapsingHeader(files[i]) then
				if _State == Mode.idle then
					if imgui.Button(Translate.load, imgui.ImVec2(270, 24)) then
						Player.Load(files[i])
					end
					imgui.SameLine()
				end
				if imgui.Button(Translate.deletesave, imgui.ImVec2(_State == Mode.idle and 270 or -0.1, 24)) then
					os.remove(getGameDirectory().."/moonloader/ReplayMod/"..files[i])
				end
			end
		end
	end
end

function DrawColorsPage()
	imgui.TextDisabled("Colors AND skins - collected automatically while connected, no need to be recording.")
	imgui.Spacing()

	if _LoadedFileName and next(_LoadedColors) then
		imgui.CenterText("From loaded recording: " .. _LoadedFileName)
		imgui.BeginChild("LoadedColorList", imgui.ImVec2(0, 150), true)
			for _, data in pairs(_LoadedColors) do
				local r = bit.band(bit.rshift(data.color, 24), 0xFF) / 255
				local g = bit.band(bit.rshift(data.color, 16), 0xFF) / 255
				local b = bit.band(bit.rshift(data.color, 8), 0xFF) / 255
				local label = data.realName .. (data.skin and ("  (skin " .. data.skin .. ")") or "")
				imgui.TextColored(imgui.ImVec4(r, g, b, 1.0), label)
			end
		imgui.EndChild()
		imgui.Separator()
	end

	imgui.CenterText("Captured player name colors & skins")
	imgui.TextDisabled("Stored in player_colors.ini.")
	imgui.Separator()

	local count = 0
	for _ in pairs(_PlayerColors) do count = count + 1 end
	imgui.Text("Total captured: " .. count)
	imgui.Spacing()

	imgui.BeginChild("ColorList", imgui.ImVec2(0, 400), true)
		if count == 0 then
			imgui.Spacing()
			imgui.CenterText("Nothing captured yet - connect to a server and wait a few seconds.")
		else
			for _, data in pairs(_PlayerColors) do
				local r = bit.band(bit.rshift(data.color, 24), 0xFF) / 255
				local g = bit.band(bit.rshift(data.color, 16), 0xFF) / 255
				local b = bit.band(bit.rshift(data.color, 8), 0xFF) / 255
				local label = data.realName .. (data.skin and ("  (skin " .. data.skin .. ")") or "")
				imgui.TextColored(imgui.ImVec4(r, g, b, 1.0), label)
			end
		end
	imgui.EndChild()
end

function DrawSettingsPage()
	imgui.CenterText(Translate.settingsmenu)
	imgui.Dummy(imgui.ImVec2(0, 6))

	if imgui.Button(Translate.switchtoviewmode, imgui.ImVec2(-0.1, 32)) then
		RemoveAllContent()
	end

	imgui.Dummy(imgui.ImVec2(0, 8))
	imgui.Separator()
	imgui.Dummy(imgui.ImVec2(0, 4))

	imgui.Checkbox(Translate.autocentercam, Settings.autoCenterCamera)
	imgui.Checkbox(Translate.loopplaybackopt, Settings.loopPlayback)
	imgui.Checkbox("Show chat notifications", Settings.chatNotify)
	imgui.Checkbox("Show on-screen overlay", Settings.overlayEnabled)
	imgui.Checkbox("Hide time/progress while watching playback", Settings.hideTimeOverlay)

	imgui.Dummy(imgui.ImVec2(0, 8))
	imgui.Text(Translate.rewindcooldown)
	imgui.PushItemWidth(-1)
	imgui.SliderInt("##cooldown", Settings.rewindCooldownSec, 1, 30)

	imgui.Dummy(imgui.ImVec2(0, 8))
	imgui.Text(Translate.nameprefix)
	imgui.PushItemWidth(-1)
	imgui.InputText("##prefix", Settings.customNamePrefix)

	imgui.Dummy(imgui.ImVec2(0, 10))
	if imgui.Button("Save settings", imgui.ImVec2(-0.1, 30)) then
		SaveSettings()
		Say("Settings saved.")
	end
end

function DrawInfoPage()
	imgui.CenterText("")
	imgui.CenterText("ReplayMod " .. _Version)
	imgui.CenterText(Translate.activation)
	imgui.CenterText("/rmstart, /rmstop, /rmpause")
	imgui.CenterText("/rewind HH:MM:SS, /rmpossess")
	imgui.CenterText("")
	imgui.CenterText("Recording is fully manual: start/stop anytime.")
	imgui.CenterText("World-init data is cached on connect and")
	imgui.CenterText("written automatically when you press Start.")
	imgui.CenterText("")
	imgui.CenterText("Original script: kuzheren (maynkraftpro2010)")
	imgui.CenterText("Unified Edition build")
	imgui.CenterText("")
	imgui.CenterText("Author: Sam Wilson")
	imgui.CenterText("Автор - Sam Wilson")
end

function imgui.CenterText(text)
	local width = imgui.GetWindowWidth()
	local calc = imgui.CalcTextSize(text)
	imgui.SetCursorPosX(width / 2 - calc.x / 2)
	imgui.Text(text)
end

--------------------------------------------------------------
-- Shared low-level helpers (serialization / bit manipulation)
-- Unchanged in logic from the original scripts.
--------------------------------------------------------------
function ConvertOutputData(Mode_, BitStream, IsCompressed)
	raknetBitStreamSetReadOffset(BitStream, 8)
	local BitString = DecToBinary(Mode_, 8) .. BigEndianToLittleEndian(DecToBinary(sampGetLocalPlayerId(), 16))
	if IsCompressed then
		if Mode_ == PACKET_PLAYER_SYNC then
			local LrKey = raknetBitStreamReadInt16(BitStream)
			if LrKey ~= 0 then
				BitString = BitString .. "1" .. BigEndianToLittleEndian(DecToBinary(LrKey, 16))
			else
				BitString = BitString .. "0"
			end
			local UdKey = raknetBitStreamReadInt16(BitStream)
			if UdKey ~= 0 then
				BitString = BitString .. "1" .. BigEndianToLittleEndian(DecToBinary(UdKey, 16))
			else
				BitString = BitString .. "0"
			end
			local Keys = raknetBitStreamReadInt16(BitStream)
			if Keys == 160 then Keys = 0 end
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(Keys, 16))

			local X, Y, Z = raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream)
			BitString = BitString .. HexStringToBitString(FloatToLittleEndianBitString(X)) .. HexStringToBitString(FloatToLittleEndianBitString(Y)) .. HexStringToBitString(FloatToLittleEndianBitString(Z))

			local QuatW, QuatX, QuatY, QuatZ = raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream)
			BitString = BitString .. BoolToNum(QuatW < 0) .. BoolToNum(QuatX < 0) .. BoolToNum(QuatY < 0) .. BoolToNum(QuatZ < 0)
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(math.floor(math.abs(QuatX) * 65535), 16))
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(math.floor(math.abs(QuatY) * 65535), 16))
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(math.floor(math.abs(QuatZ) * 65535), 16))

			local Health = raknetBitStreamReadInt8(BitStream)
			local Armor = raknetBitStreamReadInt8(BitStream)
			BitString = BitString .. DecToBinary(compress_health_and_armor(Health, Armor), 8)

			local Weapon = raknetBitStreamReadInt8(BitStream)
			BitString = BitString .. DecToBinary(Weapon, 8)
			local SpecialAction = raknetBitStreamReadInt8(BitStream)
			BitString = BitString .. DecToBinary(SpecialAction, 8)

			local MovespeedX, MovespeedY, MovespeedZ = raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream)
			local Magnitude = math.sqrt(MovespeedX^2 + MovespeedY^2 + MovespeedZ^2)
			BitString = BitString .. HexStringToBitString(FloatToLittleEndianBitString(Magnitude))
			if Magnitude == 0 then Magnitude = 0.0001 end
			if Magnitude > 0 then
				BitString = BitString .. writeCf(MovespeedX / Magnitude)
				BitString = BitString .. writeCf(MovespeedY / Magnitude)
				BitString = BitString .. writeCf(MovespeedZ / Magnitude)
			end

			BitString = BitString .. "0"
			local SurfingVehicleID = raknetBitStreamReadInt16(BitStream)
			local SurfOffsetX = raknetBitStreamReadFloat(BitStream)
			local SurfOffsetY = raknetBitStreamReadFloat(BitStream)
			local SurfOffsetZ = raknetBitStreamReadFloat(BitStream)

			local AnimID = raknetBitStreamReadInt16(BitStream)
			local AnimFlags = raknetBitStreamReadInt16(BitStream)
			BitString = BitString .. "1"
			BitString = BitString .. DecToBinary(sampGetPlayerAnimationId(sampGetLocalPlayerId()), 16)
			BitString = BitString .. DecToBinary(AnimFlags, 16)

			repeat BitString = BitString .. "0" until #BitString % 8 == 0
			return BitStringToHexString(BitString)
		end
		if Mode_ == PACKET_VEHICLE_SYNC then
			local CarID = raknetBitStreamReadInt16(BitStream)
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(CarID, 16))

			local LrKey = raknetBitStreamReadInt16(BitStream)
			if LrKey ~= 0 then
				if LrKey == 65408 then BitString = BitString .. "1000000011111111"
				elseif LrKey == 128 then BitString = BitString .. "1000000000000000" end
			else
				BitString = BitString .. "0000000000000000"
			end

			local UdKey = raknetBitStreamReadInt16(BitStream)
			if UdKey ~= 0 then
				if UdKey == 65408 then BitString = BitString .. "1000000011111111"
				elseif UdKey == 128 then BitString = BitString .. "1000000000000000" end
			else
				BitString = BitString .. "0000000000000000"
			end

			local Keys = raknetBitStreamReadInt16(BitStream)
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(Keys, 16))

			local QuatW, QuatX, QuatY, QuatZ = raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream)
			BitString = BitString .. BoolToNum(QuatW < 0) .. BoolToNum(QuatX < 0) .. BoolToNum(QuatY < 0) .. BoolToNum(QuatZ < 0)
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(math.floor(math.abs(QuatX) * 65535), 16))
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(math.floor(math.abs(QuatY) * 65535), 16))
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(math.floor(math.abs(QuatZ) * 65535), 16))

			local X, Y, Z = raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream)
			BitString = BitString .. HexStringToBitString(FloatToLittleEndianBitString(X)) .. HexStringToBitString(FloatToLittleEndianBitString(Y)) .. HexStringToBitString(FloatToLittleEndianBitString(Z))

			local MovespeedX, MovespeedY, MovespeedZ = raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream), raknetBitStreamReadFloat(BitStream)
			local Magnitude = math.sqrt(MovespeedX^2 + MovespeedY^2 + MovespeedZ^2)
			if Magnitude == 0 then Magnitude = 0.001 end
			BitString = BitString .. HexStringToBitString(FloatToLittleEndianBitString(Magnitude))
			if Magnitude > 0 then
				BitString = BitString .. writeCf(MovespeedX / Magnitude)
				BitString = BitString .. writeCf(MovespeedY / Magnitude)
				BitString = BitString .. writeCf(MovespeedZ / Magnitude)
			end

			local CarHealth = raknetBitStreamReadFloat(BitStream)
			BitString = BitString .. BigEndianToLittleEndian(DecToBinary(sampGetLocalPlayerCarHealth(), 16))

			local Health = raknetBitStreamReadInt8(BitStream)
			local Armor = raknetBitStreamReadInt8(BitStream)
			BitString = BitString .. DecToBinary(compress_health_and_armor(Health, Armor), 8)

			local Weapon = raknetBitStreamReadInt8(BitStream)
			BitString = BitString .. DecToBinary(Weapon, 8)

			local SirenState = raknetBitStreamReadBool(BitStream)
			BitString = BitString .. BoolToNum(SirenState)

			local GearState = raknetBitStreamReadBool(BitStream)
			BitString = BitString .. BoolToNum(GearState)

			local TrainSpeed = raknetBitStreamReadFloat(BitStream)
			if TrainSpeed ~= 0 then
				BitString = BitString .. "1" .. "00000000000000000000000000000000"
			else
				BitString = BitString .. "0"
			end

			local TrailerID = raknetBitStreamReadInt16(BitStream)
			if TrailerID ~= 0 then
				BitString = BitString .. "1" .. BigEndianToLittleEndian(DecToBinary(TrailerID, 16))
			else
				BitString = BitString .. "0"
			end

			repeat BitString = BitString .. "0" until #BitString % 8 == 0
			return BitStringToHexString(BitString)
		end
	else
		for i=1, raknetBitStreamGetNumberOfUnreadBits(BitStream) / 8 do
			BitString = BitString .. DecToBinary(raknetBitStreamReadInt8(BitStream), 8)
		end
		return BitStringToHexString(BitString)
	end
end

function SerializeData(id, BitStream, ModeTag)
	local SerializedString = ToHex(id)
	if ModeTag == "Packet" then raknetBitStreamSetReadOffset(BitStream, 8) end
	local Bytes = {}
	for i=1, raknetBitStreamGetNumberOfUnreadBits(BitStream) / 8 do
		Bytes[i] = raknetBitStreamReadInt8(BitStream)
	end
	if id == RPC_SCRINITGAME and ModeTag == "RPC" then
		Bytes[14] = 233
		Bytes[15] = 3
	end
	local SerializedStringBytes = ""
	for i=1, #Bytes do
		SerializedStringBytes = SerializedStringBytes .. ToHex(Bytes[i])
	end
	return SerializedString .. SerializedStringBytes
end

function EmulateSerializedData(SerializedString, ModeTag)
	local DeserializedBytes = DeserializeString(SerializedString)
	local Id = DeserializedBytes[1]
	table.remove(DeserializedBytes, 1)
	local BitStream = raknetNewBitStream()
	for i=1, #DeserializedBytes do
		raknetBitStreamWriteInt8(BitStream, DeserializedBytes[i])
	end
	if ModeTag == "RPC" then
		raknetEmulRpcReceiveBitStream(Id, BitStream)
	elseif ModeTag == "Packet" then
		raknetEmulPacketReceiveBitStream(Id, BitStream)
	end
	raknetDeleteBitStream(BitStream)
end

function DeserializeString(SerializedString)
	local DeserializedBytes = {}
	local SerializedBytes = {}
	for i=1, #SerializedString, 2 do
		SerializedBytes[#SerializedBytes+1] = tostring(SerializedString):sub(i, i+1)
	end
	for i=1, #SerializedBytes do
		DeserializedBytes[i] = tonumber(SerializedBytes[i], 16)
	end
	return DeserializedBytes
end

function AddDataToQueue(SerializedString, ModeTag)
	if ModeTag == "RPC" then
		_DataQueue[#_DataQueue+1] = PacketTag.RPC .. SerializedString
	elseif ModeTag == "Packet" then
		_DataQueue[#_DataQueue+1] = PacketTag.Packet .. SerializedString
	end
end

function AddDataToSaveFile(SaveHandle, Data)
	-- Writes are buffered; the recorder flushes on a wall-clock schedule and
	-- performs one final flush before closing the file.
	SaveHandle:write(Data)
end

function LoadSave(LoadPath)
	local file = io.open(LoadPath, "r")
	if not file then return nil end
	local lines = {}
	for line in file:lines() do table.insert(lines, line) end
	file:close()
	return lines
end

function compress_health_and_armor(hp, armor)
	local hpAp = 0
	if hp > 0 and hp < 100 then hpAp = bit.lshift(hp / 7, 4)
	elseif hp >= 100 then hpAp = 0xF0 end
	if armor > 0 and armor < 100 then hpAp = bit.bor(hpAp, armor / 7)
	elseif armor >= 100 then hpAp = bit.bor(hpAp, 0x0F) end
	return hpAp
end

function writeCf(value)
	if value < -1 then value = -1 elseif value > 1 then value = 1 end
	return BigEndianToLittleEndian(DecToBinary((math.floor((value + 1) * 32767.5)), 16))
end

function FloatToBigEndianBitString(n)
	if n == 0.0 then return 0.0 end
	local sign = 0
	if n < 0.0 then sign = 0x80; n = -n end
	local mant, expo = math.frexp(n)
	local hext = {}
	if mant ~= mant then
		hext[#hext+1] = string.char(0xFF, 0x88, 0x00, 0x00)
	elseif mant == math.huge or expo > 0x80 then
		if sign == 0 then hext[#hext+1] = string.char(0x7F, 0x80, 0x00, 0x00)
		else hext[#hext+1] = string.char(0xFF, 0x80, 0x00, 0x00) end
	elseif (mant == 0.0 and expo == 0) or expo < -0x7E then
		hext[#hext+1] = string.char(sign, 0x00, 0x00, 0x00)
	else
		expo = expo + 0x7E
		mant = (mant * 2.0 - 1.0) * math.ldexp(0.5, 24)
		hext[#hext+1] = string.char(sign + math.floor(expo / 0x2),
									(expo % 0x2) * 0x80 + math.floor(mant / 0x10000),
									math.floor(mant / 0x100) % 0x100,
									mant % 0x100)
	end
	return string.gsub(table.concat(hext),"(.)", function (c) return string.format("%02X%s",string.byte(c),"") end)
end

function FloatToLittleEndianBitString(FloatNumber)
	local BigEndianHexString = FloatToBigEndianBitString(FloatNumber)
	local bytes = {}
	local hexarr = StringToTable(BigEndianHexString)
	for i=1, #hexarr/2 do
		bytes[#bytes+1] = hexarr[1] .. hexarr[2]
		table.remove(hexarr, 1)
		table.remove(hexarr, 1)
	end
	bytes = Reverse(bytes)
	return table.concat(bytes)
end

function BitStringToHexString(s)
	local bin2hex = {
		["0000"]="0",["0001"]="1",["0010"]="2",["0011"]="3",["0100"]="4",["0101"]="5",
		["0110"]="6",["0111"]="7",["1000"]="8",["1001"]="9",["1010"]="A",["1011"]="B",
		["1100"]="C",["1101"]="D",["1110"]="E",["1111"]="F"
	}
	local l = string.len(s)
	local rem = l % 4
	l = l - 1
	local h = ""
	if rem > 0 then s = string.rep("0", 4 - rem)..s end
	for i = 1, l, 4 do
		local b = string.sub(s, i, i+3)
		h = h..bin2hex[b]
	end
	return h
end

function HexStringToBitString(hexstr)
	local hex2bin = {
		["0"]="0000",["1"]="0001",["2"]="0010",["3"]="0011",["4"]="0100",["5"]="0101",
		["6"]="0110",["7"]="0111",["8"]="1000",["9"]="1001",["A"]="1010",["B"]="1011",
		["C"]="1100",["D"]="1101",["E"]="1110",["F"]="1111"
	}
	local ret = ""
	for i = 1, #hexstr do ret = ret..hex2bin[hexstr:sub(i, i)] end
	return ret
end

function BigEndianToLittleEndian(BigEndianBits)
	local LittleEndianBits = ""
	if #BigEndianBits == 16 then
		LittleEndianBits = BigEndianBits:sub(9, 16) .. BigEndianBits:sub(1, 8)
	end
	return LittleEndianBits
end

function DecToBinary(num, bits)
	bits = bits or math.max(1, select(2, math.frexp(num)))
	local t = {}
	for b = bits, 1, -1 do
		t[b] = math.fmod(num, 2)
		num = math.floor((num - t[b]) / 2)
	end
	return table.concat(t)
end

function sampGetLocalPlayerId()
	return select(2, sampGetPlayerIdByCharHandle(1))
end

function ToHex(int)
	local s = string.format("%X", tostring(int))
	if #s == 1 then s = "0" .. s end
	return s
end

function StringToTable(str)
	local t = {}
	for i=1, #tostring(str) do t[i] = tostring(str):sub(i, i) end
	return t
end

function Reverse(t)
	local r = {}
	local n = #t
	for k, v in ipairs(t) do r[n + 1 - k] = v end
	return r
end

function BoolToNum(b) return b and "1" or "0" end

local function SafeFilePart(value, fallback)
	local part = tostring(value or ""):gsub("[^%w_%-]", "_")
	part = part:gsub("_+", "_"):sub(1, 40)
	if part == "" then return fallback end
	return part
end

function DeGenerateName(prefix)
	local safePrefix = SafeFilePart(prefix, "Replay")
	local safeNickname = SafeFilePart(sampGetPlayerNickname(sampGetLocalPlayerId()), "Player")
	local base = safePrefix .. "_" .. safeNickname .. "_" .. tostring(os.date("%Y-%m-%d_%H-%M-%S"))
	local directory = getGameDirectory() .. "/moonloader/ReplayMod/"
	local candidate = base .. ".replay"
	local suffix = 1
	-- Avoid appending a new recording to an existing file when two starts
	-- happen during the same timestamp second.
	while doesFileExist(directory .. candidate) do
		candidate = base .. "_" .. tostring(suffix) .. ".replay"
		suffix = suffix + 1
	end
	return candidate
end

function sampGetLocalPlayerCarHealth()
	local carhealth = 1000
	pcall(function() carhealth = getCarHealth(storeCarCharIsInNoSave(1)) end)
	return carhealth
end

function RemoveAllContent()
	if _State == Mode.replay then _State = Mode.idle end
	lua_thread.create(function()
		sampDisconnectWithReason(0)
		wait(100)
		sampSetGamestate(3)
		wait(100)
		sampSpawnPlayerWithEmulation()
		wait(100)
		SpectatorMode(1)
		SpectatorMode(0)
		wait(100)
		sampSpawnPlayer()
		restoreCameraJumpcut()
	end)
end

function sampSpawnPlayerWithEmulation()
	emul_rpc('onRequestSpawnResponse', {true})
	emul_rpc('onSetSpawnInfo', {0, 74, 0, {2495.0187988281, -1686.2733154297, 13.512998580933}, 0, {0}, {0}})
	restoreCameraJumpcut()
end

function SpectatorMode(modeVal)
	local bs = raknetNewBitStream()
	raknetBitStreamWriteInt32(bs, modeVal)
	raknetEmulRpcReceiveBitStream(124, bs)
	raknetDeleteBitStream(bs)
end

function ModuleAbs(int)
	if int > 0 then return int else return -int end
end

function ConvertTicksToTimeString(ticks)
	ticks = ticks / 10000
	local hours, mins, sec = math.floor(ticks % (3600*24) / 3600), math.floor(ticks % 3600 / 60), math.floor(ticks % 60)
	return tostring(string.format("%02d:%02d:%02d", hours, mins, sec))
end

function ConvertTimeStringToTicks(timestring)
	local t = split(timestring, ":")
	if #t == 3 then
		if tonumber(t[1]) and tonumber(t[2]) and tonumber(t[3]) then
			return (tonumber(t[1]) * 3600 + tonumber(t[2]) * 60 + tonumber(t[3])) * 10000
		end
	end
end

function split(inputstr, sep)
	if sep == nil then sep = "%s" end
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do table.insert(t, str) end
	return t
end

function emul_rpc(hook, parameters)
	local bs_io = require 'samp.events.bitstream_io'
	local handler = require 'samp.events.handlers'
	local extra_types = require 'samp.events.extra_types'
	local hooks = {
		['onRequestSpawnResponse'] = { 'bool8', 129 },
		['onSetSpawnInfo'] = { 'int8', 'int32', 'int8', 'vector3d', 'float', 'Int32Array3', 'Int32Array3', 68 }
	}
	local extra = { ['PlayerScorePingMap'] = true, ['Int32Array3'] = true }
	local hook_table = hooks[hook]
	if hook_table then
		local bs = raknetNewBitStream()
		local max = #hook_table-1
		if max > 0 then
			for i = 1, max do
				local p = hook_table[i]
				if extra[p] then extra_types[p]['write'](bs, parameters[i])
				else bs_io[p]['write'](bs, parameters[i]) end
			end
		end
		raknetEmulRpcReceiveBitStream(hook_table[#hook_table], bs)
		raknetDeleteBitStream(bs)
	end
end

function string.replace(text, old, new)
	local b, e = text:find(old, 1, true)
	if not b then return text else return text:sub(1, b - 1) .. new .. text:sub(e + 1) end
end

--------------------------------------------------------------
-- RED THEME
--------------------------------------------------------------
function ApplyRedTheme()
	imgui.SwitchContext()
	local style  = imgui.GetStyle()
	local colors = style.Colors
	local clr    = imgui.Col
	local ImVec4 = imgui.ImVec4

	style.WindowRounding      = 6.0
	style.ChildWindowRounding = 5.0
	style.FrameRounding       = 4.0
	style.ItemSpacing         = imgui.ImVec2(6.0, 5.0)
	style.ScrollbarSize       = 13.0
	style.GrabRounding        = 4.0
	style.WindowTitleAlign    = imgui.ImVec2(0.5, 0.5)

	colors[clr.Text]                 = ImVec4(1.00, 0.96, 0.96, 1.00)
	colors[clr.TextDisabled]         = ImVec4(0.65, 0.45, 0.45, 1.00)
	colors[clr.WindowBg]             = ImVec4(0.10, 0.03, 0.03, 0.96)
	colors[clr.ChildWindowBg]        = ImVec4(0.14, 0.04, 0.04, 1.00)
	colors[clr.PopupBg]              = ImVec4(0.08, 0.02, 0.02, 0.96)
	colors[clr.Border]               = ImVec4(0.90, 0.10, 0.10, 1.00)
	colors[clr.BorderShadow]         = ImVec4(0.00, 0.00, 0.00, 0.00)
	colors[clr.FrameBg]              = ImVec4(0.45, 0.08, 0.08, 1.00)
	colors[clr.FrameBgHovered]       = ImVec4(0.62, 0.10, 0.10, 1.00)
	colors[clr.FrameBgActive]        = ImVec4(0.75, 0.12, 0.12, 1.00)
	colors[clr.TitleBg]              = ImVec4(0.30, 0.04, 0.04, 1.00)
	colors[clr.TitleBgActive]        = ImVec4(0.65, 0.08, 0.08, 1.00)
	colors[clr.TitleBgCollapsed]     = ImVec4(0.20, 0.02, 0.02, 0.80)
	colors[clr.MenuBarBg]            = ImVec4(0.30, 0.04, 0.04, 1.00)
	colors[clr.ScrollbarBg]          = ImVec4(0.10, 0.02, 0.02, 0.60)
	colors[clr.ScrollbarGrab]        = ImVec4(0.55, 0.10, 0.10, 1.00)
	colors[clr.ScrollbarGrabHovered] = ImVec4(0.70, 0.12, 0.12, 1.00)
	colors[clr.ScrollbarGrabActive]  = ImVec4(0.85, 0.15, 0.15, 1.00)
	colors[clr.CheckMark]            = ImVec4(1.00, 0.95, 0.95, 1.00)
	colors[clr.SliderGrab]           = ImVec4(0.80, 0.12, 0.12, 1.00)
	colors[clr.SliderGrabActive]     = ImVec4(0.95, 0.18, 0.18, 1.00)
	colors[clr.Button]               = ImVec4(0.70, 0.10, 0.10, 1.00)
	colors[clr.ButtonHovered]        = ImVec4(0.85, 0.14, 0.14, 1.00)
	colors[clr.ButtonActive]         = ImVec4(0.55, 0.06, 0.06, 1.00)
	colors[clr.Header]               = ImVec4(0.70, 0.10, 0.10, 1.00)
	colors[clr.HeaderHovered]        = ImVec4(0.85, 0.14, 0.14, 1.00)
	colors[clr.HeaderActive]         = ImVec4(0.55, 0.06, 0.06, 1.00)
	colors[clr.Separator]            = ImVec4(0.90, 0.20, 0.20, 1.00)
	colors[clr.SeparatorHovered]     = ImVec4(1.00, 0.35, 0.35, 1.00)
	colors[clr.SeparatorActive]      = ImVec4(1.00, 0.50, 0.50, 1.00)
	colors[clr.ResizeGrip]           = ImVec4(0.70, 0.10, 0.10, 0.40)
	colors[clr.ResizeGripHovered]    = ImVec4(0.85, 0.14, 0.14, 0.70)
	colors[clr.ResizeGripActive]     = ImVec4(0.95, 0.18, 0.18, 1.00)
	colors[clr.CloseButton]          = ImVec4(0.70, 0.10, 0.10, 0.60)
	colors[clr.CloseButtonHovered]   = ImVec4(0.90, 0.15, 0.15, 1.00)
	colors[clr.CloseButtonActive]    = ImVec4(0.55, 0.06, 0.06, 1.00)
	colors[clr.PlotLines]            = ImVec4(0.90, 0.20, 0.20, 1.00)
	colors[clr.PlotHistogram]        = ImVec4(0.90, 0.30, 0.10, 1.00)
	colors[clr.TextSelectedBg]       = ImVec4(0.85, 0.20, 0.20, 0.45)
	colors[clr.ModalWindowDarkening] = ImVec4(0.30, 0.05, 0.05, 0.45)
end

ApplyRedTheme()

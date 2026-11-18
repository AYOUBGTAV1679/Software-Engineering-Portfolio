-- Author identity record: Salah Aleedn Wurdku
--------------------------------------------------------------
-- Zeno Skin Changer v3.0
-- by Sam Wilson
-- Command: /zskin   Hotkey: F4 by default, changeable in My Skin tab
--   [Skins]      browse & apply any skin (search included)
--   [My Skin]    save/clear YOUR permanent skin (persists between sessions)
--   [Names]      give a skin to a specific nickname the moment they
--                stream in - LOCAL ONLY, TEMPORARY (cleared when you
--                close the game, nothing is written to disk)
--   [Walk Style] apply a walk style to yourself OR one chosen player
--                ID only - never applied to everyone at once
-- Manual custom skins:  moonloader/zskin_skins.ini
-- Auto-import skins:    moonloader/skins/<FolderName>/*.dff (+ *.txd)
--                        just drop the folder in, no editing needed
--------------------------------------------------------------
script_version("3.0")
script_author("Sam Wilson")
--------------------------------------------------------------
-- FROM: _RM__PlayStable.lua lines 5-10
local imgui = require("imgui")
require("sampfuncs")

-- NowSeconds() measures process CPU time, which can stall while the game is idle.
-- Prefer the host's elapsed game timer and fall back to wall-clock seconds.
local function NowSeconds()
    if type(getGameTimer) == "function" then
        local ok, milliseconds = pcall(getGameTimer)
        if ok and type(milliseconds) == "number" then
            return milliseconds / 1000
        end
    end
    return os.time()
end
local windows_state = imgui.ImBool(false)
imgui.Process = false
--------------------------------------------------------------
-- FROM: _RM__PlayStable.lua lines 62-63
local _MenuPage = 1
local _Version  = "3.0"
--------------------------------------------------------------
-- FROM: _RM__PlayStable.lua line 74
local searchBuf = imgui.ImBuffer(64)
--------------------------------------------------------------

-- UI state for the Names and Walk Style tabs
local nameNickBuf   = imgui.ImBuffer(32)
local nameIdBuf      = imgui.ImInt(0)
local walkTargetBuf  = imgui.ImInt(0)
local applyToSelf    = imgui.ImBool(true)

local skinList    = {}
local filtered    = {}
local activeSkin  = -1
local statusText  = ""
local statusExp   = 0

-- PATTERN: coordinate_lookup_tool.lua cache table — stores granted skins per player
-- grantedSkins[sampId] = skinId
local grantedSkins = {}

--------------------------------------------------------------
-- PERSISTENT LOCAL DATA (all local-only, nothing sent to server)
--------------------------------------------------------------
local OWN_SKIN_FILE  = getGameDirectory() .. "/moonloader/zskin_own.ini"
local SKINS_DIR       = getGameDirectory() .. "/moonloader/skins"
local HOTKEY_FILE      = getGameDirectory() .. "/moonloader/zskin_hotkey.ini"

local hotKeyCode    = 0x73 -- F4 by default
local waitingForKey  = false
local rebindArmTime  = 0

local KEY_NAMES = {
    [0x70]="F1", [0x71]="F2", [0x72]="F3", [0x73]="F4", [0x74]="F5", [0x75]="F6",
    [0x76]="F7", [0x77]="F8", [0x78]="F9", [0x79]="F10", [0x7A]="F11", [0x7B]="F12",
    [0xC0]="`",  [0x14]="CapsLock", [0x2D]="Insert", [0x2E]="Delete",
    [0x24]="Home", [0x23]="End", [0x21]="PageUp", [0x22]="PageDown",
}

local function KeyName(code)
    return KEY_NAMES[code] or ("Key(0x%X)"):format(code)
end

local function SaveHotkey()
    local f = io.open(HOTKEY_FILE, "w")
    if f then
        f:write(tostring(hotKeyCode) .. "\n")
        f:close()
    end
end

local function LoadHotkey()
    local f = io.open(HOTKEY_FILE, "r")
    if not f then return end
    local line = f:read("*l")
    f:close()
    local code = tonumber(line)
    if code then hotKeyCode = code end
end

local mySkin    = nil -- your own permanent skin id (nil = none saved)
local nameSkins = {}  -- [nickname_lower] = skinId, applied on stream-in

--------------------------------------------------------------
-- FROM: _RM__PlayStable.lua line 116  (Say function)
function Say(msg)
    sampAddChatMessage("{4499FF}[ZSkin]{FFFFFF} " .. tostring(msg), -1)
end

--------------------------------------------------------------
-- FROM: _RM__PlayStable.lua lines 488-493  (CenterText)
function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc  = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
end

--------------------------------------------------------------
-- SKIN NAMES TABLE
-- FROM: skin_selector.cpp lines 75-920
-- each entry: [id] = "NAME"
--------------------------------------------------------------
local SKIN_NAMES = {
    [7]   = "MALE01",   [8]   = "(NONE)",   [9]   = "BFORI",
    [10]  = "BFOST",    [11]  = "VBFYCR",   [12]  = "BFYRI",
    [13]  = "BFYST",    [14]  = "BMORI",    [15]  = "BMOST",
    [16]  = "BMYAP",    [17]  = "BMYBU",    [18]  = "BMYBE",
    [19]  = "BMYDJ",    [20]  = "BMYRI",    [21]  = "BMYCR",
    [22]  = "BMYST",    [23]  = "WMYBMX",   [24]  = "WBDYG1",
    [25]  = "WBDYG2",   [26]  = "WMYBP",    [27]  = "WMYCON",
    [28]  = "BMYDRUG",  [29]  = "WMYDRUG",  [30]  = "HMYDRUG",
    [31]  = "DWFOLC",   [32]  = "DWMOLC1",  [33]  = "DWMOLC2",
    [34]  = "DWMYLC1",  [35]  = "HMOGAR",   [36]  = "WMYGOL1",
    [37]  = "WMYGOL2",  [38]  = "HFORI",    [39]  = "HFOST",
    [40]  = "HFYRI",    [41]  = "HFYST",    [43]  = "HMORI",
    [44]  = "HMOST",    [45]  = "HMYBE",    [46]  = "HMYRI",
    [47]  = "HMYCR",    [48]  = "HMYST",    [49]  = "OMOKUNG",
    [50]  = "WMYMECH",  [51]  = "BMYMOUN",  [52]  = "WMYMOUN",
    [53]  = "OFORI",    [54]  = "OFOST",    [55]  = "OFYRI",
    [56]  = "OFYST",    [57]  = "OMORI",    [58]  = "OMOST",
    [59]  = "OMYRI",    [60]  = "OMYST",    [61]  = "WMYPLT",
    [62]  = "WMOPJ",    [63]  = "BFYPRO",   [64]  = "HFYPRO",
    [66]  = "BMYPOL1",  [67]  = "BMYPOL2",  [68]  = "WMOPREA",
    [69]  = "SBFYST",   [70]  = "WMOSCI",   [71]  = "WMYSGRD",
    [72]  = "SWMYHP1",  [73]  = "SWMYHP2",  [75]  = "SWFOPRO",
    [76]  = "WFYSTEW",  [77]  = "SWMOTR1",  [78]  = "WMOTR1",
    [79]  = "BMOTR1",   [80]  = "VBMYBOX",  [81]  = "VWMYBOX",
    [86]  = "WFYBE",    [87]  = "WFORI",    [88]  = "WFOST",
    [89]  = "WFYJG",    [90]  = "WFYRI",    [91]  = "WFYRO",
    [92]  = "WFYST",    [93]  = "WMORI",    [94]  = "WMOST",
    [95]  = "WMORI",    [96]  = "WMYJG",    [97]  = "WMYLG",
    [98]  = "WMYRI",    [99]  = "WMYRO",    [100] = "WMYCR",
    [101] = "WMYST",    [102] = "BALLAS1",  [103] = "BALLAS2",
    [104] = "BALLAS3",  [105] = "FAM1",     [106] = "FAM2",
    [107] = "FAM3",     [108] = "LSV1",     [109] = "LSV2",
    [110] = "LSV3",     [111] = "MAFFA",    [112] = "MAFFB",
    [113] = "MAFBOSS",  [114] = "VLA1",     [115] = "VLA2",
    [116] = "VLA3",     [117] = "TRIADA",   [118] = "TRIADB",
    [120] = "TRIBOSS",  [121] = "DNB1",     [122] = "DNB2",
    [123] = "DNB3",     [124] = "VMAFF1",   [125] = "VMAFF2",
    [126] = "VMAFF3",   [127] = "VMAFF4",   [128] = "DNMYLC",
    [129] = "DNFOLC1",  [130] = "DNFOLC2",  [131] = "DNFYLC",
    [132] = "DNMOLC1",  [133] = "DNMOLC2",  [134] = "SBMOTR2",
    [135] = "SWMOTR2",  [136] = "SBMYTR3",  [137] = "SWMOTR3",
    [138] = "WFYBE",    [139] = "BFYBE",    [140] = "HFYBE",
    [141] = "SOFYBU",   [142] = "SBMYST",   [143] = "SBMYCR",
    [144] = "BMYCG",    [145] = "WFYCRK",   [146] = "HMYCM",
    [147] = "WMYBU",    [148] = "BFYBU",    [150] = "WFYBU",
    [151] = "DWFYLC1",  [152] = "WFYPRO",   [153] = "WMYCONB",
    [154] = "WMYBE",    [155] = "WMYPIZZ",  [156] = "BMOBAR",
    [157] = "CWFYHB",   [158] = "CWMOFR",   [159] = "CWMOHB1",
    [160] = "CWMOHB2",  [161] = "CWMYFR",   [162] = "CWMYHB1",
    [163] = "BMYBOUN",  [164] = "WMYBOUN",  [165] = "WMOMIB",
    [166] = "BMYMIB",   [167] = "WMYBELL",  [168] = "BMOCHIL",
    [169] = "SOFYRI",   [170] = "SOMYST",   [171] = "VWMYBJD",
    [172] = "VWFYCRP",  [173] = "SFR1",     [174] = "SFR2",
    [175] = "SFR3",     [176] = "BMYBAR",   [177] = "WMYBAR",
    [178] = "WFYSEX",   [179] = "WMYAMMO",  [180] = "BMYTATT",
    [181] = "VWMYCR",   [182] = "VBMOCD",   [183] = "VBMYCR",
    [184] = "VHMYCR",   [185] = "SBMYRI",   [186] = "SOMYRI",
    [187] = "SOMYBU",   [188] = "SWMYST",   [189] = "WMYVA",
    [190] = "COPGRL3",  [191] = "GUNGRL3",  [192] = "MECGRL3",
    [193] = "NURGRL3",  [194] = "CROGRL3",  [195] = "GANGRL3",
    [196] = "CWFOFR",   [197] = "CWFOHB",   [198] = "CWFYFR1",
    [199] = "CWFYFR2",  [200] = "CWMYHB2",  [201] = "DWFYLC2",
    [202] = "DWMYLC2",  [203] = "OMYKARA",  [204] = "WMYKARA",
    [205] = "WFYBURG",  [206] = "VWMYCD",   [207] = "VHFYPRO",
    [209] = "OMONOOD",  [210] = "OMOBOAT",  [221] = "SBMORI",
    [222] = "SBMOST",   [223] = "SHMYCR",   [224] = "SOFORI",
    [225] = "SOFOST",   [226] = "SOFYST",   [227] = "SOMOBU",
    [228] = "SOMORI",   [229] = "SOMOST",   [230] = "SWMOTR5",
    [231] = "SWFORI",   [232] = "SWFOST",   [233] = "SWFYST",
    [234] = "SWMOCD",   [235] = "SWMORI",   [236] = "SWMOST",
    [237] = "SHFYPRO",  [238] = "SBFYPRO",  [239] = "SWMOTR4",
    [240] = "SWMYRI",   [241] = "SMYST",    [242] = "SMYST2",
    [243] = "SFYPRO",   [244] = "VBFYST2",  [245] = "VBFYPRO",
    [246] = "VHFYST3",  [247] = "BIKERA",   [248] = "BIKERB",
    [249] = "BMYPIMP",  [250] = "SWMYCR",   [251] = "WFYLG",
    [252] = "WMYVA2",   [253] = "BMOSEC",   [254] = "BIKDRUG",
    [255] = "WMYCH",    [256] = "SBFYSTR",  [257] = "SWFYSTR",
    [258] = "HECK1",    [259] = "HECK2",    [260] = "BMYCON",
    [261] = "WMYCD1",   [262] = "BMOCD",    [263] = "VWFYWA2",
    [264] = "WMOICE",   [274] = "LAEMT1",   [275] = "LVEMT1",
    [276] = "SFEMT1",   [277] = "LAFD1",    [278] = "LVFD1",
    [279] = "SFFD1",    [280] = "LAPD1",    [281] = "SFPD1",
    [282] = "LVPD1",    [283] = "CSHER",    [284] = "LAPDM1",
    [285] = "SWAT",     [286] = "FBI",      [287] = "ARMY",
    [288] = "DSHER",
}

-- Custom skins DFF/TXD paths (manual entries only - anything placed
-- as a folder under moonloader/skins/ is picked up automatically by
-- ScanAutoSkins instead, so it doesn't need an entry here)
local CUSTOM_SKINS = {
}

-- Do not guess a custom runtime model ID. ID 7 is already the built-in
-- MALE01 model in SKIN_NAMES; reusing it would replace a standard model.
-- Enable DFF imports only after a host extension and a verified free slot
-- have both been identified and tested.
local CUSTOM_SKIN_SLOT = nil

local function GetRuntimeSkinModelId(skinId)
    if CUSTOM_SKINS[skinId] and type(CUSTOM_SKIN_SLOT) == "number" then
        return CUSTOM_SKIN_SLOT
    end
    return skinId
end

--------------------------------------------------------------
-- FILE: read extra skins from moonloader/zskin_skins.ini
-- FROM: _RM__PlayStable.lua LoadSave pattern lines 556-563
--------------------------------------------------------------
local function LoadExtraSkins()
    local path = getGameDirectory() .. "/moonloader/zskin_skins.ini"

    -- First run: create the file WITH the required format so it
    -- actually works the first time someone edits it.
    if not doesFileExist(path) then
        local nf = io.open(path, "w")
        if nf then
            nf:write("; Zeno Skin Changer - manual custom skins\n")
            nf:write("; Format:  id = Name|path/to/model.dff|path/to/texture.txd\n")
            nf:write("; The [Skins] line below is REQUIRED - nothing loads without it.\n")
            nf:write("; Paths are relative to your GTA SA folder. TXD is optional.\n")
            nf:write("; Example (remove the leading ; to enable):\n")
            nf:write("; 950=My Custom Skin|moonloader/skins/myskin.dff|moonloader/skins/myskin.txd\n")
            nf:write("[Skins]\n")
            nf:close()
        end
        return
    end

    local file = io.open(path, "r")
    if not file then return end

    local inSection = false
    local loaded = 0
    for line in file:lines() do
        if line:match("^%s*%[Skins%]") then
            inSection = true
        elseif line:match("^%s*%[") then
            inSection = false
        elseif inSection
            and not line:match("^%s*;")
            and not line:match("^%s*$")
        then
            local id, rest = line:match("^%s*(%d+)%s*=%s*(.-)%s*$")
            if id and rest and rest ~= "" then
                local parts = {}
                for p in (rest .. "|"):gmatch("([^|]*)|") do
                    table.insert(parts, p:match("^%s*(.-)%s*$"))
                end
                local numId = tonumber(id)
                SKIN_NAMES[numId] = parts[1]
                if parts[2] and parts[2] ~= "" then
                    CUSTOM_SKINS[numId] = {
                        dff = parts[2],
                        txd = (parts[3] and parts[3] ~= "") and parts[3] or nil,
                    }
                end
                loaded = loaded + 1
            end
        end
    end
    file:close()

    -- Visible feedback either way, instead of failing silently.
    if loaded == 0 then
        Say("{FFAA00}zskin_skins.ini has no valid entries - make sure it has a " ..
            "[Skins] line, then rows like: 950=Name|path.dff|path.txd")
    else
        Say("Loaded " .. loaded .. " custom skin(s) from zskin_skins.ini.")
    end
end

--------------------------------------------------------------
-- OWN PERMANENT SKIN  (saved locally, auto-applied every spawn)
--------------------------------------------------------------
local function SaveOwnSkin(id)
    mySkin = id
    local f = io.open(OWN_SKIN_FILE, "w")
    if f then
        f:write(tostring(id) .. "\n")
        f:close()
    end
end

local function ClearOwnSkin()
    mySkin = nil
    os.remove(OWN_SKIN_FILE)
end

local function LoadOwnSkin()
    local f = io.open(OWN_SKIN_FILE, "r")
    if not f then return end
    local line = f:read("*l")
    f:close()
    local id = tonumber(line)
    if id then mySkin = id end
end

--------------------------------------------------------------
-- TEMPORARY NAME-BASED SKINS (LOCAL ONLY, SESSION ONLY)
-- Nothing here is written to disk on purpose - the whole point is
-- that this list resets itself the moment you close the game.
-- nameSkins[nickname_lower] = skinId
--------------------------------------------------------------
local function AddNameSkin(nick, id)
    nameSkins[nick:lower()] = id
end

local function RemoveNameSkin(nick)
    nameSkins[nick:lower()] = nil
end

--------------------------------------------------------------
-- AUTO-IMPORT SKINS FROM FOLDERS
-- Drop a folder into moonloader/skins/ containing a .dff (and
-- optionally a .txd) and it is picked up automatically — no ini
-- editing needed. Example: moonloader/skins/hunk/hunk.dff
--------------------------------------------------------------
local AUTO_ID_BASE = 900 -- auto-imported skins are numbered from here

-- Uses findFirstFile/findNextFile (CLEO-style, no external process) -
-- NOT io.popen, which spawns a real cmd.exe console window and can
-- get the game killed by anti-cheat for launching an external process.
local function listEntries(pattern)
    local items = {}
    local ok, handle, name = pcall(findFirstFile, pattern)
    if ok and handle then
        while name do
            if name ~= "." and name ~= ".." then
                table.insert(items, name)
            end
            name = findNextFile(handle)
        end
        findClose(handle)
    end
    return items
end

local function stripExt(name, ext)
    local lower     = name:lower()
    local extLower  = "." .. ext:lower()
    if lower:sub(-#extLower) == extLower then
        return name:sub(1, #name - #extLower)
    end
    return name
end

local function ScanAutoSkins()
    if not doesDirectoryExist(SKINS_DIR) then
        createDirectory(SKINS_DIR)
        return 0
    end

    local entries = listEntries(SKINS_DIR .. "\\*")
    local nextId  = AUTO_ID_BASE
    local added   = 0

    for _, folder in ipairs(entries) do
        local folderPath = SKINS_DIR .. "\\" .. folder

        if doesDirectoryExist(folderPath) then
            local dffList = listEntries(folderPath .. "\\*.dff")
            local txdList = listEntries(folderPath .. "\\*.txd")
            local dff = dffList[1] and (folderPath .. "\\" .. dffList[1]) or nil
            local txd = txdList[1] and (folderPath .. "\\" .. txdList[1]) or nil

            if dff then
                -- skip folders already imported in this or a previous run
                local alreadyImported = false
                for _, entry in pairs(CUSTOM_SKINS) do
                    if entry.autoName == folder then alreadyImported = true break end
                end

                if not alreadyImported then
                    while SKIN_NAMES[nextId] do nextId = nextId + 1 end
                    SKIN_NAMES[nextId] = folder:upper()
                    CUSTOM_SKINS[nextId] = {
                        dff      = dff,
                        txd      = txd,
                        fullPath = true, -- these are already absolute paths
                        autoName = folder,
                    }
                    nextId = nextId + 1
                    added  = added + 1
                end
            end
        end
    end

    -- Also pick up loose .dff/.txd files sitting directly in
    -- moonloader/skins/ (no subfolder needed) - pairs "name.dff"
    -- with "name.txd" by matching filename.
    local looseDff = listEntries(SKINS_DIR .. "\\*.dff")
    for _, dffName in ipairs(looseDff) do
        local baseName = stripExt(dffName, "dff")
        local dffPath  = SKINS_DIR .. "\\" .. dffName

        local alreadyImported = false
        for _, entry in pairs(CUSTOM_SKINS) do
            if entry.autoName == baseName then alreadyImported = true break end
        end

        if not alreadyImported then
            local txdPath = nil
            local txdMatches = listEntries(SKINS_DIR .. "\\" .. baseName .. ".txd")
            if txdMatches[1] then
                txdPath = SKINS_DIR .. "\\" .. txdMatches[1]
            end

            while SKIN_NAMES[nextId] do nextId = nextId + 1 end
            SKIN_NAMES[nextId] = baseName:upper()
            CUSTOM_SKINS[nextId] = {
                dff      = dffPath,
                txd      = txdPath,
                fullPath = true,
                autoName = baseName,
            }
            nextId = nextId + 1
            added  = added + 1
        end
    end

    return added
end

--------------------------------------------------------------
-- Build skinList from SKIN_NAMES table
--------------------------------------------------------------
local function BuildSkinList()
    skinList = {}
    for id, name in pairs(SKIN_NAMES) do
        if name ~= "(NONE)" then
            table.insert(skinList, { id = id, name = name })
        end
    end
    table.sort(skinList, function(a, b) return a.id < b.id end)
end

local function UpdateFilter()
    local q = searchBuf.v:lower()
    filtered = {}
    for _, s in ipairs(skinList) do
        if q == ""
        or s.name:lower():find(q, 1, true)
        or tostring(s.id):find(q, 1, true) then
            table.insert(filtered, s)
        end
    end
end

--------------------------------------------------------------
-- APPLY SKIN
-- FROM: skin_selector.cpp lines 1210-1223
--   Model.Load(26@)           -> requestModel
--   038B load_requested_models -> loadAllModelsNow
--   write_memory 0x609A4E     -> writeMemory (Wesser walk fix)
--   write_memory 0x609A52     -> writeMemory
--   09C7 change_player 0      -> setPlayerModel
--   Player.Build(0)           -> buildPlayerModel
--   0687 clear_actor task     -> clearCharTasksImmediately
--------------------------------------------------------------
-- Walk style table
-- FROM: ped.ifp - extracted real anim names
-- IFP name = "ped" (internal name inside ped.ifp)
local WALK_STYLES = {
    [0]  = { ifp = "ped",  anim = "WALK_player",      label = "Default"    },
    [1]  = { ifp = "ped",  anim = "WALK_civi",        label = "Civilian"   },
    [2]  = { ifp = "ped",  anim = "WALK_shuffle",     label = "Shuffle"    },
    [3]  = { ifp = "ped",  anim = "WALK_old",         label = "Old Man"    },
    [4]  = { ifp = "ped",  anim = "WALK_gang1",       label = "Gang 1"     },
    [5]  = { ifp = "ped",  anim = "WALK_gang2",       label = "Gang 2"     },
    [6]  = { ifp = "ped",  anim = "WALK_fatold",      label = "Old Fat"    },
    [7]  = { ifp = "ped",  anim = "WALK_fat",         label = "Fat"        },
    [8]  = { ifp = "ped",  anim = "WALK_drunk",       label = "Drunk"      },
    [9]  = { ifp = "ped",  anim = "WALK_armed",       label = "Armed"      },
    [10] = { ifp = "ped",  anim = "WOMAN_walknorm",   label = "Woman"      },
    [11] = { ifp = "ped",  anim = "WOMAN_walkshop",   label = "Shopping"   },
    [12] = { ifp = "ped",  anim = "WOMAN_walkbusy",   label = "Busy Woman" },
    [13] = { ifp = "ped",  anim = "WOMAN_walksexy",   label = "Sexy"       },
    [14] = { ifp = "ped",  anim = "WOMAN_walkpro",    label = "Pro Woman"  },
    [15] = { ifp = "ped",  anim = "WOMAN_walkold",    label = "Old Woman"  },
    [16] = { ifp = "ped",  anim = "WOMAN_walkfatold", label = "Fat Woman"  },
    [17] = { ifp = "ped",  anim = "Walk_Wuzi",        label = "Wuzi"       },
    [18] = { ifp = "ped",  anim = "Player_Sneak",     label = "Sneak"      },
    [19] = { ifp = "ped",  anim = "WALK_rocket",      label = "Rocket"     },
    [20] = { ifp = "ped",  anim = "WALK_csaw",        label = "Chainsaw"   },
}

-- Walk grants: [sampId] = styleId  (0 = self)
local walkGrants = {}

-- Load our custom ped.ifp once at startup
-- Place ped.ifp in: moonloader/skins/ped.ifp
-- The configured walk styles use the built-in "ped" animation block.
-- requestAnimation expects an animation-block name, not a filesystem path.
local PED_ANIMATION_BLOCK = "ped"
local pedAnimationRequested = false
local pedAnimationWarningShown = false

local function loadPedIfp()
    if not pedAnimationRequested then
        local ok, err = pcall(requestAnimation, PED_ANIMATION_BLOCK)
        if not ok then
            if not pedAnimationWarningShown then
                Say("{FF4444}Could not request animation block 'ped': " .. tostring(err))
                pedAnimationWarningShown = true
            end
            return false
        end
        pedAnimationRequested = true
    end

    local ok, loaded = pcall(hasAnimationLoaded, PED_ANIMATION_BLOCK)
    if not ok then
        pedAnimationRequested = false
        if not pedAnimationWarningShown then
            Say("{FF4444}Could not check animation block 'ped': " .. tostring(loaded))
            pedAnimationWarningShown = true
        end
        return false
    end

    if not loaded then return false end
    pedAnimationWarningShown = false
    return true
end

-- Apply only after the requested animation block is ready. The main loop
-- retries saved walk grants, so this function does not need to block/yield.
local function applyWalkStyle(ped, styleId)
    local ws = WALK_STYLES[styleId]
    if not ws then return false end
    if not loadPedIfp() then return false end

    -- Avoid restarting the same walk animation on every periodic refresh.
    local playingOk, alreadyPlaying = pcall(isCharPlayingAnim, ped, ws.anim)
    if playingOk and alreadyPlaying then return true end

    -- Standard MoonLoader task signature:
    -- taskPlayAnim(ped, animation, IFP, speed, loop, lockX, lockY, lockF, time)
    local ok, err = pcall(taskPlayAnim, ped, ws.anim, ws.ifp,
        1.2, true, false, false, false, -1)
    if not ok then
        if not pedAnimationWarningShown then
            Say("{FF4444}Could not apply walk animation: " .. tostring(err))
            pedAnimationWarningShown = true
        end
        return false
    end
    return true
end

-- Pending skin application state, processed non-blocking in the main
-- loop below (see ProcessPendingSkin). We do NOT call the blocking
-- loadAllModelsNow() from here - if a custom DFF/TXD is corrupt or
-- incompatible, that call can wait forever and freeze the whole game
-- with no way back except force-closing it.
local pendingSkin      = nil -- { id = ..., realId = ..., entry = ... }
local pendingLoadStart = nil

local function ApplySkin(entry)
    local id = entry.id
    local realId = id -- the skin's real/logical id - must survive even
                       -- though `id` below gets overwritten with the
                       -- internal loading slot for custom skins

    -- Load custom DFF/TXD if this is a custom skin
    if CUSTOM_SKINS[id] then
        local c    = CUSTOM_SKINS[id]
        -- The host API and a safe free model slot are both required. Do not
        -- reuse a built-in ID; 7 is MALE01 in the built-in catalogue.
        if c.dff and type(CUSTOM_SKIN_SLOT) ~= "number" then
            Say("{FF4444}Custom DFF loading is disabled: no verified free runtime model slot is configured.")
            return
        end
        if c.dff and type(loadModelInfo) ~= "function" then
            Say("{FF4444}Custom DFF loading is unavailable: loadModelInfo() is not provided by this host.")
            return
        end
        if c.txd and type(loadTextureDictionary) ~= "function" then
            Say("{FF4444}TXD loading is unavailable: loadTextureDictionary() is not provided by this host.")
            return
        end

        -- Use one internal slot for imported custom DFF assets.
        local slot = CUSTOM_SKIN_SLOT

        if c.txd then
            local fullTxd = c.fullPath and c.txd or (getGameDirectory() .. "/" .. c.txd)
            -- FIX: "r" is TEXT mode. On Windows this does CRLF translation and,
            -- critically, treats byte 0x1A (Ctrl+Z) as end-of-file - a byte value
            -- any binary .txd file is quite likely to contain somewhere in its
            -- data. That silently truncates f:seek("end") for a perfectly valid
            -- file, which the size check below then wrongly reports as
            -- "corrupt/truncated". Binary assets must always be opened "rb".
            local f = io.open(fullTxd, "rb")
            if f then
                local size = f:seek("end")
                f:close()
                if not size or size < 64 then
                    Say("{FF4444}TXD looks corrupt/truncated (" .. tostring(size or 0) ..
                        " bytes) - refusing to load it: " .. c.txd)
                    return
                end
                -- Load the TXD using the documented MoonLoader opcode name.
                local loadOk, loaded = pcall(loadTextureDictionary, fullTxd)
                if not loadOk or loaded == false then
                    Say("{FF4444}TXD loading failed: " .. tostring(loaded or c.txd))
                    return
                end
                Say("TXD loaded: " .. c.txd)
            else
                Say("TXD not found: " .. c.txd)
                return
            end
        end

        if c.dff then
            local fullDff = c.fullPath and c.dff or (getGameDirectory() .. "/" .. c.dff)
            -- FIX: same text-mode/binary-mode bug as the TXD check above - .dff
            -- model files are binary and must be opened "rb", not "r".
            local f = io.open(fullDff, "rb")
            if f then
                local size = f:seek("end")
                f:close()
                if not size or size < 64 then
                    Say("{FF4444}DFF looks corrupt/truncated (" .. tostring(size or 0) ..
                        " bytes) - refusing to load it: " .. c.dff)
                    return
                end
                -- Custom DFF loading requires the host extension checked above.
                local loadOk, loaded = pcall(loadModelInfo, slot, fullDff)
                if not loadOk or loaded == false then
                    Say("{FF4444}DFF loading failed: " .. tostring(loaded or c.dff))
                    return
                end
                Say("DFF loaded into slot " .. slot)
            else
                Say("DFF not found: " .. c.dff)
                return
            end
        end

        -- Use slot 7 as the skin ID
        id = slot
    end

    -- Model.Load(26@)  line 1210
    requestModel(id)

    -- Instead of the blocking loadAllModelsNow(), hand off to the
    -- main loop to finish this once the model is actually ready (or
    -- give up after a timeout instead of hanging forever).
    pendingSkin      = { id = id, realId = realId, entry = entry }
    pendingLoadStart = NowSeconds()
    Say("Loading skin: " .. entry.name .. " ...")
end

-- Called every tick from the main loop. Finishes applying a pending
-- skin once its model has actually finished loading, or gives up
-- cleanly after PENDING_SKIN_TIMEOUT seconds instead of freezing.
local PENDING_SKIN_TIMEOUT = 8 -- seconds

local function ProcessPendingSkin()
    if not pendingSkin then return end

    local ok, loaded = pcall(hasModelLoaded, pendingSkin.id)

    -- FIX: a pcall FAILURE (ok == false, e.g. hasModelLoaded missing on this
    -- MoonLoader build, or a bad argument) used to fall straight through to
    -- the generic 8-second timeout, which then always blamed "the DFF/TXD
    -- file may be corrupt" - even for a vanilla skin with no file involved at
    -- all, and even though the real cause (the native call erroring every
    -- single tick) was known immediately. Surface it right away instead of
    -- waiting out the full timeout to report the wrong diagnosis.
    if not ok then
        local entry = pendingSkin.entry
        pendingSkin = nil
        Say("{FF4444}Skin apply failed: hasModelLoaded() errored (" ..
            tostring(loaded) .. "). This looks like a MoonLoader/game-version " ..
            "issue, not a problem with: " .. entry.name)
        return
    end

    if ok and loaded then
        local id, realId, entry = pendingSkin.id, pendingSkin.realId, pendingSkin.entry
        pendingSkin = nil

        -- walk_hack_thanks_to_Wesser  lines 1216-1220
        writeMemory(0x609A4E, 4, 0x90909090, true)
        writeMemory(0x609A52, 2, 0x9090,     true)

        -- 09C7: change_player 0 model_to 26@  line 1221
        setPlayerModel(0, id)

        -- Player.Build(0)  line 1222
        buildPlayerModel(0)

        -- 0687: clear_actor $PLAYER_ACTOR task  line 1223
        clearCharTasksImmediately(PLAYER_PED)

        activeSkin = realId
        statusText = "Applied: " .. entry.name .. " (ID " .. realId .. ")"
        statusExp  = NowSeconds() + 3
        Say("Skin applied: {FFFF00}" .. entry.name .. " {FFFFFF}ID=" .. realId)

    elseif NowSeconds() - pendingLoadStart > PENDING_SKIN_TIMEOUT then
        local entry = pendingSkin.entry
        pendingSkin = nil
        Say("{FF4444}Skin failed to load (timed out after " .. PENDING_SKIN_TIMEOUT ..
            "s): " .. entry.name .. " - the DFF/TXD file may be corrupt or incompatible.")
    end
end

--------------------------------------------------------------
-- NOTE: name-based auto-apply and own-skin auto-reapply are now
-- handled by polling inside the main loop below (search for
-- "LOCAL-ONLY PERMANENT SKIN POLLING"), using ONLY natives that
-- already exist elsewhere in this exact file (sampGetCharHandleBySampPlayerId,
-- doesCharExist). No external library required.
--------------------------------------------------------------

--------------------------------------------------------------
-- RED STYLE
-- FROM: _RM__PlayStable.lua ApplyCustomOrangeStyle lines 575-636
--       and ApplyCustomMagentaStyle lines 638-703
--       Same structure, red colors instead
--------------------------------------------------------------
function ApplyRedStyle()
    -- FROM: PlayStable line 576
    imgui.SwitchContext()
    local style  = imgui.GetStyle()
    local colors = style.Colors
    local clr    = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2

    -- FROM: PlayStable lines 583-591
    style.WindowRounding      = 6.0
    style.WindowTitleAlign    = ImVec2(0.5, 0.5)
    style.ChildWindowRounding = 5.0
    style.FrameRounding       = 4.0
    style.ItemSpacing         = ImVec2(5.0, 4.0)
    style.ItemInnerSpacing    = ImVec2(4.0, 4.0)
    style.IndentSpacing       = 21.0
    style.ScrollbarSize       = 10.0
    style.ScrollbarRounding   = 4.0
    style.GrabMinSize         = 8.0
    style.GrabRounding        = 4.0
    style.ButtonTextAlign     = ImVec2(0.5, 0.5)

    -- Red aggressive colors
    -- FROM: same structure as PlayStable lines 593-635
    colors[clr.Text]                 = ImVec4(1.00, 0.95, 0.95, 1.00)
    colors[clr.TextDisabled]         = ImVec4(0.68, 0.40, 0.40, 1.00)
    colors[clr.WindowBg]             = ImVec4(0.13, 0.03, 0.03, 0.97)
    colors[clr.ChildWindowBg]        = ImVec4(0.18, 0.04, 0.04, 1.00)
    colors[clr.PopupBg]              = ImVec4(0.14, 0.04, 0.04, 0.97)
    colors[clr.Border]               = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.BorderShadow]         = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.FrameBg]              = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.FrameBgHovered]       = ImVec4(1.00, 0.16, 0.14, 1.00)
    colors[clr.FrameBgActive]        = ImVec4(1.00, 0.20, 0.16, 1.00)
    colors[clr.TitleBg]              = ImVec4(0.28, 0.04, 0.03, 0.95)
    colors[clr.TitleBgActive]        = ImVec4(0.62, 0.06, 0.05, 1.00)
    colors[clr.TitleBgCollapsed]     = ImVec4(0.30, 0.04, 0.03, 0.80)
    colors[clr.MenuBarBg]            = ImVec4(0.30, 0.05, 0.05, 1.00)
    colors[clr.ScrollbarBg]          = ImVec4(0.25, 0.05, 0.05, 1.00)
    colors[clr.ScrollbarGrab]        = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.ScrollbarGrabHovered] = ImVec4(1.00, 0.16, 0.14, 1.00)
    colors[clr.ScrollbarGrabActive]  = ImVec4(1.00, 0.22, 0.18, 1.00)
    colors[clr.ComboBg]              = ImVec4(0.55, 0.08, 0.08, 1.00)
    colors[clr.CheckMark]            = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[clr.SliderGrab]           = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.SliderGrabActive]     = ImVec4(1.00, 0.20, 0.16, 1.00)
    colors[clr.Button]               = ImVec4(0.70, 0.08, 0.08, 1.00)
    colors[clr.ButtonHovered]        = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.ButtonActive]         = ImVec4(0.55, 0.05, 0.05, 1.00)
    colors[clr.Header]               = ImVec4(0.70, 0.08, 0.08, 1.00)
    colors[clr.HeaderHovered]        = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.HeaderActive]         = ImVec4(0.55, 0.05, 0.05, 1.00)
    colors[clr.Separator]            = ImVec4(1.00, 0.20, 0.16, 1.00)
    colors[clr.SeparatorHovered]     = ImVec4(1.00, 0.35, 0.30, 1.00)
    colors[clr.SeparatorActive]      = ImVec4(1.00, 0.50, 0.45, 1.00)
    colors[clr.ResizeGrip]           = ImVec4(0.70, 0.08, 0.08, 1.00)
    colors[clr.ResizeGripHovered]    = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.ResizeGripActive]     = ImVec4(0.55, 0.05, 0.05, 1.00)
    colors[clr.CloseButton]          = ImVec4(0.70, 0.08, 0.08, 1.00)
    colors[clr.CloseButtonHovered]   = ImVec4(1.00, 0.20, 0.16, 1.00)
    colors[clr.CloseButtonActive]    = ImVec4(0.55, 0.05, 0.05, 1.00)
    colors[clr.PlotLines]            = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[clr.PlotLinesHovered]     = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.PlotHistogram]        = ImVec4(1.00, 0.20, 0.16, 1.00)
    colors[clr.PlotHistogramHovered] = ImVec4(1.00, 0.35, 0.30, 1.00)
    colors[clr.TextSelectedBg]       = ImVec4(0.90, 0.12, 0.10, 1.00)
    colors[clr.ModalWindowDarkening] = ImVec4(0.20, 0.00, 0.00, 0.70)
end

--------------------------------------------------------------
-- MAIN
-- FROM: _RM__PlayStable.lua lines 317-384
--------------------------------------------------------------
function main()
    -- FROM: PlayStable line 318
    repeat wait(0) until isSampAvailable()

    -- FROM: PlayStable lines 321-326
    if not doesDirectoryExist(getGameDirectory() .. "/moonloader/skins") then
        createDirectory(getGameDirectory() .. "/moonloader/skins")
    end

    -- Load extra skins from file if exists
    LoadExtraSkins()

    -- Auto-import any skin folders dropped into moonloader/skins/
    local autoAdded = ScanAutoSkins()

    -- Load persistent local data (your own permanent skin only —
    -- the per-name list is intentionally session-only, see below)
    LoadOwnSkin()
    LoadHotkey()

    -- Build skin list from table
    BuildSkinList()
    UpdateFilter()

    Say("Loaded! v" .. _Version .. " | /zskin | " .. KeyName(hotKeyCode) .. " | by Sam Wilson")
    Say("Total skins: " .. #skinList .. " (auto-imported: " .. autoAdded .. ")")

    -- Apply your saved permanent skin right away, if you have one
    if mySkin then
        ApplySkin({ id = mySkin, name = SKIN_NAMES[mySkin] or ("ID " .. mySkin) })
        Say("Permanent skin restored (ID " .. mySkin .. ")")
    end

    -- FROM: PlayStable lines 333-336
    sampRegisterChatCommand("zskin", function()
        windows_state.v = not windows_state.v
        imgui.Process   = windows_state.v
        if windows_state.v then
            searchBuf.v = ""
            UpdateFilter()
        end
    end)

    -- FROM: skinc.lua set_player_skin using RakNet RPC 153
    local function set_player_skin(id, skin)
        local BS = raknetNewBitStream()
        raknetBitStreamWriteInt32(BS, id)
        raknetBitStreamWriteInt32(BS, skin)
        raknetEmulRpcReceiveBitStream(153, BS)
        raknetDeleteBitStream(BS)
    end

    -- /sskin <playerID> <skinID>
    sampRegisterChatCommand("sskin", function(args)
        local pid, sid = args:match("^%s*(%d+)%s+(%d+)%s*$")
        if not pid or not sid then
            Say("Usage: /sskin <playerID> <skinID>")
            return
        end
        local playerId = tonumber(pid)
        local skinId   = tonumber(sid)
        grantedSkins[playerId] = skinId
        -- FROM: skinc.lua set_player_skin RPC 153
        set_player_skin(playerId, skinId)
        Say("Skin " .. (SKIN_NAMES[skinId] or sid) ..
            " applied to player " .. playerId)
    end)

    -- /sskin0 <playerID> remove grant
    sampRegisterChatCommand("sskin0", function(args)
        local pid = tonumber(args)
        if not pid then Say("Usage: /sskin0 <playerID>") return end
        grantedSkins[pid] = nil
        Say("Removed grant for player " .. pid)
    end)

    -- /zskinsave  save your CURRENT skin as your permanent skin
    -- (auto re-applied on every spawn/reconnect, local only)
    sampRegisterChatCommand("zskinsave", function()
        if activeSkin < 0 then
            Say("Apply a skin first (open /zskin), then use /zskinsave.")
            return
        end
        SaveOwnSkin(activeSkin)
        Say("Saved as your permanent skin: " ..
            (SKIN_NAMES[activeSkin] or "?") .. " (ID " .. activeSkin .. ")")
    end)

    -- /zskinclear  remove your permanent skin
    sampRegisterChatCommand("zskinclear", function()
        ClearOwnSkin()
        Say("Permanent skin cleared.")
    end)

    -- /zskinname add <nick> <id>  -> given skin the moment that
    --                                 character streams in (LOCAL ONLY,
    --                                 SESSION ONLY - cleared on game exit)
    -- /zskinname del <nick>
    -- /zskinname list
    -- (Same list is also editable from the "Names" tab in /zskin)
    sampRegisterChatCommand("zskinname", function(args)
        local sub, rest = args:match("^%s*(%S+)%s*(.-)%s*$")
        if not sub then
            Say("Usage: /zskinname add <nick> <id> | del <nick> | list")
            return
        end

        if sub == "add" then
            local nick, sid = rest:match("^(%S+)%s+(%d+)$")
            if not nick or not sid then
                Say("Usage: /zskinname add <nick> <skinID>")
                return
            end
            AddNameSkin(nick, tonumber(sid))
            Say("Local skin set: " .. nick .. " -> ID " .. sid ..
                " (temporary, applied locally when they enter)")

        elseif sub == "del" then
            local nick = rest:match("^(%S+)$")
            if not nick or not nameSkins[nick:lower()] then
                Say("Usage: /zskinname del <nick>")
                return
            end
            RemoveNameSkin(nick)
            Say("Removed local skin for " .. nick)

        elseif sub == "list" then
            local count = 0
            for nick, sid in pairs(nameSkins) do
                Say("  " .. nick .. " -> ID " .. sid ..
                    " (" .. (SKIN_NAMES[sid] or "?") .. ")")
                count = count + 1
            end
            if count == 0 then Say("No names added this session yet.") end

        else
            Say("Usage: /zskinname add <nick> <id> | del <nick> | list")
        end
    end)

    -- /swalk <styleID>  set YOUR walk style (0-20)
    -- FROM: A9xWalkStyle.cs walk styles list
    sampRegisterChatCommand("swalk", function(args)
        local sid = tonumber(args)
        if not sid or not WALK_STYLES[sid] then
            Say("Usage: /swalk <0-20>")
            for k, v in pairs(WALK_STYLES) do
                sampAddChatMessage("  " .. k .. " = " .. v.label, -1)
            end
            return
        end
        walkGrants[0] = sid
        local applied = applyWalkStyle(PLAYER_PED, sid)
        if applied then
            Say("Walk style active: " .. WALK_STYLES[sid].label)
        else
            Say("Walk style saved; waiting for the animation block or host API.")
        end
    end)

    -- /swalkp <playerID> <styleID>  set walk on another player
    sampRegisterChatCommand("swalkp", function(args)
        local pid, sid = args:match("^%s*(%d+)%s+(%d+)%s*$")
        if not pid or not sid then
            Say("Usage: /swalkp <playerID> <styleID 0-20>")
            return
        end
        local playerId = tonumber(pid)
        local styleId  = tonumber(sid)
        if not WALK_STYLES[styleId] then
            Say("Invalid style ID. Use /swalk for list.")
            return
        end
        walkGrants[playerId] = styleId
        pcall(function()
            local res, ped = sampGetCharHandleBySampPlayerId(playerId)
            if res and doesCharExist(ped) then
                local applied = applyWalkStyle(ped, styleId)
                if applied then
                    Say("Walk " .. WALK_STYLES[styleId].label ..
                        " -> player " .. playerId)
                else
                    Say("Walk style saved; waiting for the animation block or host API.")
                end
            else
                Say("Saved. Will apply when player is visible.")
            end
        end)
    end)

    -- /swalk0  reset YOUR walk to default
    sampRegisterChatCommand("swalk0", function()
        walkGrants[0] = nil
        local applied = applyWalkStyle(PLAYER_PED, 0)
        Say(applied and "Walk reset to Default." or
            "Default walk reset saved; waiting for the animation block or host API.")
    end)

    -- FROM: PlayStable lines 363-383
    local reapplyTimer = 0
    while true do wait(0)
        ProcessPendingSkin()

        if windows_state.v == false then
            imgui.Process = false
        end

        -- Configurable hotkey (default F4)
        if waitingForKey then
            if NowSeconds() > rebindArmTime then
                for k = 1, 254 do
                    if isKeyJustPressed(k) then
                        hotKeyCode   = k
                        waitingForKey = false
                        SaveHotkey()
                        Say("Hotkey set to: " .. KeyName(k))
                        break
                    end
                end
            end
        elseif isKeyJustPressed(hotKeyCode) then
            windows_state.v = not windows_state.v
            imgui.Process   = windows_state.v
            if windows_state.v then
                searchBuf.v = ""
                UpdateFilter()
            end
        end

        -- LOCAL-ONLY PERMANENT SKIN POLLING
        -- Same 2-second tick as the grant reapply above. Wrapped in
        -- its own pcall so that if any function here isn't available
        -- on this build, ONLY this feature silently skips itself -
        -- it can never take down the rest of the script.
        if NowSeconds() - reapplyTimer > 2.0 then
            -- (reapplyTimer itself gets reset by the grant-reapply
            -- block right below, on this same tick)

            -- Sync temporary "Names" list -> grantedSkins, so the
            -- existing grant/reapply loop above does the actual work
            pcall(function()
                local maxId = sampGetMaxPlayerId(false)
                for i = 0, maxId do
                    if sampIsPlayerConnected(i) then
                        local nick = sampGetPlayerNickname(i)
                        if nick then
                            local wanted = nameSkins[nick:lower()]
                            if wanted and grantedSkins[i] ~= wanted then
                                grantedSkins[i] = wanted
                            end
                        end
                    end
                end
            end)

            -- Re-apply your own permanent skin if it drifted (respawn, etc.)
            if mySkin then
                pcall(function()
                    local customEntry = CUSTOM_SKINS[mySkin]
                    local customLoaderMissing = customEntry and customEntry.dff
                        and (type(loadModelInfo) ~= "function"
                            or type(CUSTOM_SKIN_SLOT) ~= "number")
                    if not customLoaderMissing and doesCharExist(PLAYER_PED)
                        and getCharModel(PLAYER_PED) ~= GetRuntimeSkinModelId(mySkin) then
                        ApplySkin({ id = mySkin, name = SKIN_NAMES[mySkin] or ("ID " .. mySkin) })
                    end
                end)
            end
        end

        -- FROM: skinc.lua sp.onSetPlayerPos pattern - re-apply via RPC 153
        -- FIX (repeated-grant issue): only resend the RPC when the
        -- character's current model has actually drifted away from
        -- what was granted. Blindly resending every 2s on every
        -- granted player caused constant redundant grants and
        -- visible model-rebuild flicker even when nothing changed.
        if NowSeconds() - reapplyTimer > 2.0 then
            reapplyTimer = NowSeconds()
            for playerId, skinId in pairs(grantedSkins) do
                pcall(function()
                    local res, ped   = sampGetCharHandleBySampPlayerId(playerId)
                    local needsApply = true
                    if res and doesCharExist(ped) then
                        needsApply = (getCharModel(ped) ~= skinId)
                    end
                    if needsApply then
                        local BS = raknetNewBitStream()
                        raknetBitStreamWriteInt32(BS, playerId)
                        raknetBitStreamWriteInt32(BS, skinId)
                        raknetEmulRpcReceiveBitStream(153, BS)
                        raknetDeleteBitStream(BS)
                    end
                end)
            end
            -- Re-apply walk styles
            for playerId, styleId in pairs(walkGrants) do
                pcall(function()
                    if playerId == 0 then
                        applyWalkStyle(PLAYER_PED, styleId)
                    else
                        local res, ped = sampGetCharHandleBySampPlayerId(playerId)
                        if res and doesCharExist(ped) then
                            applyWalkStyle(ped, styleId)
                        end
                    end
                end)
            end
        end
    end
end

--------------------------------------------------------------
-- IMGUI WINDOW
-- FROM: _RM__PlayStable.lua lines 386-486
--   imgui.OnDrawFrame() pattern
--   imgui.Begin / imgui.BeginChild / imgui.EndChild / imgui.End
--   NO if-check on Begin (matches PlayStable pattern exactly)
--------------------------------------------------------------
function imgui.OnDrawFrame()
    -- FROM: PlayStable line 387-389
    imgui.SetNextWindowSize(imgui.ImVec2(480, 620), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(420, 60),   imgui.Cond.FirstUseEver)
    imgui.Begin(
        "  ZENO SKIN CHANGER  v" .. _Version .. "  |  /zskin",
        windows_state,
        imgui.WindowFlags.NoResize
    )

    ----------------------------------------------------------
    -- PAGE SWITCHER (plain buttons - no BeginTabBar, works on
    -- every mimgui/moon-imgui build, old or new)
    ----------------------------------------------------------
    local function PageButton(label, page)
        local isCurrent = (_MenuPage == page)
        if isCurrent then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.12, 0.10, 1.0))
        end
        if imgui.Button(label, imgui.ImVec2(108, 24)) then
            _MenuPage = page
        end
        if isCurrent then
            imgui.PopStyleColor(1)
        end
    end

    PageButton("Skins", 1)
    imgui.SameLine()
    PageButton("My Skin", 2)
    imgui.SameLine()
    PageButton("Names", 3)
    imgui.SameLine()
    PageButton("Walk Style", 4)
    imgui.SameLine()
    PageButton("New Skins", 5)

    imgui.Separator()

    ----------------------------------------------------------
    -- PAGE 1: SKINS (browse + apply + search + reload/auto-import)
    ----------------------------------------------------------
    if _MenuPage == 1 then

        if activeSkin >= 0 then
            imgui.TextColored(imgui.ImVec4(0.3, 0.75, 1.0, 1.0),
                "Active: ID " .. activeSkin ..
                "  (" .. (SKIN_NAMES[activeSkin] or "?") .. ")")
        else
            imgui.TextDisabled("No skin applied")
        end

        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetWindowWidth() - 76)
        if imgui.Button("Reload", imgui.ImVec2(64, 18)) then
            LoadExtraSkins()
            local autoAdded = ScanAutoSkins()
            BuildSkinList()
            UpdateFilter()
            Say("Reloaded: " .. #skinList .. " skins (auto-imported: " .. autoAdded .. ")")
        end

        imgui.Separator()

        -- Search bar
        imgui.Text("Search:")
        imgui.SameLine()
        imgui.PushItemWidth(300)
        if imgui.InputText("##q", searchBuf) then
            UpdateFilter()
        end
        imgui.PopItemWidth()

        -- Status line
        if statusText ~= "" and NowSeconds() < statusExp then
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.45, 1.0), statusText)
        end

        imgui.TextDisabled(
            "Showing " .. #filtered .. " / " .. #skinList ..
            "  |  [*] = custom DFF/TXD"
        )

        imgui.Separator()

        imgui.BeginChild("SkinList", imgui.ImVec2(0, 400), true)

            if #filtered == 0 then
                imgui.Spacing()
                imgui.CenterText("No skins found.")
                imgui.CenterText("Add skins to: moonloader/zskin_skins.ini")
            else
                for _, skin in ipairs(filtered) do
                    local isActive = (skin.id == activeSkin)
                    local isCustom = (CUSTOM_SKINS[skin.id] ~= nil)

                    if isActive then
                        imgui.PushStyleColor(imgui.Col.Button,
                            imgui.ImVec4(0.00, 0.42, 0.18, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered,
                            imgui.ImVec4(0.00, 0.58, 0.25, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonActive,
                            imgui.ImVec4(0.00, 0.72, 0.30, 1.0))
                    end

                    local tag   = isCustom and "[*]" or "   "
                    local label = string.format(
                        "%s [%d]  %s", tag, skin.id, skin.name
                    )

                    if imgui.Button(label, imgui.ImVec2(435, 27)) then
                        ApplySkin(skin)
                    end

                    if isActive then
                        imgui.PopStyleColor(3)
                    end
                end
            end

        imgui.EndChild()

    ----------------------------------------------------------
    -- PAGE 2: MY SKIN (permanent, persists between game sessions)
    ----------------------------------------------------------
    elseif _MenuPage == 2 then
        imgui.Spacing()
        if mySkin then
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.45, 1.0),
                "Permanent skin: " .. (SKIN_NAMES[mySkin] or "?") ..
                " (ID " .. mySkin .. ")")
            imgui.TextDisabled("Re-applied automatically every time you spawn.")
        else
            imgui.TextDisabled("No permanent skin saved yet.")
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if activeSkin >= 0 then
            imgui.Text("Currently active: " .. (SKIN_NAMES[activeSkin] or "?") ..
                " (ID " .. activeSkin .. ")")
        else
            imgui.TextDisabled("Pick a skin from the Skins page first.")
        end

        imgui.Spacing()
        if imgui.Button("Save Current as Permanent", imgui.ImVec2(230, 28)) then
            if activeSkin >= 0 then
                SaveOwnSkin(activeSkin)
                Say("Saved as your permanent skin: " ..
                    (SKIN_NAMES[activeSkin] or "?") .. " (ID " .. activeSkin .. ")")
            else
                Say("Apply a skin first from the Skins page.")
            end
        end
        imgui.SameLine()
        if imgui.Button("Clear Permanent", imgui.ImVec2(150, 28)) then
            ClearOwnSkin()
            Say("Permanent skin cleared.")
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        imgui.Text("Menu hotkey: " .. KeyName(hotKeyCode))
        imgui.SameLine()
        if waitingForKey then
            imgui.TextColored(imgui.ImVec4(1.0, 0.75, 0.3, 1.0), "Press any key...")
        else
            if imgui.Button("Change Hotkey", imgui.ImVec2(140, 0)) then
                waitingForKey = true
                rebindArmTime = NowSeconds() + 0.3 -- avoid catching this click
                Say("Press the key you want to use to open this menu...")
            end
        end

    ----------------------------------------------------------
    -- PAGE 3: NAMES (temporary, local only, cleared on game exit)
    ----------------------------------------------------------
    elseif _MenuPage == 3 then
        imgui.TextColored(imgui.ImVec4(1.0, 0.75, 0.3, 1.0),
            "Temporary - local only, cleared when you close the game.")
        imgui.Spacing()

        imgui.Text("Nickname:")
        imgui.SameLine()
        imgui.PushItemWidth(150)
        imgui.InputText("##nameNick", nameNickBuf)
        imgui.PopItemWidth()

        imgui.Text("Skin ID:")
        imgui.SameLine()
        imgui.PushItemWidth(90)
        imgui.InputInt("##nameId", nameIdBuf)
        imgui.PopItemWidth()
        imgui.SameLine()
        if imgui.Button("Add", imgui.ImVec2(60, 0)) then
            local nick = nameNickBuf.v:match("^%s*(.-)%s*$")
            local id   = nameIdBuf.v
            if nick ~= "" and id and id > 0 then
                AddNameSkin(nick, id)
                Say("Local skin set: " .. nick .. " -> ID " .. id)
                nameNickBuf.v = ""
            else
                Say("Enter a nickname and a valid skin ID.")
            end
        end

        imgui.Separator()
        imgui.BeginChild("NameList", imgui.ImVec2(0, 280), true)

            local any = false
            for nick, id in pairs(nameSkins) do
                any = true
                imgui.Text(nick .. "  ->  ID " .. id ..
                    "  (" .. (SKIN_NAMES[id] or "?") .. ")")
                imgui.SameLine()
                imgui.SetCursorPosX(imgui.GetWindowWidth() - 60)
                if imgui.Button("X##rm_" .. nick, imgui.ImVec2(40, 18)) then
                    RemoveNameSkin(nick)
                end
            end
            if not any then
                imgui.Spacing()
                imgui.CenterText("No names added this session yet.")
            end

        imgui.EndChild()

    ----------------------------------------------------------
    -- PAGE 4: WALK STYLE (yourself OR one chosen player, never all)
    ----------------------------------------------------------
    elseif _MenuPage == 4 then
        imgui.Checkbox("Apply to myself", applyToSelf)
        if not applyToSelf.v then
            imgui.SameLine()
            imgui.Text("Player ID:")
            imgui.SameLine()
            imgui.PushItemWidth(70)
            imgui.InputInt("##walkTarget", walkTargetBuf)
            imgui.PopItemWidth()
        end

        imgui.Separator()
        imgui.BeginChild("WalkList", imgui.ImVec2(0, 400), true)

            for id = 0, 20 do
                local ws = WALK_STYLES[id]
                if ws then
                    if imgui.Button(ws.label .. "##walk" .. id, imgui.ImVec2(435, 25)) then
                        if applyToSelf.v then
                            walkGrants[0] = id
                            applyWalkStyle(PLAYER_PED, id)
                            Say("Walk: " .. ws.label .. " (you)")
                        else
                            local target = walkTargetBuf.v
                            walkGrants[target] = id
                            local res, ped = sampGetCharHandleBySampPlayerId(target)
                            if res and doesCharExist(ped) then
                                applyWalkStyle(ped, id)
                                Say("Walk: " .. ws.label .. " -> player " .. target)
                            else
                                Say("Saved. Will apply once player " ..
                                    target .. " is visible.")
                            end
                        end
                    end
                end
            end

        imgui.EndChild()

    ----------------------------------------------------------
    -- PAGE 5: NEW SKINS (only custom/auto-imported skins, so
    -- they're easy to find separate from the vanilla list)
    ----------------------------------------------------------
    elseif _MenuPage == 5 then
        imgui.TextDisabled("Only custom skins (imported folders or zskin_skins.ini entries).")
        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetWindowWidth() - 76)
        if imgui.Button("Reload", imgui.ImVec2(64, 18)) then
            LoadExtraSkins()
            local autoAdded = ScanAutoSkins()
            BuildSkinList()
            UpdateFilter()
            Say("Reloaded: " .. #skinList .. " skins (auto-imported: " .. autoAdded .. ")")
        end

        imgui.Separator()
        imgui.BeginChild("NewSkinList", imgui.ImVec2(0, 460), true)

            local any = false
            for id, c in pairs(CUSTOM_SKINS) do
                any = true
                local isActive = (id == activeSkin)
                if isActive then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.42, 0.18, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.58, 0.25, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.00, 0.72, 0.30, 1.0))
                end

                local label = string.format("[%d]  %s", id, SKIN_NAMES[id] or "?")
                if imgui.Button(label, imgui.ImVec2(435, 27)) then
                    ApplySkin({ id = id, name = SKIN_NAMES[id] or ("ID " .. id) })
                end

                if isActive then
                    imgui.PopStyleColor(3)
                end
            end

            if not any then
                imgui.Spacing()
                imgui.CenterText("No custom skins yet.")
                imgui.CenterText("Drop a folder into moonloader/skins/<name>/")
                imgui.CenterText("with a .dff (+ optional .txd) inside, then Reload.")
            end

        imgui.EndChild()
    end

    imgui.Spacing()
    imgui.CenterText("by Sam Wilson")

    imgui.End()
end

--------------------------------------------------------------
-- FROM: _RM__PlayStable.lua line 785  (called at bottom)
ApplyRedStyle()

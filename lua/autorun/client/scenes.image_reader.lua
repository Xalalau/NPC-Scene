-- W.I.P.

-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/public/scenefilecache/SceneImageFile.h
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/sceneimage.cpp
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoscene.cpp#L3783
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreoactor.cpp#L267
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/sceneimage.cpp#L217

local SIZEOF_INT = 4
local SIZEOF_UINT = 4
local SIZEOF_SHORT = 2
local function toUShort(b)
	local i = {string.byte(b,1,SIZEOF_SHORT)}
	return i[1] +i[2] *256
end
local function toInt(b)
	local i = {string.byte(b,1,SIZEOF_INT)}
	i = i[1] +i[2] *256 +i[3] *65536 +i[4] *16777216
	if(i > 2147483647) then return i -4294967296 end
	return i
end
local function toUInt(b)
	local i = {string.byte(b,1,SIZEOF_UINT)}
	return i[1] +i[2] *256 +i[3] *65536 +i[4] *16777216
end
local function ReadInt(f) return toInt(f:Read(SIZEOF_INT)) end
local function ReadUInt(f) return toUInt(f:Read(SIZEOF_UINT)) end
local function ReadUShort(f) return toUShort(f:Read(SIZEOF_SHORT)) end
local function ReadShort(f)
	local b1 = f:ReadByte()
	local b2 = f:ReadByte()
	return bit.lshift(b2,8) +b1
end

local function IDToString(f) return string.char(string.byte(f:Read(SIZEOF_UINT),1,SIZEOF_UINT)) end

local function ReadNullTerminatedString(f,max)
    local t = ""
    while(true) do
        local c = f:Read(1)
        if c == "\0" then break end
        t = t .. c
    end
    return t
end

--[[
    binary stucture:

    header
    string offsets
    string pool
    scene entries
    scene summary
    scene data

    Note: entries, summary and data follow the same list order
]]

local _R = debug.getregistry()
local meta = {}
_R.sceneimage = meta
local methods = {}
meta.__index = methods
methods.MetaName = "scenes.image"
function meta:__tostring()
	local str = "scenes.image [" .. tostring(self.fName) .. "] [" .. tostring(self.m_id) .. "] [" .. tostring(self.m_version) .. "]"
	return str
end

function OpenScenesImage(fName)
	local f = file.Open(fName, "rb", "GAME")
    if (!f) then return false end

    local t = {
        m_id = IDToString(f),
	    m_version = ReadUInt(f),
	    m_scenes_number = ReadUInt(f),
	    m_strings_number = ReadUInt(f),
	    m_scene_entry_offset = ReadUInt(f),
	    m_string_poll_offset = f:Tell(),
        m_file = f,
        m_path = fName
    }

    setmetatable(t, meta)

    return t
end

function methods:ReadStringOffsets()
	local f = self.m_file
    if (!f) then return false end

    f:Seek(self.m_string_poll_offset)

    local stringOffsets = {}
    for i = 1,self.m_strings_number do
		stringOffsets[i] = ReadUInt(f)
	end

    return stringOffsets
end

function methods:ReadStringPool(stringOffset)
	local f = self.m_file
    if (!f) then return false end

    f:Seek(stringOffset)

    return ReadNullTerminatedString(f)
end

function methods:ReadSceneEntries()
	local f = self.m_file
    if (!f) then return false end

    f:Seek(self.m_scene_entry_offset)

    local sceneEntries = {}
    for i = 1,self.m_scenes_number do
		local sceneEntry = {
			crcName = ReadUInt(f),
			dataOffset = ReadUInt(f),
			dataLength = ReadUInt(f),
			sceneSummaryOffset = ReadUInt(f)
        }

        table.insert(sceneEntries, sceneEntry)
	end

    return sceneEntries
end

function methods:ReadSceneSummary(sceneEntry)
	local f = self.m_file
    if !f or !sceneEntry then return false end

    f:Seek(sceneEntry.sceneSummaryOffset)

    local sceneSummary = {
        milliseconds = ReadUInt(f),
        soundsNumber = ReadUInt(f),
    }

    return sceneSummary
end

function methods:ReadSceneData(sceneEntry)
	local f = self.m_file
    if !f or !sceneEntry then return false end

    f:Seek(sceneEntry.dataOffset)

    local id = IDToString(f)
    if id == "bvcd" then
        return {
            id = id,
            scene = f:Read(sceneEntry.dataLength)
        }
    elseif id == "LZMA" then
        local sceneData = {
            id = id,
            actualSize = ReadUInt(f),
            LZMASize = ReadUInt(f),
            properties = f:Read(5)
        }
        sceneData.scene = string.char(string.byte(f:Read(sceneData.LZMASize), 1, sceneData.LZMASize))

        return sceneData
    end
end

-- TESTING:

local scenes_data = OpenScenesImage("scenes/scenes.image")
local scenesEntries = scenes_data:ReadSceneEntries()

for k,scenesEntry in ipairs(scenesEntries) do
    local sceneData = scenes_data:ReadSceneData(scenesEntry)
    if sceneData.id == "LZMA" then
        -- How to uncompress sceneData.scene?
        print("")
    end
    if k == 6 then break end -- Limit the test
end

print("----------")
print()
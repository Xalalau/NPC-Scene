-- W.I.P.

-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/public/scenefilecache/SceneImageFile.h
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/sceneimage.cpp
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoscene.cpp#L3783
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreoactor.cpp#L267
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/sceneimage.cpp#L217

local function IDToString(f) return string.char(string.byte(f:Read(4),1,4)) end

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
    return "scenes.image [" .. tostring(self.fName) .. "] [" .. tostring(self.m_id) .. "] [" .. tostring(self.m_version) .. "]"
end

function OpenScenesImage(fName)
    local f = file.Open(fName, "rb", "GAME")
    if not f then return false end

    local t = {
        m_id = f:ReadULong(),
        m_version = f:ReadULong(),
        m_scenes_number = f:ReadULong(),
        m_strings_number = f:ReadULong(),
        m_scene_entry_offset = f:ReadULong(),
        m_string_poll_offset = f:Tell(),
        m_file = f,
        m_path = fName
    }

    setmetatable(t, meta)

    return t
end

function methods:ReadStringOffsets()
    local f = self.m_file
    if not f then return false end

    f:Seek(self.m_string_poll_offset)

    local stringOffsets = {}
    for i = 1,self.m_strings_number do
        stringOffsets[i] = f:ReadULong()
    end

    return stringOffsets
end

function methods:ReadStringPool(stringOffset)
    local f = self.m_file
    if not f then return false end

    f:Seek(stringOffset)

    return ReadNullTerminatedString(f)
end

function methods:ReadSceneEntries()
    local f = self.m_file
    if not f then return false end

    f:Seek(self.m_scene_entry_offset)

    local sceneEntries = {}
    for i = 1,self.m_scenes_number do
        local sceneEntry = {
            crcName = f:ReadULong(),
            dataOffset = f:ReadULong(),
            dataLength = f:ReadULong(),
            sceneSummaryOffset = f:ReadULong()
        }

        table.insert(sceneEntries, sceneEntry)
    end

    return sceneEntries
end

function methods:ReadSceneSummary(sceneEntry)
    local f = self.m_file
    if not f or not sceneEntry then return false end

    f:Seek(sceneEntry.sceneSummaryOffset)

    local sceneSummary = {
        milliseconds = f:ReadULong(),
        soundsNumber = f:ReadULong(),
    }

    return sceneSummary
end

function methods:ReadSceneData(sceneEntry)
    local f = self.m_file
    if not f or not sceneEntry then return false end

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
            actualSize = f:ReadULong(),
            LZMASize = f:ReadULong(),
            properties = f:Read(5)
        }
        sceneData.scene = f:Read(sceneData.LZMASize)

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

        -- util.Decompress(sceneData.scene) -- CRASH

        print("")
    end
    if k == 6 then break end -- Limit the test (3 = CRASH)
end

print("----------")
print()
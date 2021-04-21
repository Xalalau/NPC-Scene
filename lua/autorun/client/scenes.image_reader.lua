do return end

-- W.I.P.
-- (R.I.P.)

--[[

    All of the following code is intended for reading binary vcds from scenes.image files. My goal here is to rebuild the game
    scenes list because GMod desn't provide it.

    With what I already have it'd be easy to obtain the vcd paths if they weren't all converted to CRC. This is irreversible,
    so the names are just garbage. A second option would be to look up the names directly in the string pool, but I printed
    it out and I couldn't find all the scenes. Moving forward the last option that I imagined would be to rebuild the vcds
    theirselves since we can get the paths from a field in each one. The problem is that my code still doesn't work.

    In short, you're only going to get correct results until methods:ReadSceneData(), when reading the bvcd offset has proven
    to be something very confusing. Perhaps this part is still totally broken... From there starts the binary restoration,
    which I barely tested. It was more of an exercise to handle Source than something to use, certainly the logic is broken.
    So I left several links pointing to the origin of each function to help with advances later.

    For someone who wants to make a list, this is kind of overkill.

    - Xalalau Xubilozo


    [Edit] Even with https://developer.valvesoftware.com/wiki/VSIF2VCD, that the author knows what he's doing, I wasn't able
    to recover all the scene names. This is not worth it. I'll generate the lists using the SDK and make them hardcoded.
        https://github.com/ValveSoftware/source-sdk-2013/tree/master/sp/game
]]

-- References:
-- https://developer.valvesoftware.com/wiki/Scenes.image
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/public/scenefilecache/SceneImageFile.h
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/sceneimage.cpp
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoscene.cpp#L3783
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreoactor.cpp#L267
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/utils/lzma/C/Util/Lzma/LzmaUtil.c#L151
-- https://github.com/VSES/SourceEngine2007/blob/43a5c90a5ada1e69ca044595383be67f40b33c61/src_main/scenefilecache/SceneFileCache.cpp#L290
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/server/sceneentity.cpp#L231

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
            sceneOffset = f:Tell(),
            scene = f:Read(sceneEntry.dataLength)
        }
    elseif id == "LZMA" then
        local sceneData = {
            id = id,
            actualSize = f:ReadULong(),
            LZMASize = f:ReadULong(),
            properties = f:Read(5),
            sceneOffset = f:Tell()
        }
        sceneData.scene = f:Read(sceneEntry.dataLength)

        return sceneData
    end
end










-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreochannel.cpp#L540
-- bool CChoreoChannel::RestoreFromBuffer( CUtlBuffer& buf, CChoreoScene *pScene, CChoreoActor *pActor, IChoreoStringPool *pStringPool )
function methods:ChannelRestoreFromBuffer(bvcd)
    local restored = {
        name = self:ReadStringPool(bvcd:ReadShort()),
        numEvents = bvcd:Read(1),
        events = {}
    }

	for i = 1,restored.numEvents do
        restored.events[i] = self:EventRestoreFromBuffer(bvcd)
	end

	restored.active = buf.GetChar() == 1 and true or false

	return restored
end

-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoactor.cpp#L267
-- bool CChoreoActor::RestoreFromBuffer( CUtlBuffer& buf, CChoreoScene *pScene, IChoreoStringPool *pStringPool )
function methods:ActorRestoreFromBuffer(bvcd)
    local restored = {
        name = self:ReadStringPool(bvcd:ReadShort()),
        count = bvcd:Read(1),
        channels = {}
    }

	for i = 1,restored.count do
        restored.channels[i] = self:ChannelRestoreFromBuffer(bvcd)
	end

    restored.active = buf.GetChar() == 1 and true or false

    return restored
end

-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoevent.cpp#L4379
-- bool CCurveData::RestoreFromBuffer( CUtlBuffer& buf, IChoreoStringPool *pStringPool )
function methods:CCurveDataRestoreFromBuffer(bvcd)
    local restored = {
        count = bvcd:Read(1)
    }

    for i = 1,restored.count do
		restored[i].time = bvcd:ReadFloat()
		restored[i].value = bvcd:Read(1) * 1.0/255.0
        restored[i].sample = false
    end

    return restored
end

-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoevent.cpp#L4379
-- bool CChoreoEvent::RestoreFlexAnimationsFromBuffer( CUtlBuffer& buf, IChoreoStringPool *pStringPool )
function methods:RestoreFlexAnimationsFromBuffer(bvcd)
    local restored = {
        numTracks = bvcd:Read(1),
        tracks = {}
    }

	for i = 1,restored.numTracks do
        restored.tracks[i].name = self:ReadStringPool(bvcd:ReadShort())
        restored.tracks[i].flags = bvcd:Read(1)
        restored.tracks[i].min = bvcd:ReadFloat()
        restored.tracks[i].max = bvcd:ReadFloat()
        restored.tracks[i].samplesNum = bvcd:ReadShort()
        restored.tracks[i].samples = {}

		for j = 1,restored.tracks[i].samplesNum do
            restored.tracks[i].samples[j].time = bvcd:ReadFloat()
            restored.tracks[i].samples[j].value = bvcd:Read(1) * 1.0/255.0
        end

        restored.tracks[i].samplesSetCurveTypeNum = bvcd:ReadShort()
        restored.tracks[i].samplesSetCurveType = {}

		if bit.band(restored.tracks[i].flags, bit.rshift(1, 1)) then -- flags & ( 1<<1 ) ) ? true : false -- I don't know if this is right
            for j = 1,restored.tracks[i].samplesSetCurveTypeNum do
                restored.tracks[i].samplesSetCurveType[j].time = bvcd:ReadFloat()
                restored.tracks[i].samplesSetCurveType[j].value = bvcd:Read(1) * 1.0/255.0
            end
        end
    end

	return restored
end

-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoevent.cpp#L4244
-- bool CChoreoEvent::RestoreFromBuffer( CUtlBuffer& buf, CChoreoScene *pScene, IChoreoStringPool *pStringPool )
function methods:EventRestoreFromBuffer(bvcd)
    local function GetTags(types, max, percent)
        local tags = {}
        for i = 1,types do
            for i = 1,max do
                tags[i].name = bvcd:ReadShort()
                tags[i].percentage = bvcd:Read(1) * percent
            end
        end
        return tags
    end

    local restored = {
        type = bvcd:Read(1),
        eventName = self:ReadStringPool(bvcd:ReadShort()),
        startTime = bvcd:ReadFloat(),
        endTime = bvcd:ReadFloat(),
        param1 = self:ReadStringPool(bvcd:ReadShort()),
        param2 = self:ReadStringPool(bvcd:ReadShort()),
        param3 = self:ReadStringPool(bvcd:ReadShort()),
        restoredCCurveData = self:CCurveDataRestoreFromBuffer(bvcd),
        flags = bvcd:Read(1),
        distanceToTarget = bvcd:ReadFloat(),
        relTags = GetTags(1, bvcd:Read(1), 1.0/255.0),
        timingTags = GetTags(1, bvcd:Read(1), 1.0/255.0),
        typeTags = GetTags(3, bvcd:Read(1), 1.0/4096.0), -- ChoreoEvent::NUM_ABS_TAG_TYPES = 3        
    }

    if restored.type == 6 then -- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreoevent.h#L257
        restored.duration = bvcd:ReadFloat()
    end
	
	if bvcd:Read(1) == 1 then
        restored.tagname = bvcd:ReadShort()
        restored.wavname = bvcd:ReadShort()
    end

	self:RestoreFlexAnimationsFromBuffer(bvcd)

    if restored.type == 12 then -- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreoevent.h#L296
		restored.loopCount = bvcd:Read(1)
    end

    if restored.type == 5 then -- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/choreoevent.h#L275
        restored.closedCaptionType = bvcd:Read(1)
        restored.closedCaptionToken = self:ReadStringPool(bvcd:ReadShort())
        restored.closedCaptionFlags = bvcd:Read(1)
	end

	return restored
end

-- bool CChoreoScene::RestoreFromBinaryBuffer( CUtlBuffer& buf, char const *filename, IChoreoStringPool *pStringPool )
-- https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/choreoscene.cpp#L3783
function methods:ReadBinaryVCD(sceneData)
    local bvcd = self.m_file
    if not bvcd or not sceneData then return {} end

    bvcd:Seek(sceneData.sceneOffset)

    local vcd = {
        tag = bvcd:ReadLong(),
        version = bvcd:Read(1),
        crc = bvcd:ReadLong(),
    }

    vcd.eventCount = bvcd:Read(1)
    vcd.events = {}
    for i = 1,vcd.eventCount do
        vcd.events[i] = self:EventRestoreFromBuffer(bvcd)
    end

    vcd.actorCount = bvcd:Read(1)
    vcd.actors = {}
    for i = 1,vcd.actorCount do
        vcd.actors[i] = self:ActorRestoreFromBuffer(bvcd)
    end

    vcd.restoredCCurveData = self:CCurveDataRestoreFromBuffer(bvcd)

	vcd.ignorePhonemes = bvcd:Read(1) != 0

    return vcd
end








-- TESTING

local function test()
    local sImage = OpenScenesImage("scenes/scenes.image")
    local scenesEntries = sImage:ReadSceneEntries()

    for k,scenesEntry in ipairs(scenesEntries) do
        local sceneData = sImage:ReadSceneData(scenesEntry)
        PrintTable(sceneData)
        if sceneData.id == "bvcd" then
            -- PrintTable(sImage:ReadBinaryVCD(sceneData))
        elseif sceneData.id == "LZMA" then
            -- How to uncompress sceneData.scene?

            -- util.Decompress(sceneData.scene) -- CRASH            
        end
        print("")
        if k == 2 then break end -- Limit the test (3 = CRASH)
    end

    print("----------")
    print()
end

--test()
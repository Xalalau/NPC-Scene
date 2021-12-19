AddCSLuaFile()

NPCS = {
    premadeSceneList = {}
}

local function includeLibs(dir, isClientLib)
    local files, dirs = file.Find( dir.."*", "LUA" )

    if not dirs then return end

    for _, fdir in pairs(dirs) do
        includeLibs(dir .. fdir .. "/", isClientLib)
    end

    for k,v in pairs(files) do
        if SERVER and isClientLib then
            AddCSLuaFile(dir .. v)
        else
            include(dir .. v)
        end
    end 
end

NPCS.folder = { lua = "npcscene/" }

if SERVER then
    includeLibs(NPCS.folder.lua)
end
includeLibs(NPCS.folder.lua, true)
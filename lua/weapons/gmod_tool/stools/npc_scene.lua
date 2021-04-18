--[[ 

[Credits] Tool originally created by Deco and continued by Xalalau
1.2 (original) by Deco: http://www.garrysmod.org/downloads/?a=view&id=42593 
1.3 (fix for 1.2) and 1.4 (remake) by Xalalau: http://steamcommunity.com/sharedfiles/filedetails/?id=121182342

Current version: 1.4.7

Link: https://github.com/xalalau/GMod/tree/master/NPC%20Scene

]]--

-- --------------
-- TOOL SETUP
-- --------------

TOOL.Category = "Poser"
TOOL.Name = "#Tool.npc_scene.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar["scene"] = "scenes/npc/Gman/gman_intro"
TOOL.ClientConVar["actor"] = "Alyx"
TOOL.ClientConVar["loop"] = 0
TOOL.ClientConVar["key"] = 0
TOOL.ClientConVar["multiple"] = 0
TOOL.ClientConVar["render"] = 1
TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" }
}

if CLIENT then
    language.Add("Tool.npc_scene.name", "NPC Scene")
    language.Add("Tool.npc_scene.desc", "Make NPCs act using \".vcd\" files!")
    language.Add("Tool.npc_scene.left", "Left click to play the scene.")
    language.Add("Tool.npc_scene.right", "Right click to set the actor name.")
    language.Add("Tool.npc_scene.reload", "Reload to stop the scene.")
end

if SERVER then
    util.AddNetworkString("npc_scene_set_ent_table")
    util.AddNetworkString("npc_scene_hook_key")
    util.AddNetworkString("npc_scene_play")
end

-- --------------
-- GLOBAL VARS
-- --------------

-- Table for controlling keys, NPC reloading and name printing.
local modifiedEntsTable = {}

-- --------------
-- GENERAL
-- --------------

-- Plays a scene with or without loops.
local function StartScene(ent)
    if CLIENT then return end

    ent.npcscene.active = 1

    -- Gets the animationg lenght and plays it.
    local lenght = ent:PlayScene(ent.npcscene.scene) 
    local index = ent.npcscene.index

    -- Waits for the next play (if we are using loops).
    if ent.npcscene.loop != 0 then
        timer.Create(tostring(ent) .. index, lenght, ent.npcscene.loop, function()
            if not ent:IsValid() then
                modifiedEntsTable[index] = nil
                timer.Stop(tostring(ent) .. index)
            elseif ent.npcscene.loop == 0 then
                modifiedEntsTable[index] = nil
                ent.npcscene.active = 0
                timer.Stop(tostring(ent) .. index)
            else
                ent:PlayScene(ent.npcscene.scene)
                ent.npcscene.loop = ent.npcscene.loop - 1
            end
        end)
    end
end

-- Reloads NPCs so we can apply new scenes.
local function ReloadEntity(ply, ent)
    if CLIENT then return end

    local dup = {}

    dup = duplicator.Copy(ent)
    SafeRemoveEntity(ent)
    duplicator.Paste(ply, dup.Entities, dup.Constraints)

    ent = ply:GetEyeTrace().Entity

    undo.Create("NPC ")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
    undo.Finish()

    return ent
end

-- Check if a entity is valid (NPC).
local function IsValidEnt(tr)
    if tr.Hit and tr.Entity and tr.Entity:IsValid() and tr.Entity:IsNPC() then
        return true
    end
    
    return false
end

-- Render the NPC names.
local function RenderActorName()
    if SERVER then return end

    if GetConVar("npc_scene_render"):GetInt() == 1 then
        for _,ent in pairs(modifiedEntsTable) do
            if ent:IsValid() then
                local entPos = ent:GetPos()
                local screenPos = Vector(0, 0, 0)
                local entHeadBone = ent:LookupBone("ValveBiped.Bip01_Head1")

                if entHeadBone then
                    local entHeadPos, entHeadAng = ent:GetBonePosition(entHeadBone)

                    screenPos = (entHeadPos + Vector(0, 0, 10)):ToScreen()
                else
                    local minBound, maxBound = ent:WorldSpaceAABB()
                    local drawPos = Vector(entPos.x, entPos.y, minBound.z)

                    screenPos = drawPos:ToScreen()
                end

                if ent.npcscene.name != "" and LocalPlayer():GetPos():Distance(ent:GetPos()) < 300 then
                    draw.DrawText(ent.npcscene.name, "TargetID", screenPos.x - string.len(ent.npcscene.name) * 4, screenPos.y - 15, Color(255, 255, 255, 255))
                end
            end
        end
    end
end

if CLIENT then
    hook.Add("HUDPaint", "RenderActorName", RenderActorName)
end

-- Send the modifiedEntsTable to new players
local function InitModifiedEntsTable(ply)
    if table.Count(modifiedEntsTable) > 0 then
        local currentTableFormated = {}

        for _,modifiedEnt in pairs(modifiedEntsTable) do
            table.insert(currentTableFormated, { ent = modifiedEnt, npcscene = modifiedEnt.npcscene })
        end

        net.Start("npc_scene_set_ent_table")
        net.WriteTable(currentTableFormated)
        net.Send(ply)
    end
end

if SERVER then
    hook.Add("PlayerInitialSpawn", "InitModifiedEntsTable", function (ply)
        hook.Add("SetupMove", "SetupMove" .. tostring(ply), function(ply)
            InitModifiedEntsTable(ply)
        end)
    end)
end

-- --------------
-- NET FUNCTIONS
-- --------------

if SERVER then
    -- Plays scenes with keys associated.
    net.Receive("npc_scene_play", function()
        local ent = net.ReadEntity()
        local multiple = net.ReadInt(2)

        if ent.npcscene.active == 0 or multiple == 1 then
            StartScene(ent)
        end
    end)
end

if CLIENT then
    -- Sets the ent table.
    net.Receive("npc_scene_set_ent_table", function()
        local entsTable = net.ReadTable()
        
        for _,modifiedEnt in ipairs(entsTable) do
            if not modifiedEnt.npcscene then continue end

            modifiedEnt.ent.npcscene = modifiedEnt.npcscene       
            table.insert(modifiedEntsTable, modifiedEnt.ent.npcscene.index, modifiedEnt.ent)
        end
    end)

    -- Sets the keys ("Tick" hook).
    net.Receive("npc_scene_hook_key", function(_, ply)
        local ent = net.ReadEntity()
        local index = ent.npcscene.index

        if hook.GetTable()[index] then
            return
        end

        local multiple = GetConVar("npc_scene_multiple"):GetInt()

        hook.Add("Tick", "hook_" .. index, function()
            if not ent:IsValid() then
                modifiedEntsTable[index] = nil
                hook.Remove("Tick", "hook_" .. index)
            elseif input.IsKeyDown(ent.npcscene.key) then
                net.Start("npc_scene_play")
                net.WriteEntity(ent)
                net.WriteInt(multiple, 2)
                net.SendToServer()
            end
        end)
    end)
end

-- --------------
-- FILES
-- --------------

-- Client Derma.
local sceneListPanel
local ctrl

-- Populates the scenes list in Singleplayer.
local function ScanDir(parentNode, parentDir, ext)
    if SERVER then return end

    local files, dirs = file.Find(parentDir .. "*", "GAME")

    for _,dirName in ipairs(dirs) do
        local node = parentNode:AddNode(dirName)
        local clicked = false

        node.DoClick = function()
            if clicked then return end

            clicked = true
            ScanDir(node, parentDir .. dirName .. "/", ext)
            node:SetExpanded(true)
        end
    end

    for _,fileName in ipairs(files) do
        local node = parentNode:AddNode(fileName)
        local path = parentDir .. fileName

        node:SetIcon("icon16/page_white.png")
        node.DoClick = function() RunConsoleCommand("npc_scene_scene", path) end
    end 
end

if CLIENT then
    sceneListPanel = vgui.Create("DFrame")
        sceneListPanel:SetTitle("Scenes")
        sceneListPanel:SetSize(300, 700)
        sceneListPanel:SetPos(10, 10)
        sceneListPanel:SetDeleteOnClose(false)
        sceneListPanel:SetVisible(false)

    ctrl = vgui.Create("DTree", sceneListPanel)
        ctrl:SetPadding(5)
        ctrl:SetSize(300, 675)
        ctrl:SetPos(0, 25)
        ctrl:SetBackgroundColor(Color(255, 255, 255, 255))
end

local initialized
local function ListScenes()
    if SERVER then return end

    if not initialized then
        local node = ctrl:AddNode("Scenes! (click one to select)")

        ScanDir(node, "scenes/", ".vcd")
        node:SetExpanded(true)
        initialized = true
    end

    sceneListPanel:SetVisible(true)
    sceneListPanel:MakePopup()
end

if CLIENT then
    concommand.Add("npc_scene_list", ListScenes)
end

-- --------------
-- TOOLGUN
-- --------------

-- Plays scenes.
function TOOL:LeftClick(tr)
    if not IsValidEnt(tr) then
        return false
    elseif CLIENT then
        return true
    end

    local ply = self:GetOwner()
    local ent = tr.Entity
    local scene = string.gsub(self:GetClientInfo("scene"), ".vcd", "")
    local name = ""
    local times = self:GetClientNumber("multiple")

    -- Checks if a scene is already applied.
    if ent.npcscene then
        -- Are we applying the same scene with the "Multiple Times" option enabled?
        if times == 1 and ent.npcscene.scene == scene then
            -- If yes, we just need to play it again and thats it Haha
            StartScene(ent)

            return true
        end
        -- Gets the actor name if there is one.
        if ent.npcscene.name then
            name = ent.npcscene.name
        end
    end

    -- Reloads the scenes (by deleting the loops and reloading the NPCs).
    if ent.npcscene then 
        if ent.npcscene.active == 1 and times == 0 then
            timer.Stop(tostring(ent) .. ent.npcscene.index)
            ent = ReloadEntity(ply, ent)
        end
    end

    -- Adds the configurations to the entity.
    local data = {
        active = 0,
        index  = ent:EntIndex(),
        loop   = self:GetClientNumber("loop"),
        scene  = scene,
        name   = name,
        key    = self:GetClientNumber("key"),
    }

    timer.Simple(0.25, function() -- Timer to avoid spawning errors.
        ent.npcscene = data

        if not ent.npcscene then return end

        -- Registers the entity in our internal table.
        table.insert(modifiedEntsTable, ent:EntIndex(), ent)
        net.Start("npc_scene_set_ent_table")
        net.WriteTable({ { ent = ent, npcscene = ent.npcscene } })
        net.Send(ply)

        -- Plays/Prepares the scene.
        if ent.npcscene.key == 0 then -- Not using keys? Let's play it.
            StartScene(ent)
        else -- Using keys? Let's bind it.
            net.Start("npc_scene_hook_key")
            net.WriteEntity(ent)
            net.Send(ply)
        end
    end)

    return true
end

-- Sets actor names.
function TOOL:RightClick(tr)
    if not IsValidEnt(tr) then
        return false
    elseif CLIENT then
        return true
    end 

    local ent = tr.Entity
    local name = self:GetClientInfo("actor")

    timer.Simple(0.25, function() -- Timer to avoid spawning errors.
        -- Sets the name.
        ent:SetName(name)

        -- Adds the name to the entity.
        if not ent.npcscene then
            ent.npcscene = {}
            ent.npcscene.index  = ent:EntIndex()
        end
        ent.npcscene.name = name

        -- Register the entity in our internal table.
        table.insert(modifiedEntsTable, ent:EntIndex(), ent)
        for _, v in ipairs(player.GetAll()) do
            net.Start("npc_scene_set_ent_table")
            net.WriteTable({ { ent = ent, npcscene = ent.npcscene } })
            net.Send(v)
        end
    end)

    return true
end

function TOOL:Reload(tr)
    if not IsValidEnt(tr) then
        return false
    end

    local ent = tr.Entity

    -- Deletes the loops and reloads the NPCs.
    if ent.npcscene then 
        if SERVER then
            timer.Simple(0.25, function() -- Timer to avoid spawning errors.
                if ent.npcscene.name then
                    ent:SetName("")
                end

                timer.Stop(tostring(ent) .. ent.npcscene.index)
                ReloadEntity(self:GetOwner(), ent)
            end)
        end

        return true
    else
        return false
    end
end

-- --------------
-- CPanel
-- --------------

function TOOL.BuildCPanel(CPanel)
    CPanel:AddControl ("Header"  , { Text  = '#Tool.npc_scene.name', Description = '#Tool.npc_scene.desc' })
    CPanel:AddControl ("Numpad"  , { Label = "Scene key", Command = "npc_scene_key" })
    CPanel:AddControl ("TextBox" , { Label = "Scene Name" , Command = "npc_scene_scene", MaxLength = 500 })
    CPanel:AddControl ("TextBox" , { Label = "Actor Name" , Command = "npc_scene_actor", MaxLength = 30 })
    if game.SinglePlayer() then
        CPanel:ControlHelp("\nApply a scene and open the console to see which actor names you need to set.")
    end
    CPanel:AddControl ("Slider"  , { Label = "Loop", Type = "int", Min = "0", Max = "100", Command = "npc_scene_loop"})
    CPanel:AddControl ("CheckBox", { Label = "Allow to apply scene multiple times", Command = "npc_scene_multiple" })
    CPanel:AddControl ("CheckBox", { Label = "Render actor names", Command = "npc_scene_render" })
    CPanel:Help       ("")
    CPanel:AddControl ("Button" , { Text  = "List Scenes", Command = "npc_scene_list" })
end

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

local modifiedEntsTable = {}
--[[
    modifiedEntsTable[index] = ent -- ent index = ent object

    In ent we have the npcscene field, like this:
 
    ent.npcscene = {
        active = int        -- 1/0 if the scene is/isn't running
        index  = int,       -- ent index
        loop   = int,       -- how many times the scene is going to repeat
        scene  = string,    -- scene path
        name   = string,    -- actor name
        key    = string,    -- keyboard key association
    }
]]

-- Play a scene
local function StartScene(ent)
    if CLIENT then return end

    ent.npcscene.active = 1

    -- Play the scene and get its lenght
    local lenght = ent:PlayScene(ent.npcscene.scene) 

    -- Set the next loops
    if ent.npcscene.loop != 0 then
        local index = ent.npcscene.index

        timer.Create(tostring(ent) .. index, lenght, ent.npcscene.loop, function()
            -- Invalid ent, stop the loop
            if not ent:IsValid() then
                modifiedEntsTable[index] = nil
                timer.Stop(tostring(ent) .. index)
            -- Last loop
            elseif ent.npcscene.loop == 0 then
                modifiedEntsTable[index] = nil
                ent.npcscene.active = 0
                timer.Stop(tostring(ent) .. index)
            -- An execution in the sequence, there are more to do
            else
                ent:PlayScene(ent.npcscene.scene)
                ent.npcscene.loop = ent.npcscene.loop - 1
            end
        end)
    end
end

-- Remove our modifications from the npc
local function ReloadEntity(ply, ent)
    if CLIENT then return end

    -- Use the duplicator to reset the states and create an effect
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

-- Render NPC names over their heads
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

                if ent.npcscene.actor != "" and LocalPlayer():GetPos():Distance(ent:GetPos()) < 300 then
                    draw.DrawText(ent.npcscene.actor, "TargetID", screenPos.x - string.len(ent.npcscene.actor) * 4, screenPos.y - 15, Color(255, 255, 255, 255))
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
    -- Play a scene by key 
    net.Receive("npc_scene_play", function()
        local ent = net.ReadEntity()
        local multiple = net.ReadInt(2)

        if ent.npcscene.active == 0 or multiple == 1 then
            StartScene(ent)
        end
    end)
end

if CLIENT then
    -- Receive a table with modified entities to add to modifiedEntsTable
    net.Receive("npc_scene_set_ent_table", function()
        local entsTable = net.ReadTable()
        
        for _,modifiedEnt in ipairs(entsTable) do
            if not modifiedEnt.npcscene then continue end

            modifiedEnt.ent.npcscene = modifiedEnt.npcscene       
            table.insert(modifiedEntsTable, modifiedEnt.ent.npcscene and modifiedEnt.ent.npcscene.index, modifiedEnt.ent)
        end
    end)

    -- Set a key association
    net.Receive("npc_scene_hook_key", function(_, ply)
        local ent = net.ReadEntity()
        local index = ent.npcscene.index
        local hookName = "npc_scene" .. index

        if hook.GetTable()["Tick"][hookName] then
            return
        end

        hook.Add("Tick", hookName, function()
            -- NPC is gone
            if not ent:IsValid() then
                modifiedEntsTable[index] = nil
                hook.Remove("Tick", hookName)
            -- Play scene
            elseif input.IsKeyDown(ent.npcscene.key) then
                net.Start("npc_scene_play")
                    net.WriteEntity(ent)
                    net.WriteInt(GetConVar("npc_scene_multiple"):GetInt(), 2)
                net.SendToServer()
            end
        end)
    end)
end

-- --------------
-- FILES
-- --------------

local sceneListPanel
local ctrl

-- Scan for .vcds and folders in a folder
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

-- Initialize the scenes list
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

-- Set the scenes list panel
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

-- --------------
-- TOOLGUN
-- --------------

local function toolGunChecks(tr)
    -- Check if we're modifying a NPC
    if not (tr.Hit and tr.Entity and tr.Entity:IsValid() and tr.Entity:IsNPC()) then
        return false
    end

    return true
end

-- Play a scene
function TOOL:LeftClick(tr)
    if not toolGunChecks(tr) then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()
    local ent = tr.Entity
    local scene = string.gsub(self:GetClientInfo("scene"), ".vcd", "")
    local actor = ""
    local multiple = self:GetClientNumber("multiple")

    -- Checks if there's a scene applied
    if ent.npcscene then
        -- Apply the scene on top scene if it's configured to do so
        if multiple == 1 and ent.npcscene.scene == scene then
            StartScene(ent)

            return true
        end

        -- Get the actor name if there's one
        if ent.npcscene.actor then
            actor = ent.npcscene.actor
        end

        -- Reload the scenes by deleting the loops and reloading the NPCs
        if ent.npcscene.active == 1 and multiple == 0 then
            timer.Stop(tostring(ent) .. ent.npcscene.index)
            ent = ReloadEntity(ply, ent)
        end
    end

    -- Get the scene configuration and set it
    local sceneData = {
        active = 0,
        index  = ent:EntIndex(),
        loop   = self:GetClientNumber("loop"),
        scene  = scene,
        actor   = actor,
        key    = self:GetClientNumber("key"),
    }

    ent.npcscene = sceneData

    -- Store the modified entity in modifiedEntsTable
    table.insert(modifiedEntsTable, ent:EntIndex(), ent)

    net.Start("npc_scene_set_ent_table")
        net.WriteTable({ { ent = ent, npcscene = ent.npcscene } })
    net.Send(ply)

    -- Play the scene
    if ent.npcscene.key == 0 then
        StartScene(ent)
    -- Prepare the scene to be played by key
    else
        net.Start("npc_scene_hook_key")
            net.WriteEntity(ent)
        net.Send(ply)
    end

    return true
end

-- Set an actor name
function TOOL:RightClick(tr)
    if not toolGunChecks(tr) then return false end
    if CLIENT then return true end

    local ent = tr.Entity
    local actor = self:GetClientInfo("actor")

    -- Set the name
    ent:SetName(actor)

    -- Add the name to the entity
    if not ent.npcscene then
        ent.npcscene = {}
        ent.npcscene.index  = ent:EntIndex()
    end

    ent.npcscene.actor = actor

    -- Store the modified entity in modifiedEntsTable
    table.insert(modifiedEntsTable, ent:EntIndex(), ent)

    for _,aPly in ipairs(player.GetHumans()) do
        net.Start("npc_scene_set_ent_table")
            net.WriteTable({ { ent = ent, npcscene = ent.npcscene } })
        net.Send(aPly)
    end

    return true
end

-- Clear modifications
function TOOL:Reload(tr)
    if not toolGunChecks(tr) then return false end

    local ent = tr.Entity

    -- Stop any loops and reload the NPC
    if ent.npcscene then 
        if SERVER then
            if ent.npcscene.actor then
                ent:SetName("")
            end

            timer.Stop(tostring(ent) .. ent.npcscene.index)
            ReloadEntity(self:GetOwner(), ent)
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

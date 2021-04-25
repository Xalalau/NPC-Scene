--[[
    NPC Scene - by Xalalau Xubilozo

    MIT License 2021
]]

-- --------------
-- Base
-- --------------

TOOL.Category = "Poser"
TOOL.Name = "#Tool.npc_scene.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar["scene"] = "scenes/npc/Gman/gman_intro"
TOOL.ClientConVar["actor"] = "Alyx"
TOOL.ClientConVar["loop"] = 0
TOOL.ClientConVar["key"] = 0
TOOL.ClientConVar["start"] = 0
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

-- --------------
-- Net
-- --------------

if SERVER then
    util.AddNetworkString("npc_scene_hook_key")
    util.AddNetworkString("npc_scene_play")
    util.AddNetworkString("npc_scene_render_actor")

    net.Receive("npc_scene_play", function(_, ply)
        NPCS:PlayScene(ply, net.ReadInt(16))
    end)
end
    
if CLIENT then
    net.Receive("npc_scene_hook_key", function()
        NPCS:SetKey(net.ReadInt(16))
    end)

    net.Receive("npc_scene_render_actor", function()
        NPCS:RenderActorName(net.ReadInt(16))
    end)
end

-- --------------
-- General
-- --------------

-- Share the scene values between server and client
function NPCS:SetNWVars(npc, sceneData)
    if sceneData.active then npc:SetNWBool("npcscene_active", sceneData.active) end
    if sceneData.index then npc:SetNWInt("npcscene_index", sceneData.index) end
    if sceneData.loop then npc:SetNWInt("npcscene_loop", sceneData.loop) end
    if sceneData.path then npc:SetNWString("npcscene_path", sceneData.path) end
    if sceneData.actor then npc:SetNWString("npcscene_actor", sceneData.actor) end
    if sceneData.key then npc:SetNWInt("npcscene_key", sceneData.key) end
end

-- Set a key association
function NPCS:SetKey(index)
    if SERVER then return end

    local npc = ents.GetByIndex(index)
    local hookName = "npc_scene" .. index

    -- Don't recreate the hook for nothing
    if hook.GetTable()["Tick"][hookName] then
        return
    end

    hook.Add("Tick", hookName, function()
        -- NPC is gone
        if not npc:IsValid() then
            hook.Remove("Tick", hookName)
        -- Play scene
        elseif input.IsKeyDown(npc:GetNWInt("npcscene_key")) then
            net.Start("npc_scene_play")
                net.WriteInt(npc:EntIndex(), 16)
            net.SendToServer()
        end
    end)
end

-- Play a scene
function NPCS:PlayScene(ply, index)
    if CLIENT then return end

    local multiple = ply:GetInfo("npc_scene_multiple") == "1" and true or false
    local npc = ents.GetByIndex(index)

    -- When a animation is running only start more animations if the "multiple" checkbox is checked
    if npc:GetNWBool("npcscene_active") and not multiple then return end

    npc:SetNWBool("npcscene_active", true)

    -- Play the scene and get its lenght
    local lenght = npc:PlayScene(npc:GetNWString("npcscene_path")) 

    if not lenght then return end

    -- Set the next loops
    if npc:GetNWInt("npcscene_loop") > 0 then
        local index = npc:EntIndex()

        timer.Create(tostring(npc) .. index, lenght, npc:GetNWInt("npcscene_loop"), function()
            -- Invalid ent, stop the loop
            if not npc:IsValid() then
                timer.Stop(tostring(npc) .. index)
            -- Last loop
            elseif npc:GetNWInt("npcscene_loop") == 0 then
                npc:SetNWBool("npcscene_active", false)
                timer.Stop(tostring(npc) .. index)
            -- An execution in the sequence, there are more to do
            else
                npc:PlayScene(npc:GetNWString("npcscene_path"))
                npc:SetNWInt("npcscene_loop", npc:GetNWInt("npcscene_loop") - 1)
            end
        end)
    -- Set the animation as finished
    else
        timer.Simple(lenght, function()
            npc:SetNWBool("npcscene_active", false)
        end)
    end
end

-- Remove our modifications from the npc
function NPCS:ReloadNPC(ply, npc, removeName)
    if CLIENT then return end

    local dup = {}
    local name = not removeName and npc.RenderOverride and npc:GetName()

    -- Change the entity
    local newNpc = duplicator.CreateEntityFromTable(ply, duplicator.CopyEntTable(npc))
    SafeRemoveEntity(npc)

    -- Add undo
    undo.Create("NPC")
        undo.AddEntity(newNpc)
        undo.SetPlayer(ply)
    undo.Finish()

    -- Reapply the name
    if name then
        local sceneData = {
            index = newNpc:EntIndex(),
            actor = name
        }

        newNpc.RenderOverride = true
        newNpc:SetName(name)
        self:SetNWVars(newNpc, sceneData)

        timer.Simple(0.5, function()
            net.Start("npc_scene_render_actor")
                net.WriteInt(sceneData.index, 16)
            net.Send(ply)
        end)
    end

    return newNpc
end

-- Render NPC names over their heads
function NPCS:RenderActorName(index)
    if SERVER then return end

    local npc = ents.GetByIndex(index)

    npc.RenderOverride = function(self)
        self:DrawModel()

        if GetConVar("npc_scene_render"):GetBool() then
            -- The text to display
            local text = self:GetNWString("npcscene_actor")

            if not text then return end

            if LocalPlayer():GetPos():Distance(self:GetPos()) > 300 then return end

            -- Use model bounds to make the text appear just above the npc
            local mins, maxs = self:GetModelBounds()
            local pos = self:GetPos() + Vector(0, 0, maxs.z + 7)
            local scale = 0.4

            -- The angle
            local ang = Angle(0, EyeAngles().y + 90, 90)
            ang:RotateAroundAxis(Vector(0, 0, 1), 180)

            -- Draw
            cam.Start3D2D(pos, ang, scale)
                draw.DrawText(text, "TargetID", 0, 0, color_white, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end
end

-- Scan for .vcds and folders in a folder
function NPCS:CreateNodes(parentNode, parentDir, sceneList)
    if SERVER then return end

    local folders, files = {}, {}

    for k, item in pairs(sceneList) do
        if istable(item) then
            local tab = { [k] = item }
            folders[k] = tab
        else
            table.insert(files, item)
        end
    end

    for _, item in SortedPairs(folders) do
        for folderName, folder in pairs(item) do
            local node = parentNode:AddNode(folderName)

            node.DoClick = function()
                node:SetExpanded(not node:GetExpanded())
            end

            self:CreateNodes(node, parentDir .. folderName .. "/", folder)
        end
    end

    for _, fileName in pairs(files) do
        local node = parentNode:AddNode(fileName)

        node:SetIcon("icon16/page.png")
        node.DoClick = function() RunConsoleCommand("npc_scene_scene", "scenes/" .. parentDir .. fileName) end
    end
end

-- Scan for .vcds and folders in a folder
function NPCS:ScanDir(parentDir, foundScenes)
    if SERVER then return end

    if not foundScenes then foundScenes = {} end

    local files, dirs = file.Find(parentDir .. "*", "MOD")

    for _, dirName in ipairs(dirs) do
        foundScenes[dirName] = {}
        self:ScanDir(parentDir .. dirName .. "/", foundScenes[dirName])
    end

    for _, fileName in ipairs(files) do
        if string.GetExtensionFromFilename(fileName) == "vcd" then
            table.insert(foundScenes, fileName)
        end
    end 

    return foundScenes
end

-- Build a scene list checking for mounted games and using our pre-made scene tables
function NPCS:BuildPremandeSceneList()
    local premadeSceneList = {}

    for _, game in ipairs(engine.GetGames()) do
        if game.mounted and self.premadeSceneList[game.title] or game.title == "Half-Life 2" then
            table.Merge(premadeSceneList, self.premadeSceneList[game.title])
        end
    end

    return premadeSceneList
end

-- Open the scenes list
local initialized
local sceneListPanel
local function ListScenes()
    if SERVER then return end

    if not initialized then
        local width, height = 300, 700
        local padding = 35

        sceneListPanel = vgui.Create("DFrame")
            sceneListPanel:SetTitle("Scenes")
            sceneListPanel:SetSize(width, height)
            sceneListPanel:SetPos(ScrW() - width - padding, padding)
            sceneListPanel:SetDeleteOnClose(false)
            sceneListPanel:SetVisible(false)

        local ctrl = vgui.Create("DTree", sceneListPanel)
            ctrl:SetPadding(5)
            ctrl:SetSize(width, height - 25)
            ctrl:SetPos(0, 25)
            ctrl:SetBackgroundColor(Color(255, 255, 255, 255))

        local node = ctrl:AddNode("Scenes! (click one to select)")
            local premadeSceneList = NPCS:BuildPremandeSceneList()
            local foundSceneList = NPCS:ScanDir("scenes/")
            table.Merge(foundSceneList, premadeSceneList)
            NPCS:CreateNodes(node, "", foundSceneList)
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
-- Toolgun
-- --------------

local function toolGunChecks(tr, anyEnt)
    -- Check if we're modifying a NPC
    if not (tr.Hit and tr.Entity and tr.Entity:IsValid() and (anyEnt or tr.Entity:IsNPC())) then
        return false
    end

    return true
end

-- Play a scene
function TOOL:LeftClick(tr)
    if not toolGunChecks(tr) then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()
    local npc = tr.Entity
    local path  = string.gsub(self:GetClientInfo("scene"), ".vcd", "")
    local actor
    local multiple = self:GetClientNumber("multiple") == 1 and true or false

    -- Checks if there's a scene applied
    if npc:GetNWInt("npcscene_index") > 0 then
        -- Apply the scene on top scene if it's configured to do so
        if multiple and npc:GetNWString("npcscene_path") == path then
            NPCS:PlayScene(ply, npc:GetNWInt("npcscene_index"))

            return true
        end

        -- Get the actor name if there's one
        if npc:GetNWString("npcscene_actor") ~= "" then
            actor = npc:GetNWString("npcscene_actor")
        end

        -- Reload the scenes by deleting the loops and reloading the NPCs
        if npc:GetNWBool("npcscene_active") and not multiple then
            timer.Stop(tostring(npc) .. npc:GetNWInt("npcscene_index"))
            npc = NPCS:ReloadNPC(ply, npc)
        end
    end

    -- Get the scene configuration and set it
    local sceneData = {
        active = false,
        index  = npc:EntIndex(),
        loop   = self:GetClientNumber("loop"),
        path   = path,
        actor  = actor,
        key    = self:GetClientNumber("key"),
        start  = self:GetClientNumber("start") == 1 and true or false,
    }

    NPCS:SetNWVars(npc, sceneData)

    -- Prepare the scene to be played by key
    if sceneData.key != 0 then
        net.Start("npc_scene_hook_key")
            net.WriteInt(sceneData.index, 16)
        net.Send(ply)
    end
    
    -- Play the scene
    if sceneData.start or sceneData.key == 0 then
        NPCS:PlayScene(ply, sceneData.index)
    end

    return true
end

-- Set an actor name
function TOOL:RightClick(tr)
    if not toolGunChecks(tr, true) then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()    
    local npc = tr.Entity

    -- Add the name to the entity
    local sceneData = {
        index = npc:GetNWInt("npcscene_index") == 0 and npc:EntIndex() or nil,
        actor = self:GetClientInfo("actor")
    }

    npc:SetName(sceneData.actor)

    NPCS:SetNWVars(npc, sceneData)

    -- Render the name on the client
    npc.RenderOverride = true
    net.Start("npc_scene_render_actor")
        net.WriteInt(sceneData.index or npc:GetNWInt("npcscene_index"), 16)
    net.Send(ply)

    return true
end

-- Clear modifications
function TOOL:Reload(tr)
    if not toolGunChecks(tr, true) then return false end

    local ply = self:GetOwner()
    local npc = tr.Entity

    -- Stop any loops and reload the NPC
    if npc:GetNWInt("npcscene_index") > 0 then
        if SERVER then
            timer.Stop(tostring(npc) .. npc:GetNWInt("npcscene_index"))
            NPCS:ReloadNPC(ply, npc, true)
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
    CPanel:AddControl ("CheckBox", { Label = "Start On (When using a key)", Command = "npc_scene_start" })
    CPanel:AddControl ("CheckBox", { Label = "Render actor names", Command = "npc_scene_render" })
    CPanel:Help       ("")
    CPanel:AddControl ("Button" , { Text  = "List Scenes", Command = "npc_scene_list" })
end

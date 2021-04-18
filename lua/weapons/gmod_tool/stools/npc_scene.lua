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
    util.AddNetworkString("npc_scene_hook_key")
    util.AddNetworkString("npc_scene_play")
end

-- Share the scene values between server and client
local function SetNWVars(npc, sceneData)
    if sceneData.active then npc:SetNWBool("npcscene_active", sceneData.active) end
    if sceneData.index then npc:SetNWInt("npcscene_index", sceneData.index) end
    if sceneData.loop then npc:SetNWInt("npcscene_loop", sceneData.loop) end
    if sceneData.path then npc:SetNWString("npcscene_path", sceneData.path) end
    if sceneData.actor then npc:SetNWString("npcscene_actor", sceneData.actor) end
    if sceneData.key then npc:SetNWInt("npcscene_key", sceneData.key) end
end

-- Play a scene
local function PlayScene(npc)
    if CLIENT then return end

    npc:SetNWBool("npcscene_active", true)

    -- Play the scene and get its lenght
    local lenght = npc:PlayScene(npc:GetNWString("npcscene_path")) 

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
    end
end

-- Remove our modifications from the npc
local function ReloadNPC(ply, npc)
    if CLIENT then return end

    -- Use the duplicator to reset the states and create an effect
    local dup = {}

    dup = duplicator.Copy(npc)
    SafeRemoveEntity(npc)
    duplicator.Paste(ply, dup.Entities, dup.Constraints)

    npc = ply:GetEyeTrace().Entity

    undo.Create("NPC")
        undo.AddEntity(npc)
        undo.SetPlayer(ply)
    undo.Finish()

    return npc
end

-- Render NPC names over their heads
local function RenderActorName(npc)
    if SERVER then return end

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
                draw.DrawText(text, "TargetID", 0, 0, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end
end

-- --------------
-- NET FUNCTIONS
-- --------------

if SERVER then
    -- Play a scene by key 
    net.Receive("npc_scene_play", function()
        local index = net.ReadInt(16)
        local multiple = net.ReadInt(2)
        local npc = ents.GetByIndex(index)

        if not npc:GetNWBool("npcscene_active") or multiple == 1 then
            PlayScene(npc)
        end
    end)
end

if CLIENT then
    -- Set a key association
    net.Receive("npc_scene_hook_key", function(_, ply)
        local index = net.ReadInt(16)
        local npc = ents.GetByIndex(index)
        local hookName = "npc_scene" .. index

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
    local npc = tr.Entity
    local path  = string.gsub(self:GetClientInfo("scene"), ".vcd", "")
    local actor
    local multiple = self:GetClientNumber("multiple") == 1 and true or false

    -- Checks if there's a scene applied
    if npc:GetNWInt("npcscene_index") then
        -- Apply the scene on top scene if it's configured to do so
        if multiple and npc:GetNWString("npcscene_path") == path then
            PlayScene(npc)

            return true
        end

        -- Get the actor name if there's one
        if npc:GetNWString("npcscene_actor") then
            actor = npc:GetNWString("npcscene_actor")
        end

        -- Reload the scenes by deleting the loops and reloading the NPCs
        if npc:GetNWBool("npcscene_active") and not multiple then
            timer.Stop(tostring(npc) .. npc:GetNWInt("npcscene_index"))
            npc = ReloadNPC(ply, npc)
        end
    end

    -- Get the scene configuration and set it
    local sceneData = {
        active = false,
        index  = npc:EntIndex(),
        loop   = self:GetClientNumber("loop"),
        path  = path,
        actor   = actor,
        key    = self:GetClientNumber("key"),
    }

    SetNWVars(npc, sceneData)

    -- Play the scene
    if sceneData.key == 0 then
        PlayScene(npc)
    -- Prepare the scene to be played by key
    else
        net.Start("npc_scene_hook_key")
            net.WriteInt(npc:EntIndex(), 16)
        net.Send(ply)
    end

    return true
end

-- Set an actor name
function TOOL:RightClick(tr)
    if not toolGunChecks(tr) then return false end

    local npc = tr.Entity

    -- Render the name on the client
    RenderActorName(npc)

    if CLIENT then return true end

    -- Add the name to the entity
    local sceneData = {
        index = not npc:GetNWInt("npcscene_index") and npc:EntIndex() or nil,
        actor = self:GetClientInfo("actor")
    }

    npc:SetName(sceneData.actor)

    SetNWVars(npc, sceneData)

    return true
end

-- Clear modifications
function TOOL:Reload(tr)
    if not toolGunChecks(tr) then return false end

    local ply = self:GetOwner()
    local npc = tr.Entity

    -- Stop any loops and reload the NPC
    if npc:GetNWInt("npcscene_index") then 
        if SERVER then
            timer.Stop(tostring(npc) .. npc:GetNWInt("npcscene_index"))
            ReloadNPC(ply, npc)
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

-- ServerScriptService/HubDialogueRouter.server.lua
--!strict
-- 클라 RF_RequestDialogue(characterKey) → 서버 검증 → EV_HubIntroDialogue:FireClient(player, {characterKey})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Remotes 보장
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRF(name: string): RemoteFunction
	local rf = Remotes:FindFirstChild(name) :: RemoteFunction
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = Remotes
	end
	return rf
end

local function ensureRE(name: string): RemoteEvent
	local ev = Remotes:FindFirstChild(name) :: RemoteEvent
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = Remotes
	end
	return ev
end

local RF_RequestDialogue = ensureRF("RF_RequestDialogue")
local EV_HubIntroDialogue = ensureRE("EV_HubIntroDialogue")

local ALLOW_KEYS = {
	turtle = true, shark = true, dolphin = true, seahorse = true, crab = true
}

local lastCallAt: {[number]: number} = {}

RF_RequestDialogue.OnServerInvoke = function(player: Player, characterKey: string)
	if type(characterKey) ~= "string" or not ALLOW_KEYS[characterKey] then
		warn("[HubDialogueRouter] invalid key from", player.Name, characterKey)
		return false
	end

	local now = os.clock()
	local prev = lastCallAt[player.UserId] or 0
	if now - prev < 0.5 then
		return false
	end
	lastCallAt[player.UserId] = now

	EV_HubIntroDialogue:FireClient(player, { characterKey })
	return true
end

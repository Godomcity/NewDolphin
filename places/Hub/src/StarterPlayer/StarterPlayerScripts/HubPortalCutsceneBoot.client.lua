-- StarterPlayerScripts/HubPortalCutsceneBoot.client.lua
--!strict
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Remotes
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local RE_Cutscene     = Remotes:WaitForChild("Quiz_Cutscene")
local RE_CutsceneDone = Remotes:WaitForChild("Quiz_CutsceneDone")

-- Module
local HubFX = require(ReplicatedStorage:WaitForChild("Modules")
	:WaitForChild("Cutscene"):WaitForChild("HubPortalCutscene"))

RE_Cutscene.OnClientEvent:Connect(function(payload)
	-- 다른 타입은 무시 (portal_open / portal_spawn 등은 CutsceneBoot에서 처리)
	if not payload or (payload.type ~= "hub_portal" and payload.type ~= "hub_portal_open") then
		return
	end

	-- 컷씬 재생 (FX + 하이라이트 + 라이트 등)
	local ok = pcall(function()
		HubFX.play(payload)
	end)

	-- 🔹 duration 만큼 기다렸다가 ACK
	--    HubPortalCutscene.lua의 기본 dur(3.0)과 맞춰서 사용
	local dur = tonumber(payload.duration) or 3.0

	task.delay(math.max(dur + 0.05, 0.2), function()
		RE_CutsceneDone:FireServer({
			stage = tonumber(payload.stage) or 1
		})
	end)
end)

print("[HubPortalCutsceneBoot] READY (hub_portal 전용 컷씬 → 끝나고 ACK)")

-- StarterGui/TeleportingGui/LocalScript
--!strict

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent :: ScreenGui

-- 텔레포트 대기 중에도 안 사라지게(로비에서만 유지 목적이면 true 추천)
gui.ResetOnSpawn = false
gui.Enabled = true  -- 기본은 꺼두고, 서버가 show 보낼 때만 켜기

local Remotes = RS:WaitForChild("Remotes")
local RE = Remotes:WaitForChild("RE_LobbyResume_TeleportingGui") :: RemoteEvent

local function setVisible(on: boolean)
	gui.Enabled = on
	-- 원하면 아예 제거도 가능:
	-- if not on then gui:Destroy() end
end

RE.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	local mode = payload.mode
	if mode == "show" then
		setVisible(true)
	elseif mode == "hide" then
		setVisible(false)
	end
end)

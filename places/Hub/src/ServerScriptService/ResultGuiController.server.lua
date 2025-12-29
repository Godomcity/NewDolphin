-- ServerScriptService/ResultGuiController.server.lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))

local Permissions = require(game.ServerScriptService:WaitForChild("Modules"):WaitForChild("Permissions"))

local RE_CloseAllResults = Net.ensureRE("Result_CloseAll")

RE_CloseAllResults.OnServerEvent:Connect(function(player: Player)
	-- ✅ 선생님만 허용
	if not Permissions.requireTeacher(player) then
		return
	end

	RE_CloseAllResults:FireAllClients()
end)

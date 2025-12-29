-- ReplicatedStorage/Modules/CameraReset.lua
--!strict
-- 컷씬 시작 직전에 1번만 쓰는 “카메라 초기화”

local Players = game:GetService("Players")

local M = {}

local function getHumanoid(): Humanoid?
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

function M.ResetOnce(tag: string?)
	local cam = workspace.CurrentCamera
	if not cam then return end

	local hum = getHumanoid()
	cam.CameraType = Enum.CameraType.Custom
	if hum then
		cam.CameraSubject = hum
	end
	cam.FieldOfView = 70

	if tag then
		print(("[CameraReset] ResetOnce (%s)"):format(tag))
	end
end

return M

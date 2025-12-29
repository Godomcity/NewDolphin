--!strict
-- TeacherLockClient.client.lua
-- 서버에서 잠금 명령이 오면 PlayerLock2로 "이동만" 잠금(카메라 제외)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

local Roles = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Roles"))
local PlayerLock2 = require(ReplicatedStorage.Modules.PlayerLock)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Lock = Remotes:WaitForChild("Teacher_ClientLock")

RE_Lock.OnClientEvent:Connect(function(shouldLock: boolean)
-- 선생님은 항상 제외
        local role = lp:GetAttribute("userRole")
        if Roles.isTeacherRole(role) then return end

        local isTeacherAttr = lp:GetAttribute("isTeacher")
        if typeof(isTeacherAttr) == "boolean" and isTeacherAttr then
                return
        end

	if shouldLock then
		PlayerLock2.Lock({
			freezeMovement = true,
			freezeCamera = false,
			disableInput = false,
		})
	else
		PlayerLock2.Unlock()
	end
end)

--!strict
-- TeacherLockClient.client.lua
-- 서버에서 잠금 명령이 오면 PlayerLock으로 "이동만" 잠금(카메라 제외)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

local StageRolePolicy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StageRolePolicy"))
local PlayerLock = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerLock"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Lock = Remotes:WaitForChild("Teacher_ClientLock")

local currentIsTeacher = false

-- StageRolePolicy.ObserveTeacher는 역할 복제 대기, 속성 변경, 서버 브로드캐스트를 모두 포함하므로
-- 이 함수 하나로 교사 상태를 안정적으로 관찰할 수 있습니다.
StageRolePolicy.ObserveTeacher(lp, function(isTeacher: boolean, reason: string?)
	currentIsTeacher = isTeacher
	print(("[TeacherLockClient] Teacher status updated: %s (reason: %s)"):format(tostring(isTeacher), reason or "n/a"))
end, { timeoutSec = 15 })

RE_Lock.OnClientEvent:Connect(function(shouldLock: boolean)
        -- 선생님은 항상 제외
	if currentIsTeacher then
		-- 혹시 잠겨있을 수 있는 상태를 대비해, 선생님은 항상 Unlock을 호출해 풀어줍니다.
		PlayerLock.Unlock()
		return
	end

        if shouldLock then
		PlayerLock.Lock({
                        freezeMovement = true,
                        freezeCamera = false,
                        disableInput = false,
                })
        else
		PlayerLock.Unlock()
        end
end)

print("[TeacherLockClient] READY")

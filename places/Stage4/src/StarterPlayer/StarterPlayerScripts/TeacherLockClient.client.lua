--!strict
-- TeacherLockClient.client.lua
-- 서버에서 잠금 명령이 오면 PlayerLock2로 "이동만" 잠금(카메라 제외)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

local StageRolePolicy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StageRolePolicy"))
local PlayerLock2 = require(ReplicatedStorage.Modules.PlayerLock)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Lock = Remotes:WaitForChild("Teacher_ClientLock")

local currentIsTeacher = false
local teacherDisconnect: (() -> ())? = nil
local teacherBroadcastDisconnect: (() -> ())? = nil

if StageRolePolicy.WaitForRoleReplication(lp, 12) then
        currentIsTeacher = StageRolePolicy.IsTeacher(lp)
end

teacherDisconnect = StageRolePolicy.ObserveTeacher(lp, function(isTeacher: boolean)
        currentIsTeacher = isTeacher

        if isTeacher then
                if teacherDisconnect then
                        teacherDisconnect()
                        teacherDisconnect = nil
                end
                if teacherBroadcastDisconnect then
                        teacherBroadcastDisconnect()
                        teacherBroadcastDisconnect = nil
                end
        end
end, { timeoutSec = 15 })

local observeBroadcast = StageRolePolicy and StageRolePolicy.ObserveTeacherBroadcast
if observeBroadcast then
        teacherBroadcastDisconnect = observeBroadcast(lp, function(_, isTeacher)
                if typeof(isTeacher) == "boolean" then
                        currentIsTeacher = isTeacher

                        if isTeacher and teacherBroadcastDisconnect then
                                teacherBroadcastDisconnect()
                                teacherBroadcastDisconnect = nil
                        end
                end
        end, 15)
end

RE_Lock.OnClientEvent:Connect(function(shouldLock: boolean)
        -- 선생님은 항상 제외
        if currentIsTeacher then return end

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

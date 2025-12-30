-- ReplicatedStorage/Modules/StageRolePolicy.lua
--!strict

<<<<<<< HEAD
print("변경")

=======
local Players = game:GetService("Players")
>>>>>>> a022e90620db0dfa7b96c0988191c328f6fa45d2
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}

local Roles = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Roles"))

local TeacherRoleEvent: RemoteEvent? = nil
local TeacherRoleConn: RBXScriptConnection? = nil

local function resolveTeacherRoleEvent(timeoutSec: number?): RemoteEvent?
        if TeacherRoleEvent and TeacherRoleEvent.Parent then
                return TeacherRoleEvent
        end

        local timeout = timeoutSec or 5

        local remotes = ReplicatedStorage:WaitForChild("Remotes", timeout)
        if not remotes then
                return nil
        end

        local ev = remotes:WaitForChild("TeacherRoleUpdated", timeout)
        if ev and ev:IsA("RemoteEvent") then
                TeacherRoleEvent = ev
                return ev
        end

        return nil
end

TeacherRoleEvent = resolveTeacherRoleEvent()

local function isTeacherByRole(plr: Player): boolean
        local role = plr:GetAttribute("userRole")
        if Roles.isTeacherRole(role) then
                return true
        end

        local isTeacherAttr = plr:GetAttribute("isTeacher")
        if typeof(isTeacherAttr) == "boolean" then
                return isTeacherAttr
        end

        return false
end

function M.IsTeacher(plr: Player): boolean
        if not plr or not plr.UserId then
                return false
        end

        return isTeacherByRole(plr)
end

local function hasRoleAttributes(plr: Player): boolean
        if not plr then
                return false
        end

        local roleAttr = plr:GetAttribute("userRole")
        local isTeacherAttr = plr:GetAttribute("isTeacher")

        return roleAttr ~= nil or typeof(isTeacherAttr) == "boolean"
end

local function applyTeacherPayload(plr: Player, role: string?, isTeacher: boolean?)
        if role and plr:GetAttribute("userRole") ~= role then
                plr:SetAttribute("userRole", role)
        end

        local currentTeacher = plr:GetAttribute("isTeacher")
        if typeof(isTeacher) == "boolean" and (typeof(currentTeacher) ~= "boolean" or currentTeacher ~= isTeacher) then
                plr:SetAttribute("isTeacher", isTeacher)
        end
end

local function ensureTeacherBroadcastListener()
        if TeacherRoleConn or not RunService:IsClient() then
                return
        end

        local event = resolveTeacherRoleEvent()
        if not event then
                return
        end

        local lp = Players.LocalPlayer
        TeacherRoleConn = event.OnClientEvent:Connect(function(userId: number, role: string?, isTeacher: boolean?)
                if not lp or lp.UserId ~= userId then
                        return
                end

                applyTeacherPayload(lp, role, isTeacher)
        end)
end

ensureTeacherBroadcastListener()

local function waitForTeacherBroadcast(plr: Player, timeout: number): boolean
        if not RunService:IsClient() then
                return false
        end

        ensureTeacherBroadcastListener()

        if timeout <= 0 then
                return false
        end

        local event = resolveTeacherRoleEvent(timeout)
        if not event then
                return false
        end

        local deadline = os.clock() + timeout
        local received = false
        local conn: RBXScriptConnection?

        conn = event.OnClientEvent:Connect(function(userId: number, role: string?, isTeacher: boolean?)
                if not plr or plr.UserId ~= userId then
                        return
                end

                received = true

                applyTeacherPayload(plr, role, isTeacher)
        end)

        while os.clock() < deadline and not received do
                if hasRoleAttributes(plr) then
                        break
                end
                task.wait(0.25)
        end

        if conn then
                conn:Disconnect()
        end

        return received
end

function M.ObserveTeacherBroadcast(plr: Player, callback: (string?, boolean?) -> (), timeoutSec: number?)
        if not RunService:IsClient() then
                return nil
        end

        local event = resolveTeacherRoleEvent(timeoutSec)
        if not event then
                return nil
        end

        local conn: RBXScriptConnection
        conn = event.OnClientEvent:Connect(function(userId: number, role: string?, isTeacher: boolean?)
                if not plr or plr.UserId ~= userId then
                        return
                end

                applyTeacherPayload(plr, role, isTeacher)
                callback(role, isTeacher)
        end)

        return function()
                conn:Disconnect()
        end
end

-- userRole/isTeacher 속성이 복원될 때까지 대기
function M.WaitForRoleReplication(plr: Player, timeoutSec: number?): boolean
        local timeout = timeoutSec or 10
        local deadline = os.clock() + timeout

        if hasRoleAttributes(plr) then
                return true
        end

        local remaining = deadline - os.clock()
        if remaining > 0 then
                waitForTeacherBroadcast(plr, remaining)
        end

        while os.clock() < deadline do
                if hasRoleAttributes(plr) then
                        return true
                end
                task.wait(0.25)
        end

        return hasRoleAttributes(plr)
end

-- 선생님 여부를 관찰(초기값 + 속성 변경 + 캐릭터 재스폰)하며 callback 호출
-- 반환값: 연결을 모두 끊는 함수
function M.ObserveTeacher(plr: Player, callback: (boolean, string?) -> (), opts: { timeoutSec: number? }?)
        local timeout = (opts and opts.timeoutSec) or 10

        local connections: { RBXScriptConnection } = {}

        local function disconnectAll()
                for _, conn in ipairs(connections) do
                        conn:Disconnect()
                end
                table.clear(connections)
        end

        local function fire(reason: string)
                callback(M.IsTeacher(plr), reason)
        end

        task.spawn(function()
                M.WaitForRoleReplication(plr, timeout)
                fire("(initial)")
        end)

        if RunService:IsClient() then
                local event = resolveTeacherRoleEvent(timeout)
                if event then
                        table.insert(connections, event.OnClientEvent:Connect(function(userId: number, role: string?, isTeacher: boolean?)
                                if not plr or plr.UserId ~= userId then
                                        return
                                end

                                applyTeacherPayload(plr, role, isTeacher)

                                fire("(server role broadcast)")
                        end))
                end
        end

        table.insert(connections, plr:GetAttributeChangedSignal("userRole"):Connect(function()
                fire("(userRole changed)")
        end))

        table.insert(connections, plr:GetAttributeChangedSignal("isTeacher"):Connect(function()
                fire("(isTeacher changed)")
        end))

        table.insert(connections, plr.CharacterAdded:Connect(function()
                fire("(character added)")
        end))

        return disconnectAll
end

-- 이 플레이어가 "스테이지 클라이언트 흐름(퀴즈/컷씬/포탈)"을 스킵해야 하는지
function M.ShouldSkipStageClientFlow(plr: Player): boolean
        return M.IsTeacher(plr)
end

return M

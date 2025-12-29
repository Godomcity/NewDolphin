-- ReplicatedStorage/Modules/StageRolePolicy.lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}

local Roles = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Roles"))

local function getTeacherRoleEvent(): RemoteEvent?
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then
                return nil
        end

        local ev = remotes:FindFirstChild("TeacherRoleUpdated")
        if ev and ev:IsA("RemoteEvent") then
                return ev
        end

        return nil
end

local TeacherRoleEvent: RemoteEvent? = getTeacherRoleEvent()

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

-- userRole/isTeacher 속성이 복원될 때까지 대기
function M.WaitForRoleReplication(plr: Player, timeoutSec: number?): boolean
        local timeout = timeoutSec or 10
        local deadline = os.clock() + timeout

        if hasRoleAttributes(plr) then
                return true
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

        if RunService:IsClient() and TeacherRoleEvent then
                table.insert(connections, TeacherRoleEvent.OnClientEvent:Connect(function(userId: number, role: string?, isTeacher: boolean?)
                        if not plr or plr.UserId ~= userId then
                                return
                        end

                        fire("(server role broadcast)")
                end))
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

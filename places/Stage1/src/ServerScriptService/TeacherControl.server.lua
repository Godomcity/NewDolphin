--!strict
-- TeacherControl.server.lua
-- Stop : 선생님 제외 전원 이동 잠금/해제(클라에서 PlayerLock2 실행)
-- Spawn: 선생님 앞으로 전원 순간이동
-- + 선생님에게 "적용 인원수" 피드백 메시지 보내기

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roles = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Roles"))

local function isTeacher(plr: Player): boolean
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

-- Remotes 폴더 보장
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
        Remotes = Instance.new("Folder")
        Remotes.Name = "Remotes"
        Remotes.Parent = ReplicatedStorage
end

local function ensureRE(name: string): RemoteEvent
        local re = Remotes:FindFirstChild(name)
        if re and re:IsA("RemoteEvent") then
                return re
        end
        local n = Instance.new("RemoteEvent")
        n.Name = name
        n.Parent = Remotes
        return n
end

local RE_Stop = ensureRE("Teacher_StopAll")
local RE_Spawn = ensureRE("Teacher_SpawnAll")
local RE_ClientLock = ensureRE("Teacher_ClientLock")
local RE_Feedback = ensureRE("Teacher_Feedback")

local frozen = false

-- Stop 버튼
RE_Stop.OnServerEvent:Connect(function(sender: Player)
        if not isTeacher(sender) then return end

        frozen = not frozen

        local count = 0
        for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= sender then
                        count += 1
                        RE_ClientLock:FireClient(plr, frozen)
                end
        end

        -- 선생님 UI 토글 상태 반영(기존)
        RE_Stop:FireClient(sender, frozen)
        -- 선생님에게 피드백
        RE_Feedback:FireClient(sender, ("Stop %s (students=%d)"):format(frozen and "ON" or "OFF", count))
end)

-- Spawn 버튼
RE_Spawn.OnServerEvent:Connect(function(sender: Player)
        if not isTeacher(sender) then return end

        local tChar = sender.Character
        local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
        if not tRoot then
                RE_Feedback:FireClient(sender, "Spawn failed: teacher HumanoidRootPart missing")
                return
        end

        local baseCF = tRoot.CFrame * CFrame.new(0, 0, -6) -- 선생님 앞 6

        local count = 0
        local offset = 0
        for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= sender then
                        local c = plr.Character
                        local r = c and c:FindFirstChild("HumanoidRootPart")
                        if r then
                                count += 1
                                offset += 1
                                -- 겹치지 않게 약간씩 배열
                                r.CFrame =
                                        baseCF
                                        * CFrame.new((offset % 5) * 2 - 4, 0, math.floor(offset / 5) * 2)
                        end
                end
        end

        RE_Feedback:FireClient(sender, ("Spawned students=%d"):format(count))
end)

print("[TeacherControl] Server Ready")

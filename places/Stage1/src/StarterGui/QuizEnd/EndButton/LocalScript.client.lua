-- LocalScript @ StarterGui/QuizEnd/EndButton
--!strict
-- 선생님만 보임
-- 클릭하면 서버에 Quiz_EndRequest만 보냄
-- (정리+엔딩 컷씬+Hub 텔레포트는 서버 오케스트레이터가 처리)

local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StageRolePolicy = require(RS:WaitForChild("Modules"):WaitForChild("StageRolePolicy"))

local player     = Players.LocalPlayer
local endButton  = script.Parent
local quizEndGui = endButton:FindFirstAncestorOfClass("ScreenGui")

local Remotes     = RS:WaitForChild("Remotes")
local RE_QuizEnd  = Remotes:WaitForChild("Quiz_EndRequest") :: RemoteEvent

local currentIsTeacher = false
local teacherDisconnect: (() -> ())? = nil
local teacherBroadcastDisconnect: (() -> ())? = nil

if endButton:IsA("GuiObject") then
        endButton.Visible = false
end

local function updateTeacher(isTeacher: boolean, reason: string?)
        currentIsTeacher = isTeacher

        if endButton:IsA("GuiObject") then
                endButton.Visible = isTeacher
        end

        if isTeacher and teacherDisconnect then
                teacherDisconnect()
                teacherDisconnect = nil
        end

        if isTeacher and teacherBroadcastDisconnect then
                teacherBroadcastDisconnect()
                teacherBroadcastDisconnect = nil
        end

        if isTeacher then
                print("[QuizEnd] Teacher detected -> EndButton visible", reason)
        end
end

if StageRolePolicy.WaitForRoleReplication(player, 12) then
        updateTeacher(StageRolePolicy.IsTeacher(player), "(initial)")
end

teacherDisconnect = StageRolePolicy.ObserveTeacher(player, function(isTeacher: boolean, reason: string?)
updateTeacher(isTeacher, reason)
end, { timeoutSec = 15 })

local observeBroadcast = StageRolePolicy and StageRolePolicy.ObserveTeacherBroadcast
if observeBroadcast then
teacherBroadcastDisconnect = observeBroadcast(player, function(_, isTeacher)
if typeof(isTeacher) == "boolean" then
updateTeacher(isTeacher, "(TeacherRoleUpdated)")
end
end, 15)
end

local isClicked = false

local function onEndClicked()
        if not currentIsTeacher then return end
        if isClicked then return end
        isClicked = true

        -- 버튼 GUI 닫기(선생님 화면)
        if quizEndGui then
                quizEndGui.Enabled = false
        end

        -- ✅ 서버가:
        -- 1) 모든 참가자 QuizGui/대사UI 정리
        -- 2) 4문제/10문제 컷씬 취소
        -- 3) 엔딩 컷씬 재생
        -- 4) 컷씬 끝나면 Hub 텔레포트(세션 전체)
        RE_QuizEnd:FireServer({
                sessionId = player:GetAttribute("sessionId"),
        })
end

if endButton:IsA("GuiButton") then
        endButton.Activated:Connect(onEndClicked)
else
        endButton.MouseButton1Click:Connect(onEndClicked)
end

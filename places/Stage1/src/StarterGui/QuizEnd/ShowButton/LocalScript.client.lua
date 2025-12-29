--!strict
-- QuizEnd UI (ShowButton 아래 LocalScript)
-- ShowButton -> BackGround 슬라이드 인 (X=0 -> 2.987)
-- XButton    -> 슬라이드 아웃 (X=2.987 -> 0)
-- Spawn/Stop -> 선생님만 서버 Remote 호출
-- + 버튼 Hover/Press 시 커짐
-- + 선생님 피드백(적용 인원) 콘솔 출력
-- + 클릭 사운드 추가
-- + BackGround.Visible == true 이면 ShowButton hover/press 비활성

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local StageRolePolicy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StageRolePolicy"))
local lp = Players.LocalPlayer

local CLICK_SOUND_ID = "rbxassetid://15675059323"

local showBtn = script.Parent :: GuiButton
local bg = showBtn:WaitForChild("BackGround") :: Frame
local xBtn = bg:WaitForChild("XButton") :: GuiButton
local spawnBtn = bg:WaitForChild("SpawnButton") :: GuiButton
local stopBtn = bg:WaitForChild("StopButton") :: GuiButton

local isTeacher = false
local teacherDisconnect: (() -> ())? = nil

-- ✅ 패널 Position: 열기 X=2.987, 닫기 X=0 (Y=2.343 고정)
local Y_SCALE = 2.3
local POS_SHOW = UDim2.new(2.987, 0, Y_SCALE, 0)
local POS_HIDE = UDim2.new(0, 0, Y_SCALE, 0)

showBtn.Visible = false

local function isPanelOpen(): boolean
        return bg.Visible == true
end

local function closePanel()
        if not bg.Visible then return end

        bg.Visible = false
        bg.Position = POS_HIDE
        showBtn.Active = true
end

local function applyTeacherFlag(flag: boolean, reason: string?)
        isTeacher = flag
        showBtn.Visible = flag

        if not flag then
                closePanel()
        elseif flag and teacherDisconnect then
                teacherDisconnect()
                teacherDisconnect = nil
        end

        if flag then
                print("[QuizEnd] Teacher detected -> teacher panel enabled", reason)
        end
end

bg.Visible = false
bg.Position = POS_HIDE

if StageRolePolicy.WaitForRoleReplication(lp, 12) then
        applyTeacherFlag(StageRolePolicy.IsTeacher(lp), "(initial)")
end

teacherDisconnect = StageRolePolicy.ObserveTeacher(lp, function(flag: boolean, reason: string?)
        applyTeacherFlag(flag, reason)
end, { timeoutSec = 15 })

-- 패널 트윈
local panelTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local panelTween: Tween? = nil

local function tweenPanelTo(pos: UDim2, onDone: (() -> ())?)
        if panelTween then
                panelTween:Cancel()
                panelTween = nil
        end
        panelTween = TweenService:Create(bg, panelTweenInfo, { Position = pos })
        if onDone then
                panelTween.Completed:Once(onDone)
        end
        panelTween:Play()
end

-- ✅ 클릭 사운드(한 개 만들어서 재사용)
local function playClickSound(parent: Instance)
        local sound = parent:FindFirstChild("__ClickSound")
        if not sound then
                sound = Instance.new("Sound")
                sound.Name = "__ClickSound"
                sound.SoundId = CLICK_SOUND_ID
                sound.Volume = 0.7
                sound.PlayOnRemove = false
                sound.Parent = parent
        end
        local s = sound :: Sound
        s:Stop()
        s:Play()
end

-- ✅ 버튼 Hover/Press 효과(모든 버튼 공통)
-- isEnabledFn 이 false면 hover/press tween 자체를 무시
local function setupButtonFX(btn: GuiButton, hoverScale: number?, pressScale: number?, isEnabledFn: (() -> boolean)?)
        hoverScale = hoverScale or 1.06
        pressScale = pressScale or 0.96

        local uiScale = btn:FindFirstChildOfClass("UIScale")
        if not uiScale then
                uiScale = Instance.new("UIScale")
                uiScale.Scale = 1
                uiScale.Parent = btn
        end

        local tInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local cur: Tween? = nil

        local function canFX(): boolean
                if isEnabledFn then
                        return isEnabledFn()
                end
                return true
        end

        local function tweenScale(target: number)
                if not canFX() then
                        -- 비활성 상태면 원래 크기로 고정
                        (uiScale :: UIScale).Scale = 1
                        return
                end
                if cur then cur:Cancel() end
                cur = TweenService:Create(uiScale, tInfo, { Scale = target })
                cur:Play()
        end

        btn.MouseEnter:Connect(function() tweenScale(hoverScale :: number) end)
        btn.MouseLeave:Connect(function()
                (uiScale :: UIScale).Scale = 1
                if cur then cur:Cancel() end
        end)

        btn.MouseButton1Down:Connect(function() tweenScale(pressScale :: number) end)
        btn.MouseButton1Up:Connect(function()
                if canFX() then
                        tweenScale(hoverScale :: number)
                else
                        (uiScale :: UIScale).Scale = 1
                end
        end)
end

-- ✅ showBtn은 패널 열려있을 때 hover/press 금지
setupButtonFX(showBtn, 1.06, 0.96, function()
        return isTeacher and (not isPanelOpen())
end)

setupButtonFX(xBtn, 1.08, 0.95)
setupButtonFX(spawnBtn, 1.06, 0.96)
setupButtonFX(stopBtn, 1.06, 0.96)

-- Show / X
showBtn.Activated:Connect(function()
        if not isTeacher then return end
        if isPanelOpen() then return end -- ✅ 이미 열려있으면 무시

        playClickSound(showBtn)

        bg.Visible = true
        -- ✅ 패널 열려있을 때 ShowButton 입력/호버 비활성
        showBtn.Active = false

        tweenPanelTo(POS_SHOW, nil)
end)

xBtn.Activated:Connect(function()
        if not isTeacher then return end
        playClickSound(bg)

        tweenPanelTo(POS_HIDE, function()
                bg.Visible = false
                -- ✅ 패널 닫히면 ShowButton 다시 활성
                showBtn.Active = true
        end)
end)

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Stop = Remotes:WaitForChild("Teacher_StopAll")
local RE_Spawn = Remotes:WaitForChild("Teacher_SpawnAll")
local RE_Feedback = Remotes:WaitForChild("Teacher_Feedback")

spawnBtn.Activated:Connect(function()
        if not isTeacher then return end
        playClickSound(bg)
        RE_Spawn:FireServer()
end)

stopBtn.Activated:Connect(function()
        if not isTeacher then return end
        playClickSound(bg)
        RE_Stop:FireServer()
end)

-- Stop 토글 텍스트(텍스트 버튼일 경우)
RE_Stop.OnClientEvent:Connect(function(isFrozen: boolean)
        if stopBtn:IsA("TextButton") then
                stopBtn.Text = isFrozen and "RESUME" or "STOP"
        end
end)

-- ✅ 선생님 피드백 출력(F9 콘솔에서 확인)
RE_Feedback.OnClientEvent:Connect(function(msg: string)
        warn("[TEACHER]", msg)
end)

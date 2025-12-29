-- StarterPlayerScripts/PortalCutsceneTest.client.lua
--!strict

local RS   = game:GetService("ReplicatedStorage")
local CAS  = game:GetService("ContextActionService")
local WS   = game:GetService("Workspace")
local SoundService            = game:GetService("SoundService")

local Modules = RS:WaitForChild("Modules")

local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

local PortalMover =
	tryRequire(RS:FindFirstChild("PortalMover"))
	or tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalMover"))

local CutscenePlayer =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("Cutscene") and RS.Modules.Cutscene:FindFirstChild("CutscenePlayer"))
	or tryRequire(RS:FindFirstChild("CutscenePlayer"))


local TARGET_POS = Vector3.new(-249.289, 22.578, 21.106)
local BUSY = false
local COOLDOWN_SEC = 1.8

local SFX: {[string]: string} = {
	TrashClean   = "rbxassetid://4636006374",       -- 오브젝트 정화 될 때
	Wrong        = "rbxassetid://5521959695",       -- 오답 시
	ChoiceClick  = "rbxassetid://9055474333",       -- 문제 클릭(보기 선택) 할 때
	Correct      = "rbxassetid://114326413874741",  -- 정답 시
	Submit       = "rbxassetid://15675059323",      -- 제출하기 버튼 눌렀을 때
	QuizOpen     = "rbxassetid://89842591486388",   -- 퀴즈 나올 때

	DoorOpen1    = "rbxassetid://103840356233584",  -- 4문제 풀고 문 열릴 때 사운드 1
	DoorOpen2    = "rbxassetid://6636232274",       -- 4문제 풀고 문 열릴 때 사운드 2

	PortalOpen   = "rbxassetid://2017454590",       -- 포탈 열릴 때
}

local function playSfx(name: string, volume: number?)
	local soundId = SFX[name]
	if not soundId then return end

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.RollOffMode = Enum.RollOffMode.Inverse
	s.Parent = SoundService

	s.Ended:Connect(function()
		if s then
			s:Destroy()
		end
	end)

	s:Play()
end

local function playDoorCutscene(stage:number)
	-- 4문제 이상 풀고 문 열릴 때 사운드
	playSfx("DoorOpen1")
	playSfx("DoorOpen2")

	-- 문 열기(날개 이동)
	pcall(function()
		if PortalMover then
			PortalMover.Open(stage, 10, 0.6)
		end
	end)

	-- 카메라 컷씬
	local cutDur = 3
	pcall(function()
		if CutscenePlayer then
			CutscenePlayer.PlayPortalOpen(stage, {
				duration  = cutDur,
				allowSkip = true,
			})
		end
	end)

	-- 컷씬 끝난 뒤 문 투명 처리
	task.delay(0, function()
		pcall(function()
			if PortalMover and PortalMover.FadeOut then
				PortalMover.FadeOut(stage, 0)
			end
		end)
	end)
end

local function onAction(_, state, _)
	if state == Enum.UserInputState.Begin then
		playDoorCutscene(1)
	end
end

CAS:BindAction("PortalCutsceneTest", onAction, false, Enum.KeyCode.F6)
print(("[PortalTest] READY — F1: spawn @ %s"):format(tostring(TARGET_POS)))

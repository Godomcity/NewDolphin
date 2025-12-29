-- ReplicatedStorage/Modules/WaterleafCutscene.lua
--!strict

local TweenService = game:GetService("TweenService")
local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Players      = game:GetService("Players") -- ★ 추가

local CUTSCENE_TIME = 3.0
local LEAF_OFFSET   = 4.5

local M = {}

local function collectParts(root: Instance?): {BasePart}
	local list = {}
	if not root then return list end

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- 🔊 사운드 재생 함수
local function playSound(soundId: string, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

----------------------------------------------------
-- ★ LocalPlayer 컨트롤 / Humanoid 헬퍼
----------------------------------------------------
local function getControls()
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local ps = lp:FindFirstChildOfClass("PlayerScripts")
	if not ps then return nil end
	local pm = ps:FindFirstChild("PlayerModule")
	if not pm or not pm:IsA("ModuleScript") then return nil end

	local ok, mod = pcall(require, pm)
	if not ok or not mod.GetControls then return nil end

	local ok2, controls = pcall(function()
		return mod:GetControls()
	end)
	if not ok2 then return nil end

	return controls
end

local function getLocalHumanoid(): Humanoid?
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

----------------------------------------------------
-- 1) 기존 버전 : 카메라 + 잎 컷씬 (플레이어 잠금 추가)
----------------------------------------------------
function M.Play()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- 스테이지/모델/카메라 파츠 먼저 확인
	local stage5    = Workspace:FindFirstChild("Stage5")
	if not stage5 then
		warn("[WaterleafCutscene] Stage5 를 찾지 못했습니다.")
		return
	end

	local waterleaf = stage5:FindFirstChild("Waterleaf")
	if not waterleaf then
		warn("[WaterleafCutscene] Waterleaf 를 찾지 못했습니다.")
		return
	end

	local leftModel  = waterleaf:FindFirstChild("Left")
	local rightModel = waterleaf:FindFirstChild("Right")

	if not (leftModel and rightModel) then
		warn("[WaterleafCutscene] Left / Right 모델을 찾지 못했습니다.")
		return
	end

	local camStartPart = Workspace:FindFirstChild("CutSceneCamPos") :: BasePart?
	local camEndPart   = Workspace:FindFirstChild("CutSceneEndCamPos") :: BasePart?
	if not (camStartPart and camEndPart) then
		warn("[WaterleafCutscene] CutSceneCamPos / CutSceneEndCamPos 를 찾지 못했습니다.")
		return
	end

	-- 카메라 상태 백업
	local origType   = camera.CameraType
	local origCFrame = camera.CFrame

	-- ★ 플레이어 컨트롤 / 이동 잠금
	local controls = getControls()
	if controls then
		pcall(function()
			controls:Disable()
		end)
	end

	local humanoid = getLocalHumanoid()
	local oldWalkSpeed: number? = nil
	local oldJumpPower: number? = nil
	local oldJumpHeight: number? = nil
	local oldAutoRotate: boolean? = nil

	if humanoid then
		oldWalkSpeed   = humanoid.WalkSpeed
		oldJumpPower   = humanoid.JumpPower
		oldJumpHeight  = humanoid.JumpHeight
		oldAutoRotate  = humanoid.AutoRotate

		humanoid.WalkSpeed  = 0
		humanoid.JumpPower  = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end

	-- 컷씬용 카메라 세팅
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame     = camStartPart.CFrame

	local leftParts  = collectParts(leftModel)
	local rightParts = collectParts(rightModel)

	local camTweenInfo  = TweenInfo.new(CUTSCENE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local leafTweenInfo = TweenInfo.new(CUTSCENE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	----------------------------------------------
	-- 🔊 문 열리는 사운드 2개 동시에 재생
	----------------------------------------------
	playSound("rbxassetid://103840356233584", 1)
	playSound("rbxassetid://6636232274", 0.8)

	----------------------------------------------
	-- Left 잎 열림
	----------------------------------------------
	for _, part in ipairs(leftParts) do
		part.CanCollide = false
		local targetCf = part.CFrame * CFrame.new(LEAF_OFFSET, 0, 0)
		TweenService:Create(part, leafTweenInfo, {
			CFrame = targetCf,
			Transparency = 1,
		}):Play()
	end

	----------------------------------------------
	-- Right 잎 열림
	----------------------------------------------
	for _, part in ipairs(rightParts) do
		part.CanCollide = false
		local targetCf = part.CFrame * CFrame.new(-LEAF_OFFSET, 0, 0)
		TweenService:Create(part, leafTweenInfo, {
			CFrame = targetCf,
			Transparency = 1,
		}):Play()
	end

	----------------------------------------------
	-- 카메라 이동
	----------------------------------------------
	local camTween = TweenService:Create(camera, camTweenInfo, {
		CFrame = camEndPart.CFrame,
	})
	camTween:Play()
	camTween.Completed:Wait()

	-- 카메라 복구
	camera.CameraType = origType
	camera.CFrame     = origCFrame

	-- ★ 이동/점프/회전 + 컨트롤 복구
	if humanoid and humanoid.Parent then
		if oldWalkSpeed ~= nil then
			humanoid.WalkSpeed = oldWalkSpeed
		end
		if oldJumpPower ~= nil then
			humanoid.JumpPower = oldJumpPower
		end
		if oldJumpHeight ~= nil then
			humanoid.JumpHeight = oldJumpHeight
		end
		if oldAutoRotate ~= nil then
			humanoid.AutoRotate = oldAutoRotate
		end
	end

	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
end

----------------------------------------------------
-- 2) 새 버전 : 카메라는 그대로, 잎(문)만 열리는 컷씬
----------------------------------------------------
function M.PlayLeafOnly()
	local stage5    = Workspace:FindFirstChild("Stage5")
	if not stage5 then
		warn("[WaterleafCutscene] Stage5 를 찾지 못했습니다. (PlayLeafOnly)")
		return
	end

	local waterleaf = stage5:FindFirstChild("Waterleaf")
	if not waterleaf then
		warn("[WaterleafCutscene] Waterleaf 를 찾지 못했습니다. (PlayLeafOnly)")
		return
	end

	local leftModel  = waterleaf:FindFirstChild("Left")
	local rightModel = waterleaf:FindFirstChild("Right")

	if not (leftModel and rightModel) then
		warn("[WaterleafCutscene] Left / Right 모델을 찾지 못했습니다. (PlayLeafOnly)")
		return
	end

	local leftParts  = collectParts(leftModel)
	local rightParts = collectParts(rightModel)

	local leafTweenInfo = TweenInfo.new(CUTSCENE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	----------------------------------------------
	-- Left 잎 열림
	----------------------------------------------
	for _, part in ipairs(leftParts) do
		part.CanCollide = false
		local targetCf = part.CFrame * CFrame.new(LEAF_OFFSET, 0, 0)
		TweenService:Create(part, leafTweenInfo, {
			CFrame = targetCf,
			Transparency = 1,
		}):Play()
	end

	----------------------------------------------
	-- Right 잎 열림
	----------------------------------------------
	for _, part in ipairs(rightParts) do
		part.CanCollide = false
		local targetCf = part.CFrame * CFrame.new(-LEAF_OFFSET, 0, 0)
		TweenService:Create(part, leafTweenInfo, {
			CFrame = targetCf,
			Transparency = 1,
		}):Play()
	end

	-- 카메라는 건드리지 않고, 대충 연출 시간만큼 기다렸다가 충돌 정리
	task.wait(CUTSCENE_TIME)

	for _, part in ipairs(leftParts) do
		part.CanCollide = false
	end
	for _, part in ipairs(rightParts) do
		part.CanCollide = false
	end
end

return M

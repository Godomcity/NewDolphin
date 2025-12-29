-- ReplicatedStorage/Modules/JellyfishCutscene.lua
--!strict
-- 사용 예 (클라이언트):
-- local RS = game:GetService("ReplicatedStorage")
-- local JCut = require(RS.Modules.JellyfishCutscene)
-- JCut.Play()

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players") -- ★ 추가

local M = {}

---------------------------------------------------------
-- 설정 값
---------------------------------------------------------

-- 파츠가 아래에서 위로 올라오는 높이(Y축)
local DROP_HEIGHT = 23.345 -- 필요하면 감성에 맞게 조절

-- 카메라 이동 시간
local CAM_MOVE_TIME = 3.5

-- 파츠 물방울 연출
local PART_MOVE_TIME  = 2.5    -- 파츠 한 개가 “생성”되는 시간
local PART_MAX_DELAY  = 1.0    -- 파츠마다 0 ~ 1초 랜덤 딜레이
local PART_SCALE_FROM = 0.7    -- 시작 크기 비율(0.7배 → 1배)

-- 사운드
local JELLY_SOUND_ID = "rbxassetid://9112752575"
local JELLY_SOUND_VOLUME = 10

---------------------------------------------------------
-- Stage3 / JellyFish / 카메라 파트 찾기
---------------------------------------------------------

local function getStage3(): Instance
	return workspace:WaitForChild("Stage3")
end

local function getJelly(): Model
	local stage3 = getStage3()

	-- Stage3 바로 아래에 있으면 그거 사용
	local direct = stage3:FindFirstChild("JellyFish")
	if direct and direct:IsA("Model") then
		return direct
	end

	-- 아니면 자손 중에서 찾기
	for _, d in ipairs(stage3:GetDescendants()) do
		if d:IsA("Model") and d.Name == "JellyFish" then
			return d
		end
	end

	error("[JellyfishCutscene] Stage3 아래에서 'JellyFish' 모델을 찾지 못했습니다.")
end

local function getCamParts(): (BasePart, BasePart)
	local stage3 = getStage3()
	-- 너가 수정한 대로 workspace 루트에서 찾게 유지
	local startPart = workspace:WaitForChild("JellyCamPos") :: BasePart
	local endPart   = workspace:WaitForChild("JellyCamEndPos") :: BasePart
	return startPart, endPart
end

---------------------------------------------------------
-- ★ LocalPlayer 컨트롤 / Humanoid 헬퍼
---------------------------------------------------------

local function getControls()
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local ps = lp:FindFirstChildOfClass("PlayerScripts")
	if not ps then return nil end
	local pm = ps:FindFirstChild("PlayerModule")
	if not pm or not pm:IsA("ModuleScript") then return nil end

	local ok, mod = pcall(require, pm)
	if not ok or not mod.GetControls then return nil end

	return mod:GetControls()
end

local function getLocalHumanoid(): Humanoid?
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

---------------------------------------------------------
-- JellyFish 하위 파트 물방울 + Y축 상승 연출
--  - X,Z는 원래 위치 고정
--  - Y만 DROP_HEIGHT 만큼 아래에서 위로 올라간다
--  - 올라오기 시작할 때 사운드 재생
---------------------------------------------------------

local function playPartsVerticalBubble(jelly: Model)
	type PartInfo = {
		part: BasePart,
		startCF: CFrame,
		endCF: CFrame,
		baseSize: Vector3,
	}

	local infos: {PartInfo} = {}

	-- 사운드 템플릿 하나 만들어두고 복제해서 사용
	local soundTemplate = Instance.new("Sound")
	soundTemplate.SoundId = JELLY_SOUND_ID
	soundTemplate.Volume = JELLY_SOUND_VOLUME
	soundTemplate.PlayOnRemove = false
	soundTemplate.Looped = false
	soundTemplate.Name = "JellyRiseSoundTemplate"
	soundTemplate.Parent = jelly

	for _, obj in ipairs(jelly:GetDescendants()) do
		if obj:IsA("BasePart") then
			local endCF = obj.CFrame
			local endPos = endCF.Position
			local rotOnly = endCF - endPos

			-- X,Z는 그대로, Y만 DROP_HEIGHT 만큼 아래에서 시작
			local startPos = Vector3.new(endPos.X, endPos.Y - DROP_HEIGHT, endPos.Z)
			local startCF = rotOnly + startPos

			table.insert(infos, {
				part = obj,
				startCF = startCF,
				endCF = endCF,
				baseSize = obj.Size,
			})

			-- 시작 상태 세팅
			obj.CFrame = startCF
			obj.Transparency = 1
			obj.Size = obj.Size * PART_SCALE_FROM
		end
	end

	for _, info in ipairs(infos) do
		local part = info.part
		if not part or not part.Parent then
			continue
		end

		local delaySec = math.random() * PART_MAX_DELAY

		task.delay(delaySec, function()
			if not part or not part.Parent then return end

			-- 이 파트가 올라오기 시작할 때 사운드 재생
			local s = soundTemplate:Clone()
			s.Parent = part
			s:Play()
			s.Ended:Connect(function()
				s:Destroy()
			end)

			-- 위치 Tween: startCF → endCF (X,Z 고정, Y만 위로)
			local moveTween = TweenService:Create(
				part,
				TweenInfo.new(PART_MOVE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CFrame = info.endCF }
			)

			-- 투명도 1 → 0
			local fadeTween = TweenService:Create(
				part,
				TweenInfo.new(PART_MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 0 }
			)

			-- 사이즈 0.7배 → 1배 (물방울처럼 톡 튀어나오는 느낌)
			local sizeTween = TweenService:Create(
				part,
				TweenInfo.new(PART_MOVE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = info.baseSize }
			)

			moveTween:Play()
			fadeTween:Play()
			sizeTween:Play()
		end)
	end
end

local function noSoundjelly(jelly: Model)
	type PartInfo = {
		part: BasePart,
		startCF: CFrame,
		endCF: CFrame,
		baseSize: Vector3,
	}

	local infos: {PartInfo} = {}

	for _, obj in ipairs(jelly:GetDescendants()) do
		if obj:IsA("BasePart") then
			local endCF = obj.CFrame
			local endPos = endCF.Position
			local rotOnly = endCF - endPos

			-- X,Z는 그대로, Y만 DROP_HEIGHT 만큼 아래에서 시작
			local startPos = Vector3.new(endPos.X, endPos.Y - DROP_HEIGHT, endPos.Z)
			local startCF = rotOnly + startPos

			table.insert(infos, {
				part = obj,
				startCF = startCF,
				endCF = endCF,
				baseSize = obj.Size,
			})

			-- 시작 상태 세팅
			obj.CFrame = startCF
			obj.Transparency = 1
			obj.Size = obj.Size * PART_SCALE_FROM
		end
	end

	for _, info in ipairs(infos) do
		local part = info.part
		if not part or not part.Parent then
			continue
		end

		local delaySec = math.random() * PART_MAX_DELAY

		task.delay(delaySec, function()
			if not part or not part.Parent then return end

			-- 위치 Tween: startCF → endCF (X,Z 고정, Y만 위로)
			local moveTween = TweenService:Create(
				part,
				TweenInfo.new(PART_MOVE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CFrame = info.endCF }
			)

			-- 투명도 1 → 0
			local fadeTween = TweenService:Create(
				part,
				TweenInfo.new(PART_MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 0 }
			)

			-- 사이즈 0.7배 → 1배 (물방울처럼 톡 튀어나오는 느낌)
			local sizeTween = TweenService:Create(
				part,
				TweenInfo.new(PART_MOVE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = info.baseSize }
			)

			moveTween:Play()
			fadeTween:Play()
			sizeTween:Play()
		end)
	end
end

---------------------------------------------------------
-- Public API
-- opts = {
--   jelly: Model?,        -- 기본: Stage3 안의 JellyFish 모델
--   keepCamera: boolean?, -- true면 끝나도 카메라 복구 안 함
--   onFinished: (() -> ())?,
-- }
---------------------------------------------------------

function M.Play(opts: { jelly: Model?, keepCamera: boolean?, onFinished: (() -> ())? }?)
	opts = opts or {}
	local jelly = opts.jelly or getJelly()
	local cam   = workspace.CurrentCamera

	if not jelly then
		warn("[JellyfishCutscene] JellyFish model not found")
		return
	end
	if not cam then
		warn("[JellyfishCutscene] no CurrentCamera")
		return
	end

	local camStartPart, camEndPart = getCamParts()
	local camStartCF = camStartPart.CFrame
	local camEndCF   = camEndPart.CFrame

	-- 카메라 백업
	local prevType   = cam.CameraType
	local prevCFrame = cam.CFrame

	-- ★ 컨트롤 & Humanoid 잠금
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

	-- JellyFish 파트들: X,Z 고정, Y만 아래에서 위로 올라오게 세팅 + 랜덤 연출/사운드 시작
	playPartsVerticalBubble(jelly)

	-- 카메라 고정 + 시작 CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = camStartCF

	-- 카메라 Tween (JellyCamPos → JellyCamEndPos)
	local camTween = TweenService:Create(
		cam,
		TweenInfo.new(CAM_MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = camEndCF }
	)

	camTween:Play()
	camTween.Completed:Wait()

	-- 🔊 컷씬 종료 후: JellyFish 안의 관련 사운드 전부 정리
	for _, d in ipairs(jelly:GetDescendants()) do
		if d:IsA("Sound") and (d.Name == "JellyRiseSoundTemplate" or d.SoundId == JELLY_SOUND_ID) then
			d:Destroy()
		end
	end

	-- 카메라 복구
	if not opts.keepCamera then
		cam.CameraType = prevType
		cam.CFrame = prevCFrame
	end

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

	if opts.onFinished then
		pcall(opts.onFinished)
	end
end

---------------------------------------------------------
-- 🔹 카메라 고정: 젤리만 물방울처럼 올라오는 버전
--    재입장 때 쓰기 좋음
-- opts = {
--   jelly: Model?,
--   onFinished: (() -> ())?,
-- }
---------------------------------------------------------
function M.PlayJellyOnly(opts: { jelly: Model?, onFinished: (() -> ())? }?)
	opts = opts or {}
	local jelly = opts.jelly or getJelly()
	if not jelly then
		warn("[JellyfishCutscene] JellyFish model not found (PlayJellyOnly)")
		return
	end

	noSoundjelly(jelly)

	if opts.onFinished then
		-- 파츠 애니메이션이 PART_MOVE_TIME + PART_MAX_DELAY 정도라
		-- 그 이후에 콜백 한 번 호출해줌
		task.delay(PART_MOVE_TIME + PART_MAX_DELAY + 0.2, function()
			pcall(opts.onFinished :: () -> ())
		end)
	end
end

return M

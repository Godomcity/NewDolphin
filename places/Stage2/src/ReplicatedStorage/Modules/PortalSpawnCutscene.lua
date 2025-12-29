-- ReplicatedStorage/Modules/PortalSpawnCutscene.lua
--!strict
-- 포탈 스폰 컷씬 (Stage1용 커스텀)
--  - 더 이상 위에서 떨어지지 않음
--  - Potal 모델의 Body / Inside / Inside 안의 Decal 이 서서히 나타나는 페이드인 연출
--  - 페이드가 끝나면 포탈 ProximityPrompt 활성화 + 파티클 이펙트 재생
--  - 카메라 연출은 그대로 CamPos → CamEndPos 사용 (없으면 기본 front 뷰)
--  - ★ 컷씬 동안 플레이어 조작 잠시 비활성화

local TweenService  = game:GetService("TweenService")
local Workspace     = game:GetService("Workspace")
local Players       = game:GetService("Players")
local RS            = game:GetService("ReplicatedStorage")

local M = {}

-------------------------------------------------------
-- 유틸
-------------------------------------------------------
local function getPivotCF(inst: Instance): CFrame
	if inst:IsA("Model") then return inst:GetPivot() end
	local cf, _ = (inst :: any):GetBoundingBox()
	return cf
end

local function uniqueChildName(parent: Instance, base: string): string
	if not parent:FindFirstChild(base) then return base end
	local i = 2
	while parent:FindFirstChild(base .. i) do i += 1 end
	return base .. i
end

local function resolvePath(root: Instance, path: string?): Instance?
	if not path or #path == 0 then return nil end
	local cur: Instance? = root
	for seg in string.gmatch(path, "[^%.]+") do
		if not cur then return nil end
		cur = cur:FindFirstChild(seg)
	end
	return cur
end

local function cfOf(anyInst: Instance): CFrame
	if anyInst:IsA("Attachment") then
		return (anyInst :: Attachment).WorldCFrame
	elseif anyInst:IsA("BasePart") then
		return (anyInst :: BasePart).CFrame
	elseif anyInst:IsA("Model") then
		return (anyInst :: Model):GetPivot()
	else
		return getPivotCF(anyInst)
	end
end

local function findDefaultParent(): Instance
	local w = Workspace
	if w:FindFirstChild("Stage01") then return w.Stage01 end
	if w:FindFirstChild("Objects") and w.Objects:FindFirstChild("Stage01") then
		return w.Objects.Stage01
	end
	for _, d in ipairs(w:GetDescendants()) do
		if d.Name == "Stage01" then return d end
	end
	return Workspace
end

local function tryFindSpawnSlot(parent: Instance): CFrame?
	local CANDS = { "PortalSpawn", "PotalSpawn", "PortalSlot", "PotalSlot", "Spawn_Portal" }
	for _, n in ipairs(CANDS) do
		local f = parent:FindFirstChild(n, true)
		if f then
			if f:IsA("BasePart") then
				return (f :: BasePart).CFrame
			else
				return getPivotCF(f)
			end
		end
	end
	return nil
end

-- 포탈의 모든 ParticleEmitter를 한 번에 재생
local function kickParticles(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			local pe = d :: ParticleEmitter
			pe.Enabled = true
			pe:Clear()
			print(pe)
			local ok = pcall(function()
				pe:FastForward(0.25) -- “이미 조금 나온 상태”처럼
			end)
			if not ok then
				pe:Emit(1)
			end
		end
	end
end

-- ★ 로컬 플레이어 Humanoid 구하기
local function getLocalHumanoid(): Humanoid?
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

--[[  M.play(opts)
opts = {
	templateName: string?      -- 기본 "Potal"
	parent: Instance?          -- 기본 Stage01/Workspace
	nameBase: string?          -- 기본 "Potal"

	targetCF: CFrame?
	targetPosition: Vector3?

	fadeTime: number?          -- 기본 0.9 (예전 dropTime 대신 사용)
	restoreDelay: number?      -- 기본 fadeTime + 0.4

	-- 카메라 앵커(Workspace 기준 경로)
	camStartPath: string?      -- 기본 "CamPos"
	camEndPath:   string?      -- 기본 "CamEndPos"
	camDuration:  number?      -- 기본 fadeTime + 0.2
	camAnchorsUseOrientation: boolean? -- 기본 false(양쪽 모두 포탈을 바라보게 회전)

	-- (앵커 없을 때 fallback) 간단 front 모드
	cameraMode: "front"|"offset"?  -- 기본 "front"
	frontPre: {dist:number?, height:number?, side:number?}?
	frontEnd: {dist:number?, height:number?, side:number?}?
	flipFront: boolean?       -- 기본 false

	soundId: string?
}
return: Model?
]]
function M.play(opts)
	opts = opts or {}
	local templateName  = opts.templateName or "Potal"
	local nameBase      = opts.nameBase or "Potal"

	-- 예전 dropTime 옵션과 호환
	local fadeTime      = opts.fadeTime or opts.dropTime or 3
	local restoreDelay  = opts.restoreDelay or (fadeTime + 0.4)

	local camStartPath  = (opts.camStartPath ~= nil) and opts.camStartPath or "CamPos"
	local camEndPath    = (opts.camEndPath   ~= nil) and opts.camEndPath   or "CamEndPos"
	local camDur        = opts.camDuration or (fadeTime + 0.2)
	local useAnchorRot  = (opts.camAnchorsUseOrientation == true)

	-- 템플릿
	local template = RS:FindFirstChild(templateName)
	if not template or not template:IsA("Model") then
		warn(("[PortalSpawnCutscene] ReplicatedStorage.%s 템플릿이 없거나 Model이 아님"):format(templateName))
		return nil
	end

	-- 부모
	local parent = opts.parent or findDefaultParent()

	-- targetCF 결정
	local targetCF: CFrame? = nil
	if opts.targetCF then
		targetCF = opts.targetCF
	elseif typeof(opts.targetPosition) == "Vector3" then
		local baseCF = template:GetPivot()
		targetCF = CFrame.fromMatrix(opts.targetPosition, baseCF.RightVector, baseCF.UpVector)
	else
		targetCF = tryFindSpawnSlot(parent) or template:GetPivot()
	end
	local targetPos = (targetCF :: CFrame).Position

	-- 카메라 상태 백업
	local cam = workspace.CurrentCamera
	local oldType, oldCF = cam.CameraType, cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable

	-- ★ 컷씬 시작 시 플레이어 이동 잠금 상태 백업 & 잠그기
	local humanoid = getLocalHumanoid()
	local oldWalkSpeed: number? = nil
	local oldJumpPower: number? = nil
	local oldJumpHeight: number? = nil
	local oldAutoRotate: boolean? = nil

	-- PlayerModule 컨트롤(있으면 같이 비활성화)
	local controls = nil
	do
		local lp = Players.LocalPlayer
		if lp then
			local ps = lp:FindFirstChild("PlayerScripts")
			if ps then
				local pm = ps:FindFirstChild("PlayerModule")
				if pm and pm:IsA("ModuleScript") then
					local ok, mod = pcall(require, pm)
					if ok and mod and mod.GetControls then
						local ok2, ctrls = pcall(function()
							return mod:GetControls()
						end)
						if ok2 and ctrls then
							controls = ctrls
							pcall(function()
								controls:Disable()
							end)
						end
					end
				end
			end
		end
	end

	if humanoid then
		oldWalkSpeed = humanoid.WalkSpeed
		oldAutoRotate = humanoid.AutoRotate

		-- JumpPower / JumpHeight 둘 중 무엇을 쓰는지에 따라 백업
		if humanoid.UseJumpPower == nil or humanoid.UseJumpPower == true then
			oldJumpPower = humanoid.JumpPower
		else
			oldJumpHeight = humanoid.JumpHeight
		end

		-- 실제 잠금
		humanoid.WalkSpeed = 0
		if oldJumpPower ~= nil then
			humanoid.JumpPower = 0
		elseif oldJumpHeight ~= nil then
			humanoid.JumpHeight = 0
		end
		humanoid.AutoRotate = false
	end

	-------------------------------------------------------
	-- 카메라 앵커 사용: CamPos → CamEndPos
	-------------------------------------------------------
	local startAnchor = resolvePath(Workspace, camStartPath)
	local endAnchor   = resolvePath(Workspace, camEndPath)
	local usedAnchors = (startAnchor ~= nil)

	if startAnchor then
		local startCF = cfOf(startAnchor :: Instance)
		if not useAnchorRot then
			startCF = CFrame.new(startCF.Position, targetPos)
		end
		cam.CFrame = startCF

		if endAnchor then
			local endCF = cfOf(endAnchor :: Instance)
			if not useAnchorRot then
				endCF = CFrame.new(endCF.Position, targetPos)
			end
			TweenService:Create(
				cam,
				TweenInfo.new(camDur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CFrame = endCF }
			):Play()
		end
	else
		-- 앵커 없으면 front 모드 fallback
		local cameraMode = (opts.cameraMode == "offset") and "offset" or "front"
		if cameraMode == "front" then
			local cf = (targetCF :: CFrame)
			local origin, f, u, r = cf.Position, cf.LookVector, cf.UpVector, cf.RightVector
			local pre  = opts.frontPre or  { dist=18, height=1.5, side=0 }
			local en   = opts.frontEnd or { dist=12, height=0.8, side=0 }
			local dir  = (opts.flipFront == true) and 1 or -1
			local endPos = origin + f*(dir*en.dist)  + u*en.height  + r*en.side
			cam.CFrame = CFrame.new(endPos, origin)
		else
			cam.CFrame = CFrame.new(cam.CFrame.Position, targetPos)
		end
	end

	-------------------------------------------------------
	-- 포탈 클론 (위에서 떨어지지 않고 바로 위치 고정)
	-------------------------------------------------------
	local finalName = uniqueChildName(parent, nameBase)
	local clone = template:Clone()
	clone.Name = finalName
	clone.Parent = parent
	clone:PivotTo(targetCF :: CFrame)

	-------------------------------------------------------
	-- 포탈 페이드인 연출
	-------------------------------------------------------
	local body   = clone:FindFirstChild("Body", true)   :: BasePart?
	local inside = clone:FindFirstChild("Inside", true) :: BasePart?
	local decal: Decal? = nil
	if inside then
		for _, d in ipairs(inside:GetDescendants()) do
			if d:IsA("Decal") then
				decal = d
				break
			end
		end
	end

	-- 시작은 완전 투명
	if body then body.Transparency = 1 end
	if inside then inside.Transparency = 1 end
	if decal then decal.Transparency = 1 end

	-- 먼저 포탈의 ProximityPrompt 들은 잠시 비활성화
	local prompts: {ProximityPrompt} = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.Enabled = false
			table.insert(prompts, d)
		end
	end

	-- 사운드(선택)
	if typeof(opts.soundId) == "string" and #opts.soundId > 0 then
		local s = Instance.new("Sound")
		s.SoundId = opts.soundId
		s.Volume   = 0.75
		s.PlayOnRemove = true
		s.Parent = clone
		s:Destroy()
	end
	delay(1,function()
		-- 파티클 이펙트 재생
		kickParticles(clone)
	end)

	-- 페이드인 트윈 (Body/Inside = 0, Decal = 0.5)
	if body then
		TweenService:Create(
			body,
			TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 0 }
		):Play()
	end

	if inside then
		TweenService:Create(
			inside,
			TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 0 }
		):Play()
	end

	if decal then
		TweenService:Create(
			decal,
			TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 0.5 }
		):Play()
	end

	-------------------------------------------------------
	-- ★ 페이드가 끝났을 때: 프롬프트 활성화
	-------------------------------------------------------
	task.delay(fadeTime, function()
		-- ProximityPrompt 켜기
		for _, pp in ipairs(prompts) do
			if pp.Parent then
				pp.Enabled = true
				if pp.MaxActivationDistance <= 0 then
					pp.MaxActivationDistance = 10
				end
			end
		end
	end)

	-- 카메라 / 이동 복원
	task.delay(restoreDelay, function()
		if cam then
			cam.CameraType = oldType
			cam.CFrame = oldCF
		end

		-- ★ 캐릭터 이동 다시 활성화
		if controls then
			pcall(function()
				controls:Enable()
			end)
		end

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
	end)

	print(("[PortalSpawnCutscene] Spawned '%s' under %s (fade %.2fs, anchors=%s → %s)")
		:format(finalName, parent:GetFullName(), fadeTime, camStartPath, usedAnchors and camEndPath or "none"))

	return clone
end

return M

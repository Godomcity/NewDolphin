-- ReplicatedStorage/Modules/LadderCinematic.lua
--!strict
-- 사다리 연출 전담:
--  - 템플릿 복제/배치
--  - 자식 BasePart/Decal/Texture "항상" 투명(=1) 유지 옵션
--  - 드랍 & 바운스 애니메이션
--  - (옵션) 사운드 재생
--  - (옵션) 카메라 컷씬: 현재 시점 → 전체샷 → 줌인
--  - ★ spawnInstant(opts): 드랍/바운스/카메라 없이 바로 배치용 헬퍼

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")

local M = {}

export type SpawnOpts = {
	template: Instance,          -- 복제할 템플릿(Model/BasePart)
	position: Vector3,           -- 최종 배치 위치(회전은 템플릿 그대로)
	parent: Instance?,           -- 기본: workspace
	dropHeight: number?,         -- 위로 얼마나 띄워서 시작할지(기본 18)
	dropTime: number?,           -- 떨어지는 시간(기본 0.65초)
	bouncePower: number?,        -- 0.0~1.0 (시각적, Tween Easing만 사용) 기본 1.0
	nameSuffix: string?,         -- 클론 이름 뒤에 붙일 텍스트
	keepChildrenTransparent: boolean?, -- 기본 true
	-- 🔊 사운드 옵션
	soundId: string?,            -- 사다리에서 재생할 사운드
	soundVolume: number?,        -- 기본 1
}

-- (카메라 컷씬 옵션 추가 타입)
export type CameraSpawnOpts = SpawnOpts & {
	cameraTotalTime: number?,    -- 전체 컷씬 시간(기본 3.0초)
	cameraBackWide: number?,     -- 전체샷에서 뒤로 빠지는 거리(기본 32)
	cameraHeightWide: number?,   -- 전체샷에서 위로 올리는 높이(기본 18)
	cameraBackClose: number?,    -- 줌인 샷에서 뒤로 빠지는 거리(기본 18)
	cameraHeightClose: number?,  -- 줌인 샷에서 위로 올리는 높이(기본 10)
}

-- 내부: 자식 파트들을 항상 투명 1로 유지
local ALWAYS_TAG = "_LadderAlwaysTransparent"

local function forceTransparent(inst: Instance)
	if inst:IsA("BasePart") then
		inst:SetAttribute(ALWAYS_TAG, true)
		inst.Transparency = 1
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				d:SetAttribute(ALWAYS_TAG, true)
				d.Transparency = 1
			end
		end
	end
end

-- 공개: 루트 이하 자식이 추가되더라도 영구히 투명 유지
function M.ensureAlwaysTransparent(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		forceTransparent(d)
	end
	root.DescendantAdded:Connect(function(d)
		forceTransparent(d)
	end)
end

-- 내부: 모델/파트를 주어진 위치로 옮기는 헬퍼
local function setToPositionKeepingRotation(inst: Instance, pos: Vector3)
	if inst:IsA("Model") then
		local rot = inst:GetPivot().Rotation
		inst:PivotTo(CFrame.new(pos) * rot)
	elseif inst:IsA("BasePart") then
		local rot = inst.CFrame.Rotation
		inst.CFrame = CFrame.new(pos) * rot
	end
end

-- 내부: 사운드를 사다리 위치에서 재생
local function playLadderSound(root: Instance, soundId: string, volume: number?)
	local target: BasePart? = nil
	if root:IsA("Model") then
		local m = root :: Model
		if m.PrimaryPart then
			target = m.PrimaryPart
		else
			target = m:FindFirstChildWhichIsA("BasePart", true)
		end
	elseif root:IsA("BasePart") then
		target = root
	end
	if not target then return end

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.PlayOnRemove = false
	s.Parent = target
	s:Play()

	s.Ended:Connect(function()
		s:Destroy()
	end)

	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- 내부: LocalPlayer 컨트롤 비활성/복구
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

-- ★ 내부: LocalPlayer Humanoid 가져오기
local function getLocalHumanoid(): Humanoid?
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

-- 내부: 카메라 핸들
local function getCamera(): Camera?
	return workspace.CurrentCamera
end

-------------------------------------------------------
-- 기본: 템플릿 복제 + 항상 투명 + 드롭&바운스 연출 (카메라 X)
-------------------------------------------------------
function M.spawnAndAnimate(opts: SpawnOpts): Instance?
	local template = opts.template
	if not template then
		warn("[LadderCinematic] template is nil")
		return nil
	end
	local parent    = opts.parent or workspace
	local dropH     = opts.dropHeight or 18
	local dropTime  = opts.dropTime or 0.65
	local bouncePow = math.clamp(opts.bouncePower or 1.0, 0, 1)
	local nameSuf   = opts.nameSuffix or "(Clone)"
	local keepTrans = if opts.keepChildrenTransparent == nil then true else opts.keepChildrenTransparent
	local soundId   = opts.soundId
	local soundVol  = opts.soundVolume

	local clone = template:Clone()
	clone.Name = (template.Name .. nameSuf)
	clone.Parent = parent

	local finalPos = opts.position
	local startPos = finalPos + Vector3.new(0, dropH, 0)

	if keepTrans then
		M.ensureAlwaysTransparent(clone)
	end

	setToPositionKeepingRotation(clone, startPos)

	if soundId and soundId ~= "" then
		playLadderSound(clone, soundId, soundVol)
	end

	if clone:IsA("Model") then
		local pivot = clone:GetPivot()
		local proxy = Instance.new("Part")
		proxy.Name = "_LadderCineProxy"
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.Transparency = 1
		proxy.CFrame = pivot
		proxy.Parent = parent

		local con = proxy:GetPropertyChangedSignal("CFrame"):Connect(function()
			local target = proxy.CFrame
			clone:PivotTo(target)
		end)

		local targetCF = CFrame.new(finalPos) * pivot.Rotation

		local tw = TweenService:Create(
			proxy,
			TweenInfo.new(dropTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ CFrame = targetCF }
		)
		tw:Play(); tw.Completed:Wait()

		con:Disconnect()
		proxy:Destroy()
	else
		local rot = clone.CFrame.Rotation
		local tw = TweenService:Create(
			clone,
			TweenInfo.new(dropTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(finalPos) * rot }
		)
		tw:Play(); tw.Completed:Wait()
	end

	if bouncePow > 0 then
		local hop = math.max(0.5, 1.5 * bouncePow)
		if clone:IsA("Model") then
			local pivot = clone:GetPivot()
			local upCF  = pivot + Vector3.new(0, hop, 0)
			local downCF= CFrame.new(finalPos) * pivot.Rotation
			local proxy = Instance.new("Part")
			proxy.Anchored, proxy.CanCollide, proxy.Transparency = true, false, 1
			proxy.CFrame = pivot; proxy.Parent = parent
			local con = proxy:GetPropertyChangedSignal("CFrame"):Connect(function()
				clone:PivotTo(proxy.CFrame)
			end)
			local t1 = TweenService:Create(proxy, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = upCF })
			t1:Play(); t1.Completed:Wait()
			local t2 = TweenService:Create(proxy, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),  { CFrame = downCF })
			t2:Play(); t2.Completed:Wait()
			con:Disconnect(); proxy:Destroy()
		else
			local rot = clone.CFrame.Rotation
			local up  = CFrame.new(finalPos + Vector3.new(0, hop, 0)) * rot
			local mid = CFrame.new(finalPos) * rot
			local t1  = TweenService:Create(clone, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = up })
			t1:Play(); t1.Completed:Wait()
			local t2  = TweenService:Create(clone, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),  { CFrame = mid })
			t2:Play(); t2.Completed:Wait()
		end
	end

	return clone
end

-------------------------------------------------------
-- ★ 새로 추가: 즉시 소환용 헬퍼 (드랍/바운스 X)
--  StageTeacherSkip 에서 사용: LadderCinematic.spawnInstant(opts)
-------------------------------------------------------
function M.spawnInstant(opts: SpawnOpts): Instance?
	-- 원본 옵션 건드리지 않도록 복사
	local newOpts = table.clone(opts :: any)

	-- 드랍/바운스 모두 0으로
	newOpts.dropHeight   = 0
	newOpts.dropTime     = 0
	newOpts.bouncePower  = 0

	-- 즉시 완전 보이게 배치하고 싶다면 keepChildrenTransparent 기본 false
	if newOpts.keepChildrenTransparent == nil then
		newOpts.keepChildrenTransparent = false
	end

	return M.spawnAndAnimate(newOpts)
end

-------------------------------------------------------
-- 이미 존재하는 사다리에 애니만 적용
-------------------------------------------------------
export type AnimateOpts = {
	root: Instance,
	dropHeight: number?, dropTime: number?, bouncePower: number?,
}
function M.animateExisting(opts: AnimateOpts)
	local root = opts.root
	if not root then return end
	local y = opts.dropHeight or 18
	local t = opts.dropTime or 0.65
	local b = math.clamp(opts.bouncePower or 1.0, 0, 1)

	M.ensureAlwaysTransparent(root)

	if root:IsA("Model") then
		local pivot = root:GetPivot()
		local upCF  = pivot + Vector3.new(0, y, 0)
		local proxy = Instance.new("Part")
		proxy.Anchored, proxy.CanCollide, proxy.Transparency = true, false, 1
		proxy.CFrame = upCF; proxy.Parent = root.Parent
		local con = proxy:GetPropertyChangedSignal("CFrame"):Connect(function()
			root:PivotTo(proxy.CFrame)
		end)
		local t1 = TweenService:Create(proxy, TweenInfo.new(t, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = pivot })
		t1:Play(); t1.Completed:Wait()
		con:Disconnect(); proxy:Destroy()
	else
		local rot = root.CFrame.Rotation
		root.CFrame = CFrame.new(root.Position + Vector3.new(0, y, 0)) * rot
		local tw = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = CFrame.new(root.Position - Vector3.new(0, y, 0)) * rot })
		tw:Play(); tw.Completed:Wait()
	end

	if b > 0 then
		M.animateExisting({ root = root, dropHeight = math.max(0.5, 1.5 * b), dropTime = 0.4, bouncePower = 0 })
	end
end

-------------------------------------------------------
-- 카메라 포함 컷씬: 현재 시점 → 전체샷 → 줌인
-------------------------------------------------------
function M.playWithCamera(opts: CameraSpawnOpts): Instance?
	local cam = getCamera()
	if not cam then
		warn("[LadderCinematic] playWithCamera: no Camera, fallback to spawnAndAnimate only")
		return M.spawnAndAnimate(opts)
	end

	local totalTime = opts.cameraTotalTime or 3.0
	totalTime = math.max(totalTime, 0.5)

	-- 타임라인: 현재→전체샷 30%, 전체샷→줌인 70%
	local introDur = totalTime * 0.3
	local zoomDur  = totalTime - introDur

	local backWide    = opts.cameraBackWide    or 32
	local heightWide  = opts.cameraHeightWide  or 18
	local backClose   = opts.cameraBackClose   or 18
	local heightClose = opts.cameraHeightClose or 10

	-- 컨트롤 잠깐 끄기
	local controls = getControls()
	if controls then controls:Disable() end

	-- ★ Humanoid 이동/점프/회전 잠금
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

	-- 카메라 백업
	local oldType = cam.CameraType
	local oldCF   = cam.CFrame
	local oldFOV  = cam.FieldOfView

	cam.CameraType = Enum.CameraType.Scriptable

	local template = opts.template
	if not template then
		warn("[LadderCinematic] playWithCamera: template is nil")

		-- ★ 실패 시에도 상태 복구
		cam.CameraType  = oldType
		cam.CFrame      = oldCF
		cam.FieldOfView = oldFOV

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

		if controls then controls:Enable() end
		return nil
	end

	local pivotRot: CFrame
	if template:IsA("Model") then
		pivotRot = template:GetPivot().Rotation
	elseif template:IsA("BasePart") then
		pivotRot = template.CFrame.Rotation
	else
		pivotRot = CFrame.new().Rotation
	end

	local finalPos  = opts.position
	local finalCF   = CFrame.new(finalPos) * pivotRot
	local focusPos  = finalCF.Position
	local forward   = finalCF.LookVector
	local up        = finalCF.UpVector

	local widePos  = focusPos - forward * backWide  + up * heightWide
	local wideCF   = CFrame.lookAt(widePos, focusPos, up)

	local closePos = focusPos - forward * backClose + up * heightClose
	local closeCF  = CFrame.lookAt(closePos, focusPos, up)

	-- 사다리 드랍은 전체 컷씬 시간에 맞춰 별도로 실행
	local spawnOpts: SpawnOpts = table.clone(opts :: any)
	spawnOpts.dropTime = totalTime * 0.4
	local ladder: Instance? = nil
	task.spawn(function()
		ladder = M.spawnAndAnimate(spawnOpts)
	end)

	-- 1) 현재 카메라(oldCF) → 전체샷(wideCF)
	local introTween = TweenService:Create(
		cam,
		TweenInfo.new(
			introDur,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			CFrame      = wideCF,
			FieldOfView = 70,
		}
	)
	introTween:Play()
	introTween.Completed:Wait()

	-- 2) 전체샷(wideCF) → 줌인샷(closeCF)
	local zoomTween = TweenService:Create(
		cam,
		TweenInfo.new(
			zoomDur,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		),
		{
			CFrame      = closeCF,
			FieldOfView = 62,
		}
	)
	zoomTween:Play()
	zoomTween.Completed:Wait()

	-- 카메라 복구
	cam.CameraType  = oldType
	cam.CFrame      = oldCF
	cam.FieldOfView = oldFOV

	-- ★ Humanoid / 컨트롤 복구
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

	if controls then controls:Enable() end

	return ladder
end

return M

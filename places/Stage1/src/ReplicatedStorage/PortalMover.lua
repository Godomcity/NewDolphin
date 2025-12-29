-- ReplicatedStorage/PortalMover.lua
--!strict
-- 🔹 목적: "문 열기(Open)" + "문 숨기기(FadeOut)" + "카메라 이동" 제공 (카메라 이동은 클라이언트 전용)
-- 🔹 동작: 루트 RightVector 기준으로 Left는 왼쪽(−Right), Right는 오른쪽(+Right)
-- ✅ MoveCameraIntoPortal 중에 다른 컷씬(예: FinalZone)이 시작되면 기존 카메라 트윈을 종료시키기 위해 CutsceneManager 토큰 적용

local TweenService = game:GetService("TweenService")
local Workspace    = game:GetService("Workspace")
local RunService   = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

-- CutsceneManager (있으면 사용, 없으면 그냥 기존 방식대로)
local CutsceneManager: any = nil
do
	local mods = ReplicatedStorage:FindFirstChild("Modules")
	if mods then
		local cm = mods:FindFirstChild("CutsceneManager")
		if cm and cm:IsA("ModuleScript") then
			local ok, mod = pcall(require, cm)
			if ok then
				CutsceneManager = mod
			end
		end
	end
end

-- ===== 내부 유틸 =====
local function portalName1(stage:number) return string.format("Stage%dPotal", stage) end   -- Stage1Potal
local function portalName2(stage:number) return string.format("Stage%02dPotal", stage) end -- Stage01Potal

local function findPortalRootAnywhere(stage:number)
	local n1, n2 = portalName1(stage), portalName2(stage)

	local s01 = Workspace:FindFirstChild("Stage01")
	if s01 then
		local r = s01:FindFirstChild(n1) or s01:FindFirstChild(n2)
		if r then return r end
	end

	local objs = Workspace:FindFirstChild("Objects")
	if objs then
		local st = objs:FindFirstChild("Stage01")
		if st then
			local r = st:FindFirstChild(n1) or st:FindFirstChild(n2)
			if r then return r end
		end
	end

	local r = Workspace:FindFirstChild(n1) or Workspace:FindFirstChild(n2)
	if r then return r end

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and (d.Name == n1 or d.Name == n2) then
			return d
		end
	end
	return nil
end

local function collectParts(inst: Instance): {BasePart}
	local out: {BasePart} = {}
	if inst:IsA("BasePart") then
		table.insert(out, inst)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- (기존) 위치만 옮기는 버전 – 혹시 다른 데서 쓰고 있을 수도 있으니 그대로 두자
local function tweenParts(parts: {BasePart}, worldOffset: Vector3, duration: number?, easingStyle, easingDir)
	duration    = duration    or 0.8
	easingStyle = easingStyle or Enum.EasingStyle.Quad
	easingDir   = easingDir   or Enum.EasingDirection.Out
	for _, p in ipairs(parts) do
		local cf0 = p.CFrame
		local rot = cf0 - cf0.Position
		local target = CFrame.new(cf0.Position + worldOffset) * rot
		TweenService:Create(p, TweenInfo.new(duration, easingStyle, easingDir), {
			CFrame = target,
		}):Play()
	end
end

-- ★ 새로 추가: 이동 + 점점 투명해지기
local function tweenPartsMoveAndFade(parts: {BasePart}, worldOffset: Vector3, duration: number?, easingStyle, easingDir, targetTransparency: number?)
	duration           = duration           or 3.0
	easingStyle        = easingStyle        or Enum.EasingStyle.Quad
	easingDir          = easingDir          or Enum.EasingDirection.Out
	targetTransparency = targetTransparency or 1

	for _, p in ipairs(parts) do
		local cf0 = p.CFrame
		local rot = cf0 - cf0.Position
		local targetCF = CFrame.new(cf0.Position + worldOffset) * rot

		local ti = TweenInfo.new(duration, easingStyle, easingDir)

		-- 베이스 파트: 위치 + 투명도
		p.CanCollide = false
		TweenService:Create(p, ti, {
			CFrame       = targetCF,
			Transparency = targetTransparency,
		}):Play()

		-- 하위 Decal / Texture 도 같이 페이드
		for _, d in ipairs(p:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				TweenService:Create(d, ti, {
					Transparency = targetTransparency,
				}):Play()
			end
		end
	end
end

local function getPivotCF(inst: Instance): CFrame
	if inst:IsA("Model") then return inst:GetPivot() end
	local cf, _ = inst:GetBoundingBox()
	return cf
end

local function outwardDir(wing: Instance, rootPivot: CFrame): Vector3
	local wingPivot: CFrame
	if wing:IsA("Model") then
		wingPivot = wing:GetPivot()
	else
		local cf, _ = (wing :: any):GetBoundingBox()
		wingPivot = cf
	end

	local rv = rootPivot.RightVector
	local sign = ((wingPivot.Position - rootPivot.Position):Dot(rv) >= 0) and 1 or -1
	return rv * sign
end

-- =========================================================
-- 🔸 카메라를 포탈 쪽으로 부드럽게 이동시키는 헬퍼 (클라이언트에서만 사용)
-- =========================================================
function M.MoveCameraIntoPortal(stage: number, camDistance: number?, duration: number?): boolean
	-- 서버에서 require 해서 호출해도 안전하게 무시
	if not RunService:IsClient() then
		warn("[PortalMover] MoveCameraIntoPortal 는 클라이언트에서만 사용 가능합니다.")
		return false
	end

	stage       = tonumber(stage) or 1
	camDistance = camDistance or 10
	duration    = duration    or 1.6

	local root = findPortalRootAnywhere(stage)
	if not root then
		warn(("[PortalMover] Portal root not found for MoveCameraIntoPortal (Stage%dPotal/Stage%02dPotal)."):format(stage, stage))
		return false
	end

	local cam = Workspace.CurrentCamera
	if not cam then
		warn("[PortalMover] CurrentCamera 없음 (MoveCameraIntoPortal).")
		return false
	end

	-- ✅ 다른 컷씬 시작 시 이 카메라 트윈도 끊기도록 토큰 시작(가능하면)
	local token: any = nil
	if CutsceneManager and CutsceneManager.Begin then
		token = CutsceneManager.Begin("PortalMover_MoveCameraIntoPortal")
	end

	local rootPivot = getPivotCF(root)

	-- 카메라가 바라볼 지점(포탈 중심)
	local lookTarget = rootPivot.Position
	local forward = rootPivot.LookVector

	local targetPos = lookTarget - forward * camDistance + Vector3.new(0, 2, 0)
	local targetCF  = CFrame.new(targetPos, lookTarget)

	-- 카메라를 스크립트 모드로 전환
	cam.CameraType = Enum.CameraType.Scriptable

	local tween = TweenService:Create(cam, TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
		), {
			CFrame = targetCF
		})

	if token and token.AddTween and token.OnCancel then
		token:AddTween(tween)
		token:OnCancel(function()
			-- 취소/종료 시 카메라 복구
			if cam and cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Custom
			end
		end)
	end

	tween:Play()

	-- duration 이후에 다시 Custom (토큰 있으면 토큰 방식으로 종료)
	if token and token.Delay and token.Cancel then
		token:Delay(duration + 0.1, function()
			token:Cancel("finish_camera")
		end)
	else
		task.delay(duration + 0.1, function()
			if cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Custom
			end
		end)
	end

	return true
end

-- ===== 공개 API: Open (문 열기) =====
function M.Open(stage, distance, duration): boolean
	stage    = tonumber(stage) or 1
	distance = distance or 6

	-- ★ 문 열리는 시간: 최소 3초 보장
	local baseDuration = duration or 3.0
	duration = math.max(baseDuration, 3.0)

	local root = findPortalRootAnywhere(stage)
	if not root then
		warn(("[PortalMover] Portal root not found (Stage%dPotal/Stage%02dPotal)."):format(stage, stage))
		return false
	end

	local left  = root:FindFirstChild("Left")
	local right = root:FindFirstChild("Right")
	if not (left or right) then
		warn("[PortalMover] Left/Right missing under:", root:GetFullName())
		return false
	end

	local rootPivot = getPivotCF(root)

	-- ★ 문 열기(양 날개 바깥쪽으로 이동 + 그동안 점점 투명해지기)
	if left then
		tweenPartsMoveAndFade(collectParts(left),  outwardDir(left,  rootPivot) * distance, duration)
	end
	if right then
		tweenPartsMoveAndFade(collectParts(right), outwardDir(right, rootPivot) * distance, duration)
	end

	return true
end

-- ===== 공개 API: FadeOut (컷씬 끝나고 호출) =====
function M.FadeOut(stage, fadeDuration): boolean
	stage        = tonumber(stage) or 1
	fadeDuration = fadeDuration or 0

	local root = findPortalRootAnywhere(stage)
	if not root then
		warn(("[PortalMover] Portal root not found for FadeOut (Stage%dPotal/Stage%02dPotal)."):format(stage, stage))
		return false
	end

	local left  = root:FindFirstChild("Left")
	local right = root:FindFirstChild("Right")
	if not (left or right) then
		warn("[PortalMover] Left/Right missing under (FadeOut):", root:GetFullName())
		return false
	end

	local function fadeWing(wing: Instance)
		local parts = collectParts(wing)
		for _, p in ipairs(parts) do
			local ti = TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(p, ti, { Transparency = 1 }):Play()
			p.CanCollide = false
		end

		if wing:IsA("BasePart") then
			local bp = wing :: BasePart
			local ti = TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(bp, ti, { Transparency = 1 }):Play()
			bp.CanCollide = false
		end
	end

	if left then fadeWing(left) end
	if right then fadeWing(right) end

	return true
end

return M

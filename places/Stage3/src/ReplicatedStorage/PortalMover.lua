-- ReplicatedStorage/PortalMover.lua
--!strict
-- 🔹 목적: "문 열기(Open)" + "문 숨기기(FadeOut)" 제공 (카메라 없음)
-- 🔹 동작: 루트 RightVector 기준으로 Left는 왼쪽(−Right), Right는 오른쪽(+Right)

local TweenService = game:GetService("TweenService")
local Workspace    = game:GetService("Workspace")

local M = {}

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

local function tweenParts(parts: {BasePart}, worldOffset: Vector3, duration: number?, easingStyle, easingDir)
	duration    = duration    or 0.8
	easingStyle = easingStyle or Enum.EasingStyle.Quad
	easingDir   = easingDir   or Enum.EasingDirection.Out
	for _, p in ipairs(parts) do
		local cf0 = p.CFrame
		local rot = cf0 - cf0.Position
		local target = CFrame.new(cf0.Position + worldOffset) * rot
		TweenService:Create(p, TweenInfo.new(duration, easingStyle, easingDir), { CFrame = target }):Play()
	end
end

local function getPivotCF(inst: Instance): CFrame
	if inst:IsA("Model") then return inst:GetPivot() end
	local cf, _ = inst:GetBoundingBox()
	return cf
end

local function outwardDir(wing: Instance, rootPivot: CFrame): Vector3
	local wingPivot = if wing:IsA("Model")
		then wing:GetPivot()
		else CFrame.new((wing :: any):GetBoundingBox())
	local rv = rootPivot.RightVector
	local sign = ((wingPivot.Position - rootPivot.Position):Dot(rv) >= 0) and 1 or -1
	return rv * sign
end

-- ===== 공개 API: Open =====
function M.Open(stage, distance, duration): boolean
	stage    = tonumber(stage) or 1
	distance = distance or 6
	duration = duration or 0.8

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

	-- 문 열기(양 날개 바깥쪽으로 이동)
	if left then
		tweenParts(collectParts(left),  outwardDir(left,  rootPivot) * distance, duration)
	end
	if right then
		tweenParts(collectParts(right), outwardDir(right, rootPivot) * distance, duration)
	end

	return true
end

-- ===== 공개 API: FadeOut (컷씬 끝나고 호출) =====
function M.FadeOut(stage, fadeDuration): boolean
	stage        = tonumber(stage) or 1
	fadeDuration = 0

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
			TweenService:Create(p, ti, {
				Transparency = 1,
			}):Play()
			p.CanCollide = false
		end

		if wing:IsA("BasePart") then
			local bp = wing :: BasePart
			local ti = TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(bp, ti, {
				Transparency = 1,
			}):Play()
			bp.CanCollide = false
		end
	end

	if left then fadeWing(left) end
	if right then fadeWing(right) end

	return true
end

return M

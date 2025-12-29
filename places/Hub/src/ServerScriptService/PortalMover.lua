local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local M = {}
local opened = {}

local function collectParts(inst)
	local out = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end

local function tweenParts(parts, worldOffset, duration, easingStyle, easingDir)
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

local function portalRootName(stage) return string.format("Stage%dPotal", stage) end

-- 날개가 루트의 어느 쪽에 있는지로 "바깥쪽" 방향을 결정
local function outwardDir(wing, rootPivot)
	local wingPivot = wing:IsA("Model") and wing:GetPivot() or CFrame.new(wing:GetBoundingBox())
	local rv = rootPivot.RightVector
	local sign = ((wingPivot.Position - rootPivot.Position):Dot(rv) >= 0) and 1 or -1
	-- sign=+1 ⇒ 루트의 +X(오른쪽)에 있는 날개 → +RightVector(오른쪽)으로 이동
	-- sign=-1 ⇒ 루트의 -X(왼쪽)에 있는 날개 → -RightVector(왼쪽)으로 이동
	return rv * sign
end

function M.Open(stage, distance, duration)
	stage = tonumber(stage) or 1
	if opened[stage] then return true end

	local root  = workspace.Stage01:FindFirstChild(portalRootName(stage))
	if not root then warn(("Portal %s not found"):format(portalRootName(stage))); return false end
	local left  = root:FindFirstChild("Left")
	local right = root:FindFirstChild("Right")
	if not (left or right) then warn("[PortalMover] Left/Right missing"); return false end

	distance = distance or 6
	local rootPivot = (root:IsA("Model") and root:GetPivot()) or CFrame.new(root:GetBoundingBox())

	if left  then tweenParts(collectParts(left),  outwardDir(left,  rootPivot) * distance, duration) end
	if right then tweenParts(collectParts(right), outwardDir(right, rootPivot) * distance, duration) end

	opened[stage] = true
	return true
end

function M.Close(stage, distance, duration)
	stage = tonumber(stage) or 1
	local root  = workspace:FindFirstChild(portalRootName(stage)); if not root then return false end
	local left  = root:FindFirstChild("Left")
	local right = root:FindFirstChild("Right"); if not (left or right) then return false end

	distance = distance or 6
	local rootPivot = (root:IsA("Model") and root:GetPivot()) or CFrame.new(root:GetBoundingBox())

	if left  then tweenParts(collectParts(left),  -outwardDir(left,  rootPivot) * distance, duration) end
	if right then tweenParts(collectParts(right), -outwardDir(right, rootPivot) * distance, duration) end

	opened[stage] = nil
	return true
end

function M.SpawnAndDrop(stage:number, opts:table?)
	opts = opts or {}

	local function portalName(n:number) return ("Stage%dPotal"):format(n) end
	local function findModelAnywhere(root: Instance, name: string): Instance?
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and d.Name == name then return d end
		end
		return nil
	end
	local function getPivotCF(inst: Instance): CFrame
		if inst:IsA("Model") then return inst:GetPivot() end
		local cf,_ = inst:GetBoundingBox(); return cf
	end

	-- 1) 템플릿 검색
	local template =
		ReplicatedStorage:FindFirstChild(portalName(stage))
		or (ReplicatedStorage:FindFirstChild("Portals") and ReplicatedStorage.Portals:FindFirstChild(portalName(stage)))
	if not template or not template:IsA("Model") then
		warn(("[PortalMover] SpawnAndDrop: Template %s not found"):format(portalName(stage)))
		return nil
	end

	-- 2) 부모 폴더: 옵션 > 이전 포탈 부모 > Workspace
	local prevRoot = findModelAnywhere(workspace, portalName(stage - 1))
	local parent = opts.parentFolder or (prevRoot and prevRoot.Parent) or workspace

	-- 3) 목표 '위치'만 결정 (회전은 템플릿 그대로 유지)
	local targetPos: Vector3
	do
		if typeof(opts.targetPosition) == "Vector3" then
			targetPos = opts.targetPosition
		elseif opts.slotName then
			local slot = parent:FindFirstChild(opts.slotName, true) or findModelAnywhere(parent, opts.slotName)
			if slot then
				local cf = slot:IsA("BasePart") and slot.CFrame or getPivotCF(slot)
				targetPos = cf.Position
			end
		end
		if not targetPos then
			if prevRoot then
				-- 이전 포탈 앞쪽 8스튜드 (이전 포탈의 회전은 사용 X, 위치만 참조)
				local pv = getPivotCF(prevRoot)
				targetPos = (pv * CFrame.new(0, 0, -8)).Position
			else
				-- 템플릿 피벗 위치
				targetPos = getPivotCF(template).Position
			end
		end
	end

	-- 4) 템플릿 '회전 고정'으로 최종/시작 CFrame 구성
	local baseCF = getPivotCF(template)  -- 템플릿의 원래 회전 유지
	local targetCF = CFrame.fromMatrix(targetPos, baseCF.RightVector, baseCF.UpVector)

	local clone = template:Clone()
	clone.Name = portalName(stage)
	clone.Parent = parent

	local dropH        = opts.dropHeight or 35
	local delayBefore  = opts.delayBeforeDrop or 0.5
	local dropTime     = opts.dropTime or 1.0
	local startCF      = targetCF * CFrame.new(0, dropH, 0)

	clone:PivotTo(startCF)

	task.delay(delayBefore, function()
		local cfv = Instance.new("CFrameValue")
		cfv.Value = startCF
		cfv.Changed:Connect(function(v) clone:PivotTo(v) end)

		local tw = TweenService:Create(cfv, TweenInfo.new(dropTime, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Value = targetCF
		})
		tw:Play()
		Debris:AddItem(cfv, dropTime + 0.2)
	end)

	return clone
end


return M

-- ReplicatedStorage/Modules/InteractionActionRouter.lua
--!strict

local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace") -- ★ HitEffect용

local M = {}

-- ★ HitEffect 템플릿
local HitEffectTemplate: Instance? = RS:FindFirstChild("HitEffect")

-- tag → action(root, ctx)
local _actions: {[string]: (Instance, {[string]: any}) -> ()} = {}

-- 인스턴스별 디바운스(중복 실행 방지)
local _busy = setmetatable({}, { __mode = "k" }) :: {[Instance]: boolean}

-- ===================== 유틸 =====================

local function hasAnyTag(inst: Instance?, tags: {string}): (boolean, string?)
	if not inst then return false, nil end
	for _, t in ipairs(tags) do
		if CollectionService:HasTag(inst, t) then
			return true, t
		end
	end
	return false, nil
end

local function findAncestorWithAnyTag(inst: Instance?, tags: {string}): (Instance?, string?)
	if not inst then return nil, nil end
	local cur = inst
	while cur do
		local ok, tag = hasAnyTag(cur, tags)
		if ok then return cur, tag end
		cur = cur.Parent
	end
	return nil, nil
end

local function findAncestorByName(inst: Instance?, names: {string}): Instance?
	if not inst then return nil end
	local set: {[string]: boolean} = {}
	for _,n in ipairs(names) do set[n]=true end
	local cur = inst
	while cur do
		if set[cur.Name] then return cur end
		cur = cur.Parent
	end
	return nil
end

local function tween(inst: Instance, ti: TweenInfo, props: {[string]: any})
	local ok, tw = pcall(function() return TweenService:Create(inst, ti, props) end)
	if ok and tw then tw:Play() end
	return ok and tw or nil
end

-- ★ 중심 CFrame 계산: 항상 "묶음의 가운데"에서 이펙트 나오게
local function computeCenterCFrame(source: Instance): CFrame?
	-- 1) Model이면 GetBoundingBox 기준
	if source:IsA("Model") then
		local m = source :: Model
		local cf, _ = m:GetBoundingBox()
		return cf
	end

	-- 2) 자신 + 자손 BasePart들 평균 위치 사용
	local parts: {BasePart} = {}

	if source:IsA("BasePart") then
		table.insert(parts, source :: BasePart)
	end

	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end

	if #parts > 0 then
		local sum = Vector3.zero
		for _, p in ipairs(parts) do
			sum += p.Position
		end
		local center = sum / #parts
		-- 첫 파츠 방향을 유지해서 CFrame 구성
		local first = parts[1]
		local look = first.CFrame.LookVector
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		return CFrame.new(center, center + look)
	end

	-- 3) 위에서 못 찾았으면, 조상 Model/Part 기준으로 한 번 더 시도
	local ancestorModel = source:FindFirstAncestorOfClass("Model")
	if ancestorModel then
		local cf, _ = (ancestorModel :: Model):GetBoundingBox()
		return cf
	end

	local ancestorPart = source:FindFirstAncestorWhichIsA("BasePart")
	if ancestorPart then
		return (ancestorPart :: BasePart).CFrame
	end

	return nil
end

-- ★ HitEffect 재생 함수: 항상 "중심" 위치에서
local function playHitEffect(source: Instance)
	if not HitEffectTemplate then return end

	local cf = computeCenterCFrame(source)
	if not cf then return end

	local clone = HitEffectTemplate:Clone()
	clone.Parent = Workspace

	if clone:IsA("Model") then
		(clone :: Model):PivotTo(cf)
	elseif clone:IsA("BasePart") then
		(clone :: BasePart).CFrame = cf
	else
		-- Model/Part가 아니면 자식 중 Model/Part 찾아서 맞춰 줌
		local childModel = clone:FindFirstChildWhichIsA("Model", true)
		if childModel then
			(childModel :: Model):PivotTo(cf)
		else
			local childPart = clone:FindFirstChildWhichIsA("BasePart", true)
			if childPart then
				(childPart :: BasePart).CFrame = cf
			end
		end
	end

	-- 3초 뒤 삭제
	task.delay(3, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)
end

-- ===================== 공개 API =====================

function M.inspectAncestor(inst: Instance): {ancestor: Instance?, tags: {string}}
	local cur = inst
	while cur do
		local tags = CollectionService:GetTags(cur)
		if #tags > 0 then
			return { ancestor = cur, tags = tags }
		end
		cur = cur.Parent
	end
	return { ancestor = nil, tags = {} }
end

function M.register(tag: string, fn: (Instance, {[string]: any}) -> ())
	_actions[tag] = fn
end

function M.registerMany(map: {[string]: (Instance, {[string]: any}) -> ()})
	for tag, fn in pairs(map) do
		M.register(tag, fn)
	end
end

-- 정답 등 트리거 시 호출
function M.run(inst: Instance, ctx: {[string]: any}?, opts: {[string]: any}?)
	ctx = ctx or {}
	opts = opts or {}
	local targetTags: {string} = {}
	local matchedTag: string? = nil

	if opts.targetTags and #opts.targetTags > 0 then
		targetTags = opts.targetTags
	else
		for tag, _ in pairs(_actions) do
			table.insert(targetTags, tag)
		end
	end
	if #targetTags == 0 then
		warn("[ActionRouter] 등록된 태그 없음")
		return
	end

	-- 1) Box/seaShell: 프롬프트 기준 부모의 부모 우선
	local preferGrand = opts.preferGrandparentFor or { "Box", "seaShell" }
	local root: Instance? = nil
	do
		local gp = inst.Parent and inst.Parent.Parent or nil
		if gp then
			local ok, tag = hasAnyTag(gp, preferGrand)
			if ok then
				root, matchedTag = gp, tag
			else
				if findAncestorByName(inst, preferGrand) == gp then
					root, matchedTag = gp, gp.Name
				end
			end
		end
	end

	-- 2) 일반 태그 검색
	if not root then
		root, matchedTag = findAncestorWithAnyTag(inst, targetTags)
	end

	-- 3) 이름 폴백(Box/seaShell)
	if not root then
		local nameFallbacks = {}
		for _, t in ipairs(targetTags) do
			if t == "Box" or t == "seaShell" then table.insert(nameFallbacks, t) end
		end
		if #nameFallbacks > 0 then
			root = findAncestorByName(inst, nameFallbacks)
			matchedTag = root and root.Name or nil
		end
	end

	if not root then
		warn("[ActionRouter] 매칭 조상 없음:", inst:GetFullName())
		return
	end

	local tag = matchedTag
	if not tag then
		for _, t in ipairs(targetTags) do
			if CollectionService:HasTag(root, t) then tag = t; break end
		end
	end
	if not tag then
		warn("[ActionRouter] 태그 매칭 실패:", root:GetFullName())
		return
	end

	if opts.debounce ~= false then
		if _busy[root] then return end
		_busy[root] = true
	end

	local action = _actions[tag]
	if not action then
		_busy[root] = nil
		warn(("[ActionRouter] '%s' 태그 액션 미등록"):format(tag))
		return
	end

	-- 🔥 여기서 바로 HitEffect 먼저 재생 (조금이라도 더 빠르게)
	--    필요하면 ctx.playHitEffect = false 로 비활성화 가능
	if ctx.playHitEffect ~= false then
		playHitEffect(root)
	end

	local okRun, err = pcall(function()
		action(root :: Instance, ctx)
	end)
	if not okRun then
		warn("[ActionRouter] 액션 실행 오류:", err)
	end

	_busy[root] = nil
end

-- ===================== 기본 액션 =====================

local function actionDisappear(root: Instance, ctx)
	local dur = ctx.fadeDuration or 0.35
	local delayDestroy = ctx.delayDestroy or 0.0
	local parts: {BasePart} = {}

	-- HitEffect는 M.run 쪽에서 이미 실행

	if root:IsA("BasePart") then
		table.insert(parts, root)
	elseif root:IsA("Model") or root:IsA("Folder") then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	else
		return
	end

	for _, p in ipairs(parts) do
		p.CanCollide = false
		p.CastShadow = false
		tween(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
	end
	task.wait(dur + delayDestroy)

	if root:IsA("Model") or root:IsA("Folder") then
		root:Destroy()
	else
		(root :: BasePart):Destroy()
	end
end

local function actionDoorOpen(root: Instance, ctx)
	local doorName = ctx.doorName or "Door"
	local yawDeg = ctx.yawDeg or 35
	local dur = ctx.duration or 0.6

	local door: BasePart? = nil
	if root:IsA("Model") then
		local found = root:FindFirstChild(doorName)
		if found and found:IsA("BasePart") then door = found end
	elseif root:IsA("BasePart") then
		door = root
	end
	if not door then return end

	local cf = door.CFrame
	local open = cf * CFrame.Angles(0, math.rad(yawDeg), 0)
	tween(door, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = open })
end

local function actionPortalNeonOn(root: Instance, ctx)
	local color: Color3 = ctx.portalColor or Color3.fromRGB(0, 255, 120)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.Neon
			d.Color = color
		end
	end
end

-- ===================== 신규 액션 (완전 교체: 위치+회전 보존) =====================

local function pickAnchorPartFrom(inst: Instance): BasePart?
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		local m = inst :: Model
		if m.PrimaryPart then return m.PrimaryPart end
		for _,d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then return d end
		end
	end
	local p = inst:FindFirstAncestorWhichIsA("BasePart")
	return p
end

local function pickMatchingAnchorInClone(clone: Instance, nameHint: string?): BasePart?
	if clone:IsA("Model") then
		local m = clone :: Model
		if nameHint and #nameHint > 0 then
			local cand = m:FindFirstChild(nameHint, true)
			if cand and cand:IsA("BasePart") then return cand end
		end
		if m.PrimaryPart then return m.PrimaryPart end
		for _,d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then return d end
		end
	elseif clone:IsA("BasePart") then
		return clone
	end
	return nil
end

local function actionReplaceWithRS(root: Instance, ctx)
	local rootModel: Model? = nil
	if root:IsA("Model") then
		rootModel = root
	else
		rootModel = root:FindFirstAncestorOfClass("Model")
	end
	local target: Instance = rootModel or root
	local parent = target.Parent
	if not parent then return end

	-- HitEffect는 M.run 쪽에서 이미 실행

	local targetAnchor: BasePart? = pickAnchorPartFrom(target)
	local targetPivot: CFrame?
	if target:IsA("Model") then
		targetPivot = (target :: Model):GetPivot()
	elseif target:IsA("BasePart") then
		targetPivot = (target :: BasePart).CFrame
	end
	if not targetAnchor and not targetPivot then
		warn("[ActionRouter] 교체 위치를 계산할 수 없습니다.")
		return
	end

	local targetName = target.Name
	local template = RS:FindFirstChild(targetName)
	if not template then
		warn(("[ActionRouter] RS에 '%s' 템플릿이 없습니다."):format(targetName))
		return
	end

	local clone = template:Clone()
	clone.Name = targetName
	clone.Parent = parent

	if targetAnchor then
		local anchorName = targetAnchor.Name
		local cloneAnchor: BasePart? = pickMatchingAnchorInClone(clone, anchorName)
		if cloneAnchor then
			local delta = targetAnchor.CFrame * cloneAnchor.CFrame:Inverse()
			if clone:IsA("Model") then
				(clone :: Model):PivotTo(delta * (clone :: Model):GetPivot())
			elseif clone:IsA("BasePart") then
				(clone :: BasePart).CFrame = delta * (clone :: BasePart).CFrame
			end
		elseif targetPivot then
			if clone:IsA("Model") then
				(clone :: Model):PivotTo(targetPivot)
			elseif clone:IsA("BasePart") then
				(clone :: BasePart).CFrame = targetPivot
			end
		end
	elseif targetPivot then
		if clone:IsA("Model") then
			(clone :: Model):PivotTo(targetPivot)
		elseif clone:IsA("BasePart") then
			(clone :: BasePart).CFrame = targetPivot
		end
	end

	for _, tag in ipairs(CollectionService:GetTags(target)) do
		CollectionService:AddTag(clone, tag)
	end
	local attrs = target:GetAttributes()
	for k, v in pairs(attrs) do
		pcall(function() clone:SetAttribute(k, v) end)
	end

	target:Destroy()
end

-- ===================== 기본 등록 =====================
M.registerMany({
	Disappear       = actionDisappear,
	VanishOnCorrect = actionDisappear,
	DoorOpen        = actionDoorOpen,
	PortalNeonOn    = actionPortalNeonOn,
})

M.register("Box", actionReplaceWithRS)
M.register("seaShell", actionReplaceWithRS)

function M.debugDescribeAncestor(inst: Instance): string
	local info = M.inspectAncestor(inst)
	if not info.ancestor then
		return "[Ancestor] 없음"
	end
	local names = table.concat(CollectionService:GetTags(info.ancestor :: Instance), ", ")
	return string.format("[Ancestor] %s | Tags: %s", (info.ancestor :: Instance):GetFullName(), names)
end

function M.debugWalk(inst: Instance)
	local cur = inst
	print("=== [ActionRouter] Ancestor Walk ===")
	while cur do
		local tags = CollectionService:GetTags(cur)
		print( string.format(" - %s (Tags: %s)", cur:GetFullName(), (#tags>0 and table.concat(tags,", ") or "-")) )
		cur = cur.Parent
	end
	print("=== [ActionRouter] End Walk ===")
end

return M

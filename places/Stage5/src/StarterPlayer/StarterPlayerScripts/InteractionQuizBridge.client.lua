-- ReplicatedStorage/Modules/InteractionActionRouter.lua
--!strict
-- 인터랙션 지점의 상위 부모(ancestor)를 찾아 태그별로 액션 실행.
-- 기본 액션: Disappear(사라짐), DoorOpen(문 열기), PortalNeonOn(포탈 네온)
-- 신규 액션: Box / seaShell → ReplicatedFirst의 동일 이름 템플릿으로 "완전 교체"

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local M = {}

-- tag → action(root, ctx)
local _actions: {[string]: (Instance, {[string]: any}) -> ()} = {}

-- 인스턴스별 디바운스(중복 실행 방지)
local _busy = setmetatable({}, { __mode = "k" }) :: {[Instance]: boolean}

-- ===================== 유틸 =====================

-- inst 기준으로 부모 방향으로 올라가며, tags 중 하나라도 가진 첫 조상 반환
local function findAncestorWithAnyTag(inst: Instance?, tags: {string}): Instance?
	if not inst then return nil end
	local tagSet: {[string]: boolean} = {}
	for _, t in ipairs(tags) do tagSet[t] = true end

	local cur = inst
	while cur do
		for _, t in ipairs(CollectionService:GetTags(cur)) do
			if tagSet[t] then
				return cur
			end
		end
		cur = cur.Parent
	end
	return nil
end

-- 조상의 태그 목록
local function getAllTags(inst: Instance): {string}
	return CollectionService:GetTags(inst)
end

-- tags 배열 순서대로 우선순위 매칭
local function firstMatchingTag(inst: Instance, tags: {string}): string?
	for _, t in ipairs(tags) do
		if CollectionService:HasTag(inst, t) then
			return t
		end
	end
	return nil
end

local function tween(inst: Instance, ti: TweenInfo, props: {[string]: any})
	local ok, tw = pcall(function() return TweenService:Create(inst, ti, props) end)
	if ok and tw then tw:Play() end
	return ok and tw or nil
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

	local root = findAncestorWithAnyTag(inst, targetTags)
	if not root then
		warn("[ActionRouter] 매칭 조상 없음:", inst:GetFullName())
		return
	end
	if opts.debounce ~= false then
		if _busy[root] then return end
		_busy[root] = true
	end

	local tag = firstMatchingTag(root, targetTags)
	if not tag then
		_busy[root] = nil
		warn("[ActionRouter] 태그 매칭 실패:", root:GetFullName())
		return
	end

	local action = _actions[tag]
	if not action then
		_busy[root] = nil
		warn(("[ActionRouter] '%s' 태그 액션 미등록"):format(tag))
		return
	end

	local ok, err = pcall(function()
		action(root, ctx)
	end)
	if not ok then
		warn("[ActionRouter] 액션 실행 오류:", err)
	end

	_busy[root] = nil
end

-- ===================== 기본 액션 =====================

-- 1) Disappear / VanishOnCorrect : 파트(또는 모델 내 모든 BasePart) 페이드 아웃 후 제거
local function actionDisappear(root: Instance, ctx)
	local dur = ctx.fadeDuration or 0.35
	local delayDestroy = ctx.delayDestroy or 0.0
	local parts: {BasePart} = {}

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

-- 2) DoorOpen : 문 살짝 열기(힌지 회전 예시)
local function actionDoorOpen(root: Instance, ctx)
	local doorName = ctx.doorName or "Door"
	local yawDeg = ctx.yawDeg or 35
	local dur = ctx.duration or 0.6

	local door: BasePart? = nil
	if root:IsA("Model") then
		local found = root:FindChild(doorName)
		if found and found:IsA("BasePart") then door = found end
	elseif root:IsA("BasePart") then
		door = root
	end
	if not door then return end

	local cf = door.CFrame
	local open = cf * CFrame.Angles(0, math.rad(yawDeg), 0)
	tween(door, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = open })
end

-- 3) PortalNeonOn : 포탈을 네온+색 변경
local function actionPortalNeonOn(root: Instance, ctx)
	local color: Color3 = ctx.portalColor or Color3.fromRGB(0, 255, 120)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.Neon
			d.Color = color
		end
	end
end

-- ===================== 신규 액션 (완전 교체) =====================

-- Box / seaShell : ReplicatedFirst의 동일 이름 템플릿으로 "완전 교체"
local function actionReplaceWithReplicatedFirst(root: Instance, ctx)
	-- 교체 대상은 가능하면 모델 루트
	local rootModel: Model? = nil
	if root:IsA("Model") then
		rootModel = root
	else
		rootModel = root:FindFirstAncestorOfClass("Model")
	end

	local target: Instance = rootModel or root
	local targetName = target.Name
	local parent = target.Parent
	if not parent then return end

        local template = ReplicatedFirst:FindFirstChild(targetName)
        if not template then
                warn(("[ActionRouter] ReplicatedFirst에 '%s' 템플릿이 없습니다."):format(targetName))
                return
        end

	-- 현재 위치(피벗) 확보
	local pivotCF: CFrame
	if target:IsA("Model") then
		pivotCF = (target :: Model):GetPivot()
	elseif target:IsA("BasePart") then
		pivotCF = (target :: BasePart).CFrame
	else
		local m = target:FindFirstAncestorOfClass("Model")
		if m then pivotCF = m:GetPivot() else
			local p = target:FindFirstAncestorWhichIsA("BasePart")
			if p then pivotCF = p.CFrame else
				warn("[ActionRouter] 교체 위치를 계산할 수 없습니다."); return
			end
		end
	end

	-- 새 클론 생성(부모/이름/피벗 동일하게)
	local clone = template:Clone()
	clone.Name = targetName
	clone.Parent = parent

	if clone:IsA("Model") then
		(clone :: Model):PivotTo(pivotCF)
	elseif clone:IsA("BasePart") then
		(clone :: BasePart).CFrame = pivotCF
	else
		local childModel = clone:FindFirstChildOfClass("Model")
		if childModel then childModel:PivotTo(pivotCF)
		else
			local childPart = clone:FindFirstChildWhichIsA("BasePart", true)
			if childPart then childPart.CFrame = pivotCF end
		end
	end

	-- 태그와 Attributes를 신형으로 이관
	for _, tag in ipairs(CollectionService:GetTags(target)) do
		CollectionService:AddTag(clone, tag)
	end
	local attrs = target:GetAttributes()
	for k, v in pairs(attrs) do
		pcall(function() clone:SetAttribute(k, v) end)
	end

	-- 완전 교체: 기존 타겟 즉시 제거
	target:Destroy()
end

-- ===================== 기본 등록 =====================
M.registerMany({
	Disappear      = actionDisappear,
	VanishOnCorrect= actionDisappear, -- 동의어
	DoorOpen       = actionDoorOpen,
	PortalNeonOn   = actionPortalNeonOn,
})

-- 신규 태그 등록(완전 교체)
M.register("Box", actionReplaceWithReplicatedFirst)
M.register("seaShell", actionReplaceWithReplicatedFirst)

-- 디버그: 상위 부모/태그 문자열
function M.debugDescribeAncestor(inst: Instance): string
	local info = M.inspectAncestor(inst)
	if not info.ancestor then
		return "[Ancestor] 없음"
	end
	local names = table.concat(getAllTags(info.ancestor :: Instance), ", ")
	return string.format("[Ancestor] %s | Tags: %s", (info.ancestor :: Instance):GetFullName(), names)
end

return M

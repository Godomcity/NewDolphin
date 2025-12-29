-- StarterPlayerScripts/QuestArrowGuide.client.lua
--!strict

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local LP = Players.LocalPlayer

task.wait(2)

local QUEST_TAG_NPC     = "QuestNPC"
local QUEST_TAG_OBJECT  = "QuestObject"

local PORTAL_TAG        = "Stage2Potal"
local PORTAL_NAME       = "Potal"

local ARROW_TEXTURE_ID  = "rbxassetid://5662246193"
local ATTACH_OFFSET     = Vector3.new(0, 0, 0)

-- ========= 유틸 =========
local function findByTagOrName(tagName: string): Instance?
	local tagged = CollectionService:GetTagged(tagName)
	if #tagged > 0 then
		return tagged[1]
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == tagName then
			return inst
		end
	end
	return nil
end

local function getAnyBasePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		local m = inst :: Model
		if m.PrimaryPart then
			return m.PrimaryPart
		end
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function getPortalRootFrom(inst: Instance?): Instance?
	if not inst then return nil end
	if inst:IsA("Model") or inst:IsA("BasePart") then
		return inst
	end
	local cur: Instance? = inst
	while cur do
		if cur:IsA("Model") or cur:IsA("BasePart") then
			return cur
		end
		cur = cur.Parent
	end
	return inst
end

local function findPortalTarget(payload: any?): Instance?
	if typeof(payload) == "Instance" then
		return getPortalRootFrom(payload)
	end

	local tagged = CollectionService:GetTagged(PORTAL_TAG)
	if #tagged > 0 then
		return getPortalRootFrom(tagged[1])
	end

	local byName = workspace:FindFirstChild(PORTAL_NAME, true)
	if byName then
		return getPortalRootFrom(byName)
	end

	return nil
end

-- ========= Beam/Attachment 상태 =========
local guideFolder: Folder? = nil
local att0: Attachment? = nil
local att1: Attachment? = nil
local guideBeam: Beam? = nil
local currentTargetPart: BasePart? = nil

local function ensureFolder(): Folder
	if guideFolder and guideFolder.Parent then
		return guideFolder
	end
	local f = Instance.new("Folder")
	f.Name = "_QuestGuideBeam_Local"
	f.Parent = workspace
	guideFolder = f
	return f
end

local function clearBeam()
	if guideBeam then guideBeam:Destroy() end
	if att0 then att0:Destroy() end
	if att1 then att1:Destroy() end
	guideBeam, att0, att1 = nil, nil, nil
end

local function ensureSourceAttachment(): Attachment?
	local char = LP.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	if att0 and att0.Parent == root then
		return att0
	end

	if att0 then att0:Destroy() end
	local a = Instance.new("Attachment")
	a.Name = "QuestGuide_Att0"
	a.Position = ATTACH_OFFSET
	a.Parent = root
	att0 = a
	return a
end

local function ensureTargetAttachment(): Attachment?
	if not currentTargetPart then return nil end

	if att1 and att1.Parent == currentTargetPart then
		return att1
	end

	if att1 then att1:Destroy() end
	local a = Instance.new("Attachment")
	a.Name = "QuestGuide_Att1"
	a.Position = ATTACH_OFFSET
	a.Parent = currentTargetPart
	att1 = a
	return a
end

local function rebuildBeam()
	local src = ensureSourceAttachment()
	local dst = ensureTargetAttachment()
	if not src or not dst then
		if guideBeam then guideBeam.Enabled = false end
		return
	end

	local folder = ensureFolder()

	if not guideBeam or not guideBeam.Parent then
		local b = Instance.new("Beam")
		b.Name = "QuestGuideBeam"
		b.Attachment0 = src
		b.Attachment1 = dst

		b.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		b.Width0 = 2
		b.Width1 = 2
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true

		b.Texture = ARROW_TEXTURE_ID
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 4
		b.TextureSpeed = 2

		b.Enabled = true
		b.Parent = folder

		guideBeam = b
	else
		guideBeam.Attachment0 = src
		guideBeam.Attachment1 = dst
		guideBeam.Enabled = true
	end
end

local function setGuideTarget(inst: Instance?)
	currentTargetPart = nil

	if not inst then
		clearBeam()
		return
	end

	local base = getAnyBasePart(inst)
	if not base then
		warn("[QuestArrowGuide] 가이드 타겟 BasePart 를 찾지 못했습니다:", inst:GetFullName())
		clearBeam()
		return
	end

	currentTargetPart = base
	print("[QuestArrowGuide] Guide target set →", currentTargetPart:GetFullName())
	rebuildBeam()
end

local function setGuideTargetByTag(tagName: string)
	local inst = findByTagOrName(tagName)
	if not inst then
		warn(("[QuestArrowGuide] '%s' 대상(태그/이름)을 찾지 못했습니다."):format(tagName))
	end
	setGuideTarget(inst)
end

LP.CharacterAdded:Connect(function()
	task.wait(0.2)
	if currentTargetPart then
		rebuildBeam()
	end
end)

-------------------------------------------------
-- ★ _QuizState 기반으로 초기 가이드 방향 정하기
-------------------------------------------------
local function applyInitialGuideFromQuizState()
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then
		setGuideTargetByTag(QUEST_TAG_NPC)
		return
	end

	local qs = pg:FindFirstChild("_QuizState")
	if not (qs and qs:IsA("Folder")) then
		setGuideTargetByTag(QUEST_TAG_NPC)
		return
	end

	local function getInt(name: string): number
		local v = qs:FindFirstChild(name)
		if v and v:IsA("IntValue") then
			return v.Value
		end
		return 0
	end

	local phase = getInt("QuestPhase")
	local extra = getInt("ExtraTrash")

	if phase <= 0 then
		setGuideTargetByTag(QUEST_TAG_NPC)

	elseif phase == 1 then
		setGuideTargetByTag(QUEST_TAG_OBJECT)

	elseif phase == 2 then
		setGuideTargetByTag(QUEST_TAG_NPC)

	elseif phase >= 3 then
		if extra >= 9 then
			setGuideTargetByTag(QUEST_TAG_NPC)
		else
			setGuideTargetByTag(QUEST_TAG_OBJECT)
		end
	end
end

-- ========= QuestGuideBus 연동 =========
task.spawn(function()
	-- ★ 초기: QuizState를 보고 방향 설정
	applyInitialGuideFromQuizState()

	local bus = RS:WaitForChild("QuestGuideBus", 10)
	if not (bus and bus:IsA("BindableEvent")) then
		warn("[QuestArrowGuide] QuestGuideBus 를 찾지 못했습니다.")
		return
	end

	bus.Event:Connect(function(cmd: any, payload: any?)
		if cmd == "targetNPC" then
			setGuideTargetByTag(QUEST_TAG_NPC)

		elseif cmd == "targetFirstTrash" then
			setGuideTargetByTag(QUEST_TAG_OBJECT)

		elseif cmd == "targetMoreTrash" then
			setGuideTargetByTag(QUEST_TAG_OBJECT)

		elseif cmd == "targetPortal" then
			local portalInst = findPortalTarget(payload)
			if not portalInst then
				warn("[QuestArrowGuide] targetPortal 요청 받았지만 포탈 인스턴스를 찾지 못했습니다.")
			end
			setGuideTarget(portalInst)

		elseif cmd == "hide" or cmd == "off" then
			setGuideTarget(nil)
		end
	end)
end)

print("[QuestArrowGuide] READY (QuizState sync + Beam guide)")

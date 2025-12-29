-- StarterPlayerScripts/HubTalkPrompt.client.lua
--!strict
-- 캐릭터 프롬프트 → DialogueUI 버스 호출

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

-- DialogueUI 버스
local DialogueBus = ReplicatedStorage:FindFirstChild("DialogueUIBus") :: BindableEvent?
if not DialogueBus then
	DialogueBus = Instance.new("BindableEvent")
	DialogueBus.Name = "DialogueUIBus"
	DialogueBus.Parent = ReplicatedStorage
end
local bus = DialogueBus :: BindableEvent

-- 대사 데이터(허브용) - 이전에 만들었던 모듈 재사용
-- 경로: ReplicatedStorage/Modules/HubDialogueData.lua
local Data do
	local Modules = ReplicatedStorage:FindFirstChild("Modules")
	if Modules then
		local mod = Modules:FindFirstChild("HubDialogueData")
		if mod and mod:IsA("ModuleScript") then
			local ok, M = pcall(require, mod)
			if ok then Data = M end
		end
	end
end

-- 태그 → 캐릭터 키
local TAG_TO_KEY: {[string]: string} = {
	["Talk_Turtle"]   = "turtle",
	["Talk_Shark"]    = "shark",
	["Talk_Dolphin"]  = "dolphin",
	["Talk_Seahorse"] = "seahorse",
	["Talk_Crab"]     = "crab",
}

-- 프롬프트별 쿨다운(중복 방지)
local BUSY: {[Instance]: boolean} = setmetatable({}, {__mode="k"})

local function findTaggedAncestor(inst: Instance?): Instance?
	local cur = inst
	while cur do
		for tag in pairs(TAG_TO_KEY) do
			if CollectionService:HasTag(cur, tag) then
				return cur
			end
		end
		cur = cur.Parent
	end
	return nil
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if player ~= LP then return end
	if BUSY[prompt] then return end

	local talkRoot = findTaggedAncestor(prompt)
	if not talkRoot then return end

	local characterKey: string? = nil
	for tag, key in pairs(TAG_TO_KEY) do
		if CollectionService:HasTag(talkRoot, tag) then
			characterKey = key
			break
		end
	end
	if not characterKey then return end

	-- 대사 라인 준비
	local lines: {string} = {}
	if Data and Data.characters and Data.characters[characterKey] then
		local line = Data.characters[characterKey].line
		if typeof(line) == "string" then
			lines = { line }
		elseif typeof(line) == "table" then
			for _, v in ipairs(line) do
				if typeof(v) == "string" then table.insert(lines, v) end
			end
		end
	end
	if #lines == 0 then
		-- 폴백
		lines = { "..." }
	end

	-- Dialogue UI 실행
	BUSY[prompt] = true
	bus:Fire("Play", {
		npc = talkRoot,  -- 제목은 NPC 이름으로 표시
		lines = lines,
	})

	task.delay(0.5, function() BUSY[prompt] = nil end)
end

ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

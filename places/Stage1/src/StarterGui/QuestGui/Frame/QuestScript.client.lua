-- LocalScript @ QuestGui/Frame
--!strict

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer

local StageRolePolicy = require(RS:WaitForChild("Modules"):WaitForChild("StageRolePolicy"))

-- ===== UI 찾기 =====
local root       = script.Parent :: Frame
local questRoot  = root:WaitForChild("Quest") :: Frame
local listFrame  = questRoot:WaitForChild("Frame") :: Frame

local questLabel = listFrame:WaitForChild("1") :: TextLabel
local textLabel  = listFrame:WaitForChild("TextLabel") :: TextLabel
questLabel.RichText = true

-- ✅ 선생님은 QuestGui 안 보이게(아예 로직 실행 X)
local teacherDisconnect: (() -> ())? = nil
local teacherBroadcastDisconnect: (() -> ())? = nil

local function hideQuestForTeacher(reason: string?)
        questRoot.Visible = false

        -- 상위 ScreenGui까지 있으면 통째로 끔(더 확실)
        local gui = root:FindFirstAncestorOfClass("ScreenGui")
        if gui then
                gui.Enabled = false
        end

        if teacherDisconnect then
                teacherDisconnect()
                teacherDisconnect = nil
        end

        if teacherBroadcastDisconnect then
                teacherBroadcastDisconnect()
                teacherBroadcastDisconnect = nil
        end

        print("[QuestClient] Teacher detected -> QuestGui hidden", reason)
end

local function ensureQuestHiddenForTeacher(): boolean
        teacherBroadcastDisconnect = StageRolePolicy.ObserveTeacherBroadcast(LP, function(_, isTeacher)
                if isTeacher then
                        hideQuestForTeacher("(TeacherRoleUpdated)")
                end
        end, 15)

        if StageRolePolicy.WaitForRoleReplication(LP, 12) then
                if StageRolePolicy.IsTeacher(LP) then
                        hideQuestForTeacher("(initial)")
                        return true
                end
        end

        teacherDisconnect = StageRolePolicy.ObserveTeacher(LP, function(isTeacher: boolean, reason: string?)
                if isTeacher then
                        hideQuestForTeacher(reason)
                end
        end, { timeoutSec = 15 })

        return false
end

if ensureQuestHiddenForTeacher() then
        return
end

-- ===== 퀘스트 텍스트 정의 =====
local MAX_QUEST_INDEX   = 5
local TRASH_QUEST_INDEX = 3
local TRASH_TOTAL       = 9

local QUEST_TEXTS: {[number]: string} = {
	[1] = "NPC에게 말 걸기",
	[2] = "오염된 쓰레기 1개 정화 후 NPC에게 말 걸기",
	[3] = "쓰레기 9개 정화하기 0/9",
	[4] = "NPC에게 말 걸기",
	[5] = "다음 스테이지로 이동하기",
}

-- ===== 퀘스트 변경 사운드 =====
local QUEST_CHANGE_SOUND_ID = "rbxassetid://7740696902"

local function playQuestChangeSfx()
	local s = Instance.new("Sound")
	s.SoundId = QUEST_CHANGE_SOUND_ID
	s.Volume = 1
	s.RollOffMode = Enum.RollOffMode.Inverse
	s.Parent = SoundService
	s.Ended:Connect(function()
		if s then s:Destroy() end
	end)
	s:Play()
end

local didSetStage1Label = false

-- ★ 슬라이드용
local BASE_POS_QUEST: UDim2 = questRoot.Position
local currentTweenQuest = nil
local SLIDE_TIME   = 0.45
local SLIDE_OFFSET = -1.0

-- ===== 상태 저장용 값들 =====
local function getStateFolder()
	local pg = LP:WaitForChild("PlayerGui")
	local f = pg:FindFirstChild("_QuestState")
	if not f then
		f = Instance.new("Folder")
		f.Name = "_QuestState"
		f.Parent = pg
	end
	return f
end

local function getCurrentIndexValue(): IntValue
	local f = getStateFolder()
	local v = f:FindFirstChild("CurrentQuest")
	if not v then
		v = Instance.new("IntValue")
		v.Name = "CurrentQuest"
		v.Value = 1
		v.Parent = f
	end
	return v
end

local function getTrashClearedValue(): IntValue
	local f = getStateFolder()
	local v = f:FindFirstChild("TrashCleared")
	if not v then
		v = Instance.new("IntValue")
		v.Name = "TrashCleared"
		v.Value = 0
		v.Parent = f
	end
	return v
end

local function getAllClearedValue(): BoolValue
	local f = getStateFolder()
	local v = f:FindFirstChild("AllCleared")
	if not v then
		v = Instance.new("BoolValue")
		v.Name = "AllCleared"
		v.Value = false
		v.Parent = f
	end
	return v
end

local currentIndexValue = getCurrentIndexValue()
local trashClearedValue = getTrashClearedValue()
local allClearedValue   = getAllClearedValue()

local function syncFromQuizState()
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return end

	local qs = pg:FindFirstChild("_QuizState")
	if not (qs and qs:IsA("Folder")) then
		return
	end

	local phaseValue = qs:FindFirstChild("QuestPhase")
	local extraValue = qs:FindFirstChild("ExtraTrash")

	local phase = 0
	local extra = 0

	if phaseValue and phaseValue:IsA("IntValue") then
		phase = phaseValue.Value
	end
	if extraValue and extraValue:IsA("IntValue") then
		extra = extraValue.Value
	end

	-- ★ 재입장 시 phase 가 4 이상이면 4로 고정해서 사용
	if phase >= 4 then
		phase = 4
	end

	-- ★ QuestPhase → questIndex 매핑
	local questIndex = 1
	if phase <= 0 then
		questIndex = 1
	elseif phase == 1 then
		questIndex = 2
	elseif phase == 2 then
		questIndex = 3
	elseif phase == 3 then
		questIndex = 3
	elseif phase == 4 then
		questIndex = 4
	end
	-- questIndex 5는 advanceQuest() 로만 올라가게 둠

	currentIndexValue.Value = questIndex

	if phase >= 3 then
		trashClearedValue.Value = math.clamp(extra, 0, TRASH_TOTAL)
	else
		trashClearedValue.Value = 0
	end

	allClearedValue.Value = false

	-- ★ phase 3 이상이면 스테이지 라벨 표시
	if phase >= 3 then
		textLabel.Text = "스테이지1"
		didSetStage1Label = true
	end
end

----------------------------------------------------------------
-- 1) 텍스트만 갱신하는 함수 (애니메이션 X)
----------------------------------------------------------------
local function updateQuestText()
	local idx      = math.clamp(currentIndexValue.Value, 1, MAX_QUEST_INDEX)
	local cleared  = math.clamp(trashClearedValue.Value, 0, TRASH_TOTAL)
	local finished = allClearedValue.Value

	local baseText = QUEST_TEXTS[idx] or ""

	if idx == TRASH_QUEST_INDEX then
		local base = (QUEST_TEXTS[TRASH_QUEST_INDEX] or ""):gsub("%s*%d+/%d+%s*$", "")
		baseText = string.format("%s %d/%d", base, cleared, TRASH_TOTAL)

		if not didSetStage1Label then
			textLabel.Text = "스테이지1"
			didSetStage1Label = true
		end
	end

	if finished then
		questLabel.Text = string.format("<s>%s</s>", baseText)
		questLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	else
		questLabel.Text = baseText
		questLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	questLabel.TextTransparency = 0
end

----------------------------------------------------------------
-- 2) Quest 프레임 슬라이드 애니메이션
----------------------------------------------------------------
local function playQuestSlide()
	if currentTweenQuest then
		currentTweenQuest:Cancel()
		currentTweenQuest = nil
	end

	questRoot.Visible = true
	questRoot.Position = BASE_POS_QUEST + UDim2.fromScale(SLIDE_OFFSET, 0)

	local tInfo = TweenInfo.new(
		SLIDE_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	currentTweenQuest = TweenService:Create(questRoot, tInfo, {
		Position = BASE_POS_QUEST,
	})
	currentTweenQuest:Play()
end

local function refreshFromQuizState()
	syncFromQuizState()
	updateQuestText()
end

updateQuestText()
questRoot.Position = BASE_POS_QUEST

task.spawn(function()
	local pg = LP:WaitForChild("PlayerGui")
	pg:WaitForChild("_QuizState")
	task.wait(0.05)
	refreshFromQuizState()
end)

----------------------------------------------------------------
-- 퀘스트 진행 (인덱스 변경 + 사운드 + 슬라이드)
----------------------------------------------------------------
local function advanceQuest()
	local idx = math.clamp(currentIndexValue.Value, 1, MAX_QUEST_INDEX)

	if idx < MAX_QUEST_INDEX then
		idx += 1
		currentIndexValue.Value = idx
		playQuestChangeSfx()
	else
		allClearedValue.Value = true
		playQuestChangeSfx()
	end

	updateQuestText()
	playQuestSlide()
end

----------------------------------------------------------------
-- QuestProgressBus 연결
----------------------------------------------------------------
local BUS_NAME = "QuestProgressBus"
local bus = RS:FindFirstChild(BUS_NAME)
if not bus then
	local ev = Instance.new("BindableEvent")
	ev.Name = BUS_NAME
	ev.Parent = RS
	bus = ev
end

bus.Event:Connect(function(payload: any)
	if payload == "complete" or payload == "next" then
		advanceQuest()
		return
	end

	if typeof(payload) == "number" then
		local newIdx = math.clamp(payload, 1, MAX_QUEST_INDEX)

		if currentIndexValue.Value ~= newIdx then
			currentIndexValue.Value = newIdx
			allClearedValue.Value = false
			playQuestChangeSfx()
			updateQuestText()
			playQuestSlide()
		else
			allClearedValue.Value = false
			updateQuestText()
		end
		return
	end

	if typeof(payload) == "table" and payload.type == "trashProgress" then
		local c = tonumber(payload.count)
		local total = tonumber(payload.total) or TRASH_TOTAL
		if c then
			trashClearedValue.Value = math.clamp(c, 0, total)
			updateQuestText()
		end
	end
end)

print("[QuestClient] READY (QuestGui + QuizState sync)")

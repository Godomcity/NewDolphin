-- StarterPlayerScripts/DialogueUI.client.lua
--!strict
-- RS.DialogueUIBus:Fire("Play", { npc=<Instance>, questPhase=<number>, text=..., lines=... })

local Players         = game:GetService("Players")
local RS              = game:GetService("ReplicatedStorage")
local TweenService    = game:GetService("TweenService")
local Workspace       = game:GetService("Workspace")
local SoundService    = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local LP = Players.LocalPlayer

-- ★ 돌고래 초상 이미지
local DOLPHIN_PORTRAIT_ID = "rbxassetid://119823066460625"

-- ===== 공통 유틸 =====
local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

-- ★ 포탈 컷씬
local PortalSpawnCutscene =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalSpawnCutscene"))
	or tryRequire(RS:FindFirstChild("PortalSpawnCutscene"))

local playerLock = require(RS:WaitForChild("Modules"):WaitForChild("PlayerLock"))

local PORTAL_TRIGGER_TEXT = "다음 스테이지로 가는 해류 포탈을 열어드릴게요."

-- ★ 쓰레기 퀘스트 총 개수(QuestGui와 맞추기)
local TRASH_TOTAL = 9

-- ★ 각 phase "기본" 퀘스트 문구
local QUEST_HINT_BASE: {[number]: string} = {
	[1] = "QUEST : 오염된 쓰레기 1개 정화 후 NPC에게 말 걸기 0/1",
	[2] = "QUEST : 쓰레기 9개 정화하기",
	[3] = "QUEST : 쓰레기 9개 정화하기", -- ✅ 여기 뒤에 x/9 동적으로 붙임
	[4] = "QUEST : 다음 스테이지로 이동하기",
}

-- ========= SFX =========
local SFX_IDS: {[string]: string} = {
	PortalOpen    = "rbxassetid://2017454590",
	DialogueStart = "rbxassetid://9114124227",
	DialogueNext  = "rbxassetid://103307955424380",
}

local SFX_CACHE: {[string]: Sound} = {}

do
	local soundsToPreload = {}

	for name, id in pairs(SFX_IDS) do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = id
		s.Volume = 1
		s.RollOffMode = Enum.RollOffMode.Inverse
		s.Looped = false
		s.Parent = SoundService

		SFX_CACHE[name] = s
		table.insert(soundsToPreload, s)
	end

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(soundsToPreload)
		end)
	end)
end

local function playSfx(name: string, volume: number?)
	local s = SFX_CACHE[name]
	if not s then return end
	if volume then s.Volume = volume end
	s.TimePosition = 0
	s:Play()
end

-- ========= Dialogue Bus =========
local DialogueBus = RS:FindFirstChild("DialogueUIBus")
if not DialogueBus then
	DialogueBus = Instance.new("BindableEvent")
	DialogueBus.Name = "DialogueUIBus"
	DialogueBus.Parent = RS
end
local bus = DialogueBus :: BindableEvent

local QuestGuideBus: BindableEvent? do
	local obj = RS:FindFirstChild("QuestGuideBus")
	if obj and obj:IsA("BindableEvent") then
		QuestGuideBus = obj
	end
end

-- ========= DialogueData =========
local DialogueData = tryRequire(RS:FindFirstChild("DialogueData"))

local DefaultLines: {string} = {
	"안녕하세요! 퀴즈에 참여해 주세요.",
	"문제는 총 10개이고, 정답 4개면 문이 열립니다.",
	"모두 맞추면 포탈이 생성됩니다.",
}

local function getLinesFromDialogueData(questPhase: number?): {any}?
	if not DialogueData then return nil end

	if type((DialogueData :: any).phases) == "table" and questPhase and (DialogueData :: any).phases[questPhase] then
		return (DialogueData :: any).phases[questPhase]
	end

	if questPhase == 1 and type((DialogueData :: any).phase1) == "table" then
		return (DialogueData :: any).phase1
	elseif questPhase == 2 and type((DialogueData :: any).phase2) == "table" then
		return (DialogueData :: any).phase2
	elseif questPhase == 3 and type((DialogueData :: any).phase3_incomplete) == "table" then
		return (DialogueData :: any).phase3_incomplete
	elseif questPhase == 4 and type((DialogueData :: any).phase4_final) == "table" then
		return (DialogueData :: any).phase4_final
	end

	if type((DialogueData :: any).lines) == "table" then
		return (DialogueData :: any).lines
	end

	if type(DialogueData) == "table" and #(DialogueData :: any) > 0 then
		return DialogueData
	end

	return nil
end

local function toStringOrNil(v:any): string?
	if type(v) == "string" then return v end
	if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
	if type(v) == "table" then
		local s = v.text or v.Text or v.line or v.content or v.message or v.caption or v[1]
		if type(s) == "string" then return s end
	end
	return nil
end

local function normalizeLines(input:any, questPhase:number?): {string}
	if input ~= nil then
		if type(input) == "string" then
			return { input }
		end
		if type(input) == "table" then
			if input.lines and type(input.lines) == "table" then
				input = input.lines
			end
			if type(input) == "table" then
				local out = {}
				for _, v in ipairs(input) do
					local s = toStringOrNil(v)
					if s then table.insert(out, s) end
				end
				if #out > 0 then return out end
			end
		end
	end

	local fromModule = getLinesFromDialogueData(questPhase)
	if fromModule then
		local out = {}
		for _, v in ipairs(fromModule) do
			local s = toStringOrNil(v)
			if s then table.insert(out, s) end
		end
		if #out > 0 then return out end
	end

	local out = {}
	for _, v in ipairs(DefaultLines) do
		local s = toStringOrNil(v)
		if s then table.insert(out, s) end
	end
	if #out == 0 then
		out = { "..." }
	end
	return out
end

-- ========= PlayerGui 쪽 퀘스트 상태 읽기 =========
local function getTrashProgressFromState(): (number, number)
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return 0, TRASH_TOTAL end

	local stateFolder = pg:FindFirstChild("_QuestState")
	if not stateFolder then return 0, TRASH_TOTAL end

	local trashVal = stateFolder:FindFirstChild("TrashCleared")
	local count = 0
	if trashVal and trashVal:IsA("IntValue") then
		count = trashVal.Value
	end

	return math.clamp(count, 0, TRASH_TOTAL), TRASH_TOTAL
end

-- ========= UI 생성 =========
local function buildUI(): ScreenGui
	local pg = LP:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("DialogueGui")
	if gui and gui:IsA("ScreenGui") then return gui end

	gui = Instance.new("ScreenGui")
	gui.Name = "DialogueGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9000
	gui.Enabled = true -- ✅ ScreenGui는 항상 켜둔다
	gui.Parent = pg

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.BackgroundColor3 = Color3.fromRGB(0,0,0)
	bg.BackgroundTransparency = 0.35
	bg.Size = UDim2.fromScale(1,1)
	bg.Active = true
	bg.Visible = false -- ✅ 초기엔 BG만 숨김
	bg.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5,1)
	panel.Position = UDim2.fromScale(0.5, 1.02)
	panel.Size = UDim2.fromScale(0.9, 0.26)
	panel.BackgroundColor3 = Color3.fromRGB(24,28,36)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = bg
	panel.ZIndex = 2

	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0,12); pad.PaddingBottom = UDim.new(0,12)
	pad.PaddingLeft = UDim.new(0,16); pad.PaddingRight = UDim.new(0,16)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1,0.24)
	title.Text = "대화"
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(210,230,255)
	title.Parent = panel
	title.ZIndex = 3

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0,0.28)
	body.Size = UDim2.fromScale(0.7,0.54)
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Font = Enum.Font.Gotham
	body.TextScaled = true
	body.TextColor3 = Color3.fromRGB(240,240,240)
	body.Parent = panel
	body.ZIndex = 3

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.AnchorPoint = Vector2.new(1,0)
	portrait.Position = UDim2.fromScale(1.12, -3.15)
	portrait.Size = UDim2.fromScale(0.5, 5)
	portrait.Image = DOLPHIN_PORTRAIT_ID
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Visible = false
	portrait.ZIndex = 1
	portrait.Parent = panel

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0, 16)
	portraitCorner.Parent = portrait

	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "Next"
	nextBtn.AnchorPoint = Vector2.new(1,1)
	nextBtn.Position = UDim2.fromScale(0.99, 0.98)
	nextBtn.Size = UDim2.fromScale(0.18, 0.26)
	nextBtn.Text = "다음"
	nextBtn.Font = Enum.Font.GothamBold
	nextBtn.TextScaled = true
	nextBtn.TextColor3 = Color3.new(1,1,1)
	nextBtn.BackgroundColor3 = Color3.fromRGB(46,120,255)
	Instance.new("UICorner", nextBtn).CornerRadius = UDim.new(0,12)
	nextBtn.Visible = false
	nextBtn.Parent = panel
	nextBtn.ZIndex = 3

	return gui
end

local GUI = buildUI()

-- ✅ BG만 토글하는 헬퍼
local function setDialogueVisible(on: boolean)
	local bg = GUI:FindFirstChild("BG")
	if bg and bg:IsA("Frame") then
		bg.Visible = on
		playerLock.Lock({freezeCamera = true, freezeMovement = true, disableInput = true})
	end

	if not on then
		playerLock.Unlock()
		if bg and bg:IsA("Frame") then
			local panel = bg:FindFirstChild("Panel")
			if panel and panel:IsA("Frame") then
				panel.Visible = false

				local nextBtn = panel:FindFirstChild("Next")
				if nextBtn and nextBtn:IsA("GuiObject") then
					nextBtn.Visible = false
				end

				local portrait = panel:FindFirstChild("Portrait")
				if portrait and portrait:IsA("ImageLabel") then
					portrait.Visible = false
				end
			end
		end
	end
end

-- ========= 상태/연결 =========
local running   = false
local nextConn  : RBXScriptConnection? = nil
local clickConn : RBXScriptConnection? = nil

-- ========= 애니/표시 =========
local function slideIn(panel: Frame)
	panel.Visible = true
	TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.96)
	}):Play()
end

local function slideOutAndClose(panel: Frame)
	TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, 1.02)
	}):Play()
	task.wait(0.22)

	setDialogueVisible(false)
	bus:Fire("Finished")
end

local function typewrite(label: TextLabel, text: string, cps: number?, state: {skip:boolean})
	cps = cps or 35
	label.Text = ""
	for i = 1, #text do
		if state.skip then
			label.Text = text
			break
		end
		label.Text = string.sub(text, 1, i)
		task.wait(1/(cps :: number))
	end
end

-- ========= 포탈 컷씬 =========
local function playPortalCutsceneAndWait()
	if not PortalSpawnCutscene then
		warn("[DialogueUI] PortalSpawnCutscene 모듈을 찾지 못했습니다.")
		return
	end

	local spawnedPortal: Instance? = nil
	playSfx("PortalOpen")

	pcall(function()
		spawnedPortal = PortalSpawnCutscene.play({
			templateName   = "Potal",
			parent         = workspace,
			targetPosition = Vector3.new(-241.601, 26.539, 18.286),
			camStartPath   = "CamPos",
			camEndPath     = "CamEndPos",
			camAnchorsUseOrientation = true,
		})
	end)

	task.wait(2.5)

	if spawnedPortal then
		_G.spawnedPortal = spawnedPortal
	end

	if QuestGuideBus then
		local portal = spawnedPortal or _G.spawnedPortal
		if portal then
			QuestGuideBus:Fire("targetPortal", portal)
		else
			QuestGuideBus:Fire("targetPortal")
		end
	end
end

-- ========= 시퀀스 =========
local function runDialogueSequence(npc: Instance?, src:any, questPhase:number?)
	if running then return end
	running = true

	local bg      = GUI:FindFirstChild("BG") :: Frame
	local panel   = bg:FindFirstChild("Panel") :: Frame
	local title   = panel:FindFirstChild("Title") :: TextLabel
	local body    = panel:FindFirstChild("Body")  :: TextLabel
	local nextBtn = panel:FindFirstChild("Next") :: TextButton
	local portrait = panel:FindFirstChild("Portrait") :: ImageLabel?

	-- ✅ 이제 ScreenGui Enabled 대신 BG만 켠다
	setDialogueVisible(true)

	panel.Position = UDim2.fromScale(0.5, 1.02)
	panel.Visible  = true

	if portrait then
		portrait.Image = DOLPHIN_PORTRAIT_ID
		portrait.Visible = true
	end

	playSfx("DialogueStart")

	local lines = normalizeLines(src, questPhase)
	title.Text = npc and npc.Name or "대화"

	local questHintText: string? = nil
	local base = questPhase and QUEST_HINT_BASE[questPhase] or nil
	if base then
		if questPhase == 3 then
			local cleared, total = getTrashProgressFromState()
			questHintText = string.format("%s %d/%d", base, cleared, total)
		else
			questHintText = base
		end
	end

	local normalCount = #lines
	local totalCount  = normalCount + ((questHintText and 1) or 0)
	local idx = 1

	local typingState = {
		isTyping = false,
		skip = false,
	}

	local portalCutscenePlayed  = false
	local portalCutscenePlaying = false

	local function showCurrentLine()
		local text: string
		local isHintLine = (questHintText ~= nil and idx == totalCount)

		if isHintLine then
			text = questHintText or ""
			body.TextColor3 = Color3.fromRGB(255, 230, 100)
		else
			text = lines[idx] or ""
			body.TextColor3 = Color3.fromRGB(240,240,240)
		end

		body.Text = ""
		nextBtn.Visible      = false
		typingState.skip     = false
		typingState.isTyping = true

		typewrite(body, text, 35, typingState)
		typingState.isTyping = false

		nextBtn.Visible = true
	end

	local function handleAdvance(playNextSound: boolean)
		if portalCutscenePlaying then
			return
		end

		if typingState.isTyping then
			typingState.skip = true
			return
		end

		if playNextSound then
			playSfx("DialogueNext")
		end

		local isHintLine = (questHintText ~= nil and idx == totalCount)
		local currentText = (idx <= normalCount) and (lines[idx] or "") or ""

		if (not isHintLine)
			and (not portalCutscenePlayed)
			and typeof(currentText) == "string"
			and string.find(currentText, "해류 포탈을 열어드릴게요", 1, true) ~= nil
		then
			portalCutscenePlayed  = true
			portalCutscenePlaying = true
			nextBtn.Visible = false

			-- ✅ UI 숨김도 BG로만
			setDialogueVisible(false)
			panel.Visible = false

			playPortalCutsceneAndWait()

			portalCutscenePlaying = false

			idx += 1
			if idx <= totalCount then
				setDialogueVisible(true)

				panel.Position = UDim2.fromScale(0.5, 1.02)
				panel.Visible  = true
				slideIn(panel)

				showCurrentLine()
				return
			else
				slideOutAndClose(panel)
				running = false
				if nextConn then nextConn:Disconnect(); nextConn = nil end
				if clickConn then clickConn:Disconnect(); clickConn = nil end
				return
			end
		end

		idx += 1
		if idx <= totalCount then
			showCurrentLine()
		else
			nextBtn.Visible = false
			slideOutAndClose(panel)
			running = false
			if nextConn then nextConn:Disconnect(); nextConn = nil end
			if clickConn then clickConn:Disconnect(); clickConn = nil end
		end
	end

	if nextConn then nextConn:Disconnect() end
	if clickConn then clickConn:Disconnect() end

	nextConn = nextBtn.MouseButton1Click:Connect(function()
		handleAdvance(true)
	end)

	clickConn = bg.InputBegan:Connect(function(input, _gp)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- ✅ 배경 탭도 "다음" 사운드가 원래 원치 않으면 false로 바꿔도 됨
			handleAdvance(true)
		end
	end)

	slideIn(panel)
	showCurrentLine()
end

-- ========= Bus 연결 =========
bus.Event:Connect(function(cmd:any, payload:any)
	if cmd == "Play" then
		local npc        = payload and payload.npc
		local src        = payload and (payload.text or payload.lines or payload.sequence) or nil
		local questPhase = payload and payload.questPhase
		runDialogueSequence(npc, src, questPhase)

	elseif cmd == "Close" then
		-- ✅ 닫기: BG만 끄고 상태 정리
		setDialogueVisible(false)
		running = false
	end
end)

print("[DialogueUI] READY (BG.Visible 토글 방식)")

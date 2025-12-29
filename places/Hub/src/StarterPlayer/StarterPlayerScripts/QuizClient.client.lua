-- StarterPlayerScripts/QuizClient.client.lua
-- 퀴즈 모달 UI + 제출 흐름 (모바일/PC 스케일 대응)
-- 요구 Remotes: Quiz_StageReady(RE), QuizRun_Start(RF), QuizRun_Submit(RF),
--               QuizRun_Interaction(RE), QuizRun_Progress(RE-선택), QuizRun_GroupUpdate(RE-선택)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local RE_StageReady   = Net.ensureRE("Quiz_StageReady")
local RF_Start        = Net.ensureRF("QuizRun_Start")
local RF_Submit       = Net.ensureRF("QuizRun_Submit")
local RE_Interact     = Net.ensureRE("QuizRun_Interaction")
local RE_GroupUpdate  = Net.ensureRE("QuizRun_GroupUpdate")

local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled

-- ========== 모달 UI ==========
local modal = Instance.new("ScreenGui")
modal.Name = "QuizModal"
modal.IgnoreGuiInset = true
modal.ResetOnSpawn = false
modal.Enabled = false
modal.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
modal.DisplayOrder = 9000
modal.Parent = pg

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(IS_MOBILE and 0.94 or 0.7, IS_MOBILE and 0.62 or 0.56)
root.BackgroundColor3 = Color3.fromRGB(255,255,255)
root.BorderSizePixel = 0
root.Parent = modal
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 16)

local ar = Instance.new("UIAspectRatioConstraint")
ar.Parent = root
ar.AspectRatio = IS_MOBILE and 16/10 or 16/9
ar.DominantAxis = Enum.DominantAxis.Width

local pad = Instance.new("UIPadding")
pad.Parent = root
pad.PaddingTop = UDim.new(0, IS_MOBILE and 16 or 12)
pad.PaddingBottom = UDim.new(0, IS_MOBILE and 16 or 12)
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.fromScale(1, 0.14)
title.Position = UDim2.fromScale(0, 0)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "문제"
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(30,30,30)
title.Parent = root

local body = Instance.new("TextLabel")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Size = UDim2.fromScale(1, 0.32)
body.Position = UDim2.fromScale(0, 0.14)
body.TextWrapped = true
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextScaled = true
body.Font = Enum.Font.Gotham
body.TextColor3 = Color3.fromRGB(45,45,45)
body.Text = ""
body.Parent = root

local area = Instance.new("Frame")
area.Name = "ChoicesArea"
area.BackgroundTransparency = 1
area.Size = UDim2.fromScale(1, 0.54)
area.Position = UDim2.fromScale(0, 0.46)
area.Parent = root

local list = Instance.new("UIListLayout")
list.Parent = area
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Top
list.Padding = UDim.new(0, IS_MOBILE and 10 or 8)

-- 대기 배너
local waitGui = Instance.new("ScreenGui")
waitGui.Name = "QuizWait"
waitGui.IgnoreGuiInset = true
waitGui.ResetOnSpawn = false
waitGui.Enabled = false
waitGui.DisplayOrder = 9100
waitGui.Parent = pg

local waitBar = Instance.new("TextLabel")
waitBar.BackgroundTransparency = 0.2
waitBar.BackgroundColor3 = Color3.fromRGB(20,20,20)
waitBar.Size = UDim2.fromScale(0.9, 0.08)
waitBar.AnchorPoint = Vector2.new(0.5, 0.5)
waitBar.Position = UDim2.fromScale(0.5, 0.9)
waitBar.Text = "모든 인원이 완료할 때까지 대기 중…"
waitBar.TextScaled = true
waitBar.Font = Enum.Font.GothamBold
waitBar.TextColor3 = Color3.fromRGB(255,255,255)
waitBar.Parent = waitGui
Instance.new("UICorner", waitBar).CornerRadius = UDim.new(0, 12)

-- 그룹 현황(참여/완료)
local groupGui = Instance.new("ScreenGui")
groupGui.Name = "QuizGroupHUD"
groupGui.IgnoreGuiInset = true
groupGui.ResetOnSpawn = false
groupGui.DisplayOrder = 9050
groupGui.Parent = pg

local groupLbl = Instance.new("TextLabel")
groupLbl.BackgroundTransparency = 0.3
groupLbl.BackgroundColor3 = Color3.fromRGB(0,0,0)
groupLbl.TextColor3 = Color3.fromRGB(255,255,255)
groupLbl.TextScaled = true
groupLbl.Font = Enum.Font.GothamMedium
groupLbl.Size = UDim2.fromScale(0.28, 0.06)
groupLbl.Position = UDim2.fromScale(0.02, 0.04)
groupLbl.TextXAlignment = Enum.TextXAlignment.Left
groupLbl.Text = ""
groupLbl.Parent = groupGui
Instance.new("UICorner", groupLbl).CornerRadius = UDim.new(0, 8)
local groupPad = Instance.new("UIPadding")
groupPad.Parent = groupLbl
groupPad.PaddingLeft = UDim.new(0, 10)
groupPad.PaddingRight = UDim.new(0, 8)

-- ========== 상태 ==========
local current = { stage = 1, q = nil }

local function clearArea()
	for _, ch in ipairs(area:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
end

local function makeButton(textStr, heightScale)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Text = textStr
	b.Size = UDim2.fromScale(1, heightScale)
	b.BackgroundColor3 = Color3.fromRGB(230,240,255)
	b.TextScaled = true
	b.Font = Enum.Font.GothamMedium
	b.TextColor3 = Color3.fromRGB(30,30,30)
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
	return b
end

local function renderQuestion(q)
	current.q = q
	if not q then
		modal.Enabled = false
		return
	end
	modal.Enabled = true

	title.Text = string.upper(q.type or "") .. " 문제"
	body.Text  = q.text or ""

	clearArea()

	if q.type == "ox" then
		local h = IS_MOBILE and 0.22 or 0.2
		local o = makeButton("O", h); o.Parent = area
		local x = makeButton("X", h); x.Parent = area
		o.Activated:Connect(function()
			local res = RF_Submit:InvokeServer({ stage = current.stage, qid = q.id, answer = "O" })
			if res and res.ok then
				if res.correct and not res.done then renderQuestion(res.nextQuestion)
				elseif res.correct and res.done then modal.Enabled = false end
			end
		end)
		x.Activated:Connect(function()
			local res = RF_Submit:InvokeServer({ stage = current.stage, qid = q.id, answer = "X" })
			if res and res.ok then
				if res.correct and not res.done then renderQuestion(res.nextQuestion)
				elseif res.correct and res.done then modal.Enabled = false end
			end
		end)

	elseif q.type == "mc" then
		local choices = q.choices or {}
		local h = IS_MOBILE and 0.18 or 0.16
		for i, txt in ipairs(choices) do
			local b = makeButton(string.format("[%d] %s", i, tostring(txt)), h)
			b.Parent = area
			b.Activated:Connect(function()
				local res = RF_Submit:InvokeServer({ stage = current.stage, qid = q.id, answer = i })
				if res and res.ok then
					if res.correct and not res.done then renderQuestion(res.nextQuestion)
					elseif res.correct and res.done then modal.Enabled = false end
				end
			end)
		end

	else
		-- 주관식
		local tb = Instance.new("TextBox")
		tb.Size = UDim2.fromScale(1, IS_MOBILE and 0.2 or 0.18)
		tb.ClearTextOnFocus = false
		tb.TextScaled = true
		tb.Text = ""
		tb.PlaceholderText = "정답을 입력하세요"
		tb.BackgroundColor3 = Color3.fromRGB(242,242,242)
		tb.Font = Enum.Font.Gotham
		tb.TextColor3 = Color3.fromRGB(30,30,30)
		Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 10)
		tb.Parent = area

		local submit = makeButton("제출", IS_MOBILE and 0.16 or 0.14)
		submit.Parent = area

		local function doSubmit()
			local res = RF_Submit:InvokeServer({ stage = current.stage, qid = q.id, answer = tb.Text })
			if res and res.ok then
				if res.correct and not res.done then renderQuestion(res.nextQuestion)
				elseif res.correct and res.done then modal.Enabled = false end
			end
		end
		submit.Activated:Connect(doSubmit)
		tb.FocusLost:Connect(function(enter) if enter then doSubmit() end end)
	end
end

-- ========== 이벤트 바인딩 ==========
-- 교사도 포함: 가드 제거
RE_StageReady.OnClientEvent:Connect(function(stage)
	current.stage = tonumber(stage) or 1
	local start = RF_Start:InvokeServer(current.stage)
	if start and start.ok then
		renderQuestion(start.question)
	end
end)

RE_Interact.OnClientEvent:Connect(function(ev)
	if not ev then return end
	if ev.type == "mid" then
		print("[Quiz] 중간 인터랙션!")
	elseif ev.type == "wait" then
		waitGui.Enabled = true
	elseif ev.type == "all_done" then
		waitGui.Enabled = false
		print(string.format("[Quiz] 전원 완료! 다음 스테이지(=%s) 열림", tostring(ev.next)))
	end
end)

RE_GroupUpdate.OnClientEvent:Connect(function(info)
	if not info then return end
	groupLbl.Text = string.format("참여: %d  완료: %d", tonumber(info.participants or 0), tonumber(info.completed or 0))
end)

print("[QuizClient] READY. 모바일=", IS_MOBILE)

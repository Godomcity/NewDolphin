-- StarterPlayerScripts/TeleportPromptClient.client.lua
--!strict

local Players               = game:GetService("Players")
local ProximityPromptService= game:GetService("ProximityPromptService")
local CollectionService     = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local Lighting     = game:GetService("Lighting")

local LP = Players.LocalPlayer

-- ★ 텔레포트 유틸 사용
local TeleportUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TeleportUtil"))

local playerLock = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerLock"))

-- ★ 여기만 스테이지마다 다르게 설정!
local STAGE2_PLACE_ID = 110579663083129 -- 기존 TeleportOnRequest.NEXT_PLACE_ID 와 동일하게 맞춰주면 됨

local GLOBAL_COOLDOWN = 1.0
local _lastAt = 0

local bus = ReplicatedStorage:WaitForChild("QuestGuideBus", 10)

-- ✅ 모든 UI 비활성화
local function disableAllUI()
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return end

	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") then
			gui.Enabled = false
		end
	end
end

-- ===== 블러(컷씬 종료 후) =====
local ENDING_BLUR_NAME = "EndingBlur"
local ENDING_BLUR_TARGET_SIZE = 20
local ENDING_BLUR_TWEEN_TIME = 0.6

local function getOrCreateEndingBlur()
	local blur = Lighting:FindFirstChild(ENDING_BLUR_NAME)
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = ENDING_BLUR_NAME
		blur.Size = 0
		blur.Enabled = false
		blur.Parent = Lighting
	end
	return blur
end

local function fadeInEndingBlur()
	local blur = getOrCreateEndingBlur()
	blur.Enabled = true
	blur.Size = 0

	local ti = TweenInfo.new(ENDING_BLUR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blur, ti, { Size = ENDING_BLUR_TARGET_SIZE }):Play()
	-- ✅ 유지: 끄거나 0으로 내리지 않는 한 계속 20 유지
end

local function hasStage2Tag(pp: ProximityPrompt): boolean
	local cur: Instance? = pp
	while cur do
		if CollectionService:HasTag(cur, "Stage2Potal") then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function guessDevice(): string
	-- 필요하면 UserInputService 기반으로 "pc"/"mobile" 정교하게 분기
	return "pc"
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if player ~= LP then return end
	if not hasStage2Tag(prompt) then return end
	prompt.Enabled = false
	playerLock.Lock({freezeCamera = true, freezeMovement = true, disableInput = true})
	bus:Fire("off")
	disableAllUI()

	-- ✅ 컷씬 끝나자마자 블러(0 -> 20 서서히) + 유지
	fadeInEndingBlur()

	local now = os.clock()
	if now - _lastAt < GLOBAL_COOLDOWN then
		return
	end
	_lastAt = now

	-- ★ TeleportUtil.Go 로 통일
	TeleportUtil.Go(STAGE2_PLACE_ID, {
		reason = "stage2_portal",
		device = guessDevice(),
		-- sessionId 는 서버에서 Player:GetAttribute("sessionId") 로 가져가므로 굳이 안 실어도 됨
		meta = {
			promptName = prompt.Name,
			promptPath = prompt:GetFullName(),
			selectedStage = 2,
		},
	})
end

ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

print("[TeleportPromptClient] READY (Stage2 portal → TeleportUtil.Go → TeleportRouter)")

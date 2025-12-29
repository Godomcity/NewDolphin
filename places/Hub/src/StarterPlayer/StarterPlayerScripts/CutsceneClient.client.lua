-- StarterPlayerScripts/CutsceneBoot.client.lua
--!strict
-- RE_Cutscene payload.type:
--   "portal_open" / "portal_spawn(_at)" / "hub_portal"
-- "hub_portal" 은 HubPortalCutscene 모듈(HubPortalCutscene.play) 사용

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local LP = Players.LocalPlayer

-- Remotes
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local RE_Cutscene     = Remotes:WaitForChild("Quiz_Cutscene")      :: RemoteEvent
local RE_CutsceneDone = Remotes:WaitForChild("Quiz_CutsceneDone")  :: RemoteEvent

-- Hub 포탈 컷씬 모듈 (CamPos → CamEndPos + 이펙트)
local HubPortalCutscene = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Cutscene")
		:WaitForChild("HubPortalCutscene")
)

-- ========== 유틸 ==========
local function twn(i: Instance, ti: TweenInfo, props: {[string]: any})
	return TweenService:Create(i, ti, props)
end

local function setPartsTransparency(root: Instance, alpha: number)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = alpha
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = alpha
		end
	end
end

local function enableEmitters(root: Instance, on: boolean)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then d.Enabled = on end
		if d:IsA("Beam") then d.Enabled = on end
		if d:IsA("Trail") then d.Enabled = on end
	end
end

local function tryPlaySound(root: Instance)
	local s = root:FindFirstChildWhichIsA("Sound", true)
	if s then pcall(function() s:Play() end) end
end

local function ack(stage: number?)
	RE_CutsceneDone:FireServer({ stage = stage or 1 })
end

-- 포탈의 기준 CFrame(중심/정면)을 추출
local function getPortalFrame(portal: Instance): (CFrame, Vector3)
	if portal:IsA("Model") then
		local cf, size = portal:GetBoundingBox()
		return cf, size
	end
	-- BasePart 우선, 없으면 자식 BasePart 하나라도 사용
	if portal:IsA("BasePart") then
		return portal.CFrame, portal.Size
	end
	local anyPart = portal:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart.CFrame, anyPart.Size
	end
	-- 최후: 월드 원점
	return CFrame.new(0, 5, 0), Vector3.new(8, 8, 1)
end

-- ========== A. 기존 포탈 열림(간단 버전) ==========
local function playPortalOpen(stage: number)
	ack(stage)
end

-- ========== B. HubPortalCutscene 모듈 사용 버전 ==========

-- payload:
--   type = "hub_portal"
--   stage?: number
--   duration?: number  -- HubPortalCutscene에서 사용하는 dur
--   portalPath?: "Level.HubPortal" 등
--   colorRGB?: {r,g,b} 등
local function playHubPortal(payload: {stage: number?, portalPath: string?, duration: number?, [string]: any})
	local stage = tonumber(payload.stage) or 1
	local dur   = tonumber(payload.duration) or 3.0

	-- HubPortalCutscene 모듈에 카메라 + 이펙트 모두 위임
	local ok, err = pcall(function()
		HubPortalCutscene.play(payload)
	end)
	if not ok then
		warn("[CutsceneBoot] HubPortalCutscene.play error:", err)
		-- 실패하면 바로 ACK
		ack(stage)
		return
	end

	-- 컷씬 길이(dur) 만큼 기다렸다가 ACK → 서버에서 텔레포트
	task.delay(math.clamp(dur + 0.05, 0.3, 5), function()
		ack(stage)
	end)
end

-- ========== 수신 ==========
RE_Cutscene.OnClientEvent:Connect(function(payload)
	if not payload then return end
	local tp = tostring(payload.type or "")
	print(("[CutsceneBoot] type=%s stage=%s"):format(tp, tostring(payload.stage)))

	if tp == "portal_open" then
		playPortalOpen(tonumber(payload.stage) or 1)

	elseif tp == "portal_spawn" or tp == "portal_spawn_at" then
		playPortalOpen(tonumber(payload.stage) or 1)

	elseif tp == "hub_portal" then
		playHubPortal(payload)

	else
		return
	end
end)

-- (선택) F6 → 허브 포탈 컷씬 셀프 테스트
--UserInputService.InputBegan:Connect(function(input, gp)
--	if gp then return end
--	if input.KeyCode == Enum.KeyCode.F6 then
--		print("[CutsceneBoot] SelfTest → hub_portal")
--		playHubPortal({
--			type     = "hub_portal",
--			stage    = 1,
--			duration = 3.0,
--			portalPath = "Level.HubPortal",
--		})
--	end
--end)

print("[CutsceneBoot] READY (portal_open / portal_spawn / hub_portal via HubPortalCutscene)")

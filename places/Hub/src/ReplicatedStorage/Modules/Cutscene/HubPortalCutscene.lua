-- ReplicatedStorage/Modules/Cutscene/HubPortalCutscene.lua
--!strict

local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")

local playerLock = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerLock"))

local M = {}

-------------------------------------------------------
-- Utility
-------------------------------------------------------
local function toColor3(t:any?): Color3
	if typeof(t) == "Color3" then return t end
	if typeof(t) == "table" and #t >= 3 then
		return Color3.fromRGB(
			tonumber(t[1]) or 40,
			tonumber(t[2]) or 140,
			tonumber(t[3]) or 255
		)
	end
	return Color3.fromRGB(40,140,255)
end

local function findHubPortal(opts: any?): Instance?
	for _, inst in ipairs(CollectionService:GetTagged("HubPortal")) do
		return inst
	end

	local name = (opts and opts.portalName) or "HubPortal"

	if opts and typeof(opts.portalPath) == "string" then
		local cur: Instance = Workspace
		for seg in string.gmatch(opts.portalPath, "[^%.]+") do
			cur = cur:FindFirstChild(seg)
			if not cur then break end
		end
		if cur then return cur end
	end

	local level = Workspace:FindFirstChild("Level")
	if level then
		for _, d in ipairs(level:GetDescendants()) do
			if d.Name == name then return d end
		end
	end

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name == name then return d end
	end
	return nil
end

local function primaryAndParts(root: Instance): (BasePart?, {BasePart})
	if not root then return nil, {} end
	if root:IsA("BasePart") then return root, {root} end

	if root:IsA("Model") then
		local pp = root.PrimaryPart
		if not pp then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then
					pp = d
					break
				end
			end
		end

		local parts = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		return pp, parts
	end

	local parts = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts[1], parts
end

local function findCamMarker(name: string): BasePart?
	local inst = Workspace:FindFirstChild(name) or Workspace:FindFirstChild(name, true)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then return inst.PrimaryPart end
	return nil
end

-------------------------------------------------------
-- Ending Post Effect (Blur + UI Off)
-------------------------------------------------------
local ENDING_BLUR_NAME = "EndingBlur"
local ENDING_BLUR_TARGET_SIZE = 20
local ENDING_BLUR_TWEEN_TIME = 0.6

local function fadeInEndingBlur()
	local blur = Lighting:FindFirstChild(ENDING_BLUR_NAME) :: BlurEffect?
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = ENDING_BLUR_NAME
		blur.Size = 0
		blur.Enabled = false
		blur.Parent = Lighting
	end

	blur.Enabled = true
	blur.Size = 0

	TweenService:Create(
		blur,
		TweenInfo.new(
			ENDING_BLUR_TWEEN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{ Size = ENDING_BLUR_TARGET_SIZE }
	):Play()
end

local function disableAllUI()
	local lp = Players.LocalPlayer
	if not lp then return end

	local pg = lp:FindFirstChild("PlayerGui")
	if not pg then return end

	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") then
			gui.Enabled = false
		end
	end
end

-------------------------------------------------------
-- Play
-------------------------------------------------------
function M.play(opts: any?): ()
	local portal = findHubPortal(opts)
	if not portal then
		warn("[HubPortalCutscene] HubPortal not found")
		return
	end

	local dur   = tonumber(opts and opts.duration) or 3.0
	local color = toColor3(opts and opts.colorRGB)

	----------------------------------------------------
	-- 0) Portal_Frame 즉시 이펙트
	----------------------------------------------------
	do
		local frame = portal:FindFirstChild("Portal_Frame")
		if frame then
			for _, d in ipairs(frame:GetDescendants()) do
				if d:IsA("ParticleEmitter") then
					d.Enabled = true
					d:Clear()
					d:Emit(1)
				end
			end
		end
	end

	local primary = primaryAndParts(portal)
	if not primary then
		warn("[HubPortalCutscene] No BasePart in HubPortal")
		return
	end

	----------------------------------------------------
	-- 1) Camera CamPos → CamEndPos
	----------------------------------------------------
	do
		local cam = Workspace.CurrentCamera
		if cam then
			local camPosPart    = findCamMarker("CamPos")
			local camEndPosPart = findCamMarker("CamEndPos")

			if camPosPart and camEndPosPart then
				local origType = cam.CameraType
				local lp = Players.LocalPlayer
				local humanoid = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")

				cam.CameraType = Enum.CameraType.Scriptable
				cam.CFrame = camPosPart.CFrame

				local tween = TweenService:Create(
					cam,
					TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ CFrame = camEndPosPart.CFrame }
				)
				tween:Play()

				tween.Completed:Connect(function()
					task.wait()
					if humanoid then
						cam.CameraType = Enum.CameraType.Custom
						cam.CameraSubject = humanoid
					else
						cam.CameraType = origType
					end
				end)
			end
		end
	end

	----------------------------------------------------
	-- 1-1) Portal_Inside 페이드 인
	----------------------------------------------------
	do
		local inside = portal:FindFirstChild("Portal_Inside")
		if inside then
			for _, d in ipairs(inside:GetDescendants()) do
				if d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = 1
					TweenService:Create(
						d,
						TweenInfo.new(dur * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Transparency = 0 }
					):Play()
				end
			end
		end
	end

	----------------------------------------------------
	-- 2) Highlight / Light / Particle
	----------------------------------------------------
	local primary2, _ = primaryAndParts(portal)

	local highlight = Instance.new("Highlight")
	highlight.Adornee = portal
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = portal

	local light = Instance.new("PointLight")
	light.Range = 0
	light.Brightness = 0
	light.Color = color
	light.Parent = primary2

	local att = Instance.new("Attachment")
	att.Parent = primary2

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = att
	emitter:Emit(60)

	TweenService:Create(
		highlight,
		TweenInfo.new(dur * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 0.2, OutlineTransparency = 0 }
	):Play()

	TweenService:Create(
		light,
		TweenInfo.new(dur * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Range = 16, Brightness = 2.2 }
	):Play()

	----------------------------------------------------
	-- 3) 정리 + 후처리
	----------------------------------------------------
	task.delay(dur + 0.15, function()
		if highlight then highlight:Destroy() end
		if att then att:Destroy() end
		if light then light:Destroy() end
	end)

	task.delay(dur + 0.2, function()
		disableAllUI()
		fadeInEndingBlur()
		playerLock.Lock({freezeCamera = true, freezeMovement = true, disableInput = true})
	end)
end

return M

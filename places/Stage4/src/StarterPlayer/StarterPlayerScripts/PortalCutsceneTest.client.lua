-- StarterPlayerScripts/PortalCutsceneTest.client.lua
--!strict

local RS   = game:GetService("ReplicatedStorage")
local CAS  = game:GetService("ContextActionService")
local WS   = game:GetService("Workspace")

local Modules = RS:WaitForChild("Modules")
local PortalSpawnCutscene = require(Modules:WaitForChild("PortalSpawnCutscene"))

local middleDoorCutScene = require(Modules:WaitForChild("MiddleDoorCutscene"))

local TARGET_POS = Vector3.new(-249.289, 22.578, 21.106)
local BUSY = false
local COOLDOWN_SEC = 1.8

local function runTest()
	if BUSY then return end
	BUSY = true

	PortalSpawnCutscene.play({
		templateName   = "Potal",
		parent         = workspace,
		targetPosition = Vector3.new(202.504, 116.252, -528.161),

		-- 카메라: CamPos → CamEndPos
		camStartPath   = "CamPos",
		camEndPath     = "CamEndPos",
		--camDuration    = 1.2,            -- 필요시 조절
		-- 앵커의 회전을 그대로 쓰고 싶다면:
		 camAnchorsUseOrientation = true,
	})

	task.delay(COOLDOWN_SEC, function() BUSY = false end)
end

local function onAction(_, state, _)
	if state == Enum.UserInputState.Begin then
		--runTest()
		middleDoorCutScene.Play()
	end
end

CAS:BindAction("PortalCutsceneTest", onAction, false, Enum.KeyCode.F6)
print(("[PortalTest] READY — F1: spawn @ %s"):format(tostring(TARGET_POS)))

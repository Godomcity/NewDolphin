-- StarterPlayerScripts/HubRouter.client.lua
local RS = game:GetService("ReplicatedStorage")
local TeleportUtil = require(RS.Modules.TeleportUtil)

local STAGE1_PLACE_ID = 99318205197051
local STAGE2_PLACE_ID = 110579663083129

-- 예: Stage1 버튼
TeleportUtil.Go(STAGE1_PLACE_ID, { reason = "go_stage1" })

-- 예: Stage2 버튼(바로 가는 동선이 있다면)
-- TeleportUtil.Go(STAGE2_PLACE_ID, { reason = "go_stage2" })

-- StarterPlayerScripts/Stage1Next.client.lua (혹은 기존 QuizClient에서 조건 충족 시)
local RS = game:GetService("ReplicatedStorage")
local TeleportUtil = require(RS.Modules.TeleportUtil)

local STAGE2_PLACE_ID = 110579663083129

-- 예: Stage1 완료 → Stage2 이동
TeleportUtil.Go(STAGE2_PLACE_ID, { reason = "stage1_to_stage2" })

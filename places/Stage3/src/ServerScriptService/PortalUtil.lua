-- ServerScriptService/PortalUtil.lua
-- 스테이지 포탈 열고/닫기 공용 유틸

local M = {}

local function findStagePortal(stage: number)
	local Portals = workspace:FindFirstChild("Portals")
	if not Portals then return nil end
	local part = Portals:FindFirstChild(("Stage%dPortal"):format(stage))
	if not part then return nil end
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
	return part, prompt
end

function M.SetPortalOpen(stage: number, open: boolean)
	local part, prompt = findStagePortal(stage)
	if prompt then prompt.Enabled = open end
	if part then
		part.Transparency = open and 0.2 or 0.75
		part.CanCollide = true
	end
end

return M

-- ServerScriptService/GameBootstrap.lua
-- 텔레포트 데이터로 속성 세팅 + 화이트리스트 기반 Role 강제 오버라이드

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local RoleConfig = require(script.Parent:WaitForChild("RoleConfig"))

local function applyFromTeleportData(player: Player, td: table)
	if not td then return end
	local function setAttr(k, v) player:SetAttribute(k, v) end

	if td.session then
		setAttr("SessionId", tostring(td.session.id or ""))
		setAttr("InviteCode", tostring(td.session.invite or ""))
		setAttr("Role", tostring(td.session.role or "")) -- "teacher"|"student" (임시, 아래에서 오버라이드)
		setAttr("PartyId", tostring(td.session.partyId or ""))
	end
	if td.player then
		setAttr("Device", tostring(td.player.device or "")) -- "mobile"|"desktop"
	end
	setAttr("SelectedStage", tonumber(td.selectedStage or 1))
end

local function enforceRoleOverride(player: Player)
	-- ⚠️ API 없을 때는 여기서 최종 결정을 강제
	if RoleConfig.TEACHER_IDS[player.UserId] then
		player:SetAttribute("Role", "teacher")
	else
		-- 화이트리스트가 아니면 전부 학생으로 고정
		player:SetAttribute("Role", "student")
	end
end

Players.PlayerAdded:Connect(function(plr)
	local td
	pcall(function() td = TeleportService:GetPlayerTeleportData(plr) end)

	-- 텔레포트 데이터 반영(있으면)
	if td then
		applyFromTeleportData(plr, td)
	else
		-- 기본값
		plr:SetAttribute("SelectedStage", 1)
	end

	-- ✅ 최종 Role 강제 오버라이드 (화이트리스트 기반)
	enforceRoleOverride(plr)
end)

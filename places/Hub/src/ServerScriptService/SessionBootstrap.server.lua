-- ServerScriptService/SessionBootstrap.server.lua
--!strict
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local playerPassThrough = require(game.ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerPassThrough"))
playerPassThrough.Enable()

-- TeleportData 에서 sessionId 추출 (새/옛 스키마 둘 다 지원)
local function extractSessionId(td: any): string?
	if typeof(td) ~= "table" then
		return nil
	end

	-- ✅ 새 스키마: TeleportData.session.id
	local session = td.session
	if typeof(session) == "table" and typeof(session.id) == "string" and #session.id > 0 then
		return session.id
	end

	-- 🔙 옛 스키마 호환: TeleportData.sessionId
	if typeof(td.sessionId) == "string" and #td.sessionId > 0 then
		return td.sessionId
	end

	return nil
end

-- ✅ TeleportData 에서 userRole 추출 (추가)
local function extractUserRole(td: any): string?
	if typeof(td) ~= "table" then
		return nil
	end

	-- ✅ 권장 스키마: TeleportData.player.userRole
	local p = td.player
	if typeof(p) == "table" and typeof(p.userRole) == "string" and #p.userRole > 0 then
		return p.userRole
	end

	-- 🔙 (혹시) TeleportData.userRole 로 내려온 경우 대비
	if typeof(td.userRole) == "string" and #td.userRole > 0 then
		return td.userRole
	end

	-- 🔙 (예전에 session.player.userRole로 넣었을 수도 있어서) 호환
	local session = td.session
	if typeof(session) == "table" then
		local sp = session.player
		if typeof(sp) == "table" and typeof(sp.userRole) == "string" and #sp.userRole > 0 then
			return sp.userRole
		end
	end

	return nil
end

-- ✅ TeleportData 에서 roomCode 추출 (추가)
local function extractRoomCode(td: any): string?
	if typeof(td) ~= "table" then
		return nil
	end

	-- ✅ 권장 스키마: TeleportData.session.roomCode
	local session = td.session
	if typeof(session) == "table" and typeof(session.roomCode) == "string" and #session.roomCode > 0 then
		return session.roomCode
	end

	-- 🔙 (혹시) TeleportData.roomCode 로 내려온 경우 대비
	if typeof(td.roomCode) == "string" and #td.roomCode > 0 then
		return td.roomCode
	end

	return nil
end

local function isTeacherRole(role: string?): boolean
	return role == "ROLE_TEACHER"
end

Players.PlayerAdded:Connect(function(plr: Player)
	local sid: string? = nil
	local userRole: string? = nil
	local roomCode: string? = nil

	-- TeleportData 읽기
	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)

	if ok and typeof(joinData) == "table" then
		local td = joinData.TeleportData
		sid = extractSessionId(td)

		-- ✅ 추가: userRole / roomCode
		userRole = extractUserRole(td)
		roomCode = extractRoomCode(td)
	end

	-- 스튜디오에서 직접 플레이 눌렀을 때: 디버그용 가짜 세션 부여
	if RunService:IsStudio() and (not sid or #sid == 0) then
		sid = string.format("local-%d-%d", plr.UserId, os.time())
	end

	if sid and #sid > 0 then
		plr:SetAttribute("sessionId", sid)
	end

	-- ✅ 추가: userRole / isTeacher / roomCode Attribute 저장
	if userRole and #userRole > 0 then
		plr:SetAttribute("userRole", userRole)
		plr:SetAttribute("isTeacher", isTeacherRole(userRole))
	end

	if roomCode and #roomCode > 0 then
		plr:SetAttribute("roomCode", roomCode)
	end

	print(
		"[SessionBootstrap]",
		plr.Name,
		"sessionId =", plr:GetAttribute("sessionId"),
		"userRole =", plr:GetAttribute("userRole"),
		"isTeacher =", plr:GetAttribute("isTeacher"),
		"roomCode =", plr:GetAttribute("roomCode")
	)
end)

print("[SessionBootstrap] READY (reads TeleportData.session.id + userRole/roomCode)")

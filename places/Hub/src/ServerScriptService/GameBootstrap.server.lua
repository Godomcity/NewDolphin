---- ServerScriptService/GameBootstrap.lua
---- 텔레포트 데이터로 속성 세팅 + 화이트리스트 기반 Role 강제 오버라이드
---- (추가) TeleportData에 실린 예약 서버 코드들을 ReservedCodesJson(JSON)으로 저장
---- (선택) SessionRouter가 있으면 MemoryStore에도 prime

--local Players          = game:GetService("Players")
--local TeleportService  = game:GetService("TeleportService")
--local HttpService      = game:GetService("HttpService")

--local RoleConfig = require(script.Parent:WaitForChild("RoleConfig"))

---- (선택) SessionRouter가 프로젝트에 있으면 사용
--local SessionRouter
--do
--	local ok, mod = pcall(function()
--		local container = script.Parent:FindFirstChild("Modules") or script.Parent
--		local m = container and container:FindFirstChild("SessionRouter")
--		return m and require(m)
--	end)
--	if ok then SessionRouter = mod end
--end

--local function toStr(v:any) : string
--	return (v == nil and "") or tostring(v)
--end

---- TeleportData에서 다양한 스키마로 넘어온 예약 코드들을 수집
--local function collectReservedCodes(td:any) : {[string]: string}
--	local codes: {[string]: string} = {}
--	if type(td) ~= "table" then return codes end

--	-- (A) session.privateServerCode + session.placeId/targetPlaceId/nextPlaceId
--	if td.session then
--		local code = td.session.privateServerCode
--		local pid  = td.session.placeId or td.session.targetPlaceId or td.session.nextPlaceId
--		if code and pid then
--			codes[tostring(pid)] = tostring(code)
--		end
--	end

--	-- (B) reservedCodes = { [placeId] = code, ... }
--	if type(td.reservedCodes) == "table" then
--		for k, v in pairs(td.reservedCodes) do
--			if k ~= nil and v ~= nil then
--				codes[tostring(k)] = tostring(v)
--			end
--		end
--	end

--	-- (C) reservedNext = { placeId=..., code=... }
--	if td.reservedNext and td.reservedNext.placeId and td.reservedNext.code then
--		codes[tostring(td.reservedNext.placeId)] = tostring(td.reservedNext.code)
--	end

--	return codes
--end

--local function applyFromTeleportData(player: Player, td: table)
--	if not td then return end
--	local function setAttr(k, v) player:SetAttribute(k, v) end

--	-- 기본 세션/플레이어 속성
--	if td.session then
--		setAttr("SessionId",   toStr(td.session.id))
--		setAttr("InviteCode",  toStr(td.session.invite))
--		setAttr("Role",        toStr(td.session.role)) -- "teacher" | "student" (임시)
--		setAttr("PartyId",     toStr(td.session.partyId))
--	end
--	if td.player then
--		setAttr("Device", toStr(td.player.device)) -- "mobile" | "desktop"
--	end
--	setAttr("SelectedStage", tonumber(td.selectedStage or 1))

--	-- 예약 서버 코드 회수 → JSON으로 저장
--	local codes = collectReservedCodes(td)
--	local json = ""
--	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, codes)
--	if ok and encoded and next(codes) ~= nil then
--		json = encoded
--	end
--	setAttr("ReservedCodesJson", json)
--end

--local function enforceRoleOverride(player: Player)
--	-- ⚠️ API 없거나 임시일 경우 화이트리스트로 최종 강제
--	if RoleConfig.TEACHER_IDS[player.UserId] then
--		player:SetAttribute("Role", "teacher")
--	else
--		player:SetAttribute("Role", "student")
--	end
--end

--Players.PlayerAdded:Connect(function(plr)
--	local td
--	pcall(function()
--		td = TeleportService:GetPlayerTeleportData(plr)
--	end)

--	if td then
--		applyFromTeleportData(plr, td)

--		-- (선택) SessionRouter가 있으면 메모리스토어에도 프라임해서
--		-- 이후 어떤 서버/플레이스에서도 동일 코드 재사용 가능
--		if SessionRouter and SessionRouter.primeFromTeleportData then
--			pcall(function()
--				SessionRouter.primeFromTeleportData(plr, td)
--			end)
--		end
--	else
--		-- 기본값 초기화
--		plr:SetAttribute("SelectedStage", 1)
--		plr:SetAttribute("ReservedCodesJson", "")
--	end

--	-- ✅ 최종 Role 강제 오버라이드
--	enforceRoleOverride(plr)
--end)

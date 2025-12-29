-- ServerScriptService/ApiClient.lua
-- 실제 API가 준비되기 전까지 사용하는 모의 검증 모듈

local HttpService = game:GetService("HttpService")
local ApiClient = {}

-- 필요 시 false -> true 로 바꿔서 실제 API 구현으로 전환
local USE_REAL_API = false

-- ===== MOCK =====
local function mockValidate(entryCode: string, token: string, player: Player, device: string)
	entryCode = (entryCode or ""):gsub("%s+", ""):upper()
	token     = (token or ""):match("^%s*(.-)%s*$")

	-- 초대코드: 8자 영숫자
	if not (entryCode:match("^[A-Z0-9]+$") and #entryCode == 8) then
		return { ok=false, error="invalid_code" }
	end

	-- 토큰: 10자 이상
	if #token < 10 then
		return { ok=false, error="invalid_token" }
	end

	-- 만료 시뮬레이션
	if token:upper():sub(1,7) == "EXPIRED" then
		return { ok=false, error="token_expired" }
	end

	-- 역할 규칙(임시): 토큰에 'TEACH' 포함 → 교사, 아니면 학생
	local role = (token:upper():find("TEACH") and "teacher") or "student"

	-- 교사가 방을 새로 열고 싶다면 토큰에 'NEW' 포함
	local requestNewPrivate = (role == "teacher") and (token:upper():find("NEW") ~= nil)

	-- 목적지(지금은 고정된 게임 본체 PlaceId)
	local placeId = 120816172838238

	-- 결과
	return {
		ok = true,
		role = role,
		requestNewPrivate = requestNewPrivate,
		selectedStage = 1,          -- 필요 시 로직 확장
		partyId = nil,
		session = {
			id = "S_" .. entryCode,
			inviteCode = entryCode,
			placeId = placeId,
			privateServerCode = nil,  -- 필요 시 서버에서 ReserveServer로 채움
		},
		-- 목적지 서버에서 재검증할 때 사용할 짧은 티켓(원 토큰은 절대 전달 X)
		ticket = HttpService:GenerateGUID(false),
	}
end

-- ===== REAL API 스텁(준비되면 여기에 붙이면 됨) =====
local function realValidate(entryCode: string, token: string, player: Player, device: string)
	-- TODO: 실제 API 연결
	-- return { ok=false, error="network_error" }
	return mockValidate(entryCode, token, player, device) -- 지금은 모의로 처리
end

function ApiClient.validate(entryCode, token, player, device)
	if USE_REAL_API then
		return realValidate(entryCode, token, player, device)
	else
		return mockValidate(entryCode, token, player, device)
	end
end

return ApiClient

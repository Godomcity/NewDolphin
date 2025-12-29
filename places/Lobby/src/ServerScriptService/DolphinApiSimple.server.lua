-- ServerScriptService/DolphinApiSimple.server.lua
-- (필수) Game Settings > Security > Allow HTTP Requests ON
-- 클라(EntryScreen)에서 FireServer로 보낸 개인토큰(tokenId)을 받아서 TOKEN_LOOKUP 호출

--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- 네 프로젝트 Net 모듈 사용
local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))

local BASE = "https://api.dolphincoding.kr/dolphincoding/v1"
local TOKEN_LOOKUP_URL = BASE .. "/courses/worlds/users/tokens/%s"

local ROBLOX_CLIENT_ID = "ROBLOX_CLIENT_ID"

-- ✅ 서버에서만 보관 (절대 LocalScript에 두지 말 것)
local ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI2NWMwNWVhYy0zN2YzLTRjNGMtYTM5ZS0yNGQ3OWNjOWRjN2MiLCJjb3Vyc2VJZCI6MTY5LCJ0b2tlblR5cGUiOiJBQ0NFU1MiLCJpYXQiOjE3NjY0Njg4MDQsImV4cCI6MTc2NjQ3MjQwNCwidXNlclJvbGUiOiJST0xFX1VTRVIifQ.IBTSuiALXJALRdWvY8zBkU3k3_t83RjSxwXhpUwz-_I"

local function maskToken(s: string?)
	if type(s) ~= "string" then return tostring(s) end
	if #s <= 12 then return "****" end
	return s:sub(1, 6) .. "..." .. s:sub(-4)
end

local function dumpTable(t: any, title: string)
	print(("---- %s ----"):format(title))
	if type(t) ~= "table" then
		print(t)
		return
	end
	for k, v in pairs(t) do
		print(("%s: %s"):format(tostring(k), tostring(v)))
	end
end

local function safeJsonDecode(body: string)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if ok then return decoded end
	return nil
end

local function fetchToken(tokenId: string)
	local url = TOKEN_LOOKUP_URL:format(tokenId)

	local reqHeaders = {
		["Accept"] = "application/json",
		["X-CLIENT-ID"] = ROBLOX_CLIENT_ID,

		-- ✅ 이 엔드포인트가 인증 필요하면 켜야 함
		-- ["Authorization"] = "Bearer " .. ACCESS_TOKEN,
	}

	print("REQUEST URL:", url)
	print("ACCESS_TOKEN:", maskToken(ACCESS_TOKEN))
	dumpTable(reqHeaders, "REQUEST HEADERS (to send)")

	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = reqHeaders,
		})
	end)

	if not ok then
		warn("[API] RequestAsync failed:", res)
		return nil
	end

	print(("RESPONSE: Success=%s StatusCode=%s StatusMessage=%s"):format(
		tostring(res.Success),
		tostring(res.StatusCode),
		tostring(res.StatusMessage)
		))
	dumpTable(res.Headers, "RESPONSE HEADERS (from server)")
	print("RESPONSE BODY:", res.Body)

	if not res.Success then
		warn(("[API] HTTP %d"):format(res.StatusCode))
		return nil
	end

	local decoded = safeJsonDecode(res.Body or "")
	return decoded or res.Body
end

----------------------------------------------------------------
-- ✅ 클라에서 토큰 받기 (RemoteEvent)
-- 클라 LocalScript에서: RE_SubmitPersonalToken:FireServer({ token = "2L4LG_HT", ... })
----------------------------------------------------------------
local RE_SubmitPersonalToken = Net.ensureRE("RE_SubmitPersonalToken")

RE_SubmitPersonalToken.OnServerEvent:Connect(function(plr, payload)
	local tokenId = tostring(payload and payload.token or ""):match("^%s*(.-)%s*$")

	if tokenId == "" then
		warn(("[API] empty token from %s(%d)"):format(plr.Name, plr.UserId))
		return
	end

	print(("[API] token received from %s(%d): %s")
		:format(plr.Name, plr.UserId, maskToken(tokenId)))

	local result = fetchToken(tokenId)
	print("[API] token result:", result)
end)

print("[DolphinApiSimple] READY (listening RE_SubmitPersonalToken)")

-- ServerScriptService/Modules/QuizApi.lua
-- 외부 API 호출 모듈 (토큰/클라이언트ID 포함 → 서버에만!)
-- 제공 함수:
--   GetQuestionWithErr() -> (dto|nil, errTable|nil)
--   SubmitAnswerWithErr(quizStorageId: string, quizChoiceId: number) -> (result|nil, errTable|nil)

local HttpService = game:GetService("HttpService")

-- ===== 너 환경에 맞게 채우기 =====
local ROBLOX_CLIENT_ID = "ROBLOX_CLIENT_ID"
local ACCESS_TOKEN = "eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJjMWQyYzYzYy01YTZlLTRkYWQtYTUwZS02YjllYWU4MjE2YjMiLCJ1c2VyUm9sZSI6IlJPTEVfVEVBQ0hFUiIsImNvdXJzZUlkIjoxNjksInRva2VuVHlwZSI6IkFDQ0VTUyIsImV4cCI6MTc2NjgwMDQ3N30.r7IL-Kat88iRJYPjOm9T-3VlsewzWAm59oAF1kyC1TWphrYb8EMSdhSA8cb9fIlUGeaN7jVU87l6M8y1X-kkrg" -- 서버에만! 절대 클라로 보내면 안 됨

-- 테스트(quizId=2) : 필요하면 quizId만 바꿔서 사용
local QUIZ_GET_URL = "https://api.dolphincoding.kr/dolphincoding/v1/quizs/2"
local QUIZ_SUBMIT_URL = "https://api.dolphincoding.kr/dolphincoding/v1/users/quizs/submit"

-- ===== 유틸 =====
local function safeJsonDecode(body: string)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if ok then return decoded end
	return nil
end

local function requestAsync(method: string, url: string, bodyTable: any?)
	local headers = {
		["Accept"] = "application/json",
		["Content-Type"] = "application/json",
		["X-CLIENT-ID"] = ROBLOX_CLIENT_ID,
		["accessToken"] = "Bearer " .. ACCESS_TOKEN,
	}

	local payload: any = {
		Url = url,
		Method = method,
		Headers = headers,
	}

	if bodyTable ~= nil then
		payload.Body = HttpService:JSONEncode(bodyTable)
	end

	local ok, res = pcall(function()
		return HttpService:RequestAsync(payload)
	end)

	if not ok then
		return false, {
			Success = false,
			StatusCode = 0,
			StatusMessage = tostring(res),
			Body = "",
		}
	end

	return true, res
end

-- ===== GET 응답 → DTO 변환 =====
-- 외부 GET 응답 예:
-- { quizId, quizStorageId, title, content, choices=[{quizChoiceId, choiceNumber, choiceText}...] }
local function buildQuestionDto(decoded: any)
	if typeof(decoded) ~= "table" then return nil end
	if typeof(decoded.choices) ~= "table" then return nil end

	local outChoices = {}
	for _, ch in ipairs(decoded.choices) do
		table.insert(outChoices, {
			quizChoiceId = tonumber(ch.quizChoiceId) or 0,
			choiceNumber = tonumber(ch.choiceNumber) or 0,
			choiceText = tostring(ch.choiceText or ""),
		})
	end

	return {
		id = tostring(decoded.quizId),
		q = tostring(decoded.content or decoded.title or ""),
		title = tostring(decoded.title or ""),
		quizStorageId = tostring(decoded.quizStorageId or ""),
		choices = outChoices,
	}
end

-- ===== 공개 API =====
local QuizApi = {}

function QuizApi.GetQuestionWithErr()
	local ok, res = requestAsync("GET", QUIZ_GET_URL, nil)
	if not ok or not res.Success then
		return nil, {
			msg = "GET failed",
			statusCode = res.StatusCode,
			statusMessage = res.StatusMessage,
			body = res.Body,
		}
	end

	local decoded = safeJsonDecode(res.Body or "")
	if not decoded then
		return nil, { msg = "GET decode failed", raw = res.Body }
	end

	local dto = buildQuestionDto(decoded)
	if not dto then
		return nil, { msg = "buildQuestionDto failed", raw = decoded }
	end

	if dto.quizStorageId == "" then
		return nil, { msg = "missing quizStorageId", raw = decoded }
	end

	return dto, nil
end

function QuizApi.SubmitAnswerWithErr(quizStorageId: string, quizChoiceId: number)
	-- ✅ 서버가 POST할 바디 (Postman과 동일)
	local body = {
		quizStorageId = quizStorageId,
		selectedChoiceIds = { quizChoiceId }, -- 배열!
		textAnswer = "",
	}

	local ok, res = requestAsync("POST", QUIZ_SUBMIT_URL, body)
	if not ok or not res.Success then
		return nil, {
			msg = "POST failed",
			statusCode = res.StatusCode,
			statusMessage = res.StatusMessage,
			body = res.Body,
		}
	end

	local decoded = safeJsonDecode(res.Body or "")
	if not decoded then
		return nil, { msg = "POST decode failed", raw = res.Body }
	end

	-- decoded 예: { submissionId, quizStorageId, isCorrect, feedback, earnedScore, ... }
	return decoded, nil
end

return QuizApi

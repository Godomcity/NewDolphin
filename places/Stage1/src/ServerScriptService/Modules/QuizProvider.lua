-- ServerScriptService/Modules/QuizProvider.lua
--!strict
-- 외부 API(JSON) 응답 포맷을 내부 퀴즈 뱅크로 변환/제공 + 채점
-- 🔸 수정 포인트:
--   - GetNextQuestion(plr, solvedList?) : solvedList 기준으로 '안 푼 문제'만 골라서 하나 반환

local Players = game:GetService("Players")

local M = {}

-- ▼ 여기 JSON을 "Lua 테이블"로 옮겨둠 (answerIndex: 0-based → 내부는 1-based로 변환)
local RAW = {
	worldMapId = "ATLANTIS_STAGE_1",
	language = "KO",
	quizList = {
		{ quizId=2201, question="변수 x에 5를 저장하고, y에 3을 저장한 뒤 두 수의 곱을 출력하려면?",
			choices={"x = 5; y = 3; print(x * y)","x = 5, y = 3; print(x * y)","x = 5 * y = 3; print(x, y)","print(5 x 3)"},
			answerIndex=0 },
		{ quizId=2202, question="사용자로부터 입력을 받아 변수 name에 저장하려면?",
			choices={"input(name)","name = input()","name = input('name')","get.input(name)"},
			answerIndex=1 },
		{ quizId=2203, question="다음 코드의 출력 결과는?print(3 + 2 * 2)",
			choices={"10","7","8","9"},
			answerIndex=1 },
		{ quizId=2204, question="리스트 [1, 2, 3, 4]의 길이를 구하는 함수는?",
			choices={"count([1, 2, 3, 4])","size([1, 2, 3, 4])","length([1, 2, 3, 4])","len([1, 2, 3, 4])"},
			answerIndex=3 },
		{ quizId=2205, question="다음 코드의 출력 결과는?for i in range(2, 5):    print(i, end=' ')",
			choices={"2 3 4","1 2 3 4","0 1 2 3 4","3 4 5"},
			answerIndex=0 },
		{ quizId=2206, question="if문을 이용해 x가 10 이상일 때 'OK'를 출력하려면?",
			choices={"if x > 10 print('OK')","if (x >= 10): print('OK')","if x >= 10 then print('OK')","if x => 10: print('OK')"},
			answerIndex=1 },
		{ quizId=2207, question="다음 중 문자열 연결이 올바른 것은?",
			choices={"'Hello' + 'World'","'Hello' * 'World'","'Hello'.join('World')","concat('Hello', 'World')"},
			answerIndex=0 },
		{ quizId=2208, question="다음 코드의 출력 결과는?x = 10y = 3print(x % y)",
			choices={"3","1","0.3","7"},
			answerIndex=1 },
		{ quizId=2209, question="다음 코드의 출력 결과는?text = 'python'print(text.upper())",
			choices={"PYTHON","Python","python","pYTHON"},
			answerIndex=0 },
		{ quizId=2210, question="리스트 numbers = [1, 2, 3]에 4를 추가하려면?",
			choices={"numbers.add(4)","numbers.push(4)","numbers.append(4)","numbers.insert(4)"},
			answerIndex=2 },
	}
}

-- 내부 뱅크: id(string) 키 → {id,q,c,correct}
local BANK: {[string]: {id:string, q:string, c:{string}, correct:number}} = {}

do
	for _, q in ipairs(RAW.quizList) do
		local id = tostring(q.quizId)
		local correct1 = (q.answerIndex :: number) + 1  -- 0-based → 1-based
		BANK[id] = {
			id = id,
			q  = q.question,
			c  = q.choices,
			correct = correct1,
		}
	end
end

-- 고정 출제 순서
local ORDER: {string} = (function()
	local arr = {}
	for _, q in ipairs(RAW.quizList) do
		table.insert(arr, tostring(q.quizId))
	end
	return arr
end)()

local TOTAL = #ORDER

----------------------------------------------------------------
-- solvedList → set 으로 변환 ( ["2201"]=true, ... )
----------------------------------------------------------------
local function buildSolvedSet(solvedList: any): {[string]: boolean}
	local set: {[string]: boolean} = {}
	if typeof(solvedList) ~= "table" then
		return set
	end

	for _, id in ipairs(solvedList) do
		local key = tostring(id)
		if key ~= "" then
			set[key] = true
		end
	end

	return set
end

----------------------------------------------------------------
-- 플레이어별 다음 문제 제공
--  - solvedList 가 nil 이면: ORDER 순서대로 처음부터
--  - solvedList 가 table 이면: 그 중 "안 푼 문제"만 순서대로 골라서 하나 반환
--  - 더 이상 낼 문제가 없으면 nil
----------------------------------------------------------------
function M.GetNextQuestion(plr: Player, solvedList: any?)
	local solvedSet = buildSolvedSet(solvedList)

	-- 안 푼 문제 중에서 가장 앞에 있는 것 선택
	for _, qid in ipairs(ORDER) do
		if not solvedSet[qid] then
			local item = BANK[qid]
			if item then
				return {
					id = item.id,
					q  = item.q,
					c  = item.c,
				}
			end
		end
	end

	-- 전부 풀었으면 nil
	return nil
end

----------------------------------------------------------------
-- 채점: qid/choiceIndex(1..4)
----------------------------------------------------------------
function M.CheckAnswer(plr: Player, qid: string, choiceIndex: number)
	local item = BANK[qid]
	if not item then
		return { correct = false, reason = "qid_not_found" }
	end
	local ok = (choiceIndex == item.correct)
	return { correct = ok }
end

-- 필요 시 초기화/정리 (지금은 커서 사용 안 함)
function M.ResetPlayer(plr: Player)
	-- nothing
end

Players.PlayerRemoving:Connect(function(plr)
	-- 나중에 뭔가 캐시를 추가해도 여기서 정리
end)

return M

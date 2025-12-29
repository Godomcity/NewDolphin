---- ServerScriptService/QuizServer.lua
----!strict
---- 클라이언트 QuizClient.lua가 호출하는 Remotes:
----  - RF_Quiz_GetQuestion(): { id, q, c }  1문제 전달 (선택지 4개)
----  - RF_Quiz_CheckAnswer(qid, choiceIndex): { correct = boolean }

--local Players = game:GetService("Players")
--local RS      = game:GetService("ReplicatedStorage")

---- Remotes 폴더/함수 보장 (클라가 먼저 만들었어도 여기서 다시 참조)
--local Remotes = RS:FindFirstChild("Remotes")
--if not Remotes then
--	Remotes = Instance.new("Folder")
--	Remotes.Name = "Remotes"
--	Remotes.Parent = RS
--end

--local function ensureRF(name: string): RemoteFunction
--	local rf = Remotes:FindFirstChild(name)
--	if not rf then
--		rf = Instance.new("RemoteFunction")
--		rf.Name = name
--		rf.Parent = Remotes
--	end
--	return rf :: RemoteFunction
--end

--local RF_Get   = ensureRF("RF_Quiz_GetQuestion")
--local RF_Check = ensureRF("RF_Quiz_CheckAnswer")

---- 로컬 문제 은행 로드
--local BankMod = require(RS:WaitForChild("Modules"):WaitForChild("QuizBankLocal"))
--type BankItem = { id: string, q: string, c: {string}, a: number }
--local BANK: {BankItem} = BankMod.items or {}

---- 빠른 id->문제 매핑
--local BY_ID: {[string]: BankItem} = {}
--for _, it in ipairs(BANK) do
--	BY_ID[it.id] = it
--end

---- 1인 세션 상태(서버 메모리; 게임 떠나면 정리)
--type Session = {
--	used: {[string]: boolean},
--	asked: number,
--}
--local sessions: {[number]: Session} = {}
--local TOTAL_QUESTIONS = 10  -- 클라와 동일하게 유지

--local function getSession(plr: Player): Session
--	local s = sessions[plr.UserId]
--	if not s then
--		s = { used = {}, asked = 0 }
--		sessions[plr.UserId] = s
--	end
--	return s
--end

---- 남은 문제 중 랜덤 하나
--local function pickNextFor(plr: Player): BankItem?
--	if #BANK == 0 then return nil end
--	local s = getSession(plr)

--	-- 모두 소진 or 10문제 이상 요청했으면 nil 반환(클라가 HUD/컷씬 처리)
--	if s.asked >= TOTAL_QUESTIONS then
--		return nil
--	end

--	-- 남은 후보 모으기
--	local remain = {}
--	for _, it in ipairs(BANK) do
--		if not s.used[it.id] then table.insert(remain, it) end
--	end
--	if #remain == 0 then
--		return nil
--	end

--	-- 랜덤 선택
--	local r = Random.new(tick() * plr.UserId % 1 * 1e6)
--	local pick = remain[r:NextInteger(1, #remain)]

--	-- 상태 반영(여기서 asked 카운트만 증가; 정답 여부는 서버가 굳이 저장할 필요 X)
--	s.asked += 1
--	s.used[pick.id] = true

--	return pick
--end

---- 문제 전달
--RF_Get.OnServerInvoke = function(plr: Player)
--	local q = pickNextFor(plr)
--	if not q then
--		return nil
--	end
--	-- 보기만 보내고 정답 인덱스(a)는 숨김
--	return { id = q.id, q = q.q, c = q.c }
--end

---- 채점
--RF_Check.OnServerInvoke = function(plr: Player, qid: string, choiceIndex: number)
--	if typeof(qid) ~= "string" or typeof(choiceIndex) ~= "number" then
--		return { correct = false }
--	end
--	local q = BY_ID[qid]
--	if not q then
--		return { correct = false }
--	end
--	local ok = (choiceIndex == q.a)
--	return { correct = ok }
--end

---- 세션 정리
--Players.PlayerRemoving:Connect(function(plr)
--	sessions[plr.UserId] = nil
--end)

--print("[QuizServer] READY (local bank, RF_Quiz_GetQuestion / RF_Quiz_CheckAnswer)")

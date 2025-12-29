-- ReplicatedStorage/DialogueData.lua
--!strict
-- 스테이지2 전용 대사 데이터 (Phase별, 퀘스트 텍스트 제거 버전)

local M = {}

-- 말풍선에 뜨는 이름 (원하면 나중에 이름만 수정해도 됨)
M.npcName = "꽃게"
M.bubbleText = "조용히 좀 해줘요… zZz"

-- Phase 1 : 첫 진입, 퀘스트 시작 대사
-- (처음 NPC에게 말 걸었을 때)
M.phase1 = {
	{ speaker = "꽃게", text = "꺄! 안녕! 네가 소문으로 듣던 친구구나? 만나서 반가워" },
	{ speaker = "꽃게", text = "있지, 있지! 이 지저분한 쓰레기들 때문에 내 반짝이는 보물들이 하나도 안 보이잖아!" },
	{ speaker = "꽃게", text = "네가 퀴즈 짱이라며? 요기 쓰레기 10개만 '뿅!' 하고 정화시켜 줄래? 응? 응?" },
}

-- Phase 2 : 퀘스트 도중, 아직 10개 다 안 끝났을 때
M.phase2 = {
	{ speaker = "꽃게", text = "아직 멀었어? 으쌰으쌰! 힘내!" },
}

-- Phase 3 (진행 중) : 필요하면 Phase2와 동일하게 사용
M.phase3_incomplete = {
	{ speaker = "꽃게", text = "아직 멀었어? 으쌰으쌰! 힘내!" },
}

-- Phase 4 (최종) : 쓰레기 10개를 모두 정화한 뒤, 다시 말을 걸었을 때
-- 3번째 줄(포탈 열어줄게…)에서 포탈 컷씬을 실행시키고,
-- 나머지 2줄은 컷씬 이후 이어지는 대사로 사용하면 좋음.
M.phase4_final = {
	{ speaker = "꽃게", text = "우와~ 완벽해! 👏👏👏" },
	{ speaker = "꽃게", text = "우리 집이 다시 반짝반짝해졌어! 너 정말 최고야" },
	{ speaker = "꽃게", text = "고마우니까 내가 다음 구역 포탈 열어줄게! 받아라, 집게 파워" }, -- ★ 이 라인 끝나고 포탈 컷씬
	{ speaker = "꽃게", text = "저 너머엔... 음... 조금 무서운 친구가 있긴 한데... 너라면 괜찮을 거야! 화이팅!" },
}

-- 기본 lines (예전 코드 호환용) → 1페이즈 대사로 사용
M.lines = M.phase1

-- phases 테이블(DialogueUI가 questPhase로 인덱싱해서 쓰기 좋게 유지)
M.phases = {
	[1] = M.phase1,
	[2] = M.phase2,
	[3] = M.phase3_incomplete,
	[4] = M.phase4_final,
}

return M

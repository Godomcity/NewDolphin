-- ReplicatedStorage/DialogueData.lua
--!strict
-- 스테이지2 전용 대사 데이터 (Phase별, 퀘스트 텍스트 제거 버전)

local M = {}

-- 말풍선에 뜨는 이름 (원하면 나중에 이름만 수정해도 됨)
M.npcName = "해마"
M.bubbleText = "조용히 좀 해줘요… zZz"

-- Phase 1 : 첫 진입, 퀘스트 시작 대사
-- (처음 NPC에게 말 걸었을 때)
M.phase1 = {
	{ speaker = "해마", text = "네가 그 녀석이로군... 여기까지 용케 왔어." },
	{ speaker = "해마", text = "여긴 마지막 구역. 이 구역만 정화하면… 우리의 임무도 끝이야." },
	{ speaker = "해마", text = "표적은 10개… 파트너, 신속하게 처리하지." },
}

-- Phase 2 : 퀘스트 도중, 아직 10개 다 안 끝났을 때
M.phase2 = {
	{ speaker = "해마", text = "아직 임무 수행 중인가? ...방해하지 마." },
}

-- Phase 3 (진행 중) : 필요하면 Phase2와 동일하게 사용
M.phase3_incomplete = {
	{ speaker = "해마", text = "아직 임무 수행 중인가? ...방해하지 마." },
}

-- Phase 4 (최종) : 쓰레기 10개를 모두 정화한 뒤, 다시 말을 걸었을 때
-- 3번째 줄(포탈 열어줄게…)에서 포탈 컷씬을 실행시키고,
-- 나머지 2줄은 컷씬 이후 이어지는 대사로 사용하면 좋음.
M.phase4_final = {
	{ speaker = "해마", text = "...완벽해. 이 구역의 오염원은 모두 제거됐다" },
	{ speaker = "해마", text = "이제... 바다 전체가 정화됐어. 마지막 '보고'를 하러 갈 시간이다." },
	{ speaker = "해마", text = "내가 최종 집결지로 가는 포탈을 열지." }, -- ★ 이 라인 끝나고 포탈 컷씬
	{ speaker = "해마", text = "다른 동료들도 모두 그 곳에서 널 기다리고 있다." },
	{ speaker = "해마", text = "어서 가봐, 모두의 힘이 필요한 마지막 절차가 남았으니까." },
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

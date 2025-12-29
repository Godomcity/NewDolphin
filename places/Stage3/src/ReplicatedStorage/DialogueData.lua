-- ReplicatedStorage/DialogueData.lua
--!strict
-- 스테이지2 전용 대사 데이터 (Phase별, 퀘스트 텍스트 제거 버전)

local M = {}

-- 말풍선에 뜨는 이름 (원하면 나중에 이름만 수정해도 됨)
M.npcName = "상어"
M.bubbleText = "조용히 좀 해줘요… zZz"

-- Phase 1 : 첫 진입, 퀘스트 시작 대사
-- (처음 NPC에게 말 걸었을 때)
M.phase1 = {
	{ speaker = "상어", text = "칫... 네 녀석이군. 앞 스테이지에서 소란 피운 녀석이" },
	{ speaker = "상어", text = " 이 구역은 내 영역이다. ...그런데 지금 이 더러운 쓰레기들 때문에 아주 거슬려" },
	{ speaker = "상어", text = "난 이런 지저분한 건 딱 질색이야." },
	{ speaker = "상어", text = "실력 좀 볼까. 이 구역 쓰레기 10개, 당장 안 치워? 멍하니 서 있지 말고" },
}

-- Phase 2 : 퀘스트 도중, 아직 10개 다 안 끝났을 때
M.phase2 = {
	{ speaker = "상어", text = "아직도 얼쩡거려? 꾸물대지 말고 어서 치워!" },
}

-- Phase 3 (진행 중) : 필요하면 Phase2와 동일하게 사용
M.phase3_incomplete = {
	{ speaker = "상어", text = "아직도 얼쩡거려? 꾸물대지 말고 어서 치워!" },
}

-- Phase 4 (최종) : 쓰레기 10개를 모두 정화한 뒤, 다시 말을 걸었을 때
-- 3번째 줄(포탈 열어줄게…)에서 포탈 컷씬을 실행시키고,
-- 나머지 2줄은 컷씬 이후 이어지는 대사로 사용하면 좋음.
M.phase4_final = {
	{ speaker = "상어", text = "흥. 생각보다 쓸 만하군. 이제 좀 다닐 만해졌어." },
	{ speaker = "상어", text = "내 영역을 깨끗하게 해 줬으니, 보답은 하지." },
	{ speaker = "상어", text = "다음 구역으로 가는 포탈이다" }, -- ★ 이 라인 끝나고 포탈 컷씬
	{ speaker = "상어", text = "저 너머엔 더 귀찮은 녀석들이 있어. 어디 잘해 보라고." },
	{ speaker = "상어", text = "내 눈앞에서 사라져." },
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

-- ReplicatedStorage/DialogueData.lua
--!strict
-- 스테이지2 전용 대사 데이터 (Phase별, 퀘스트 텍스트 제거 버전)

local M = {}

-- 말풍선에 뜨는 이름 (원하면 나중에 이름만 수정해도 됨)
M.npcName = "거북이"
M.bubbleText = "조용히 좀 해줘요… zZz"

-- Phase 1 : 첫 진입, 퀘스트 시작 대사
-- (처음 NPC에게 말 걸었을 때)
M.phase1 = {
	{ speaker = "거북이", text = "음냐암 …  zZz … 어? 누구… 시끄럽네…" },
	{ speaker = "거북이", text = "아…너구나….돌핀이 말한 친구가….." },
	{ speaker = "거북이", text = "보다시피 난 좀 자야하는데, 이놈의 오염된 쓰레기들 때문에… 하암… 영 잠자리가 사나워." },
	{ speaker = "거북이", text = "너가 퀴즈를 잘 푼다며? 이 구역의 쓰레기 10개만… 정화해 줘. 그럼 조용해지겠지?…" },
	{ speaker = "거북이", text = "난… 다시 좀 잘게 … zZz …" },
}

-- Phase 2 : 퀘스트 도중, 아직 10개 다 안 끝났을 때
M.phase2 = {
	{ speaker = "거북이", text = "...아직도... 다 안 끝났나... 시끄럽네… zZz" },
}

-- Phase 3 (진행 중) : 필요하면 Phase2와 동일하게 사용
M.phase3_incomplete = {
	{ speaker = "거북이", text = "...아직도... 다 안 끝났나... 시끄럽네… zZz" },
}

-- Phase 4 (최종) : 쓰레기 10개를 모두 정화한 뒤, 다시 말을 걸었을 때
-- 3번째 줄(포탈 열어줄게…)에서 포탈 컷씬을 실행시키고,
-- 나머지 2줄은 컷씬 이후 이어지는 대사로 사용하면 좋음.
M.phase4_final = {
	{ speaker = "거북이", text = "(기지개를 켜며) 아… 드디어… 조용하고 깨끗해졌네…" },
	{ speaker = "거북이", text = "덕분에… 이제 정말 꿀잠 잘 수 있겠어…. 고마워…." },
	{ speaker = "거북이", text = "다음 구역으로 갈 수 있는 포탈을 열어줄게…." }, -- ★ 이 라인 끝나고 포탈 컷씬
	{ speaker = "거북이", text = "저 너머에도…. 도움이 필요한 친구들이 있어…" },
	{ speaker = "거북이", text = "나는 이제 정말 잘게… 잘 가… zZz" },
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

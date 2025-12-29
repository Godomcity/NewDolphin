-- ReplicatedStorage/DialogueData.lua
--!strict
-- 스테이지1 전용 대사 데이터 (Phase별)

local M = {}

-- 말풍선에 뜨는 이름
M.npcName = "돌핀"
M.bubbleText = "도움이 필요해요!"

-- Phase 1 : 첫 진입, 전체 상황 설명 + 튜토리얼 쓰레기 안내
M.phase1 = {
	{ speaker = "돌고래", text = "드디어 와주셨군요! 저는 이 구역을 지키는 수호자, '돌핀'입니다." },
	{ speaker = "돌고래", text = "… 보시다시피, 우리의 바다가 정체 모를 '오염'에 휩싸였어요." },
	{ speaker = "돌고래", text = "당신의 도움이 필요해요." },
	{ speaker = "돌고래", text = "우선, 우측에 있는 ‘오염된 쓰레기’에 다가가 상호작용 키를 눌러보시겠어요?" },
	{ speaker = "돌고래", text = "바다를 정화할 ‘신비한 퀴즈’가 나타날 거예요. 당신의 지혜로 퀴즈를 풀면, 쓰레기는 깨끗하게 정화될 거예요!" },
	{ speaker = "돌고래", text = "퀴즈를 정화 후 다시 저에게 말을 걸어주세요." },
}

-- Phase 2 : 튜토리얼 쓰레기 1개 정화 후, NPC에게 돌아왔을 때
-- (2번 퀘스트 완료 + 3번 퀘스트 시작 설명)
M.phase2 = {
	{ speaker = "돌고래", text = "훌륭해요! 당신의 지혜가 오염을 없애고, 바다를 정화시켰어요!" },
	{ speaker = "돌고래", text = "하지만 아직 안심하긴 일러요. 이 구역에는 아직 9개의 쓰레기가 남아있어요." },
	{ speaker = "돌고래", text = "이 구역의 남은 쓰레기 9개를 모두 찾아 정화해 주세요! 이 바다의 운명이 당신의 손에 달렸습니다!" },
}

-- Phase 3 (진행 중) : 9개 다 안 끝난 상태에서 NPC에게 말 걸었을 때
M.phase3_incomplete = {
	{ speaker = "돌고래", text = "아직 맵 어딘가에 오염원이 남아있어요. 정화를 서둘러 주세요!" },
}

-- Phase 4 (최종) : 10문제+쓰레기 9개 전부 끝난 뒤, 마지막 대사
-- 2번째 줄에서 포탈 컷씬이 나가고, 그 다음 줄이 마지막 멘트
M.phase4_final = {
	{ speaker = "돌고래", text = "당신의 용기와 지혜 덕분에 이 구역이 다시 빛을 되찾았어요!" },
	{ speaker = "돌고래", text = "다음 스테이지로 가는 해류 포탈을 열어드릴게요." }, -- ★ 이 라인 끝나고 포탈 컷씬
	{ speaker = "돌고래", text = "저 너머에도 당신의 도움이 절실히 필요합니다. 부디 바다를 구해주세요!" },
}

-- 기본 lines (예전 코드 호환용) → 1페이즈 대사로 사용
M.lines = M.phase1

-- phases 테이블(DialogueUI가 questPhase로 인덱싱해서 쓰기 좋게)
M.phases = {
	[1] = M.phase1,
	[2] = M.phase2,
	[3] = M.phase3_incomplete,
	[4] = M.phase4_final,
}

return M

-- ReplicatedStorage/Modules/HubDialogueData.lua
--!strict
-- 허브에서 출력할 캐릭터 대사 모음

local M = {}

-- 공통 텍스트 스타일
local STYLE = {
	nameColor = Color3.fromRGB(240, 255, 255),
	textColor = Color3.fromRGB(240, 240, 240),
}

M.characters = {
	turtle = {
		key = "turtle",
		displayName = "🐢 거북이",
		persona = "잠만보, 느긋함",
		line = [[하암... 바다가 더러워져서... 잠자리가 영 불편하구먼...  ...네가 좀... 구해줘...]],
		style = STYLE,
	},
	shark = {
		key = "shark",
		displayName = "🦈 상어",
		persona = "무서움, 터프함",
		line = [[칫... 이 더러운 물 냄새, 정말 거슬리는군. 가만히 서 있지 말고 당장 바다를 구해!]],
		style = STYLE,
	},
	dolphin = {
		key = "dolphin",
		displayName = "🐬 돌핀",
		persona = "대표 캐릭터, 영웅적",
		line = [[드디어 와주셨군요! 우리의 바다가 심각하게 오염되고 있어요! 지금 바로 당신의 힘이 필요해요!]],
		style = STYLE,
	},
	seahorse = {
		key = "seahorse",
		displayName = "🤠 해마",
		persona = "총잡이, 쿨함",
		line = [[목표는 '오염된 바다'. 임무는 '정화'. ...신속하게 처리해 주길 바란다, 파트너.]],
		style = STYLE,
	},
	crab = {
		key = "crab",
		displayName = "🦀 꽃게",
		persona = "발랄함, 귀여움",
		line = [[꺄! 바다가 너무 지저분해졌잖아! 반짝반짝 빛나는 바다로 다시 돌려줘!]],
		style = STYLE,
	},
}

-- 기본 재생 순서(선택)
M.defaultOrder = { "turtle", "shark", "dolphin", "seahorse", "crab" }

return M

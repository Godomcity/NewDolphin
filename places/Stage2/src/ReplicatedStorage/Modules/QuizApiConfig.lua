-- ReplicatedStorage/Modules/QuizApiConfig.lua
return {
	-- 지금은 원격 API 사용 안함
	url = "",

	headers = {
		["Accept"]      = "application/json",
		["X-CLIENT-ID"] = "ROBLOX_CLIENT_ID",
	},

	cacheSec = 300,

	-- 디버그 로그 OFF (필요하면 true)
	debug = false,

	-- ★ 오프라인 스위치: true면 절대 HTTP 요청 안 보냄
	offline = true,

	-- 정확한 엔드포인트 확정 후 강제로 이 주소만 쓰고 싶다면 배열로 넣으세요.
	-- forceCandidates = { "https://api.example.com/...." },
	forceCandidates = nil,
}

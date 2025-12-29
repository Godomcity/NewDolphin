# Stage4 퀴즈 연동 요약

- **API 호출 스크립트**: `src/ServerScriptService/QuizApiService.lua`에서 `QuizApiConfig` 값에 따라 HttpService 요청을 보내 퀴즈 문제를 불러오도록 구성되어 있습니다.
- **서버 처리 스크립트**: `src/ServerScriptService/QuizRemoteService.server.lua`가 RemoteFunction(`RF_Quiz_GetQuestion`, `RF_Quiz_CheckAnswer`)을 열고, `QuizProvider`/`SessionProgress`를 통해 문제 지급과 정답 체크를 수행합니다.
- **클라이언트 스크립트**: `src/StarterPlayer/StarterPlayerScripts/QuizClient.client.lua`가 UI를 띄우고, 이미 푼 문제 ID 목록을 서버에 보내 새 문제를 요청한 뒤 선택한 보기를 제출해 정답 여부를 확인합니다.

-- StarterPlayerScripts/LobbyEnter.client.lua
local RS = game:GetService("ReplicatedStorage")
local TeleportUtil = require(RS.Modules.TeleportUtil)

local HUB_PLACE_ID = 120816172838238  -- 허브 PlaceId로 교체
local inputCode = "사용자입력코드" -- TextBox.Text 등

TeleportUtil.Go(HUB_PLACE_ID, {
	sessionId = inputCode,       -- 첫 진입에서만 꼭 넣어줌
	reason = "enter_hub",
})

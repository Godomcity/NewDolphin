-- ReplicatedStorage/Modules/UI/UIRefs.lua
-- 화면에 "이미 배치된" UI를 찾아서 참조를 반환한다.
-- 스크린샷 구조 대응:
-- EntryScreen
--  ├─ Wrapper
--  │   └─ EntryCard
--  │       ├─ EnterTextBox
--  │       ├─ TokenTextBox
--  │       ├─ TextButton   ← (Enter 버튼)
--  │       ├─ CircleIcon
--  │       └─ TextLabel

local M = {}

local function findDesc(root: Instance, name: string)
	if not root then return nil end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then return d end
	end
	return nil
end

local function warnMissing(label, obj)
	if not obj then warn(("[UIRefs] %s not found"):format(label)) end
end

-- entryScreen: ScreenGui (ex: script.Parent)
function M.bind(entryScreen: Instance)
	local ui = {}

	ui.Root       = entryScreen
	ui.Wrapper    = findDesc(entryScreen, "Wrapper") or entryScreen
	ui.EntryCard  = findDesc(ui.Wrapper, "EntryCard")

	ui.EnterTextBox = ui.EntryCard and findDesc(ui.EntryCard, "EnterTextBox") or nil
	ui.TokenTextBox = ui.EntryCard and findDesc(ui.EntryCard, "TokenTextBox") or nil

	-- 버튼 이름이 TextButton으로 변경됨 → EnterButton 별칭으로도 제공
	local btn = ui.EntryCard and (findDesc(ui.EntryCard, "TextButton") or findDesc(ui.EntryCard, "EnterButton")) or nil
	ui.TextButton  = btn
	ui.EnterButton = btn  -- ✅ 기존 코드 호환

	ui.CircleIcon  = ui.EntryCard and findDesc(ui.EntryCard, "CircleIcon") or nil
	ui.TextLabel   = ui.EntryCard and findDesc(ui.EntryCard, "TextLabel") or nil
	ui.Background  = findDesc(entryScreen, "Background") -- 있으면 반환 (옵션)

	-- 진단 메시지(개발 중 편의)
	warnMissing("Wrapper", ui.Wrapper)
	warnMissing("EntryCard", ui.EntryCard)
	warnMissing("EnterTextBox", ui.EnterTextBox)
	warnMissing("TokenTextBox", ui.TokenTextBox)
	warnMissing("TextButton/EnterButton", ui.EnterButton)
	warnMissing("CircleIcon", ui.CircleIcon)

	-- 초기 상태 권장: CircleIcon 숨김
	if ui.CircleIcon and ui.CircleIcon:IsA("GuiObject") then
		ui.CircleIcon.Visible = false
	end

	return ui
end

return M

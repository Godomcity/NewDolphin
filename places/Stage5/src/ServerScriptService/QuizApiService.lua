-- ServerScriptService/QuizApiService.lua
--!strict
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local function tryRequire(inst: Instance?): any
	if inst and inst:IsA("ModuleScript") then
		local ok, m = pcall(require, inst)
		if ok then return m end
	end
	return nil
end

local cfg = tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("QuizApiConfig"))
	or tryRequire(RS:FindFirstChild("QuizApiConfig"))
	or {}

local BASE_URL  = tostring(cfg.url or "")
local HEADERS   = cfg.headers or { ["Accept"] = "application/json" }
local CACHE_SEC = tonumber(cfg.cacheSec or 300) :: number
local DEBUG     = cfg.debug == true
local OFFLINE   = (cfg.offline == true) or (BASE_URL == "")

export type Item = { id:string, q:string, c:{string}, a:number }
local cache = { data: {} :: {Item}?, expires: 0 }

local M = {}

-- 오프라인: HTTP 일절 금지, 빈 배열만 반환(경고도 안 찍음)
function M.Preload(_stage:number): {Item}
	if OFFLINE then
		cache.data = {}
		cache.expires = os.clock() + CACHE_SEC
		return {}
	end
	-- 온라인 모드 로직은 나중에 활성화
	return {}
end

function M.Reload(_stage:number?)
	cache.data = nil
	cache.expires = 0
end

function M.GetBank(stage:number?, _opts:any?): {Item}
	if OFFLINE then return {} end
	return cache.data or {}
end

function M.SelectTen(stage:number, opts:{seed:number?, number:number?}?): {Item}
	if OFFLINE then return {} end
	local bank = M.GetBank(stage)
	if #bank == 0 then return {} end
	local want = math.clamp(tonumber(opts and opts.number or 10) or 10, 1, 50)
	local r = (opts and opts.seed) and Random.new(tonumber(opts.seed) :: number) or Random.new()
	local used:{[number]:boolean} = {}; local out:{Item} = {}
	for _=1, math.min(want, #bank) do
		local idx = r:NextInteger(1, #bank); local tries=0
		while used[idx] and tries<6 do idx=r:NextInteger(1,#bank); tries+=1 end
		used[idx]=true; table.insert(out, bank[idx])
	end
	return out
end

return M

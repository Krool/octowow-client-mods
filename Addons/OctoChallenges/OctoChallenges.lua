-- OctoChallenges: shows your own active leveling challenges as icons on the
-- character paperdoll, with hover tooltips.
--
-- Protocol (Turtle/OctoWoW client, from patch-4 TargetFrame.lua and
-- Turtle_General.lua): send  SendAddonMessage("TW_UI",
-- "REQUEST_PLAYER_CHALLENGES;<guid>", "GUILD"); the server answers with a
-- CHAT_MSG_ADDON whose PREFIX (arg1) is "RESPONSE_PLAYER_CHALLENGES" and whose
-- body (arg2) is "<guid>:<mask>". Bit i of the mask = list index i+1 below
-- (same ordering as Turtle_AvailableChallenges, extended by OctoChallengeTip).
-- Guids come from Turtle's extended UnitExists: local _, guid = UnitExists(unit).

-- Double-load guard: this file also ships inside the octowow-client-mods
-- repo (root toc for launcher git-URL installs). With both addons present,
-- the second copy must not register duplicate frames/handlers.
if OctoChallenges_Loaded then
	return
end
OctoChallenges_Loaded = true

local CHALLENGES = {
	{ name = "Slow & Steady",         icon = "Spell_Nature_TimeStop",
	  desc = "Gaining 50% fewer experience points from defeating enemies. Lose 5% of accumulated experience from current level upon being defeated by enemies." },
	{ name = "Exhaustion",            icon = "Spell_Nature_Sleep",
	  desc = "No longer gaining rested experience, but your weapon skill gain will be doubled." },
	{ name = "War Mode",              icon = "Ability_DualWield",
	  desc = "PvP is enabled. While active: experience gain from all sources is increased, and killing players in the open world grants experience. Disabling it is permanent for this character." },
	{ name = "Hardcore",              icon = "INV_Misc_Bone_HumanSkull_01",
	  desc = "Upon death your spirit is lost to the Twisting Nether, unable to ever return to the Material Plane." },
	{ name = "Vagrant's Endeavor",    icon = "Ability_Warrior_Disarm",
	  desc = "You can only use poor and common quality equipment. Enchanting items is not allowed." },
	{ name = "Boaring Adventure",     icon = "Spell_Magic_PolymorphPig",
	  desc = "In this challenge, leveling up is a real pig deal. Experience comes exclusively from slaying boars!" },
	{ name = "Level One Lunatic",     icon = "INV_Pet_Mouse",
	  desc = "During this challenge, you will earn exclusive titles while staying at level one." },
	{ name = "Traveling Craftmaster", icon = "Ability_Repair",
	  desc = "Equip only what you craft. True power comes from your own hands!" },
	{ name = "Path of the Brewmaster", icon = "INV_Cask_03",
	  desc = "From bar to the Barrens, your journey begins! You gain no experience unless you're completely smashed. For every ding, have a drink!" },
	{ name = "Trial of Heroism",      icon = "Ability_Warlock_DemonicEmpowerment",
	  desc = "Achieve level 58 by earning experience strictly from orange and red-tier monsters and quests." },
	{ name = "Way of the Samurai",    icon = "INV_Sword_41",
	  desc = "You may only wield katana-style swords. No other weapon (bows, guns, etc.) may be equipped." },
	{ name = "Together Forever",      icon = "Spell_Holy_PrayerofSpirit",
	  desc = "Bound to your fellowship: you gain experience from kills only while your entire fellowship is with you. The bond is permanent." },
	{ name = "True Hardcore",         icon = "Spell_Shadow_SoulGem",
	  desc = "Locked to the Hardcore Realm. This character can never leave through the Dark Portal or transfer to another realm." },
}
local NUM_CHALLENGES = table.getn(CHALLENGES)

local ICON_SIZE = 26
local ICON_GAP  = 5
local MAX_RETRIES = 12
local RETRY_INTERVAL = 2

local playerGuid = nil
local retriesLeft = 0
local gotResponse = false
local icons = {}

local function GetPlayerGuid()
	if not playerGuid then
		local _, guid = UnitExists("player")
		playerGuid = guid
	end
	return playerGuid
end

local function ActiveList(mask)
	local list = {}
	local bit = 1
	for i = 1, NUM_CHALLENGES do
		if mod(mask, bit * 2) >= bit then
			table.insert(list, CHALLENGES[i])
		end
		bit = bit * 2
	end
	return list
end

-- ---------------------------------------------------------------- UI --------

local function Icon_OnEnter()
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:AddLine(this.challengeName, 1, 0.82, 0)
	GameTooltip:AddLine(this.challengeDesc, 1, 1, 1, 1)
	GameTooltip:AddLine("Active challenge", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function Icon_OnLeave()
	GameTooltip:Hide()
end

local ICONS_PER_COLUMN = 5

local function GetIconButton(i)
	if icons[i] then return icons[i] end
	local b = CreateFrame("Button", "OctoChallengesIcon" .. i, PaperDollFrame)
	b:SetWidth(ICON_SIZE)
	b:SetHeight(ICON_SIZE)
	-- Column down the LEFT inside edge of the 3D model area. The right edge
	-- is taken by CharacterResistanceFrame (x 265-297), and the model's
	-- top-left 70x35 is the rotate buttons, so start below those. Wraps into
	-- a second column for characters with many challenges.
	local col = math.floor((i - 1) / ICONS_PER_COLUMN)
	local row = math.mod(i - 1, ICONS_PER_COLUMN)
	b:SetPoint("TOPLEFT", CharacterModelFrame, "TOPLEFT",
		6 + col * (ICON_SIZE + 9), -42 - row * (ICON_SIZE + ICON_GAP))
	b:SetFrameLevel(CharacterModelFrame:GetFrameLevel() + 2)

	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	border:SetPoint("CENTER", b, "CENTER", 0, -1)
	border:SetWidth(ICON_SIZE + 18)
	border:SetHeight(ICON_SIZE + 18)

	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(b)
	b.icon = tex

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	b:GetHighlightTexture():SetBlendMode("ADD")
	b:SetScript("OnEnter", Icon_OnEnter)
	b:SetScript("OnLeave", Icon_OnLeave)

	icons[i] = b
	return b
end

local function Render()
	local mask = OctoChallengesDB and OctoChallengesDB.mask
	local list = mask and ActiveList(mask) or {}
	for i = 1, table.getn(list) do
		local b = GetIconButton(i)
		b.icon:SetTexture("Interface\\Icons\\" .. list[i].icon)
		b.challengeName = list[i].name
		b.challengeDesc = list[i].desc
		b:Show()
	end
	for i = table.getn(list) + 1, table.getn(icons) do
		icons[i]:Hide()
	end
end

-- Char-select bridge: where nampower's file APIs exist in this VM, the mask
-- is upserted into CustomData\octoglue-challenges the moment the server
-- answers (format "v1|Realm/Name=mask,...") and the character-select screen
-- (OctoGlue v25+) reads that file live - no rebuild step. Without the APIs
-- the "OctoGlue realm status" scheduled task mirrors SavedVariables into the
-- same file after a logout flush, and glue's baked OCTO_BAKED_CHALLENGES
-- table is the final fallback. This addon keeps OctoChallengesDB.mask
-- current either way.

local CHAL_FILE = "octoglue-challenges"

local function MirrorMask(mask)
	if type(WriteCustomFile) ~= "function" then
		return false
	end
	local realm = string.gsub(GetRealmName() or "", "^%s*(.-)%s*$", "%1")
	local name = UnitName("player")
	if realm == "" or not name then
		return false
	end
	local entries, order = {}, {}
	if type(ReadCustomFile) == "function" then
		local ok, s = pcall(ReadCustomFile, CHAL_FILE)
		if ok and type(s) == "string" then
			-- keys are "Realm/Name" (may contain spaces and '), values digits;
			-- the "v1" header has no "=" so the pattern skips it naturally
			for k, v in string.gfind(s, "([^=,|]+)=(%d+)") do
				if not entries[k] then
					table.insert(order, k)
				end
				entries[k] = v
			end
		end
	end
	local key = realm .. "/" .. name
	if not entries[key] then
		table.insert(order, key)
	end
	entries[key] = tostring(mask)
	local parts = {}
	for i = 1, table.getn(order) do
		table.insert(parts, order[i] .. "=" .. entries[order[i]])
	end
	local ok = pcall(WriteCustomFile, CHAL_FILE, "v1|" .. table.concat(parts, ","))
	return ok
end

-- ------------------------------------------------------------ protocol ------

local settledNoAnswer = false

local timer = CreateFrame("Frame")
timer.elapsed = 0
timer:Hide()
timer:SetScript("OnUpdate", function()
	timer.elapsed = timer.elapsed + arg1
	if timer.elapsed < RETRY_INTERVAL then return end
	timer.elapsed = 0
	if gotResponse then
		timer:Hide()
		return
	end
	if retriesLeft <= 0 then
		timer:Hide()
		-- The server does NOT reply for a character with zero active
		-- challenges (verified 2026-08-31: every zero-challenge char times
		-- out, every challenged char answers) - silence after a full retry
		-- run IS the "no challenges" answer. Cache and mirror mask 0 so
		-- character select stops showing stale/baked icons. Only when
		-- nothing was ever cached; an existing mask is kept untouched
		-- (a flood-dropped reply must not wipe real data).
		if not settledNoAnswer then
			settledNoAnswer = true
			if not (OctoChallengesDB and OctoChallengesDB.mask) then
				if not OctoChallengesDB then OctoChallengesDB = {} end
				OctoChallengesDB.mask = 0
				Render()
				MirrorMask(0)
			end
		end
		return
	end
	retriesLeft = retriesLeft - 1
	local guid = GetPlayerGuid()
	if guid then
		SendAddonMessage("TW_UI", "REQUEST_PLAYER_CHALLENGES;" .. guid, "GUILD")
	end
end)

local function RequestChallenges()
	gotResponse = false
	retriesLeft = MAX_RETRIES
	timer.elapsed = RETRY_INTERVAL -- fire on next frame
	timer:Show()
end

local handler = CreateFrame("Frame")
handler:RegisterEvent("VARIABLES_LOADED")
handler:RegisterEvent("PLAYER_ENTERING_WORLD")
handler:RegisterEvent("CHAT_MSG_ADDON")
handler:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		if not OctoChallengesDB then OctoChallengesDB = {} end
	elseif event == "PLAYER_ENTERING_WORLD" then
		Render() -- cached mask from a previous session, if any
		RequestChallenges()
	elseif event == "CHAT_MSG_ADDON" and arg1 == "RESPONSE_PLAYER_CHALLENGES" then
		-- %d* not %d+: accept an empty mask ("guid:") as zero challenges
		local _, _, guid, mask = string.find(arg2 or "", "^(.+):(%d*)$")
		if guid and guid == GetPlayerGuid() then
			gotResponse = true
			if not OctoChallengesDB then OctoChallengesDB = {} end
			local old = OctoChallengesDB.mask
			OctoChallengesDB.mask = tonumber(mask) or 0
			Render()
			local mirrored = MirrorMask(OctoChallengesDB.mask)
			-- Announce a NEW or CHANGED cache (a silent failure here used to
			-- read as "no challenges" and leave character select stale).
			if OctoChallengesDB.mask ~= old then
				local n = table.getn(ActiveList(OctoChallengesDB.mask))
				if mirrored then
					DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OctoChallenges|r: cached " .. n .. " active challenge(s) - character-select icons update automatically.")
				else
					DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OctoChallenges|r: cached " .. n .. " active challenge(s) - character select refreshes after your next logout.")
				end
			end
		end
	end
end)

-- Re-query when the paperdoll opens if the login-time request never answered.
local origPaperDollOnShow = PaperDollFrame:GetScript("OnShow")
PaperDollFrame:SetScript("OnShow", function()
	if origPaperDollOnShow then origPaperDollOnShow() end
	if not gotResponse then RequestChallenges() end
	Render()
end)

-- ---------------------------------------------------------------- slash -----

SLASH_OCTOCHALLENGES1 = "/octochallenges"
SlashCmdList["OCTOCHALLENGES"] = function()
	RequestChallenges()
	local mask = OctoChallengesDB and OctoChallengesDB.mask
	if not mask or mask == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OctoChallenges|r: no active challenges known (re-querying server).")
		return
	end
	local list = ActiveList(mask)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OctoChallenges|r: active challenges:")
	for i = 1, table.getn(list) do
		DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100" .. list[i].name .. "|r")
	end
end

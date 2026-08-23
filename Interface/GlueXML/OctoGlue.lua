-- OctoGlue.lua - character-select enhancements for the OctoWoW client.
-- by Krool
--
-- LOADING MECHANISM: this client's exe gives extra patch archives (like our
-- patch-9.mpq) LOWER priority than its built-in patch-1..5 list, so we cannot
-- override patch-4's CharacterSelect.lua directly. Instead patch-9 overrides
-- CreditsFrame.xml (which ships ONLY in the base interface.MPQ, where extras
-- DO win) and that XML includes this file. CreditsFrame.xml sits after
-- CharacterSelect.xml in GlueXML.toc, so by the time this runs the stock
-- functions exist and we can redefine them. XML event handlers call these
-- functions by global name at event time, so redefinition is safe.
--
-- Features:
--   * OctoReorder - per-row up/down arrows to rearrange the character list.
--   * OctoChal    - per-row challenge icons (fed by the OctoChallenges
--                   in-world addon through the shared cvar payload).
--   * OctoSound   - "Sound" button on login + char select opening a
--                   volume-slider panel usable before logging in.
--
-- Storage: one cvar holds a ";"-separated payload of "K=value" sections:
--   O=<name1>,<name2>,...          display order (owned here)
--   C=<realm>/<name>:<mask>,...    challenge masks (owned by OctoChallenges)
-- Cvars are engine-global across the glue<->world boundary. Candidates:
-- custom "octoCharOrder" first, stock "accountList" (sub-account list,
-- unused on private servers) as fallback; session-only if neither persists.
--
-- OctoReorder renders a display permutation (the server's char-enum order is
-- immutable client-side): ReorderPerm[displaySlot] = server character index.
-- CharacterSelect.selectedIndex stays a SERVER index everywhere (rename,
-- delete, EnterWorld and the selection events keep working untouched); only
-- rendering, row clicks and keyboard navigation translate through the
-- permutation. The create-button path is unaffected: its id is always >
-- numChars, and Reorder_ServerIndex falls back to the input for unmapped ids.
-- The order is saved as names and re-matched by name on every list update,
-- so it survives creates, deletes and renames (unknown names append in
-- server order).

local ReorderPerm = {}
local octoCvar = nil
local OCTO_CVAR_CANDIDATES = { "octoCharOrder", "accountList" }

-- Without pcall, a rejected SetCVar would hard-error and take the whole
-- character screen down with it - so no pcall, no persistence.
local function Octo_CanPersist()
	return type(pcall) == "function"
		and type(SetCVar) == "function"
		and type(GetCVar) == "function"
end

local function Octo_ReadPayload()
	if not Octo_CanPersist() then
		return ""
	end
	if octoCvar then
		local ok, s = pcall(GetCVar, octoCvar)
		if ok and type(s) == "string" then
			return s
		end
		return ""
	end
	for _, cvar in ipairs(OCTO_CVAR_CANDIDATES) do
		local ok, s = pcall(GetCVar, cvar)
		if ok and type(s) == "string" and string.find(s, "^%a=") then
			octoCvar = cvar
			return s
		end
	end
	return ""
end

local function Octo_WritePayload(payload)
	if not Octo_CanPersist() then
		return
	end
	if octoCvar then
		pcall(SetCVar, octoCvar, payload)
		return
	end
	for _, cvar in ipairs(OCTO_CVAR_CANDIDATES) do
		local ok = pcall(SetCVar, cvar, payload)
		if ok then
			local ok2, got = pcall(GetCVar, cvar)
			if ok2 and got == payload then
				octoCvar = cvar
				return
			end
		end
	end
end

local function Octo_GetSection(key)
	for sec in string.gfind(Octo_ReadPayload(), "[^;]+") do
		local _, _, k, v = string.find(sec, "^(%a)=(.*)$")
		if k == key then
			return v
		end
	end
	return nil
end

local function Octo_SetSection(key, value)
	local out = {}
	local found = false
	for sec in string.gfind(Octo_ReadPayload(), "[^;]+") do
		local _, _, k = string.find(sec, "^(%a)=")
		if k == key then
			table.insert(out, key .. "=" .. value)
			found = true
		elseif k then
			table.insert(out, sec)
		end
	end
	if not found then
		table.insert(out, key .. "=" .. value)
	end
	Octo_WritePayload(table.concat(out, ";"))
end

-- ---------------------------------------------------------------- OctoDiag --
-- On-screen diagnostics (font strings render even where frames misbehave).
-- Shows load state and traps errors from widget creation so failures are
-- visible instead of silent. Remove once everything is confirmed working.
local OCTO_VERSION = "v6"
local diagStrings = {}
local diagLines = { "OctoGlue " .. OCTO_VERSION .. " loaded" }

local function Octo_DiagRender()
	local text = table.concat(diagLines, "\n")
	for _, fs in ipairs(diagStrings) do
		fs:SetText(text)
	end
end

local function Octo_Diag(msg)
	if diagLines[table.getn(diagLines)] == msg then
		return -- dedupe repeats (list updates fire often)
	end
	table.insert(diagLines, msg)
	Octo_DiagRender()
end

local function Octo_DiagAttach(parent, point, x, y)
	if parent then
		local fs = parent:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall")
		fs:SetPoint(point, parent, point, x, y)
		fs:SetTextColor(1, 0.9, 0.3)
		fs:SetJustifyH("LEFT")
		table.insert(diagStrings, fs)
		Octo_DiagRender()
	end
end

-- Safe call: run f, log any error to the diagnostics, return ok.
local function Octo_Try(label, f, a1, a2)
	if type(pcall) ~= "function" then
		f(a1, a2)
		return true
	end
	local ok, err = pcall(f, a1, a2)
	if not ok then
		Octo_Diag("ERR " .. label .. ": " .. tostring(err))
	end
	return ok
end

Octo_DiagAttach(AccountLoginUI or AccountLogin, "BOTTOM", 0, 45)
Octo_DiagAttach(CharacterSelectUI, "TOPLEFT", 16, -120)
Octo_Diag(type(CreateFrame) == "function" and "CreateFrame: present" or "CreateFrame: MISSING")

-- ------------------------------------------------------------ OctoReorder --

local function Reorder_Save()
	local names = {}
	for slot = 1, GetNumCharacters() do
		local name = GetCharacterInfo(ReorderPerm[slot] or slot)
		if name then
			table.insert(names, name)
		end
	end
	Octo_SetSection("O", table.concat(names, ","))
end

local function Reorder_Rebuild()
	local numChars = GetNumCharacters()
	ReorderPerm = {}
	local used = {}
	local saved = Octo_GetSection("O")
	if saved then
		for w in string.gfind(saved, "[^,]+") do
			for i = 1, numChars do
				if not used[i] and GetCharacterInfo(i) == w then
					used[i] = true
					table.insert(ReorderPerm, i)
					break
				end
			end
		end
	end
	for i = 1, numChars do
		if not used[i] then
			table.insert(ReorderPerm, i)
		end
	end
end

local function Reorder_DisplaySlot(serverIndex)
	for slot = 1, table.getn(ReorderPerm) do
		if ReorderPerm[slot] == serverIndex then
			return slot
		end
	end
	return serverIndex
end

local function Reorder_ServerIndex(displaySlot)
	return ReorderPerm[displaySlot] or displaySlot
end

local function Reorder_Move(slot, dir)
	local numChars = GetNumCharacters()
	local other = slot + dir
	if slot < 1 or slot > numChars or other < 1 or other > numChars then
		return
	end
	local t = ReorderPerm[slot]
	ReorderPerm[slot] = ReorderPerm[other]
	ReorderPerm[other] = t
	Reorder_Save()
	PlaySound("gsTitleOptionOK")
	UpdateCharacterList()
end

local reorderArrows = {}

local function Reorder_MakeArrow(slot, parent, dir, texBase, yOff)
	local name = "OctoReorder" .. (dir < 0 and "Up" or "Down") .. slot
	local b = CreateFrame("Button", name, parent)
	b:SetWidth(16)
	b:SetHeight(16)
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, yOff)
	b:SetNormalTexture(texBase .. "-Up")
	b:SetPushedTexture(texBase .. "-Down")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
	b:GetHighlightTexture():SetBlendMode("ADD")
	b:SetScript("OnClick", function()
		Reorder_Move(slot, dir)
	end)
	return b
end

local function Reorder_EnsureArrows(slot)
	if not reorderArrows[slot] then
		local parent = _G["CharSelectCharacterButton" .. slot]
		reorderArrows[slot] = {
			up = Reorder_MakeArrow(slot, parent, -1,
				"Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", -6),
			down = Reorder_MakeArrow(slot, parent, 1,
				"Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", -24),
		}
	end
	return reorderArrows[slot]
end

local function Reorder_UpdateArrows(numChars)
	for slot = 1, MAX_CHARACTERS_DISPLAYED do
		if slot <= numChars and numChars > 1 then
			local arrows = Reorder_EnsureArrows(slot)
			if slot > 1 then
				arrows.up:Show()
			else
				arrows.up:Hide()
			end
			if slot < numChars then
				arrows.down:Show()
			else
				arrows.down:Hide()
			end
		elseif reorderArrows[slot] then
			reorderArrows[slot].up:Hide()
			reorderArrows[slot].down:Hide()
		end
	end
end

-- --------------------------------------------------------------- OctoChal --
-- Bit i-1 of the stored mask = entry i below (the server's
-- RESPONSE_PLAYER_CHALLENGES bit order, i.e. Turtle_AvailableChallenges
-- extended by OctoChallengeTip). Names/texts are the stock glue strings,
-- already localized. Icons are 16px, up to 7 per row, second row stacking
-- above - fixed size, they never shrink.
local ROW_CHALLENGES = {
	{ icon = "Spell_Nature_TimeStop",              name = CHALLENGE_SLOW_AND_STEADY,  text = CHALLENGE_SLOW_AND_STEADY_TEXT },
	{ icon = "Spell_Nature_Sleep",                 name = CHALLENGE_EXHAUSTION,       text = CHALLENGE_EXHAUSTION_TEXT },
	{ icon = "Ability_DualWield",                  name = CHALLENGE_WAR_MODE,         text = CHALLENGE_WAR_MODE_TEXT },
	{ icon = "INV_Misc_Bone_HumanSkull_01",        name = CHALLENGE_HARDCORE,         text = CHALLENGE_HARDCORE_TEXT },
	{ icon = "Ability_Warrior_Disarm",             name = CHALLENGE_VAGRANT,          text = CHALLENGE_VAGRANT_TEXT },
	{ icon = "Spell_Magic_PolymorphPig",           name = CHALLENGE_BOARING,          text = CHALLENGE_BOARING_TEXT },
	{ icon = "INV_Pet_Mouse",                      name = CHALLENGE_LUNATIC,          text = CHALLENGE_LUNATIC_TEXT },
	{ icon = "Ability_Repair",                     name = CHALLENGE_CRAFTMASTER,      text = CHALLENGE_CRAFTMASTER_TEXT },
	{ icon = "INV_Cask_03",                        name = CHALLENGE_BREWMASTER,       text = CHALLENGE_BREWMASTER_TEXT },
	{ icon = "Ability_Warlock_DemonicEmpowerment", name = CHALLENGE_HEROIC,           text = CHALLENGE_HEROIC_TEXT },
	{ icon = "INV_Sword_41",                       name = CHALLENGE_SAMURAI,          text = CHALLENGE_SAMURAI_TEXT },
	{ icon = "Spell_Holy_PrayerofSpirit",          name = CHALLENGE_TOGETHER_FOREVER, text = CHALLENGE_TOGETHER_FOREVER_TEXT },
	{ icon = "Spell_Shadow_SoulGem",               name = CHALLENGE_TRUE_HARDCORE,    text = CHALLENGE_TRUE_HARDCORE_TEXT },
}

local rowChalIcons = {}

local function Chal_MaskForName(name)
	local c = Octo_GetSection("C")
	if not c or not name then
		return nil
	end
	local realm = GetServerName() or ""
	local fallback = nil
	for entry in string.gfind(c, "[^,]+") do
		local _, _, r, n, m = string.find(entry, "^(.*)/(.+):(%d+)$")
		if n == name then
			if r == realm then
				return tonumber(m)
			end
			if not fallback then
				fallback = tonumber(m)
			end
		end
	end
	return fallback
end

local function Chal_EnsureIcon(slot, j)
	rowChalIcons[slot] = rowChalIcons[slot] or {}
	local t = rowChalIcons[slot]
	if not t[j] then
		local parent = _G["CharSelectCharacterButton" .. slot]
		local b = CreateFrame("Button", "OctoChalIcon" .. slot .. "_" .. j, parent)
		b:SetWidth(16)
		b:SetHeight(16)
		local col = math.mod(j - 1, 7)
		local row = math.floor((j - 1) / 7)
		b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22 - col * 18, 6 + row * 18)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		b:GetHighlightTexture():SetBlendMode("ADD")
		b:SetScript("OnEnter", function()
			if ChallengesTooltip and ChallengesTooltip_Update and this.chalName then
				ChallengesTooltip:ClearAllPoints()
				ChallengesTooltip:SetPoint("TOPRIGHT", this, "TOPLEFT", -10, 0)
				ChallengesTooltip_Update(this.chalName, this.chalText or "")
				ChallengesTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function()
			if ChallengesTooltip then
				ChallengesTooltip:Hide()
			end
		end)
		t[j] = b
	end
	return t[j]
end

local function Chal_UpdateRow(slot, charName)
	local shown = 0
	local mask = Chal_MaskForName(charName)
	if mask and mask > 0 then
		local bit = 1
		for i = 1, table.getn(ROW_CHALLENGES) do
			if math.mod(mask, bit * 2) >= bit then
				shown = shown + 1
				local b = Chal_EnsureIcon(slot, shown)
				b:SetNormalTexture("Interface\\Icons\\" .. ROW_CHALLENGES[i].icon)
				b.chalName = ROW_CHALLENGES[i].name
				b.chalText = ROW_CHALLENGES[i].text
				b:Show()
			end
			bit = bit * 2
		end
	end
	if rowChalIcons[slot] then
		for j = shown + 1, table.getn(rowChalIcons[slot]) do
			rowChalIcons[slot][j]:Hide()
		end
	end
end

-- -------------------------------------------------------------- OctoSound --
-- Volume cvars (MusicVolume / SoundVolume / AmbienceVolume) are engine-
-- global, so changes here apply to the glue music immediately (or on the
-- next track) and carry into the world.
local soundPanel = nil
local soundSliders = {}

local SOUND_CVARS = {
	{ cvar = "MusicVolume",    label = "Music" },
	{ cvar = "SoundVolume",    label = "Effects" },
	{ cvar = "AmbienceVolume", label = "Ambience" },
}

local function OctoSound_Refresh()
	for _, s in ipairs(soundSliders) do
		local ok, v = pcall(GetCVar, s.cvar)
		v = ok and tonumber(v) or 1
		s.updating = true
		s.slider:SetValue(v)
		s.updating = false
		s.valueText:SetText(math.floor(v * 100 + 0.5) .. "%")
	end
end

local function OctoSound_MakeSlider(i, def)
	local slider = CreateFrame("Slider", "OctoSoundSlider" .. i, soundPanel)
	slider:SetWidth(160)
	slider:SetHeight(17)
	slider:SetPoint("TOPLEFT", soundPanel, "TOPLEFT", 30, -40 - (i - 1) * 42)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(0, 1)
	slider:SetValueStep(0.05)
	slider:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

	local label = soundPanel:CreateFontString(nil, "ARTWORK", "GlueFontNormalSmall")
	label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 3)
	label:SetText(def.label)

	local valueText = soundPanel:CreateFontString(nil, "ARTWORK", "GlueFontHighlightSmall")
	valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)

	local entry = { cvar = def.cvar, slider = slider, valueText = valueText }
	slider:SetScript("OnValueChanged", function()
		if entry.updating then
			return
		end
		local v = this:GetValue()
		pcall(SetCVar, entry.cvar, v)
		entry.valueText:SetText(math.floor(v * 100 + 0.5) .. "%")
	end)
	table.insert(soundSliders, entry)
end

local function OctoSound_EnsurePanel()
	if soundPanel then
		return soundPanel
	end
	soundPanel = CreateFrame("Frame", "OctoSoundPanel", GlueParent)
	soundPanel:SetWidth(260)
	soundPanel:SetHeight(210)
	soundPanel:SetPoint("CENTER", GlueParent, "CENTER", 0, 40)
	soundPanel:SetFrameStrata("DIALOG")
	soundPanel:EnableMouse(true)
	soundPanel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	soundPanel:Hide()

	local title = soundPanel:CreateFontString(nil, "ARTWORK", "GlueFontNormal")
	title:SetPoint("TOP", soundPanel, "TOP", 0, -18)
	title:SetText("Sound Settings")

	for i = 1, table.getn(SOUND_CVARS) do
		OctoSound_MakeSlider(i, SOUND_CVARS[i])
	end

	local okay = CreateFrame("Button", "OctoSoundOkay", soundPanel, "GlueDialogButtonTemplate")
	okay:SetPoint("BOTTOM", soundPanel, "BOTTOM", 0, 18)
	okay:SetText(OKAY or "Okay")
	okay:SetScript("OnClick", function()
		soundPanel:Hide()
	end)

	return soundPanel
end

function OctoSound_Toggle()
	local panel = OctoSound_EnsurePanel()
	if panel:IsShown() then
		panel:Hide()
	else
		OctoSound_Refresh()
		panel:Show()
	end
end

local function OctoSound_MakeOpenButton(name, parent, point, x, y)
	if _G[name] or not parent then
		return
	end
	local b = CreateFrame("Button", name, parent, "GlueButtonSmallTemplate")
	b:SetPoint(point, parent, point, x, y)
	b:SetText("Sound")
	b:SetScript("OnClick", function()
		OctoSound_Toggle()
	end)
end

-- Both screens already exist by the time this file loads (CreditsFrame.xml
-- comes after AccountLogin.xml and CharacterSelect.xml in GlueXML.toc).
-- NOTE: AccountLogin is a ModelFFX (the 3D background); interactive children
-- must be parented to its AccountLoginUI child or the model swallows them.
if Octo_CanPersist() then
	local ok1 = Octo_Try("sound-btn-login", function()
		OctoSound_MakeOpenButton("OctoSoundOpenLogin", AccountLoginUI or AccountLogin, "BOTTOMLEFT", 16, 45)
	end)
	local ok2 = Octo_Try("sound-btn-charsel", function()
		OctoSound_MakeOpenButton("OctoSoundOpenCharSelect", CharacterSelectUI, "BOTTOMLEFT", 16, 60)
	end)
	if ok1 and ok2 then
		Octo_Diag("sound buttons created")
	end
else
	Octo_Diag("persistence unavailable (no pcall/SetCVar)")
end

-- --------------------------- stock function redefinitions ------------------
-- Bodies are patch-4's originals with the marked additions; XML handlers
-- resolve these globals at event time, so redefining here takes effect for
-- every later event.

function CharacterSelect_OnKeyDown()
	if ( arg1 == "ESCAPE" ) then
		-- OctoSound: ESC closes the sound panel before it exits the screen.
		if ( OctoSoundPanel and OctoSoundPanel:IsShown() ) then
			OctoSoundPanel:Hide();
			return;
		end
		CharacterSelect_Exit();
	elseif ( arg1 == "ENTER" ) then
		CharacterSelect_EnterWorld();
	elseif ( arg1 == "PRINTSCREEN" ) then
		Screenshot();
	elseif ( arg1 == "UP" or arg1 == "LEFT" ) then
		-- OctoReorder: navigate in DISPLAY order, not server order.
		local numChars = GetNumCharacters();
		if ( numChars > 1 ) then
			local pos = Reorder_DisplaySlot(this.selectedIndex);
			if ( pos > 1 ) then
				pos = pos - 1;
			else
				pos = numChars;
			end
			CharacterSelect_SelectCharacter(Reorder_ServerIndex(pos));
		end
	elseif ( arg1 == "DOWN" or arg1 == "RIGHT" ) then
		-- OctoReorder: navigate in DISPLAY order, not server order.
		local numChars = GetNumCharacters();
		if ( numChars > 1 ) then
			local pos = Reorder_DisplaySlot(this.selectedIndex);
			if ( pos < numChars ) then
				pos = pos + 1;
			else
				pos = 1;
			end
			CharacterSelect_SelectCharacter(Reorder_ServerIndex(pos));
		end
	end
end

function UpdateCharacterSelection()
	for i=1, MAX_CHARACTERS_DISPLAYED, 1 do
		_G["CharSelectCharacterButton"..i]:UnlockHighlight();
	end

	-- OctoReorder: selectedIndex is a server index; highlight its display slot.
	local index = Reorder_DisplaySlot(CharacterSelect.selectedIndex);
	if ( (index > 0) and (index <= MAX_CHARACTERS_DISPLAYED) )then
		_G["CharSelectCharacterButton"..index]:LockHighlight();
	end
end

function UpdateCharacterList()
	local numChars = GetNumCharacters();
	local index = 1;

	Reorder_Rebuild(); -- OctoReorder

	for i=1, numChars, 1 do
		-- OctoReorder: row i shows the character at ReorderPerm[i].
		local name, race, class, level, zone, fileString, gender, ghost = GetCharacterInfo(Reorder_ServerIndex(i));

		local button = _G["CharSelectCharacterButton"..index];
		if ( not name ) then
			button:SetText("ERROR - Tell Jeremy");
		else
			if ( not zone ) then
				zone = "";
			end

			local classColor
			local classToken = TW_CLASS_TOKEN and TW_CLASS_TOKEN[class]
			if classToken and CLASS_COLORS[classToken] then
				classColor = CLASS_COLORS[classToken]
				class = classColor .. class .. "|r"
			end
			_G["CharSelectCharacterButton"..index.."ButtonTextName"]:SetText(name);
			if ( ghost ) then
				_G["CharSelectCharacterButton"..index.."ButtonTextInfo"]:SetText(format(CHARACTER_SELECT_INFO_GHOST, level, class));
			else
				_G["CharSelectCharacterButton"..index.."ButtonTextInfo"]:SetText(format(CHARACTER_SELECT_INFO, level, class));
			end
			_G["CharSelectCharacterButton"..index.."ButtonTextLocation"]:SetText(zone);
		end
		Octo_Try("chal-row", Chal_UpdateRow, index, name); -- OctoChal
		button:Show();

		index = index + 1;
		if ( index > MAX_CHARACTERS_DISPLAYED ) then
			break;
		end
	end

	if ( Octo_Try("arrows", Reorder_UpdateArrows, numChars) ) then
		Octo_Diag("list: " .. numChars .. " chars, arrows ok"); -- OctoReorder
	end

	if ( numChars == 0 ) then
		CharacterSelectDeleteButton:Disable();
		CharSelectEnterWorldButton:Disable();
	else
		CharacterSelectDeleteButton:Enable();
		CharSelectEnterWorldButton:Enable();
	end

	CharacterSelect.createIndex = 0;
	CharSelectCreateCharacterButton:Hide();

	local connected = IsConnectedToServer();
	for i=index, MAX_CHARACTERS_DISPLAYED, 1 do
		local button = _G["CharSelectCharacterButton"..index];
		if ( (CharacterSelect.createIndex == 0) and (numChars < MAX_CHARACTERS_PER_REALM) ) then
			CharacterSelect.createIndex = index;
			if ( connected ) then
				--If can create characters position and show the create button
				CharSelectCreateCharacterButton:SetID(index);
				CharSelectCreateCharacterButton:Show();
			end
		end
		button:Hide();
		index = index + 1;
	end

	if ( numChars == 0 ) then
		CharacterSelect.selectedIndex = 0;
		return;
	end

	if ( CharacterSelect.selectLast == 1 ) then
		CharacterSelect.selectLast = 0;
		CharacterSelect_SelectCharacter(numChars, 1);
		return;
	end

	if ( (CharacterSelect.selectedIndex == 0) or (CharacterSelect.selectedIndex > numChars) ) then
		CharacterSelect.selectedIndex = 1;
	end
	CharacterSelect_SelectCharacter(CharacterSelect.selectedIndex, 1);
end

function CharacterSelectButton_OnClick()
	-- OctoReorder: the button id is a display slot; map it to a server index.
	local id = Reorder_ServerIndex(this:GetID());
	if ( id ~= CharacterSelect.selectedIndex ) then
		CharacterSelect_SelectCharacter(id);
	end
end

function CharacterSelectButton_OnDoubleClick()
	-- OctoReorder: the button id is a display slot; map it to a server index.
	local id = Reorder_ServerIndex(this:GetID());
	if ( id ~= CharacterSelect.selectedIndex ) then
		CharacterSelect_SelectCharacter(id);
	end
	CharacterSelect_EnterWorld();
end

-- ------------------------------------------------------------- OctoStatus --
-- "Server down?" banner on the login screen. Glue Lua has no network API,
-- so this is observational: when the client's own login attempt fails with a
-- connection-class error (not a bad password), latch a red banner; reaching
-- character select clears it. GlueDialog_Show is plain Lua (GlueDialog.lua,
-- loaded before this file), so wrapping it is safe.
local statusBanner = nil
local probing = false

local DOWN_MESSAGES = {}
for _, s in ipairs({ LOGIN_FAILED, LOGIN_SERVER_DOWN, SERVER_DOWN,
		DISCONNECTED, RESPONSE_DISCONNECTED, CHAR_LOGIN_FAILED }) do
	DOWN_MESSAGES[s] = true
end

-- Any of these means the AUTH SERVER ANSWERED (about our throwaway probe
-- account or a real one) - i.e. the server is reachable and up.
local UP_MESSAGES = {}
for _, s in ipairs({ LOGIN_UNKNOWN_ACCOUNT, LOGIN_INCORRECT_PASSWORD,
		LOGIN_BANNED, LOGIN_SUSPENDED, LOGIN_ALREADYONLINE, LOGIN_DBBUSY,
		LOGIN_BADVERSION, LOGIN_NOTIME }) do
	UP_MESSAGES[s] = true
end

local function Status_Parent()
	return AccountLoginUI or AccountLogin
end

local function Status_EnsureBanner()
	if not statusBanner then
		statusBanner = Status_Parent():CreateFontString("OctoStatusBanner", "OVERLAY", "GlueFontNormalLarge")
		statusBanner:SetPoint("TOP", Status_Parent(), "TOP", 0, -90)
		statusBanner:Hide()
	end
	return statusBanner
end

local function Status_MarkDown()
	local b = Status_EnsureBanner()
	b:SetTextColor(1, 0.15, 0.15)
	b:SetText("OctoWoW appears to be DOWN\n(last connection attempt failed)")
	b:Show()
end

local function Status_MarkUp(announce)
	if announce then
		local b = Status_EnsureBanner()
		b:SetTextColor(0.1, 1, 0.1)
		b:SetText("OctoWoW is UP\n(the server answered)")
		b:Show()
	elseif statusBanner then
		statusBanner:Hide()
	end
end

-- "Check Server" probe: connect with a throwaway account. A connection
-- failure means down; an auth-level rejection ("information not valid",
-- banned, etc.) means the server answered, so it is up. While probing, the
-- final result dialog is converted into the banner instead of being shown.
function OctoStatus_Probe()
	probing = true
	DefaultServerLogin("octoprobe", "probe")
end

local Octo_OrigGlueDialog_Show = GlueDialog_Show
function GlueDialog_Show(which, text, data)
	if text and DOWN_MESSAGES[text] then
		Status_MarkDown()
		if probing then
			probing = false
			if GlueDialog then GlueDialog:Hide() end
			return
		end
	elseif text and UP_MESSAGES[text] then
		if probing then
			probing = false
			Status_MarkUp(true)
			if GlueDialog then GlueDialog:Hide() end
			return
		end
	end
	return Octo_OrigGlueDialog_Show(which, text, data)
end

-- A real login click ends any dangling probe state (e.g. after the user
-- cancelled a probe's Connecting dialog).
if type(AccountLogin_Login) == "function" then
	local Octo_OrigAccountLogin_Login = AccountLogin_Login
	function AccountLogin_Login()
		probing = false
		return Octo_OrigAccountLogin_Login()
	end
end

local Octo_OrigCharacterSelect_OnShow = CharacterSelect_OnShow
function CharacterSelect_OnShow()
	probing = false
	Status_MarkUp() -- we connected, so the server is up; clear the banner
	return Octo_OrigCharacterSelect_OnShow()
end

Octo_Try("check-btn", function()
	local parent = Status_Parent()
	if parent and not _G["OctoStatusCheckButton"] then
		local b = CreateFrame("Button", "OctoStatusCheckButton", parent, "GlueButtonSmallTemplate")
		b:SetPoint("TOP", parent, "TOP", 0, -130)
		b:SetText("Check Server")
		b:SetScript("OnClick", function()
			OctoStatus_Probe()
		end)
	end
end)
Octo_Diag("status section loaded")

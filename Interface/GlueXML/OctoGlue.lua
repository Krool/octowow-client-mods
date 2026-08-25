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
-- GLUE VM FACTS (established by on-screen diagnostics, 2026-08-23):
--   * CreateFrame and pcall exist; SetCVar/GetCVar DO NOT.
--   * Buttons built purely in Lua do not render; template-inherited ones do
--     (the templates live in our CreditsFrame.xml).
--   * The only persistent, glue-writable storage is the saved account name
--     (Get/SetSavedAccountName -> Config.wtf). "#" is illegal in account
--     names, so the character order is stored as a "#O=..." suffix there and
--     stripped before the login box is filled.
--   * No VOLUME APIs exist in glue (no SetCVar), but the MUSIC transport
--     does: PlayGlueMusic/StopGlueMusic are called by the stock
--     GlueParent.lua, so a music on/off toggle is possible - that is what
--     OctoMusic is. Effects volume would still need a DLL.
--   * The row highlight texture is anchored 20px LEFT of its button
--     (TOPLEFT -20, size 256 vs the button's own 256): the button's true
--     right edge sits 20px PAST the visible plate. Anything right-anchored
--     to a row must budget that extra 20 or it draws on/over the border.
--
-- Features:
--   * OctoReorder - per-row up/down arrows to rearrange the character list;
--     order persists via the saved-account-name suffix.
--   * OctoChal    - per-row challenge icons. Data is BAKED at build time
--     from CustomData\octoglue-challenges (written live in-world by the
--     OctoChallenges addon via nampower's WriteCustomFile, or mirrored from
--     SavedVariables by the realm-status scheduled task), falling back to
--     the static OCTO_BAKED_CHALLENGES table in OctoGlueData.lua.
--   * OctoStatus  - dialog-free ~1s server probe, shown as a green/yellow/
--     red lamp top-right of the login screen; details in its hover tooltip,
--     click to re-check. Auto-run once at the login screen.
--   * OctoMusic   - "Music: On/Off" toggle (login screen + char select);
--     shadows PlayGlueMusic so the choice sticks across glue screens, and
--     persists as a "#M=0" token in the saved-account-name suffix.

-- (No version constant: versions live in git tags/releases. The old
-- OCTO_VERSION needed a manual bump every change and nothing has rendered
-- it since the v24 tag removal.)

-- Run f protected so one broken feature cannot take the whole glue screen
-- with it. Failures are silent now that the on-screen diagnostics are gone
-- (v6-v13); if something regresses, restore OctoDiag from the v13 commit.
local function Octo_Try(label, f, a1, a2)
	if type(pcall) ~= "function" then
		f(a1, a2)
		return true
	end
	local ok = pcall(f, a1, a2)
	return ok
end

local HAS_SAVEDNAME = type(GetSavedAccountName) == "function"
	and type(SetSavedAccountName) == "function"

-- One of the injected DLLs (see Logs\nampower_debug.log: "Registering
-- WriteCustomFile/ReadCustomFile...") adds file APIs to the Lua VMs. If they
-- exist here in glue they are CRASH-PROOF storage: the account-name cvar only
-- reaches Config.wtf on a clean client flush, so a crash on logout/exit (which
-- this install hits regularly) silently loses a reorder saved that session.
-- The file is written the moment the order changes. The cvar suffix stays as
-- the fallback (and keeps working when the DLL is absent).
local SUFFIX_FILE = "octoglue-settings"

local function Suffix_ReadFile()
	if type(ReadCustomFile) ~= "function" or type(pcall) ~= "function" then
		return nil
	end
	local ok, s = pcall(ReadCustomFile, SUFFIX_FILE)
	if ok and type(s) == "string" and string.find(s, "#", 1, true) then
		return s
	end
	return nil
end

local function Suffix_WriteFile(s)
	if type(WriteCustomFile) == "function" and type(pcall) == "function" then
		pcall(WriteCustomFile, SUFFIX_FILE, s)
	end
end

-- ------------------------------------------------------ suffix persistence --
-- Everything we persist lives after a "#" in the saved account name, as
-- "#"-separated tokens:
--   "Krool#O=Speakno,Kaboom,...#M=0"
-- "#O=" is the character order, "#M=0" means music off. AccountLogin_OnShow
-- (wrapped below) strips the whole suffix before the login box shows it;
-- AccountLogin_Login re-appends it after the stock save runs.
local memoryOrder = nil -- session fallback when SavedAccountName is missing
local musicOff = false  -- OctoMusic state; loaded from the suffix below

-- GetServerName() pads with trailing whitespace on this client.
local function Octo_Realm()
	local r = GetServerName() or ""
	return string.gsub(r, "^%s*(.-)%s*$", "%1")
end

local function Order_SplitSaved()
	if not HAS_SAVEDNAME then
		return "", nil
	end
	local s = GetSavedAccountName() or ""
	local i = string.find(s, "#", 1, true)
	if i then
		return string.sub(s, 1, i - 1), string.sub(s, i)
	end
	return s, nil
end

-- The current suffix: the DLL file wins (survives crashes and the stock
-- login's SetSavedAccountName("") clear), the cvar suffix is the fallback.
local function Suffix_Get()
	local s = Suffix_ReadFile()
	if s then
		return s
	end
	local _, suffix = Order_SplitSaved()
	return suffix
end

local function Order_GetCSV()
	local suffix = Suffix_Get()
	if suffix then
		-- [^#]* so a following token ("#M=0") cannot leak into the last name.
		local _, _, csv = string.find(suffix, "#O=([^#]*)")
		if csv and csv ~= "" then
			return csv
		end
	end
	return memoryOrder
end

-- Rewrite the whole suffix from current state. An order saved by an earlier
-- session survives a music toggle (and vice versa) because each half falls
-- back to what is already saved when this session never touched it.
local function Suffix_Save()
	local csv = memoryOrder or Order_GetCSV() -- memory first: it is the newer write
	local suffix = ""
	if csv and csv ~= "" then
		suffix = suffix .. "#O=" .. csv
	end
	if musicOff then
		suffix = suffix .. "#M=0"
	end
	Suffix_WriteFile(suffix) -- lands on disk NOW, crash or no crash
	if not HAS_SAVEDNAME then
		return
	end
	local base = Order_SplitSaved()
	if base == "" and AccountLoginAccountEdit and AccountLoginAccountEdit.GetText then
		base = AccountLoginAccountEdit:GetText() or ""
	end
	SetSavedAccountName(base .. suffix)
end

local function Order_SetCSV(csv)
	memoryOrder = csv
	Suffix_Save()
end

-- Load the music flag once at startup.
do
	local suffix = Suffix_Get()
	if suffix and string.find(suffix, "#M=0", 1, true) then
		musicOff = true
	end
end

-- ------------------------------------------------------------ OctoReorder --
-- Renders a display permutation (the server's char-enum order is immutable
-- client-side): ReorderPerm[displaySlot] = server character index.
-- CharacterSelect.selectedIndex stays a SERVER index everywhere (rename,
-- delete, EnterWorld and the selection events keep working untouched); only
-- rendering, row clicks and keyboard navigation translate through the
-- permutation. The create-button path is unaffected: its id is always >
-- numChars, and Reorder_ServerIndex falls back to the input for unmapped
-- ids. The order is saved as names and re-matched by name on every list
-- update, so it survives creates, deletes and renames (unknown names append
-- in server order).
local ReorderPerm = {}

-- Order entries are realm-qualified ("N'Zoth/Kaboom") since v17: with bare
-- names, the realms shared ONE order - reordering on realm B overwrote
-- realm A's saved order (nothing matched, so the rebuild fell back to
-- server order and the next save clobbered the CSV). Legacy unqualified
-- entries are read as belonging to the current realm and re-qualified on
-- the next save. "/", "," and "#" cannot appear in character names.
local function Reorder_Save()
	local realm = Octo_Realm()
	local names = {}
	-- Preserve the other realms' saved entries untouched.
	local old = Order_GetCSV()
	if old then
		for w in string.gfind(old, "[^,]+") do
			local _, _, r = string.find(w, "^(.*)/")
			if r and r ~= realm then
				table.insert(names, w)
			end
		end
	end
	for slot = 1, GetNumCharacters() do
		local name = GetCharacterInfo(ReorderPerm[slot] or slot)
		if name then
			table.insert(names, realm .. "/" .. name)
		end
	end
	Order_SetCSV(table.concat(names, ","))
end

local function Reorder_Rebuild()
	local numChars = GetNumCharacters()
	ReorderPerm = {}
	local used = {}
	local saved = Order_GetCSV()
	if saved then
		local realm = Octo_Realm()
		for w in string.gfind(saved, "[^,]+") do
			-- "realm/name"; a legacy bare name counts as the current realm.
			local _, _, r, n = string.find(w, "^(.*)/(.*)$")
			if not r then
				r, n = realm, w
			end
			if r == realm then
				for i = 1, numChars do
					if not used[i] and GetCharacterInfo(i) == n then
						used[i] = true
						table.insert(ReorderPerm, i)
						break
					end
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

-- Arrows idle dimmed and light up under the mouse, so busy rows (arrows +
-- challenge icons) stay quiet until you reach for them. Alpha, not
-- Hide/Show: a hidden frame cannot be hovered, and the row button's own
-- OnLeave fires the moment the mouse crosses onto a child, so hiding would
-- make the arrows unclickable. SetAlpha in glue is unverified - degrade to
-- always-bright if it is missing.
local ARROW_IDLE_ALPHA = 0.35

local function Arrow_SetAlpha(b, a)
	if b and b.SetAlpha and type(pcall) == "function" then
		pcall(b.SetAlpha, b, a)
	end
end

local function Arrow_SetRowAlpha(slot, a)
	local arrows = reorderArrows[slot]
	if arrows then
		Arrow_SetAlpha(arrows.up, a)
		Arrow_SetAlpha(arrows.down, a)
	end
end

-- A row's arrows are lit when the mouse is on them OR the row holds the
-- selected character (v20) - the row you are most likely to move.
local function Arrow_IsLit(slot)
	local arrows = reorderArrows[slot]
	if arrows and arrows.hover then
		return true
	end
	return CharacterSelect
		and Reorder_DisplaySlot(CharacterSelect.selectedIndex or 0) == slot
end

local function Arrow_Refresh(slot)
	Arrow_SetRowAlpha(slot, Arrow_IsLit(slot) and 1.0 or ARROW_IDLE_ALPHA)
end

local function Arrow_RefreshAll()
	for slot = 1, MAX_CHARACTERS_DISPLAYED do
		if reorderArrows[slot] then
			Arrow_Refresh(slot)
		end
	end
end

local function Reorder_MakeArrow(slot, parent, dir, yOff)
	local name = "OctoReorder" .. (dir < 0 and "Up" or "Down") .. slot
	-- The stock glue scrollbar button templates provably render at this
	-- screen (every glue scroll frame uses them).
	local template = dir < 0 and "GlueScrollUpButtonTemplate" or "GlueScrollDownButtonTemplate"
	local b = CreateFrame("Button", name, parent, template)
	b:SetWidth(18)
	b:SetHeight(18)
	-- The visible row plate ends 20px LEFT of the button's true right edge
	-- (highlight texture anchored at -20 - see the header). -23 = 3px inside
	-- the plate; the old -3 parked the arrows out on the panel border art.
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -23, yOff)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)
	b:SetScript("OnClick", function()
		Reorder_Move(slot, dir)
	end)
	b:SetScript("OnEnter", function()
		local arrows = reorderArrows[slot]
		if arrows then
			arrows.hover = true
		end
		Arrow_SetRowAlpha(slot, 1.0)
	end)
	b:SetScript("OnLeave", function()
		local arrows = reorderArrows[slot]
		if arrows then
			arrows.hover = nil
		end
		Arrow_Refresh(slot) -- stays lit if this row is the selected character
	end)
	-- NOTE: no point setting the idle alpha here - something in the glue
	-- template plumbing resets it before first display (observed in v18:
	-- arrows started full-bright until first hover). It is re-asserted on
	-- every Reorder_UpdateArrows instead.
	return b
end

local function Reorder_EnsureArrows(slot)
	if not reorderArrows[slot] then
		local parent = _G["CharSelectCharacterButton" .. slot]
		reorderArrows[slot] = {
			up = Reorder_MakeArrow(slot, parent, -1, -6),
			down = Reorder_MakeArrow(slot, parent, 1, -24),
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
			-- Re-assert the alpha on every list update: the initial
			-- SetAlpha at creation does not survive to first display (glue
			-- template quirk), and this also restores it after Show().
			-- Hovered and selected rows stay bright.
			Arrow_Refresh(slot)
		elseif reorderArrows[slot] then
			reorderArrows[slot].up:Hide()
			reorderArrows[slot].down:Hide()
		end
	end
end

-- --------------------------------------------------------------- OctoChal --
-- Bit i-1 of the baked mask = entry i below (the server's
-- RESPONSE_PLAYER_CHALLENGES bit order, i.e. Turtle_AvailableChallenges
-- extended by OctoChallengeTip). Names/texts are the stock glue strings.
-- Icons are 16px, up to 5 per row, further rows stacking above - fixed
-- size. 5, not 7: at 7 the row overlapped the character name/level text
-- (owner, 2026-08-23).
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

-- Live masks from CustomData\octoglue-challenges ("v1|Realm/Name=mask,...").
-- The in-world addon writes it the moment the server answers (v25 - no more
-- rebuild step), and the realm-status scheduled task mirrors SavedVariables
-- into it for installs whose world VM lacks WriteCustomFile. Re-read on
-- every CharacterSelect_OnShow; the baked table is the fallback so a shared
-- prebuilt MPQ (empty bake) still works everywhere.
local CHAL_FILE = "octoglue-challenges"
local liveChal = nil

local function Chal_LoadLive()
	liveChal = nil
	if type(ReadCustomFile) ~= "function" then
		return
	end
	local ok, s = pcall(ReadCustomFile, CHAL_FILE)
	if not ok or type(s) ~= "string" then
		return
	end
	local t = {}
	for k, v in string.gfind(s, "([^=,|]+)=(%d+)") do
		t[k] = tonumber(v)
	end
	liveChal = t
end

local function Chal_MaskForName(name)
	if not name then
		return nil
	end
	local realm = Octo_Realm()
	if liveChal then
		local m = liveChal[realm .. "/" .. name] or liveChal[name]
		if m then
			return m
		end
	end
	if type(OCTO_BAKED_CHALLENGES) ~= "table" then
		return nil
	end
	return OCTO_BAKED_CHALLENGES[realm .. "/" .. name] or OCTO_BAKED_CHALLENGES[name]
end

local function Chal_EnsureIcon(slot, j)
	rowChalIcons[slot] = rowChalIcons[slot] or {}
	local t = rowChalIcons[slot]
	if not t[j] then
		local parent = _G["CharSelectCharacterButton" .. slot]
		local b = CreateFrame("Button", "OctoChalIcon" .. slot .. "_" .. j, parent, "OctoChalIconTemplate")
		local col = math.mod(j - 1, 5)
		local row = math.floor((j - 1) / 5)
		-- The bottom 15px of each 70px row is hit-rect inset (dead art zone),
		-- so sit above it or the icons look like they belong to the next row.
		-- -44, not -24: the visible plate ends 20px left of the button's true
		-- right edge (highlight texture at -20 - see the header), so at -24
		-- the first icon straddled the row border - "the run off with 5".
		-- 20px pitch (v19): the gold quickslot rings extend 6px past each
		-- 16px icon and need the extra breathing room 18px did not give.
		b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -44 - col * 20, 20 + row * 20)
		b:SetFrameLevel(parent:GetFrameLevel() + 2)
		-- Closures over the button rather than `this` (glue handler
		-- convention for `this` in SetScript'd closures is unverified).
		b:SetScript("OnEnter", function()
			if ChallengesTooltip and ChallengesTooltip_Update and b.chalName then
				ChallengesTooltip:ClearAllPoints()
				ChallengesTooltip:SetPoint("TOPRIGHT", b, "TOPLEFT", -10, 0)
				ChallengesTooltip_Update(b.chalName, b.chalText or "")
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

-- Selected-character challenge panel on the LEFT side of the screen:
-- larger icons under a "Challenges" header, refreshed on every selection
-- change.
local selHeader = nil
local selIcons = {}

local function Sel_EnsureHeader()
	if not selHeader and CharacterSelectUI then
		selHeader = CharacterSelectUI:CreateFontString(nil, "OVERLAY", "GlueFontNormalLarge")
		selHeader:SetPoint("TOPLEFT", CharacterSelectUI, "TOPLEFT", 26, -170)
		selHeader:SetText(CHALLENGES or "Challenges")
		selHeader:Hide()
	end
	return selHeader
end

local function Sel_EnsureIcon(j)
	if not selIcons[j] then
		local b = CreateFrame("Button", "OctoSelChal" .. j, CharacterSelectUI, "OctoChalIconTemplate")
		b:SetWidth(32)
		b:SetHeight(32)
		local col = math.mod(j - 1, 4)
		local row = math.floor((j - 1) / 4)
		-- 40px pitch (v19): room for the quickslot rings around 32px icons.
		b:SetPoint("TOPLEFT", CharacterSelectUI, "TOPLEFT", 26 + col * 40, -196 - row * 40)
		b:SetScript("OnEnter", function()
			if ChallengesTooltip and ChallengesTooltip_Update and b.chalName then
				ChallengesTooltip:ClearAllPoints()
				ChallengesTooltip:SetPoint("TOPLEFT", b, "TOPRIGHT", 10, 0)
				ChallengesTooltip_Update(b.chalName, b.chalText or "")
				ChallengesTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function()
			if ChallengesTooltip then
				ChallengesTooltip:Hide()
			end
		end)
		selIcons[j] = b
	end
	return selIcons[j]
end

local function Sel_Update()
	local shown = 0
	-- selectedIndex is 0 with an empty character list; don't feed that to
	-- GetCharacterInfo.
	local idx = CharacterSelect and CharacterSelect.selectedIndex
	local name = nil
	if idx and idx >= 1 then
		name = GetCharacterInfo(idx)
	end
	local mask = Chal_MaskForName(name)
	if mask and mask > 0 then
		local bit = 1
		for i = 1, table.getn(ROW_CHALLENGES) do
			if math.mod(mask, bit * 2) >= bit then
				shown = shown + 1
				local b = Sel_EnsureIcon(shown)
				b:SetNormalTexture("Interface\\Icons\\" .. ROW_CHALLENGES[i].icon)
				b.chalName = ROW_CHALLENGES[i].name
				b.chalText = ROW_CHALLENGES[i].text
				b:Show()
			end
			bit = bit * 2
		end
	end
	local h = Sel_EnsureHeader()
	if h then
		if shown > 0 then
			h:Show()
		else
			h:Hide()
		end
	end
	for j = shown + 1, table.getn(selIcons) do
		selIcons[j]:Hide()
	end
end

-- --------------------------- stock function redefinitions ------------------
-- Bodies are patch-4's originals with the marked additions; XML handlers
-- resolve these globals at event time, so redefining here takes effect for
-- every later event.

function CharacterSelect_OnKeyDown()
	if ( arg1 == "ESCAPE" ) then
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

	Octo_Try("sel-chal", Sel_Update); -- OctoChal: left-side panel
	Octo_Try("sel-arrows", Arrow_RefreshAll); -- OctoReorder: light the selected row's arrows
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

	Octo_Try("arrows", Reorder_UpdateArrows, numChars); -- OctoReorder

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
-- Quick "ping": connect with a throwaway account, judge by what comes back
-- and how fast. A connection failure or silence past the timeout means down;
-- an auth-level rejection means the server answered, so it is up. ALL
-- dialogs are swallowed while probing. Shown as a single 16px status lamp
-- top-right (green/yellow/red); details live in its hover tooltip and a
-- click re-runs the probe (the old text banner + Check Server button were
-- dropped as too garish - owner, v27).
local probing = false

-- Build the sets from GLOBAL NAMES, not values: with values, one nil global
-- in a {list} constructor makes ipairs stop early and silently drops every
-- entry after it (v17 - latent since v12).
local function Octo_StringSet(names)
	local t = {}
	for i = 1, table.getn(names) do
		local s = _G[names[i]]
		if type(s) == "string" then
			t[s] = true
		end
	end
	return t
end

local DOWN_MESSAGES = Octo_StringSet({ "LOGIN_FAILED", "LOGIN_SERVER_DOWN",
	"SERVER_DOWN", "DISCONNECTED", "RESPONSE_DISCONNECTED", "CHAR_LOGIN_FAILED" })

local UP_MESSAGES = Octo_StringSet({ "LOGIN_UNKNOWN_ACCOUNT",
	"LOGIN_INCORRECT_PASSWORD", "LOGIN_BANNED", "LOGIN_SUSPENDED",
	"LOGIN_ALREADYONLINE", "LOGIN_DBBUSY", "LOGIN_BADVERSION", "LOGIN_NOTIME" })

-- Auth PROGRESS states that require actual SERVER BYTES. Any of these means
-- the server answered - even if the bogus probe account then takes ages to be
-- rejected (auth cores rate-limit failed logins) or the final rejection
-- string is one we do not know. This is what stopped the false DOWNs: v12
-- judged only the FINAL dialog, so a slow rejection ran into the 5s hard mark
-- and the banner said DOWN while a real login worked fine. "Connecting" is
-- deliberately NOT in the list - it shows while the connect is still in
-- flight - and neither is "Handshaking" (v22): the client shows it the
-- instant the TCP socket OPENS, before the server has sent anything, so a
-- half-dead host (or a proxy front) that accepts connections with the auth
-- daemon dead behind it read UP. "Authenticating" is the first state that
-- only occurs after the server's challenge response, and it follows within
-- milliseconds on a live server, so nothing is lost. These arrive via
-- UPDATE_STATUS_DIALOG (which never reaches GlueDialog_Show), so the probe
-- frame listens for the event itself.
local ANSWER_MESSAGES = Octo_StringSet({
	"LOGIN_STATE_AUTHENTICATING", "LOGIN_STATE_CHECKINGVERSIONS",
	"LOGIN_STATE_AUTHENTICATED", "LOGIN_STATE_DOWNLOADFILE",
	"LOGIN_STATE_SURVEY" })

local function Status_Parent()
	return AccountLoginUI or AccountLogin
end

-- The lamp: a template-inherited button (Lua-only buttons never render in
-- this glue VM) whose fill texture is tinted by verdict. Tooltip reuses the
-- stock ChallengesTooltip like the challenge icons do.
local statusDot = nil
local dotTitle = ""
local dotBody = ""
local dotTipOpen = false

local function Dot_RefreshTooltip()
	if dotTipOpen and ChallengesTooltip and ChallengesTooltip_Update then
		ChallengesTooltip_Update(dotTitle, dotBody)
	end
end

local function Status_EnsureDot()
	if not statusDot then
		local parent = Status_Parent()
		statusDot = CreateFrame("Button", "OctoStatusDot", parent, "OctoStatusDotTemplate")
		statusDot:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -24, -24)
		statusDot:SetFrameLevel(parent:GetFrameLevel() + 2)
		statusDot.fill = _G["OctoStatusDotFill"]
		statusDot:SetScript("OnEnter", function()
			if ChallengesTooltip and ChallengesTooltip_Update then
				dotTipOpen = true
				ChallengesTooltip:ClearAllPoints()
				ChallengesTooltip:SetPoint("TOPRIGHT", statusDot, "BOTTOMLEFT", -4, -4)
				ChallengesTooltip_Update(dotTitle, dotBody)
				ChallengesTooltip:Show()
			end
		end)
		statusDot:SetScript("OnLeave", function()
			dotTipOpen = false
			if ChallengesTooltip then
				ChallengesTooltip:Hide()
			end
		end)
		statusDot:SetScript("OnClick", function()
			OctoStatus_Probe()
		end)
	end
	return statusDot
end

-- ---- realm (world server) status, v23 ----
-- The probe can only ever test the LOGIN server: its throwaway account is
-- rejected at auth and never sees the realm list, and the glue VM has no
-- other network primitive. 2026-08-24 outage: auth answered while all three
-- realms were offline, so the banner said UP with nothing playable. The
-- realm status therefore comes from OUTSIDE: a scheduled task
-- (tools\realm-status.ps1, every 2 min) scrapes octowow.st into
-- CustomData\octoglue-realmstatus and the DLL ReadCustomFile API carries it
-- in here. Glue has no clock, so freshness is shown as the poller's own
-- HH:mm stamp rather than computed. Format: v1|HH:mm|on/total|Name=UP,...
local REALM_FILE = "octoglue-realmstatus"

local function Realms_Read()
	if type(ReadCustomFile) ~= "function" then
		return nil
	end
	local ok, s = pcall(ReadCustomFile, REALM_FILE)
	if not ok or type(s) ~= "string" then
		return nil
	end
	s = string.gsub(s, "%s+$", "")
	local _, _, when, counts, detail = string.find(s, "^v1|([^|]*)|([^|]*)|(.*)$")
	if not when then
		return nil
	end
	local r = { when = when, detail = detail }
	local _, _, on, total = string.find(counts, "^(%d+)/(%d+)$")
	if on then
		r.online = tonumber(on)
		r.total = tonumber(total)
	end
	return r
end

-- One tooltip line per realm plus a summary state: "up" (all), "partial",
-- "down" (none), or "unknown" (no feed / failed fetch).
local function Realms_Describe(r)
	if not r then
		return "Realms: no data (helper task not running)", "unknown"
	end
	if not r.online then
		return "Realms: web check failed (" .. (r.when or "?") .. ")", "unknown"
	end
	local body = "Realms (web " .. (r.when or "?") .. "):"
	if r.detail then
		for name, st in string.gfind(r.detail, "([^=,|]+)=([A-Z]+)") do
			if st == "UP" then
				body = body .. "\n" .. name .. ": up"
			else
				body = body .. "\n" .. name .. ": DOWN"
			end
		end
	end
	local state = "up"
	if r.online == 0 then
		state = "down"
	elseif r.online < r.total then
		state = "partial"
	end
	return body, state
end

-- The single verdict paint. The probe only proves the LOGIN server answers;
-- the realm feed can veto its green (the 2026-08-24 outage: auth answered
-- while every realm was offline). Colors: green = login up and no realm
-- known down; yellow = still checking, or partial realm outage; red = login
-- down, or every realm down. Unknown realm data leans green (pre-v23
-- behavior) with the tooltip saying so.
local function Status_Paint(loginState, detail)
	local d = Status_EnsureDot()
	d:Show()
	local rline, rstate = Realms_Describe(Realms_Read())
	local login, color
	if loginState == "checking" then
		dotTitle = "OctoWoW: checking..."
		login = "Login server: probing..."
		color = "yellow"
	elseif loginState == "slow" then
		dotTitle = "OctoWoW: no answer yet..."
		login = "Login server: still waiting for an answer"
		color = "yellow"
	elseif loginState == "down" then
		dotTitle = "OctoWoW is DOWN"
		login = "Login server: DOWN (" .. (detail or "no answer within 5s") .. ")"
		color = "red"
	else -- "up"; detail = answer latency in seconds (may be nil)
		login = "Login server: up"
		if detail then
			login = login .. string.format(" (answered in %.1fs)", detail)
		end
		if rstate == "down" then
			dotTitle = "OctoWoW realms are DOWN"
			color = "red"
		elseif rstate == "partial" then
			dotTitle = "OctoWoW: partial outage"
			color = "yellow"
		else
			dotTitle = "OctoWoW is UP"
			color = "green"
		end
	end
	if color == "red" then
		if d.fill then d.fill:SetVertexColor(1, 0.15, 0.15) end
	elseif color == "yellow" then
		if d.fill then d.fill:SetVertexColor(1, 0.82, 0) end
	else
		if d.fill then d.fill:SetVertexColor(0.1, 1, 0.1) end
	end
	dotBody = login .. "\n" .. rline .. "\n\nClick to re-check."
	Dot_RefreshTooltip()
end

-- The probe machinery below is verdict-logic only; it talks to the UI
-- through these four marks (kept from the banner era so it never changed).
local function Status_MarkChecking()
	Status_Paint("checking")
end

local function Status_MarkSlow()
	Status_Paint("slow")
end

local function Status_MarkDown(reason)
	Status_Paint("down", reason)
end

local function Status_MarkUp(announce, secs)
	if announce then
		Status_Paint("up", secs)
	elseif statusDot then
		statusDot:Hide()
	end
end

-- Two-stage verdict: a full auth handshake takes several round-trips, so a
-- short timeout that ABORTS causes false DOWNs. At the soft mark the banner
-- turns cautionary but the attempt keeps running; only the hard mark
-- declares DOWN and aborts. A late auth answer flips the banner to UP.
-- After the hard abort, `probing` intentionally stays set so late dialogs
-- from the aborted attempt are still swallowed (a real Login click or a
-- verdict clears it).
local PROBE_SOFT = 1.2
local PROBE_HARD = 5.0
-- v21: DISCONNECTED is NEVER accepted as a probe verdict. v17 tried a
-- 0.75s grace window, but the old session's realm-socket teardown can fire
-- DISCONNECTED seconds later - well past any grace and past the 2s probe
-- delay - and kept flipping the banner DOWN on every Back-from-char-select.
-- A genuinely refused connect says LOGIN_FAILED, and a server that dies
-- mid-handshake just goes silent into the 5s hard mark, so nothing real is
-- lost by ignoring disconnect texts entirely while probing.
-- After the hard-mark verdict, keep swallowing the aborted attempt's
-- dialogs only this much longer; then stop even if no terminal dialog ever
-- arrives (v17: DisconnectFromServer on a never-connected probe can be a
-- silent no-op, which used to leave `probing` stuck swallowing forever).
local PROBE_SETTLE_WINDOW = 2.0
local probeAnswered = false -- saw an auth-progress state this probe
local probeAnsweredAt = nil -- seconds into the probe the first answer came
local probeSettled = false  -- hard mark already showed the verdict; swallow
                            -- the aborted attempt's fallout WITHOUT re-marking

local probeTimer = CreateFrame("Frame")
probeTimer.elapsed = 0
probeTimer.softShown = false
probeTimer:Hide()
probeTimer:SetScript("OnUpdate", function()
	if not probing then
		probeTimer:Hide()
		return
	end
	probeTimer.elapsed = probeTimer.elapsed + (arg1 or 0.02)
	if not probeTimer.softShown and probeTimer.elapsed >= PROBE_SOFT then
		probeTimer.softShown = true
		Status_MarkSlow()
	end
	if probeTimer.elapsed >= PROBE_HARD then
		if not probeSettled then
			-- The hard mark aborts the ATTEMPT, but the verdict depends on
			-- whether the server ever spoke: a handshake that got past connect
			-- is a server that is up, just slow to reject a bogus account.
			if probeAnswered then
				Status_MarkUp(true, probeAnsweredAt)
			else
				Status_MarkDown()
			end
			-- The verdict is final: DisconnectFromServer below raises a
			-- DISCONNECTED dialog of our own making, and before v15 the probing
			-- branch of GlueDialog_Show re-marked on it - flipping a hard-mark UP
			-- to "appears DOWN (Disconnected)" a moment later.
			probeSettled = true
			if type(DisconnectFromServer) == "function" then
				DisconnectFromServer()
			end
		elseif probeTimer.elapsed >= PROBE_HARD + PROBE_SETTLE_WINDOW then
			-- No terminal dialog ever arrived; stop swallowing.
			probing = false
			probeTimer:Hide()
		end
	end
end)

-- Deferred probe start: returning to the login screen from character select
-- must NOT probe immediately - the old session's teardown is still in
-- flight (see PROBE_GRACE). The delay lets it finish first.
local probeDelayTimer = CreateFrame("Frame")
probeDelayTimer.remaining = 0
probeDelayTimer:Hide()
probeDelayTimer:SetScript("OnUpdate", function()
	probeDelayTimer.remaining = probeDelayTimer.remaining - (arg1 or 0.02)
	if probeDelayTimer.remaining <= 0 then
		probeDelayTimer:Hide()
		OctoStatus_Probe()
	end
end)

local function OctoStatus_ProbeSoon(delay)
	probeDelayTimer.remaining = delay
	probeDelayTimer:Show()
	Status_MarkChecking() -- fill the corner right away; the probe follows
end

-- The auth progress states arrive as UPDATE_STATUS_DIALOG, which the stock
-- GlueDialog handles directly - they never pass through GlueDialog_Show, so
-- the hook below cannot see them. Listen for the event ourselves.
Octo_Try("probe-events", function()
	probeTimer:RegisterEvent("UPDATE_STATUS_DIALOG")
	probeTimer:SetScript("OnEvent", function()
		if probing and arg1 and ANSWER_MESSAGES[arg1] then
			if not probeAnswered then
				probeAnsweredAt = probeTimer.elapsed
			end
			probeAnswered = true
		end
	end)
end)

function OctoStatus_Probe()
	probeDelayTimer:Hide() -- a direct probe supersedes a pending deferred one
	probing = true
	probeAnswered = false
	probeAnsweredAt = nil
	probeSettled = false
	probeTimer.elapsed = 0
	probeTimer.softShown = false
	probeTimer:Show()
	Status_MarkChecking()
	DefaultServerLogin("octoprobe", "probe")
end

local Octo_OrigGlueDialog_Show = GlueDialog_Show
function GlueDialog_Show(which, text, data)
	if probing then
		if probeSettled then
			-- Hard mark already ruled; this dialog is fallout from the
			-- aborted attempt (typically DISCONNECTED from our own
			-- DisconnectFromServer). Swallow it, and once the terminal
			-- dialog lands stop swallowing so real dialogs get through.
			if text and (DOWN_MESSAGES[text] or UP_MESSAGES[text]) then
				probing = false
			end
			return
		end
		if text and DOWN_MESSAGES[text] then
			if text == DISCONNECTED or text == RESPONSE_DISCONNECTED then
				return -- stale teardown fallout, never a verdict (see above)
			end
			probing = false
			probeTimer:Hide()
			Status_MarkDown(text)
		elseif text and UP_MESSAGES[text] then
			probing = false
			probeTimer:Hide()
			Status_MarkUp(true, probeTimer.elapsed)
		elseif text and ANSWER_MESSAGES[text] then
			-- OPEN_STATUS_DIALOG path for a progress state
			if not probeAnswered then
				probeAnsweredAt = probeTimer.elapsed
			end
			probeAnswered = true
		end
		return -- swallow every dialog during a probe (no Connecting/Cancel)
	end
	-- v15: no MarkDown here. A stock DISCONNECTED dialog fires every time the
	-- player RETURNS to the login screen after a session - it means "you were
	-- disconnected", not "the server is down", and painting the banner red on
	-- it was the standing false "appears DOWN" after logout.
	return Octo_OrigGlueDialog_Show(which, text, data)
end

-- Wrap AccountLogin_OnShow: strip the "#O=..." order suffix from the login
-- box, and auto-probe once so the corner status populates by itself. On a
-- RETURN from character select the probe is deferred (see PROBE_GRACE /
-- OctoStatus_ProbeSoon): probing while the old session tears down was what
-- produced the false "appears DOWN" after logout.
local autoProbed = false
local returningFromCharSelect = false
local backWasVoluntary = false

-- The Back button and ESCAPE both land here. A VOLUNTARY exit from char
-- select is itself proof the server is up - we were connected to it one
-- second ago - so the login screen can go straight to the green banner
-- with no probe at all (v21). This also sidesteps the auth core
-- rate-limiting repeat probe logins within one session. A forced return
-- (kicked/disconnected) does not pass through here and still probes.
if type(CharacterSelect_Exit) == "function" then
	local Octo_OrigCharacterSelect_Exit = CharacterSelect_Exit
	function CharacterSelect_Exit()
		backWasVoluntary = true
		return Octo_OrigCharacterSelect_Exit()
	end
end

if type(AccountLogin_OnShow) == "function" then
	local Octo_OrigAccountLogin_OnShow = AccountLogin_OnShow
	function AccountLogin_OnShow()
		Octo_OrigAccountLogin_OnShow()
		if AccountLoginAccountEdit and AccountLoginAccountEdit.GetText then
			local t = AccountLoginAccountEdit:GetText() or ""
			local cut = string.find(t, "#", 1, true)
			if cut then
				AccountLoginAccountEdit:SetText(string.sub(t, 1, cut - 1))
			end
		end
		if not autoProbed then
			autoProbed = true
			if returningFromCharSelect and backWasVoluntary then
				-- Chose Back while connected: the server is up, say so.
				returningFromCharSelect = false
				backWasVoluntary = false
				Status_MarkUp(true)
			elseif returningFromCharSelect then
				returningFromCharSelect = false
				OctoStatus_ProbeSoon(2.0)
			else
				OctoStatus_Probe()
			end
		end
	end
end

-- Wrap AccountLogin_Login: end any dangling probe, and re-append the order
-- suffix after the stock code saves (or clears) the plain account name.
if type(AccountLogin_Login) == "function" then
	local Octo_OrigAccountLogin_Login = AccountLogin_Login
	function AccountLogin_Login()
		probing = false
		probeDelayTimer:Hide() -- a real login cancels any pending auto-probe
		local _, suffix = Order_SplitSaved()
		Octo_OrigAccountLogin_Login()
		if suffix and HAS_SAVEDNAME then
			local s = GetSavedAccountName() or ""
			if not string.find(s, "#", 1, true) then
				SetSavedAccountName(s .. suffix)
			end
		end
	end
end

local Octo_OrigCharacterSelect_OnShow = CharacterSelect_OnShow
function CharacterSelect_OnShow()
	Octo_Try("chal-live", Chal_LoadLive) -- fresh masks for the row icons
	probing = false
	probeDelayTimer:Hide()
	Status_MarkUp() -- we connected, so the server is up; clear the banner
	-- Re-arm the auto-probe: if we later land back on the login screen
	-- (logout/disconnect), the old verdict is stale - probe again, but
	-- DEFERRED, after the old session's teardown dialogs are done.
	autoProbed = false
	returningFromCharSelect = true
	backWasVoluntary = false -- only a real Back/ESC sets it, right before exit
	return Octo_OrigCharacterSelect_OnShow()
end

-- The v18-v23 version tag (grey "OctoGlue vNN", bottom-right) was removed in
-- v24 (owner: no debug text on screen). Survived-a-server-patch check now:
-- the status banner appearing at all IS the mod - stock glue has none.

-- Marker for the in-game LauncherNotice (launcher git-URL installs get the
-- addon but not this MPQ): its presence in CustomData says the full package
-- is installed. Written every client start; harmless without the DLL.
Octo_Try("installed-marker", function()
	if type(WriteCustomFile) == "function" then
		pcall(WriteCustomFile, "octoglue-installed", "1")
	end
end)

-- -------------------------------------------------------------- OctoMusic --
-- The glue VM has no volume cvars, but it DOES have the music transport:
-- PlayGlueMusic/StopGlueMusic (the stock GlueParent.lua drives them). So the
-- "sound button" is a MUSIC toggle: shadowing PlayGlueMusic keeps the choice
-- across glue-screen changes (GlueParent replays the theme on every screen
-- swap by global name, so it calls our wrapper), and "#M=0" in the account
-- suffix keeps it across sessions. Effects volume would still need a DLL.
local musicButtons = {}

local Octo_OrigPlayGlueMusic = PlayGlueMusic
-- Remember the last track the stock UI ASKED for, even while muted: toggling
-- music back on then resumes the current screen's own theme instead of
-- always restarting the login theme (v17).
local lastGlueMusic = nil
function PlayGlueMusic(music)
	if music then
		lastGlueMusic = music
	end
	if musicOff then
		return
	end
	return Octo_OrigPlayGlueMusic(music)
end

local function Music_UpdateLabels()
	for _, b in ipairs(musicButtons) do
		b:SetText(musicOff and "Music: Off" or "Music: On")
	end
end

local function Music_Toggle()
	musicOff = not musicOff
	if musicOff then
		if type(StopGlueMusic) == "function" then
			StopGlueMusic()
		end
	else
		Octo_OrigPlayGlueMusic(lastGlueMusic or CurrentGlueMusic
			or "Sound\\Music\\GlueScreenMusic\\wow_main_theme.mp3")
	end
	Suffix_Save()
	Music_UpdateLabels()
end

local function Music_MakeButton(name, parent, point, relTo, relPoint, x, y)
	if not parent or _G[name] then
		return
	end
	local b = CreateFrame("Button", name, parent, "GlueButtonSmallTemplate")
	b:SetPoint(point, relTo or parent, relPoint or point, x, y)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)
	b:SetScript("OnClick", Music_Toggle)
	table.insert(musicButtons, b)
end

Octo_Try("music-btn", function()
	-- Login screen: under the status lamp (which sits at -24,-24).
	Music_MakeButton("OctoMusicButtonLogin", Status_Parent(),
		"TOPRIGHT", nil, nil, -20, -50)
	-- Char select: beside the AddOns button, bottom-left.
	local addons = _G["CharacterSelectAddonsButton"]
	if addons then
		Music_MakeButton("OctoMusicButtonCharSelect", CharacterSelectUI,
			"LEFT", addons, "RIGHT", 8, 0)
	else
		Music_MakeButton("OctoMusicButtonCharSelect", CharacterSelectUI,
			"BOTTOMLEFT", nil, nil, 16, 40)
	end
	Music_UpdateLabels()
	if musicOff and type(StopGlueMusic) == "function" then
		StopGlueMusic() -- the theme may already be playing when we load
	end
end)

-- One-time pointer for launcher git-URL installs that lack the full package.
-- The glue mod (patch-9.mpq) writes CustomData\octoglue-installed at client
-- start via nampower's WriteCustomFile, so its absence in-world means this
-- is an addon-only install. Without nampower we cannot tell - stay quiet
-- rather than nag full installs.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
	f:UnregisterEvent("PLAYER_ENTERING_WORLD") -- fires on every loading screen
	if type(CustomFileExists) ~= "function" then
		return
	end
	local ok, present = pcall(CustomFileExists, "octoglue-installed")
	if ok and not present then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OctoWoW client mods|r: addon-only install. Character-select reordering, challenge row icons and the server-status banner come from the full package: github.com/Krool/octowow-client-mods/releases")
	end
end)

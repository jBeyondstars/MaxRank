-- MaxRank: upgrades action bar spells to the highest rank you know.
-- Core: namespace helpers, saved variables, events, refresh scheduling and slash commands.
--
-- WoW Forever runs the Retail client (Interface 16001): only C_Spell / C_SpellBook exist,
-- and registering an event the client does not know throws, hence the pcall below.

local ADDON, ns = ...

local PREFIX = "|cffffc040MaxRank|r: "
local UPGRADE_AFTER_COMBAT_DELAY = 0.5	-- seconds after combat before a queued update runs

local defaults = {
	ignored = {},		-- [spellID] = true: exact ranks that are never upgraded, on any bar
	showBar = true,		-- buttons under the spellbook
	sessions = 0,		-- load counter, shows in /maxrank status whether saved data survives a restart
}

local DB

ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Secret values (Forever combat restrictions) cannot be compared or used as keys: treat them as missing.
function ns.Val(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
	return v
end

function ns.Plural(n)
	return n == 1 and "" or "s"
end

function ns.GetDB()
	return DB
end

-- Many events can ask for a refresh in the same frame; run it once, on the next frame,
-- after Blizzard's own handlers have updated each button's action slot.
local refreshQueued = false

local function RunRefresh()
	refreshQueued = false
	if not DB or not ns.supported then return end
	ns.RefreshOverlays()
	ns.RefreshSpellBookBar()
end

function ns.RequestRefresh()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, RunRefresh)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"SPELLS_CHANGED",
	"LEARNED_SPELL_IN_SKILL_LINE",
	"ACTIVE_TALENT_GROUP_CHANGED",
	"ACTIONBAR_SLOT_CHANGED",
	"ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR",
	"UPDATE_SHAPESHIFT_FORM",
	"UPDATE_VEHICLE_ACTIONBAR",
	"UPDATE_OVERRIDE_ACTIONBAR",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
}) do
	pcall(f.RegisterEvent, f, e)
end

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ns.loadedFromDisk = MaxRankCharDB ~= nil
		MaxRankCharDB = MaxRankCharDB or {}
		for k, v in pairs(defaults) do
			if MaxRankCharDB[k] == nil then
				MaxRankCharDB[k] = type(v) == "table" and {} or v
			end
		end
		DB = MaxRankCharDB
		DB.sessions = DB.sessions + 1
		ns.supported = C_SpellBook ~= nil and C_SpellBook.IsSpellBookItemLowRank ~= nil
		if ns.supported and EventRegistry then
			-- Fired by every Blizzard action button right after it changes slot (paging, stance, content).
			EventRegistry:RegisterCallback("ActionButton.OnActionChanged", ns.RequestRefresh, ns)
		end
		return
	end
	if not DB then return end
	if not ns.supported then
		if event == "PLAYER_LOGIN" then
			ns.Print("this client has no spell rank API, MaxRank stays disabled.")
		end
		return
	end

	if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
		or event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		ns.MarkSpellbookDirty()
		ns.RequestRefresh()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Click catchers would block casting with the mouse in combat.
		if ns.IsPickMode() then
			ns.StopPick()
			ns.Print("Ignore mode closed: you entered combat.")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.pendingUpgrade then
			ns.pendingUpgrade = false
			C_Timer.After(UPGRADE_AFTER_COMBAT_DELAY, ns.UpgradeAll)
		end
		ns.RequestRefresh()
	else
		ns.RequestRefresh()
	end
end)

--------------------------------------------------------------------------------
-- /maxrank commands
--------------------------------------------------------------------------------

local HELP = {
	"/maxrank update - upgrade outdated spells on your action bars",
	"/maxrank scan - list outdated spells without changing anything",
	"/maxrank ignore - toggle ignore mode (click a spell on a bar to keep that exact rank)",
	"/maxrank highlight - toggle the glow on outdated spells",
	"/maxrank list - list ignored ranks",
	"/maxrank clear - stop ignoring every rank",
	"/maxrank bar on|off - show or hide the buttons under the spellbook",
	"/maxrank status - version, saved data and spellbook details",
}

SLASH_MAXRANK1 = "/maxrank"
SlashCmdList.MAXRANK = function(input)
	if not DB then return end
	if not ns.supported then
		ns.Print("this client has no spell rank API, MaxRank stays disabled.")
		return
	end
	local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd, arg = cmd:lower(), arg:lower()
	if cmd == "update" then
		ns.UpgradeAll()
	elseif cmd == "scan" then
		ns.PrintScan()
	elseif cmd == "ignore" then
		ns.TogglePickMode()
	elseif cmd == "highlight" then
		ns.ToggleHighlight()
	elseif cmd == "list" then
		ns.PrintIgnored()
	elseif cmd == "clear" then
		ns.ClearIgnored()
	elseif cmd == "bar" then
		if arg == "on" then DB.showBar = true elseif arg == "off" then DB.showBar = false else DB.showBar = not DB.showBar end
		ns.Print("spellbook buttons " .. (DB.showBar and "shown." or "hidden. Type /maxrank bar on to show them again."))
		ns.RequestRefresh()
	elseif cmd == "status" then
		ns.PrintStatus()
	else
		ns.Print("commands:")
		for _, line in ipairs(HELP) do
			DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
		end
	end
end

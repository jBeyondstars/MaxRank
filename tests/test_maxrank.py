"""Offline tests for MaxRank: the addon's Lua files run against a stubbed WoW Forever API.

Run from the MaxRank folder:  python -m unittest discover -s tests -v
"""

import re
import unittest
from pathlib import Path

try:
    from lupa.lua51 import LuaRuntime  # same Lua version as the game
except ImportError:
    try:
        from lupa import LuaRuntime
    except ImportError:
        LuaRuntime = None

ROOT = Path(__file__).resolve().parent.parent


def toc_files():
    lines = (ROOT / "MaxRank.toc").read_text(encoding="utf-8").splitlines()
    return [line.strip() for line in lines if line.strip() and not line.startswith("#")]


STUBS = r"""
Enum = {
	SpellBookSpellBank = { Player = 0, Pet = 1 },
	SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
issecretvalue = function() return false end

-- Forever throws on unknown events; ACTIVE_TALENT_GROUP_CHANGED is left out on purpose.
KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
	"LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
	"UPDATE_SHAPESHIFT_FORM", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do KNOWN_EVENTS[e] = true end

CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end }
function ChatContains(text)
	for _, line in ipairs(CHAT) do if line:find(text, 1, true) then return true end end
	return false
end

TIMERS = {}
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
function RunTimers()
	local guard = 0
	while #TIMERS > 0 do
		guard = guard + 1
		assert(guard < 1000, "timer loop")
		table.remove(TIMERS, 1)()
	end
end

-- Frames created by the addon: plain tables that remember what matters.
FRAMES = {}
local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(e)
	if not KNOWN_EVENTS[e] then error("unknown event " .. e) end
	self.events[e] = true
end
function Methods:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Methods:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown end
function Methods:SetText(t) self.text = t end
function Methods:SetEnabled(v) self.enabled = v end
function Methods:GetFrameLevel() return 5 end
function Methods:GetWidth() return 45 end
function Methods:GetHeight() return 45 end
function Methods:IsPlaying() return self.playing end
function Methods:Play() self.playing = true end
function Methods:Stop() self.playing = false end
function Methods:IsOwned() return false end
local function NewObject(kind, name, parent)
	local o = { scripts = {}, events = {}, shown = true, kind = kind, name = name, parent = parent }
	return setmetatable(o, { __index = function(_, key)
		if Methods[key] then return Methods[key] end
		if key:match("^Create") then return function(self, k) return NewObject(k or key, nil, self) end end
		if key:match("^%u") then return function() end end	-- widget methods; plain fields stay nil
	end })
end
function CreateFrame(kind, name, parent)
	local f = NewObject(kind, name, parent)
	FRAMES[#FRAMES + 1] = f
	if name then _G[name] = f end
	return f
end
function ChildrenOf(parent, kind)
	local out = {}
	for _, f in ipairs(FRAMES) do if f.parent == parent and (not kind or f.kind == kind) then out[#out + 1] = f end end
	return out
end
function FireEvent(event, ...)
	for _, f in ipairs(FRAMES) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end
UIParent = NewObject("Frame")
GameTooltip = NewObject("GameTooltip")
UISpecialFrames = {}
SlashCmdList = {}
C_AddOns = { GetAddOnMetadata = function() return "test" end }
C_Texture = { GetAtlasInfo = function() return {} end }

CALLBACKS = {}
EventRegistry = { RegisterCallback = function(_, event, fn, owner)
	CALLBACKS[event] = CALLBACKS[event] or {}
	table.insert(CALLBACKS[event], { fn = fn, owner = owner })
end }
function FireCallback(event, ...)
	for _, c in ipairs(CALLBACKS[event] or {}) do c.fn(c.owner, ...) end
end
PENDING_ADDONS = {}
EventUtil = { ContinueOnAddOnLoaded = function(name, fn) PENDING_ADDONS[name] = fn end }
-- Opens the spellbook for the first time: Blizzard_PlayerSpells loads, MaxRank attaches its buttons.
function LoadSpellBook()
	BOOK_FIELDS = { shown = true }
	BOOK_FIELDS.PagedSpellsFrame = Protected("PagedSpellsFrame", { PagingControls = Protected("PagingControls", {}) })
	PlayerSpellsFrame = Protected("PlayerSpellsFrame", { SpellBookFrame = Protected("SpellBookFrame", BOOK_FIELDS) })
	PENDING_ADDONS["Blizzard_PlayerSpells"]()
	RunTimers()
end

-- Blizzard frames: reads are fine, any write from the addon is a bug (taint).
function Protected(name, fields)
	return setmetatable({}, {
		__index = function(_, key)
			if fields[key] ~= nil then return fields[key] end
			if Methods[key] then return Methods[key] end
			if key:match("^%u") then return function() end end
		end,
		__newindex = function(_, key) error("MaxRank wrote '" .. tostring(key) .. "' into Blizzard frame " .. name) end,
	})
end
BUTTON_SLOTS = {}
for i = 1, 12 do
	local fields = { action = i, scripts = {}, events = {}, shown = true }
	BUTTON_SLOTS[i] = fields
	_G["ActionButton" .. i] = Protected("ActionButton" .. i, fields)
end

-- Spells and the spellbook.
SPELLS = {}
BOOK = {}
function Spell(id, name, sub, level) SPELLS[id] = { name = name, sub = sub, level = level } end
C_Spell = {
	GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end,
	GetSpellSubtext = function(id) return SPELLS[id] and SPELLS[id].sub end,
	GetSpellLevelLearned = function(id) return SPELLS[id] and SPELLS[id].level or 0 end,
	GetBaseSpell = function(id) return id end,
	PickupSpell = function(id) CURSOR = { "spell", id } end,
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK, isGuild = false } end,
	GetSpellBookItemInfo = function(slot)
		local e = BOOK[slot]
		if not e then return nil end
		local s = SPELLS[e.id]
		return { actionID = e.id, spellID = e.id, itemType = e.itemType or 1, name = s.name, subName = s.sub or "",
			isPassive = e.passive or false, isOffSpec = false }
	end,
	GetSpellBookItemLevelLearned = function(slot) return SPELLS[BOOK[slot].id].level end,
	IsSpellBookItemLowRank = function(slot) return BOOK[slot].low or false end,
	PickupSpellBookItem = function(slot) CURSOR = { "spell", BOOK[slot].id } end,
	FindSpellBookSlotForSpell = function(id)
		for i, e in ipairs(BOOK) do if e.id == id then return i, 0 end end
	end,
	IsSpellKnown = function(id)
		for _, e in ipairs(BOOK) do if e.id == id and (e.itemType or 1) == 1 then return true end end
		return false
	end,
}

-- Action slots and the cursor.
ACTIONS = {}
function GetActionInfo(slot) local a = ACTIONS[slot]; if a then return a[1], a[2], a[3] end end
function HasAction(slot) return ACTIONS[slot] ~= nil end

function GetActionTexture(slot) return ACTIONS[slot] and 134400 end
function SlotSpell(slot) return ACTIONS[slot] and ACTIONS[slot][2] end
CURSOR = nil
function GetCursorInfo() if CURSOR then return CURSOR[1], CURSOR[2] end end
function ClearCursor() CURSOR = nil end
function SpellIsTargeting() return false end
IN_COMBAT = false
function InCombatLockdown() return IN_COMBAT end
PLACED = 0
function PlaceAction(slot)
	assert(not IN_COMBAT, "PlaceAction called in combat")
	local old = ACTIONS[slot]
	ACTIONS[slot] = CURSOR and { CURSOR[1], CURSOR[2] } or nil
	CURSOR = old and { old[1], old[2] } or nil
	PLACED = PLACED + 1
end

-- A priest: Flash Heal ranks 1-3 known (4 still to train), Heroic Strike rank 1 replaced by rank 2.
Spell(2061, "Flash Heal", "Rank 1", 20)
Spell(9472, "Flash Heal", "Rank 2", 26)
Spell(9473, "Flash Heal", "Rank 3", 32)
Spell(9474, "Flash Heal", "Rank 4", 38)
Spell(139, "Renew", "Rank 1", 8)
Spell(5019, "Shoot", "", 1)
Spell(78, "Heroic Strike", "Rank 1", 1)
Spell(284, "Heroic Strike", "Rank 2", 8)
Spell(15000, "Spirit Tap", "Passive", 10)
BOOK = {
	{ id = 2061, low = true }, { id = 9472, low = true }, { id = 9473 }, { id = 9474, itemType = 2 },
	{ id = 139 }, { id = 5019 }, { id = 284 }, { id = 15000, passive = true },
}
ACTIONS = {
	[1] = { "spell", 2061 }, [2] = { "spell", 9472 }, [3] = { "spell", 9473 }, [4] = { "spell", 139 },
	[5] = { "spell", 5019 }, [6] = { "macro", 1 }, [7] = { "item", 6948 }, [8] = { "spell", 78 },
	[9] = { "spell", 2061 }, [10] = { "spell", 9472, "pet" },
	[75] = { "spell", 9472 },	-- a stance or form page, not on screen
	[150] = { "spell", 2061 },	-- MultiBar5
}
"""


@unittest.skipIf(LuaRuntime is None, "Optional developer Lua runtime (lupa)")
class MaxRankTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUBS)
        self.g = self.lua.globals()
        self.ns = self.lua.table()
        loader = self.lua.eval(
            "function(src, name, ns) return assert((loadstring or load)(src, '@' .. name))('MaxRank', ns) end")
        for name in toc_files():
            loader((ROOT / name).read_text(encoding="utf-8"), name, self.ns)
        self.lua.execute("FireEvent('ADDON_LOADED', 'MaxRank'); FireEvent('PLAYER_LOGIN'); RunTimers()")

    def slot(self, n):
        return self.g.SlotSpell(n)

    def info(self, n):
        return self.ns.GetSlotInfo(n)

    def chat(self, text):
        return self.g.ChatContains(text)

    def test_loads_despite_unknown_event_and_counts_session(self):
        db = self.g.MaxRankCharDB
        self.assertEqual(db.sessions, 1)
        self.assertFalse(self.ns.loadedFromDisk)
        self.assertTrue(self.ns.supported)

    def test_classification(self):
        self.assertTrue(self.info(1).outdated)
        self.assertEqual(self.info(1).top.actionID, 9473)
        self.assertTrue(self.info(2).outdated)
        self.assertFalse(self.info(3).outdated)   # top known rank
        self.assertFalse(self.info(4).outdated)   # single rank
        self.assertFalse(self.info(5).outdated)   # no rank at all
        self.assertIsNone(self.info(6))           # macro
        self.assertIsNone(self.info(7))           # item
        self.assertIsNone(self.info(10))          # pet action
        replaced = self.info(8)                   # rank 1 no longer in the spellbook
        self.assertTrue(replaced.outdated)
        self.assertEqual(replaced.top.actionID, 284)

    def test_update_skips_ignored_rank_everywhere(self):
        self.ns.ToggleIgnoreSlot(1)
        self.assertTrue(self.g.MaxRankCharDB.ignored[2061])
        self.ns.UpgradeAll()
        self.assertEqual(self.slot(1), 2061)
        self.assertEqual(self.slot(9), 2061)
        self.assertEqual(self.slot(150), 2061)
        self.assertEqual(self.slot(2), 9473)
        self.assertEqual(self.slot(75), 9473)     # hidden page updated too
        self.assertEqual(self.slot(8), 284)
        self.assertEqual(self.slot(3), 9473)
        self.assertEqual(self.slot(6), 1)         # macro untouched
        self.assertIsNone(self.g.CURSOR)
        self.lua.execute("RunTimers()")
        self.assertFalse(self.chat("could not be updated"))
        self.assertTrue(self.chat("Updated 3 action slots"))
        self.assertTrue(self.chat("(3 ignored)"))

    def test_toggle_ignore_twice_restores_update(self):
        self.ns.ToggleIgnoreSlot(1)
        self.ns.ToggleIgnoreSlot(9)               # same rank, other slot: un-ignores
        self.assertIsNone(self.g.MaxRankCharDB.ignored[2061])
        self.ns.UpgradeAll()
        self.assertEqual(self.slot(1), 9473)
        self.assertEqual(self.slot(150), 9473)

    def test_non_spell_cannot_be_ignored(self):
        self.ns.ToggleIgnoreSlot(6)
        self.assertTrue(self.chat("Only spells can be ignored."))

    def test_combat_postpones_update(self):
        self.g.IN_COMBAT = True
        self.ns.UpgradeAll()
        self.assertEqual(self.g.PLACED, 0)
        self.assertTrue(self.ns.pendingUpgrade)
        self.g.IN_COMBAT = False
        self.lua.execute("FireEvent('PLAYER_REGEN_ENABLED'); RunTimers()")
        self.assertEqual(self.slot(2), 9473)

    def test_busy_cursor_refuses(self):
        self.lua.execute("CURSOR = { 'item', 6948 }")
        self.ns.UpgradeAll()
        self.assertEqual(self.g.PLACED, 0)
        self.assertTrue(self.chat("cursor is busy"))

    def test_pick_mode_clicks_toggle_ignore_and_combat_exits(self):
        self.ns.StartPick()
        self.assertTrue(self.ns.IsPickMode())
        self.assertTrue(self.g.MaxRankPickHint.shown)
        catcher = self.g.ChildrenOf(self.g.ActionButton1, "Button")[1]
        catcher.scripts.OnClick(catcher, "LeftButton")
        self.assertTrue(self.g.MaxRankCharDB.ignored[2061])
        catcher.scripts.OnClick(catcher, "RightButton")
        self.assertFalse(self.ns.IsPickMode())
        self.assertFalse(self.g.MaxRankPickHint.shown)
        self.ns.StartPick()
        self.lua.execute("IN_COMBAT = true; FireEvent('PLAYER_REGEN_DISABLED')")
        self.assertFalse(self.ns.IsPickMode())

    def test_pick_mode_refused_in_combat(self):
        self.g.IN_COMBAT = True
        self.ns.StartPick()
        self.assertFalse(self.ns.IsPickMode())

    def test_highlight_follows_button_slot_changes(self):
        self.ns.ToggleHighlight()
        self.lua.execute("RunTimers()")
        overlay = self.g.ChildrenOf(self.g.ActionButton1, "Frame")[1]
        self.assertTrue(overlay.shown)
        self.assertTrue(overlay.glow.shown)
        self.assertEqual(len(self.g.ChildrenOf(self.g.ActionButton3, "Frame")), 0)
        # Paging: ActionButton1 now shows slot 3 (max rank); Blizzard fires the callback.
        self.lua.execute("BUTTON_SLOTS[1].action = 3; FireCallback('ActionButton.OnActionChanged'); RunTimers()")
        self.assertFalse(overlay.shown)

    def test_ignored_rank_shows_padlock_not_glow(self):
        self.ns.ToggleIgnoreSlot(1)
        self.ns.ToggleHighlight()
        self.lua.execute("RunTimers()")
        overlay = self.g.ChildrenOf(self.g.ActionButton1, "Frame")[1]
        self.assertTrue(overlay.shown)
        self.assertFalse(overlay.glow.shown)
        self.assertTrue(overlay.mark.shown)

    def test_spellbook_bar_attaches_when_blizzard_spellbook_loads(self):
        self.assertIsNotNone(self.g.PENDING_ADDONS["Blizzard_PlayerSpells"])
        self.lua.execute("LoadSpellBook()")
        self.assertEqual(self.g.MaxRankUpdateButton.text, "Update (6)")
        self.ns.StartPick()
        self.lua.execute("RunTimers()")
        self.assertEqual(self.g.MaxRankIgnoreButton.text, "Done")

    def test_closing_spellbook_ends_highlight_and_ignore_mode(self):
        self.lua.execute("LoadSpellBook()")
        self.ns.ToggleHighlight()
        self.ns.StartPick()
        # Minimize/maximize hides the book and shows it again in the same pass: modes stay on.
        self.lua.execute("FireCallback('PlayerSpellsFrame.SpellBookFrame.Hide'); RunTimers()")
        self.assertTrue(self.ns.IsHighlight())
        self.assertTrue(self.ns.IsPickMode())
        self.lua.execute("BOOK_FIELDS.shown = false; FireCallback('PlayerSpellsFrame.SpellBookFrame.Hide'); RunTimers()")
        self.assertFalse(self.ns.IsHighlight())
        self.assertFalse(self.ns.IsPickMode())
        self.assertFalse(self.g.MaxRankPickHint.shown)
        overlay = self.g.ChildrenOf(self.g.ActionButton1, "Frame")[1]
        self.assertFalse(overlay.shown)

    def test_slash_commands(self):
        self.g.SlashCmdList.MAXRANK("scan")
        self.assertTrue(self.chat("6 action slots can be updated"))
        self.g.SlashCmdList.MAXRANK("status")
        self.assertTrue(self.chat("session 1"))
        self.g.SlashCmdList.MAXRANK("")
        self.assertTrue(self.chat("/maxrank update"))


class SourceTests(unittest.TestCase):
    FORBIDDEN = [
        r"\bGetSpellInfo\(", r"\bGetSpellBookItemName\b", r"ActionButton_ShowOverlayGlow", r"(?<![.\w])IsAddOnLoaded\(",
        r"\bhooksecurefunc\b", r"RegisterGameMenuEscHandler", r"UpdateOnBarHighlightMarks", r"\bgoto\b",
    ]

    def lua_sources(self):
        return [(name, (ROOT / name).read_bytes()) for name in toc_files()]

    def test_toc_files_exist(self):
        for name in toc_files():
            self.assertTrue((ROOT / name).is_file(), name)

    def test_style(self):
        for name, data in self.lua_sources():
            text = data.decode("ascii")  # English-only, plain ASCII
            self.assertNotIn("\n", text.replace("\r\n", ""), f"{name}: expected CRLF line endings")
            for number, line in enumerate(text.split("\r\n"), 1):
                self.assertFalse(line.startswith("    "), f"{name}:{number}: indent with tabs")

    def test_no_removed_or_risky_api(self):
        for name, data in self.lua_sources():
            text = re.sub(r"--[^\r\n]*", "", data.decode("ascii"))  # comments may name them
            for pattern in self.FORBIDDEN:
                self.assertIsNone(re.search(pattern, text), f"{name}: {pattern}")


if __name__ == "__main__":
    unittest.main()

-- Ranks: finds action bar spells below the highest rank you know, and upgrades them.
--
-- The spellbook API lists every rank; C_SpellBook.IsSpellBookItemLowRank tells which ones have a
-- known higher rank (Blizzard only hides those in Lua, CVar ShowAllSpellRanks). Ranks are ordered by
-- the level they are learned at, never by spell ID: Forever adds new IDs (Slam rank 1 is 1240193).

local ADDON, ns = ...

local MAX_ACTION_SLOT = 180		-- pages 1-15; vehicle and override pages sit beyond it
local BANK = Enum.SpellBookSpellBank.Player
local SPELL_ITEM = Enum.SpellBookItemType.Spell
local RESCAN_DELAY = 0.2		-- seconds before checking what an update left behind
local MAX_LISTED = 10			-- pending changes listed in the Update tooltip
local MAX_CHAT_LISTED = 4		-- changes named in the single line an automatic update prints
local SPEC_SETTLE = 1			-- quiet time on the bars and spellbook after a spec switch before anything is placed
local SPEC_SETTLE_MAX = 10		-- longest wait for that quiet time
local AUTO_SETTLE = 5			-- seconds after a rank is learned during which automatic update keeps looking
local AUTO_RETRY_DELAY = 1		-- seconds between automatic tries while the cursor is busy
local AUTO_RETRIES = 30

local Val, Plural = ns.Val, ns.Plural

-- Rank map, rebuilt lazily after the spellbook changes.
local members = {}			-- [spellID] = member, for both the base (actionID) and the override (spellID)
local bySlot = {}			-- [spellbook slot] = member
local topByName = {}		-- [name] = member holding the single highest known rank of that name
local ambiguous = {}		-- [name] = true: several spells share this name, MaxRank leaves them alone
local pendingSpells = {}	-- [spellID] = "requested" | "text" | "done": async subtext load state
local mapSize = 0
local dirty = true
local requestingSpell = false

function ns.MarkSpellbookDirty()
	dirty = true
end

function ns.IsRequestingSpell()
	return requestingSpell
end

local function RequestSpellText(id)
	if not id or pendingSpells[id] ~= nil then return end
	pendingSpells[id] = "requested"
	if C_Spell.RequestLoadSpellData then
		requestingSpell = true
		pcall(C_Spell.RequestLoadSpellData, id)
		requestingSpell = false
	end
end

function ns.OnSpellLoaded(event, spellID, success)
	spellID = Val(spellID)
	local state = spellID and pendingSpells[spellID]
	if not state or state == "done" then return false end
	if event == "SPELL_TEXT_UPDATE" then
		pendingSpells[spellID] = "done"
		return true
	end
	if not Val(success) then
		pendingSpells[spellID] = "done"
		return false
	end
	if state == "requested" then
		pendingSpells[spellID] = "text"
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Rank map
--------------------------------------------------------------------------------

local function RankNumber(text)
	return text and tonumber(text:match("%d+"))
end

local function SpellSubtext(id, m)
	local sub = m and m.subName
	if not sub or sub == "" then
		local queryID = m and m.spellID or id
		sub = C_Spell.GetSpellSubtext and Val(C_Spell.GetSpellSubtext(queryID))
		if sub and sub ~= "" then
			pendingSpells[queryID] = "done"
			if m then
				m.subName = sub
				m.rank = RankNumber(sub)
			end
		else
			RequestSpellText(queryID)
		end
	end
	return sub
end

-- True when a is a higher rank than b: higher rank number first, then learned later.
local function IsHigher(a, b)
	if a.rank and b.rank and a.rank ~= b.rank then return a.rank > b.rank end
	if a.level ~= b.level then return a.level > b.level end
	return (a.rank or 0) > (b.rank or 0)
end

local function IsLocked(spellID)
	-- Level Link (party sync) locks spells above the synced level.
	return C_LevelLink and C_LevelLink.IsSpellLocked and Val(C_LevelLink.IsSpellLocked(spellID)) and true or false
end

-- The highest rank in one skill line's entries of a name, or nil when it is not clear-cut.
local function PickTop(list)
	local top, count = nil, 0
	for _, m in ipairs(list) do
		if not m.low then top, count = m, count + 1 end
	end
	if count > 1 then return nil end
	if count == 0 then
		-- Every entry is flagged low (another spell supersedes the chain): the highest one wins, ties are skipped.
		for _, m in ipairs(list) do
			if not top or IsHigher(m, top) then top = m end
		end
		for _, m in ipairs(list) do
			if m ~= top and not IsHigher(top, m) then return nil end
		end
	end
	if top and top.locked then return nil end
	return top
end

local function BuildRankMap()
	dirty = false
	wipe(members)
	wipe(bySlot)
	wipe(topByName)
	wipe(ambiguous)
	mapSize = 0

	local groups = {}	-- [name] = { [skill line] = { members } }
	for line = 1, Val(C_SpellBook.GetNumSpellBookSkillLines()) or 0 do
		local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if lineInfo and not Val(lineInfo.isGuild) then
			local offset = Val(lineInfo.itemIndexOffset) or 0
			local count = Val(lineInfo.numSpellBookItems) or 0
			for slot = offset + 1, offset + count do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
				local actionID = item and Val(item.actionID)
				local name = item and Val(item.name)
				if item and Val(item.itemType) == SPELL_ITEM and not Val(item.isPassive) and not Val(item.isOffSpec)
					and actionID and name and name ~= "" then
					local spellID = Val(item.spellID) or actionID
					local subName = Val(item.subName)
					if (not subName or subName == "") and C_Spell.GetSpellSubtext then
						subName = Val(C_Spell.GetSpellSubtext(spellID))
					end
					if not subName or subName == "" then
						RequestSpellText(spellID)
					else
						pendingSpells[spellID] = "done"
					end
					local m = {
						slot = slot,
						actionID = actionID,
						spellID = spellID,
						name = name,
						subName = subName,
						rank = RankNumber(subName),
						level = Val(C_SpellBook.GetSpellBookItemLevelLearned(slot, BANK)) or 0,
						low = Val(C_SpellBook.IsSpellBookItemLowRank(slot, BANK)) and true or false,
					}
					m.locked = IsLocked(m.spellID)
					members[m.actionID] = m
					members[m.spellID] = m
					bySlot[slot] = m
					mapSize = mapSize + 1
					local byLine = groups[m.name]
					if not byLine then
						byLine = {}
						groups[m.name] = byLine
					end
					byLine[line] = byLine[line] or {}
					table.insert(byLine[line], m)
				end
			end
		end
	end

	for name, byLine in pairs(groups) do
		local nameTop, lines, clear = nil, 0, true
		for _, list in pairs(byLine) do
			local top = PickTop(list)
			if top then
				for _, m in ipairs(list) do
					-- Never point an entry at a rank learned at a lower level or a lower rank number.
					local higherRank = m.rank and top.rank and top.rank > m.rank
					local lowerRank = m.rank and top.rank and m.rank >= top.rank
					if m ~= top and not lowerRank and (top.level >= m.level or (top.level == 0 and higherRank)) then
						m.top = top
					end
				end
				nameTop, lines = top, lines + 1
			elseif #list > 1 then
				clear = false
			end
		end
		if clear and lines == 1 then
			topByName[name] = nameTop
		elseif lines > 0 or not clear then
			ambiguous[name] = true
		end
	end
end

local function SameRank(id, m)
	if not m or id == m.actionID or id == m.spellID then return true end
	local rank = RankNumber(SpellSubtext(id))
	local mRank = m.rank or RankNumber(SpellSubtext(m.spellID, m))
	if rank and mRank and rank ~= mRank then return false end
	return true
end

local function FindMember(id)
	local m = members[id]
	if m then return m end
	local base = C_Spell.GetBaseSpell and Val(C_Spell.GetBaseSpell(id))
	m = base and members[base]
	if m and SameRank(id, m) then return m end
	if C_SpellBook.FindSpellBookSlotForSpell then
		local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(id, true, false, false, false)
		slot, bank = Val(slot), Val(bank)
		m = slot and bank == BANK and bySlot[slot] or nil
		if m and SameRank(id, m) then return m end
	end
	return nil
end

local function IsKnownSpell(id)
	if C_SpellBook.IsSpellKnown then
		return Val(C_SpellBook.IsSpellKnown(id, BANK)) and true or false
	end
	return IsPlayerSpell and Val(IsPlayerSpell(id)) and true or false
end

-- A rank that left the spellbook because a higher one replaced it (Warrior/Rogue abilities,
-- or replaced ranks on Forever like Heal): upgrade it to the single known top rank of the same name.
local function ReplacedBy(id)
	if IsKnownSpell(id) then return nil end
	local name = Val(C_Spell.GetSpellName(id))
	local top = name and topByName[name]
	if not top or top.actionID == id or top.spellID == id then return nil end
	local rank = RankNumber(SpellSubtext(id))
	local topRank = top.rank or RankNumber(SpellSubtext(top.spellID, top))
	local level = C_Spell.GetSpellLevelLearned and Val(C_Spell.GetSpellLevelLearned(id)) or 0
	if rank and topRank then
		if rank >= topRank then return nil end
		if level == 0 or top.level == 0 or top.level >= level then return top end
		return nil
	end
	if rank and not topRank then return nil end
	if level > 0 and top.level > level then return top end
end

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

local function Ignored()
	return ns.GetDB().ignored
end

function ns.IsIgnored(id, m)
	local ignored = Ignored()
	return ignored[id] or (m ~= nil and (ignored[m.actionID] or ignored[m.spellID])) or false
end

-- The spell in an action slot, or nil when the slot holds no spell (empty, macro, item...).
-- info.outdated: a higher known rank exists (info.top). info.ignored: that exact rank is ignored.
function ns.GetSlotInfo(slot)
	if dirty then BuildRankMap() end
	local actionType, id, subType = GetActionInfo(slot)
	actionType, id, subType = Val(actionType), Val(id), Val(subType)
	if actionType ~= "spell" or not id or subType == "pet" then return nil end
	local m = FindMember(id)
	local top
	if m then
		top = m.top
	else
		top = ReplacedBy(id)
	end
	return {
		slot = slot,
		spellID = id,
		member = m,
		top = top,
		outdated = top ~= nil,
		ignored = ns.IsIgnored(id, m),
	}
end

-- Outdated slots that will be upgraded, and how many outdated slots are ignored.
function ns.ScanBars()
	local outdated, ignored = {}, 0
	for slot = 1, MAX_ACTION_SLOT do
		local info = ns.GetSlotInfo(slot)
		if info and info.outdated then
			if info.ignored then
				ignored = ignored + 1
			else
				outdated[#outdated + 1] = info
			end
		end
	end
	return outdated, ignored
end

function ns.SpellLabel(id)
	local m = members[id]
	local name = m and m.name or Val(C_Spell.GetSpellName(id)) or ("spell #" .. id)
	local sub = SpellSubtext(id, m)
	if sub and sub ~= "" then return ("%s (%s)"):format(name, sub) end
	return name
end

local function RankLabel(m)
	local sub = SpellSubtext(m.spellID, m)
	if sub and sub ~= "" then return sub end
	return "highest rank"
end

local function IgnoredSuffix(n)
	return n > 0 and (" (%d ignored)"):format(n) or ""
end

-- Tooltip lines for the Update button.
function ns.DescribePending(tooltip)
	local outdated, ignored = ns.ScanBars()
	if #outdated == 0 then
		tooltip:AddLine("All action bar spells are at their highest known rank" .. IgnoredSuffix(ignored) .. ".", 0.6, 0.6, 0.6, true)
		return
	end
	for i, info in ipairs(outdated) do
		if i > MAX_LISTED then
			tooltip:AddLine(("...and %d more"):format(#outdated - MAX_LISTED), 0.6, 0.6, 0.6)
			break
		end
		tooltip:AddLine(("%s -> %s"):format(ns.SpellLabel(info.spellID), RankLabel(info.top)), 1, 1, 1)
	end
	if ignored > 0 then
		tooltip:AddLine(("%d ignored slot%s left as they are."):format(ignored, Plural(ignored)), 0.6, 0.6, 0.6)
	end
end

--------------------------------------------------------------------------------
-- Dual spec
--
-- Each spec has its own action bars and only the active spec's bars can be read or changed, so a
-- rank learned in one spec leaves the other spec's bars behind. DB.rankSerial counts the new ranks
-- automatic update has seen and DB.specSeen[spec] the count when that spec's bars were last updated:
-- a spec that is behind gets caught up when you switch to it. While a switch swaps the bars nothing
-- is placed: a button changed then could land on the other spec's bar.
--------------------------------------------------------------------------------

local settling = false			-- a spec switch is swapping the bars
local settleStart, lastChange = 0, 0
local lastSpecKey				-- active spec at the previous look, to notice a switch without a spec event
local manualAfterSwitch = false	-- Update was clicked while the bars were swapping

local function SafeCall(fn)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn)
	if ok then return Val(v) end
	return nil
end

-- Talent group (dual spec) and specialization, with whichever API the client has.
local function ActiveSpec()
	local info = C_SpecializationInfo
	local group = SafeCall(info and info.GetActiveSpecGroup) or SafeCall(GetActiveSpecGroup) or SafeCall(GetActiveTalentGroup)
	local spec = SafeCall(info and info.GetSpecialization) or SafeCall(GetSpecialization)
	return group, spec
end

local function SpecKey()
	local group, spec = ActiveSpec()
	if not group and not spec then return nil end
	return tostring(group or 0) .. ":" .. tostring(spec or 0)
end

local function MarkSpecCurrent()
	local key = SpecKey()
	if key then
		local db = ns.GetDB()
		db.specSeen[key] = db.rankSerial
	end
end

-- True when a rank was learned since the active spec's bars were last updated. Without a spec API
-- every switch counts as behind once a rank has been learned.
local function SpecBehind()
	local db = ns.GetDB()
	if db.rankSerial == 0 then return false end
	local key = SpecKey()
	return not key or (db.specSeen[key] or 0) < db.rankSerial
end

--------------------------------------------------------------------------------
-- Upgrade
--------------------------------------------------------------------------------

local function PickUp(top)
	ClearCursor()
	-- Same call as dragging the spell out of the spellbook.
	C_SpellBook.PickupSpellBookItem(top.slot, BANK)
	if Val(GetCursorInfo()) ~= "spell" then
		ClearCursor()
		C_Spell.PickupSpell(top.actionID)
	end
	return Val(GetCursorInfo()) == "spell"
end

local function PlaceAll(outdated)
	local groups, order, placed = {}, {}, 0
	for _, info in ipairs(outdated) do
		if PickUp(info.top) then
			PlaceAction(info.slot)
			ClearCursor()	-- PlaceAction hands the old rank back on the cursor
			local _, id = GetActionInfo(info.slot)
			id = Val(id)
			if id and (id == info.top.actionID or id == info.top.spellID) then
				placed = placed + 1
				local key = info.spellID .. ":" .. info.top.actionID
				local g = groups[key]
				if not g then
					g = { from = info.spellID, to = info.top, count = 0 }
					groups[key] = g
					order[#order + 1] = g
				end
				g.count = g.count + 1
			end
		end
	end
	return placed, order
end

local function CursorBusy()
	return Val(GetCursorInfo()) or Val(SpellIsTargeting())
end

-- Automatic update never asks the player to try again: it waits for the cursor, then gives up quietly.
local waitingForCursor = false

local function RetryWhenCursorFree(tries)
	C_Timer.After(AUTO_RETRY_DELAY, function()
		if not CursorBusy() then
			waitingForCursor = false
			ns.UpgradeAll(true)
		elseif tries < AUTO_RETRIES then
			RetryWhenCursorFree(tries + 1)
		else
			waitingForCursor = false
		end
	end)
end

-- "Fade (Rank 4) -> Rank 5, Flash Heal (Rank 5) -> Rank 6", for the one line of an automatic update.
local function DescribeChanges(order)
	local parts = {}
	for i, g in ipairs(order) do
		if i > MAX_CHAT_LISTED then
			parts[#parts + 1] = ("and %d more"):format(#order - MAX_CHAT_LISTED)
			break
		end
		parts[#parts + 1] = ("%s -> %s"):format(ns.SpellLabel(g.from), RankLabel(g.to))
	end
	return table.concat(parts, ", ")
end

-- auto: started by automatic update, which only speaks when it changes something, in one line.
-- spec: automatic catch-up of the bars of the spec you just switched to.
function ns.UpgradeAll(auto, spec)
	if settling then
		if not auto then
			manualAfterSwitch = true
			ns.Print("Your action bars are still changing after the spec switch. The update will run in a moment.")
		end
		return	-- automatic update looks again when the switch settles
	end
	if InCombatLockdown() then
		if auto then
			ns.pendingUpgrade = ns.pendingUpgrade or "auto"
		else
			ns.pendingUpgrade = true
			ns.Print("Can't change action bars in combat. The update will run when combat ends.")
		end
		return
	end
	if CursorBusy() then
		if not auto then
			ns.Print("Your cursor is busy. Drop what you're holding and try again.")
		elseif not waitingForCursor then
			waitingForCursor = true
			RetryWhenCursorFree(1)
		end
		return
	end
	BuildRankMap()	-- always start from a fresh read of the spellbook
	local outdated, ignored = ns.ScanBars()
	MarkSpecCurrent()	-- this spec's bars have now seen every rank learned so far
	if #outdated == 0 then
		if not auto then
			ns.Print("All action bar spells are already at their highest known rank" .. IgnoredSuffix(ignored) .. ".")
		end
		return
	end

	local ok, placed, order = pcall(PlaceAll, outdated)
	ClearCursor()
	if not ok then
		ns.Print("|cffff4040the client refused to change an action slot:|r " .. tostring(placed))
		return
	end

	if auto then
		-- Never asks the player to try again: what is left shows on the Update button.
		if placed > 0 then
			ns.Print(("Updated %d button%s%s: %s."):format(placed, Plural(placed),
				spec and " on this spec's bars" or "", DescribeChanges(order)))
		end
		C_Timer.After(RESCAN_DELAY, function() ns.RequestRefresh() end)
		return
	end

	for _, g in ipairs(order) do
		ns.Print(("%s -> %s (%d button%s)"):format(ns.SpellLabel(g.from), RankLabel(g.to), g.count, Plural(g.count)))
	end
	ns.Print(("Updated %d action slot%s to the highest known rank%s."):format(placed, Plural(placed), IgnoredSuffix(ignored)))

	-- A slot may refuse the change (for example on a form page): count the slots that still hold the
	-- rank they had. Slots outdated by something else in the meantime (a rank learned a moment ago,
	-- bars swapped by a spec switch) are not refusals.
	C_Timer.After(RESCAN_DELAY, function()
		ns.RequestRefresh()
		if settling then return end
		local left = 0
		for _, info in ipairs(outdated) do
			local _, id = GetActionInfo(info.slot)
			if Val(id) == info.spellID then left = left + 1 end
		end
		if left > 0 then
			ns.Print(("|cffffd040%d action slot%s could not be updated.|r Switch to that form or stance and try again."):format(left, Plural(left)))
		end
	end)
end

--------------------------------------------------------------------------------
-- Automatic update
--------------------------------------------------------------------------------

local known			-- [actionID] = true: spellbook spells at the last look, nil before the first one
local learnedAt		-- GetTime() of the last look that found a new spell

-- True when the spellbook holds a spell it did not hold at the previous call. The first call only
-- records the spellbook, so nothing is upgraded at login or when the option is turned on.
local function LearnedSpell()
	BuildRankMap()
	local before, learned = known, false
	known = {}
	for _, m in pairs(bySlot) do
		known[m.actionID] = true
		if before and not before[m.actionID] then learned = true end
	end
	return learned and next(before) ~= nil
end

-- Runs a moment after the spellbook changed or a rank text loaded.
function ns.AutoUpdate()
	local db = ns.GetDB()
	if not db.autoUpdate then
		known, learnedAt = nil, nil
		return
	end
	-- Looked at again when the spec switch settles or when combat ends.
	if settling or InCombatLockdown() then return end
	if LearnedSpell() then
		learnedAt = GetTime()
		db.rankSerial = db.rankSerial + 1	-- the other spec's bars are behind from now on
	end
	-- A new rank can show up before its rank text: keep looking for a few seconds.
	if learnedAt and GetTime() - learnedAt <= AUTO_SETTLE then
		ns.UpgradeAll(true)
	end
end

function ns.SetAutoUpdate(on)
	local db = ns.GetDB()
	db.autoUpdate = on and true or false
	-- Nothing changes when it is turned on, on this spec or the other one.
	db.rankSerial = 0
	wipe(db.specSeen)
	known, learnedAt = nil, nil
	if on then
		ns.AutoUpdate()	-- records the spellbook as it is now
		ns.Print("Automatic update on: your action bars will be updated each time you learn a new rank.")
	else
		ns.Print("Automatic update off.")
	end
	ns.RequestRefresh()
end

--------------------------------------------------------------------------------
-- Spec switch: wait for the bars to settle, then catch them up
--------------------------------------------------------------------------------

local function FinishSwitch()
	settling = false
	local db = ns.GetDB()
	if db.autoUpdate then
		-- The new spec's talent spells are not newly learned ranks: only record the spellbook.
		LearnedSpell()
	end
	if manualAfterSwitch then
		manualAfterSwitch = false
		ns.UpgradeAll()
	elseif db.autoUpdate and SpecBehind() then
		ns.UpgradeAll(true, true)
	end
	ns.RequestRefresh()
end

local function CheckSettled()
	local now = GetTime()
	local quiet = now - lastChange
	if quiet >= SPEC_SETTLE or now - settleStart >= SPEC_SETTLE_MAX then
		FinishSwitch()
	else
		C_Timer.After(SPEC_SETTLE - quiet, CheckSettled)
	end
end

-- The active spec changed (or the client says it may have): the bars are being swapped.
function ns.OnSpecSwitch()
	local now = GetTime()
	lastChange = now
	lastSpecKey = SpecKey() or lastSpecKey
	if settling then return end
	settling, settleStart = true, now
	C_Timer.After(SPEC_SETTLE, CheckSettled)
end

-- The bars or the spellbook changed: a switch in progress is not over yet, or a switch just started
-- and the client fired no spec event for it (the spec API says the active spec changed).
function ns.NoteSwitchActivity()
	local key = SpecKey()
	if key and lastSpecKey and key ~= lastSpecKey then
		ns.OnSpecSwitch()
		return
	end
	lastSpecKey = key or lastSpecKey
	if settling then lastChange = GetTime() end
end

function ns.PrintScan()
	local outdated, ignored = ns.ScanBars()
	if #outdated == 0 then
		ns.Print("Nothing to update" .. IgnoredSuffix(ignored) .. ".")
		return
	end
	for _, info in ipairs(outdated) do
		ns.Print(("slot %d: %s -> %s"):format(info.slot, ns.SpellLabel(info.spellID), RankLabel(info.top)))
	end
	ns.Print(("%d action slot%s can be updated%s."):format(#outdated, Plural(#outdated), IgnoredSuffix(ignored)))
end

--------------------------------------------------------------------------------
-- Ignore list
--------------------------------------------------------------------------------

function ns.ToggleIgnoreSlot(slot)
	local info = slot and ns.GetSlotInfo(slot)
	if not info then
		ns.Print("Only spells can be ignored.")
		return
	end
	local ignored = Ignored()
	local m = info.member
	if ns.IsIgnored(info.spellID, m) then
		ignored[info.spellID] = nil
		if m then
			ignored[m.actionID] = nil
			ignored[m.spellID] = nil
		end
		ns.Print("No longer ignoring " .. ns.SpellLabel(info.spellID) .. ".")
	else
		ignored[m and m.actionID or info.spellID] = true
		ns.Print("Now ignoring " .. ns.SpellLabel(info.spellID) .. " on all action bars.")
	end
	ns.RequestRefresh()
end

function ns.PrintIgnored()
	if dirty then BuildRankMap() end
	local labels = {}
	for id in pairs(Ignored()) do
		labels[#labels + 1] = ns.SpellLabel(id)
	end
	if #labels == 0 then
		ns.Print("No ignored ranks.")
		return
	end
	table.sort(labels)
	ns.Print("Ignored ranks: " .. table.concat(labels, ", "))
end

function ns.ClearIgnored()
	local n = 0
	for _ in pairs(Ignored()) do n = n + 1 end
	wipe(Ignored())
	ns.Print(("Stopped ignoring %d rank%s."):format(n, Plural(n)))
	ns.RequestRefresh()
end

function ns.PrintStatus()
	local db = ns.GetDB()
	local outdated, ignored = ns.ScanBars()
	local names = {}
	for name in pairs(ambiguous) do names[#names + 1] = name end
	table.sort(names)
	ns.Print(("version %s, saved data %s, session %d."):format(ns.VERSION, ns.loadedFromDisk and "loaded from disk" or "new", db.sessions))
	ns.Print(("%d spellbook spells read, %d action slot%s to update%s."):format(mapSize, #outdated, Plural(#outdated), IgnoredSuffix(ignored)))
	ns.Print("Automatic update is " .. (db.autoUpdate and "on." or "off."))
	local group, spec = ActiveSpec()
	if group or spec then
		ns.Print(("Active spec: talent group %s, specialization %s."):format(tostring(group or "-"), tostring(spec or "-")))
	else
		ns.Print("Active spec: not reported by this client, every spec switch is checked.")
	end
	if #names > 0 then
		ns.Print("Left alone (several spells share the name): " .. table.concat(names, ", "))
	end
end

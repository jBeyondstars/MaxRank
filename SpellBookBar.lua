-- SpellBookBar: the Update / Ignore / Highlight buttons in the spellbook footer.
--
-- The strip is a child of PlayerSpellsFrame.SpellBookFrame, so it only shows on the Spellbook tab.
-- It sits left of the page controls: under the frame it would cover the action bars.

local ADDON, ns = ...

local BUTTON_WIDTH, BUTTON_HEIGHT, GAP = 96, 22, 4
local PAGING_GAP = 12
local FALLBACK_X, FALLBACK_Y = 85, 45	-- used if the page controls are missing

local bar, updateButton, ignoreButton, highlightButton

local function ShowTooltip(button, title, text, extra)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(title)
	GameTooltip:AddLine(text, 1, 1, 1, true)
	if extra then extra(GameTooltip) end
	GameTooltip:Show()
end

local function MakeButton(name, label, onClick, onEnter)
	local b = CreateFrame("Button", name, bar, "UIPanelButtonTemplate")
	b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	b:SetText(label)
	b:SetMotionScriptsWhileDisabled(true)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", onEnter)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

function ns.AttachSpellBook()
	local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	if bar or not book then return end

	bar = CreateFrame("Frame", "MaxRankSpellBookBar", book)
	bar:SetSize(BUTTON_WIDTH * 3 + GAP * 2, BUTTON_HEIGHT)
	local paging = book.PagedSpellsFrame and book.PagedSpellsFrame.PagingControls
	if paging then
		bar:SetPoint("RIGHT", paging, "LEFT", -PAGING_GAP, 0)
		bar:SetFrameLevel(paging:GetFrameLevel() + 1)
	else
		bar:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", FALLBACK_X, FALLBACK_Y)
	end

	updateButton = MakeButton("MaxRankUpdateButton", "Update", function() ns.UpgradeAll() end, function(self)
		ShowTooltip(self, "Update spell ranks",
			"Replaces every spell on your action bars that is below the highest rank you know. Macros and items are never changed.",
			ns.DescribePending)
	end)
	updateButton:SetPoint("LEFT")

	ignoreButton = MakeButton("MaxRankIgnoreButton", "Ignore", function() ns.TogglePickMode() end, function(self)
		ShowTooltip(self, "Ignore ranks",
			"Click, then click a spell on your action bars to keep that exact rank, for example Flash Heal (Rank 1). It is never upgraded, on any bar. Click it again to stop ignoring it. Right-click, Esc or closing the spellbook ends this mode.")
	end)
	ignoreButton:SetPoint("LEFT", updateButton, "RIGHT", GAP, 0)

	highlightButton = MakeButton("MaxRankHighlightButton", "Highlight", function() ns.ToggleHighlight() end, function(self)
		ShowTooltip(self, "Highlight outdated spells",
			"Makes every action button below the highest known rank glow. Ignored ranks show a padlock. Closing the spellbook turns it off.")
	end)
	highlightButton:SetPoint("LEFT", ignoreButton, "RIGHT", GAP, 0)

	-- Closing the spellbook ends Highlight and ignore mode. Checked a frame later: minimizing or
	-- maximizing the book hides it and shows it again in the same pass.
	EventRegistry:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.Hide", function()
		C_Timer.After(0, function()
			if not book:IsVisible() then ns.EndModes() end
		end)
	end, bar)

	bar:SetScript("OnShow", ns.RequestRefresh)
	ns.RequestRefresh()
end

function ns.RefreshSpellBookBar()
	if not bar then return end
	local wanted = ns.GetDB().showBar and not IsGamepadUI()
	bar:SetShown(wanted)
	if not wanted or not bar:IsVisible() then return end

	local outdated = ns.ScanBars()
	local n = #outdated
	updateButton:SetText(n > 0 and ("Update (%d)"):format(n) or "Update")
	updateButton:SetEnabled(n > 0)

	local picking = ns.IsPickMode()
	ignoreButton:SetText(picking and "Done" or "Ignore")
	if picking then ignoreButton:LockHighlight() else ignoreButton:UnlockHighlight() end

	local lit = ns.IsHighlight()
	highlightButton:SetText(lit and "Highlight: On" or "Highlight")
	if lit then highlightButton:LockHighlight() else highlightButton:UnlockHighlight() end
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
	-- Runs now if the spellbook is already loaded, otherwise when it loads.
	EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", ns.AttachSpellBook)
end

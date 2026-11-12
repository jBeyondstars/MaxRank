-- SpellBookBar: the Update and Auto buttons and the ... menu in the spellbook footer.
--
-- The strip is a child of PlayerSpellsFrame.SpellBookFrame, so it only shows on the Spellbook tab.
-- It sits left of the page controls: under the frame it would cover the action bars.
-- The spellbook can be narrow and the strip grows to the left, towards the edge of the page, so
-- it stays short: Update only shows while a spell is outdated, and Ignore and Highlight share the
-- ... button, which opens a menu.

local ADDON, ns = ...

local UPDATE_WIDTH, AUTO_WIDTH, MENU_WIDTH = 96, 76, 48
local IGNORE_WIDTH = 60	-- the ... button on a client without menus, where it is the Ignore button
local BUTTON_HEIGHT, GAP = 22, 4
local PAGING_GAP = 12
local FALLBACK_X, FALLBACK_Y = 85, 45	-- used if the page controls are missing

local UPDATE_TITLE = "Update spell ranks"
local UPDATE_TEXT = "Replaces every spell on your action bars that is below the highest rank you know. Macros and items are never changed."
local IGNORE_TITLE = "Ignore ranks"
local IGNORE_TEXT = "Click a spell on your action bars to keep that exact rank, for example Flash Heal (Rank 1). It is never upgraded, on any bar. Click it again to stop ignoring it. Right-click, Esc or closing the spellbook ends this mode."
local HIGHLIGHT_TITLE = "Highlight outdated spells"
local HIGHLIGHT_TEXT = "Makes every action button below the highest known rank glow. Ignored ranks show a padlock. Closing the spellbook turns it off."

local bar, updateButton, autoButton, menuButton

local function FillTooltip(tooltip, title, text, extra)
	tooltip:SetText(title)
	tooltip:AddLine(text, 1, 1, 1, true)
	if extra then extra(tooltip) end
end

local function ShowTooltip(button, title, text, extra)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	FillTooltip(GameTooltip, title, text, extra)
	GameTooltip:Show()
end

local function MakeButton(name, label, width, onClick, onEnter)
	local b = CreateFrame("Button", name, bar, "UIPanelButtonTemplate")
	b:SetSize(width, BUTTON_HEIGHT)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", onEnter)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

--------------------------------------------------------------------------------
-- ... button: a menu with Ignore and Highlight
--------------------------------------------------------------------------------

local function HasMenu()
	return MenuUtil ~= nil and MenuUtil.CreateContextMenu ~= nil
end

local function SetItemTooltip(item, title, text)
	if item.SetTooltip then
		item:SetTooltip(function(tooltip) FillTooltip(tooltip, title, text) end)
	end
end

local function OpenMenu(owner)
	GameTooltip:Hide()
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("MaxRank")

		local ignore = root:CreateButton("Ignore ranks", function() ns.StartPick() end)
		SetItemTooltip(ignore, IGNORE_TITLE, IGNORE_TEXT)

		local highlight = root:CreateCheckbox("Highlight", function() return ns.IsHighlight() end, function()
			ns.ToggleHighlight()
			return MenuResponse and MenuResponse.Close	-- the glow is on the action bars, not in the menu
		end)
		SetItemTooltip(highlight, HIGHLIGHT_TITLE, HIGHLIGHT_TEXT)
	end)
end

local function MenuOnClick(self)
	if ns.IsPickMode() then
		ns.StopPick()	-- the button reads Done
	elseif HasMenu() then
		OpenMenu(self)
	else
		ns.StartPick()	-- no menu on this client: the button is Ignore, Highlight stays on /maxrank
	end
end

local function MenuOnEnter(self)
	if ns.IsPickMode() then
		ShowTooltip(self, IGNORE_TITLE, "Click to leave ignore mode.")
	elseif HasMenu() then
		ShowTooltip(self, "MaxRank", "Click to ignore the ranks you want to keep, or to highlight outdated spells.")
	else
		ShowTooltip(self, IGNORE_TITLE, IGNORE_TEXT)
	end
end

--------------------------------------------------------------------------------
-- Strip
--------------------------------------------------------------------------------

function ns.AttachSpellBook()
	local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	if bar or not book then return end

	bar = CreateFrame("Frame", "MaxRankSpellBookBar", book)
	local menuWidth = HasMenu() and MENU_WIDTH or IGNORE_WIDTH
	bar:SetSize(UPDATE_WIDTH + GAP + AUTO_WIDTH + GAP + menuWidth, BUTTON_HEIGHT)
	local paging = book.PagedSpellsFrame and book.PagedSpellsFrame.PagingControls
	if paging then
		bar:SetPoint("RIGHT", paging, "LEFT", -PAGING_GAP, 0)
		bar:SetFrameLevel(paging:GetFrameLevel() + 1)
	else
		bar:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", FALLBACK_X, FALLBACK_Y)
	end

	-- Laid out from the right: Auto and ... stay where they are when Update shows or hides.
	menuButton = MakeButton("MaxRankMenuButton", "...", menuWidth, MenuOnClick, MenuOnEnter)
	menuButton:SetPoint("RIGHT")

	autoButton = MakeButton("MaxRankAutoButton", "Auto", AUTO_WIDTH, function() ns.SetAutoUpdate(not ns.GetDB().autoUpdate) end, function(self)
		ShowTooltip(self, "Automatic update",
			"Runs Update by itself each time you learn a new rank. Ignored ranks are still left alone. Nothing changes when you turn it on: click Update for what is already outdated.")
	end)
	autoButton:SetPoint("RIGHT", menuButton, "LEFT", -GAP, 0)

	updateButton = MakeButton("MaxRankUpdateButton", "Update", UPDATE_WIDTH, function() ns.UpgradeAll() end, function(self)
		ShowTooltip(self, UPDATE_TITLE, UPDATE_TEXT, ns.DescribePending)
	end)
	updateButton:SetPoint("RIGHT", autoButton, "LEFT", -GAP, 0)

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

	-- Update is only there while something is outdated: its showing up is the reminder.
	local outdated = ns.ScanBars()
	local n = #outdated
	updateButton:SetText(("Update (%d)"):format(n))
	if n == 0 and GameTooltip:IsOwned(updateButton) then GameTooltip:Hide() end
	updateButton:SetShown(n > 0)

	-- Done leaves ignore mode.
	local picking = ns.IsPickMode()
	menuButton:SetText(picking and "Done" or HasMenu() and "..." or "Ignore")
	if picking or ns.IsHighlight() then menuButton:LockHighlight() else menuButton:UnlockHighlight() end

	local auto = ns.GetDB().autoUpdate
	autoButton:SetText(auto and "Auto: On" or "Auto")
	if auto then autoButton:LockHighlight() else autoButton:UnlockHighlight() end
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
	-- Runs now if the spellbook is already loaded, otherwise when it loads.
	EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", ns.AttachSpellBook)
end

# MaxRank
![MaxRank](https://raw.githubusercontent.com/jBeyondstars/MaxRank/main/docs/assets/maxrank-curseforge-cover-holy-v2.png)

**Keep every spell on your action bars at its highest rank, in one click or automatically.**

In Forever, learning a new rank at your trainer doesn't change your action bars: your buttons keep casting the old rank until you drag the new one onto every bar yourself. MaxRank does it for you, in one click or by itself each time you learn a rank, lets you keep the low ranks you use on purpose (downranking), and shows at a glance what still needs an upgrade.

![The MaxRank buttons in the spellbook](https://raw.githubusercontent.com/jBeyondstars/MaxRank/main/docs/assets/spellbook-buttons.webp)

## Features

- **Update**: replaces every outdated spell on your action bars with the highest rank you know. Every bar and every page, including stance and form bars you aren't in right now.
- **Auto**: turn it on and Update runs by itself each time you learn a new rank.
- **Ignore**: keep a specific rank on purpose, like *Flash Heal (Rank 1)* for cheap heals. Ignored ranks are never touched, on any bar.
- **Highlight**: outdated spells glow gold on your bars, ignored ones show a padlock.
- **Safe**: never downgrades a spell, never touches macros or items, never changes your bars in combat.
- **Simple**: a few small buttons in your spellbook, nothing to set up.

## How to use

### 1. Open your spellbook

Press **P**. The MaxRank buttons sit at the bottom of the spellbook, next to the page arrows:

- **Update** only shows up when a spell on your bars is outdated.
- **Auto** turns the automatic update on or off.
- **...** opens a small menu with **Ignore ranks** and **Highlight**.

### 2. See what's outdated: Highlight

Click **...** and tick **Highlight**. Every spell on your bars that isn't at its highest rank lights up in gold.

![An outdated spell glowing on the action bar](https://raw.githubusercontent.com/jBeyondstars/MaxRank/main/docs/assets/highlight.png)

Untick it, or close your spellbook, to turn it off.

### 3. Keep the ranks you want: Ignore

Using a low rank on purpose? Protect it before you update:

1. Click **...** and choose **Ignore ranks**.
2. Click the spell on your action bar. It turns grey with a padlock: that exact rank is now kept on all your bars.
3. Changed your mind? Click it again to un-ignore it.
4. When you're done, click **Done** (the **...** button reads *Done* in this mode), right-click, press **Esc** or close your spellbook.

No risk of casting by mistake: while Ignore mode is on, clicking a button never casts the spell.

![An ignored rank, greyed out with a padlock](https://raw.githubusercontent.com/jBeyondstars/MaxRank/main/docs/assets/ignored-rank.png)

### 4. Upgrade everything else: Update

As soon as something is outdated, the **Update** button shows up with the number of buttons it will change, for example *Update (3)*. Hover over it to see the list, then click it.

![The Update tooltip listing the changes](https://raw.githubusercontent.com/jBeyondstars/MaxRank/main/docs/assets/update-tooltip.png)

Each change is printed in your chat, like *Holy Light (Rank 1) -> Rank 2*. When everything is up to date, the button goes away.

**Tip:** after each visit to your class trainer, open your spellbook and click **Update**. Or let MaxRank do it for you, see below.

### 5. Never click again: Auto

Click **Auto**. The button reads *Auto: On*, and from then on MaxRank runs Update by itself each time you learn a new rank, from a trainer, a tome or a quest. Your ignored ranks are still left alone.

Turning Auto on changes nothing right away: click **Update** once for what is already outdated. Click **Auto** again to turn it off.

## Slash commands

Everything also works from the chat:

- `/maxrank update`: upgrade your bars now
- `/maxrank auto on` or `/maxrank auto off`: update by itself each time you learn a new rank
- `/maxrank scan`: list outdated spells without changing anything
- `/maxrank ignore`: turn Ignore mode on or off
- `/maxrank highlight`: turn Highlight on or off
- `/maxrank list`: list your ignored ranks
- `/maxrank clear`: un-ignore every rank
- `/maxrank bar on` or `/maxrank bar off`: show or hide the spellbook buttons
- `/maxrank status`: version and diagnostic info

## Good to know

- **Combat:** action bars can't be changed in combat. Click Update during a fight, or learn a rank with Auto on, and MaxRank updates your bars as soon as combat ends. Ignore mode turns off when combat starts.
- **Auto is off by default** and saved per character.
- **Key bindings** still cast normally in Ignore mode: only mouse clicks are caught.
- **Ignored ranks are saved per character.**
- **Macros are never changed**
- **Bar addons:** Update works with any bar addon.
- Don't use MaxRank together with an addon that upgrades ranks automatically: it would undo your ignored ranks.

## Feedback

Found a bug or have an idea? Open an issue on [GitHub](https://github.com/jBeyondstars/MaxRank).

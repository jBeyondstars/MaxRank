# MaxRank

Keeps your action bars on the highest spell rank you know, for **World of Warcraft: Forever** (Interface 16001).

On Forever, learning a new rank does not change the buttons that still hold the old one. MaxRank upgrades them in one click, or by itself as you learn them, lets you keep the ranks you want (downranking), and shows what is outdated.

<img src="docs/assets/spellbook-buttons.webp" alt="The MaxRank buttons in the spellbook footer" width="600">

The buttons sit in the spellbook footer, left of the page arrows: **Update**, **Auto**, and **...**, which opens a menu with Ignore ranks and Highlight.

## Features

### Update

Replaces every spell on your action bars that is below the highest rank you know. It covers every bar and page, including stance and form pages you are not in. Macros, items and empty slots are never touched, and a spell is never downgraded.

The button says how many slots it will change, for example *Update (3)*, and is greyed out when there is nothing to do. With Auto on, it only shows while something is left to update. Its tooltip lists the changes:

![Update tooltip listing Holy Light (Rank 1) -> Rank 2](docs/assets/update-tooltip.png)

### Auto

Click Auto and MaxRank runs Update by itself each time you learn a new rank (trainer, tome, quest), and prints what it changed. The button then reads *Auto: On*. Click it again to turn it off. Ignored ranks are still left alone.

It is off by default and saved per character. Turning it on changes nothing by itself: click Update for what is already outdated.

### Highlight

Tick Highlight in the **...** menu. Outdated buttons light up with a golden burst, then marching ants and a breathing glow, like a proc:

![An outdated Holy Light glowing on the action bar](docs/assets/highlight.png)

### Ignore

Choose Ignore ranks in the **...** menu, then click a spell on your action bars, for example Holy Light (Rank 1). That exact rank is kept on every bar, while the other ranks of the spell are still upgraded. Click it again to stop ignoring it. The **...** button reads *Done* while ignore mode is on: click it when you are finished. The list is saved per character.

While Highlight or ignore mode is on, ignored ranks are greyed out with a padlock and a blue border:

![An ignored Holy Light rank, greyed out with a padlock](docs/assets/ignored-rank.png)

## Commands

| Command | Effect |
|---|---|
| `/maxrank update` | upgrade outdated spells on your action bars |
| `/maxrank auto on\|off` | update by itself each time you learn a new rank |
| `/maxrank scan` | list outdated spells without changing anything |
| `/maxrank ignore` | toggle ignore mode |
| `/maxrank highlight` | toggle the glow on outdated spells |
| `/maxrank list` | list ignored ranks |
| `/maxrank clear` | stop ignoring every rank |
| `/maxrank bar on\|off` | show or hide the spellbook buttons |
| `/maxrank status` | version, saved data and spellbook details |

## Notes

- Action bars can only change out of combat. An update requested in combat runs when combat ends, and ignore mode closes when combat starts. A rank learned in combat with automatic update on is applied when combat ends.
- In ignore mode, only mouse clicks are intercepted: key bindings still cast normally.
- Closing the spellbook turns Highlight off and ends ignore mode. Esc does both, since it closes the spellbook.
- Most Warrior and Rogue abilities (and some Druid and Paladin ones) replace their previous rank on their own, so there is usually nothing to update for them.
- Don't use it together with Auto Spell Ranks: that addon would upgrade the ranks you ignore.
- Only Blizzard's action bars get the glow and ignore mode. The update itself works on every action slot, whatever bar addon displays it.
- If ignored ranks are lost after a restart, check `/maxrank status`: the session counter must go up and saved data must say "loaded from disk".

## Development

Offline tests run the Lua files against a stubbed WoW API with Python and [lupa](https://pypi.org/project/lupa/):

```
python -m unittest discover -s tests -v
```

# Zuestie

Zygor's leveling guides inside Questie's quest tracker, for WoW Forever.

Zuestie runs Zygor's guide engine with its window hidden and shows the current step as a section at the top of Questie's tracker: step lines with icons, a progress bar and map pins. On the map, a violet "!" marks quests your guide or the next three guides in Zygor's order pick up; yellow "!" are quests the guides skip. Zygor's arrow stays. Your Questie quest list stays as it is.

Beta: expect rough edges.

## Requirements

- WoW Forever
- [Questie](https://www.curseforge.com/wow/addons/questie) with QuestieDB
- Zygor Guide Viewer (Forever)

## Install with WowUp

1. WowUp 2.24 or newer, with your WoW Forever installation selected.
2. Get Addons, then Install from URL.
3. Paste `https://github.com/Yupmoh/Zuestie` and install.

WowUp updates Zuestie like any other addon when a new release comes out.

## Use

- The book button on the step line chooses a guide. The arrows go back a step or skip one.
- Click a step line to point the arrow there or confirm it. Right-click for the guide menu.
- Click the progress bar to switch between quests, steps and XP.

| Command | What it does |
|---|---|
| `/zu` | Guide menu |
| `/zu next`, `/zu back` | Skip or go back a step |
| `/zu zygor` | Turn Zuestie off and get Zygor's own window back |
| `/zu on` | Turn Zuestie on again |
| `/zu status` | Check that Zygor's engine is running |
| `/zu lines` | Print the guide lines with their raw text, for bug reports |
| `/zu quests` | Show which of Questie's "!" belong to your guides and how many are violet |

## Bugs

Open an issue with a screenshot and the output of `/zu status` and `/zu lines`.

## License

GPL-3.0. The violet "!" is a recolored Questie icon (GPL-3.0).

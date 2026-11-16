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

- The book button on the step line chooses a guide; right-click it to hide or show Zygor's arrow. The arrows go back a step or skip one.
- Click a step line to point the arrow there or confirm it. Right-click for the guide menu.
- Click the progress bar to switch between quests, steps and XP.
- Steps that say to use an item get a clickable item button. The buttons appear or move only out of combat; clicking them works in combat.
- On a guide's last step, a "Next guide" line loads the next guide in Zygor's order.
- Quests your guides use get a violet "!" in Questie's quest list too.

## Catch-up

Skipped a zone? When quests ahead in the guide need earlier quests you never did, a violet line under the step says so, for example "Earlier quests needed: 5, from Duskwood & Redridge Mountains (25-27)". Hover it to see the quests.

Click it to catch up. Zygor loads the earlier guide at the first needed quest and skips every step that does not lead to those quests. The line counts down as you turn them in. When the last one is done, you jump back to the step you left.

Zuestie uses Zygor's quest chains and fills the gaps with Questie's prerequisites. Quests for another race or class never count. Click the line again, or type `/zu catchup`, to stop: you go back to the step you left.

While Zuestie is on, Zygor also skips accept steps whose earlier quests you have not done, so it stops sending you to quest givers who have nothing for you.

## Settings

Esc, then Options, then AddOns, then Zuestie (or type `/zu config`). Switch the progress bar, tips, step-line buttons, item buttons, quest-list marks, catch-up line, map pins and violet "!" on or off, choose how many next guides count, and change Zygor's arrow style and size.

## Commands

| Command | What it does |
|---|---|
| `/zu` | Guide menu |
| `/zu next`, `/zu back` | Skip or go back a step |
| `/zu zygor` | Turn Zuestie off and get Zygor's own window back |
| `/zu on` | Turn Zuestie on again |
| `/zu catchup` | Start or stop catching up on earlier quests |
| `/zu status` | Check that Zygor's engine is running |
| `/zu config` | Open the settings |
| `/zu lines` | Print the guide lines with their raw text, for bug reports |
| `/zu quests` | Show which of Questie's "!" belong to your guides and how many are violet |

## Bugs

[Open a bug report](https://github.com/Yupmoh/Zuestie/issues/new?template=bug_report.yml). The form asks for the output of `/zu status` and a screenshot.

## Development

`lua5.1 tests/run.lua` runs the offline checks. GitHub runs them on every push, and a version tag publishes a release only when they pass.

## License

GPL-3.0. The violet "!" is a recolored Questie icon (GPL-3.0).

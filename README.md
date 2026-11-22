# NeedFrame

A loot roll overhaul for **WoW: Forever**. NeedFrame replaces the need/greed/pass popups with clean, modern roll bars, keeps a record of every roll in the dungeon or raid, and hands out (mostly unflattering) titles when the run is over.

> **Beta.** Please [report issues here](https://github.com/bryn-ph/NeedFrame/issues).

## Features

- **Roll bars** in place of Blizzard's popups. Each shows the item and its tooltip, its quality, bind-on-pickup and a countdown, with Need, Greed and Pass buttons. As the group chooses, the bar shows who picked what, grouped by choice and fitted to the line ("Grimbolt 87, You 45 · Lunaria · 2 passed"). Then it shows the winner and their roll.
- **Animations** (optional): bars pop in; when a result comes in a die spins and the numbers flicker before the winner lands with a flash. It's gold if it's yours.
- **Roll Log**: a small dice tab on screen during a run. Click it to slide out everything that's dropped, who won it and with what roll. It pulses when something new drops while it's tucked away.
- **Roll History**: every drop of the current and past runs (the last 20 by default), with everyone's choice and roll.
- **Run Awards** when you leave the instance: Loot Hoarder, Unlucky, Golden Hands, The Saint, Greedy Goblin, Always the Bridesmaid, Asleep at the Wheel, High Roller (Natural 100), Snake Eyes (Critical Fail), Perfectly Average, and Background Character for everyone else. One click posts them to group chat.
- **Test mode**: try it all outside an instance with a fake party, or simulate a whole run to preview the awards.

## Usage

NeedFrame works on its own: the next time something drops in a group, the roll bars appear.

- **Minimap icon**: left-click for settings, right-click for the roll history. Settings are also under *Options → AddOns → NeedFrame*.
- **Move the roll bars**: switch off *Lock position* in settings, or type `/nf unlock`. Drag the gold handle; it snaps to the centre of the screen like Edit Mode. Click **Done** when finished.
- **Try it out**: `/nf test` brings up test rolls with a fake party; `/nf test end` finishes the test run and shows its awards.

| Command | |
|---|---|
| `/nf` | Roll history |
| `/nf options` | Settings |
| `/nf summary` | Awards for the current or last run |
| `/nf end` | End the current run now |
| `/nf test` | Test rolls with a fake party (`more` adds rolls, `end` finishes, `run` simulates a whole dungeon) |
| `/nf unlock` / `/nf lock` | Move the roll bars |
| `/nf log` | Show or hide the Roll Log tab |
| `/nf anim` | Animations on or off |
| `/nf blizzard` | Bring back Blizzard's roll popups |
| `/nf minimap` | Show or hide the minimap icon |
| `/nf help` | All commands |

## Known limitations

- Blizzard's own roll popups are hidden by making them invisible and click-through, not removed, so they may still take up space in the alert stack above your action bars.
- Who-chose-what and roll results come from the game's loot history. If the game withholds them (for example during combat restrictions), bars show your own choice and the result once it's available.
- English only for now.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE).

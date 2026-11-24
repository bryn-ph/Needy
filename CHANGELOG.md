# Changelog

## v0.3.1-beta

`/reload` is enough after updating.

- If you pass, or aren't in a roll, the roll animation no longer plays with the winner's number. The bar just says **You passed** and shows the winner and their roll. The animation now only ever shows your own number.

## v0.3.0-beta

Fully restart the game after updating: this version adds a new file, which `/reload` doesn't load.

- **Flash new roll bars** (off by default; Roll Frame settings): a glow breathes round each roll bar as it appears, so you don't miss one when your bars are tucked away. It takes the item's quality colour, or gold for wishlist items.
- The number that lands on a roll bar is now always your own roll, labelled **You**, when you rolled; the winner and their roll are on the line beside it. It used to show the winner's roll when the game listed you under a different name, or sent your number a moment late.

## v0.2.0-beta

Fully restart the game after updating: this version adds new files, which `/reload` doesn't load.

- **Run Stats**: a second tab on the end-of-run report (now called the Run Report), with the run's totals and a line per player: items won, needs, greeds, passes, missed rolls, and average, highest and lowest roll.
- **Luck**: the Run Stats show how many items each player won against how many even odds would have given them.
- **Wishlist**, with the DungeonJournal addon: right-click an item in its loot lists to add it to your Needy Wishlist. When it comes up for a roll, its bar lights up and a fanfare plays. Kept per character.
- **Wishlist tab** in settings: everything you're tracking, where it drops, and a button to remove it. Wishlist items are also tagged in the Roll Log and Roll History.
- **Removed** the button that posted awards to group chat. Needy no longer sends chat messages.
- The test buttons now live only on the General tab of settings.

## v0.1.0-beta

First public beta.

- **Roll bars** replace Blizzard's need/greed/pass popups: item, quality, bind-on-pickup, countdown and Need/Greed/Pass buttons, with who chose what shown live and fitted to the line, then the winner and their roll.
- **Animations** (optional): bars pop in, and results play the game's own need-roll dice animation.
- **Roll Log**: a button on screen during a run that opens a list of this run's drops, winners and rolls.
- **Roll History** of the current and past runs.
- **Run Awards** when you leave the instance, with a button to post them to group chat. Titles only go to someone who clearly stood out (one each, at most five a run), so a quiet run may have none.
- **Settings** window (minimap icon, `/needy options`, or *Options → AddOns*). Unlocked roll bars snap to the centre of the screen.
- Looks like part of the game: standard game windows, buttons and fonts, and the default roll frame's own need/greed/pass art.
- **Test mode**: `/needy test` for fake rolls with a fake party, `/needy test run` to simulate a whole dungeon.

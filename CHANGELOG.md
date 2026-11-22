# Changelog

## 0.2.1

- The minimum Lockpicking now comes from the mouseover tooltip: in game, the soft target's own tooltip has no lines. Hover a footlocker once and the marker shows its level from then on.

## 0.2.0

- A footlocker the game is soft-targeting (the interact key's target) becomes the objective: the pin jumps to the nearest route point and stays there until the chest is looted.
- The pin goes to the next point not checked this loop. Each visit records whether a chest was there. A point empty on its last 3 visits is passed over for 2 loops. `/fr list` shows the history.
- New marker: a small diamond above the point with the minimum Lockpicking, coloured by whether your skill opens it. It fills and pulses while the chest is detected.
- Detection health on screen: the interact key off, detection limited to interact range, or a range under 15 yards is named, with who changed it and a Fix button (out of combat). Your own settings are saved first and put back by `/fr off` or `/fr restorecvars`.
- Skip keybind. `/fr suggestskip` and `/fr autoskip` (both off) act when you stand near a point with nothing detected. `/fr follow off` stops following detected chests.
- `/fr probe` shows what soft-interact has measured. It prints a chat line per change while on (`/fr probe off`).

## 0.1.7

- `/fr keepinteract` (on by default) puts the interact key back to 3 when something changes it, outside combat, and stops with a message when another addon keeps changing it back.

## 0.1.6

- The on-screen line now starts at the character, is thinner and fainter, and follows the marker every frame.
- Interact key: only `3` (always on) counts as on. `1` is gamepad only, which Plater was found setting.

## 0.1.4

- Interact key check: when Options > Controls > "Enable Interact Key" (`SoftTargetInteract`) is off, a red chat line says so after loading and whenever it changes, naming who turned it off: an addon (caught through `C_CVar.SetCVar`), or the client or settings panel. `/fr fixinteract` turns it back on (not in combat). `/fr interact` shows the last changes.

## 0.1.3

- Fixed: an error on every tick that stopped arrival detection. Waypoint and map positions come back from the client as plain tables and are now read field by field.

- FarmRoute draws its own in-world marker on the navigation anchor (`C_Navigation.GetFrame`), because Blizzard's navigation frame draws nothing on Forever. The marker sits above the point so it never covers the chest, shows the distance in yards, and fades when you are close.
- A fresh install starts running. When the route is stopped, `/fr` says how to start it.

## 0.1.0

- First version: looping routes in SavedVariables, shown with Blizzard's in-world navigation pin (TomTom arrow as an option), advance on arrival or by keybind, optional respawn timers, the route on the world map and a dotted path on the minimap, and an on-screen line to the pin.
- Seed routes for the Angor Fortress footlockers in the Badlands.
- `/fr import` takes TomTom `/way` lines.

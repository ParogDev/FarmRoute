# Changelog

## 0.3.2

- Six new seed routes for Floating Wreckage fishing pools, one per zone: Wetlands and Hillsbrad (Watertight Trunk, tier 2), The Barrens (Iron Bound Trunk, tier 3), Tanaris, Feralas and Stranglethorn (Mithril Bound Trunk, tier 4). The spawn points come from Forever Questlog and are ordered as a loop along the shore. Pick one with `/fr route Wreckage T4 Tanaris`.
- A wreckage spot counts as reached within 20 yd, so you can stand on the shore. Pools can't be detected, so these routes keep no visit history and every spot stays in the loop.
- Existing installs get new seed routes at login. A seed route you deleted stays deleted.

## 0.3.1

- `/fr learn accept` keeps the old path points of any stretch you didn't walk straight through, and says how many it kept. Path points on another continent stay too.
- The learn trail on the world map breaks where the walk had no position on the route's map. It no longer draws a straight line across ground you didn't walk.
- Deleting the current point, or accepting a walk, moves the pin to the next point instead of back to point 1.
- A stored current point that is a path point or a dropped seed moves on to the next chest still in the loop.
- A point added with `/fr add` shows as an unconfirmed (hollow) diamond until a loot lands on it. It still never drops.

## 0.3.0

- Chest spawns are learned from the chests you loot (the loot window names the chest kind). A loot within 8 yd of a learned point moves it to the average of its finds. A loot within 15 yd of a seed point confirms it at the loot spot. Anywhere else within 60 yd of the route it adds a new point where the loop grows least. Further away it belongs to another place and is not learned. `/fr list` shows "learned xN", "unconfirmed" or "dropped".
- Once a route has learned points, a seed point that no loot has confirmed and that was empty on its last 6 visits drops out of the loop. It comes back if a loot lands near it.
- Path points: via-points with no chest. The pin goes through them on the way to the next chest and moves on once you reach or pass each one. The marker shows them as a small ring.
- `/fr learn on` records your walk, a sample every 3 yd. `/fr learn off` suggests path points between the chests you passed and shows them with the trail on the world map. `/fr learn accept` saves them in walking order. `/fr learn discard` drops them.
- World map: chests are diamonds, unconfirmed seeds hollow, path points small squares, dropped seeds faint specks outside the loop.

## 0.2.4

- A chest counts as looted only when the loot window opens for it. A chair taking the soft target no longer moves the route on.
- A visit counts as empty only when detection could work (health OK, out of combat). Otherwise no history entry is made.
- Switching route, `/fr goto` and every pin move reset the point's wait. The chests seen this loop are kept per route.
- `/fr off` in combat puts your soft-target settings back when combat ends. Skips start no respawn timer.

## 0.2.3

- `/fr keepinteract` leaves your own change in Options > Controls alone and only undoes addons. A put-back blocked by combat happens when combat ends. Its log entries now read "FarmRoute (keepinteract)".

## 0.2.2

- Probe chat lines are only for chests of the active route, once per chest every 30 s. Chairs and stools that take the soft target stay in the saved log only.

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

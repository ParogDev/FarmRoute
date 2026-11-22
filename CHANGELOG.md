# Changelog

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

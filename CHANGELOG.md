# Changelog

## 0.1.2

- FarmRoute draws its own in-world marker on the navigation anchor (`C_Navigation.GetFrame`), because Blizzard's navigation frame draws nothing on Forever. The marker sits above the point so it never covers the chest, shows the distance in yards, and fades when you are close.
- A fresh install starts running. When the route is stopped, `/fr` says how to start it.

## 0.1.0

- First version: looping routes in SavedVariables, shown with Blizzard's in-world navigation pin (TomTom arrow as an option), advance on arrival or by keybind, optional respawn timers, the route on the world map and a dotted path on the minimap, and an on-screen line to the pin.
- Seed routes for the Angor Fortress footlockers in the Badlands.
- `/fr import` takes TomTom `/way` lines.

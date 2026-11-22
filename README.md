# FarmRoute

A WoW: Forever addon that walks a looping farming route (chest spawns, herb or ore nodes) one point at a time. The current point is shown with Blizzard's own navigation pin, which floats in the world with a yards readout. When you reach a point, the pin moves to the next one, and the point stays in the route.

- Routes live in SavedVariables: an ordered list of map points that loops.
- The pin moves on when you come within the arrival radius (8 yards by default), or when you press the Next point or Previous point keybind (Options > Keybindings > FarmRoute).
- Respawn timers are optional, per route or per point. A point you have passed is greyed out for that many minutes and skipped until it is up again.
- The route is drawn on the world map, with the current segment in gold. On the minimap it shows as a dotted path when another addon has loaded HereBeDragons-Pins (TomTom, Questie and others embed it).
- An on-screen line can run from the bottom of the screen to the in-world pin.
- If you prefer TomTom's arrow, `/fr mode tomtom` uses it, with arrival clearing off.

Addons can't draw on the ground. The client gives a screen position only for the one super-tracked target, so the route can't be drawn as a 3D path.

It comes with two seed routes: the Battered Footlocker loop (upper floor) and the Dented Footlocker loop (lower floor) at Angor Fortress in the Badlands, from Wowhead's Forever spawn data for objects 179490 and 179492.

## Commands

| Command | What it does |
|---|---|
| `/fr on`, `/fr off` | Start or stop the route (stopping keeps the points) |
| `/fr next`, `/fr prev`, `/fr goto <n>` | Move the pin |
| `/fr route [name]`, `/fr new <name>`, `/fr delroute <name>` | List, switch, create or delete routes |
| `/fr add [label]`, `/fr del [n]`, `/fr list` | Add your position, remove a point, list the points |
| `/fr import` | Paste TomTom `/way` lines (`/way #1418 40.8 26.7 label`) |
| `/fr radius <yards>`, `/fr auto on\|off` | Arrival radius, and whether arriving moves the pin |
| `/fr respawn <minutes> [n]`, `/fr timers reset` | Respawn timers |
| `/fr mode pin\|tomtom`, `/fr line`, `/fr map`, `/fr minimap` | Display options |
| `/fr skip` (or the Skip keybind), `/fr follow on\|off` | Skip the point; follow chests the game soft-targets |
| `/fr suggestskip on\|off`, `/fr autoskip on\|off` | When nothing is detected near a point: say so, or move on |
| `/fr fixinteract`, `/fr restorecvars`, `/fr interact` | Turn chest detection on, put your settings back, show who changed the interact key |
| `/fr keepinteract on\|off`, `/fr probe [on\|off]` | Keep the interact key on; show what detection has measured |

## Development

Lua 5.1, no build step. `luacheck .`, `busted`, `stylua --check .` (the scaffolding's `tools\lua.ps1 all -Path AddOns\FarmRoute` runs all three in Docker).

MIT licence.

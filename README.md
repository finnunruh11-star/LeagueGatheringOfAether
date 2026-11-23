# CusOba - Custom MOBA Sandbox

A small top-down MOBA for playing with friends, built around **custom characters**:
drop a folder with a JSON file (and optional sprites) into `characters/` and it's playable.

Godot 4.7 (tested with 4.7.1), GDScript, Compatibility renderer.

## Run it
- Open the folder in Godot 4.7 and press **F5**, or
- `godot --path C:\Users\FinnU\Desktop\CusOba`

**Practice** starts an offline lobby: add bots to either team, pick a map, start.
The *Training Arena* map has dummies that show your DPS.

## Controls
| | |
|---|---|
| Right mouse | move / attack (hold to keep moving) |
| Q W E R | hold to aim (shows range), release to cast. Left click also casts, right click cancels |
| A + left click | attack-move |
| S | stop |
| B | recall to base (4s, cancelled by damage or moving) |
| Y | lock/unlock camera (edge-pan or arrow keys when unlocked), Space = jump to your champion |
| Mouse wheel | zoom |
| Tab | scoreboard |
| Esc | menu |
| Minimap | left click = look there, right click = move there |

Destroy the enemy **Nexus** to win. Towers protect the ones behind them; the Nexus can only be
damaged once all towers of one lane are down. Minions spawn in waves; standing in your fountain
heals you, the enemy fountain kills you. You earn XP from nearby kills and level up (max 18).

## Playing with friends
1. Host: **Host game** (default UDP port 7777). The lobby shows your local IPs.
2. Friends: enter the host's IP, **Join game**.
3. Everyone picks a character and team; the host adds bots if wanted and presses **Start**.

Only the host needs the character files - they're sent to everyone on join.
For play over the internet either forward UDP port 7777 on the host's router, or (easier)
all join the same virtual LAN, e.g. [Tailscale](https://tailscale.com) or ZeroTier, and use the host's VPN IP.
2-4 players is the target; up to 8 can connect. If someone disconnects mid-match a bot takes over.

## Make your own characters
See **[characters/MODDING.md](characters/MODDING.md)** - stats, abilities, the effect building
blocks (projectiles, explosions, dashes, teleports, shields, heals, stuns, slows, DoTs, summons,
traps, knockbacks, beams, zones...), passives and sprites. The five example characters show most of it:

- **Sir Bonk** - melee bruiser (dash, shield, spin, leap-slam, every-3rd-hit stun)
- **Ember** - fire mage (fireball, burning ground, blink, meteor shower; abilities in separate files)
- **Gizmo** - marksman (piercing bolt, hidden bear traps, rocket jump, turret)
- **Mender** - support (heal-or-damage orb, hook, healing zone, team shield)
- **Honk Lord** - a goose. Custom pixel-art sprite sheet and goslings.

Quick test of a character from the command line:
```
godot --path . -- --auto=practice --map=arena --selftest --only=ember
```

## Maps
`maps/*.json`: size, walls (rectangles), spawn, nexus, lanes (lists of points from blue to red),
towers (lane + order: 0 = outermost) and minion wave settings. With `"mirror": true` you only
describe the blue half. Optional `"tower_stats"`, `"nexus_stats"` and
`"minion_stats": {"melee": {...}, "ranged": {...}}` override the default stats (same names as
character stats). See `two_lanes.json`, `bridge.json` and `arena.json`.

## How it works (for tinkering)
- `scripts/game.gd` - lobby, networking (Godot ENet), sends characters to clients
- `scripts/world/world.gd` - a match: spawning, snapshots to clients, waves, rules, input
- `scripts/units/` - Unit base + champion, minion, tower/nexus, summon, dummy
- `scripts/combat/effects.gd` - the effect interpreter behind every ability
- `scripts/content.gd` - loads character/map folders

The host simulates everything; clients send commands and receive ~20 snapshots per second.
Practice mode is just a host without other players.

Testing helpers (command line, after `--`): `--auto=practice|host|join`, `--char=`, `--map=`,
`--bots_blue=N`, `--bots_red=N`, `--autopilot`, `--speed=4`, `--shots=5,10 --shot=prefix`, `--quit_at=20`.

## Known limitations
- No fog of war, items, shop or jungle camps (yet).
- No client-side prediction: on a laggy connection your own movement reacts with your ping.
- Bots are simple and somewhat suicidal.
- Exported builds load `characters/` and `maps/` from the folder next to the executable.

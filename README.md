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
| Ctrl + Q W E R | spend a skill point (or click the **+** above an ability) |
| 1 - 6 | use item actives (aimed ones work like abilities) |
| P | shop (in your fountain or while dead; anywhere in Practice). Click an item for details, right-click or double-click to buy, search box + category filters; click one of your items to sell it, drag to reorder |
| A + left click | attack-move |
| S | stop |
| B | recall to base (4s, cancelled by damage or moving) |
| Y | lock/unlock camera (edge-pan or arrow keys when unlocked), Space = jump to your champion |
| Mouse wheel | zoom |
| Tab | scoreboard |
| Esc | menu |
| F1 / F2 / F3 / F4 | Practice only: level up / +1000 gold / reset cooldowns & mana / max ability ranks |
| Minimap | left click = look there, right click = move there |

Destroy the enemy **Nexus** to win. Towers protect the ones behind them; the Nexus can only be
damaged once all towers of one lane are down. Minions spawn in waves; standing in your fountain
heals you and refills mana, the enemy fountain kills you.

- **Levels & abilities:** XP from nearby kills, max level 21. Abilities start at rank 0: every level up
  to 18 gives a skill point. Q/W/E go to rank 5, R to rank 3 (at levels 6/11/16). Levels 19-21 only
  give stats.
- **Stats & mana:** health, mana (casters only - abilities cost mana), attack damage, ability power,
  attack speed, armor, magic resist, crit, ability haste, penetration, life steal/omnivamp, tenacity,
  move speed... shown in the bottom-left panel.
- **Gold & items:** you start with 500 gold and earn it over time, from last-hitting minions (22/16),
  champion kills (300, assists share 150) and towers (150 for the team). The shop has ~180 League of
  Legends items from patches 10.23-13.24 (mythics, legendaries, components, boots, potions, elixirs,
  jungle items) with their stats and effects; recipes subtract owned components, only one Mythic and
  one pair of boots. Sell for 70%.
- **Fog of war:** you only see what your team sees (champions, minions, towers, wards; walls block
  sight). The host can turn it off in the lobby; the Training Arena has none.

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

Ember shows explicit per-rank numbers (`[70, 105, 140, 175, 210]`); the others scale automatically.

## Items
`items/*.json` - one file per item, same effect system as abilities (passives are triggers, actives
are like abilities). See the "Items" section of MODDING.md. Test items without playing:
```
godot --headless --path . -- --auto=practice --map=arena --itemtest=kraken_slayer,sheen --char=gizmo --steps=attack:4,cast:q,stats
```

Quick test of a character from the command line:
```
godot --path . -- --auto=practice --map=arena --selftest --only=ember
```

## Maps
`maps/*.json`: size, walls (rectangles), spawn, nexus, lanes (lists of points from blue to red),
towers (lane + order: 0 = outermost) and minion wave settings. With `"mirror": true` you only
describe the blue half. Optional `"tower_stats"`, `"nexus_stats"` and
`"minion_stats": {"melee": {...}, "ranged": {...}}` override the default stats (same names as
character stats). Also `"fog": false` (no fog of war), `"start_gold"`, `"start_level"`,
`"gold_per_second"`, `"shop_anywhere"` and `"cheats"` (F1-F4 online). See `two_lanes.json`, `bridge.json` and `arena.json`.

## Visual effects
Hit impacts, slashes, explosions and smoke use the pixel-art packs in the project root
("Pixel Art VFX Impacts", "Pixel Art VFX - Warlock", "Pixel Art Animations - Slashes"). The sprite
sheets actually used are copied to `assets/vfx/`; the original pack folders have a `.gdignore` so Godot
doesn't import their hundreds of extra files. Effects are listed in `scripts/vfx/vfx.gd`, and characters
can choose them per ability (see MODDING.md, "Visual effects"). Everything else (rings, trails,
particles, telegraphs, the map art) is drawn procedurally.

## How it works (for tinkering)
- `scripts/game.gd` - lobby, networking (Godot ENet), sends characters to clients
- `scripts/world/world.gd` - a match: spawning, snapshots to clients, waves, rules, input
- `scripts/units/` - Unit base + champion, minion, tower/nexus, summon, dummy
- `scripts/combat/effects.gd` - the effect interpreter behind every ability
- `scripts/content.gd` - loads character/map/item folders
- `scripts/world/fog.gd` - fog of war (vision, wall occlusion, fog rendering)
- `scripts/ui/hud.gd`, `shop.gd`, `item_ui.gd` - in-match UI

The host simulates everything; clients send commands and receive ~20 snapshots per second.
Practice mode is just a host without other players.

Testing helpers (command line, after `--`): `--auto=practice|host|join`, `--char=`, `--map=`,
`--bots_blue=N`, `--bots_red=N`, `--autopilot`, `--speed=4`, `--shots=5,10 --shot=prefix`, `--quit_at=20`,
`--fog=0`, `--itemtest=...` (see MODDING.md).

## Known limitations
- No jungle camps, smite, brush or summoner spells - jungle items are adapted (they grow from minion kills).
- Item effects are faithful where the effect system allows; a few League mechanics are approximated
  (see the item descriptions in the shop).
- Fog of war is visual + targeting rules; the host still sends every unit's position to clients
  (fine among friends, not cheat-proof).
- No client-side prediction: on a laggy connection your own movement reacts with your ping.
- Bots are simple and somewhat suicidal.
- Exported builds load `characters/` and `maps/` from the folder next to the executable.

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
Default keys - **every key can be changed in Settings** (main menu, lobby, or Esc in a match).
The bottom of the screen always shows your current keys.

| | |
|---|---|
| Right mouse | move / attack (hold to keep moving) |
| Q W E R | hold to aim (shows range), release to cast. Left click also casts, right click cancels |
| Ctrl + Q W E R | spend a skill point (or click the **+** above an ability) |
| D / F | summoner spells (Flash, Ignite... picked in the lobby) |
| 1 - 6 | use item actives (aimed ones work like abilities) |
| P | shop (in your fountain or while dead; anywhere in Practice). Click an item for details, right-click or double-click to buy, search box + category filters; click one of your items to sell it, drag to reorder |
| A | attack-move: attacks the enemy in range closest to the cursor, otherwise walks there attacking whatever comes in range (Settings: closest to you instead, or the classic "A, then left click") |
| S | stop |
| B | recall to base (8s, cancelled by damage or moving) |
| Y or Z | lock/unlock camera (edge-pan or arrow keys when unlocked; speed in Settings), hold Space = center on your champion |
| Mouse wheel | zoom |
| Tab | scoreboard |
| Esc | menu (Resume / **Settings** / leave) |
| F1 / F2 / F3 / F4 | Practice only: level up / +1000 gold / reset cooldowns & mana / max ability ranks |
| Minimap | left click = look there, right click = move there |

**WASD mode** (Settings > Movement): W A S D walk, **left click attacks** the enemy closest to the
cursor (one attack, then you keep walking while you hold a direction), right click still moves/attacks.
Abilities move to Q E R F, summoner spells to Space / Shift, attack-move to X - all changeable.

Destroy the enemy **Nexus** to win. On **Two Lanes**, destroy a lane's turrets and inhibitor to
open up the two Nexus turrets. The Nexus is vulnerable only while at least one inhibitor and both
Nexus turrets are down. A destroyed inhibitor gives the opposing team super minions in that lane
until it respawns five minutes later. On **Bridge**, clear the lane turrets to expose the Nexus.
Your fountain heals and refills mana; the enemy fountain deals damage.

- **Levels & abilities:** XP comes from nearby kills, not elapsed time. The level cap is 21.
  You start with one skill point and earn one per level up to 18; levels 19-21 only give stats. Q/W/E go to rank 5, R to rank 3
  (at levels 6/11/16).
- **Stats & mana:** health, mana (casters only - abilities cost mana), attack damage, ability power,
  attack speed, armor, magic resist, crit, ability haste, penetration, life steal/omnivamp, tenacity,
  move speed... shown in the bottom-left panel.
- **Gold & items:** you start with 500 gold and earn passive gold from 1:50. Melee/caster last hits
  grant 20/14 gold, champion kills grant 300 (assists share 150), and turret kills grant 50 to each
  enemy player. The shop has ~180 League of
  Legends items from patches 10.23-13.24 (mythics, legendaries, components, boots, potions, elixirs,
  jungle items) with their stats and effects; recipes subtract owned components, only one Mythic and
  one pair of boots. Sell for 70%.
- **Fog of war:** you only see what your team sees (champions, minions, towers, wards; walls block
  sight). The host can turn it off in the lobby; the Training Arena has none.
- **Autobuy:** turn it on in the shop (or Settings). Whenever you're in your base or dead, it buys your
  build for that character in order (the item, or its most expensive affordable component). Make a
  build in the shop (Ctrl+click items or "Add to build") - until then it follows a recommended build
  for your character's role. Builds are saved per character.
- **Summoner spells:** pick two in the lobby (next to "Spells"): Flash, Ghost, Heal, Barrier, Exhaust,
  Ignite, Cleanse, Teleport (channel 4s to an allied tower; minions and wards too after 10:00) and
  Smite (there are no jungle camps - it hits minions and pets), plus the ARAM spells Clarity and Mark
  (snowball - recast to dash to whoever it hit). Values are from LoL patch 13.24. They're JSON files
  in `summoners/`, so you can edit them or make your own (see MODDING.md).

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
traps, knockbacks, beams, zones...), passives and sprites. The six example characters show most of it:

- **Sir Bonk** - melee bruiser (dash, shield, spin, leap-slam, every-3rd-hit stun)
- **Ember** - fire mage (fireball, burning ground, blink, meteor shower; abilities in separate files)
- **Gizmo** - marksman (piercing bolt, hidden bear traps, rocket jump, turret)
- **Mender** - support (heal-or-damage orb, hook, healing zone, team shield)
- **Honk Lord** - a goose. Custom pixel-art sprite sheet and goslings.
- **Clorinde** - Genshin Impact's duelist: a recast ability (Night Vigil turns her sword into piercing
  pistol shots, recast to lunge), Bond of Life (healing debt that heal bonuses turn into huge heals),
  a parry that stuns if it blocked a champion, and adaptive AD/AP damage

Ember and Clorinde show explicit per-rank numbers (`[70, 105, 140, 175, 210]`); the others scale automatically.

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
towers (lane + order: 0 = outermost) and minion wave settings. A tower entry can use
`"kind": "inhibitor"` for a lane inhibitor or `"kind": "nexus_turret"` for a base turret.
`"waves": {"rift": true, ...}` enables cannon and super minions. With `"mirror": true` you only
describe the blue half. Optional `"tower_stats"`, `"nexus_stats"` and
`"inhibitor_stats"` and `"minion_stats": {"melee": {...}, "ranged": {...}}` override the default stats (same names as
character stats). Also `"fog": false` (no fog of war), `"start_gold"`, `"start_level"`,
`"gold_per_second"`, `"shop_anywhere"` and `"cheats"` (F1-F4 online). See `two_lanes.json`, `bridge.json` and `arena.json`.

### League-scale balance branch

Health and damage use direct values (no hidden multiplier). One world coordinate unit is the
distance unit for attack range, spell geometry and pathing; movement speed is in units per second.
Basic attacks still measure edge-to-edge using this game's collision radii. The custom maps use
their own layouts: Two Lanes is 12,000 by 6,500 units, Bridge is 6,300 by 1,950, and Training Arena
keeps its compact layout.

Benchmarks include 465 HP melee minions, 284 HP casters, 750-range turrets, 4,000 HP inhibitors,
and a 5,500 HP Nexus. Two Lanes uses the classic 1:05 first wave, a 30-second wave interval, and
cannons that become more frequent later in the match. The [League of Legends Wiki](https://wiki.leagueoflegends.com/en-us/Minion)
is a reference for scale, not a patch lock: custom spells, map layouts, minion growth, and the
existing item catalog are not replicas. Jungle camps, epic monsters, and turret plates are not included.

Run the lane and base siege integration test:

```
godot --headless --path . -- --auto=practice --map=two_lanes --selftest=balance
```

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
- `scripts/ui/hud.gd`, `shop.gd`, `item_ui.gd` - in-match UI; `settings_menu.gd` + `scripts/controls.gd` - settings and key bindings

The host simulates everything; clients send commands and receive ~20 snapshots per second.
Practice mode is just a host without other players.

Testing helpers (command line, after `--`): `--auto=practice|host|join`, `--char=`, `--map=`,
`--bots_blue=N`, `--bots_red=N`, `--autopilot`, `--speed=4`, `--shots=5,10 --shot=prefix`, `--quit_at=20`,
`--fog=0`, `--wasd`, `--autobuy`, `--settings_at=2`, `--itemtest=...` (see MODDING.md).
Settings and key bindings are saved in Godot's user folder (`settings.cfg`; on Windows
`%APPDATA%\Godot\app_userdata\CusOba`).

## Known limitations
- No jungle camps or brush - jungle items are adapted (they grow from minion kills) and Smite hits minions/pets.
- Item effects are faithful where the effect system allows; a few League mechanics are approximated
  (see the item descriptions in the shop).
- Fog of war is visual + targeting rules; the host still sends every unit's position to clients
  (fine among friends, not cheat-proof).
- No client-side prediction: on a laggy connection your own movement reacts with your ping.
- Bots are simple and somewhat suicidal.
- Exported builds load `characters/` and `maps/` from the folder next to the executable.

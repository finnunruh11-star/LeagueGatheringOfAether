# CusOba - Custom MOBA Sandbox

A small top-down MOBA for playing with friends, built around **custom characters**:
drop a folder with a JSON file (and optional sprites) into `characters/` and it's playable.

Godot 4.7 (tested with 4.7.1), GDScript, Compatibility renderer.

## Run it
- Open the folder in Godot 4.7 and press **F5**, or
- `godot --path C:\Users\FinnU\Desktop\CusOba`

**Practice** starts an offline lobby: add bots to either team, pick a map, start.
The *Training Arena* map has dummies that show your DPS.

### Bot difficulty
Each bot in the lobby has a difficulty (the host picks it next to the bot; new bots use the last choice):
- **Brick** - barely plays: slow reactions, no aim prediction, random skills, items and fights.
- **Normal** - a competent player: last hits, trades when it's favorable, leads its skillshots,
  respects turrets, sometimes dodges (human-like reaction time), recalls and builds sensibly.
- **Scripting** - frame-perfect. Reads every visible cast, skillshot, dash, zone and telegraph and
  dodges it (with dashes, blinks, parries, stasis or Flash when walking isn't enough), orb-walks and
  kites at exact range, predicts last hits from every attack in flight, tracks your cooldowns,
  computes kill windows from all abilities/items/summoners after resistances, only dives when it's
  safe, hides behind minions from hooks, adapts its build to your team (boots, resistances,
  anti-heal) and plays the map (defends, pushes while you're dead, groups up to siege).

Bots understand abilities by reading their effects (`scripts/ai/bot_kit.gd`), so custom characters
work too; the bundled ones also have curated builds and skill orders.

## Controls
Default keys - **every key can be changed in Settings** (main menu, lobby, or Esc in a match).
The bottom of the screen always shows your current keys.

**Colorblind mode** (Settings > Accessibility) applies immediately and is saved locally. Your HP
bar is gold, allies are blue, enemies are orange with a diamond next to their bar, and neutral
units are gray. The HUD health bar and ground rings use the same palette.

| | |
|---|---|
| Right mouse | move / attack (hold to keep moving) |
| Q W E R | hold to aim (shows range), release to cast. Left click also casts, right click cancels |
| Ctrl + Q W E R | spend a skill point (or click the **+** above an ability) |
| Shift | show detailed ability numbers and scaling in champion select or while hovering the ability bar |
| D / F | summoner spells (Flash, Ignite... picked in the lobby) |
| 1 - 6 | use item actives (aimed ones work like abilities) |
| P | shop (in your fountain or while dead; anywhere in Practice). Click for details; right-click or double-click to buy, including from the build row. Shift+right-click removes a build entry. |
| A | attack-move: attacks the enemy in range closest to the cursor, otherwise walks there attacking whatever comes in range (Settings: closest to you instead, or the classic "A, then left click") |
| S | stop |
| B | recall to base (8s, cancelled by damage or moving) |
| Y or Z | lock/unlock camera (edge-pan or arrow keys when unlocked; speed in Settings), hold Space = center on your champion |
| Mouse wheel | zoom |
| Tab | hold to show the scoreboard; hover an item to inspect it |
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

### Aether Rift (Summoner's Rift-style)
A 14,800 x 14,800 map laid out like Summoner's Rift: blue base bottom-left, red base top-right
(the red half is the blue half rotated 180 degrees), turrets, inhibitors, Nexus turrets and Nexus at
League's positions, three lanes (top, mid, bot), a river with the Dragon pit (bottom) and Baron pit
(top), and a jungle of winding paths on each side. The shop stands on your fountain platform.
Bots take lanes in the order mid, top, bot, **jungle**, support (`"lane_order"` in the map file);
a bot jungler swaps a summoner spell for Smite and starts with a jungle pet.
- **Brush:** standing in brush hides you from enemies outside it - they need a unit or ward inside
  that same brush to see in. You still see out. Damaging an enemy champion from brush reveals you
  for 2 seconds. Your own team shows faded while in brush. Brush works even with fog of war off.
- **Camps** (from 1:30): Blue Sentinel, Gromp, Murk Wolves (blue's top side), Raptors, Red
  Brambleback, Krugs (bot side), mirrored for red. Monsters fight whoever hits them (the whole camp),
  return home and heal if pulled beyond their leash, grow with the average champion level and give
  gold and experience to the killer's team. Buffs respawn after 5:00, other camps after 2:15.
- **Buffs:** Blue Sentinel grants Crest of Insight (2 min: ability haste, mana regen), Red Brambleback
  Crest of Cinders (2 min: attacks burn and slow, health regen). Killing a holder takes the buff over.
- **Rift Scuttler** (river, from 3:30): doesn't fight; killing it leaves a speed shrine with vision.
- **Dragon** (from 5:00, every 5:00): elemental drakes give the whole team a permanent stacking
  bonus - Infernal (AD/AP), Mountain (armor/MR), Ocean (healing), Cloud (move speed). The 4th drake
  grants that element's Dragon Soul; afterwards the **Elder Dragon** spawns (Aspect of the Elder:
  your damage burns and executes champions below 20% health).
- **Baron Nashor** (from 20:00, every 6:00): Hand of Baron for the living team (3 min: AD/AP,
  4-second recall, nearby minions empowered). Dragon and Baron telegraph breath / acid attacks.
- The minimap shows camps (grey with a countdown while respawning), the top bar the drake count,
  and your buffs plus your team's drakes are shown above the ability bar.

- **Levels & abilities:** XP comes from nearby kills, not elapsed time. The level cap is 21.
  In solo lane, a regular wave plus one melee minion grants level 2. Nearby allies split a fixed
  pool of 120% of the solo XP award. Minions give up long chases and return to their lane.
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
  Smite (600 true damage to a monster, minion or pet - secure buffs, Dragon and Baron), plus the ARAM spells Clarity and Mark
  (snowball - recast to dash to whoever it hit). Values are from LoL patch 13.24. They're JSON files
  in `summoners/`, so you can edit them or make your own (see MODDING.md).

## Rune pages
Choose **Runes** in the lobby to set your primary and secondary paths and three stat shards.
The host can select a bot's name to edit its page. Unedited pages use a preset for the champion's role.
The roster follows Summoner's Rift patch 26.23, with nine additional legacy choices, including
Phase Rush alongside Stormraider's Surge and the live version of Lethal Tempo. Rune effects use
CusOba's combat, shop and vision rules; they aren't exact League reproductions.

Hold **Tab** and click **Rune actions** to use Biscuits, Predator, Minion Dematerializer, or
Unsealed Spellbook. Hexflash uses your normal Flash key while Flash is on cooldown.

## Playing with friends
1. Host: **Host game** (default UDP port 7777). The lobby shows your local IPs.
2. Friends: enter the host's IP, **Join game**.
3. Everyone picks a character and team; the host adds bots if wanted and presses **Start**.

Only the host needs the character files - they're sent to everyone on join. To share a guest's
character, choose **Suggest a character...** in the online lobby and select its folder (the one
containing `character.json`). The host can review it under **Character suggestions** and approve
or decline it. Approved characters appear for everyone right away, including guests who join
later. Approval lasts until the hosted session ends and does not write files to disk.

Suggestions support JSON, PNG and WebP (up to 8 MiB total and 64 files). Use a unique folder name
with letters, digits, underscores or hyphens. Each guest can have one pending suggestion, and
the host can approve up to eight guest characters per session. Only approve characters you trust.
Everyone needs the same game version.

For play over the internet either forward UDP port 7777 on the host's router, or (easier)
all join the same virtual LAN, e.g. [Tailscale](https://tailscale.com) or ZeroTier, and use the host's VPN IP.
2-4 players is the target; up to 8 can connect. If someone disconnects mid-match a bot takes over.

## Make your own characters
See **[characters/MODDING.md](characters/MODDING.md)** - stats, abilities, the effect building
blocks (projectiles, explosions, dashes, teleports, shields, heals, stuns, slows, DoTs, summons,
traps, knockbacks, beams, zones...), passives and sprites. The bundled characters show most of it:

- **Sir Bonk** - melee bruiser (dash, shield, spin, leap-slam, every-3rd-hit stun). Animated 8-direction
  knight sprites with alternating swings, a 3rd-hit "BONK" finisher and an animation per ability.
- **Ember** - fire mage (fireball, burning ground, blink, meteor shower; abilities in separate files)
- **Gizmo** - marksman (piercing bolt, hidden bear traps, rocket jump, turret)
- **Mender** - support (heal-or-damage orb, hook, healing zone, team shield)
- **Honk Lord** - a goose. Custom pixel-art sprite sheet and goslings.
- **Clorinde** - Genshin Impact's duelist: a recast ability (Night Vigil turns her sword into piercing
  pistol shots, recast to lunge), Bond of Life (healing debt that heal bonuses turn into huge heals),
  a parry that stuns if it blocked a champion, adaptive AD/AP damage and a point-and-click ultimate that
  blinks her around the target ten times in a second. 3D-rendered 8-direction sprites with a second
  animation set while her pistol is drawn, afterimages and a lightning-spear dash.
- **Zeri** - Summoner's Rift patch 16.23 recreation, with a separate right-click zap and aimed Q,
  terrain-powered W and E, and R chain lightning. Read the green battery bar below mana.
  Stat growth stops at 18 even on maps that allow levels 19-21.

Zeri's numbers are based on the [16.23 client data](https://raw.communitydragon.org/16.23/game/data/characters/zeri/zeri.bin.json).
She uses CusOba's built-in visuals, older item pool, and collision rules. Wall abilities do not
grant League-specific vision, and pellet timing, wall-ride paths, and unusual on-hit interactions
are approximations. Run her gameplay checks with
`godot --headless --path . -- --auto=practice --map=arena --char=zeri --selftest=zeri`.

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
`maps/*.json`: size, walls, spawn, nexus, lanes (lists of points from blue to red),
towers (lane + order: 0 = outermost) and minion wave settings. A tower entry can use
`"kind": "inhibitor"` for a lane inhibitor or `"kind": "nexus_turret"` for a base turret.
Turrets and the Nexus use larger, team-colored artwork; their collision and combat ranges are unchanged.
`"waves": {"rift": true, ...}` enables cannon and super minions. With `"mirror": true` you only
describe the blue half (copied left-right); `"mirror": "rotate"` copies it rotated 180 degrees
around the centre (diagonal maps - mirrored turrets join the lane they land on). Optional `"tower_stats"`, `"nexus_stats"` and
`"inhibitor_stats"` and `"minion_stats": {"melee": {...}, "ranged": {...}}` override the default stats (same names as
character stats). Also `"fog": false` (no fog of war), `"start_gold"`, `"start_level"`,
`"gold_per_second"`, `"shop_anywhere"` and `"cheats"` (F1-F4 online). See `two_lanes.json`, `bridge.json` and `arena.json`.

Terrain and jungle (see `rift.json`):
- `"walls"`: rectangles `[x, y, w, h]` or polygons `{"poly": [[x, y], ...]}`. Any wall, brush,
  river or camp entry can add `"mirror": false` to appear only once (e.g. walls crossing the mirror line).
- `"brush"`: polygons `[[x, y], ...]` that hide units inside (`"brush_reveal"`: seconds an attacker
  in brush stays revealed, default 2). `"river"`: water polygons (visual; `"river_color"`).
- `"camps"`: `{"kind": "blue" | "red" | "gromp" | "wolves" | "raptors" | "krugs" | "scuttle" | "dragon" | "baron",
  "pos": [x, y]}`, optional `"path"` (Scuttler route), `"first"` / `"respawn"` (seconds). Monster stats
  are in `scripts/units/monster.gd`, camp contents and rewards in `scripts/world/jungle.gd`.
- `"shop"`: where the shop stall is drawn (buying works on the fountain platform). `"lane_width"`:
  drawn half width of the lanes. `"lane_order"`: lane per player slot of a team, `-1` = jungle;
  `"lane_names"` for the lanes.
- `rift.json` is generated by `maps/tools/rift_gen.py` (Python with `shapely` and `pillow`): edit the
  paths, clearings, brush and camps there and rerun it; it also writes a preview image.

### League-scale balance branch

Health and damage use direct values (no hidden multiplier). One world coordinate unit is the
distance unit for attack range, spell geometry and pathing; movement speed is in units per second.
Champion art is nominally 100 units tall. The default champion gameplay, pathing and selection
radii are 65, 35 and 100 units respectively. Left-click a visible unit to see its stats.
A 500-unit basic attack range is measured between gameplay edges. Unbuffed champions
walk at 330-345 world units per second, compared with lane minions at 310.
The default camera zoom is 0.8x. Walking pace, camera zoom, and map dimensions are independent
of spell ranges, dash speeds, and projectile speeds.

Basic attacks have a cancelable windup, committed windup, hit or projectile release, locked recovery,
then cancelable recovery. An out-of-range target cancels early windup or makes a committed attack
miss. Spells with a cast time show a charge ring and a direction cue for aimed casts.
The custom maps keep their own layouts: Two Lanes is 14,400 by 7,800 units,
Bridge is 7,560 by 2,340, and Training Arena is 2,880 by 1,800. Aether Rift is 14,800 by 14,800 with
structures, camps and pits at Summoner's Rift positions.

Benchmarks include 465 HP melee minions, 284 HP casters, 750-range turrets, 4,000 HP inhibitors,
and a 5,500 HP Nexus. Two Lanes uses the classic 1:05 first wave, a 30-second wave interval, and
cannons that become more frequent later in the match. The [League of Legends Wiki](https://wiki.leagueoflegends.com/en-us/Minion)
is a reference for scale, not a patch lock: custom spells, map layouts, minion growth, and the
existing item catalog are not replicas. Camp monsters are tuned so a level 1 champion can clear
them without a jungle item; turret plates and the Rift Herald are not included.

Run the lane and base siege integration test, and the Aether Rift test (layout, brush, jungle):

```
godot --headless --path . -- --auto=practice --map=two_lanes --selftest=balance
godot --headless --path . -- --auto=practice --map=arena --char=ember --selftest=windup
godot --headless --path . -- --auto=practice --map=rift --char=ember --selftest=rift
```

## Visual effects
Hit impacts, slashes, explosions and smoke use the pixel-art packs in the project root
("Pixel Art VFX Impacts", "Pixel Art VFX - Warlock", "Pixel Art Animations - Slashes"). The sprite
sheets actually used are copied to `assets/vfx/`; the original pack folders have a `.gdignore` so Godot
doesn't import their hundreds of extra files. Effects are listed in `scripts/vfx/vfx.gd`, and characters
can choose them per ability (see MODDING.md, "Visual effects"). Everything else (rings, trails,
particles, telegraphs, the map art) is drawn procedurally.

Sir Bonk's sprites come from the "2D HD Character Knight" pack (also `.gdignore`d). Its
`build_sir_bonk.py` (Python + Pillow) crops the sheets he uses into `characters/sir_bonk/knight/`
(lossless WebP, about 3 MB, since characters are sent to every client) and makes his portrait.

Clorinde's sprites are rendered from an original 3D model that Python scripts build, rig and animate in
Blender 4.5 (`characters/clorinde/art/`: model, IK pose solver with cloth/hair simulation, 23
animations, weapon trails and muzzle flashes). `clorinde_render.py` renders the 8 directions and
`clorinde_sheets.py` packs them into `characters/clorinde/sprites/` (lossy WebP) and updates the
sprite block of her character.json. Godot ignores the `.py` files.

All four lane minion types use Blender-rendered PNGs in [assets/minions](./assets/minions),
with separate blue and red palettes. Lane minion sprites and hitbox radii are both 50% larger
than their original sizes. Edit the eight scenes in
[minions.blend](./assets/minions/art/minions.blend) or rebuild them from the project root:

```powershell
blender --background --python-exit-code 1 --python assets\minions\art\build_minions.py
```

The script regenerates both the Blender file and the PNGs, overwriting any manual scene edits.

## How it works (for tinkering)
- `scripts/game.gd` - lobby, networking (Godot ENet), sends characters to clients
- `scripts/world/world.gd` - a match: spawning, snapshots to clients, waves, rules, input
- `scripts/world/map.gd` - map loading (walls, brush, mirroring), pathfinding grid, sight grid; `map_art.gd` draws it
- `scripts/world/jungle.gd` - jungle camps, respawns, buffs, Dragon/Baron/Scuttler rewards
- `scripts/units/` - Unit base + champion, minion, tower/nexus, summon, dummy, monster
- `scripts/ai/` - bot AI: `bot_kit.gd` (reads abilities/items, builds) and `bot_brain.gd` (decisions, the three difficulties)
- `scripts/combat/effects.gd` - the effect interpreter behind every ability
- `scripts/content.gd` - loads character/map/item folders
- `scripts/world/fog.gd` - fog of war (vision, wall occlusion, brush, fog rendering)
- `scripts/ui/hud.gd`, `shop.gd`, `item_ui.gd` - in-match UI; `settings_menu.gd` + `scripts/controls.gd` - settings and key bindings

The host simulates everything; clients send commands and receive ~20 snapshots per second.
Practice mode is just a host without other players.

Testing helpers (command line, after `--`): `--auto=practice|host|join`, `--char=`, `--map=`,
`--bots_blue=N`, `--bots_red=N`, `--bot_difficulty=brick|normal|scripting` (or `--blue_difficulty=` /
`--red_difficulty=`), `--blue_char=a,b` / `--red_char=a,b,c` (bot characters in order), `--autopilot[=difficulty]`,
`--speed=4`, `--shots=5,10 --shot=prefix`, `--quit_at=20`, `--cam=x,y --zoom=0.5` (fixed camera for screenshots),
`--fog=0`, `--wasd`, `--autobuy`, `--settings_at=2`, `--itemtest=...` (see MODDING.md).
AI tests: `--aitest=dodge --difficulty=scripting --char=sir_bonk --shooter=gizmo --slot=q` (how many perfectly
led skillshots hit the bot) and `--aitest=watch` (bot stats and AI time per frame during a match).
Settings and key bindings are saved in Godot's user folder (`settings.cfg`; on Windows
`%APPDATA%\Godot\app_userdata\CusOba`).

## Known limitations
- Only Aether Rift has a jungle and brush; on the other maps jungle items' monster effects also work on
  minions and Smite hits minions/pets. Rift Herald and turret plates are not included.
- Item effects are faithful where the effect system allows; a few League mechanics are approximated
  (see the item descriptions in the shop).
- Fog of war is visual + targeting rules; the host still sends every unit's position to clients
  (fine among friends, not cheat-proof).
- No client-side prediction: on a laggy connection your own movement reacts with your ping.
- Bots see only what their team sees (fog of war); they don't use wards.
- Exported builds load `characters/` and `maps/` from the folder next to the executable.

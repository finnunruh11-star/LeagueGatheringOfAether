# Making characters

Every folder in `characters/` that contains a `character.json` is a playable character.
Copy an existing folder (e.g. `sir_bonk`), rename it, edit the JSON, then press
**Reload content** in the main menu (or restart). Problems (typos, unknown effect types,
bad JSON) are listed on the menu/lobby screen with the file and line.

When you host, your characters are sent to everyone who joins - friends don't need the files.

```
my_character/
  character.json        required
  portrait.png          optional (lobby + HUD)
  spritesheet.png       optional (see "Sprites")
  abilities/zap.json    optional: abilities can live in their own files
  anything.png/.ogg     sprites for projectiles/summons, icons, sounds
```

Lines starting with `//` are treated as comments.

## character.json

```jsonc
{
  "name": "Ember", "title": "The Pyromaniac", "description": "...",
  "color": "#ff7a2f",                       // placeholder body color
  "stats": { "max_hp": 560, "attack_range": 480, ... },   // see Stats
  "per_level": { "max_hp": 70, "ability_power": 12 },     // added every level up
  "attack": { "ranged": true, "projectile_speed": 950, "projectile_color": "#ffb347",
              "projectile_size": 7, "projectile_sprite": "bolt.png", "on_hit": [ ...effects ] },
  "passive": { "name": "...", "description": "...", "icon": "p.png", "triggers": [ ... ] },
  "abilities": { "q": { ... }, "w": "fireball", "e": { ... }, "r": { ... } }
}
```

A string ability (`"w": "fireball"`) loads `abilities/fireball.json`.

Optional `attack` keys (numbers or expressions, checked when each attack starts):
`damage` replaces the attack's damage (default: your AD), e.g. `"0.6 * ad + 0.3 * ap"`;
`damage_type` "physical" (default) / "magic" / "true" (or an expression returning one);
`pierce` (true or an expression) also hits every enemy in a line behind the target for the same damage
(no on-hit), `pierce_range` 350 long and `pierce_width` 60 wide.
A `buff` can swap your basic attack for its duration (see `buff`'s `attack`).

### Stats
Percent stats are fractions (`0.3` = 30%). Regen is per second.

| stat | default | notes |
|---|---|---|
| `max_hp`, `hp_regen` | 650, 1.5 | `hp_regen_percent` adds a % of base regen (items) |
| `max_mana`, `mana_regen` | 0, 0 | **0 mana = manaless**: abilities are free. `mana_regen_percent` like above |
| `attack_damage`, `ability_power` | 60, 0 | |
| `attack_speed` | 0.8 | base attacks/second. `bonus_attack_speed` (items, 0.3 = +30%) multiplies it; capped at `attack_speed_cap` 2.5 |
| `attack_range` | 125 | melee ~70-125, ranged ~450-550 |
| `move_speed` / `move_speed_bonus` | 330 / 0 | flat / percent (soft-capped above 415; final walking speed is 75% of the result, in world units/second) |
| `armor`, `magic_resist` | 20, 30 | reduce physical / magic damage (100 = half). True damage ignores both |
| `crit_chance`, `crit_damage` | 0, 1.75 | basic attacks crit for 175% damage |
| `ability_haste` | 0 | cooldown = base × 100 / (100 + haste) |
| `lethality`, `armor_pen` | 0, 0 | flat (60-100% effective by level) / percent armor ignored |
| `magic_pen`, `magic_pen_percent` | 0, 0 | flat / percent magic resist ignored |
| `lifesteal`, `omnivamp` | 0, 0 | heal % of basic-attack (and on-hit) damage / of all damage |
| `heal_power`, `heal_received` | 0, 0 | boosts heals & shields you give / receive |
| `heal_to_bond` | 0 | while above 0, healing you receive restores no HP; you gain that fraction of it as Bond of Life instead |
| `tenacity`, `slow_resist` | 0, 0 | shortens stuns/roots/silences/slows / weakens slows |
| `size`, `damage_mult`, `damage_taken_mult`, `cooldown_mult` | 1 | fun multipliers (0.5 cooldown_mult = half cooldowns) |
| `vision` | 1350 | sight radius for fog of war (minions 650, turrets 1095, summons 600) |

`per_level` stats define growth (defaults: +100 HP, +3.5 AD, +2 armor, +1 MR, +0.12 regen,
+8 AP, +2.5% attack speed). Each new level applies `0.65 + 0.035 * new_level` times the
listed growth, averaging the listed value over levels 2 through **18**.
All stats can be changed temporarily with the `buff` effect.

### Abilities
```jsonc
{
  "name": "Fireball", "description": "...", "icon": "fireball.png",
  "cooldown": [8, 7.5, 7, 6.5, 6],   // number, per-rank list, or expression
  "cost": [50, 55, 60, 65, 70],      // mana (ignored for manaless champions)
  "cost_type": "mana",               // or "health" (pay HP instead)
  "targeting": "direction",          // direction | point | self | unit | ally
  "range": 900,
  "cast_time": 0,                    // windup in seconds before effects; 0 is instant
  "effects": [ ... ]
}
```
- `direction`: skillshot toward the cursor. `point`: ground target (clamped to range).
- `self`: centered on you. `unit`: enemy under the cursor (must be in range). `ally`: ally (or you) under the cursor.
- At the top level of an ability, the *target* is **you** (except `unit`/`ally` abilities),
  so `{"type": "shield"}` shields yourself. Inside projectiles/areas/zones the target is whoever got hit.

Players hold Q/W/E/R to see the range indicator and release to cast.

#### Recasts
Give an ability a `"recast": { ... }` (any ability keys) to make it castable again for a while:
after casting, the slot turns into the recast for `window` seconds (default 3) - or, with
`"status": "id"`, for as long as you have that status (apply it in the ability's effects) - up to
`charges` times (default 1, `0` = unlimited). Each recast uses its own `cooldown` (default 0.5), also
before the first one. The ability's full cooldown starts when the recast ends (time up, status gone,
no charges left or death). The HUD shows the recast's name with a draining bar. See `clorinde/`.

#### Ranks (leveling abilities)
Everything starts at rank 0 (not castable). You get one skill point per level up to 18 and spend it
with **Ctrl+Q/W/E/R** or the **+** buttons. Q/W/E go to rank 5 (rank N needs level 2N-1, like
LoL), R to rank 3 at levels 6/11/16. Per ability you can change `max_rank` and `unlock_levels`
(e.g. `[1, 2, 3, 4, 5]`).

Any number can be a **per-rank list**: `"amount": [60, 95, 130, 165, 200]` (rank 1..5), and
expressions can use `rank`: `"amount": "[60, 95, 130][rank - 1] + 0.7 * ap"`.
Abilities that use no lists and no `rank` get stronger automatically instead: +25% damage/heal/shield
per rank (+50% for R) and slightly shorter cooldowns. Set `"auto_rank": false` to turn that off.

## Effects

Every effect is `{"type": "...", ...}`. Effects nest: projectiles, areas, zones, traps,
dashes, delays and repeats contain their own effect lists. Any effect may also have:
- `"chance": 0.25` - only happens 25% of the time
- `"if": "t_hp < 0.3 * t_max_hp"` - only happens when the expression is true

### Numbers can be expressions
`"amount": "60 + 0.8 * ap + 0.1 * t_max_hp"`. Variables (`t_` = the current target):

| variable | meaning |
|---|---|
| `ad`, `ap`, `level`, `hp`, `max_hp`, `missing_hp`, `armor`, `mr`, `speed`/`ms`, `size`, `mana`, `max_mana` | your stats |
| `as`, `bonus_as`, `crit`, `ah`, `lethality` | attack speed, bonus attack speed, crit chance, ability haste, lethality |
| `bonus_ad`, `base_ad`, `bonus_hp`, `base_hp`, `bonus_armor`, `bonus_mr` | from items/buffs vs. base (incl. level growth) |
| `ranged`, `melee` | 1 if your basic attack is ranged / melee |
| `t_hp`, `t_max_hp`, `t_missing_hp`, `t_armor`, `t_mr`, `t_mana`, `t_max_mana`, `t_bonus_hp`, `t_ms`, `t_level` | the target's stats |
| `t_champion`, `t_minion`, `t_structure`, `t_ranged` | 1/0 target type |
| `rank` | ability rank (for item/passive triggers: your level) |
| `dist`, `ally`, `i`, `time` | distance to target; 1 if target is an ally; repeat index / trigger count; match time |
| `shield`, `t_shield` | your / the target's current shield amount |
| `in_combat`, `combat_time`, `since_hit`, `since_combat` | champion-combat state (seconds) |
| `moving` | 1 while you are walking |
| `gold`, `kills`, `deaths`, `assists`, `energy`, `legendaries` | your score, Energize stacks (0-100), legendary item count |
| `dmg`, `dtype`, `crit_hit`, `is_attack`, `is_ability`, `is_dot`, `is_aoe` | inside damage triggers: the hit (`dmg` is after armor/MR) |
| `slot` | inside `cast`/`rank_up` triggers: which ability ("q"... compare with `slot == 'r'`) |
| `amount` | inside `heal_ally`/`shield_ally` triggers: how much; inside `cast` triggers: the mana spent |
| `dmg_raw` | inside damage triggers: the hit before armor/MR |
| `cc` | inside `cc_applied` triggers: "stun", "root", "slow", "silence", "knockback" or "pull" |
| `t_self` | 1 if the target is you |
| `at_base` | 1 while you stand in your fountain |
| `t_summon` | 1 if the target is a summon (turrets, wards, pets...) |
| `t_ward` | 1 if the target is a ward |
| `bond`, `t_bond` | your / the target's Bond of Life (in HP, so `bond >= max_hp` means 100%) |

Functions: `has('id')` (you have a status/mark with that id or type), `t_has('id')` (target has it, from
you - or any status of that type like `'stun'`), `t_has_any('id')`, `stacks('id')`, `t_stacks('id')`,
`counter('id')`, `stat('name')`, `t_stat('name')`, `base('name')`, `bonus('name')`, `pre('name')` (a stat
before multipliers, e.g. crit chance before Guinsoo's sets it to 0), `h_stat('name')` (stat of the unit
holding the buff whose trigger runs), `h_hp()`, `h_dist()` (holder's HP / distance to you), `near_allies(r)`, `near_enemies(r)` (champions; `near_enemies(r, 'id')` skips ones carrying your mark 'id'), `near_units(r)`,
`cd('q')` (remaining), `cd_total('r')` (full cooldown of the last cast), `has_item('id')`, `item_count('legendary')`.
Godot math and logic work too (write decimals like `10.0` in `clamp`/`min`/`max` - with whole numbers they return whole numbers): `min`, `max`, `clamp`, `pow`, `sqrt`, `randf()`, `and`, `or`, `not`,
`a if cond else b`, `[10, 20, 30][rank - 1]`.

### On a unit (the current target, or yourself with `"target": "self"`)
| type | keys (defaults) |
|---|---|
| `damage` | `amount` 50, `damage_type` "magic" / "physical" / "true" (or an expression returning one, e.g. `"'physical' if ad > ap else 'magic'"`); `can_crit` (rolls your crit), `attack` (counts as a basic attack: lifesteal, "attacked" triggers), `onhit` (lifesteal applies), `raw` (skips damage modifiers) |
| `heal` | `amount` 50 (boosted by your `heal_power`); `convert` false = not turned into Bond of Life by `heal_to_bond` |
| `bond_of_life` | adds Bond of Life: `amount` (HP), or `set` it (e.g. 0 to clear); capped at `max` (default 200% of the target's max HP) |
| `shield` | `amount` 100, `duration` 3, `damage_type` "all" / "magic" / "physical" (only blocks that type), `decay` (shrinks to 0 over the duration) |
| `stun`, `root`, `silence` | `duration` 1 (shortened by tenacity) |
| `invulnerable`, `stasis`, `untargetable`, `stealth` | `duration` 1. Stasis = invulnerable + untargetable + can't act (Zhonya's) |
| `spellshield` | blocks the next enemy ability hit; `duration` (default: until popped) |
| `grievous` | healing reduction: `amount` 0.4, `duration` 3 |
| `slow` | `amount` 0.3 (0-1), `duration` 2, `decay` (fades out over the duration) |
| `dot` / `hot` | `amount` per second 20, `duration` 3, `interval` 0.5, `damage_type`, `raw` |
| `buff` | `duration` 4, `add` {stat: value}, `multiply` {stat: factor}; stacking: `max_stacks` 5 (+`stacks` per application, `refresh` true) - each stack adds the values again; `hidden` (no buff icon/particles); `attack` {...}: replaces basic-attack keys while it lasts (same keys as the character's `attack`, e.g. `{"ranged": true, "damage": "...", "damage_type": "magic", "on_hit": [...]}` - add `attack_range` with `add`) |
| `mark` | invisible stackable marker for bookkeeping: `id` (required), `duration` 5, `stacks` 1, `max_stacks` |
| `remove` | removes your status with `id` from the target (`any_source`: from anyone), or `status`: "slow" (a whole type) |
| `shield_break` | reduces the target's current shields by `amount` (0.5 = half); with `duration`, shields they gain meanwhile are reduced too |
| `cleanse` | removes stun/root/slow/silence/dot/grievous (`cc_only`: only stun/root/slow/silence) |
| `knockback` | `distance` 220, `duration` 0.25, `from` "origin" (center of the blast / projectile) or "self" |
| `pull` | toward you; `distance` (default: all the way), `duration` 0.25 |
| `swap` | you and the target swap places |
| `mana` | restore `amount` mana (negative drains) |
| `reveal` | the target is visible to your team through fog of war (and stealth) for `duration` 2 |
| `level_up` | the target champion gains a level |
| `xp` | the target champion gains `amount` experience |

Repeated statuses from the same ability refresh instead of stacking. Add `"stack": true` to let
them stack, or `"id": "burn"` to share one status between abilities; `"keep_longer": true` keeps the
longer of the old and new duration when refreshing, and `"persist": true` keeps a status through death. (Marks add a stack each time they are applied.) Enemy spell shields block
ability effects (not basic attacks or item effects).

**Bond of Life** (from Genshin Impact) is healing debt, shown as a crimson strip on the health bar
(outlined once it reaches 100% of max HP). Healing - after `heal_power`, `heal_received` and grievous
wounds - pays it off first and only the rest restores HP, so heal bonuses matter a lot to champions
that heal themselves for more than their Bond. It lasts until paid off (or death). Paying it off
completely fires the `bond_cleared` trigger.

### You / your champion
| type | keys |
|---|---|
| `gold` | `amount` - gives you gold (floating text for you) |
| `counter` | permanent number on your champion (stacks like Mejai's): `id`, `add`, `set`, `mult`, `max`, `min`. Read with `counter('id')` |
| `cooldown` | `slot` "q"/"w"/"e"/"r"/"basic" (q+w+e)/"all", `amount` seconds (or fraction of the remaining time with `"percent": true`), or `"reset": true` |
| `item_cooldown` | `item` id or "all", `amount` / `reset`; or `set`: put this item's active on that cooldown |
| `passive_cooldown` | puts the running trigger (or this item's passive number `passive`) on cooldown `amount` - the item slot shows it |
| `attack_reset` | your next basic attack is ready immediately |
| `modify_damage` | only inside `deal_damage_pre` / `take_damage_pre` triggers: `mult`, `add` change the hit (after armor/MR) |
| `fire_event` | runs your triggers for `event` (default "attack") again on the current target, except the trigger doing it - e.g. "apply on-hit effects twice" |
| `transform` | only in item passives: replace this item with `into` (e.g. Manamune -> Muramana) |

### Movement (you)
| type | keys |
|---|---|
| `dash` | `to` "aim" (toward the target point) / "direction" (full distance) / "back" / "target"; `distance` 350, `min_distance` (aim dashes go at least this far), `speed` 1400, `on_hit` [effects on each unit passed through], `stop_on_hit`, `on_end` [effects at the landing spot] |
| `teleport` | `to` "pos" (default) / "target" (behind the target) / "home" |

### Spawners
| type | keys |
|---|---|
| `projectile` | `speed` 900, `range` (ability range), `radius` 12, `color`, `sprite`, `count` 1, `spread` (degrees, 360 = ring), `pierce` false/true/number, `homing`, `returns` (boomerang), `through_walls`, `affects` "enemies"/"allies"/"all", `hits_structures`, `on_hit` [...], `on_end` [... when it stops] |
| `area` | instant explosion. `at` "pos" (default) / "self" / "target", `radius` 150, `delay` (shows a warning circle first), `scatter` (random offset), `angle` (cone toward the aim, e.g. 70), `affects`, `hits_structures`, `color`, `show` (false = no blast visual, for auras), `filter` "champions"/"minions"/"summons"/"non_champions", `offset` (move the center forward along your aim), `exclude_target`, `exclude_self`, `sort` "nearest"/"farthest"/"lowest_hp"/"lowest_hp_percent"/"champions_first"/"champions_lowest_hp"/"random", `max_targets`, `wards` (also hit wards - normally abilities ignore them), `effects` [... per unit inside] |
| `beam` | instant line from you. `length` (ability range), `width` 70, `delay`, `affects`, `effects` [...] |
| `zone` | lingering circle. `radius` 160, `duration` 4, `interval` 0.5, `follow` (true = aura around you), `affects`, `effects` [... each tick], `on_expire` [...] |
| `trap` | `radius` 60, `duration` 30, `arm_time` 0.6, `hidden` true, `effects` [... on the unit that steps on it] |
| `summon` | `name`, `count` 1, `duration` 10, `stats` {max_hp, attack_damage, attack_range, attack_speed, move_speed, armor, vision...}, `ranged`, `stationary` (turret), `size` 0.7, `sprite`, `on_hit` [...], `on_death` [...], `ward` (a ward: 1 damage per basic attack, ignored by minions and towers), `reveal` (sees stealthed enemies in its vision), `limit` (max of these per owner; the oldest disappears) |

Abilities don't hurt towers unless you set `"hits_structures": true`.

### Visual effects (optional)
Every hit plays an impact animation automatically (melee champions slash in a color matching the
character, ranged attacks spark, abilities burst in the effect's `color`). You can pick specific ones:
- on `damage`: `"vfx": "fire"` - the impact played on each unit hit
- on `area`: `"vfx": "fire"` - the explosion style
- in `attack`: `"hit_vfx": "fire"` - your basic-attack impacts

Names: `spark`, `star`, `twinkle`, `splat`, `burst`, `claw`, `streaks` (these are tinted with the
effect's `color`), `fire`, `poison`, `star_red`, `claw_red`, `streaks_red`, `magic`, `smoke`,
`slash` (palette picked from the color) or a specific slash like `slash2_c4` (styles 1-3, palettes c1
lime, c2 red, c3 violet, c4 orange, c5 cyan), and `none`. They come from `assets/vfx/`.

### Flow & fun
| type | keys |
|---|---|
| `delay` | `time` 1, `effects` [...] |
| `repeat` | `count` 3, `interval` 0.25, `effects` [...] |
| `random` | `options`: [effect or [effects], ...] - one is picked |
| `text` | floating text: `text`, `color`, `size` 28, `at` "target" |
| `vfx` | a visual only: `kind` "ring" (`at`, `radius`) / "blast" (`at`, `radius`, `vfx`) / "line" or "beam" (`from`, `to`, `width`) |
| `sound` | `file` (.wav/.ogg in your folder), `volume` (dB), `at` "self" |

## Passive triggers
```jsonc
"triggers": [
  { "on": "attack", "every": 3, "effects": [ ... ] },        // every 3rd basic attack hit
  { "on": "interval", "interval": 5, "effects": [ ... ] },
  { "on": "lethal", "cooldown": 90, "effects": [ {"type": "heal", "amount": 300} ] }
]
```
Triggers accept `every`, `chance`, `cooldown` (number/expression/per-level list) and `if`.
Inside a trigger, `rank` is your level, so `[..18 values..]` lists scale with level.

| event | when / the target |
|---|---|
| `attack` | your basic attack hit something (target = victim; `crit_hit`) |
| `attack_launch` | you started a basic attack (before it lands) |
| `energized` | an attack hit when Energize was full (100 stacks from moving/attacking; it resets) |
| `cast` | you cast an ability (`slot`) |
| `deal_damage_pre` | you are about to damage something (`dmg`, use `modify_damage`) |
| `deal_damage` | you damaged something (`dmg`, `dtype`, `is_attack`, `is_ability`, `is_dot`, `is_aoe`, `crit_hit`). Damage from triggers/items doesn't fire it again unless the trigger has `"procs": true` |
| `take_damage_pre` | you are about to take damage (target = attacker, `modify_damage`) |
| `take_damage` / `damaged` | you took damage (target = attacker) |
| `attacked` | an enemy basic attack hit you (target = attacker) |
| `low_health` | you got hit below `threshold` (0.3) of max HP |
| `lethal` | you would die: effects run and you survive with at least 1 HP - give it a cooldown! |
| `kill`, `champion_kill` | you got the kill (target = victim) |
| `takedown` | you killed or assisted on a champion (`amount` 1 = kill, 0 = assist) |
| `death` | you died |
| `heal_ally`, `shield_ally` | you healed/shielded another champion (target = ally, `amount`) |
| `cc_applied` | you stunned/rooted/slowed/silenced/knocked back an enemy champion (`cc`) |
| `cc_received` | an enemy champion's effect stunned/rooted/slowed/silenced/knocked you back (target = them, `cc`) |
| `buff_ally` | you gave a `buff` to another allied champion (target = ally) |
| `spellshield_pop` | your spell shield blocked something |
| `blocked` | your `invulnerable`/`stasis` stopped an enemy's damage or crowd control (target = them; `dmg`... or `cc`) - parries |
| `bond_cleared` | your Bond of Life was fully paid off |
| `interval` | every `interval` seconds |
| `dash` | you dashed, blinked or teleported (target = you, `pos` = destination) |
| `spawn`, `level_up`, `rank_up`, `buy`, `item_used` | as named |

**Triggers on statuses**: a `buff` or `mark` can carry `"triggers": [...]` that work while it lasts
(any event except `interval`). They run as whoever applied the status, aimed at the event's target;
`"target": "holder"` (and `"at": "holder"`) means the unit carrying the status. Extra keys:
`"consume": true` (status ends after firing) or `"charges": 3`. Example - an ability
that makes your next 3 attacks burn:
```jsonc
{"type": "buff", "target": "self", "id": "hot_hands", "duration": 6, "triggers": [
  {"on": "attack", "charges": 3, "effects": [{"type": "dot", "amount": 20, "duration": 2}]}
]}
```

# Items

Every `.json` file in `items/` (subfolders allowed) is an item; the file name is its id. The host
sends its items to everyone, like characters. Press **P** (or the Shop button) to shop - in your
fountain or while dead (anywhere in Practice / the Training Arena). Keys **1-6** use item actives
(hold to aim, release to use). Selling refunds 70%.

```jsonc
{
  "name": "Kraken Slayer",
  "cost": 3000,                    // TOTAL cost; owned components are subtracted automatically
  "rarity": "legendary",           // basic | epic | legendary | mythic | boots | starter | consumable | jungle | transform
  "from": ["noonquiver", "cloak_of_agility", "recurve_bow"],   // recipe (item ids)
  "tags": ["Damage", "CriticalStrike", "AttackSpeed"],          // shop categories / bot builds
  "group": "lifeline",             // optional: only one item per group (string or list)
  "stack": 5,                      // optional: how many fit in one slot (potions)
  "charges": 2,                    // optional: uses per item; refilled in your fountain ("refill": false to disable); kept when empty
  "min_level": 9,                  // optional: level needed to buy (elixirs)
  "display": "counter('glory')",   // optional: number shown on the item slot (stacks)
  "limit": 1,                      // optional: max owned (default 1 for legendary/mythic/boots/jungle, else unlimited)
  "buyable": true,                 // false = can only be obtained via "transform"
  "stats": {"attack_damage": 40, "bonus_attack_speed": 0.3, "crit_chance": 0.2},
  "stats_mult": {"ability_power": 1.4},        // multiplies your total stat (Rabadon's)
  "mythic_stats": {"magic_pen": 5},            // mythic only: per other legendary item you own
  "description": "Extra rules text shown in the shop (optional).",
  "passives": [ { "name": "Bring It Down", "description": "...", "on": "attack", "every": 3, "effects": [ ... ] } ],
  "active": { "name": "Stasis", "description": "...", "cooldown": 120, "targeting": "self", "range": 600,
              "consume": false, "effects": [ ... ] },
  "short": "KS", "color": "#4fd6ff", "icon": "icons/kraken.png"   // optional looks: "icon" = picture; else a small drawn picture picked by
  // "glyph" (sword, greatsword, dagger, spear, bow, axe, hammer, book, rune, staff, wand, shield, armor, cloak, boots, potion,
  // crystal, gem, ring, orb, heart, ...; default: guessed from the tags) in "color"; setting "short" alone shows letters instead
}
```
- You can own only **one mythic**. Mythic items' `mythic_stats` are granted per other legendary.
- Only one item of each `group`, and one pair of `boots` (rarity boots).
- Stats may be expressions, re-evaluated 4 times a second: `"ability_power": "5 * counter('glory')"`.
- `passives` are triggers (see Passive triggers) plus `name`/`description`. A passive without `on` is
  just text. Passives with the same `"unique": "name"` don't stack (default: per item, so two copies
  of one item don't double up). Inside them `rank` = your level, so 18-entry lists scale by level.
- `active` works like an ability (targeting, range, indicator) and is used with keys 1-6 (`"while_dead": true` allows using it while dead; `"requires": "t_minion"` - an expression checked before the cooldown starts, e.g. only usable on minions).
  Consumables (`"consume": true`, default for rarity consumable) lose one charge per use.
- `{"type": "transform", "into": "muramana"}` inside a passive upgrades the item in place.

Examples in `items/`: `sheen.json` (Spellblade with marks), `kraken_slayer.json` (every 3rd attack,
per-target ramp), `thornmail.json` (`attacked`), `ludens_tempest.json` (`deal_damage` + chained area),
`rabadons_deathcap.json` (`stats_mult`), `zhonyas_hourglass.json` / `health_potion.json` (actives).

## Testing items
```
godot --headless --path . -- --auto=practice --map=arena --itemtest=kraken_slayer,sheen
    [--char=gizmo] [--enemy=sir_bonk] [--ally=mender] [--enemy_items=thornmail] [--level=11]
    [--steps=attack:4,cast:q,item:0,hurt:300,hurtm:300,enemy_attack:3,lowhp,kill,move:400,buy:boots,wait:2,stats]
```
prints every damage/heal/status/proc with the item that caused it. All steps are listed at the top of
`scripts/itemtest.gd` (allies, minions, crowd control, assists, levels, HP/mana, fountain...).
Item slots show passive cooldowns and `display` numbers automatically. In a Practice match you can
also press **F1** (level up), **F2** (+1000 gold), **F3** (reset cooldowns, refill mana), **F4** (max ranks).

## Sprites
Without a sprite you get a colored circle. Options:
- `"sprite": "body.png"` - one static image.
- A sheet with animations (rows of equal-size frames; facing right unless `faces_left`):
```jsonc
"sprite": {
  "sheet": "spritesheet.png", "frame_width": 32, "frame_height": 32,
  "scale": 2.4, "offset": [0, -10],
  "animations": {
    "idle":   {"row": 0, "frames": 2, "fps": 3},
    "walk":   {"row": 1, "frames": 4, "fps": 10},
    "attack": {"row": 2, "frames": 3, "fps": 14, "loop": false},
    "cast":   {"row": 3, "frames": 2, "fps": 8},
    "death":  {"row": 4, "frames": 3, "fps": 6}
  }
}
```
Only `idle` is required. See `honk_lord/` for a working example.

## Testing your character
Run the self-test, which casts each ability at a training dummy and prints damage dealt:
```
godot --path <project folder> -- --auto=practice --map=arena --selftest --only=my_character
```
For combos, the item test harness also works without items and logs every hit, heal, status and
Bond of Life change, e.g. Clorinde's Night Vigil loop (`behind` puts a dummy behind the enemy to
check piercing, `cast:e` during Vigil recasts):
```
godot --headless --path . -- --auto=practice --map=arena --itemtest= --char=clorinde --level=11
    --steps=behind,cast:e,attack:2.4,cast:e,stats
```
Or just pick Practice, choose the Training Arena map and hit the dummies (they show DPS).

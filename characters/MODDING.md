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

### Stats
`max_hp` 650, `hp_regen` 3 (per second), `move_speed` 330, `attack_damage` 60,
`attack_speed` 0.8 (attacks/second), `attack_range` 125 (melee ~70-125, ranged ~450-550),
`armor` 20 (reduces non-true damage: 100 armor = half damage), `ability_power` 0,
`lifesteal` 0 (0.2 = heal 20% of damage dealt), `size` 1 (scales body and hitbox),
`damage_mult` 1, `damage_taken_mult` 1, `cooldown_mult` 1 (0.5 = half cooldowns).
All of these can be changed temporarily with the `buff` effect.

### Abilities
```jsonc
{
  "name": "Fireball", "description": "...", "icon": "fireball.png",
  "cooldown": 5,              // number or expression, e.g. "10 - 0.3 * level"
  "targeting": "direction",   // direction | point | self | unit | ally
  "range": 900,
  "cast_time": 0,             // optional wind-up (you stand still)
  "effects": [ ... ]
}
```
- `direction`: skillshot toward the cursor. `point`: ground target (clamped to range).
- `self`: centered on you. `unit`: enemy under the cursor (must be in range). `ally`: ally (or you) under the cursor.
- At the top level of an ability, the *target* is **you** (except `unit`/`ally` abilities),
  so `{"type": "shield"}` shields yourself. Inside projectiles/areas/zones the target is whoever got hit.

Players hold Q/W/E/R to see the range indicator and release to cast.

## Effects

Every effect is `{"type": "...", ...}`. Effects nest: projectiles, areas, zones, traps,
dashes, delays and repeats contain their own effect lists. Any effect may also have:
- `"chance": 0.25` - only happens 25% of the time
- `"if": "t_hp < 0.3 * t_max_hp"` - only happens when the expression is true

### Numbers can be expressions
`"amount": "60 + 0.8 * ap + 0.1 * t_max_hp"`. Variables:

| variable | meaning |
|---|---|
| `ad`, `ap`, `level`, `hp`, `max_hp`, `missing_hp`, `armor`, `speed`, `size` | your stats |
| `t_hp`, `t_max_hp`, `t_missing_hp`, `t_armor` | the target's stats |
| `dist` | distance between you and the target |
| `ally` | 1 if the target is on your team, else 0 |
| `i` | repeat index / passive trigger count |
| `time` | match time in seconds |

Godot math functions work too: `min`, `max`, `clamp`, `pow`, `sqrt`, `randf()`, `randf_range(a, b)`...

### On a unit (the current target, or yourself with `"target": "self"`)
| type | keys (defaults) |
|---|---|
| `damage` | `amount` 50, `damage_type` "magic" / "physical" / "true" (true ignores armor) |
| `heal` | `amount` 50 |
| `shield` | `amount` 100, `duration` 3 |
| `stun`, `root`, `silence`, `invulnerable` | `duration` 1 |
| `slow` | `amount` 0.3 (0-1), `duration` 2 |
| `dot` / `hot` | `amount` per second 20, `duration` 3, `interval` 0.5 |
| `buff` | `duration` 4, `add` {stat: value}, `multiply` {stat: factor} |
| `cleanse` | removes stun/root/slow/silence/dot |
| `knockback` | `distance` 220, `duration` 0.25, `from` "origin" (center of the blast / projectile) or "self" |
| `pull` | toward you; `distance` (default: all the way), `duration` 0.25 |
| `swap` | you and the target swap places |

Repeated statuses from the same ability refresh instead of stacking. Add `"stack": true` to let
them stack, or `"id": "burn"` to share one status between abilities.

### Movement (you)
| type | keys |
|---|---|
| `dash` | `to` "aim" (toward the target point) / "direction" (full distance) / "back" / "target"; `distance` 350, `speed` 1400, `on_hit` [effects on each unit passed through], `stop_on_hit`, `on_end` [effects at the landing spot] |
| `teleport` | `to` "pos" (default) / "target" (behind the target) / "home" |

### Spawners
| type | keys |
|---|---|
| `projectile` | `speed` 900, `range` (ability range), `radius` 12, `color`, `sprite`, `count` 1, `spread` (degrees, 360 = ring), `pierce` false/true/number, `homing`, `returns` (boomerang), `through_walls`, `affects` "enemies"/"allies"/"all", `hits_structures`, `on_hit` [...], `on_end` [... when it stops] |
| `area` | instant explosion. `at` "pos" (default) / "self" / "target", `radius` 150, `delay` (shows a warning circle first), `scatter` (random offset), `angle` (cone toward the aim, e.g. 70), `affects`, `hits_structures`, `color`, `effects` [... per unit inside] |
| `beam` | instant line from you. `length` (ability range), `width` 70, `delay`, `affects`, `effects` [...] |
| `zone` | lingering circle. `radius` 160, `duration` 4, `interval` 0.5, `follow` (true = aura around you), `affects`, `effects` [... each tick], `on_expire` [...] |
| `trap` | `radius` 60, `duration` 30, `arm_time` 0.6, `hidden` true, `effects` [... on the unit that steps on it] |
| `summon` | `name`, `count` 1, `duration` 10, `stats` {max_hp, attack_damage, attack_range, attack_speed, move_speed, armor}, `ranged`, `stationary` (turret), `size` 0.7, `sprite`, `on_hit` [...], `on_death` [...] |

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
| `cooldown` | `slot` "q"/"w"/"e"/"r"/"all", `amount` seconds to reduce, or `"reset": true` |
| `text` | floating text: `text`, `color`, `size` 28, `at` "target" |
| `sound` | `file` (.wav/.ogg in your folder), `volume` (dB), `at` "self" |

## Passive triggers
```jsonc
"triggers": [
  { "on": "attack", "every": 3, "effects": [ ... ] },        // every 3rd basic attack hit
  { "on": "interval", "interval": 5, "effects": [ ... ] },
  { "on": "lethal", "cooldown": 90, "effects": [ {"type": "heal", "amount": 300} ] }
]
```
Events: `attack` (target = unit hit), `cast` (after you cast), `damaged` (target = attacker),
`low_health` (`threshold` 0.3), `kill`, `champion_kill`, `interval`, `spawn`, `level_up`,
`lethal` (you would die: effects run and you survive with at least 1 HP - give it a cooldown!).
Triggers also accept `chance`, `cooldown` and `if`.

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
Or just pick Practice, choose the Training Arena map and hit the dummies (they show DPS).

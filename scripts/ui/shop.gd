class_name Shop
extends PanelContainer
## League-style item shop. P or the HUD's "Shop (P)" button toggles it, Esc closes it.
##   left   - search box and stat categories (an item must match every selected category)
##   middle - all buyable items grouped by rarity with your price (owned components are
##            subtracted): click shows details, right-click or double-click buys
##   right  - details: recipe tree (owned parts green), what it builds into, Buy button
##   bottom - your item slots: select one to sell it, drag one onto another to swap them
## Buying and selling go through world.send_command, so the host validates everything.
## Test flags: --open_shop  --shop_select=<id>  --shop_gold[=times]  --shop_buy=<id>,<id>

const PANEL_SIZE := Vector2(1100, 660)
const RAISE := 80.0   # keeps the panel above the HUD's ability bar
const REFRESH_EVERY := 0.2
const ICON := 44.0
const CELL := Vector2(52, 66)
const HEAD_H := 30.0

const BG := Color(0.05, 0.06, 0.08, 0.95)
const BG_INNER := Color(0.075, 0.085, 0.11, 0.9)
const BORDER := Color(0.3, 0.32, 0.38)
const BORDER_DIM := Color(0.19, 0.21, 0.26)
const GOLD := Color(1, 0.85, 0.4)
const TEXT := Color(0.9, 0.91, 0.94)
const MUTED := Color(0.58, 0.61, 0.68)
const RED := Color(1, 0.42, 0.38)
const GREEN := Color(0.4, 0.88, 0.45)
const ORANGE := Color(1, 0.68, 0.38)
const PURPLE := Color(0.78, 0.45, 1.0)

## [rarity, title, note]; rarities not listed here end up in "other".
const SECTIONS := [
	["starter", "Starter", ""], ["consumable", "Consumables", ""], ["boots", "Boots", "one pair"],
	["basic", "Basic", ""], ["epic", "Epic", ""], ["legendary", "Legendary", ""],
	["mythic", "Mythic", "you can own one"], ["jungle", "Jungle", ""], ["other", "Other", ""],
]
## [label, item tags, stat keys]: an item is in a category if it has any of those tags or stats.
const CATEGORIES := [
	["Attack Damage", ["Damage"], ["attack_damage"]],
	["Critical Strike", ["CriticalStrike"], ["crit_chance", "crit_damage"]],
	["Attack Speed", ["AttackSpeed"], ["bonus_attack_speed"]],
	["On-Hit", ["OnHit"], []],
	["Armor Penetration", ["ArmorPenetration"], ["lethality", "armor_pen"]],
	["Life Steal & Vamp", ["LifeSteal", "SpellVamp"], ["lifesteal", "omnivamp"]],
	["Ability Power", ["SpellDamage"], ["ability_power"]],
	["Mana & Regen", ["Mana", "ManaRegen"], ["max_mana", "mana_regen", "mana_regen_percent"]],
	["Magic Penetration", ["MagicPenetration"], ["magic_pen", "magic_pen_percent"]],
	["Health & Regen", ["Health", "HealthRegen"], ["max_hp", "hp_regen", "hp_regen_percent"]],
	["Armor", ["Armor"], ["armor"]],
	["Magic Resist", ["SpellBlock", "MagicResist"], ["magic_resist"]],
	["Ability Haste", ["AbilityHaste", "CooldownReduction"], ["ability_haste"]],
	["Move Speed", ["NonbootsMovement", "Boots"], ["move_speed", "move_speed_bonus"]],
	["Tenacity", ["Tenacity"], ["tenacity", "slow_resist"]],
	["Heal & Shield Power", [], ["heal_power"]],
	["Actives", ["Active"], []],
	["Utility", ["Slow", "Aura", "Stealth", "Vision"], []],
]
const IGNORED_TAGS := ["Consumable", "Jungle"]   # already rarity sections

var world: World

var _font: Font
var _items_ref = null       # the Game.items dictionary the catalog was built from
var _catalog: Array = []    # every buyable item id
var _by_rarity := {}        # section key -> [ids by cost]
var _names := {}            # id -> [lowercase name, only its letters and digits]
var _cats: Array = []       # [{name, ids: {id: true}, button}]
var _active := {}           # selected category indices
var _query := ""
var _query_sq := ""         # the query with only letters and digits ("rabadons" finds "Rabadon's")
var _state := {}            # id -> [your price, check_buy() reason or ""]
var _owned := {}            # id -> number of slots holding it
var _gold := 0
var _gold_shown := -1
var _sig := ""
var _tick := 0.0
var _sel := ""
var _sel_slot := -1
var _msg_t := 0.0
var _last_notice := ""
var _auto_pending := false
var _auto_t := 0.0

var _gold_label: Label
var _search: LineEdit
var _clear_btn: Button
var _cat_box: VBoxContainer
var _scroll: ScrollContainer
var _sections: Array = []
var _no_match: Label
var _details: VBoxContainer
var _placeholder: Label
var _big_icon: BigIcon
var _d_name: Label
var _d_kind: Label
var _d_total: Label
var _d_left: Label
var _recipe_head: Label
var _tree: RecipeView
var _into_head: Label
var _into: IntoRow
var _desc: RichTextLabel
var _reason: Label
var _buy_btn: Button
var _inv: InvRow
var _sell_btn: Button
var _msg: Label


func _ready() -> void:
	visible = false
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	custom_minimum_size = PANEL_SIZE
	theme = _make_theme()
	add_theme_stylebox_override("panel", _box(BG, BORDER, 2, 6, 12))
	_build_ui()
	_place.call_deferred()
	var a: Dictionary = Game.cmdline
	_auto_pending = a.has("open_shop") or a.has("shop_select") or a.has("shop_gold") or a.has("shop_buy")


func toggle() -> void:
	visible = not visible
	if visible:
		_place()
		if not is_same(_items_ref, Game.items):
			_build_catalog()
		var nl := _notice_label()
		_last_notice = nl.text if nl != null else ""
		_sig = ""
		_poll()
	else:
		_search.release_focus()


func is_open() -> bool:
	return visible


func _place() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5 - RAISE
	offset_bottom = PANEL_SIZE.y * 0.5 - RAISE


func _champ() -> Champion:
	if world == null or not is_instance_valid(world.local_champion):
		return null
	return world.local_champion


# ------------------------------------------------------------------ input ---

func _input(event: InputEvent) -> void:
	# Clicking anywhere else (or Esc) leaves the search box so game hotkeys work again.
	if not visible or not _search.has_focus():
		return
	if event is InputEventMouseButton and event.pressed:
		if not _search.get_global_rect().has_point(_search.get_global_mouse_position()):
			_search.release_focus()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_search.release_focus()


func _cell_clicked(view: Cells, cell: Dictionary, right: bool, double: bool) -> void:
	var id := str(cell.id)
	if view == _inv:
		if right:
			if id != "":
				_buy(id)
			return
		_sel_slot = int(cell.slot)
		if id != "":
			_select(id)
		_update_sell()
		_inv.queue_redraw()
		return
	if id == "":
		return
	if right or double:
		_buy(id)
	if not right:
		_select(id)


func _buy(id: String) -> void:
	var ch := _champ()
	if ch == null or not Game.items.has(id):
		return
	var err := ch.check_buy(id)
	if err != "":
		_flash(err, RED)
		return
	world.send_command("buy", [id])
	_flash("Bought %s" % Game.items[id].name, GREEN)
	_sig = ""
	_poll()


func _sell() -> void:
	var ch := _champ()
	var it = ch.item_def(_sel_slot) if ch != null else null
	if it == null:
		return
	if not ch.can_shop():
		_flash("You can only sell in your base (or while dead)", RED)
		return
	world.send_command("sell", [_sel_slot])
	_flash("Sold %s for %d gold" % [it.name, _sell_value(it)], GOLD)
	_sig = ""
	_poll()


func _swap(a: int, b: int) -> void:
	world.send_command("swap_items", [a, b])
	if _sel_slot == a:
		_sel_slot = b
	elif _sel_slot == b:
		_sel_slot = a
	_sig = ""
	_poll()


static func _sell_value(it: Dictionary) -> int:
	return Champion.sell_value(it)


# -------------------------------------------------------------- updating ---

func _process(delta: float) -> void:
	if _auto_pending:
		_run_auto(delta)
	if not visible:
		return
	var ch := _champ()
	if ch != null and int(ch.gold) != _gold_shown:
		_gold_shown = int(ch.gold)
		_gold_label.text = str(_gold_shown)
	_tick += delta
	if _tick >= REFRESH_EVERY:
		_poll()
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_update_hint()
		else:
			_msg.modulate.a = clampf(_msg_t / 0.6, 0.0, 1.0)


## Cheap check (gold, level, items, where you are) - only redraws when something changed.
func _poll() -> void:
	_tick = 0.0
	var s := _signature()
	if s != _sig:
		_sig = s
		_refresh()
	var nl := _notice_label()
	if nl != null and nl.text != _last_notice:
		_last_notice = nl.text
		if nl.text != "":
			_flash(nl.text, ORANGE)


func _signature() -> String:
	var ch := _champ()
	if ch == null:
		return "none"
	var s := "%d|%d|%d|%d|%d" % [ch.get_instance_id(), int(ch.gold), ch.level, int(ch.can_shop()), int(ch.dead)]
	for inst in ch.items:
		s += "|-" if inst == null else "|%s:%d" % [inst.id, int(inst.n)]
	return s


func _refresh() -> void:
	var ch := _champ()
	_state.clear()
	_owned.clear()
	_gold = int(ch.gold) if ch != null else 0
	for i in Champion.ITEM_SLOTS:
		var inst = ch.items[i] if ch != null else null
		_inv.cells[i].id = str(inst.id) if inst != null else ""
		if inst != null:
			_owned[inst.id] = int(_owned.get(inst.id, 0)) + 1
	for id in _catalog:
		_st(id)
	_gold_shown = _gold
	_gold_label.text = str(_gold)
	for s in _sections:
		s.queue_redraw()
	_inv.queue_redraw()
	_update_details()
	_update_sell()


## [your price, why you can't buy it ("" = you can)], cached until the next refresh.
func _st(id: String) -> Array:
	if not _state.has(id):
		var it = Game.items.get(id)
		var ch := _champ()
		if it == null:
			_state[id] = [0, "Unknown item"]
		elif ch == null:
			_state[id] = [int(it.cost), "You have no champion"]
		else:
			_state[id] = [int(ch.price_for(id).cost), ch.check_buy(id)]
	return _state[id]


func _update_details() -> void:
	var it = Game.items.get(_sel)
	_details.visible = it != null
	_placeholder.visible = it == null
	if it == null:
		return
	var st := _st(_sel)
	var price: int = st[0]
	_d_total.text = "Total %d" % int(it.cost)
	_d_left.text = ("You pay %d" % price) if price > 0 else "Free"
	_d_left.add_theme_color_override("font_color", GOLD if _gold >= price else RED)
	_reason.text = st[1]
	_reason.visible = st[1] != ""
	_buy_btn.disabled = st[1] != ""
	_buy_btn.text = ("Buy for %d gold" % price) if price > 0 else "Buy (free)"
	_tree.mark_owned(_champ())
	_into.queue_redraw()
	_big_icon.queue_redraw()


func _update_sell() -> void:
	var ch := _champ()
	var it = ch.item_def(_sel_slot) if ch != null and _sel_slot >= 0 else null
	if it == null:
		_sell_btn.text = "Sell"
		_sell_btn.disabled = true
		_sell_btn.tooltip_text = "Click one of your items to sell it."
	else:
		_sell_btn.text = "Sell  (+%d gold)" % _sell_value(it)
		_sell_btn.disabled = not ch.can_shop()
		_sell_btn.tooltip_text = "Sell %s for %d%% of its cost." % [it.name, int(Champion.SELL_RATIO * 100.0)]
	_update_hint()


func _update_hint() -> void:
	if _msg_t > 0.0:
		return
	var ch := _champ()
	var col := MUTED
	if ch == null:
		_msg.text = "Waiting for your champion..."
	elif not ch.can_shop():
		_msg.text = "Shop in your fountain (or while dead)"
		col = ORANGE
	else:
		_msg.text = "Select one of your items to sell it - drag to swap slots"
	_msg.add_theme_color_override("font_color", col)
	_msg.modulate.a = 1.0


func _flash(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)
	_msg.modulate.a = 1.0
	_msg_t = 3.0


## The HUD shows the host's "you can't buy that" notices under the shop, so repeat them here.
func _notice_label() -> Label:
	var hud = world.get("hud") if world != null else null
	return (hud.get("notice_label") if hud != null else null) as Label


## Command-line automation for screenshots/tests (see the flags at the top), ~1 s into the match.
func _run_auto(delta: float) -> void:
	if world == null or not world.started or _champ() == null:
		return
	_auto_t += delta
	if _auto_t < 1.0:
		return
	_auto_pending = false
	var a: Dictionary = Game.cmdline
	if a.has("shop_gold"):
		var times := int(a.shop_gold) if str(a.shop_gold).is_valid_int() else 5
		for i in times:
			world.send_command("cheat", ["gold"])
	if a.has("open_shop") and not visible:
		toggle()
	if a.has("shop_buy"):
		for raw in str(a.shop_buy).split(",", false):
			var id := raw.strip_edges()
			var err := _champ().check_buy(id)
			print("[shop] buy %s: %s" % [id, "ok" if err == "" else err])
			_buy(id)
		# On a network client this still shows the items from before the host answered.
		var inv := PackedStringArray()
		for inst in _champ().items:
			inv.append(str(inst.id) if inst != null else "-")
		print("[shop] items: %s  gold: %d" % [", ".join(inv), int(_champ().gold)])
	if a.has("shop_select"):
		_select(str(a.shop_select))


# ------------------------------------------------------- catalog & filters ---

func _build_catalog() -> void:
	_items_ref = Game.items
	_catalog.clear()
	_names.clear()
	_by_rarity.clear()
	var keys := {}
	for s in SECTIONS:
		keys[s[0]] = true
	for id in Game.items:
		var it: Dictionary = Game.items[id]
		if not it.buyable or it.rarity == "transform":
			continue
		_catalog.append(id)
		var n := str(it.name).to_lower()
		_names[id] = [n, _squash(n)]
		var key := str(it.rarity) if keys.has(it.rarity) else "other"
		if not _by_rarity.has(key):
			_by_rarity[key] = []
		_by_rarity[key].append(id)
	for key in _by_rarity:
		_by_rarity[key].sort_custom(_by_cost)
	_build_categories()
	if _sel != "" and not Game.items.has(_sel):
		_sel = ""
	_apply_filters()
	_select(_sel)


func _build_categories() -> void:
	for c in _cats:
		_cat_box.remove_child(c.button)
		c.button.queue_free()
	_cats.clear()
	_active.clear()
	var defs: Array = CATEGORIES.duplicate()
	var known := {}
	for d in CATEGORIES:
		for t in d[1]:
			known[t] = true
	var extra := {}
	for id in _catalog:
		for t in Game.items[id].tags:
			if not known.has(str(t)) and not IGNORED_TAGS.has(str(t)):
				extra[str(t)] = true
	var extra_tags := extra.keys()
	extra_tags.sort()
	for t in extra_tags:
		defs.append([str(t).capitalize(), [t], []])
	for d in defs:
		var ids := {}
		for id in _catalog:
			if _in_category(Game.items[id], d):
				ids[id] = true
		if ids.is_empty():
			continue
		var b := Button.new()
		b.text = d[0]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = &"ShopFilter"
		var idx := _cats.size()
		b.toggled.connect(func(on: bool) -> void: _on_category(idx, on))
		_cat_box.add_child(b)
		_cats.append({"name": d[0], "ids": ids, "button": b})


func _in_category(it: Dictionary, d: Array) -> bool:
	for t in d[1]:
		if it.tags.has(t):
			return true
	for k in d[2]:
		if it.stats.has(k):
			return true
	return d[0] == "Actives" and it.active != null


func _by_cost(a: String, b: String) -> bool:
	var ca := int(Game.items[a].cost)
	var cb := int(Game.items[b].cost)
	if ca != cb:
		return ca < cb
	return str(Game.items[a].name).naturalnocasecmp_to(str(Game.items[b].name)) < 0


static func _squash(s: String) -> String:
	var out := ""
	for c in s:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


func _matches(id: String) -> bool:
	if _query != "":
		var n: Array = _names[id]
		if not (n[0].contains(_query) or (_query_sq != "" and n[1].contains(_query_sq)) or str(Game.items[id].short).to_lower() == _query):
			return false
	for i in _active:
		if not _cats[i].ids.has(id):
			return false
	return true


func _apply_filters() -> void:
	var any := false
	for s in _sections:
		var list: Array = _by_rarity.get(s.key, []).filter(_matches)
		s.set_ids(list)
		any = any or not list.is_empty()
	_no_match.visible = not any
	_clear_btn.visible = _query != "" or not _active.is_empty()
	_scroll.scroll_vertical = 0


func _on_search(text: String) -> void:
	_query = text.strip_edges().to_lower()
	_query_sq = _squash(_query)
	_apply_filters()


func _on_search_submit(_text: String) -> void:
	for s in _sections:
		if not s.ids.is_empty():
			_select(s.ids[0])
			break
	_search.release_focus()


func _on_category(i: int, on: bool) -> void:
	if on:
		_active[i] = true
	else:
		_active.erase(i)
	_apply_filters()


func _clear_filters() -> void:
	for i in _active:
		_cats[i].button.set_pressed_no_signal(false)
	_active.clear()
	_search.text = ""
	_query = ""
	_query_sq = ""
	_apply_filters()


func _select(id: String) -> void:
	if id != "" and not Game.items.has(id):
		push_warning("Shop: unknown item '%s'" % id)
		return
	_sel = id
	_big_icon.cells[0].id = id
	if id != "":
		var it: Dictionary = Game.items[id]
		_d_name.text = it.name
		_d_name.add_theme_color_override("font_color", ItemUI.rarity_color(it))
		var kind := str(it.rarity).capitalize()
		if int(it.min_level) > 0:
			kind += "  -  requires level %d" % int(it.min_level)
		if int(it.stack) > 1:
			kind += "  -  stacks to %d" % int(it.stack)
		_d_kind.text = kind
		_desc.text = ItemUI.describe_bbcode(it)
		_desc.scroll_to_line(0)
		_tree.set_root(id)
		_recipe_head.visible = not it.from.is_empty()
		_tree.visible = _recipe_head.visible
		var into: Array = it.get("into", []).filter(func(x): return Game.items.has(x) and Game.items[x].buyable)
		into.sort_custom(_by_cost)
		_into.set_ids(into)
		_into_head.visible = not into.is_empty()
		_into.visible = _into_head.visible
	_update_details()
	for s in _sections:
		s.queue_redraw()


func _tooltip(id: String) -> Control:
	var it = Game.items.get(id)
	if it == null:
		return null
	var st := _st(id)
	var notes := []
	if int(st[0]) != int(it.cost):
		notes.append(["You pay %d with the components you own" % int(st[0]), GOLD])
	if _owned.has(id):
		notes.append(["Owned", GREEN])
	if st[1] != "":
		notes.append([st[1], RED])
	else:
		notes.append(["Right-click to buy", MUTED])
	return ItemUI.tooltip(it, notes)


# ---------------------------------------------------------------- drawing ---

func _draw_cell(ci: CanvasItem, r: Rect2, id: String, hovered: bool) -> void:
	var it = Game.items.get(id)
	if it == null:
		return
	var st := _st(id)
	var ir := Rect2(r.position.x + (r.size.x - ICON) * 0.5, r.position.y + 3.0, ICON, ICON)
	if id == _sel:
		ci.draw_rect(ir.grow(4.0), Color(GOLD, 0.2))
		ci.draw_rect(ir.grow(4.0), GOLD, false, 2.0)
	ItemUI.draw_icon(ci, ir, it, st[1] != "")
	if hovered:
		ci.draw_rect(ir.grow(2.0), Color(1, 1, 1, 0.9), false, 2.0)
	if _owned.has(id):
		_draw_check(ci, ir.position + Vector2(ir.size.x - 3.0, 3.0), 8.0)
	var price: int = st[0]
	ci.draw_string(_font, Vector2(r.position.x, ir.end.y + 15.0), str(price), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, GOLD if _gold >= price else RED)


func _draw_small(ci: CanvasItem, r: Rect2, id: String, hovered: bool) -> void:
	var it = Game.items.get(id)
	if it == null:
		return
	ItemUI.draw_icon(ci, r, it, _st(id)[1] != "")
	if hovered:
		ci.draw_rect(r.grow(2.0), Color(1, 1, 1, 0.9), false, 2.0)
	if _owned.has(id):
		_draw_check(ci, r.position + Vector2(r.size.x - 3.0, 3.0), 7.0)


func _draw_tree_node(ci: CanvasItem, n: Dictionary, hovered: bool) -> void:
	var it = Game.items.get(n.id)
	if it == null:
		return
	var r: Rect2 = n.r
	if n.owned:
		ci.draw_rect(r.grow(4.0), Color(GREEN, 0.18))
	ItemUI.draw_icon(ci, r, it)
	if n.owned:
		ci.draw_rect(r.grow(2.0), GREEN, false, 2.0)
		_draw_check(ci, r.position + Vector2(r.size.x - 2.0, 2.0), 7.0)
	elif n.depth == 0:
		ci.draw_rect(r.grow(2.0), GOLD, false, 2.0)
	if hovered:
		ci.draw_rect(r.grow(3.0), Color(1, 1, 1, 0.9), false, 2.0)
	var y := r.end.y + 13.0
	if n.owned:
		ci.draw_string(_font, Vector2(r.position.x - 20.0, y), "owned", HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0, 12, GREEN)
	else:
		var price: int = _st(n.id)[0]
		ci.draw_string(_font, Vector2(r.position.x - 20.0, y), str(price), HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0, 13, GOLD if _gold >= price else RED)


func _draw_slot(ci: CanvasItem, cell: Dictionary, hovered: bool) -> void:
	var r: Rect2 = cell.r
	var slot: int = cell.slot
	ci.draw_rect(r, Color(0.035, 0.04, 0.055))
	var ch := _champ()
	var it = ch.item_def(slot) if ch != null else null
	if it == null:
		ci.draw_rect(r, Color(0.22, 0.24, 0.29), false, 1.0)
	else:
		ItemUI.draw_icon(ci, r.grow(-2.0), it)
		var n := int(ch.item_view(slot)[0])
		if n > 1 or it.charges > 0 or it.display != null:
			var p := Vector2(r.position.x, r.end.y - 4.0)
			ci.draw_string_outline(_font, p, str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0, 13, 4, Color.BLACK)
			ci.draw_string(_font, p, str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0, 13, Color.WHITE)
	if slot == _sel_slot:
		ci.draw_rect(r.grow(2.0), GOLD, false, 2.5)
	elif hovered:
		ci.draw_rect(r.grow(1.0), Color(1, 1, 1, 0.85), false, 2.0)
	var lp := r.position + Vector2(4, 13)
	ci.draw_string_outline(_font, lp, str(slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
	ci.draw_string(_font, lp, str(slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.95, 0.8))


func _draw_check(ci: CanvasItem, c: Vector2, rad: float) -> void:
	ci.draw_circle(c, rad + 1.0, Color(0, 0, 0, 0.6))
	ci.draw_circle(c, rad, Color(0.16, 0.62, 0.26))
	var pts := PackedVector2Array([c + Vector2(-0.5, 0.0) * rad, c + Vector2(-0.12, 0.4) * rad, c + Vector2(0.52, -0.38) * rad])
	ci.draw_polyline(pts, Color.WHITE, maxf(rad * 0.28, 1.5))


func _draw_big_icon(c: Control, hovered: bool) -> void:
	var it = Game.items.get(_sel)
	if it == null:
		return
	ItemUI.draw_icon(c, Rect2(Vector2.ZERO, c.size), it)
	if hovered:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.9), false, 2.0)
	if _owned.has(_sel):
		_draw_check(c, Vector2(c.size.x - 4.0, 4.0), 9.0)


func _draw_coin(c: Control) -> void:
	var p := c.size * 0.5
	c.draw_circle(p, 9.0, Color(1, 0.8, 0.2))
	c.draw_circle(p, 6.0, Color(0.85, 0.6, 0.1))
	c.draw_circle(p + Vector2(-2, -2), 2.0, Color(1, 0.95, 0.7, 0.8))


# ---------------------------------------------------------------- layout ---

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	_label(top, "SHOP", 24, GOLD)
	var help := _label(top, "Click an item for details  -  right-click or double-click to buy", 13, MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var coin := Painter.new()
	coin.fn = _draw_coin
	coin.custom_minimum_size = Vector2(22, 22)
	top.add_child(coin)
	_gold_label = _label(top, "0", 22, GOLD)
	_gold_label.custom_minimum_size.x = 64
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close (P or Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.theme_type_variation = &"ShopClose"
	close.custom_minimum_size = Vector2(36, 32)
	close.pressed.connect(toggle)
	top.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)
	body.add_child(_build_filters())
	body.add_child(_build_grid())
	body.add_child(_build_details())
	root.add_child(_build_inventory())


func _build_filters() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 176
	col.add_theme_constant_override("separation", 6)
	_search = LineEdit.new()
	_search.placeholder_text = "Search items..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search)
	_search.text_submitted.connect(_on_search_submit)
	col.add_child(_search)
	var h := HBoxContainer.new()
	col.add_child(h)
	var l := _label(h, "CATEGORIES", 13, MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_btn = Button.new()
	_clear_btn.text = "Clear"
	_clear_btn.flat = true
	_clear_btn.focus_mode = Control.FOCUS_NONE
	_clear_btn.theme_type_variation = &"ShopLink"
	_clear_btn.pressed.connect(_clear_filters)
	_clear_btn.visible = false
	h.add_child(_clear_btn)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	_cat_box = VBoxContainer.new()
	_cat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cat_box.add_theme_constant_override("separation", 0)
	sc.add_child(_cat_box)
	return col


func _build_grid() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(BG_INNER, BORDER_DIM, 1, 6, 4))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	_scroll.add_child(v)
	for s in SECTIONS:
		var sec := Section.new(self, s[0], s[1], s[2])
		sec.visible = false
		v.add_child(sec)
		_sections.append(sec)
	_no_match = _label(v, "No items match your search.", 15, MUTED)
	_no_match.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_match.custom_minimum_size.y = 80
	_no_match.visible = false
	return panel


func _build_details() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	panel.add_theme_stylebox_override("panel", _box(BG_INNER, BORDER_DIM, 1, 6, 10))
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	panel.add_child(_details)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_details.add_child(head)
	_big_icon = BigIcon.new(self)
	_big_icon.custom_minimum_size = Vector2(64, 64)
	_big_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_big_icon)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	_d_name = _label(hv, "", 19, TEXT)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_kind = _label(hv, "", 13, MUTED)
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 14)
	hv.add_child(costs)
	_d_total = _label(costs, "", 15, Color(0.85, 0.78, 0.55))
	_d_left = _label(costs, "", 15, GOLD)

	_recipe_head = _label(_details, "RECIPE", 13, MUTED)
	_tree = RecipeView.new(self)
	_details.add_child(_tree)
	_into_head = _label(_details, "BUILDS INTO", 13, MUTED)
	_into = IntoRow.new(self)
	_details.add_child(_into)
	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.scroll_active = true
	_desc.focus_mode = Control.FOCUS_NONE
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc.custom_minimum_size.y = 60
	_details.add_child(_desc)
	_reason = _label(_details, "", 13, RED)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_btn = Button.new()
	_buy_btn.text = "Buy"
	_buy_btn.focus_mode = Control.FOCUS_NONE
	_buy_btn.theme_type_variation = &"ShopBuy"
	_buy_btn.custom_minimum_size.y = 44
	_buy_btn.pressed.connect(func() -> void: _buy(_sel))
	_details.add_child(_buy_btn)

	_placeholder = _label(panel, "Select an item to see what it does and what it builds from.\n\nRight-click any item to buy it right away.", 15, MUTED)
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_details.visible = false
	return panel


func _build_inventory() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(BG_INNER, BORDER_DIM, 1, 6, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	_label(h, "YOUR ITEMS", 13, MUTED)
	_inv = InvRow.new(self)
	h.add_child(_inv)
	_sell_btn = Button.new()
	_sell_btn.text = "Sell"
	_sell_btn.focus_mode = Control.FOCUS_NONE
	_sell_btn.custom_minimum_size = Vector2(170, 40)
	_sell_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sell_btn.disabled = true
	_sell_btn.pressed.connect(_sell)
	h.add_child(_sell_btn)
	_msg = _label(h, "", 15, MUTED)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg.clip_text = true
	return panel


func _label(parent: Node, text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func _box(bg: Color, border := Color(0, 0, 0, 0), width := 0, radius := 4, margin := 8.0, margin_y := -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin_y if margin_y >= 0.0 else margin
	sb.content_margin_bottom = margin_y if margin_y >= 0.0 else margin
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("normal", "Button", _box(Color(0.12, 0.13, 0.17), BORDER, 1, 4, 10, 4))
	t.set_stylebox("hover", "Button", _box(Color(0.17, 0.18, 0.23), BORDER.lightened(0.25), 1, 4, 10, 4))
	t.set_stylebox("pressed", "Button", _box(Color(0.09, 0.1, 0.13), GOLD.darkened(0.3), 1, 4, 10, 4))
	t.set_stylebox("disabled", "Button", _box(Color(0.085, 0.09, 0.115), Color(0.2, 0.21, 0.25), 1, 4, 10, 4))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.52))

	t.set_type_variation(&"ShopFilter", &"Button")
	var on := _box(Color(GOLD, 0.13), GOLD, 0, 3, 10, 2)
	on.border_width_left = 3
	var on_hover := on.duplicate() as StyleBoxFlat
	on_hover.bg_color = Color(GOLD, 0.2)
	t.set_stylebox("normal", &"ShopFilter", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 10, 2))
	t.set_stylebox("hover", &"ShopFilter", _box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 3, 10, 2))
	t.set_stylebox("pressed", &"ShopFilter", on)
	t.set_stylebox("hover_pressed", &"ShopFilter", on_hover)
	t.set_color("font_color", &"ShopFilter", Color(0.78, 0.8, 0.85))
	t.set_color("font_hover_color", &"ShopFilter", Color.WHITE)
	t.set_color("font_pressed_color", &"ShopFilter", GOLD)
	t.set_color("font_hover_pressed_color", &"ShopFilter", GOLD.lightened(0.2))
	t.set_font_size("font_size", &"ShopFilter", 14)

	t.set_type_variation(&"ShopBuy", &"Button")
	t.set_stylebox("normal", &"ShopBuy", _box(Color(0.36, 0.27, 0.08), GOLD.darkened(0.2), 1, 5))
	t.set_stylebox("hover", &"ShopBuy", _box(Color(0.47, 0.36, 0.1), GOLD, 1, 5))
	t.set_stylebox("pressed", &"ShopBuy", _box(Color(0.28, 0.21, 0.06), GOLD, 1, 5))
	t.set_stylebox("disabled", &"ShopBuy", _box(Color(0.1, 0.105, 0.13), Color(0.24, 0.25, 0.3), 1, 5))
	t.set_color("font_color", &"ShopBuy", Color(1, 0.94, 0.78))
	t.set_color("font_hover_color", &"ShopBuy", Color.WHITE)
	t.set_color("font_pressed_color", &"ShopBuy", GOLD)
	t.set_font_size("font_size", &"ShopBuy", 18)

	t.set_type_variation(&"ShopClose", &"Button")
	t.set_stylebox("normal", &"ShopClose", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 6, 0))
	t.set_stylebox("hover", &"ShopClose", _box(Color(0.6, 0.16, 0.13, 0.7), Color(0, 0, 0, 0), 0, 4, 6, 0))
	t.set_stylebox("pressed", &"ShopClose", _box(Color(0.45, 0.1, 0.08, 0.8), Color(0, 0, 0, 0), 0, 4, 6, 0))
	t.set_color("font_color", &"ShopClose", MUTED)
	t.set_font_size("font_size", &"ShopClose", 26)

	t.set_type_variation(&"ShopLink", &"Button")
	t.set_stylebox("normal", &"ShopLink", StyleBoxEmpty.new())
	t.set_stylebox("hover", &"ShopLink", StyleBoxEmpty.new())
	t.set_stylebox("pressed", &"ShopLink", StyleBoxEmpty.new())
	t.set_color("font_color", &"ShopLink", GOLD.darkened(0.15))
	t.set_color("font_hover_color", &"ShopLink", GOLD.lightened(0.2))
	t.set_font_size("font_size", &"ShopLink", 13)

	t.set_stylebox("normal", "LineEdit", _box(Color(0.03, 0.035, 0.05), BORDER, 1, 4, 8, 5))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), GOLD.darkened(0.2), 1, 4, 8, 5))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.52, 0.58))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.3))
	t.set_color("clear_button_color", "LineEdit", MUTED)

	t.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 4, 5, 0))
	t.set_stylebox("scroll_focus", "VScrollBar", _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 4, 5, 0))
	t.set_stylebox("grabber", "VScrollBar", _box(Color(0.3, 0.32, 0.38), Color(0, 0, 0, 0), 0, 4, 5, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(0.42, 0.44, 0.5), Color(0, 0, 0, 0), 0, 4, 5, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(GOLD.darkened(0.35), Color(0, 0, 0, 0), 0, 4, 5, 0))

	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.035, 0.04, 0.055, 0.97), BORDER, 1, 4, 10, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	t.set_font_size("bold_font_size", "RichTextLabel", 15)
	t.set_font_size("italics_font_size", "RichTextLabel", 15)
	t.set_constant("line_separation", "RichTextLabel", 2)
	return t


# ---------------------------------------------------------- inner views ---

class Painter extends Control:
	var fn: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


## Base for the custom-drawn item views: hit testing, hover, clicks and item tooltips.
class Cells extends Control:
	var shop: Shop
	var cells: Array = []   # [{r: Rect2, id: String, ...}]
	var hover := -1

	func _init(s: Shop) -> void:
		shop = s
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP

	func cell_at(p: Vector2) -> int:
		for i in cells.size():
			if cells[i].r.has_point(p):
				return i
		return -1

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var h := cell_at(ev.position)
			if h != hover:
				hover = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
				queue_redraw()
		elif ev is InputEventMouseButton and ev.pressed:
			var i := cell_at(ev.position)
			if i >= 0 and (ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
				accept_event()
				shop._cell_clicked(self, cells[i], ev.button_index == MOUSE_BUTTON_RIGHT, ev.double_click)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hover >= 0:
			hover = -1
			queue_redraw()

	func _get_tooltip(at: Vector2) -> String:
		var i := cell_at(at)
		return str(cells[i].id) if i >= 0 else ""

	func _make_custom_tooltip(for_text: String) -> Object:
		# Godot asks even when there is no tooltip text (gaps between cells): show nothing then.
		return shop._tooltip(for_text) if for_text != "" else null


## One rarity group of the item grid: a title and a wrapping grid of items with prices.
class Section extends Cells:
	var key := ""
	var title := ""
	var note := ""
	var color := Color.WHITE
	var ids: Array = []
	var _frame: StyleBoxFlat

	func _init(s: Shop, k: String, t: String, n: String) -> void:
		super(s)
		key = k
		title = t.to_upper()
		note = n
		color = ItemUI.RARITY_COLORS.get(k, Color(0.7, 0.72, 0.78))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if k == "mythic":
			_frame = Shop._box(Color(PURPLE, 0.09), Color(PURPLE, 0.55), 1, 6)
		resized.connect(relayout)

	func set_ids(list: Array) -> void:
		ids = list
		visible = not ids.is_empty()
		relayout()

	func relayout() -> void:
		cells.clear()
		var w := size.x if size.x > 10.0 else 500.0
		var cols := maxi(int((w - 12.0) / CELL.x), 1)
		for i in ids.size():
			cells.append({"r": Rect2(6.0 + (i % cols) * CELL.x, HEAD_H + (i / cols) * CELL.y, CELL.x, CELL.y), "id": ids[i]})
		custom_minimum_size.y = HEAD_H + ceili(ids.size() / float(cols)) * CELL.y + 4.0
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		if _frame != null:
			draw_style_box(_frame, Rect2(Vector2.ZERO, size))
		draw_string(font, Vector2(10, 21), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		var x := 18.0 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if note != "":
			draw_string(font, Vector2(x - 4.0, 21), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(color, 0.75))
			x += font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6.0
		draw_line(Vector2(x, 16), Vector2(size.x - 10.0, 16), Color(color, 0.28), 1.0)
		for i in cells.size():
			shop._draw_cell(self, cells[i].r, cells[i].id, i == hover)


## Recipe tree: the item on top, its components below (up to 4 levels), joined by lines.
class RecipeView extends Cells:
	const MAX_DEPTH := 4
	const PRICE_H := 15.0
	const GAP := 12.0
	var root := ""
	var nodes: Array = []   # {id, depth, kids: [node index], lo, hi (leaf span), owned, r}

	func _init(s: Shop) -> void:
		super(s)
		resized.connect(relayout)

	func set_root(id: String) -> void:
		root = id
		nodes.clear()
		if Game.items.has(id):
			_add(id, 0)
			_span(0, [0])
		relayout()

	func _add(id: String, depth: int) -> int:
		var i := nodes.size()
		nodes.append({"id": id, "depth": depth, "kids": [], "lo": 0, "hi": 1, "owned": false, "r": Rect2()})
		if depth < MAX_DEPTH - 1:
			for c in Game.items[id].from:
				if Game.items.has(c):
					var k := _add(c, depth + 1)
					nodes[i].kids.append(k)
		return i

	func _span(i: int, next: Array) -> void:
		var n: Dictionary = nodes[i]
		if n.kids.is_empty():
			n.lo = next[0]
			n.hi = next[0] + 1
			next[0] += 1
			return
		for k in n.kids:
			_span(k, next)
		n.lo = nodes[n.kids[0]].lo
		n.hi = nodes[n.kids[-1]].hi

	func relayout() -> void:
		cells.clear()
		if nodes.is_empty():
			custom_minimum_size.y = 0.0
			queue_redraw()
			return
		var w := size.x if size.x > 10.0 else 310.0
		var depth := 0
		for n in nodes:
			depth = maxi(depth, n.depth)
		var slot: float = w / float(nodes[0].hi)
		var s := clampf(slot - 8.0, 20.0, 36.0)
		var lh := s + PRICE_H + GAP
		for n in nodes:
			var cx: float = (n.lo + n.hi) * 0.5 * slot
			n.r = Rect2(cx - s * 0.5, n.depth * lh + 3.0, s, s)
			cells.append({"r": n.r, "id": n.id, "node": n})
		custom_minimum_size.y = (depth + 1) * lh - GAP + 6.0
		queue_redraw()

	## Highlights the parts you own, matching them up exactly like Champion.price_for does.
	func mark_owned(ch: Champion) -> void:
		for n in nodes:
			n.owned = false
		if not nodes.is_empty() and ch != null:
			nodes[0].owned = ch.has_item(root)
			if not nodes[0].owned:
				_mark(0, [], ch)
		queue_redraw()

	func _mark(i: int, used: Array, ch: Champion) -> void:
		for k in nodes[i].kids:
			var found := -1
			for s in Champion.ITEM_SLOTS:
				var inst = ch.items[s]
				if inst != null and inst.id == nodes[k].id and not used.has(s):
					found = s
					break
			if found >= 0:
				used.append(found)
				_own(k)
			else:
				_mark(k, used, ch)

	func _own(i: int) -> void:
		nodes[i].owned = true
		for k in nodes[i].kids:
			_own(k)

	func _draw() -> void:
		var col := Color(0.42, 0.44, 0.5)
		for n in nodes:
			if n.kids.is_empty():
				continue
			var pr: Rect2 = n.r
			var px := pr.get_center().x
			var top: float = nodes[n.kids[0]].r.position.y
			var y0 := pr.end.y + PRICE_H
			var ym := (y0 + top) * 0.5
			draw_line(Vector2(px, y0), Vector2(px, ym), col, 2.0)
			draw_line(Vector2(nodes[n.kids[0]].r.get_center().x - 1.0, ym), Vector2(nodes[n.kids[-1]].r.get_center().x + 1.0, ym), col, 2.0)
			for k in n.kids:
				var kx: float = nodes[k].r.get_center().x
				draw_line(Vector2(kx, ym), Vector2(kx, top - 3.0), col, 2.0)
		for i in cells.size():
			shop._draw_tree_node(self, cells[i].node, i == hover)


## A wrapping row of small item icons ("Builds into"), at most 3 rows.
class IntoRow extends Cells:
	const S := 34.0
	const PITCH := 39.0
	const MAX_ROWS := 3
	var ids: Array = []
	var more := 0
	var more_rect := Rect2()

	func _init(s: Shop) -> void:
		super(s)
		resized.connect(relayout)

	func set_ids(list: Array) -> void:
		ids = list
		relayout()

	func relayout() -> void:
		cells.clear()
		var w := size.x if size.x > 10.0 else 310.0
		var cols := maxi(int((w - S) / PITCH) + 1, 1)
		var n := ids.size()
		more = 0
		if n > cols * MAX_ROWS:
			n = cols * MAX_ROWS - 1
			more = ids.size() - n
		for i in n:
			cells.append({"r": Rect2(2.0 + (i % cols) * PITCH, 2.0 + (i / cols) * PITCH, S, S), "id": ids[i]})
		more_rect = Rect2(2.0 + (n % cols) * PITCH, 2.0 + (n / cols) * PITCH, S, S)
		var rows := ceili((n + (1 if more > 0 else 0)) / float(cols))
		custom_minimum_size.y = maxf(rows * PITCH - (PITCH - S) + 4.0, 0.0)
		queue_redraw()

	func _draw() -> void:
		for i in cells.size():
			shop._draw_small(self, cells[i].r, cells[i].id, i == hover)
		if more > 0:
			draw_rect(more_rect, Color(0.12, 0.13, 0.17))
			draw_rect(more_rect, Color(0.3, 0.32, 0.38), false, 1.0)
			draw_string(ThemeDB.fallback_font, more_rect.position + Vector2(0, 22), "+%d" % more, HORIZONTAL_ALIGNMENT_CENTER, S, 13, Color(0.75, 0.77, 0.82))


## The selected item's big icon (also right-click to buy, like every item icon).
class BigIcon extends Cells:
	func _init(s: Shop) -> void:
		super(s)
		cells.append({"r": Rect2(), "id": ""})
		resized.connect(func() -> void: cells[0].r = Rect2(Vector2.ZERO, size))

	func _draw() -> void:
		shop._draw_big_icon(self, hover == 0)


## Your 6 item slots: click one to select it (for selling), drag it onto another slot to swap.
class InvRow extends Cells:
	const S := 48.0
	const GAP := 6.0
	var drag_from := -1
	var dragging := false
	var drag_pos := Vector2.ZERO

	func _init(s: Shop) -> void:
		super(s)
		custom_minimum_size = Vector2(Champion.ITEM_SLOTS * (S + GAP) - GAP + 4.0, S + 4.0)
		for i in Champion.ITEM_SLOTS:
			cells.append({"r": Rect2(2.0 + i * (S + GAP), 2.0, S, S), "id": "", "slot": i})

	func _gui_input(ev: InputEvent) -> void:
		super(ev)
		# While the button is held, Godot keeps sending motion/release here even outside the row.
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			var i := cell_at(ev.position)
			if ev.pressed:
				drag_from = i if i >= 0 and cells[i].id != "" else -1
				return
			if dragging and i >= 0 and i != drag_from:
				shop._swap(drag_from, i)
			drag_from = -1
			dragging = false
			queue_redraw()
		elif ev is InputEventMouseMotion and drag_from >= 0:
			drag_pos = ev.position
			if not dragging and drag_pos.distance_to(cells[drag_from].r.get_center()) > 10.0:
				dragging = true
			if dragging:
				queue_redraw()

	func _draw() -> void:
		for i in cells.size():
			shop._draw_slot(self, cells[i], i == hover)
		var it = Game.items.get(cells[drag_from].id) if dragging else null
		if it != null:
			var r := Rect2(drag_pos - Vector2(S, S) * 0.5, Vector2(S, S))
			draw_rect(r.grow(3.0), Color(0, 0, 0, 0.5))
			ItemUI.draw_icon(self, r, it)

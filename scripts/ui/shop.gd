class_name Shop
extends PanelContainer
## Item shop (P). Minimal version: a list of buyable items; double-click to buy.

var world: World
var list: ItemList
var info: Label
var ids: Array = []


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(720, 520)
	var v := VBoxContainer.new()
	add_child(v)
	var title := Label.new()
	title.text = "Shop - double-click an item to buy it (P to close)"
	v.add_child(title)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(700, 380)
	list.item_activated.connect(func(i): world.send_command("buy", [ids[i]]))
	list.item_selected.connect(func(i): info.text = ItemUI.describe(Game.items[ids[i]]))
	v.add_child(list)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size = Vector2(700, 100)
	v.add_child(info)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func is_open() -> bool:
	return visible


func _refresh() -> void:
	list.clear()
	ids = []
	var all: Array = Game.items.keys().filter(func(id): return Game.items[id].buyable)
	all.sort_custom(func(a, b): return Game.items[a].cost < Game.items[b].cost)
	for id in all:
		ids.append(id)
		list.add_item("%s  -  %d" % [Game.items[id].name, Game.items[id].cost])

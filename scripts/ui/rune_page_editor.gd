class_name RunePageEditor
extends ConfirmationDialog

var page: Dictionary
var fields: VBoxContainer


func open(player_name: String, initial: Dictionary, save: Callable) -> void:
	title = "Rune page - " + player_name
	ok_button_text = "Save page"
	page = initial.duplicate(true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	fields = VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	confirmed.connect(func():
		if Runes.valid(page):
			save.call(page)
		queue_free())
	canceled.connect(queue_free)
	_refresh()
	popup_centered(Vector2i(530, 540))


func _refresh() -> void:
	for child in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	_tree("Primary path", "primary")
	for i in 4:
		_pick("Keystone" if i == 0 else "Primary row %d" % i, Runes.row(page.primary, i), "major", i)
	_tree("Secondary path", "secondary")
	for i in 2:
		var choices := []
		var used: Array = Runes.secondary_rows(page.secondary, [page.minor[1 - i]])
		for row in range(1, 4):
			if not used.has(row):
				choices.append_array(Runes.row(page.secondary, row))
		_pick("Secondary %d" % (i + 1), choices, "minor", i)
	for i in 3:
		_pick(["Offense shard", "Flex shard", "Defense shard"][i], Runes.SHARDS[i], "shards", i)


func _option(label: String) -> OptionButton:
	var row := UiKit.row(fields)
	UiKit.label(row, label, 145)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _tree(label: String, key: String) -> void:
	var option := _option(label)
	var keys := Runes.TREES.keys()
	for tree in keys:
		option.add_item(tree)
	option.select(keys.find(page[key]))
	option.item_selected.connect(func(index: int):
		var other := "secondary" if key == "primary" else "primary"
		if keys[index] == page[other]:
			page[other] = page[key]
		page[key] = keys[index]
		for i in 4:
			if not Runes._has(Runes.row(page.primary, i), page.major[i]):
				page.major[i] = Runes.TREES[page.primary][i][0][0]
		if Runes.secondary_rows(page.secondary, page.minor).size() != 2:
			page.minor = [Runes.TREES[page.secondary][1][0][0], Runes.TREES[page.secondary][2][0][0]]
		_refresh.call_deferred())


func _pick(label: String, choices: Array, key: String, slot: int) -> void:
	var option := _option(label)
	for i in choices.size():
		var choice: Array = choices[i]
		option.add_item(choice[1], choice[0])
		option.set_item_tooltip(i, choice[2])
		if choice[0] == page[key][slot]:
			option.select(i)
			option.tooltip_text = choice[2]
	option.item_selected.connect(func(index: int):
		page[key][slot] = choices[index][0]
		option.tooltip_text = choices[index][2]
		if key == "minor":
			_refresh.call_deferred())

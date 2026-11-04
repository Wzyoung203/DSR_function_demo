extends CanvasLayer

## Currency shop board: builds one visible row per view dictionary and only
## emits purchase intent. It never mutates GameState, player, or equipment.

signal purchase_requested(item_id: StringName, slot: int)
signal close_requested

@onready var title_label: Label = $Backdrop/Center/Panel/Margin/Content/Header/Title
@onready var balance_label: Label = $Backdrop/Center/Panel/Margin/Content/Header/Balance
@onready var items_container: VBoxContainer = $Backdrop/Center/Panel/Margin/Content/Scroll/Items
@onready var result_label: Label = $Backdrop/Center/Panel/Margin/Content/Result
@onready var close_button: Button = $Backdrop/Center/Panel/Margin/Content/Close

var last_purchase: Dictionary = {}
var _items: Array = []
var _money := 0
var _visible_count := 0


func _ready() -> void:
	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)


func configure(items: Array, money: int) -> bool:
	if not items is Array:
		push_error("ShopBoard: configure expects an Array of view dictionaries")
		return false
	_items = items.duplicate(true)
	_money = maxi(0, money)
	_rebuild()
	return true


func item_count() -> int:
	return _visible_count


func balance_text() -> String:
	return "货币：%d" % _money


func press_purchase(item_id: StringName, slot: int) -> bool:
	var item := _find_item(item_id)
	if item.is_empty():
		return false
	var is_weapon := bool(item.get("weapon", false))
	if is_weapon:
		if slot not in [0, 1]:
			return false
	elif slot != -1:
		return false
	last_purchase = {"item_id": item_id, "slot": slot}
	purchase_requested.emit(item_id, slot)
	return true


func show_board() -> void:
	visible = true
	if close_button != null:
		close_button.grab_focus()


func hide_board() -> void:
	visible = false


func _find_item(item_id: StringName) -> Dictionary:
	for item in _items:
		if StringName(item.get("id", &"")) == item_id and not bool(item.get("hidden", false)):
			return item
	return {}


func _rebuild() -> void:
	for child in items_container.get_children():
		items_container.remove_child(child)
		child.queue_free()
	_visible_count = 0
	for item in _items:
		if bool(item.get("hidden", false)):
			continue
		_visible_count += 1
		items_container.add_child(_build_row(item))
	if balance_label != null:
		balance_label.text = balance_text()
	if result_label != null:
		result_label.text = "" if _visible_count > 0 else "暂无商品"


func _build_row(item: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = str(item.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	row.add_child(name_label)

	var description_label := Label.new()
	description_label.text = str(item.get("description", ""))
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.add_theme_font_size_override("font_size", 16)
	row.add_child(description_label)

	var price_label := Label.new()
	price_label.text = "%d 货币" % int(item.get("price", 0))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(price_label)

	var item_id: StringName = StringName(item.get("id", &""))
	if bool(item.get("weapon", false)):
		var buttons := HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons.add_theme_constant_override("separation", 12)
		buttons.add_child(_make_button("覆盖主武器", item_id, 0))
		buttons.add_child(_make_button("覆盖副武器", item_id, 1))
		row.add_child(buttons)
	else:
		row.add_child(_make_button("购买", item_id, -1))
	return row


func _make_button(text: String, item_id: StringName, slot: int) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_request_purchase.bind(item_id, slot))
	return button


func _request_purchase(item_id: StringName, slot: int) -> void:
	press_purchase(item_id, slot)


func _on_close_pressed() -> void:
	close_requested.emit()

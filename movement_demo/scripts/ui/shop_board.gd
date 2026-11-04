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
	if not purchase_enabled(item_id, slot):
		return false
	var item := _find_item(item_id)
	last_purchase = {"item_id": item_id, "slot": slot}
	purchase_requested.emit(item_id, slot)
	return true


## 只读查询当前行按钮是否可点击；与 press_purchase 使用同一判定，
## 防止禁用按钮通过测试或其他调用方绕过视觉状态。
func purchase_enabled(item_id: StringName, slot: int) -> bool:
	var item := _find_item(item_id)
	if item.is_empty():
		return false
	var is_weapon := bool(item.get("weapon", false))
	if is_weapon:
		if slot not in [0, 1]:
			return false
		return _slot_enabled(item, slot)
	if slot != -1:
		return false
	return bool(item.get("enabled", true))


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
		var slots: Array = item.get("slots", [])
		if slots.is_empty():
			slots = [
				{"slot": 0, "label": "覆盖主武器", "enabled": true},
				{"slot": 1, "label": "覆盖副武器", "enabled": true},
			]
		for entry in slots:
			var slot: int = int(entry.get("slot", -1))
			if slot not in [0, 1]:
				continue
			var label_text: String = str(entry.get("label", "覆盖主武器" if slot == 0 else "覆盖副武器"))
			buttons.add_child(_make_button(label_text, item_id, slot, bool(entry.get("enabled", true))))
		row.add_child(buttons)
	else:
		row.add_child(_make_button("购买", item_id, -1, bool(item.get("enabled", true))))
	return row


func _slot_enabled(item: Dictionary, slot: int) -> bool:
	var slots: Array = item.get("slots", [])
	if slots.is_empty():
		return true
	for entry in slots:
		if int(entry.get("slot", -1)) == slot:
			return bool(entry.get("enabled", true))
	return false


func _make_button(text: String, item_id: StringName, slot: int, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.pressed.connect(_request_purchase.bind(item_id, slot))
	return button


func _request_purchase(item_id: StringName, slot: int) -> void:
	press_purchase(item_id, slot)


func _on_close_pressed() -> void:
	close_requested.emit()

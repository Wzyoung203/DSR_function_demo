extends SceneTree

## ShopBoard: hidden rows, balance, and purchase intent without touching game state.
## Run: godot --headless --path movement_demo --script res://tests/shop_board_test.gd

const BOARD_SCENE := preload("res://scenes/ui/shop_board.tscn")

const EXPECTED_CHECKS := 30

var failures := 0
var checks_run := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	var board: Node = BOARD_SCENE.instantiate()
	root.add_child(board)
	await process_frame

	check(not board.visible, "shop board starts hidden")
	check(board.process_mode == Node.PROCESS_MODE_ALWAYS, "shop board processes while paused")

	var requests: Array = []
	board.purchase_requested.connect(func(item_id: StringName, slot: int) -> void:
		requests.append([item_id, slot]))

	var items: Array = [
		{"id": &"first_aid", "name": "急救包", "description": "恢复 35 点生命", "price": 40, "weapon": false},
		{"id": &"ammo", "name": "弹药补给", "description": "补满弹匣与备弹", "price": 30, "weapon": false},
		{"id": &"system_progress", "name": "系统进度", "description": "任务进度 +20", "price": 50, "weapon": false},
	]
	check(board.configure(items, 100), "configure accepts three rows")
	check(board.item_count() == 3, "three visible rows")
	check(board.balance_text() == "货币：100", "balance text matches money")
	check(board.press_purchase(&"ammo", -1), "consumable purchase intent is accepted")
	check(board.last_purchase == {&"item_id": &"ammo", &"slot": -1},
		"last_purchase records exact consumable intent")
	check(requests == [[&"ammo", -1]], "purchase_requested emits exact intent")

	var mixed: Array = [
		{"id": &"first_aid", "name": "急救包", "description": "恢复 35 点生命", "price": 40, "weapon": false},
		{"id": &"locked_weapon", "name": "锁定武器", "description": "隐藏", "price": 200, "weapon": true, "hidden": true},
	]
	check(board.configure(mixed, 80), "configure accepts mixed rows")
	check(board.item_count() == 1, "hidden row is not rendered")

	var weapon: Array = [
		{"id": &"shop_rifle", "name": "商店步枪", "description": "覆盖武器槽", "price": 100, "weapon": true},
	]
	check(board.configure(weapon, 120), "configure accepts a weapon row")
	check(board.item_count() == 1, "weapon row counts once")
	check(board.press_purchase(&"shop_rifle", 0), "primary weapon intent is accepted")
	check(board.last_purchase == {&"item_id": &"shop_rifle", &"slot": 0},
		"last_purchase records primary slot")
	check(board.press_purchase(&"shop_rifle", 1), "secondary weapon intent is accepted")
	check(board.last_purchase == {&"item_id": &"shop_rifle", &"slot": 1},
		"last_purchase records secondary slot")

	var disabled_items: Array = [
		{"id": &"first_aid", "name": "急救包", "description": "恢复 35 点生命", "price": 40, "weapon": false, "enabled": false},
		{"id": &"ammo", "name": "弹药补给", "description": "补满弹匣与备弹", "price": 30, "weapon": false, "enabled": true},
	]
	check(board.configure(disabled_items, 100), "configure accepts enabled state rows")
	check(not board.purchase_enabled(&"first_aid", -1), "disabled consumable reports unavailable")
	check(board.purchase_enabled(&"ammo", -1), "enabled consumable reports available")
	check(not board.press_purchase(&"first_aid", -1), "disabled consumable does not emit intent")
	check(board.press_purchase(&"ammo", -1), "enabled consumable still emits intent")
	check(_button_disabled(board, "购买") != null and _button_disabled(board, "购买").disabled,
		"disabled consumable button is visually disabled")

	var disabled_weapon: Array = [
		{
			"id": &"shop_rifle",
			"name": "商店步枪",
			"description": "覆盖武器槽",
			"price": 100,
			"weapon": true,
			"slots": [
				{"slot": 0, "label": "覆盖主武器", "enabled": false},
				{"slot": 1, "label": "覆盖副武器", "enabled": true},
			],
		},
	]
	check(board.configure(disabled_weapon, 120), "configure accepts per-slot weapon state")
	check(not board.purchase_enabled(&"shop_rifle", 0), "disabled primary weapon slot reports unavailable")
	check(board.purchase_enabled(&"shop_rifle", 1), "enabled secondary weapon slot reports available")
	check(not board.press_purchase(&"shop_rifle", 0), "disabled primary weapon slot does not emit intent")
	check(board.press_purchase(&"shop_rifle", 1), "enabled secondary weapon slot emits intent")
	check(_button_disabled(board, "覆盖主武器").disabled and not _button_disabled(board, "覆盖副武器").disabled,
		"per-slot weapon buttons match their visual disabled state")

	board.show_board()
	check(board.visible, "show_board displays the board")
	board.hide_board()
	check(not board.visible, "hide_board hides the board")

	board.queue_free()
	await process_frame

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("shop board checks: all passed")
	else:
		print("shop board checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _button_disabled(board: Node, text: String) -> Button:
	for row in board.items_container.get_children():
		if not row is VBoxContainer:
			continue
		for child in row.get_children():
			if child is Button and (child as Button).text == text:
				return child
			if child is HBoxContainer:
				for button in (child as HBoxContainer).get_children():
					if button is Button and (button as Button).text == text:
						return button
	return null

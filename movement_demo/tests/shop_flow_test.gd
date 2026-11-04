extends SceneTree

## Currency shop integration: NPC entry, board rows, effects, visibility,
## validation, and pause ownership through the real main scene.
## Run: godot --headless --path movement_demo --script res://tests/shop_flow_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const ShopControllerScript := preload("res://scripts/shop/shop_controller.gd")
const ShopCatalogScript := preload("res://scripts/shop/shop_catalog.gd")
const ShopItemScript := preload("res://scripts/shop/shop_item_definition.gd")
const Pauses := preload("res://scripts/systems/scene_pause_coordinator.gd")
const SHOTGUN := preload("res://resources/weapons/test_shotgun.tres")
const SMG := preload("res://resources/weapons/test_smg.tres")

const WATCHDOG_SECONDS := 50.0

var failures := 0
var checks_run := 0
var _finished := false


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
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	await _check_real_shop_flow()
	await _check_edge_failures()
	_finish()


func _check_real_shop_flow() -> void:
	var ctx := await _prepare_main()
	check(ctx.controller != null, "ShopController is mounted")
	check(ctx.board != null, "ShopBoard is mounted")
	check(ctx.npc != null, "RewardNPC node path is retained")
	if ctx.controller == null or ctx.board == null or ctx.npc == null:
		await _release(ctx.scene)
		return

	check(str(ctx.npc.get_node("Name").text) == "商店", "blue NPC label becomes 商店")
	check(ctx.board.item_count() == 0, "board starts with no rows")
	check(await _open_shop_via_e(ctx), "E interaction opens the shop and pauses")
	check(ctx.board.item_count() == 3, "level 0 shows the three initial products")
	check(ctx.board.balance_text() == "货币：500", "board shows current money")

	ctx.health.health = 20.0
	ctx.health._update_display()
	var health_before: float = ctx.health.health
	check(ctx.controller.purchase(&"first_aid", -1), "first aid purchase succeeds")
	check(is_equal_approx(ctx.health.health, minf(ctx.health.max_health, health_before + 35.0)),
		"first aid heals 35")
	check(ctx.state.money == 460, "first aid deducts 40")

	var money_before_ammo: int = ctx.state.money
	check(ctx.controller.purchase(&"ammo", -1), "ammo purchase succeeds")
	check(ctx.state.money == money_before_ammo - 30, "ammo deducts 30")
	check(ctx.equipment.reserve_ammo[&"rifle"] == ctx.equipment.starting_rifle_ammo
		and ctx.equipment.reserve_ammo[&"pistol"] == ctx.equipment.starting_pistol_ammo
		and ctx.equipment.reserve_ammo[&"smg"] == ctx.equipment.starting_smg_ammo
		and ctx.equipment.reserve_ammo[&"shotgun"] == ctx.equipment.starting_shotgun_ammo,
		"ammo restores every initial reserve type")
	check(_magazines_full(ctx.equipment), "ammo refills both magazines and cancels reload")

	check(ctx.controller.purchase(&"system_progress", -1), "system progress purchase succeeds")
	check(int(ctx.state.system_progress) == 20, "system progress adds 20")
	check(ctx.state.money == 380, "system progress deducts 50")

	ctx.health.health = 10.0
	ctx.health._update_display()
	check(ctx.controller.purchase(&"first_aid", -1), "repeatable first aid purchase succeeds again")
	check(is_equal_approx(ctx.health.health, 45.0), "repeat first aid heals again")
	check(ctx.state.money == 340, "repeat first aid deducts again")

	ctx.controller.close_shop()
	await ctx.tree.process_frame
	await ctx.tree.process_frame
	check(not ctx.board.visible and not ctx.tree.paused, "close_shop hides board and unpauses")

	var custom: ShopCatalog = preload("res://resources/shop/shop_catalog.tres").duplicate(true)
	custom.items.append(_weapon_item(&"shop_rifle_primary", SHOTGUN, 100, 1))
	custom.items.append(_weapon_item(&"shop_rifle_secondary", SMG, 120, 1))
	ctx.controller.shop_catalog = custom
	ctx.state.completed_level = 0
	ctx.state.purchased_shop_item_ids = {}
	await ctx.tree.process_frame

	check(await _open_shop_via_e(ctx), "shop reopens after catalog change")
	check(ctx.board.item_count() == 3, "weapon rows stay hidden before unlock level")

	ctx.controller.close_shop()
	await ctx.tree.process_frame
	ctx.state.completed_level = 1
	await ctx.tree.process_frame
	check(await _open_shop_via_e(ctx), "shop reopens at unlock level 1")
	check(ctx.board.item_count() == 5, "weapon rows appear at unlock level 1")

	var original_secondary: WeaponData = ctx.equipment.secondary_weapon
	var money_before_weapon: int = ctx.state.money
	check(ctx.controller.purchase(&"shop_rifle_primary", 0), "primary weapon purchase succeeds")
	check(ctx.equipment.primary_weapon == SHOTGUN, "slot 0 receives the purchased weapon")
	check(ctx.equipment.secondary_weapon == original_secondary, "slot 0 purchase preserves secondary")
	check(ctx.state.money == money_before_weapon - 100, "primary weapon deducts 100")
	check(ctx.state.has_purchased_shop_item(&"shop_rifle_primary"),
		"primary weapon purchase is recorded")
	check(ctx.board.item_count() == 4, "one-time primary row disappears after purchase")

	money_before_weapon = ctx.state.money
	check(ctx.controller.purchase(&"shop_rifle_secondary", 1), "secondary weapon purchase succeeds")
	check(ctx.equipment.secondary_weapon == SMG, "slot 1 receives the purchased weapon")
	check(ctx.equipment.primary_weapon == SHOTGUN, "slot 1 purchase preserves primary")
	check(ctx.state.money == money_before_weapon - 120, "secondary weapon deducts 120")
	check(ctx.state.has_purchased_shop_item(&"shop_rifle_secondary"),
		"secondary weapon purchase is recorded")
	check(ctx.board.item_count() == 3, "both one-time weapon rows disappear after purchase")

	var money_before_repeat: int = ctx.state.money
	check(not ctx.controller.purchase(&"shop_rifle_primary", 0), "repeat one-time weapon is rejected")
	check(ctx.state.money == money_before_repeat and ctx.equipment.primary_weapon == SHOTGUN,
		"repeat rejection changes neither money nor equipment")

	money_before_repeat = ctx.state.money
	check(not ctx.controller.purchase(&"shop_rifle_secondary", 2), "invalid weapon slot is rejected")
	check(ctx.state.money == money_before_repeat
		and ctx.equipment.secondary_weapon == SMG
		and ctx.equipment.primary_weapon == SHOTGUN,
		"invalid slot changes neither money nor equipment")

	ctx.state.money = 10
	ctx.health.health = 10.0
	ctx.health._update_display()
	var money_before_poor: int = ctx.state.money
	check(not ctx.controller.purchase(&"first_aid", -1), "insufficient funds are rejected")
	check(ctx.state.money == money_before_poor and is_equal_approx(ctx.health.health, 10.0),
		"insufficient funds change neither money nor health")

	var pause_owner := Node.new()
	ctx.scene.add_child(pause_owner)
	var external: int = Pauses.for_tree(ctx.tree).acquire(pause_owner, &"external", false)
	check(external != 0 and ctx.tree.paused, "external pause can join the open shop pause")
	ctx.controller.close_shop()
	check(ctx.tree.paused and not ctx.board.visible,
		"closing shop releases only its own pause and keeps external pause")
	Pauses.for_tree(ctx.tree).release(external)
	check(not ctx.tree.paused, "releasing external pause restores the game")
	pause_owner.queue_free()

	await _release(ctx.scene)


func _check_edge_failures() -> void:
	var ctx := await _prepare_main()
	var money_before: int = ctx.state.money
	check(not ctx.controller.open_shop_for_player(null), "missing player is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"missing player does not pause or mutate")

	var missing_board := ShopControllerScript.new()
	missing_board.shop_catalog = preload("res://resources/shop/shop_catalog.tres")
	missing_board.shop_board_path = NodePath()
	ctx.scene.add_child(missing_board)
	await process_frame
	check(not missing_board.open_shop_for_player(ctx.player), "missing board is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"missing board does not pause or mutate")
	missing_board.queue_free()
	await process_frame

	var missing_catalog := ShopControllerScript.new()
	missing_catalog.shop_board_path = NodePath("../ShopBoard")
	ctx.scene.add_child(missing_catalog)
	await process_frame
	check(not missing_catalog.open_shop_for_player(ctx.player), "missing catalog is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"missing catalog does not pause or mutate")
	missing_catalog.queue_free()
	await process_frame

	var empty_catalog := ShopControllerScript.new()
	empty_catalog.shop_catalog = ShopCatalogScript.new()
	empty_catalog.shop_board_path = NodePath("../ShopBoard")
	ctx.scene.add_child(empty_catalog)
	await process_frame
	check(not empty_catalog.open_shop_for_player(ctx.player), "empty catalog is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"empty catalog does not pause or mutate")
	empty_catalog.queue_free()

	await _release(ctx.scene)


func _prepare_main() -> Dictionary:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state: Node = root.get_node("GameState")
	var player: CharacterBody3D = scene.get_node("Player")
	var npc: Node3D = scene.get_node("RewardNPC")
	var equipment: Node = player.get_node("Equipment")
	state.money = 500
	state.completed_level = 0
	state.available_level = 1
	state.system_progress = 0
	state.purchased_shop_item_ids = {}
	state.rewarded_task_ids = {}
	state.clear_interaction_state()
	_deplete_ammo(equipment)
	player.set_physics_process(false)
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(8):
		await tree.physics_frame
	return {
		"scene": scene,
		"tree": tree,
		"state": state,
		"controller": scene.get_node_or_null("ShopController"),
		"board": scene.get_node_or_null("ShopBoard"),
		"player": player,
		"npc": npc,
		"health": player.get_node("Health"),
		"equipment": equipment,
	}


func _open_shop_via_e(ctx: Dictionary) -> bool:
	_press_interact()
	for _frame in range(8):
		await ctx.tree.process_frame
	return bool(ctx.board.visible) and bool(ctx.tree.paused)


func _weapon_item(item_id: StringName, weapon: WeaponData, price: int, unlock_level: int) -> ShopItemDefinition:
	var item := ShopItemScript.new()
	item.id = item_id
	item.display_name = "商店武器 " + str(item_id)
	item.description = "覆盖所选武器槽"
	item.price = price
	item.unlock_level = unlock_level
	item.effect = ShopItemScript.Effect.WEAPON
	item.weapon_data = weapon
	item.one_time = true
	return item


func _deplete_ammo(equipment: Node) -> void:
	if equipment.has_method(&"select_slot"):
		equipment.select_slot(1)
		equipment.select_slot(0)
	for slot in range(2):
		var ammo_state = equipment.get("_ammo_states")[slot]
		if ammo_state != null:
			ammo_state.magazine_rounds = 0
			ammo_state.is_reloading = true
	for ammo_type in equipment.reserve_ammo.keys():
		equipment.reserve_ammo[ammo_type] = 0


func _magazines_full(equipment: Node) -> bool:
	for slot in range(2):
		var data = equipment.call("_weapon_at", slot)
		var ammo_state = equipment.get("_ammo_states")[slot]
		if data != null and (ammo_state == null or ammo_state.magazine_rounds != data.magazine_capacity or ammo_state.is_reloading):
			return false
	return true


func _press_interact() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	Input.flush_buffered_events()


func _release(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	current_scene = null
	await process_frame


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
	push_error("shop flow test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
		current_scene.queue_free()
	if failures == 0:
		print("shop flow checks: all passed")
	else:
		print("shop flow checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)

extends SceneTree

## 任务五端到端集成检查：真实主场景、真实敌人死亡、奖励面板、返回传送与交任务。
## 运行：godot --headless --path movement_demo --script res://tests/quest_encounter_loop_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const EnemyFixture := preload("res://tests/enemy/enemy_fire_fixture.gd")
const StagePhases := preload("res://scripts/systems/stage/stage_phase.gd")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const MAX_FRAMES := 180
const MAX_SETTLE_FRAMES := 8
const HEAL_AMOUNT := 35.0
const EXPECTED_CHECKS := 48

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

	var scene = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state := root.get_node("GameState")
	var quests := scene.get_node_or_null("QuestController")
	var stage := scene.get_node_or_null("StageController")
	var arena := scene.get_node_or_null("Arena")
	var player: CharacterBody3D = scene.get_node_or_null("Player")
	var enemy: CharacterBody3D = EnemyFixture.primary_enemy(scene)
	var reward_board := scene.get_node_or_null("RewardBoard")
	var controller := scene.get_node_or_null("EncounterController")
	var return_point := scene.get_node_or_null("TavernReturnPoint")
	var portal := scene.get_node_or_null("Arena/CombatZone/ReturnPortal")

	_require(controller != null, "EncounterController 已挂载")
	_require(reward_board != null, "RewardBoard 已挂载")
	_require(return_point != null, "TavernReturnPoint 已挂载")
	_require(portal != null, "ReturnPortal 已挂载")
	_require(_has_property(state, "task_a_returned"), "GameState.task_a_returned 字段存在")
	_require(_has_property(controller, "reward_delay_seconds"), "遭遇控制器提供奖励延迟")
	if failures > 0 or controller == null or reward_board == null or return_point == null or portal == null or not _has_property(state, "task_a_returned"):
		_finish(scene)
		return
	check(is_equal_approx(float(controller.get("reward_delay_seconds")), 5.0), "奖励默认等待五秒")
	controller.set("reward_delay_seconds", 0.05)

	player.set_physics_process(false)
	enemy.set_physics_process(false)

	state.set("help_choice", "")
	state.set("task_a_returned", "")
	state.set("system_progress", 0)
	state.clear_interaction_state()
	quests.reset_progress()
	await tree.process_frame
	await tree.process_frame

	check(quests.status_of(&"task_a") == QuestControllerScript.Status.NOT_STARTED, "重置后任务回到未接")
	check(int(state.get("system_progress")) == 0, "重置后系统进度归零")

	arena.combat_cleared.emit(arena)
	await tree.process_frame
	await tree.process_frame
	check(not reward_board.visible, "接取任务前清场不显示奖励面板")
	check(not tree.paused, "接取任务前清场不暂停")

	state.set("help_choice", "accepted")
	_check(await _wait_until(tree, func() -> bool: return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS),
		"设置 accepted 后任务进入进行中")

	player.global_position = arena.to_global(Vector3(-4.0, 0.0, 0.0))
	await _wait_physics_frames(tree, MAX_SETTLE_FRAMES)
	_check(stage.get_player_zone() == &"site", "玩家进入竞技场场地")

	var health_node: CanvasLayer = player.get_node("Health")
	health_node.receive_hit(50.0)
	await tree.process_frame
	_check(health_node.health < health_node.max_health, "玩家先受到伤害以留出治疗空间")
	var health_before_reward: float = health_node.health

	enemy.receive_hit(10000.0)
	check(not reward_board.visible and not tree.paused, "敌人死亡后五秒内不显示奖励面板")
	_check(await _wait_until(tree, func() -> bool: return reward_board.visible and tree.paused),
		"等待结束后暂停并显示奖励面板")

	var reward_ids: Array = reward_board.REWARD_IDS
	check(reward_ids.size() == 3 and reward_ids[0] == &"first_aid" and reward_ids[1] == &"ammo" and reward_ids[2] == &"system_progress",
		"奖励面板提供三项选择")
	var progress_bar: ProgressBar = scene.get_node("QuestPanel/Panel/Margin/Content/SystemProgress/Bar")
	var progress_label: Label = scene.get_node("QuestPanel/Panel/Margin/Content/SystemProgress/Label")
	check(progress_bar.max_value == 100.0 and progress_bar.value == 0.0 and progress_label.text.contains("0 / 100"),
		"任务面板显示零进度和百点上限")

	_check(controller.select_reward(&"first_aid"), "选择急救包奖励成功")
	_check(is_equal_approx(health_node.health, minf(health_node.max_health, health_before_reward + HEAL_AMOUNT)),
		"急救包恢复 35 点生命")
	check(not reward_board.visible, "选择奖励后面板隐藏")
	check(not tree.paused, "选择奖励后暂停解除")
	check(portal.enabled and portal.visible and portal.monitoring, "奖励选择后返回传送门激活")

	var health_after_first: float = health_node.health
	var progress_after_first: int = int(state.get("system_progress"))
	check(not controller.select_reward(&"ammo"), "奖励不能重复选择")
	check(is_equal_approx(health_node.health, health_after_first), "重复选择不重复治疗")
	arena.combat_cleared.emit(arena)
	await tree.process_frame
	await tree.process_frame
	check(not reward_board.visible and not tree.paused, "重复清场不再次显示奖励面板")
	check(is_equal_approx(health_node.health, health_after_first), "重复清场不重复治疗")
	check(int(state.get("system_progress")) == progress_after_first, "重复清场不重复增加进度")

	_check(controller.return_to_tavern(), "返回酒馆成功")
	_check(str(state.get("task_a_returned")) == "returned", "交任务字段已写入")
	_check(await _wait_until(tree, func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED and stage.get_phase() == StagePhases.Id.RETURNED),
		"任务完成且阶段进入 RETURNED")
	var return_pos: Vector3 = return_point.global_position
	check(player.global_position.distance_to(return_pos) < 0.01, "玩家传送到酒馆返回点")
	check(player.velocity.is_zero_approx() and is_zero_approx(player.current_speed) and not player.is_sprinting,
		"返回时清除移动状态")
	check(not portal.enabled and not portal.visible and not portal.monitoring, "返回后传送门关闭")
	check(not controller.return_to_tavern(), "重复返回被拒绝")

	await _close_scene(scene)
	await _check_ammo_reward_path()
	await _check_system_progress_reward_path()

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish(null)


func _check_ammo_reward_path() -> void:
	var context := await _prepare_fresh_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var arena = context["arena"]
	var enemy = context["enemy"]
	var player = context["player"]
	var board = context["board"]
	var controller = context["controller"]
	var portal = context["portal"]
	var slots = player.get_node("WeaponSlots")

	slots.select_slot(1)
	slots.select_slot(0)
	for slot in range(2):
		var ammo_state = slots._ammo_states[slot]
		if ammo_state != null:
			ammo_state.magazine_rounds = 0
			ammo_state.is_reloading = true
	for ammo_type in slots.reserve_ammo.keys():
		slots.reserve_ammo[ammo_type] = 0

	enemy.receive_hit(10000.0)
	check(await _wait_until(tree, func() -> bool: return board.visible and tree.paused),
		"弹药奖励：真实清场暂停并显示面板")
	check(controller.select_reward(&"ammo"), "弹药奖励：选择成功")
	check(
		slots.reserve_ammo[WeaponData.AmmoType.RIFLE] == slots.starting_rifle_ammo
		and slots.reserve_ammo[WeaponData.AmmoType.PISTOL] == slots.starting_pistol_ammo
		and slots.reserve_ammo[WeaponData.AmmoType.SMG] == slots.starting_smg_ammo
		and slots.reserve_ammo[WeaponData.AmmoType.SHOTGUN] == slots.starting_shotgun_ammo,
		"弹药奖励：四类备弹恢复初始值"
	)
	var magazines_refilled := true
	for slot in range(2):
		var data = slots._weapon_at(slot)
		var ammo_state = slots._ammo_states[slot]
		if data != null:
			magazines_refilled = magazines_refilled and ammo_state != null \
				and ammo_state.magazine_rounds == data.magazine_capacity \
				and not ammo_state.is_reloading
	check(magazines_refilled, "弹药奖励：已初始化弹匣补满并取消换弹")
	check(not board.visible and not tree.paused, "弹药奖励：面板隐藏且暂停解除")
	check(portal.enabled and portal.visible and portal.monitoring, "弹药奖励：返回传送门激活")
	await _close_scene(scene)


func _check_system_progress_reward_path() -> void:
	var context := await _prepare_fresh_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var state = context["state"]
	var enemy = context["enemy"]
	var board = context["board"]
	var controller = context["controller"]
	var portal = context["portal"]
	var progress_bar: ProgressBar = scene.get_node("QuestPanel/Panel/Margin/Content/SystemProgress/Bar")
	var progress_label: Label = scene.get_node("QuestPanel/Panel/Margin/Content/SystemProgress/Label")

	enemy.receive_hit(10000.0)
	check(await _wait_until(tree, func() -> bool: return board.visible and tree.paused),
		"系统进度奖励：真实清场暂停并显示面板")
	check(progress_bar.value == 0.0 and progress_label.text.contains("0 / 100"), "系统进度奖励：选择前面板显示零进度")
	check(controller.select_reward(&"system_progress"), "系统进度奖励：选择成功")
	await tree.process_frame
	check(int(state.get("system_progress")) == 20, "系统进度奖励：进度增加到 20")
	check(progress_bar.value == 20.0 and progress_label.text.contains("20 / 100"), "系统进度奖励：任务面板显示 20 / 100")
	check(not board.visible and not tree.paused, "系统进度奖励：面板隐藏且暂停解除")
	check(portal.enabled and portal.visible and portal.monitoring, "系统进度奖励：返回传送门激活")
	await _close_scene(scene)


func _prepare_fresh_encounter() -> Dictionary:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state: Node = root.get_node("GameState")
	var quests = scene.get_node("QuestController")
	scene.get_node("EncounterController").set("reward_delay_seconds", 0.05)
	state.help_choice = ""
	state.task_a_returned = ""
	state.system_progress = 0
	state.clear_interaction_state()
	quests.reset_progress()
	await tree.process_frame
	await tree.process_frame
	state.help_choice = "accepted"
	await _wait_until(tree, func() -> bool: return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)

	var arena = scene.get_node("Arena")
	var player: CharacterBody3D = scene.get_node("Player")
	var enemy: CharacterBody3D = EnemyFixture.primary_enemy(scene)
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.global_position = arena.to_global(Vector3(-4.0, 0.0, 0.0))
	await _wait_physics_frames(tree, MAX_SETTLE_FRAMES)
	scene.get_node("StageController").set_player_in_zone(&"site", true)
	return {
		"scene": scene,
		"tree": tree,
		"state": state,
		"arena": arena,
		"player": player,
		"enemy": enemy,
		"board": scene.get_node("RewardBoard"),
		"controller": scene.get_node("EncounterController"),
		"portal": scene.get_node("Arena/CombatZone/ReturnPortal"),
	}


func _close_scene(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	current_scene = null
	await process_frame


func _require(condition: bool, label_text: String) -> void:
	check(condition, label_text)


func _check(condition: bool, label_text: String) -> void:
	check(condition, label_text)


func _has_property(node: Node, property_name: String) -> bool:
	return node.get(property_name) != null


func _wait_until(tree: SceneTree, predicate: Callable, max_frames: int = MAX_FRAMES) -> bool:
	for _frame in range(max_frames):
		if predicate.call():
			return true
		await tree.process_frame
	return false


func _wait_physics_frames(tree: SceneTree, frame_count: int) -> void:
	for _frame in range(frame_count):
		await tree.physics_frame


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
	push_error("quest encounter loop test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	if failures == 0:
		print("quest encounter loop checks: all passed")
	else:
		print("quest encounter loop checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)

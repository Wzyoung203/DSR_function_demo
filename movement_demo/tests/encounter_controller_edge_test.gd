extends SceneTree

## EncounterController 边界检查：奖励依赖缺失、死亡/外部暂停、返回依赖缺失。
## 运行：godot --headless --path movement_demo --script res://tests/encounter_controller_edge_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const MAX_FRAMES := 120
const EXPECTED_CHECKS := 34

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
	await _check_missing_reward_board()
	await _check_dead_player_reward()
	await _check_non_owner_pause()
	await _check_missing_return_player()
	await _check_missing_return_marker()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish()


func _check_missing_reward_board() -> void:
	var context := await _prepare_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var controller = context["controller"]
	var board = context["board"]
	var health = context["health"]
	var portal = context["portal"]
	var health_before: float = health.health

	controller.reward_board = null
	context["arena"].combat_cleared.emit(context["arena"])
	await tree.process_frame
	check(not tree.paused, "缺少奖励面板时不暂停")
	check(not board.visible, "缺少奖励面板时不显示面板")
	check(not controller.select_reward(&"first_aid"), "缺少奖励面板时奖励状态未打开")
	check(is_equal_approx(health.health, health_before), "缺少奖励面板时不施加奖励")
	check(not portal.enabled, "缺少奖励面板时不激活传送门")
	await _release(scene)


func _check_dead_player_reward() -> void:
	var context := await _prepare_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var controller = context["controller"]
	var board = context["board"]
	var health = context["health"]
	var player = context["player"]
	var portal = context["portal"]
	var state = context["state"]

	context["arena"].combat_cleared.emit(context["arena"])
	await tree.process_frame
	check(board.visible and tree.paused, "死亡场景前奖励面板已暂停打开")
	health.receive_hit(1000.0)
	check(player.is_dead(), "真实伤害使玩家死亡")
	check(not board.visible, "死亡后立即隐藏奖励面板")
	check(board.process_mode == Node.PROCESS_MODE_DISABLED, "死亡后立即禁用奖励面板输入")
	check(not controller.select_reward(&"first_aid"), "死亡玩家不能提交奖励")
	check(tree.paused, "死亡暂停不会被奖励选择解除")
	check(not portal.enabled, "死亡玩家不激活返回传送门")
	check(not board.visible, "死亡时冻结并隐藏奖励面板")
	check(str(state.get("task_a_returned")) == "", "死亡玩家未提交交任务字段")
	check(not controller.return_to_tavern(), "死亡玩家不能返回酒馆")
	check(str(state.get("task_a_returned")) == "", "死亡返回失败后任务仍未完成")
	await _release(scene)


func _check_non_owner_pause() -> void:
	var context := await _prepare_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var controller = context["controller"]
	var board = context["board"]
	var health = context["health"]
	var portal = context["portal"]

	health.receive_hit(50.0)
	var health_before: float = health.health
	tree.paused = true
	context["arena"].combat_cleared.emit(context["arena"])
	await tree.process_frame
	check(board.visible and tree.paused, "外部暂停时奖励面板可安全显示")
	check(controller.select_reward(&"first_aid"), "外部暂停不影响存活玩家选择奖励")
	check(health.health > health_before, "外部暂停时奖励效果正常结算")
	check(not board.visible, "外部暂停时选择后面板隐藏")
	check(portal.enabled, "外部暂停时选择后传送门激活")
	check(tree.paused, "不解除非控制器拥有的暂停")
	await _release(scene)


func _check_missing_return_player() -> void:
	var context := await _prepare_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var controller = context["controller"]
	var board = context["board"]
	var state = context["state"]
	var quests = context["quests"]
	var player = context["player"]
	var portal = context["portal"]

	context["arena"].combat_cleared.emit(context["arena"])
	await tree.process_frame
	check(board.visible and tree.paused, "缺少返回玩家前奖励面板正常打开")
	check(controller.select_reward(&"first_aid"), "缺少返回玩家前奖励可正常选择")
	player.remove_from_group(&"player")
	check(not controller.return_to_tavern(), "缺少玩家时拒绝返回酒馆")
	check(str(state.get("task_a_returned")) == "", "缺少玩家时拒绝写入交任务字段")
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS, "缺少玩家时任务保持进行中")
	check(portal.enabled, "缺少玩家时返回失败且传送门保持激活")
	await _release(scene)


func _check_missing_return_marker() -> void:
	var context := await _prepare_encounter()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var controller = context["controller"]
	var board = context["board"]
	var state = context["state"]
	var quests = context["quests"]
	var portal = context["portal"]

	context["arena"].combat_cleared.emit(context["arena"])
	await tree.process_frame
	check(board.visible and tree.paused, "缺少返回标记前奖励面板正常打开")
	check(controller.select_reward(&"first_aid"), "缺少返回标记前奖励可正常选择")
	controller.return_point = null
	check(not controller.return_to_tavern(), "缺少返回标记时拒绝返回酒馆")
	check(str(state.get("task_a_returned")) == "", "缺少返回标记时拒绝写入交任务字段")
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS, "缺少返回标记时任务保持进行中")
	check(portal.enabled, "缺少返回标记时返回失败且传送门保持激活")
	await _release(scene)


func _prepare_encounter() -> Dictionary:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state: Node = root.get_node("GameState")
	var quests = scene.get_node("QuestController")
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
	player.set_physics_process(false)
	arena.get_node("Enemy").set_physics_process(false)
	player.global_position = arena.to_global(Vector3(-4.0, 0.0, 0.0))
	scene.get_node("StageController").set_player_in_zone(&"site", true)
	await tree.process_frame

	return {
		"scene": scene,
		"tree": tree,
		"state": state,
		"quests": quests,
		"arena": arena,
		"player": player,
		"health": player.get_node("Health"),
		"controller": scene.get_node("EncounterController"),
		"board": scene.get_node("RewardBoard"),
		"portal": scene.get_node("Arena/CombatZone/ReturnPortal"),
	}


func _wait_until(tree: SceneTree, predicate: Callable, max_frames: int = MAX_FRAMES) -> bool:
	for _frame in range(max_frames):
		if predicate.call():
			return true
		await tree.process_frame
	return false


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
	push_error("encounter controller edge test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
		current_scene.queue_free()
	if failures == 0:
		print("encounter controller edge checks: all passed")
	else:
		print("encounter controller edge checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)

class_name EncounterController
extends Node

## 战斗遭遇控制器：监听竞技场清场，暂停并打开奖励面板；奖励落定后激活返回传送门，
## 玩家经传送门返回酒馆时写入任务交差字段。任务状态与阶段仍由 QuestController / StageController 权威判定。

@export var quest_id: StringName = &"task_a"
@export var turnin_field: StringName = &"task_a_returned"
@export var turnin_value: String = "returned"
@export var heal_amount: float = 35.0
@export var system_progress_amount: int = 20
## 清场后等待多久再暂停并显示奖励面板；测试可缩短但不能改变默认值。
@export var reward_delay_seconds: float = 5.0

## 场景注入点：竞技场、奖励面板、返回标记、返回传送门。
@export var arena_path: NodePath
@export var reward_board_path: NodePath
@export var return_point_path: NodePath
@export var portal_path: NodePath

@onready var arena: Node = get_node_or_null(arena_path)
@onready var reward_board: CanvasLayer = get_node_or_null(reward_board_path)
@onready var return_point: Marker3D = get_node_or_null(return_point_path)
@onready var portal: Area3D = get_node_or_null(portal_path)

var _reward_open := false
var _reward_selected := false
var _pause_owned := false
var _reward_pending := false
var _reward_generation := 0


func _ready() -> void:
	_bind_signals()


func _bind_signals() -> void:
	if arena != null and arena.has_signal(&"combat_cleared") and not arena.combat_cleared.is_connected(_on_combat_cleared):
		arena.combat_cleared.connect(_on_combat_cleared)
	if reward_board != null and reward_board.has_signal(&"reward_selected") and not reward_board.reward_selected.is_connected(_on_reward_selected):
		reward_board.reward_selected.connect(_on_reward_selected)
	if portal != null and portal.has_signal(&"interacted") and not portal.interacted.is_connected(_on_portal_interacted):
		portal.interacted.connect(_on_portal_interacted)
	_bind_player_death()


func _bind_player_death() -> void:
	var player := _player()
	if player == null:
		return
	var health := player.get_node_or_null("Health")
	if health != null and health.has_signal(&"died") and not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died)


func _on_combat_cleared(region: Node) -> void:
	if _reward_pending or _reward_open or _reward_selected:
		return
	if region != arena:
		return
	if not _player_alive():
		return
	if _quest_status() != QuestController.Status.IN_PROGRESS:
		return
	if _player_zone() != &"site":
		return
	if reward_board == null or not reward_board.has_method(&"show_board"):
		push_error("EncounterController: reward board is missing or does not implement show_board()")
		return
	_reward_pending = true
	var generation := _reward_generation + 1
	_reward_generation = generation
	await get_tree().create_timer(maxf(0.0, reward_delay_seconds), true, false, true).timeout
	if not is_inside_tree() or generation != _reward_generation:
		return
	_reward_pending = false
	if _reward_open or _reward_selected:
		return
	if not _player_alive():
		return
	if _quest_status() != QuestController.Status.IN_PROGRESS:
		return
	if _player_zone() != &"site":
		return
	var tree := get_tree()
	_reward_open = true
	_pause_owned = not tree.paused
	if _pause_owned:
		tree.paused = true
	reward_board.show_board()


func _on_reward_selected(reward_id: StringName) -> void:
	select_reward(reward_id)


func _on_portal_interacted(_interactable: Node, _player: Node3D) -> void:
	return_to_tavern()


func _on_player_died() -> void:
	if _reward_pending:
		_reward_pending = false
		_reward_generation += 1
	if _reward_open:
		_freeze_for_dead_player()


## 战斗奖励分派。无效奖励或重复选择返回 false；成功则解除暂停并激活返回传送门。
func select_reward(reward_id: StringName) -> bool:
	if _reward_selected or not _reward_open:
		return false
	if not _player_alive():
		_freeze_for_dead_player()
		return false
	match reward_id:
		&"first_aid":
			_heal_player()
		&"ammo":
			_refill_ammo()
		&"system_progress":
			_add_progress()
		_:
			return false
	var tree := get_tree()
	var owned_pause := _pause_owned
	_reward_selected = true
	_reward_open = false
	_pause_owned = false
	if reward_board != null:
		reward_board.visible = false
	if owned_pause:
		tree.paused = false
	activate_return_portal()
	return true


## 激活返回传送门：奖励已选择且任务仍在进行中时由玩家触发返回。
func activate_return_portal() -> void:
	if portal == null:
		return
	portal.enabled = true
	portal.visible = true
	portal.monitoring = true


## 只有奖励已选择且任务仍在进行中才允许返回；成功写入交差字段并把玩家送回酒馆。
func return_to_tavern() -> bool:
	if not _reward_selected:
		return false
	if _quest_status() != QuestController.Status.IN_PROGRESS:
		return false
	var player := _player()
	if player == null:
		push_error("EncounterController: cannot return to tavern without a player")
		return false
	if return_point == null or not is_instance_valid(return_point) or not return_point.is_inside_tree():
		push_error("EncounterController: cannot return to tavern without a valid return point")
		return false
	var state := _state()
	if state == null:
		push_error("EncounterController: cannot return to tavern without GameState")
		return false
	state.set(turnin_field, turnin_value)
	_zero_player_motion()
	player.global_position = return_point.global_position
	if portal != null:
		portal.enabled = false
		portal.visible = false
		portal.monitoring = false
	return true


func _heal_player() -> void:
	var player := _player()
	if player == null:
		return
	var health := player.get_node_or_null("Health")
	if health != null and health.has_method(&"heal"):
		health.heal(heal_amount)


func _refill_ammo() -> void:
	var player := _player()
	if player == null:
		return
	var slots := player.get_node_or_null("Equipment")
	if slots != null and slots.has_method(&"refill_all_ammo"):
		slots.refill_all_ammo()


func _add_progress() -> void:
	var state := _state()
	if state != null and state.has_method(&"add_system_progress"):
		state.add_system_progress(system_progress_amount)


func _zero_player_motion() -> void:
	var player := _player()
	if player == null:
		return
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.is_sprinting = false


## 玩家死亡时保留死亡暂停，冻结隐藏面板但不清除暂停所有权之外的任何状态。
func _freeze_for_dead_player() -> void:
	_reward_open = false
	_pause_owned = false
	if reward_board == null:
		return
	reward_board.visible = false
	reward_board.process_mode = Node.PROCESS_MODE_DISABLED


func _player() -> Node3D:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"player") if tree != null else null


func _player_alive() -> bool:
	var player := _player()
	if player == null:
		return false
	if player.has_method(&"is_dead"):
		return not player.is_dead()
	var health := player.get_node_or_null("Health")
	return health == null or not bool(health.get("is_dead"))


func _state() -> Node:
	return get_node_or_null("/root/GameState")


func _quests() -> Node:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"quest_controller") if tree != null else null


func _stage() -> Node:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"stage_controller") if tree != null else null


func _quest_status() -> int:
	var quests := _quests()
	if quests == null or not quests.has_method(&"status_of"):
		return QuestController.Status.NOT_STARTED
	return int(quests.status_of(quest_id))


func _player_zone() -> StringName:
	var stage := _stage()
	if stage == null or not stage.has_method(&"get_player_zone"):
		return &"other"
	return StringName(stage.get_player_zone())

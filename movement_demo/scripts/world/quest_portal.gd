class_name QuestPortal
extends Interactable

## 读取任务状态的传送门；任务状态仍由 QuestController 唯一维护。
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

@export var quest_id: StringName = &"task_a"

var _quests: Node


func _ready() -> void:
	super()
	call_deferred(&"_bind_quests")


func conditions_met() -> bool:
	return super() and _quest_in_progress()


func _refresh_prompt() -> void:
	blocked_hint = "任务进行中" if _quest_in_progress() else "需要先接取 A 的任务"
	super()


func _bind_quests() -> void:
	if not is_inside_tree():
		return
	var quests := _find_quests()
	if _quests == quests:
		return
	_quests = quests
	if _quests != null and _quests.has_signal(&"quest_changed") and not _quests.quest_changed.is_connected(_on_quest_changed):
		_quests.quest_changed.connect(_on_quest_changed)
	_refresh_prompt()


func _on_quest_changed(_quest_id: StringName, _previous: int, _current: int) -> void:
	_refresh_prompt()


func _quest_in_progress() -> bool:
	if _quests == null or not is_instance_valid(_quests):
		_quests = _find_quests()
	if _quests == null or not _quests.has_method(&"status_of"):
		return false
	return int(_quests.status_of(quest_id)) == QuestControllerScript.Status.IN_PROGRESS


func _find_quests() -> Node:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"quest_controller") if tree != null else null

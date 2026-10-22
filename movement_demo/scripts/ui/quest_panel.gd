extends CanvasLayer

## 任务面板：左上角常驻显示配置表里的全部任务与状态。
## 只读任务控制器的查询接口与 quest_changed 信号，不写任何状态，也不抢输入。

@onready var quest_list: Label = $Panel/Margin/Content/QuestList

var _quests
var _state


func _ready() -> void:
	add_to_group(&"quest_panel")
	_bind_state()
	_bind()
	# 控制器可能晚一步绑定配置表，下一帧再刷一次。
	call_deferred("_refresh")


func _bind() -> void:
	var controller := _find_quests()
	if controller == null or controller == _quests:
		return
	_quests = controller
	if _quests.has_signal(&"quest_changed") and not _quests.quest_changed.is_connected(_on_quest_changed):
		_quests.quest_changed.connect(_on_quest_changed)


func _bind_state() -> void:
	var state := _find_state()
	if state == _state:
		return
	if _state != null and is_instance_valid(_state) and _state.has_signal(&"system_progress_changed") and _state.system_progress_changed.is_connected(_on_system_progress_changed):
		_state.system_progress_changed.disconnect(_on_system_progress_changed)
	_state = state
	if _state != null and _state.has_signal(&"system_progress_changed") and not _state.system_progress_changed.is_connected(_on_system_progress_changed):
		_state.system_progress_changed.connect(_on_system_progress_changed)
	_refresh()


func _on_quest_changed(_quest_id: StringName, _previous: int, _current: int) -> void:
	_refresh()


func _on_system_progress_changed(_previous: int, _current: int) -> void:
	_refresh()


func _refresh() -> void:
	_bind()
	_bind_state()
	if quest_list == null:
		return
	var progress := 0
	if _state != null:
		progress = int(_state.get("system_progress"))
	var lines: Array[String] = ["系统进度：%d" % progress]
	var entries := _entries()
	if entries.is_empty():
		lines.append("暂无任务")
	else:
		for entry in entries:
			lines.append(_line_text(entry))
	quest_list.text = "\n".join(lines)


func _entries() -> Array:
	if _quests == null or not _quests.has_method(&"get_quest_entries"):
		return []
	return _quests.get_quest_entries()


func _line_text(entry: Dictionary) -> String:
	var status := "未解锁" if bool(entry.get("locked", false)) else str(entry.get("status_name", "未接"))
	var text := "%s：%s" % [str(entry.get("name", "")), status]
	var area := str(entry.get("target_area", ""))
	if not area.is_empty():
		text += "（场地 %s）" % area
	return text


func _find_quests() -> Node:
	var tree := get_tree()
	return tree.get_first_node_in_group(&"quest_controller") if tree != null else null


func _find_state() -> Node:
	var tree := get_tree()
	return tree.root.get_node_or_null("GameState") if tree != null else null

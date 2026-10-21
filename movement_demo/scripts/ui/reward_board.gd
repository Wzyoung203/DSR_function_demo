extends CanvasLayer

## 战斗奖励三选一面板：默认隐藏，暂停时也能处理输入；每次显示只能选择并发出一个奖励。

signal reward_selected(reward_id: StringName)

const REWARD_IDS: Array[StringName] = [&"first_aid", &"ammo", &"system_progress"]

@onready var _buttons: Array[Button] = [
	$Panel/Margin/Content/Buttons/FirstAid/Button,
	$Panel/Margin/Content/Buttons/Ammo/Button,
	$Panel/Margin/Content/Buttons/SystemProgress/Button,
]

var _selected: StringName = &""


func _ready() -> void:
	for index in REWARD_IDS.size():
		_buttons[index].pressed.connect(select_reward.bind(REWARD_IDS[index]))


func show_board() -> void:
	_selected = &""
	visible = true
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func select_reward(reward_id: StringName) -> bool:
	if not _selected.is_empty() or REWARD_IDS.find(reward_id) == -1:
		return false
	_selected = reward_id
	visible = false
	reward_selected.emit(reward_id)
	return true

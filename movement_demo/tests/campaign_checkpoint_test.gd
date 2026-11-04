extends SceneTree

## Campaign checkpoints preserve the tavern state immediately after a level
## completion, before its reward is claimed and before A unlocks the next level.
const GameStateScript := preload("res://scripts/systems/game_state.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = GameStateScript.new()
	root.add_child(state)
	_check(state.has_method(&"record_campaign_checkpoint"), "GameState exposes checkpoint recording")
	_check(state.has_method(&"restore_campaign_checkpoint"), "GameState exposes checkpoint restoration")
	if not state.has_method(&"record_campaign_checkpoint") \
			or not state.has_method(&"restore_campaign_checkpoint"):
		_finish(state)
		return

	state.completed_level = 2
	state.available_level = 2
	state.claimed_reward_levels = {1: true}
	state.system_progress = 20
	state.task_a_returned = "returned"
	state.record_campaign_checkpoint(2, {"health": {"health": 73.0}})

	state.completed_level = 3
	state.available_level = 4
	state.claimed_reward_levels = {1: true, 2: true, 3: true}
	state.system_progress = 70
	state.task_a_returned = "later"
	state.pending_player_state = {"equipment": {"active_slot": 1}}
	_check(state.restore_campaign_checkpoint(), "Completed checkpoint can be restored")
	_check(state.completed_level == 2 and state.available_level == 2,
		"Restore returns to the level-completion hotel state")
	_check(state.claimed_reward_levels == {1: true},
		"Restore reopens the latest level reward while preserving earlier claims")
	_check(state.system_progress == 20, "Restore rolls back system progress granted after completion")
	_check(state.task_a_returned == "returned", "Restore returns campaign completion markers to the checkpoint")
	_check(state.pending_player_state == {"health": {"health": 73.0}},
		"Restore makes the completion-time player snapshot available to the tavern")

	state.pending_player_state = {"health": {"health": 12.0}}
	state.campaign_checkpoint = {}
	_check(not state.restore_campaign_checkpoint() and state.completed_level == 2
			and state.pending_player_state == {"health": {"health": 12.0}},
		"An absent checkpoint leaves current campaign state untouched")
	_finish(state)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)


func _finish(state: Node) -> void:
	if is_instance_valid(state):
		state.free()
	print("campaign checkpoint checks: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

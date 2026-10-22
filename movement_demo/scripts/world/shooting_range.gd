extends Node3D

signal presentation_reset(region: Node)
signal combat_cleared(region: Node)

## Match members by faction and communication group; only team awareness is shared.
@export var team_cooperation_bindings: Array[EnemyTeamCooperationBinding] = []

var players_inside: Array[Node3D] = []
var enemies: Array[CharacterBody3D] = []
var _combat_zone: Area3D
var tactical_map = preload("res://scripts/enemy/services/enemy_tactical_map.gd").new()
var cooperation = preload("res://scripts/enemy/services/enemy_cooperation.gd").new()
var _encounter_cleared: bool = false


func enemy_environment() -> Dictionary:
	cooperation.configure_team_bindings(team_cooperation_bindings)
	cooperation.refresh_squads()
	var navigation := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	tactical_map.bind_region(navigation)
	return {"zone": get_node_or_null("CombatZone"), "navigation": navigation, "cooperation": cooperation, "tactical_map": tactical_map}


func register_enemy(enemy: CharacterBody3D) -> void:
	if not enemies.has(enemy):
		enemies.append(enemy)
	var died_callback := Callable(self, "_on_enemy_died")
	if enemy.has_signal("died") and not enemy.is_connected("died", died_callback):
		enemy.connect("died", died_callback)


func unregister_enemy(enemy: CharacterBody3D) -> void:
	var died_callback := Callable(self, "_on_enemy_died")
	if enemy.has_signal("died") and enemy.is_connected("died", died_callback):
		enemy.disconnect("died", died_callback)
	enemies.erase(enemy)
	cooperation.unregister(enemy.get_instance_id())


func _ready() -> void:
	_bind_combat_zone()


func _physics_process(delta: float) -> void:
	cooperation.configure_team_bindings(team_cooperation_bindings)
	_bind_combat_zone()
	for player in players_inside:
		if is_instance_valid(player) and not player.is_dead() and not player.is_in_dialogue:
			cooperation.advance(delta)
			break
	_check_combat_cleared()


func _bind_combat_zone() -> void:
	var zone := get_node_or_null("CombatZone") as Area3D
	if _combat_zone == zone: return
	if is_instance_valid(_combat_zone):
		_combat_zone.body_entered.disconnect(_on_player_entered)
		_combat_zone.body_exited.disconnect(_on_player_exited)
	var had_players := not players_inside.is_empty()
	players_inside.clear()
	_combat_zone = zone
	if had_players: _reset_targets()
	if zone == null: return
	zone.body_entered.connect(_on_player_entered)
	zone.body_exited.connect(_on_player_exited)
	for body in zone.get_overlapping_bodies(): _on_player_entered(body)


func _on_player_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not players_inside.has(body):
		players_inside.append(body)


func _on_player_exited(body: Node3D) -> void:
	if not players_inside.has(body):
		return
	players_inside.erase(body)
	if players_inside.is_empty():
		_reset_targets()


func _reset_targets() -> void:
	cooperation.reset()
	tactical_map.reset()
	_encounter_cleared = false
	presentation_reset.emit(self)
	# 直接子靶与注册的嵌套敌人去重，只刷新本区域。
	var targets: Array[Node] = []
	targets.assign(get_children())
	for enemy in enemies:
		if is_instance_valid(enemy) and not targets.has(enemy):
			targets.append(enemy)
	for target in targets:
		# 重开卸载场景也会发出离场信号；已出树的目标无需刷新。
		if target.is_inside_tree() and target.has_method("reset_target"):
			target.reset_target()

func _exit_tree() -> void:
	tactical_map.release()


func _on_enemy_died() -> void:
	_check_combat_cleared()


func _check_combat_cleared() -> void:
	if _encounter_cleared or players_inside.is_empty():
		return
	var registered_enemies: Array[CharacterBody3D] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree():
			registered_enemies.append(enemy)
	if registered_enemies.is_empty():
		return
	for enemy in registered_enemies:
		if not enemy.get("is_dead"):
			return
	_encounter_cleared = true
	combat_cleared.emit(self)

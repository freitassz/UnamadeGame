extends Area2D
class_name HitBox

@export var damage:= 10
@export var knockback:= 80
@export var player_knockback:= 20

@export var weapon_push: float = 60
@export var combo_window_time: float = 0.6
@export var attack_interval_time: float = 0.1

signal recoil(player_knockback_value: float, enemy_knockback_value: float, hit_position: Vector2) # Renamed for clarity

func _init() -> void:
	collision_layer = 16
	collision_mask = 32

func _ready() -> void:
	area_entered.connect(Callable(self, "_on_area_entered"))

func get_weapon_properties() -> Dictionary:
	return {
		"weapon_push": weapon_push,
		"combo_window_time": combo_window_time,
		"attack_interval_time": attack_interval_time
	}

func _on_area_entered(hurtbox: HurtBox) -> void:
	emit_signal("recoil", player_knockback, knockback, global_position)

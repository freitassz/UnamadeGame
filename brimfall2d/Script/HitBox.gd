extends Area2D
class_name HitBox

@export var damage:= 10
@export var knockback:= 80

signal recoil(knockback_value: float, hit_position: Vector2)

func _init() -> void:
	collision_layer = 2
	collision_mask = 4

func _ready() -> void:
	area_entered.connect(Callable(self, "_on_area_entered"))

func _on_area_entered(hurtbox: HurtBox) -> void:
	emit_signal("recoil", knockback, global_position)

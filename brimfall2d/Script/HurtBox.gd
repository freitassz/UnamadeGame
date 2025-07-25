extends Area2D
class_name HurtBox

func _init() -> void:
	collision_layer = 32
	collision_mask = 16

func _ready() -> void:
	area_entered.connect(Callable(self, "_on_area_entered"))

func _on_area_entered(hitbox: HitBox) -> void:
	if hitbox == null:
		return

	if owner and owner.has_method("take_damage"):
		owner.take_damage(hitbox.damage)

	if owner and owner.has_method("apply_knockback"):
		owner.apply_knockback(hitbox.knockback, hitbox.global_position)

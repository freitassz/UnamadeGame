# HurtBox.gd
extends Area2D
class_name HurtBox

func _init() -> void:
	collision_layer = 32
	collision_mask = 16

func _ready() -> void:
	area_entered.connect(Callable(self, "_on_area_entered"))

func _on_area_entered(hitbox: HitBox) -> void:
	if not hitbox:
		return

	var defender_body = owner # The CharacterBody2D that owns this HurtBox
	var attacker_body = hitbox.owner # The CharacterBody2D that owns the HitBox

	if not defender_body or not attacker_body or defender_body == attacker_body:
		return

	for group_name in defender_body.get_groups():
		if attacker_body.is_in_group(group_name):
			return 

	if defender_body.has_method("take_damage"):
		defender_body.take_damage(hitbox.damage)
		print("HurtBox: Damage taken from an external source.")

	if defender_body.has_method("apply_knockback"):
		if defender_body.is_in_group("player"):
			defender_body.apply_knockback(hitbox.player_knockback, hitbox.global_position)
			print("HurtBox: Player received knockback.")
		else:
			defender_body.apply_knockback(hitbox.knockback, hitbox.global_position)
			print("HurtBox: Non-player received knockback.")

extends Node

@export var max_health := 10
var health: int

signal died

func _ready() -> void:
	health = max_health

func take_damage(amount: int):
	health = health - amount
	emit_signal("health_changed", health)
	print(health)
	if health <= 0:
		emit_signal("died")

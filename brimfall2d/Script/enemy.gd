extends CharacterBody2D

@onready var health = $Health
#==========Knockback==========#
var knockback_vector := Vector2.ZERO
@export var knockback_resistance := 1.0
@export var knockback_friction := 100.0

func _ready() -> void:
	health.connect("died", Callable(self, "_on_died"))

func _physics_process(delta: float) -> void:
	if knockback_vector != Vector2.ZERO:
		velocity = knockback_vector
		move_and_slide()

		knockback_vector = knockback_vector.move_toward(Vector2.ZERO, knockback_friction * delta)
		if knockback_vector.length() < 10:
			knockback_vector = Vector2.ZERO

func take_damage(amount: int) -> void:
	health.take_damage(amount)

func _on_died():
	print("Inimigo morreu!")
	queue_free()

func apply_knockback(force: float, hit_position: Vector2) -> void:
	# Calcula a direção do knockback (do alvo para longe da posição do ataque)
	var knockback_direction = (global_position -  hit_position).normalized()
	# Calcula a força final do knockback, levando em conta a resistência
	var final_knockback_force = force / knockback_resistance
	# Define o vetor de knockback
	knockback_vector = knockback_direction * final_knockback_force

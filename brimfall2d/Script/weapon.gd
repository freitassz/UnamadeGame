extends Node2D

@onready var hitbox: Area2D = $Sprite2D/HitBox
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite_2d: Node2D = $Combos

var is_attacking: bool = false
@onready var player: CharacterBody2D = get_node(player_node_path) as CharacterBody2D # Cast or type-hint
@export var player_node_path: NodePath # Add this export variable to set the player path

var attack_direction_angle: float # New variable to store the direction at the start of the attack

func _ready():
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	sprite_2d.visible = false

func _process(delta):
	_update_weapon_direction()

func _input(event):
	if event.is_action_pressed("attack") and not is_attacking:
		start_attack()

func start_attack():
	#If para parar o ataque caso esteja fazendo outra ação
	if player and player.current_movement_state == player.MovementState.ROLLING || player.current_movement_state == player.MovementState.RECOILING:
		return

	is_attacking = true
	sprite_2d.visible = true

	attack_direction_angle = rotation


	if animation_player:
		animation_player.play("Combo1")

func combo1():
	pass

func combo2():
	pass

func combo3():
	pass

func _on_animation_finished(anim_name: String):
	if anim_name == "Combo1":
		is_attacking = false
		sprite_2d.visible = false

func _update_weapon_direction():
	if not is_attacking:
		var mouse_position = get_global_mouse_position()
		var weapon_global_position = global_position
		var direction = mouse_position - weapon_global_position
		rotation = direction.angle() - PI
	else:
		rotation = attack_direction_angle

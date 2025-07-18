extends Node2D # Este é o nó principal da sua arma

@onready var hitbox: Area2D = $Sprite2D/HitBox
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite_2d: Sprite2D = $Sprite2D 

var is_attacking: bool = false

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
	is_attacking = true
	sprite_2d.visible = true 

	if animation_player:
		animation_player.play("Combo1")

func _on_animation_finished(anim_name: String):
	if anim_name == "Combo1":
		is_attacking = false
		sprite_2d.visible = false

func _update_weapon_direction():
	var mouse_position = get_global_mouse_position()
	var weapon_global_position = global_position
	var direction = mouse_position - weapon_global_position
	rotation = direction.angle() - PI

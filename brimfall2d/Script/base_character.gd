extends CharacterBody2D
###ALTERAR DEPOIS, POIS O COMBO1 E 2 N PRECISAM ESTAR AQ E O HITBOX TA ERRADO O SCRIPT
@onready var combo1 = $Body/Weapon/Combos/Combo1/Sprite2D/HitBox # Consider moving this signal connection to the weapon script
@onready var combo2 = $Body/Weapon/Combos/Combo2/Sprite2D/HitBox # Consider moving this signal connection to the weapon script
@onready var weapon = $Body/Weapon
@onready var animation_player = $AnimationPlayer
@onready var character_sprite = $AnimatedSprite2D
@onready var player_sprite = $Body/BodyTexture
@onready var health = $Health

@export_category("Rolling")
@export var roll_speed: float = 250.0
@export var roll_duration: float = 0.25
@export var roll_cooldown: float = 0.5
@export_category("Invincibility")
@export var blink_interval: float = 0.1
@export var invincibility_time: float = 0.25
@export_category("Recoil")
@export var player_recoil_strength: float = 1.0
@export var recoil_friction: float = 100.0
@export var min_recoil_speed_threshold: float = 1.0
@export_category("Others")
@export var walk_speed: float = 100.0
@export var attack_pause_duration: float = 0.1

# === States ===#
enum MovementState {
	IDLE,
	WALKING,
	ROLLING,
	RECOILING,
	ATTACKING
}
var current_movement_state: MovementState = MovementState.IDLE
var animation_dir: int = -1 # 0 para frente/baixo, 1 para costas/cima
var last_walk_animation_played: String = "WALK" # Armazena a última animação de caminhada tocada

# === Roll Variables ===#
var is_rolling: bool = false
var roll_direction: Vector2 = Vector2.ZERO
var roll_timer: float = 0.0
var roll_cooldown_timer: float = 0.0
# === Invincibility Variables ===#
var is_invincible: bool = false
var invincibility_timer: float = 0.0
var blink_timer: float = 0.0
# === Recoil Variables ===#
var is_recoiling: bool = false
var recoil_vector := Vector2.ZERO
# === Attack Variables ===#
var is_attacking: bool = false
var attack_lunge_speed_current: float = 0.0
var attack_lunge_direction: Vector2 = Vector2.ZERO

func _ready():
	if character_sprite:
		character_sprite.visible = true

	health.connect("died", Callable(self, "_on_died"))
	combo1.connect("recoil", Callable(self, "_on_hitbox_recoil_signal"))
	combo2.connect("recoil", Callable(self, "_on_hitbox_recoil_signal"))
	weapon.connect("attack", Callable(self, "_is_attacking"))

func _process(delta: float) -> void:
	if is_invincible:
		invincibility_timer -= delta
		blink_timer -= delta
		if blink_timer <= 0.0:
			blink_timer = blink_interval
			if character_sprite:
				character_sprite.visible = not character_sprite.visible

		if invincibility_timer <= 0.0:
			is_invincible = false
			if character_sprite:
				character_sprite.visible = true

func _physics_process(delta: float) -> void:
	if roll_cooldown_timer > 0.0:
		roll_cooldown_timer -= delta

	if is_recoiling:
		_handle_recoil(delta)
	elif is_rolling:
		_handle_roll(delta)
	elif is_attacking:
		_handle_attack_lunge(delta)
	else:
		var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

		if Input.is_action_just_pressed("roll") and roll_cooldown_timer <= 0.0:
			_start_roll(input_direction)
		else:
			var new_state: MovementState
			var current_speed: float

			if input_direction.length() > 0:
				new_state = MovementState.WALKING
				current_speed = walk_speed
				_update_walk_animation(input_direction) # Passa input_direction
			else:
				new_state = MovementState.IDLE
				current_speed = 0.0

			_set_movement_state(new_state)
			velocity = input_direction.normalized() * current_speed
			move_and_slide()

func _set_movement_state(new_state: MovementState) -> void:
	if current_movement_state == new_state:
		return

	current_movement_state = new_state
	_update_animation()

func _update_animation() -> void:
	if not animation_player:
		return

	match current_movement_state:
		MovementState.IDLE:
			# Baseia-se na última animação de caminhada tocada
			if animation_dir == 1:
				if animation_player.current_animation != "IDLE_BACK": # Verifique se esta animação existe
					animation_player.play("IDLE_BACK")
			else:
				if animation_dir == 0:
					animation_player.play("IDLE")
		MovementState.WALKING:
			pass
		MovementState.ROLLING:
			if animation_player.current_animation != "ROLL":
				animation_player.play("ROLL")
		MovementState.RECOILING:
			if animation_player.current_animation != "idle":
				animation_player.play("idle") # ALTERAR DEPOIS POR RECOIL ANIMATION
		MovementState.ATTACKING:
			if animation_dir == 0:
				if animation_player.current_animation != "ATTACK":
					animation_player.play("ATTACK")
			elif animation_dir == 1:
				if animation_player.current_animation != "ATTACK_BACK":
					animation_player.play("ATTACK_BACK")

func _update_walk_animation(input_direction: Vector2) -> void: # Recebe input_direction como parâmetro
	# --- Lógica de Virar o Sprite Horizontalmente ---
	if input_direction.x > 0: # Movendo para a direita
		player_sprite.flip_h = true
	elif input_direction.x < 0: # Movendo para a esquerda
		player_sprite.flip_h = false
	# --- Fim Lógica de Virar o Sprite Horizontalmente ---

	# --- Lógica para Atualizar Animação de Caminhada Constantemente e definir animation_dir ---
	if input_direction.y < 0: # Movendo para cima (ex: cima-esquerda, cima-direita)
		if animation_player.current_animation != "WALK_BACK":
			animation_player.play("WALK_BACK")
		last_walk_animation_played = "WALK_BACK" # Atualiza a última animação de caminhada
		animation_dir = 1 # Define para cima/costas
	elif input_direction.y > 0: # Movendo para baixo (ex: baixo-esquerda, baixo-direita)
		if animation_player.current_animation != "WALK":
			animation_player.play("WALK")
		last_walk_animation_played = "WALK" # Atualiza a última animação de caminhada
		animation_dir = 0 # Define para baixo/frente
	elif input_direction.x != 0: # Movendo puramente na horizontal (se não houver input vertical)
		if animation_player.current_animation != "WALK":
			animation_player.play("WALK")
		last_walk_animation_played = "WALK" # Atualiza a última animação de caminhada
		animation_dir = 0 # Assume direção frontal para horizontal puro

func _start_roll(input_dir: Vector2) -> void:
	if input_dir.length() == 0:
		if velocity.length() < 0.1:
			roll_direction = Vector2(0, 1)
		else:
			roll_direction = velocity.normalized()
	else:
		roll_direction = input_dir.normalized()

	is_rolling = true
	roll_timer = roll_duration
	roll_cooldown_timer = roll_cooldown

	is_invincible = true
	invincibility_timer = invincibility_time
	blink_timer = blink_interval

	_set_movement_state(MovementState.ROLLING)

func _handle_roll(delta: float) -> void:
	velocity = roll_direction * roll_speed
	move_and_slide()

	roll_timer -= delta
	if roll_timer <= 0.0:
		is_rolling = false
		var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_direction.length() > 0:
			_set_movement_state(MovementState.WALKING)
			velocity = input_direction.normalized() * walk_speed
		else:
			_set_movement_state(MovementState.IDLE)
			velocity = Vector2.ZERO

# NEW: Unified function for knockback
func apply_knockback(force: float, hit_position: Vector2) -> void:
	if is_rolling:
		return

	is_recoiling = true
	var knockback_direction = (global_position - hit_position).normalized()
	recoil_vector = knockback_direction * (force * player_recoil_strength)
	_set_movement_state(MovementState.RECOILING)

# This function will now be called when Combo1/2 emit their "recoil" signal
func _on_hitbox_recoil_signal(player_knockback_value: float, enemy_knockback_value: float, hit_position: Vector2):
	# Assuming 'player_knockback_value' is the force to apply to the player
	apply_knockback(player_knockback_value, hit_position)


func _handle_recoil(delta: float) -> void:
	velocity = recoil_vector
	move_and_slide()

	recoil_vector = recoil_vector.move_toward(Vector2.ZERO, recoil_friction * delta)

	if recoil_vector.length() < min_recoil_speed_threshold:
		is_recoiling = false
		recoil_vector = Vector2.ZERO
		var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_direction.length() > 0:
			_set_movement_state(MovementState.WALKING)
			velocity = input_direction.normalized() * walk_speed
		else:
			_set_movement_state(MovementState.IDLE)
			velocity = Vector2.ZERO

func _is_attacking(weapon_push: float, weapon_dir: Vector2):
	if is_rolling or is_recoiling:
		return

	# --- Lógica para definir animation_dir para o ataque (NOVO) ---
	var mouse_position = get_global_mouse_position()
	# Usamos a posição Y do mouse em relação à posição global do jogador
	if mouse_position.y < global_position.y: # Mouse acima do jogador (ataque para cima/costas)
		animation_dir = 1
	else: # Mouse abaixo ou na mesma linha que o jogador (ataque para baixo/frente)
		animation_dir = 0
	# --- Fim Lógica para definir animation_dir para o ataque ---


	is_attacking = true
	_set_movement_state(MovementState.ATTACKING)

	attack_lunge_speed_current = weapon_push
	attack_lunge_direction = weapon_dir.normalized()

	# --- Lógica de Virar o Sprite Horizontalmente para o Ataque ---
	if attack_lunge_direction.x > 0: # Atacando para a direita
		player_sprite.flip_h = true
	elif attack_lunge_direction.x < 0: # Atacando para a esquerda
		player_sprite.flip_h = false
	# --- Fim Lógica de Virar o Sprite Horizontalmente para o Ataque ---

	velocity = attack_lunge_direction * attack_lunge_speed_current

	get_tree().create_timer(attack_pause_duration).timeout.connect(Callable(self, "_end_attack_lunge"))

func _handle_attack_lunge(delta: float) -> void:
	velocity = attack_lunge_direction * attack_lunge_speed_current
	move_and_slide()

func _end_attack_lunge():
	is_attacking = false
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length() > 0:
		_set_movement_state(MovementState.WALKING)
		velocity = input_direction.normalized() * walk_speed
	else:
		_set_movement_state(MovementState.IDLE)
		velocity = Vector2.ZERO

func take_damage(amount: int) -> void:
	health.take_damage(amount)

func _on_died():
	print("Personagem Morreu!")
	###MUDAR AQUI PARA SURGIR UMA TELA DE RESSUCITAR
	queue_free()

extends CharacterBody2D
##aaaaaaaaaaaaaaaaaaaaaa
signal attack1(player_dir: Vector2)
signal attack2(player_dir: Vector2)

@onready var navigation = $Tools/Navigation as NavigationAgent2D
@onready var health = $Tools/Health
@onready var chase_area = $Areas/ChaseArea
@onready var attack_area = $Areas/AttackArea
@onready var enemy_sprite = $Body/EnemySprite
@onready var attack_component = $Body/EnemyWeapon
@onready var animation_enemy = $Animations/AnimationEnemy
@onready var hit_animation = $Animations/HitFlashAnimation

#==========Export==========#
@export var move_speed: float = 50
@export var target: CharacterBody2D = null

#==========Knockback==========#
var knockback_vector := Vector2.ZERO
@export var knockback_resistance := 1.0
@export var knockback_friction := 100.0

# === States ===#
enum EnemyState {
	IDLE,
	CHASING,
	ATTACKING,
	KNOCKBACK,
	POST_ATTACK_COOLDOWN,
	DASHING_ATTACK
}
var current_enemy_state: EnemyState = EnemyState.IDLE

# === Variáveis para a Visão ===
@export var ray_cast_length: float = 500.0
@export var collision_mask_obstacles: int = 1
var can_see_target: bool = false

# === Variáveis para o Ataque ===
@export var attack_delay_min: float = 0.5
@export var attack_delay_max: float = 1.5
var current_attack_delay: float = 0.0
var has_committed_to_attack: bool = false # Nova variável para indicar que o inimigo está comprometido com o ataque

# === Variáveis para Cooldown de Ataque ===
@export var post_attack_cooldown_min: float = 0.5
@export var post_attack_cooldown_max: float = 1.0
var current_post_attack_cooldown: float = 0.0

# === Variáveis para o Dash de Ataque ===
@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.2
var dash_direction: Vector2 = Vector2.ZERO
var current_dash_time: float = 0.0

# === Variáveis para o Dash de Movimentação (dentro de CHASING) ===
@export var dash_move_speed: float = 300.0
@export var dash_move_duration: float = 0.15
@export var dash_move_cooldown: float = 0.5
var current_dash_move_cooldown: float = 0.0
var is_dashing_move: bool = false
var dash_move_direction: Vector2 = Vector2.ZERO

#====reference====#
var player_dir = Vector2.ZERO
var animation_dir: int = 0

func _ready() -> void:
	health.connect("died", Callable(self, "_on_died"))
	if not navigation is NavigationAgent2D:
		push_error("The 'navigation' node is not a NavigationAgent2D. Please ensure it is correctly set up.")
		return
	if not attack_component:
		push_error("The 'attack_component' node is not assigned. Please ensure it is correctly set up.")
		return
	call_deferred("seeker_setup")
	chase_area.connect("body_entered", Callable(self, "_on_chase_area_entered"))
	chase_area.connect("body_exited", Callable(self, "_on_chase_area_exited"))
	attack_area.connect("body_entered", Callable(self, "_on_attack_area_entered"))
	attack_area.connect("body_exited", Callable(self, "_on_attack_area_exited"))
	navigation.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))

func _physics_process(delta: float) -> void:
	update_vision()
	_update_enemy_animation()

	match current_enemy_state:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			if target and chase_area.overlaps_body(target) and can_see_target:
				_set_enemy_state(EnemyState.CHASING)

		EnemyState.CHASING:
			handle_chasing_state(delta)

		EnemyState.ATTACKING:
			velocity = Vector2.ZERO
			current_attack_delay -= delta
			if current_attack_delay <= 0:
				perform_attack()
			
			if not target:
				_set_enemy_state(EnemyState.IDLE)
				has_committed_to_attack = false
		
		EnemyState.POST_ATTACK_COOLDOWN:
			velocity = Vector2.ZERO
			current_post_attack_cooldown -= delta
			if current_post_attack_cooldown <= 0:
				has_committed_to_attack = false
				
				if target and attack_area.overlaps_body(target):
					_set_enemy_state(EnemyState.ATTACKING)
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					has_committed_to_attack = true
				elif target and chase_area.overlaps_body(target):
					_set_enemy_state(EnemyState.CHASING)
				else:
					_set_enemy_state(EnemyState.IDLE)
		
		EnemyState.DASHING_ATTACK:
			if current_dash_time > 0:
				velocity = dash_direction * dash_speed
				current_dash_time -= delta
			else:
				_set_enemy_state(EnemyState.POST_ATTACK_COOLDOWN)
				current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)

		EnemyState.KNOCKBACK:
			if knockback_vector != Vector2.ZERO:
				velocity = knockback_vector
				knockback_vector = knockback_vector.move_toward(Vector2.ZERO, knockback_friction * delta)
				if knockback_vector.length() < 10:
					knockback_vector = Vector2.ZERO
					has_committed_to_attack = false
					if target and attack_area.overlaps_body(target):
						_set_enemy_state(EnemyState.ATTACKING)
						current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
						has_committed_to_attack = true
					elif target and chase_area.overlaps_body(target):
						_set_enemy_state(EnemyState.CHASING)
					else:
						_set_enemy_state(EnemyState.IDLE)
			else:
				has_committed_to_attack = false
				if target and attack_area.overlaps_body(target):
					_set_enemy_state(EnemyState.ATTACKING)
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					has_committed_to_attack = true
				elif target and chase_area.overlaps_body(target):
					_set_enemy_state(EnemyState.CHASING)
				else:
					_set_enemy_state(EnemyState.IDLE)
	move_and_slide()

func _set_enemy_state(new_state: EnemyState) -> void:
	if current_enemy_state == new_state:
		return
	
	current_enemy_state = new_state
	_update_enemy_animation()
	print("New state: ", new_state)

func _update_enemy_animation() -> void:
	if not animation_enemy:
		return
	
	var dir_to_target = Vector2.ZERO
	if target:
		dir_to_target = (target.global_position - global_position)
		if dir_to_target.x > 0:
			enemy_sprite.flip_h = true
		elif dir_to_target.x < 0:
			enemy_sprite.flip_h = false
		
		if dir_to_target.y < 0:
			animation_dir = 1
		else:
			animation_dir = 0
	
	match current_enemy_state:
		EnemyState.IDLE:
			if animation_dir == 1:
				if animation_enemy.current_animation != "IDLE_BACK":
					animation_enemy.play("IDLE_BACK")
			else:
				if animation_enemy.current_animation != "IDLE":
					animation_enemy.play("IDLE")
		EnemyState.CHASING:
			if animation_dir == 1:
				if animation_enemy.current_animation != "RUN_BACK":
					animation_enemy.play("RUN_BACK")
			else:
				if animation_enemy.current_animation != "RUN":
					animation_enemy.play("RUN")
		EnemyState.ATTACKING:
			if animation_enemy.current_animation != "attack":
				animation_enemy.play("attack")
		EnemyState.KNOCKBACK:
			if animation_enemy.current_animation != "IDLE":
				animation_enemy.play("IDLE")
		EnemyState.DASHING_ATTACK:
			if animation_enemy.current_animation != "run":
				animation_enemy.play("run")
		EnemyState.POST_ATTACK_COOLDOWN:
			if animation_dir == 1:
				if animation_enemy.current_animation != "IDLE_BACK":
					animation_enemy.play("IDLE_BACK")
			else:
				if animation_enemy.current_animation != "IDLE":
					animation_enemy.play("IDLE")
	
func handle_chasing_state(delta: float) -> void:
	if not target or not chase_area.overlaps_body(target):
		_set_enemy_state(EnemyState.IDLE)
		velocity = Vector2.ZERO
		is_dashing_move = false
		print("Player saiu da área de perseguição. Inimigo em IDLE.")
		return
	
	if target and attack_area.overlaps_body(target) and not has_committed_to_attack:
		_set_enemy_state(EnemyState.ATTACKING)
		current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
		has_committed_to_attack = true
		is_dashing_move = false
		print("Player dentro da área de ataque. Inimigo em ATTACKING.")
		return
	
	# Restante da lógica de perseguição...
	if is_dashing_move:
		current_dash_time -= delta
		if current_dash_time > 0:
			velocity = dash_move_direction * dash_move_speed
		else:
			is_dashing_move = false
			velocity = Vector2.ZERO
			current_dash_move_cooldown = dash_move_cooldown
			print("Dash de movimentação terminou. Iniciando cooldown.")
	else:
		if current_dash_move_cooldown > 0:
			current_dash_move_cooldown -= delta
			velocity = Vector2.ZERO
		else:
			if target:
				navigation.target_position = target.global_position
				var next_path_position = navigation.get_next_path_position()
				dash_move_direction = global_position.direction_to(next_path_position)
				
				is_dashing_move = true
				current_dash_time = dash_move_duration
				print("Iniciando novo dash de movimentação.")
			else:
				velocity = Vector2.ZERO

func seeker_setup() -> void:
	if not navigation:
		push_error("NavigationAgent2D node is not assigned or is null.")
		return
	if not get_tree().get_first_node_in_group("navigation_mesh"):
		print("No NavigationRegion2D found in group 'navigation_mesh'. Navigation might not work as expected.")

func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	if current_enemy_state == EnemyState.CHASING and not is_dashing_move:
		velocity = safe_velocity
	elif current_enemy_state == EnemyState.DASHING_ATTACK:
		pass
	elif current_enemy_state == EnemyState.KNOCKBACK:
		pass
	elif current_enemy_state == EnemyState.ATTACKING or current_enemy_state == EnemyState.POST_ATTACK_COOLDOWN:
		velocity = Vector2.ZERO

func _on_chase_area_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		target = body
		print("Player entered chase area. Target set.")

func _on_chase_area_exited(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		if not has_committed_to_attack:
			target = null
			print("Player exited chase area. Target nullified.")

func _on_attack_area_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		if current_enemy_state == EnemyState.CHASING and not has_committed_to_attack:
			_set_enemy_state(EnemyState.ATTACKING)
			current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
			has_committed_to_attack = true
			print("Player entered attack area. Transitioning to ATTACKING.")

func _on_attack_area_exited(body: Node2D) -> void:
	# Ignore esta função para o comportamento desejado.
	# A lógica de transição para CHASING/IDLE após o ataque agora é tratada nos estados.
	pass

func perform_attack() -> void:
	if target:
		player_dir = (target.global_position - global_position).normalized()
		var attack_type = randi_range(1, 2)
		if attack_type == 1:
			emit_signal("attack1", player_dir)
			print("Performing attack 1.")
		else:
			emit_signal("attack2", player_dir)
			print("Performing attack 2.")

		_set_enemy_state(EnemyState.POST_ATTACK_COOLDOWN)
		current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
		print("Attack performed. Entering POST_ATTACK_COOLDOWN.")
	else:
		if chase_area.overlaps_body(target):
			_set_enemy_state(EnemyState.CHASING)
			has_committed_to_attack = false
			print("No target in range for attack. Back to CHASING.")
		else:
			_set_enemy_state(EnemyState.IDLE)
			has_committed_to_attack = false
			print("No target in range for attack. Back to IDLE.")

func apply_knockback(force: float, hit_position: Vector2) -> void:
	_set_enemy_state(EnemyState.KNOCKBACK)
	var knockback_direction = (global_position - hit_position).normalized()
	var final_knockback_force = force / knockback_resistance
	knockback_vector = knockback_direction * final_knockback_force
	has_committed_to_attack = false
	_knockback_effect()

func _on_died() -> void:
	print("Enemy died.")
	queue_free()

func take_damage(amount: int) -> void:
	health.take_damage(amount)

func update_vision() -> void:
	if not target:
		can_see_target = false
		return
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collide_with_areas = true
	query.collision_mask = collision_mask_obstacles
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		can_see_target = true
	else:
		if result.has("collider") and result.collider == target:
			can_see_target = true
		else:
			can_see_target = false

func _knockback_effect():
	hit_animation.play("hit")

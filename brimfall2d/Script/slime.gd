extends CharacterBody2D
## Código combinado e corrigido para debug

@onready var navigation = $Tools/Navigation as NavigationAgent2D
@onready var health = $Tools/Health
@onready var chase_area = $Areas/ChaseArea
@onready var attack_area = $Areas/AttackArea
@onready var enemy_sprite = $Body/EnemySprite
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
@export var collision_mask_player: int = 2
var can_see_target: bool = false
var can_start_chasing: bool = false

# === Variáveis para o Ataque ===
@export var attack_delay_min: float = 0.5
@export var attack_delay_max: float = 1.5
var current_attack_delay: float = 0.0
var can_attack: bool = true

# === Variáveis para Cooldown de Ataque ===
@export var post_attack_cooldown_min: float = 0.5
@export var post_attack_cooldown_max: float = 1.0
var current_post_attack_cooldown: float = 0.0

# === Variáveis para o Dash de Ataque ===
@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.2
var dash_direction: Vector2 = Vector2.ZERO
var current_dash_time: float = 0.0

func _ready() -> void:
	
	health.connect("died", Callable(self, "_on_died"))

	if not navigation is NavigationAgent2D:
		push_error("The 'navigation' node is not a NavigationAgent2D. Please ensure it is correctly set up.")
		return
	
	call_deferred("seeker_setup")
	chase_area.connect("body_entered", Callable(self, "_on_chase_area_entered"))
	chase_area.connect("body_exited", Callable(self, "_on_chase_area_exited"))
	attack_area.connect("body_entered", Callable(self, "_on_attack_area_entered"))
	attack_area.connect("body_exited", Callable(self, "_on_attack_area_exited"))
	
	navigation.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))
	
	await get_tree().physics_frame
	can_start_chasing = true
	print("--- INIMIGO PRONTO PARA AGIR ---")

func _physics_process(delta: float) -> void:
	update_vision()
	_update_enemy_animation()

	match current_enemy_state:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			if can_start_chasing and target and chase_area.overlaps_body(target) and can_see_target:
				_set_enemy_state(EnemyState.CHASING)

		EnemyState.CHASING:
			if target and not chase_area.overlaps_body(target):
				_set_enemy_state(EnemyState.IDLE)
				velocity = Vector2.ZERO
				
			if target and attack_area.overlaps_body(target) and can_attack:
				_set_enemy_state(EnemyState.ATTACKING)
				current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
				
			if target and current_enemy_state == EnemyState.CHASING:
				navigation.target_position = target.global_position
				var next_path_position = navigation.get_next_path_position()
				var desired_velocity = global_position.direction_to(next_path_position) * move_speed
				navigation.set_velocity(desired_velocity)
			else:
				velocity = Vector2.ZERO

		EnemyState.ATTACKING:
			velocity = Vector2.ZERO
			current_attack_delay -= delta
			if current_attack_delay <= 0:
				perform_attack()
			
			if not target:
				_set_enemy_state(EnemyState.IDLE)
				can_attack = true
		
		EnemyState.POST_ATTACK_COOLDOWN:
			velocity = Vector2.ZERO
			current_post_attack_cooldown -= delta
			if current_post_attack_cooldown <= 0:
				can_attack = true
				
				if target and attack_area.overlaps_body(target):
					_set_enemy_state(EnemyState.ATTACKING)
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false
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
				can_attack = false

		EnemyState.KNOCKBACK:
			if knockback_vector != Vector2.ZERO:
				velocity = knockback_vector
				knockback_vector = knockback_vector.move_toward(Vector2.ZERO, knockback_friction * delta)
				if knockback_vector.length() < 10:
					knockback_vector = Vector2.ZERO
					if target and attack_area.overlaps_body(target) and can_attack:
						_set_enemy_state(EnemyState.ATTACKING)
						current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
						can_attack = false
					elif target and chase_area.overlaps_body(target):
						_set_enemy_state(EnemyState.CHASING)
					else:
						_set_enemy_state(EnemyState.IDLE)
			else:
				if target and attack_area.overlaps_body(target) and can_attack:
					_set_enemy_state(EnemyState.ATTACKING)
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false
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

func _update_enemy_animation() -> void:
	if not animation_enemy:
		return
		
	if target:
		var dir_to_target = (target.global_position - global_position).normalized()
		if dir_to_target.x > 0:
			enemy_sprite.flip_h = true
		elif dir_to_target.x < 0:
			enemy_sprite.flip_h = false
		
		if animation_enemy.current_animation != "RUN" and current_enemy_state == EnemyState.CHASING:
			animation_enemy.play("RUN")
		elif animation_enemy.current_animation != "IDLE" and (current_enemy_state == EnemyState.IDLE or current_enemy_state == EnemyState.POST_ATTACK_COOLDOWN):
			animation_enemy.play("IDLE")
		elif animation_enemy.current_animation != "attack" and current_enemy_state == EnemyState.ATTACKING:
			animation_enemy.play("attack")
		elif animation_enemy.current_animation != "run" and current_enemy_state == EnemyState.DASHING_ATTACK:
			animation_enemy.play("run")


func update_vision() -> void:
	can_see_target = false

	if target == null:
		return

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = target.global_position
	query.exclude = [self]
	query.collision_mask = collision_mask_obstacles | collision_mask_player

	var result = space_state.intersect_ray(query)

	if result:
		if result.collider == target:
			can_see_target = true
			print("VISÃO: Alvo detectado sem obstáculos!")
		else:
			can_see_target = false
			print("VISÃO: Obstáculo no caminho. Collider: ", result.collider.name)
	else:
		can_see_target = false
		print("VISÃO: Nada no caminho ou alvo fora de alcance.")

func seeker_setup():
	await get_tree().physics_frame
	if target and navigation is NavigationAgent2D:
		navigation.target_position = target.global_position

func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	if current_enemy_state == EnemyState.CHASING:
		velocity = safe_velocity

func take_damage(amount: int) -> void:
	health.take_damage(amount)
	if hit_animation:
		hit_animation.play("hit")

func _on_died():
	print("Inimigo morreu!")
	queue_free()

func apply_knockback(force: float, hit_position: Vector2) -> void:
	_set_enemy_state(EnemyState.KNOCKBACK)
	var knockback_direction = (global_position - hit_position).normalized()
	var final_knockback_force = force / knockback_resistance
	knockback_vector = knockback_direction * final_knockback_force
	can_attack = true

func perform_attack() -> void:
	var attack_choice = randi_range(1, 2)
	if attack_choice == 1:
		attack_1()
	else:
		attack_2()
	
func attack_1():
	print("Ataque 1 lançado: DASH!")
	if target:
		_set_enemy_state(EnemyState.DASHING_ATTACK)
		dash_direction = (target.global_position - global_position).normalized()
		current_dash_time = dash_duration
	else:
		_set_enemy_state(EnemyState.POST_ATTACK_COOLDOWN)
		current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)

func attack_2():
	print("Ataque 2 lançado: Ataque normal.")
	_set_enemy_state(EnemyState.POST_ATTACK_COOLDOWN)
	current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)

func _on_chase_area_entered(body: CharacterBody2D) -> void:
	if body == target and can_see_target:
		_set_enemy_state(EnemyState.CHASING)

func _on_chase_area_exited(body: CharacterBody2D) -> void:
	if body == target and not (
		current_enemy_state == EnemyState.KNOCKBACK or
		current_enemy_state == EnemyState.POST_ATTACK_COOLDOWN or
		current_enemy_state == EnemyState.ATTACKING or
		current_enemy_state == EnemyState.DASHING_ATTACK
	):
		_set_enemy_state(EnemyState.IDLE)
		velocity = Vector2.ZERO
		can_attack = true

func _on_attack_area_entered(body: CharacterBody2D) -> void:
	if body == target and current_enemy_state == EnemyState.CHASING and can_attack:
		_set_enemy_state(EnemyState.ATTACKING)
		current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
		can_attack = false

func _on_attack_area_exited(body: CharacterBody2D) -> void:
	if body == target:
		if current_enemy_state == EnemyState.ATTACKING or current_enemy_state == EnemyState.POST_ATTACK_COOLDOWN:
			if target and chase_area.overlaps_body(target):
				_set_enemy_state(EnemyState.CHASING)
				can_attack = true
			else:
				_set_enemy_state(EnemyState.IDLE)
				can_attack = true

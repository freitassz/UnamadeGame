extends CharacterBody2D
##aaaaaaaaaaaaaaaaaaaaaa
signal attack1(player_dir: Vector2)
signal attack2(player_dir: Vector2)

@onready var navigation = $Navigation as NavigationAgent2D
@onready var health = $Body/Health
@onready var chase_area = $ChaseArea
@onready var attack_area = $AttackArea
@onready var enemy_sprite = $Body/EnemySprite

@onready var attack_component = $Body/EnemyWeapon

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
	CHASING, # Perseguindo o jogador (equivalente ao WALKING do jogador)
	ATTACKING,
	KNOCKBACK, # Sofrendo knockback (equivalente ao RECOILING do jogador)
	POST_ATTACK_COOLDOWN, # Novo estado para o cooldown pós-ataque
	DASHING_ATTACK # Novo estado para o ataque de dash
}
var current_enemy_state: EnemyState = EnemyState.IDLE

# === Variáveis para a Visão ===
@export var ray_cast_length: float = 500.0 # O comprimento máximo do raio
@export var collision_mask_obstacles: int = 1 # Máscara de colisão para obstáculos (ex: paredes)
var can_see_target: bool = false # Nova variável para controlar se o inimigo pode ver o alvo

# === Variáveis para o Ataque ===
@export var attack_delay_min: float = 0.5 # Tempo mínimo de espera antes de atacar (para o ataque em si)
@export var attack_delay_max: float = 1.5 # Tempo máximo de espera antes de atacar (para o ataque em si)
var current_attack_delay: float = 0.0 # O tempo de espera atual para o próximo ataque
var can_attack: bool = true # Controla se o inimigo pode atacar agora

# === Variáveis para Cooldown de Ataque ===
@export var post_attack_cooldown_min: float = 0.5 # Tempo mínimo de cooldown após um ataque
@export var post_attack_cooldown_max: float = 1.0 # Tempo máximo de cooldown após um ataque
var current_post_attack_cooldown: float = 0.0 # O tempo de cooldown atual

# === Variáveis para o Dash de Ataque ===
@export var dash_speed: float = 400.0 # Velocidade do dash
@export var dash_duration: float = 0.2 # Duração do dash em segundos
var dash_direction: Vector2 = Vector2.ZERO # Direção do dash
var current_dash_time: float = 0.0 # Tempo restante do dash

# === Variáveis para o Dash de Movimentação (dentro de CHASING) ===
@export var dash_move_speed: float = 300.0 # Velocidade do dash de movimentação
@export var dash_move_duration: float = 0.15 # Duração do dash de movimentação em segundos
@export var dash_move_cooldown: float = 0.5 # Cooldown entre dashes de movimentação
var current_dash_move_cooldown: float = 0.0
var is_dashing_move: bool = false
var dash_move_direction: Vector2 = Vector2.ZERO

#====reference====#
var player_dir = null

func _ready() -> void:

	health.connect("died", Callable(self, "_on_died"))

	if not navigation is NavigationAgent2D:
		push_error("The 'navigation' node is not a NavigationAgent2D. Please ensure it is correctly set up.")
		return

	# Ensure the attack_component is correctly assigned
	if not attack_component:
		push_error("The 'attack_component' node is not assigned. Please ensure it is correctly set up.")
		return

	call_deferred("seeker_setup")
	chase_area.connect("body_entered", Callable(self, "_on_chase_area_entered"))
	chase_area.connect("body_exited", Callable(self, "_on_chase_area_exited"))
	attack_area.connect("body_entered", Callable(self, "_on_attack_area_entered"))
	attack_area.connect("body_exited", Callable(self, "_on_attack_area_exited"))

	# Connect the velocity_computed signal
	# This line is crucial for avoidance.
	navigation.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))

func _physics_process(delta: float) -> void:
# Flip the sprite based on the target's position
	if target:
		# Calculate the direction vector from the enemy to the target
		var dir_to_target = (target.global_position - global_position).x
	
		# Flip the sprite based on the horizontal direction to the target
		if dir_to_target > 0: # Target is to the right
			enemy_sprite.flip_h = true
		elif dir_to_target < 0: # Target is to the left
			enemy_sprite.flip_h = false

	update_vision()

	match current_enemy_state:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			# Se o alvo estiver na área de perseguição E puder ser visto, começa a caçar
			# Não muda se já estiver em KNOCKBACK, POST_ATTACK_COOLDOWN ou DASHING_ATTACK
			if target and chase_area.overlaps_body(target) and can_see_target and \
			current_enemy_state != EnemyState.KNOCKBACK and \
			current_enemy_state != EnemyState.POST_ATTACK_COOLDOWN and \
			current_enemy_state != EnemyState.DASHING_ATTACK:
				current_enemy_state = EnemyState.CHASING
				print("Player visto e dentro da área. Inimigo em CHASING.")

		EnemyState.CHASING:
			handle_chasing_state(delta) # Call the new function for CHASING state logic

		EnemyState.ATTACKING:
			velocity = Vector2.ZERO # Inimigo para de se mover enquanto ataca
			current_attack_delay -= delta
			if current_attack_delay <= 0:
				perform_attack()

			if not target: # Se o alvo sumir completamente, volta para IDLE
				current_enemy_state = EnemyState.IDLE
				can_attack = true
				print("Alvo perdido durante o ataque. Inimigo volta para IDLE.")

		EnemyState.POST_ATTACK_COOLDOWN:
			velocity = Vector2.ZERO # Permanece parado durante o cooldown
			current_post_attack_cooldown -= delta
			if current_post_attack_cooldown <= 0:
				can_attack = true # Permite que o inimigo ataque novamente

				# Após o cooldown, reavalia a situação para decidir o próximo estado
				if target and attack_area.overlaps_body(target):
					# Se o player ainda estiver na área de ataque, volta a atacar
					current_enemy_state = EnemyState.ATTACKING
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false # Impede ataques imediatos novamente
					print("Cooldown terminado. Player ainda na área de ataque. Inimigo volta para ATTACKING.")
				elif target and chase_area.overlaps_body(target):
					# Se o player estiver na área de perseguição (mas não de ataque), volta a perseguir
					current_enemy_state = EnemyState.CHASING
					print("Cooldown terminado. Player fora da área de ataque, mas na de perseguição. Inimigo volta para CHASING.")
				else:
					# Se o player estiver fora de ambas as áreas ou for null, volta para IDLE
					current_enemy_state = EnemyState.IDLE
					print("Cooldown terminado. Inimigo volta para IDLE.")

		EnemyState.KNOCKBACK:
			if knockback_vector != Vector2.ZERO:
				velocity = knockback_vector
				move_and_slide()

				knockback_vector = knockback_vector.move_toward(Vector2.ZERO, knockback_friction * delta)
				if knockback_vector.length() < 10:
					knockback_vector = Vector2.ZERO
					# Após o knockback, decide para onde o inimigo deve ir
					# Agora o inimigo volta a caçar se o player ESTIVER na área DE PERSEGUIÇÃO.
					# A visão só é verificada para INICIAR a caçada, não para MANTÊ-LA.
					if target and attack_area.overlaps_body(target) and can_attack:
						current_enemy_state = EnemyState.ATTACKING
						current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
						can_attack = false # Impede ataques imediatos
						print("Knockback terminou. Player dentro da área de ataque. Inimigo em ATTACKING.")
					elif target and chase_area.overlaps_body(target):
						current_enemy_state = EnemyState.CHASING
						print("Knockback terminou. Player na área de perseguição. Inimigo em CHASING.")
					else:
						current_enemy_state = EnemyState.IDLE
						print("Knockback terminou. Inimigo em IDLE.")
			else:
				# Se o knockback_vector já for ZERO e ainda estamos no estado KNOCKBACK
				if target and attack_area.overlaps_body(target) and can_attack:
					current_enemy_state = EnemyState.ATTACKING
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false # Impede ataques imediatos
					print("Knockback já zero. Player dentro da área de ataque. Inimigo em ATTACKING.")
				elif target and chase_area.overlaps_body(target):
					current_enemy_state = EnemyState.CHASING
					print("Knockback já zero. Player na área de perseguição. Inimigo em CHASING.")
				else:
					current_enemy_state = EnemyState.IDLE
					print("Knockback já zero. Inimigo em IDLE.")
		EnemyState.DASHING_ATTACK:
			# Lógica do dash de ataque
			current_dash_time -= delta
			if current_dash_time > 0:
				velocity = dash_direction * dash_speed
			else:
				# Após o dash, decide o próximo estado.
				# Priorize o ataque se o player estiver na área de ataque e puder atacar.
				if target and attack_area.overlaps_body(target) and can_attack:
					current_enemy_state = EnemyState.ATTACKING
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false
					print("Dash de ataque terminado. Player na área de ataque. Inimigo em ATTACKING.")
				elif target and chase_area.overlaps_body(target):
					current_enemy_state = EnemyState.CHASING
					print("Dash de ataque terminado. Player na área de perseguição. Inimigo em CHASING.")
				else:
					current_enemy_state = EnemyState.IDLE
					print("Dash de ataque terminado. Inimigo em IDLE.")
	move_and_slide() # Always call move_and_slide at the end of _physics_process

func handle_chasing_state(delta: float) -> void:
	# No estado CHASING, o inimigo só para de caçar se o player sair da área de perseguição.
	# Ele continua perseguindo mesmo que perca a linha de visão, desde que o player esteja na área.
	if target and not chase_area.overlaps_body(target):
		current_enemy_state = EnemyState.IDLE
		velocity = Vector2.ZERO
		is_dashing_move = false # Reset dash state
		print("Player saiu da área de perseguição. Inimigo em IDLE.")
		return # Sai para não tentar navegar

	# Se o player estiver na área de ataque E puder atacar, transiciona para o estado ATTACKING
	if target and attack_area.overlaps_body(target) and can_attack:
		current_enemy_state = EnemyState.ATTACKING
		current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
		is_dashing_move = false # Reset dash state
		# can_attack = false é definido em _on_attack_area_entered agora para garantir o comprometimento
		print("Player dentro da área de ataque. Inimigo em ATTACKING.")
		return

	# Lógica do Dash de Movimentação
	if is_dashing_move:
		current_dash_time -= delta
		if current_dash_time > 0:
			velocity = dash_move_direction * dash_move_speed
		else:
			is_dashing_move = false
			velocity = Vector2.ZERO # Parar após o dash
			current_dash_move_cooldown = dash_move_cooldown # Iniciar cooldown
			print("Dash de movimentação terminou. Iniciando cooldown.")
	else:
		# Lógica do cooldown do dash
		if current_dash_move_cooldown > 0:
			current_dash_move_cooldown -= delta
			velocity = Vector2.ZERO # Inimigo parado durante o cooldown do dash
		else:
			# Se o cooldown terminou, o inimigo está pronto para o próximo dash
			if target:
				# Calcula a direção do dash
				navigation.target_position = target.global_position
				var next_path_position = navigation.get_next_path_position()
				dash_move_direction = global_position.direction_to(next_path_position)

				# Inicia o dash
				is_dashing_move = true
				current_dash_time = dash_move_duration
				print("Iniciando novo dash de movimentação.")
			else:
				velocity = Vector2.ZERO # Se não houver alvo, para.

func seeker_setup() -> void:
	# Check if the navigation node is valid before proceeding
	if not navigation:
		push_error("NavigationAgent2D node is not assigned or is null.")
		return

	# Ensure the navigation agent is linked to a NavigationServer2D
	# This is often set up in the scene, but good to double-check if issues arise.
	if not get_tree().get_first_node_in_group("navigation_mesh"):
		print("No NavigationRegion2D found in group 'navigation_mesh'. Navigation might not work as expected.")

func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	# Only apply computed velocity if not dashing or in knockback/attacking
	if current_enemy_state == EnemyState.CHASING and not is_dashing_move:
		velocity = safe_velocity
	elif current_enemy_state == EnemyState.DASHING_ATTACK:
		# During a dashing attack, we override the navigation velocity
		pass # Velocity is already set by the dashing attack logic
	elif current_enemy_state == EnemyState.KNOCKBACK:
		pass # Velocity is handled by knockback logic
	elif current_enemy_state == EnemyState.ATTACKING or current_enemy_state == EnemyState.POST_ATTACK_COOLDOWN:
		velocity = Vector2.ZERO # Stay still during attack or cooldown

	# Ensure movement is applied here after velocity is determined
	# (Note: move_and_slide is now called once at the end of _physics_process)

func _on_chase_area_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		target = body
		# The state change to CHASING is now handled in _physics_process based on `can_see_target`
		print("Player entered chase area. Target set.")

func _on_chase_area_exited(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		target = null
		# The state will transition to IDLE in _physics_process if target is null or outside areas
		print("Player exited chase area. Target nullified.")

func _on_attack_area_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		if current_enemy_state == EnemyState.CHASING and can_attack:
			current_enemy_state = EnemyState.ATTACKING
			current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
			can_attack = false # Commit to attacking
			print("Player entered attack area. Transitioning to ATTACKING.")

func _on_attack_area_exited(body: Node2D) -> void:
	if body is CharacterBody2D and body.name == "Player":
		# If the player exits the attack area during ATTACKING,
		# the enemy should transition to CHASING (if still in chase area) or IDLE.
		if current_enemy_state == EnemyState.ATTACKING or current_enemy_state == EnemyState.POST_ATTACK_COOLDOWN:
			if target and chase_area.overlaps_body(target):
				current_enemy_state = EnemyState.CHASING
				can_attack = true # Allow re-evaluation for attack later
				print("Player exited attack area during attack/cooldown. Transitioning to CHASING.")
			else:
				current_enemy_state = EnemyState.IDLE
				can_attack = true # Allow re-evaluation for attack later
				print("Player exited attack area. No longer in chase area. Transitioning to IDLE.")

func perform_attack() -> void:
	if target and attack_area.overlaps_body(target):
		player_dir = (target.global_position - global_position).normalized()
		var attack_type = randi_range(1, 2) # Decide between attack1 and attack2
		if attack_type == 1:
			emit_signal("attack1", player_dir)
			print("Performing attack 1.")
		else:
			emit_signal("attack2", player_dir)
			print("Performing attack 2.")

		# After performing an attack, go into POST_ATTACK_COOLDOWN
		current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
		current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
		print("Attack performed. Entering POST_ATTACK_COOLDOWN.")
	else:
		# If somehow perform_attack is called but target is not in range,
		# transition back to chasing or idle.
		if target and chase_area.overlaps_body(target):
			current_enemy_state = EnemyState.CHASING
			can_attack = true # Allow new attack attempt
			print("No target in range for attack. Back to CHASING.")
		else:
			current_enemy_state = EnemyState.IDLE
			can_attack = true
			print("No target in range for attack. Back to IDLE.")

func apply_knockback(force: float, hit_position: Vector2) -> void:
	current_enemy_state = EnemyState.KNOCKBACK
	var knockback_direction = (global_position - hit_position).normalized()
	var final_knockback_force = force / knockback_resistance
	knockback_vector = knockback_direction * final_knockback_force
	can_attack = true # Reseta a capacidade de ataque após o knockback
	_knockback_effect()

func _on_died() -> void:
	print("Enemy died.")
	queue_free()

func update_vision() -> void:
	if not target:
		can_see_target = false
		return

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collide_with_areas = true # Ray can collide with areas
	query.collision_mask = collision_mask_obstacles # Only collide with obstacles

	var result = space_state.intersect_ray(query)

	if result.is_empty():
		can_see_target = true
	else:
		# Check if the object hit by the ray is the target itself
		# If the ray hits something else before the target, then vision is blocked
		if result.has("collider") and result.collider == target:
			can_see_target = true
		else:
			can_see_target = false

func _knockback_effect():
	$HitFlashAnimation.play("hit")
	

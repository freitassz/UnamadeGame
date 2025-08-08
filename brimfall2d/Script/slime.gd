extends CharacterBody2D

@onready var navigation = $Tools/Navigation as NavigationAgent2D # Cast to NavigationAgent2D for clarity
@onready var health = $Tools/Health
@onready var chase_area = $Areas/ChaseArea
@onready var attack_area = $Areas/AttackArea # Assuming you have an AttackArea2D node

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
	
	# Connect the velocity_computed signal
	# This line is crucial for avoidance.
	navigation.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))

func _physics_process(delta: float) -> void:
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
			# No estado CHASING, o inimigo só para de caçar se o player sair da área de perseguição.
			# Ele continua perseguindo mesmo que perca a linha de visão, desde que o player esteja na área.
			if target and not chase_area.overlaps_body(target):
				current_enemy_state = EnemyState.IDLE
				velocity = Vector2.ZERO
				print("Player saiu da área de perseguição. Inimigo em IDLE.")
				return # Sai para não tentar navegar
			
			# Se o player estiver na área de ataque E puder atacar, transiciona para o estado ATTACKING
			if target and attack_area.overlaps_body(target) and can_attack:
				current_enemy_state = EnemyState.ATTACKING
				current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
				# can_attack = false é definido em _on_attack_area_entered agora para garantir o comprometimento
				print("Player dentro da área de ataque. Inimigo em ATTACKING.")
				return

			# Se o player ainda estiver na área, ele continua navegando até a posição do player.
			if target:
				# Set the target position for the navigation agent
				navigation.target_position = target.global_position
				
				# Get the desired velocity *towards* the next path_position
				# This is the velocity the agent *wants* to move at, before avoidance
				var next_path_position = navigation.get_next_path_position()
				var desired_velocity = global_position.direction_to(next_path_position) * move_speed
				
				# Tell the navigation agent to compute the avoidance velocity
				# The actual movement will happen in _on_navigation_velocity_computed
				navigation.set_velocity(desired_velocity)

		EnemyState.ATTACKING:
			velocity = Vector2.ZERO # Inimigo para de se mover enquanto ataca
			current_attack_delay -= delta
			if current_attack_delay <= 0:
				perform_attack()
				# A transição para POST_ATTACK_COOLDOWN ou DASHING_ATTACK
				# é feita DENTRO de perform_attack().
			
			# Removido: transição para CHASING se o player sair da área de ataque AQUI.
			# Agora ele se compromete com o ataque.
			
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

		EnemyState.DASHING_ATTACK:
			if current_dash_time > 0:
				velocity = dash_direction * dash_speed
				move_and_slide()
				current_dash_time -= delta
			else:
				# Dash terminou, volta para o cooldown pós-ataque
				current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
				current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
				print("Dash attack terminou. Inimigo em POST_ATTACK_COOLDOWN.")
				can_attack = false # Impede que outro ataque seja disparado imediatamente

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


func update_vision() -> void:
	can_see_target = false # Assume que não pode ver, a menos que provado o contrário

	if target == null:
		return

	# Configura os parâmetros do raio
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = target.global_position # Raio vai do inimigo ao jogador
	query.exclude = [self] # Exclui o próprio inimigo da colisão do raio
	query.collision_mask = collision_mask_obstacles # Define quais camadas o raio vai colidir

	var result = space_state.intersect_ray(query)

	if result:
		# Se o raio colidiu com algo
		if result.collider == target:
			# Se o que o raio colidiu for o próprio alvo, então ele pode ser visto
			can_see_target = true
		else:
			# Se colidiu com outra coisa (um obstáculo), ele não pode ver o alvo
			can_see_target = false
	else:
		# Se o raio não colidiu com nada, significa que não há obstáculos entre o inimigo e o alvo
		can_see_target = true

func seeker_setup():
	await get_tree().physics_frame
	if target and navigation is NavigationAgent2D: # Add check for navigation type
		navigation.target_position = target.global_position

func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	# Only apply the computed velocity if the enemy is in the CHASING state
	if current_enemy_state == EnemyState.CHASING:
		velocity = safe_velocity
		move_and_slide()

func take_damage(amount: int) -> void:
	health.take_damage(amount)

func _on_died():
	print("Inimigo morreu!")
	queue_free()

func apply_knockback(force: float, hit_position: Vector2) -> void:
	current_enemy_state = EnemyState.KNOCKBACK
	var knockback_direction = (global_position - hit_position).normalized()
	var final_knockback_force = force / knockback_resistance
	knockback_vector = knockback_direction * final_knockback_force
	can_attack = true # Reseta a capacidade de ataque após o knockback

## --- Funções de Ataque Simplificadas ---
func perform_attack() -> void:
	# Escolhe aleatoriamente entre attack_1 e attack_2
	var attack_choice = randi_range(1, 2)
	if attack_choice == 1:
		attack_1()
	else:
		attack_2()
	# A transição de estado é feita DENTRO de attack_1/attack_2 se eles forem um ataque com duração (como o dash)
	# ou após a chamada se for um ataque instantâneo (como attack_2 continua sendo).

func attack_1():
	print("Ataque 1 lançado: DASH!")
	if target:
		current_enemy_state = EnemyState.DASHING_ATTACK # Entra no novo estado de dash
		dash_direction = (target.global_position - global_position).normalized()
		current_dash_time = dash_duration
		# O dano pode ser aplicado aqui ou em _physics_process no estado DASHING_ATTACK
		# quando o inimigo colidir com o player.
		# Exemplo: attack_component.deal_damage(target, 20) # Dano imediato ao iniciar o dash
	else:
		# Se não houver alvo para o dash, volta para o cooldown pós-ataque
		current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
		current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
		print("Não há alvo para o dash. Inimigo em POST_ATTACK_COOLDOWN.")

func attack_2():
	print("Ataque 2 lançado: Ataque normal.")
	# Adicione sua lógica de ataque 2 aqui (animação, dano, etc.)
	# Ex: attack_component.deal_damage(target, 15)
	
	# Após um ataque que não é um dash, transiciona para o cooldown pós-ataque
	current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
	current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
	print("Ataque 2 realizado. Inimigo em POST_ATTACK_COOLDOWN.")

## --- Funções de Sinal ---
func _on_chase_area_entered(body: CharacterBody2D) -> void:
	# Esta função permanece, mas a lógica de ativação para CHASING
	# agora depende da visão (em _physics_process no estado IDLE).
	pass

func _on_chase_area_exited(body: CharacterBody2D) -> void:
	# O inimigo só volta para IDLE se não estiver em um estado de ataque ou knockback.
	# A saída da área de perseguição não deve cancelar um ataque em andamento.
	if body == target and \
	current_enemy_state != EnemyState.KNOCKBACK and \
	current_enemy_state != EnemyState.POST_ATTACK_COOLDOWN and \
	current_enemy_state != EnemyState.ATTACKING and \
	current_enemy_state != EnemyState.DASHING_ATTACK:
		current_enemy_state = EnemyState.IDLE
		velocity = Vector2.ZERO # Garante que o inimigo pare de se mover
		print("Player saiu da área de perseguição. Inimigo em IDLE.")
		can_attack = true # Reseta a capacidade de ataque

func _on_attack_area_entered(body: CharacterBody2D) -> void:
	if body == target and current_enemy_state == EnemyState.CHASING and can_attack:
		current_enemy_state = EnemyState.ATTACKING
		current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
		can_attack = false # Define como false AQUI para comprometer o ataque
		print("Player entrou na área de ataque. Inimigo se compromete com ATTACKING.")
	

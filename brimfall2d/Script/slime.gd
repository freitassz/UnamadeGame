extends CharacterBody2D

@onready var navigation = $Navigation as NavigationAgent2D # Cast to NavigationAgent2D for clarity
@onready var health = $Health
@onready var chase_area = $ChaseArea
@onready var attack_area = $AttackArea # Assuming you have an AttackArea2D node

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
	KNOCKBACK # Sofrendo knockback (equivalente ao RECOILING do jogador)
}
var current_enemy_state: EnemyState = EnemyState.IDLE

# === Variáveis para a Visão ===
@export var ray_cast_length: float = 500.0 # O comprimento máximo do raio
@export var collision_mask_obstacles: int = 1 # Máscara de colisão para obstáculos (ex: paredes)
var can_see_target: bool = false # Nova variável para controlar se o inimigo pode ver o alvo

# === Variáveis para o Ataque ===
@export var attack_delay_min: float = 0.5 # Tempo mínimo de espera antes de atacar
@export var attack_delay_max: float = 1.5 # Tempo máximo de espera antes de atacar
@export var attacks: Array[Callable] # Array de Callables representando diferentes funções de ataque
var current_attack_delay: float = 0.0 # O tempo de espera atual para o próximo ataque
var can_attack: bool = true # Controla se o inimigo pode atacar agora

func _ready() -> void:
	# Ensure navigation is a NavigationAgent2D node
	if not navigation is NavigationAgent2D:
		push_error("The 'navigation' node is not a NavigationAgent2D. Please ensure it is correctly set up.")
		return
		
	call_deferred("seeker_setup")
	health.connect("died", Callable(self, "_on_died"))
	chase_area.connect("body_entered", Callable(self, "_on_chase_area_entered"))
	chase_area.connect("body_exited", Callable(self, "_on_chase_area_exited"))
	attack_area.connect("body_entered", Callable(self, "_on_attack_area_entered"))
	attack_area.connect("body_exited", Callable(self, "_on_attack_area_exited"))
	
	# Connect the velocity_computed signal
	# This line is crucial for avoidance.
	navigation.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))

func _physics_process(delta: float) -> void:
	# Atualiza a visibilidade em cada frame de física
	update_vision()

	match current_enemy_state:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			# Se o alvo estiver na área de perseguição E puder ser visto, começa a caçar
			# Não muda se já estiver em KNOCKBACK
			if target and chase_area.overlaps_body(target) and can_see_target and current_enemy_state != EnemyState.KNOCKBACK:
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
			
			# Se o player estiver na área de ataque, transiciona para o estado ATTACKING
			if target and attack_area.overlaps_body(target) and can_attack:
				current_enemy_state = EnemyState.ATTACKING
				current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
				can_attack = false # Impede ataques imediatos
				print("Player dentro da área de ataque. Inimigo em ATTACKING.")
				return

			# Se o player ainda estiver na área, ele continua navegando até a posição do player.
			if target:
				# Set the target position for the navigation agent
				navigation.target_position = target.global_position
				
				# Get the desired velocity *towards* the next path position
				# This is the velocity the agent *wants* to move at, before avoidance
				var next_path_position = navigation.get_next_path_position()
				var desired_velocity = global_position.direction_to(next_path_position) * move_speed
				
				# Tell the navigation agent to compute the avoidance velocity
				# The actual movement will happen in _on_navigation_velocity_computed
				navigation.set_velocity(desired_velocity)

			# No need to call move_and_slide() here directly for CHASING
			# as it will be handled in _on_navigation_velocity_computed
		
		EnemyState.ATTACKING:
			velocity = Vector2.ZERO # Inimigo para de se mover enquanto ataca
			current_attack_delay -= delta
			if current_attack_delay <= 0:
				perform_attack()
				current_attack_delay = randf_range(attack_delay_min, attack_delay_max) # Reseta o timer para o próximo ataque
			
			# Se o alvo sair da área de ataque, volta a perseguir
			if target and not attack_area.overlaps_body(target):
				current_enemy_state = EnemyState.CHASING
				can_attack = true # Permite atacar novamente quando entrar na área
				print("Player saiu da área de ataque. Inimigo volta para CHASING.")
			elif not target: # Se o alvo sumir, volta para IDLE
				current_enemy_state = EnemyState.IDLE
				can_attack = true
				print("Alvo perdido. Inimigo volta para IDLE.")


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
					if target and chase_area.overlaps_body(target):
						current_enemy_state = EnemyState.CHASING
					else:
						current_enemy_state = EnemyState.IDLE
			else:
				# Se o knockback_vector já for ZERO e ainda estamos no estado KNOCKBACK
				if target and chase_area.overlaps_body(target):
					current_enemy_state = EnemyState.CHASING
				else:
					current_enemy_state = EnemyState.IDLE

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
	# Se o inimigo estiver atacando, ele é interrompido pelo knockback
	current_enemy_state = EnemyState.KNOCKBACK
	var knockback_direction = (global_position - hit_position).normalized()
	var final_knockback_force = force / knockback_resistance
	knockback_vector = knockback_direction * final_knockback_force
	can_attack = true # Reseta a capacidade de ataque após o knockback

## --- Funções de Ataque ---
func perform_attack() -> void:
	if attacks.is_empty():
		print("Nenhum ataque configurado para o inimigo!")
		return

	var chosen_attack: Callable
	if attacks.size() == 1:
		chosen_attack = attacks[0]
	else:
		chosen_attack = attacks[randi() % attacks.size()]
	
	if chosen_attack.is_valid():
		chosen_attack.call()
		print("Inimigo realizou um ataque.")
	else:
		push_error("Ataque inválido na lista 'attacks'.")

# --- Exemplos de Funções de Ataque (para adicionar ao array 'attacks') ---
func attack_melee() -> void:
	print("Realizando ataque corpo a corpo!")
	# Adicione sua lógica de ataque corpo a corpo aqui, por exemplo:
	# - Ativar uma hitbox de ataque
	# - Aplicar dano ao jogador se estiver na área de ataque
	# - Tocar uma animação de ataque

func attack_ranged() -> void:
	print("Realizando ataque à distância!")
	# Adicione sua lógica de ataque à distância aqui, por exemplo:
	# - Instanciar um projétil
	# - Definir a direção do projétil em relação ao jogador
	# - Tocar uma animação de ataque

func attack_special() -> void:
	print("Realizando ataque especial!")
	# Adicione sua lógica de ataque especial aqui
	# Pode ter um cooldown próprio ou efeitos únicos

## --- Funções de Sinal ---
func _on_chase_area_entered(body: CharacterBody2D) -> void:
	# Esta função permanece, mas a lógica de ativação para CHASING
	# agora depende da visão (em _physics_process no estado IDLE).
	pass

func _on_chase_area_exited(body: CharacterBody2D) -> void:
	if body == target and current_enemy_state != EnemyState.KNOCKBACK:
		current_enemy_state = EnemyState.IDLE
		velocity = Vector2.ZERO # Garante que o inimigo pare de se mover
		print("Player saiu da área de perseguição. Inimigo em IDLE.")
		can_attack = true # Reseta a capacidade de ataque se sair da área de perseguição

func _on_attack_area_entered(body: CharacterBody2D) -> void:
	if body == target and current_enemy_state == EnemyState.CHASING and can_attack:
		current_enemy_state = EnemyState.ATTACKING
		current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
		can_attack = false # Impede ataques imediatos
		print("Player entrou na área de ataque. Inimigo em ATTACKING.")

func _on_attack_area_exited(body: CharacterBody2D) -> void:
	if body == target and current_enemy_state == EnemyState.ATTACKING:
		current_enemy_state = EnemyState.CHASING
		can_attack = true # Permite atacar novamente se o jogador reentrar
		print("Player saiu da área de ataque. Inimigo volta para CHASING.")

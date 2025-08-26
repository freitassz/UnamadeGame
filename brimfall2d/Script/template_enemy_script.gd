extends CharacterBody2D

#==========Onready==========#
@onready var navigation = $Tools/Navigation as NavigationAgent2D 
@onready var health = $Tools/Health
@onready var chase_area = $Areas/ChaseArea
@onready var attack_area = $Areas/AttackArea 
@onready var attack_component = $AttackComponent
@onready var movement_component = $Tools/Movement as Node
@onready var hit_animation = $Animations/HitFlashAnimation

#==========Export==========#
@export var move_speed: float = 50
@export var target: CharacterBody2D = null
@export var knockback_resistance := 1.0
@export var knockback_friction := 100.0
@export var collision_mask_obstacles: int = 1 # Máscara de colisão para obstáculos (ex: paredes)
@export var attack_delay_min: float = 0.5 # Tempo mínimo de espera antes de atacar (para o ataque em si)
@export var attack_delay_max: float = 1.5 # Tempo máximo de espera antes de atacar (para o ataque em si)
@export var post_attack_cooldown_min: float = 0.5 # Tempo mínimo de cooldown após um ataque
@export var post_attack_cooldown_max: float = 1.0 # Tempo máximo de cooldown após um ataque
@export var dash_speed: float = 400.0 # Velocidade do dash
@export var dash_duration: float = 0.2 # Duração do dash em segundos

#==========States==========#
enum EnemyState {
	IDLE,
	CHASING, # Perseguindo o jogador (equivalente ao WALKING do jogador)
	ATTACKING,
	KNOCKBACK, # Sofrendo knockback (equivalente ao RECOILING do jogador)
	POST_ATTACK_COOLDOWN, # Novo estado para o cooldown pós-ataque
	DASHING_ATTACK # Novo estado para o ataque de dash
}
var current_enemy_state: EnemyState = EnemyState.IDLE

#==========Variables==========#
var can_see_target: bool = false # Nova variável para controlar se o inimigo pode ver o alvo
var current_attack_delay: float = 0.0 # O tempo de espera atual para o próximo ataque
var can_attack: bool = true # Controla se o inimigo pode atacar agora
var current_post_attack_cooldown: float = 0.0 # O tempo de cooldown atual
var dash_direction: Vector2 = Vector2.ZERO # Direção do dash
var current_dash_time: float = 0.0 # Tempo restante do dash
var knockback_vector := Vector2.ZERO
var ray_cast_length: float = 500.0 

#==========Base_Functions==========#
func _ready() -> void:
	health.connect("died", Callable(self, "_on_died"))

	if not movement_component:
		push_error("The 'movement_component' node is not assigned. Please ensure it is correctly set up.")
		return
		
	call_deferred("seeker_setup")
	chase_area.connect("body_entered", Callable(self, "_on_chase_area_entered"))
	chase_area.connect("body_exited", Callable(self, "_on_chase_area_exited"))
	attack_area.connect("body_entered", Callable(self, "_on_attack_area_entered"))
	attack_area.connect("body_exited", Callable(self, "_on_attack_area_exited"))
	
	# Agora o NavigationAgent2D e o target são configurados no componente de movimento
	movement_component.navigation_agent = navigation
	movement_component.parent_character = self
	movement_component.target = target

func _physics_process(delta: float) -> void:
	update_vision()

	match current_enemy_state:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			movement_component.is_chasing = false # Informa ao componente para não perseguir
			if target and chase_area.overlaps_body(target) and can_see_target:
				current_enemy_state = EnemyState.CHASING
		
		EnemyState.CHASING:
			if target and not chase_area.overlaps_body(target):
				current_enemy_state = EnemyState.IDLE
				velocity = Vector2.ZERO
				movement_component.is_chasing = false
				return
			
			if target and attack_area.overlaps_body(target) and can_attack:
				current_enemy_state = EnemyState.ATTACKING
				current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
				can_attack = false
				movement_component.is_chasing = false # Para de perseguir para atacar
				return
			
			# Chama o componente para atualizar a velocidade
			movement_component.is_chasing = true
			movement_component.update_movement(delta)
			
			# Aplica a velocidade calculada pelo componente
			velocity = movement_component.velocity_to_apply
			move_and_slide()
		
		EnemyState.ATTACKING:
			velocity = Vector2.ZERO
			current_attack_delay -= delta
			if current_attack_delay <= 0:
				perform_attack()
			
			if not target:
				current_enemy_state = EnemyState.IDLE
				can_attack = true
		
		EnemyState.POST_ATTACK_COOLDOWN:
			velocity = Vector2.ZERO
			current_post_attack_cooldown -= delta
			if current_post_attack_cooldown <= 0:
				can_attack = true
				if target and attack_area.overlaps_body(target):
					current_enemy_state = EnemyState.ATTACKING
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false
				elif target and chase_area.overlaps_body(target):
					current_enemy_state = EnemyState.CHASING
				else:
					current_enemy_state = EnemyState.IDLE
		
		EnemyState.DASHING_ATTACK:
			if current_dash_time > 0:
				velocity = dash_direction * dash_speed
				move_and_slide()
				current_dash_time -= delta
			else:
				current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
				current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
				can_attack = false

		EnemyState.KNOCKBACK:
			if knockback_vector != Vector2.ZERO:
				velocity = knockback_vector
				move_and_slide()

				knockback_vector = knockback_vector.move_toward(Vector2.ZERO, knockback_friction * delta)
				if knockback_vector.length() < 10:
					knockback_vector = Vector2.ZERO
					if target and attack_area.overlaps_body(target) and can_attack:
						current_enemy_state = EnemyState.ATTACKING
						current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
						can_attack = false
					elif target and chase_area.overlaps_body(target):
						current_enemy_state = EnemyState.CHASING
					else:
						current_enemy_state = EnemyState.IDLE
			else:
				if target and attack_area.overlaps_body(target) and can_attack:
					current_enemy_state = EnemyState.ATTACKING
					current_attack_delay = randf_range(attack_delay_min, attack_delay_max)
					can_attack = false
				elif target and chase_area.overlaps_body(target):
					current_enemy_state = EnemyState.CHASING
				else:
					current_enemy_state = EnemyState.IDLE
	
	# Mantenha o velocity_to_apply do componente sincronizado com a velocidade
	# real do CharacterBody2D para os outros estados.
	if current_enemy_state != EnemyState.CHASING:
		movement_component.velocity_to_apply = velocity

#==========Navigation==========#
func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	# Only apply the computed velocity if the enemy is in the CHASING state
	if current_enemy_state == EnemyState.CHASING:
		velocity = safe_velocity
		move_and_slide()

func seeker_setup():
	await get_tree().physics_frame
	if target and navigation is NavigationAgent2D: # Add check for navigation type
		navigation.target_position = target.global_position

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
		if result.collider == target:
			can_see_target = true
		else:
			can_see_target = false
	else:
		can_see_target = true

#==========Character_Things==========#
func take_damage(amount: int) -> void:
	health.take_damage(amount)

func _on_died():
	print("Inimigo morreu!")
	queue_free()

func apply_knockback(force: float, hit_position: Vector2) -> void:
	current_enemy_state = EnemyState.KNOCKBACK
	movement_component.is_chasing = false # Garante que o movimento de perseguição pare
	var knockback_direction = (global_position - hit_position).normalized()
	var final_knockback_force = force / knockback_resistance
	knockback_vector = knockback_direction * final_knockback_force
	can_attack = true
	_knockback_effect()

func _knockback_effect():
		hit_animation.play("hit")

#==========Attacks==========#
func perform_attack() -> void:
	var attack_choice = randi_range(1, 2)
	if attack_choice == 1:
		attack_1()
	else:
		attack_2()

func attack_1():
	print("Ataque 1 lançado: DASH!")

	current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
	current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
	print("Não há alvo para o dash. Inimigo em POST_ATTACK_COOLDOWN.")

func attack_2():
	print("Ataque 2 lançado: Ataque normal.")
	
	current_enemy_state = EnemyState.POST_ATTACK_COOLDOWN
	current_post_attack_cooldown = randf_range(post_attack_cooldown_min, post_attack_cooldown_max)
	print("Ataque 2 realizado. Inimigo em POST_ATTACK_COOLDOWN.")
	print("Ataque 2 lançado: Ataque normal.")

#==========Areas==========#
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

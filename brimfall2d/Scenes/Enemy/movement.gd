extends Node

#=== Referências do Inimigo ===
@export var parent_character: CharacterBody2D
@onready var navigation_agent: NavigationAgent2D

#=== Parâmetros de Movimento ===
@export var move_speed: float = 50

# Apenas para o estado CHASING
@export var is_chasing: bool = false
@export var target: CharacterBody2D = null

# O 'velocity' será definido aqui e o inimigo principal irá usá-lo
var velocity_to_apply: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Garante que as referências foram definidas corretamente
	if not parent_character or not navigation_agent:
		push_error("MovementComponent requires a parent_character (CharacterBody2D) and a navigation_agent (NavigationAgent2D).")
		return
	
	# Conecte o sinal para receber a velocidade de navegação
	navigation_agent.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))

func update_movement(delta: float) -> void:
	if not parent_character or not navigation_agent or not target:
		velocity_to_apply = Vector2.ZERO
		return
	
	# Se o inimigo está no estado de perseguição
	if is_chasing:
		navigation_agent.target_position = target.global_position
		
		var next_path_position = navigation_agent.get_next_path_position()
		var desired_velocity = parent_character.global_position.direction_to(next_path_position) * move_speed
		
		# Define a velocidade desejada para o NavigationAgent2D.
		# A velocidade segura será calculada e enviada via _on_navigation_velocity_computed
		navigation_agent.set_velocity(desired_velocity)
	else:
		# Se não estiver em CHASING, a velocidade é zero
		velocity_to_apply = Vector2.ZERO

func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	# Recebe a velocidade segura do NavigationAgent2D e a armazena
	velocity_to_apply = safe_velocity

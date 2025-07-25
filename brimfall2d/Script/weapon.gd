extends Node2D

signal attack(weapon_push: float, weapon_dir: Vector2)

@onready var combos_node: Node2D = $Combos
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var player: CharacterBody2D = get_parent().get_parent() as CharacterBody2D

@onready var weapon_dir: Vector2 # Esta variável armazenará a direção atual da arma

var is_attacking: bool = false
var current_combo_index: int = -1 # Começa com -1 para indicar que nenhum combo está ativo
var attack_direction_angle: float

var current_weapon_push: float
var current_combo_window_time: float
var current_attack_interval_time: float

var combo_timer: Timer # Janela para continuar o combo
var attack_cooldown_timer: Timer # Cooldown para cada golpe individual (respeita o attack_interval_time)

func _ready():
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	for i in range(combos_node.get_child_count()):
		var combo_node = combos_node.get_child(i)
		combo_node.visible = false
		var hitbox = combo_node.find_child("HitBox", true, false)
		if hitbox and hitbox is Area2D:
			hitbox.monitoring = false
			hitbox.set_deferred("monitorable", false)

	combo_timer = Timer.new()
	add_child(combo_timer)
	combo_timer.one_shot = true
	combo_timer.timeout.connect(_on_combo_timeout)

	attack_cooldown_timer = Timer.new()
	add_child(attack_cooldown_timer)
	attack_cooldown_timer.one_shot = true

func _process(delta):
	# O _update_weapon_direction() só precisa definir a rotação quando não está atacando.
	# Durante o ataque, a rotação é definida nos métodos start_attack/next_combo.
	if not is_attacking:
		_update_weapon_direction_based_on_mouse()
	# A variável weapon_dir será atualizada logo antes do emit_signal em start_attack e next_combo.

func _input(event):
	if event.is_action_pressed("attack"):
		if not is_attacking and attack_cooldown_timer.time_left <= 0:
			start_attack()
		elif is_attacking and combo_timer.time_left > 0 and current_combo_index < combos_node.get_child_count() - 1 and attack_cooldown_timer.time_left <= 0:
			next_combo()

func start_attack():
	if player and (player.current_movement_state == player.MovementState.ROLLING or player.current_movement_state == player.MovementState.RECOILING):
		return

	is_attacking = true
	current_combo_index = 0
	
	# Calcula a direção do ataque ANTES de pegar as propriedades
	# e antes de emitir o sinal, para garantir que weapon_dir esteja atualizado
	_calculate_and_set_attack_direction()
	
	update_current_combo_properties()
	
	# Emitir o sinal com a weapon_dir já atualizada
	emit_signal("attack", current_weapon_push, weapon_dir)

	play_current_combo_animation()
	combo_timer.start()
	attack_cooldown_timer.start()

func next_combo():
	if current_combo_index >= 0 && current_combo_index < combos_node.get_child_count():
		var current_combo_node = combos_node.get_child(current_combo_index)
		current_combo_node.visible = false
		var hitbox = current_combo_node.find_child("HitBox", true, false)
		if hitbox and hitbox is Area2D:
			hitbox.monitoring = false
			hitbox.set_deferred("monitorable", false)

	current_combo_index += 1
	if current_combo_index < combos_node.get_child_count():
		# Calcula a direção do ataque para o próximo combo ANTES de emitir o sinal
		_calculate_and_set_attack_direction() 
		
		update_current_combo_properties()
		
		# Emitir o sinal com a weapon_dir já atualizada
		emit_signal("attack", current_weapon_push, weapon_dir)
		
		play_current_combo_animation()
		combo_timer.start()
		attack_cooldown_timer.start()
	else:
		finish_attack()

func play_current_combo_animation():
	var combo_node = combos_node.get_child(current_combo_index)
	if combo_node:
		combo_node.visible = true
		var hitbox = combo_node.find_child("HitBox", true, false)
		if hitbox and hitbox is Area2D:
			hitbox.monitoring = true
			hitbox.monitorable = true 

		var combo_name = "Combo" + str(current_combo_index + 1)
		if animation_player.has_animation(combo_name):
			animation_player.play(combo_name)
		else:
			print("Animação não encontrada para: ", combo_name)
			finish_attack()
	else:
		finish_attack()

func finish_attack():
	is_attacking = false
	current_combo_index = -1
	combo_timer.stop()
	for i in range(combos_node.get_child_count()):
		var combo_node = combos_node.get_child(i)
		combo_node.visible = false
		var hitbox = combo_node.find_child("HitBox", true, false)
		if hitbox and hitbox is Area2D:
			hitbox.monitoring = false
			hitbox.set_deferred("monitorable", false)

func _on_animation_finished(anim_name: String):
	var expected_anim_name = "Combo" + str(current_combo_index + 1)
	if anim_name == expected_anim_name:
		if current_combo_index >= 0 && current_combo_index < combos_node.get_child_count():
			var current_combo_node = combos_node.get_child(current_combo_index)
			current_combo_node.visible = false
			var hitbox = current_combo_node.find_child("HitBox", true, false)
			if hitbox and hitbox is Area2D:
				hitbox.monitoring = false
				hitbox.set_deferred("monitorable", false)

		if (combo_timer.time_left <= 0 and is_attacking) or \
		   (current_combo_index == combos_node.get_child_count() - 1 and anim_name == expected_anim_name):
			finish_attack()

func _on_combo_timeout():
	if is_attacking:
		finish_attack()

func _update_weapon_direction_based_on_mouse():
	var mouse_position = get_global_mouse_position()
	var weapon_global_position = global_position
	var direction = mouse_position - weapon_global_position
	rotation = direction.angle() - PI

func _calculate_and_set_attack_direction():

	var mouse_position = get_global_mouse_position()
	var weapon_global_position = global_position
	
	attack_direction_angle = (mouse_position - weapon_global_position).angle() 
	rotation = attack_direction_angle - PI 
	
	weapon_dir = Vector2.RIGHT.rotated(rotation + PI)

func update_current_combo_properties():
	if current_combo_index >= 0 and current_combo_index < combos_node.get_child_count():
		var current_combo_node = combos_node.get_child(current_combo_index)
		var hitbox = current_combo_node.find_child("HitBox", true, false)
		if hitbox and hitbox is HitBox and hitbox.has_method("get_weapon_properties"):
			var props = hitbox.get_weapon_properties()
			current_weapon_push = props["weapon_push"]
			current_combo_window_time = props["combo_window_time"]
			current_attack_interval_time = props["attack_interval_time"]

			if combo_timer:
				combo_timer.wait_time = current_combo_window_time
			if attack_cooldown_timer:
				attack_cooldown_timer.wait_time = current_attack_interval_time
		else:
			printerr("Erro: HitBox não encontrada ou não é do tipo HitBox com o método get_weapon_properties para o combo: ", current_combo_index)
			current_weapon_push = 60.0
			current_combo_window_time = 0.6
			current_attack_interval_time = 0.1
			if combo_timer: combo_timer.wait_time = current_combo_window_time
			if attack_cooldown_timer: attack_cooldown_timer.wait_time = current_attack_interval_time
	else:
		printerr("Erro: current_combo_index inválido em update_current_combo_properties: ", current_combo_index)
		current_weapon_push = 60.0
		current_combo_window_time = 0.6
		current_attack_interval_time = 0.1
		if combo_timer: combo_timer.wait_time = current_combo_window_time
		if attack_cooldown_timer: attack_cooldown_timer.wait_time = current_attack_interval_time

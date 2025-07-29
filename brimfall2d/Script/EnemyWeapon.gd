extends Node2D

@onready var enemy: CharacterBody2D = get_parent().get_parent() as CharacterBody2D
@onready var animation_enemy: AnimationPlayer = $AnimationEnemy # Assuming you have an AnimationPlayer here for the enemy's weapon animations

# We'll use this to control visibility and hitbox
@onready var attack_sprite1: Node2D = $Attack1 # Assuming you have a Sprite2D named Attack1Sprite for the weapon's visual
@onready var attack_sprite2: Node2D = $Attack2 # Assuming you have a Sprite2D named Attack1Sprite for the weapon's visual
@onready var attack_hitbox: Area2D = $Attack1/AttackSprite/HitBox # Assuming you have an Area2D named Attack1HitBox for the attack's hitbox

# New hitboxes for Attack2, assuming they are children of attack_sprite2
@onready var attack2_hitbox: Area2D = $Attack2/AttackSprite/HitBox # Assuming a similar structure for Attack2


func _ready() -> void:
	if enemy:
		enemy.connect("attack1", Callable(self, "_execute_attack1"))
		enemy.connect("attack2", Callable(self, "_execute_attack2"))

	if animation_enemy:
		animation_enemy.animation_finished.connect(Callable(self, "_on_attack_animation_finished"))

	if attack_sprite1:
		attack_sprite1.visible = false
	if attack_sprite2: # Initialize attack_sprite2 as well
		attack_sprite2.visible = false

func _execute_attack1(player_dir: Vector2):
	rotation = player_dir.angle() - PI

	# 2. Make the weapon visible and enable its hitbox
	if attack_sprite1:
		attack_sprite1.visible = true
	if attack_sprite2: # Ensure Attack2 sprite is hidden if Attack1 is active
		attack_sprite2.visible = false

	if attack_hitbox:
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
	if attack2_hitbox: # Ensure Attack2 hitbox is disabled if Attack1 is active
		attack2_hitbox.monitoring = false
		attack2_hitbox.monitorable = false

	# 3. Play the attack animation
	# Ensure you have an animation named "Attack1" in your AnimationPlayer.
	if animation_enemy and animation_enemy.has_animation("Attack1"):
		animation_enemy.play("Attack1")
	else:
		printerr("Error: Animation 'Attack1' not found in AnimationEnemy or AnimationPlayer is null.")
		# If animation fails, ensure visibility and hitbox are reset
		_on_attack_animation_finished("Attack1") # Call directly to reset state

func _execute_attack2(player_dir: Vector2):
	rotation = player_dir.angle() - PI

	# 2. Make the weapon visible and enable its hitbox for Attack2
	if attack_sprite2:
		attack_sprite2.visible = true
	if attack_sprite1: # Ensure Attack1 sprite is hidden if Attack2 is active
		attack_sprite1.visible = false

	if attack2_hitbox:
		attack2_hitbox.monitoring = true
		attack2_hitbox.monitorable = true
	if attack_hitbox: # Ensure Attack1 hitbox is disabled if Attack2 is active
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false

	# 3. Play the attack animation for Attack2
	# Ensure you have an animation named "Attack2" in your AnimationPlayer.
	if animation_enemy and animation_enemy.has_animation("Attack2"): # Changed to "Attack2"
		animation_enemy.play("Attack2")
	else:
		printerr("Error: Animation 'Attack2' not found in AnimationEnemy or AnimationPlayer is null.")
		# If animation fails, ensure visibility and hitbox are reset
		_on_attack_animation_finished("Attack2") # Call directly to reset state, passing "Attack2"

func _on_attack_animation_finished(anim_name: String):
	# Check if the finished animation is "Attack1"
	if anim_name == "Attack1":
		if attack_sprite1:
			attack_sprite1.visible = false
		if attack_hitbox:
			attack_hitbox.monitoring = false
			attack_hitbox.set_deferred("monitorable", false)
		print("Enemy 'Attack1' animation finished. Weapon hidden and hitbox disabled.")
	# Check if the finished animation is "Attack2"
	elif anim_name == "Attack2": # Added handling for "Attack2"
		if attack_sprite2:
			attack_sprite2.visible = false
		if attack2_hitbox:
			attack2_hitbox.monitoring = false
			attack2_hitbox.set_deferred("monitorable", false)
		print("Enemy 'Attack2' animation finished. Weapon hidden and hitbox disabled.")

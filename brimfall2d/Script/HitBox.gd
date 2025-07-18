extends Area2D
class_name HitBox

@export var damage:= 10
@export var knockback:= 80

# Altera o sinal para emitir o knockback_value e a hit_position
signal recoil(knockback_value: float, hit_position: Vector2)

func _init() -> void:
	collision_layer = 2
	collision_mask = 4
	# Removido 'emit_signal("died")' pois é tipicamente tratado pelo sistema de saúde do personagem, não pela hitbox em si.

func _ready() -> void:
	area_entered.connect(Callable(self, "_on_area_entered"))

func _on_area_entered(hurtbox: HurtBox) -> void:
	# Emite o sinal, passando o valor de knockback e a posição global da hitbox
	emit_signal("recoil", knockback, global_position)

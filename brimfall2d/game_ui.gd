extends Control

@onready var pause_menu: MarginContainer = $Menu_Screen/Pause_Menu
@onready var settings_menu: MarginContainer = $Menu_Screen/Settings_Menu

var settings_open = false

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause_menu") && settings_open == false:
		pause_menu_open()
		
	if Input.is_action_just_pressed("pause_menu") && settings_open == true:
		setting_menu_open()

func pause_menu_open():
		Global.toggle_pause()
		pause_menu.visible = not pause_menu.visible

func setting_menu_open():
		settings_menu.visible = not settings_menu.visible
		pause_menu.visible = not pause_menu.visible
		settings_open = not settings_open

func _on_resume_pressed() -> void:
	pause_menu_open()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_settings_pressed() -> void:
	setting_menu_open()

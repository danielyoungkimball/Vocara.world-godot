extends Control

func _ready() -> void:
	print("🚀 Starting Vocara...")
	
	# Load the main game scene directly (native builds have all assets bundled)
	print("🎬 Loading main game scene...")
	get_tree().change_scene_to_file("res://game/Game.tscn")

func _connect_to_server() -> void:
	# TODO: Implement multiplayer server connection
	pass

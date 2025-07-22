extends Node3D

func _ready() -> void:
	print("🚀 Starting Vocara...")
	
	# FIRST: Load asset manifest before anything else
	print("📋 Loading manifest...")
	await AssetStreamer._fetch_manifest()
	
	# Handle Player Info Fetch
	# Establish connect to server otherwise show errors
	# Check for patch/updates and prompt to update

	# if everything lookgs good - start game
	# safe load the game scene
	var game_scene = await AssetStreamer.safe_load_scene("res://game/Game.tscn")
	
	if game_scene and game_scene is PackedScene:
		get_tree().change_scene_to_packed(game_scene)
	else:
		print("❌ Failed to load main scene")
		# Show error to client

func _connect_to_server() -> void:
	pass

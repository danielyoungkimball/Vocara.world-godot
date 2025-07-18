extends Node3D

## Smart Floating Island Loader
## Handles conditional asset streaming for web builds while preserving editor workflow
## 
## Behavior:
## - Editor/Desktop: Does nothing, uses existing GLB
## - Web builds: Replaces content with streamed assets when needed

@onready var asset_streamer = get_node("../../AssetStreamer")
var island_loaded = false
var original_children = []

func _ready():
	print("[FloatingIslandLoader] Initializing on node: ", name)
	
	# Store original children (in case we need to restore them)
	for child in get_children():
		original_children.append(child)
	
	# Wait a frame to let the scene fully load
	await get_tree().process_frame
	
	# Check what type of build we're in
	if OS.has_feature("web"):
		print("[FloatingIslandLoader] Web build detected")
		_handle_web_build()
	else:
		print("[FloatingIslandLoader] Desktop/Editor build detected - using existing island")
		# Desktop/Editor: Do nothing, let the existing island work

func _handle_web_build():
	"""Handle asset streaming for web builds"""
	
	# Check if the island content loaded successfully
	var has_working_content = _check_island_content()
	
	if has_working_content:
		print("[FloatingIslandLoader] Existing island content works - keeping it")
		return
	
	print("[FloatingIslandLoader] Island content missing or broken - starting asset streaming")
	
	# Clear any broken content
	_clear_island_content()
	
	# Start asset streaming
	if asset_streamer:
		_start_asset_streaming()
	else:
		print("[FloatingIslandLoader] No AssetStreamer found - creating fallback")
		_create_fallback_island()

func _check_island_content() -> bool:
	"""Check if the island has working content loaded"""
	
	# Check if we have any MeshInstance3D children (indicating successful GLB load)
	for child in get_children():
		if child is MeshInstance3D:
			print("[FloatingIslandLoader] Found working MeshInstance3D content")
			return true
		if child.get_child_count() > 0:
			# Check nested children (GLB scenes have nested structure)
			for nested_child in child.get_children():
				if nested_child is MeshInstance3D:
					print("[FloatingIslandLoader] Found working nested MeshInstance3D content")
					return true
	
	print("[FloatingIslandLoader] No working mesh content found")
	return false

func _clear_island_content():
	"""Clear existing broken content"""
	print("[FloatingIslandLoader] Clearing broken island content")
	
	for child in get_children():
		child.queue_free()

func _start_asset_streaming():
	"""Start streaming the island asset"""
	print("[FloatingIslandLoader] Starting asset streaming...")
	
	# Show loading indicator
	_create_loading_indicator()
	
	# Connect to asset streamer signals
	asset_streamer.asset_loaded.connect(_on_asset_loaded)
	asset_streamer.asset_download_started.connect(_on_download_started)
	asset_streamer.asset_download_completed.connect(_on_download_completed)
	asset_streamer.streaming_error.connect(_on_streaming_error)
	
	# Request the floating island asset
	var already_loaded = asset_streamer.request_asset("floating_island.glb", "critical")
	
	if already_loaded:
		print("[FloatingIslandLoader] Asset already available!")
	else:
		print("[FloatingIslandLoader] Asset downloading...")

func _create_loading_indicator():
	"""Create a loading indicator while downloading"""
	print("[FloatingIslandLoader] Creating loading indicator...")
	
	var loading_indicator = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 3.0
	sphere_mesh.height = 6.0
	loading_indicator.mesh = sphere_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.2, 0.8, 1.0)
	loading_indicator.material_override = material
	
	add_child(loading_indicator)
	loading_indicator.name = "LoadingIndicator"
	
	# Animate the loading indicator
	var tween = create_tween()
	tween.set_loops()
	tween.parallel().tween_method(func(angle): loading_indicator.rotation_y = angle, 0.0, TAU, 2.0)
	tween.parallel().tween_method(func(scale): loading_indicator.scale = Vector3.ONE * scale, 0.8, 1.2, 1.0)
	tween.tween_method(func(scale): loading_indicator.scale = Vector3.ONE * scale, 1.2, 0.8, 1.0)

func _on_download_started(asset_name: String):
	if asset_name == "floating_island.glb":
		print("[FloatingIslandLoader] Download started for floating island")

func _on_download_completed(asset_name: String, success: bool):
	if asset_name == "floating_island.glb":
		if success:
			print("[FloatingIslandLoader] Download completed successfully!")
		else:
			print("[FloatingIslandLoader] Download failed - creating fallback")
			_create_fallback_island()

func _on_asset_loaded(asset_name: String, resource: Resource):
	if asset_name == "floating_island.glb":
		print("[FloatingIslandLoader] Asset loaded! Instantiating...")
		_instantiate_streamed_island(resource)

func _on_streaming_error(error_message: String):
	print("[FloatingIslandLoader] Streaming error: ", error_message)
	_create_fallback_island()

func _instantiate_streamed_island(resource: Resource):
	"""Replace content with streamed island"""
	if not resource:
		print("[FloatingIslandLoader] ERROR: Resource is null!")
		_create_fallback_island()
		return
	
	# Remove loading indicator
	var loading_indicator = get_node_or_null("LoadingIndicator")
	if loading_indicator:
		loading_indicator.queue_free()
	
	# Create the island instance
	var island_instance = resource.instantiate()
	if not island_instance:
		print("[FloatingIslandLoader] ERROR: Failed to instantiate island!")
		_create_fallback_island()
		return
	
	# Add the streamed island
	add_child(island_instance)
	
	print("[FloatingIslandLoader] ✅ Streamed island loaded successfully!")
	island_loaded = true

func _create_fallback_island():
	"""Create a fallback island when streaming fails"""
	print("[FloatingIslandLoader] Creating fallback island...")
	
	# Remove loading indicator
	var loading_indicator = get_node_or_null("LoadingIndicator")
	if loading_indicator:
		loading_indicator.queue_free()
	
	# Create island-like fallback
	var fallback = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 15.0
	cylinder_mesh.bottom_radius = 12.0
	cylinder_mesh.height = 8.0
	fallback.mesh = cylinder_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.7, 0.2)  # Island green
	material.roughness = 0.8
	fallback.material_override = material
	
	add_child(fallback)
	
	# Add some simple details
	var rock1 = MeshInstance3D.new()
	var rock_mesh = SphereMesh.new()
	rock_mesh.radius = 2.0
	rock1.mesh = rock_mesh
	rock1.position = Vector3(5, 4, 3)
	add_child(rock1)
	
	var rock2 = MeshInstance3D.new()
	rock2.mesh = rock_mesh
	rock2.position = Vector3(-4, 4, -2)
	rock2.scale = Vector3(0.7, 0.7, 0.7)
	add_child(rock2)
	
	print("[FloatingIslandLoader] ✅ Fallback island created!")
	island_loaded = true 

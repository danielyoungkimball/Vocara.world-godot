extends Node3D

## Floating Island Loader
## Handles loading the floating island model via asset streaming for web builds
## or directly from local files for editor/desktop builds

@onready var asset_streamer = get_node("../../AssetStreamer")
@onready var world = get_node("../../World")
@onready var placeholder = get_node("../../World/FloatingIslandPlaceholder")

var island_loaded = false
var island_resource_path = "res://assets/models/environment/floating_island.glb"

func _ready():
	# Wait a frame to ensure nodes are ready
	await get_tree().process_frame
	
	# Check if we're in a web build or editor/desktop
	if OS.has_feature("web"):
		# Web build - use asset streaming
		load_floating_island_streaming()
	else:
		# Editor/Desktop build - load directly
		load_floating_island_direct()

func load_floating_island_direct():
	"""Load the floating island directly from the local file system"""
	print("[FloatingIslandLoader] Loading island directly from: ", island_resource_path)
	
	# Check if the resource exists
	if not ResourceLoader.exists(island_resource_path):
		print("[FloatingIslandLoader] ERROR: Island resource not found at: ", island_resource_path)
		_create_fallback_island()
		return
	
	# Load the resource
	var island_scene = load(island_resource_path)
	if not island_scene:
		print("[FloatingIslandLoader] ERROR: Failed to load island resource!")
		_create_fallback_island()
		return
	
	# Instantiate and add to scene
	_instantiate_island(island_scene)

func load_floating_island_streaming():
	"""Load the floating island via asset streaming for web builds"""
	if not asset_streamer:
		print("[FloatingIslandLoader] ERROR: AssetStreamer not found!")
		_create_fallback_island()
		return
	
	if not placeholder:
		print("[FloatingIslandLoader] ERROR: FloatingIslandPlaceholder not found!")
		_create_fallback_island()
		return
	
	print("[FloatingIslandLoader] Requesting floating island asset via streaming...")
	
	# Connect to asset streamer signals
	asset_streamer.asset_loaded.connect(_on_asset_loaded)
	asset_streamer.asset_download_started.connect(_on_download_started)
	asset_streamer.asset_download_completed.connect(_on_download_completed)
	asset_streamer.streaming_error.connect(_on_streaming_error)
	
	# Request the floating island asset
	island_loaded = asset_streamer.request_asset("floating_island.glb", "critical")
	
	if island_loaded:
		print("[FloatingIslandLoader] Asset already loaded!")
	else:
		print("[FloatingIslandLoader] Asset will be downloaded...")

func _on_download_started(asset_name: String):
	if asset_name == "floating_island.glb":
		print("[FloatingIslandLoader] Download started for floating island")

func _on_download_completed(asset_name: String, success: bool):
	if asset_name == "floating_island.glb":
		if success:
			print("[FloatingIslandLoader] Download completed successfully!")
		else:
			print("[FloatingIslandLoader] Download failed!")
			_create_fallback_island()

func _on_asset_loaded(asset_name: String, resource: Resource):
	if asset_name == "floating_island.glb":
		print("[FloatingIslandLoader] Asset loaded via streaming, instantiating...")
		_instantiate_island(resource)

func _on_streaming_error(error_message: String):
	print("[FloatingIslandLoader] Streaming error: ", error_message)
	_create_fallback_island()

func _instantiate_island(resource: Resource):
	if not resource:
		print("[FloatingIslandLoader] ERROR: Resource is null!")
		_create_fallback_island()
		return
	
	# Create the island instance
	var island_instance = resource.instantiate()
	if not island_instance:
		print("[FloatingIslandLoader] ERROR: Failed to instantiate island!")
		_create_fallback_island()
		return
	
	# Set the transform from the placeholder
	island_instance.transform = placeholder.transform
	
	# Add to world
	world.add_child(island_instance)
	
	# Remove placeholder
	placeholder.queue_free()
	
	print("[FloatingIslandLoader] ✅ Floating island loaded successfully!")
	island_loaded = true

func _create_fallback_island():
	print("[FloatingIslandLoader] Creating fallback island...")
	
	# Create a simple cube as fallback
	var fallback = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(20, 5, 20)
	fallback.mesh = box_mesh
	
	# Create a basic material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.8, 0.3)  # Green color
	fallback.material_override = material
	
	# Set transform from placeholder
	fallback.transform = placeholder.transform
	
	# Add to world
	world.add_child(fallback)
	
	# Remove placeholder
	placeholder.queue_free()
	
	print("[FloatingIslandLoader] ✅ Fallback island created!")
	island_loaded = true 

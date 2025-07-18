extends Node

## Global Asset Manager
## Automatically handles large asset streaming for web builds using node groups
## 
## Usage:
## 1. Add large asset nodes to the "large_asset_stream" group
## 2. Set node metadata: set_meta("asset_path", "floating_island.glb")
## 3. System automatically handles streaming for web builds
## 4. Desktop builds work normally

signal asset_stream_started(node_name: String, asset_path: String)
signal asset_stream_completed(node_name: String, success: bool)
signal asset_stream_error(node_name: String, error: String)

# Asset registry mapping node names to streaming info
var asset_registry = {}
var asset_streamer: Node = null
var is_web_build: bool = false

func _ready():
	name = "GlobalAssetManager"
	
	# Check if we're in a web build
	is_web_build = OS.has_feature("web")
	
	print("[GlobalAssetManager] Initializing - Web build: ", is_web_build)
	
	# Wait for scene tree to be ready
	await get_tree().process_frame
	
	if is_web_build:
		_initialize_web_streaming()
	else:
		print("[GlobalAssetManager] Desktop build - asset streaming disabled")

func _initialize_web_streaming():
	"""Initialize asset streaming for web builds"""
	print("[GlobalAssetManager] Initializing web asset streaming...")
	
	# Find or create AssetStreamer
	asset_streamer = _find_or_create_asset_streamer()
	
	if not asset_streamer:
		print("[GlobalAssetManager] ERROR: Could not initialize AssetStreamer")
		return
	
	# Connect signals
	asset_streamer.asset_loaded.connect(_on_asset_loaded)
	asset_streamer.asset_download_started.connect(_on_asset_download_started)
	asset_streamer.asset_download_completed.connect(_on_asset_download_completed)
	asset_streamer.streaming_error.connect(_on_asset_streaming_error)
	
	# Scan for tagged assets
	_scan_and_process_tagged_assets()

func _find_or_create_asset_streamer() -> Node:
	"""Find existing AssetStreamer or create new one"""
	
	# First try to find existing AssetStreamer
	var streamer = get_tree().get_first_node_in_group("asset_streamer")
	
	if streamer:
		print("[GlobalAssetManager] Found existing AssetStreamer")
		return streamer
	
	# Create new AssetStreamer
	var asset_streamer_script = load("res://src/assets/AssetStreamer.gd")
	
	if not asset_streamer_script:
		print("[GlobalAssetManager] ERROR: Could not load AssetStreamer script")
		return null
	
	streamer = Node.new()
	streamer.set_script(asset_streamer_script)
	streamer.name = "AssetStreamer"
	streamer.add_to_group("asset_streamer")
	
	# Add to scene tree
	get_tree().root.add_child(streamer)
	
	print("[GlobalAssetManager] Created new AssetStreamer")
	return streamer

func _scan_and_process_tagged_assets():
	"""Scan all scenes for nodes tagged with large_asset_stream"""
	print("[GlobalAssetManager] Scanning for tagged assets...")
	
	var tagged_nodes = get_tree().get_nodes_in_group("large_asset_stream")
	
	if tagged_nodes.is_empty():
		print("[GlobalAssetManager] No tagged assets found")
		return
	
	print("[GlobalAssetManager] Found ", tagged_nodes.size(), " tagged assets")
	
	# Process each tagged asset
	for node in tagged_nodes:
		_process_tagged_asset(node)

func _process_tagged_asset(node: Node):
	"""Process a single tagged asset node"""
	var asset_path = node.get_meta("asset_path", "")
	
	if asset_path.is_empty():
		print("[GlobalAssetManager] WARNING: Node '", node.name, "' in large_asset_stream group has no asset_path metadata")
		return
	
	print("[GlobalAssetManager] Processing tagged asset: ", node.name, " -> ", asset_path)
	
	# Store in registry
	asset_registry[node.name] = {
		"node": node,
		"asset_path": asset_path,
		"original_children": [],
		"loading_indicator": null
	}
	
	# Replace with loading indicator
	_replace_with_loading_indicator(node, asset_path)
	
	# Start streaming
	_start_asset_streaming(node.name, asset_path)

func _replace_with_loading_indicator(node: Node, asset_path: String):
	"""Replace asset content with loading indicator"""
	var registry_entry = asset_registry[node.name]
	
	# Store original children
	for child in node.get_children():
		if child.name != "AssetStreamer":  # Don't store AssetStreamer
			registry_entry.original_children.append(child)
			child.queue_free()
	
	# Create loading indicator
	var loading_indicator = _create_loading_indicator(asset_path)
	node.add_child(loading_indicator)
	
	registry_entry.loading_indicator = loading_indicator
	
	print("[GlobalAssetManager] Replaced '", node.name, "' content with loading indicator")

func _create_loading_indicator(asset_path: String) -> Node3D:
	"""Create a visual loading indicator"""
	var indicator = MeshInstance3D.new()
	indicator.name = "LoadingIndicator"
	
	# Create glowing sphere
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 5.0
	sphere_mesh.height = 10.0
	indicator.mesh = sphere_mesh
	
	# Create glowing material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.4, 0.9, 1.0)
	material.emission_energy = 2.0
	indicator.material_override = material
	
	# Add floating animation
	var tween = create_tween()
	tween.set_loops()
	tween.parallel().tween_method(func(y): indicator.position.y = y, 0.0, 2.0, 1.5)
	tween.parallel().tween_method(func(angle): indicator.rotation_y = angle, 0.0, TAU, 2.0)
	tween.tween_method(func(y): indicator.position.y = y, 2.0, 0.0, 1.5)
	
	return indicator

func _start_asset_streaming(node_name: String, asset_path: String):
	"""Start streaming an asset"""
	print("[GlobalAssetManager] Starting stream for: ", asset_path)
	
	emit_signal("asset_stream_started", node_name, asset_path)
	
	# Request asset from streamer
	var already_loaded = asset_streamer.request_asset(asset_path, "critical")
	
	if already_loaded:
		print("[GlobalAssetManager] Asset already available: ", asset_path)

# AssetStreamer signal handlers
func _on_asset_download_started(asset_path: String):
	print("[GlobalAssetManager] Download started: ", asset_path)

func _on_asset_download_completed(asset_path: String, success: bool):
	print("[GlobalAssetManager] Download completed: ", asset_path, " (success: ", success, ")")
	
	if not success:
		# Find node for this asset
		for node_name in asset_registry:
			if asset_registry[node_name].asset_path == asset_path:
				_handle_streaming_failure(node_name)
				break

func _on_asset_loaded(asset_path: String, resource: Resource):
	print("[GlobalAssetManager] Asset loaded: ", asset_path)
	
	# Find node for this asset
	for node_name in asset_registry:
		if asset_registry[node_name].asset_path == asset_path:
			_replace_with_streamed_asset(node_name, resource)
			break

func _on_asset_streaming_error(error: String):
	print("[GlobalAssetManager] Streaming error: ", error)

func _replace_with_streamed_asset(node_name: String, resource: Resource):
	"""Replace loading indicator with streamed asset"""
	var registry_entry = asset_registry[node_name]
	var node = registry_entry.node
	
	# Remove loading indicator
	if registry_entry.loading_indicator:
		registry_entry.loading_indicator.queue_free()
	
	# Instantiate streamed asset
	var asset_instance = resource.instantiate()
	
	if not asset_instance:
		print("[GlobalAssetManager] ERROR: Failed to instantiate asset for: ", node_name)
		_handle_streaming_failure(node_name)
		return
	
	# Add to node
	node.add_child(asset_instance)
	
	print("[GlobalAssetManager] ✅ Successfully replaced '", node_name, "' with streamed asset")
	emit_signal("asset_stream_completed", node_name, true)

func _handle_streaming_failure(node_name: String):
	"""Handle asset streaming failure"""
	print("[GlobalAssetManager] Handling streaming failure for: ", node_name)
	
	var registry_entry = asset_registry[node_name]
	var node = registry_entry.node
	
	# Remove loading indicator
	if registry_entry.loading_indicator:
		registry_entry.loading_indicator.queue_free()
	
	# Create fallback content
	var fallback = _create_fallback_content(node_name)
	node.add_child(fallback)
	
	emit_signal("asset_stream_completed", node_name, false)
	emit_signal("asset_stream_error", node_name, "Failed to stream asset")

func _create_fallback_content(node_name: String) -> Node3D:
	"""Create fallback content when streaming fails"""
	var fallback = MeshInstance3D.new()
	fallback.name = "FallbackContent"
	
	# Create a simple geometric shape based on asset type
	var mesh = CylinderMesh.new()
	mesh.top_radius = 8.0
	mesh.bottom_radius = 6.0
	mesh.height = 5.0
	fallback.mesh = mesh
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 0.2)  # Brownish fallback
	material.roughness = 0.8
	fallback.material_override = material
	
	return fallback

# Public API
func register_asset_manually(node: Node, asset_path: String):
	"""Manually register a node for asset streaming"""
	node.set_meta("asset_path", asset_path)
	node.add_to_group("large_asset_stream")
	
	if is_web_build:
		_process_tagged_asset(node)

func get_streaming_status(node_name: String) -> Dictionary:
	"""Get streaming status for a node"""
	if not asset_registry.has(node_name):
		return {"status": "not_found"}
	
	var entry = asset_registry[node_name]
	return {
		"status": "registered",
		"asset_path": entry.asset_path,
		"has_loading_indicator": entry.loading_indicator != null
	} 
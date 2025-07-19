extends Node

## Global Asset Manager - Enhanced Stream Orchestrator
## Seamlessly handles both bundled (res://) and streamed assets
## Automatically detects nodes tagged for streaming and manages their asset loading
## 
## Usage:
## 1. Add nodes to the "large_asset_stream" group for automatic streaming
## 2. Set node metadata: set_meta("asset_path", "models/environment/floating_island.glb")
## 3. System handles the rest automatically - no code changes needed!

signal streaming_initialized()
signal asset_stream_started(node_name: String, asset_path: String)
signal asset_stream_completed(node_name: String, success: bool)
signal asset_stream_error(node_name: String, error_message: String)
signal all_streaming_assets_ready()

# Configuration
@export var enable_streaming: bool = true
@export var auto_process_on_ready: bool = true
@export var show_streaming_progress: bool = true
@export var debug_scene_tree: bool = false  # Enable for web debugging

# Asset streaming state
var asset_streamer: Node
var streaming_nodes: Dictionary = {}  # node_path -> asset_info
var node_references: Dictionary = {}  # node_path -> node_reference
var pending_streams: Array = []
var completed_streams: int = 0
var total_streams: int = 0
var is_initialized: bool = false

# Scene integration
var original_meshes: Dictionary = {}  # node -> original_mesh_path (deprecated)
var placeholder_scenes: Dictionary = {} # node -> placeholder_resource

func _ready():
	name = "GlobalAssetManager"
	
	# Wait a frame for scene tree to fully initialize
	await get_tree().process_frame
	
	# Debug scene tree structure (especially important for web builds)
	if debug_scene_tree or OS.has_feature("web"):
		_debug_scene_tree()
	
	# Find the AssetStreamer with multiple fallback strategies
	asset_streamer = _find_asset_streamer()
	if not asset_streamer:
		print("[GlobalAssetManager] ERROR: AssetStreamer not found after all attempts!")
		return
	
	# Connect to AssetStreamer signals
	asset_streamer.connect("asset_ready", _on_asset_ready)
	asset_streamer.connect("asset_failed", _on_asset_failed)
	asset_streamer.connect("streaming_error", _on_streaming_error)
	
	if auto_process_on_ready:
		call_deferred("initialize_streaming")

func initialize_streaming():
	"""Initialize the streaming system and scan for assets"""
	if is_initialized:
		print("[GlobalAssetManager] Already initialized")
		return
	
	print("[GlobalAssetManager] Initializing asset streaming system...")
	
	# Check if we're in a web build (streaming enabled)
	var is_web_build = OS.has_feature("web")
	
	if not enable_streaming or not is_web_build:
		print("[GlobalAssetManager] Streaming disabled or not web build, using bundled assets")
		is_initialized = true
		streaming_initialized.emit()
		return
	
	# Scan scene tree for streaming assets
	_scan_streaming_assets()
	
	if total_streams == 0:
		print("[GlobalAssetManager] No streaming assets found")
		is_initialized = true
		streaming_initialized.emit()
		all_streaming_assets_ready.emit()
	else:
		print("[GlobalAssetManager] Found ", total_streams, " streaming assets to load")
		_start_streaming_process()
	
	is_initialized = true
	streaming_initialized.emit()

func _scan_streaming_assets():
	"""Scan the scene tree for nodes tagged for streaming"""
	streaming_nodes.clear()
	node_references.clear()
	pending_streams.clear()
	completed_streams = 0
	total_streams = 0
	
	# Find all nodes in the "large_asset_stream" group
	var streaming_group = get_tree().get_nodes_in_group("large_asset_stream")
	
	for node in streaming_group:
		var asset_path = node.get_meta("asset_path", "")
		
		if asset_path.is_empty():
			print("[GlobalAssetManager] WARNING: Node ", node.name, " in streaming group but no asset_path metadata")
			continue
		
		print("[GlobalAssetManager] Found streaming asset: ", node.name, " -> ", asset_path)
		
		# Use node path as consistent key
		var node_path = node.get_path()
		
		# Store the asset info using node path as key
		streaming_nodes[node_path] = {
			"asset_path": asset_path,
			"node_name": node.name,
			"node_path": node_path,
			"original_scene": null,
			"is_loaded": false
		}
		
		# Store node reference separately
		node_references[node_path] = node
		
		pending_streams.append(node_path)
		total_streams += 1
		
		# Replace with placeholder if needed
		_setup_placeholder_for_node(node)

func _setup_placeholder_for_node(node: Node):
	"""Set up a placeholder for a node while its asset loads"""
	if not node.has_method("set_visible"):
		return
	
	# For 3D nodes, we can make them invisible or replace with a simple placeholder
	if node is Node3D:
		# Store original visibility
		var node_path = node.get_path()
		var asset_info = streaming_nodes[node_path]
		asset_info["original_visible"] = node.visible
		
		# Create a simple placeholder (optional)
		if show_streaming_progress:
			_create_loading_placeholder(node)
		else:
			node.visible = false

func _create_loading_placeholder(node: Node3D):
	"""Create a visual loading placeholder for 3D nodes"""
	var placeholder = MeshInstance3D.new()
	placeholder.name = node.name + "_Loading_Placeholder"
	
	# Create a simple spinning cube to indicate loading
	var mesh = BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	placeholder.mesh = mesh
	
	# Add a material that indicates loading
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.7)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.6, 1.0, 1)
	material.emission_energy = 0.3
	placeholder.material_override = material
	
	# Add to the same parent
	if node.get_parent():
		node.get_parent().add_child(placeholder)
		placeholder.global_transform = node.global_transform
		
		# Store reference for cleanup
		placeholder_scenes[node] = placeholder
		
		# Simple rotation animation
		var tween = get_tree().create_tween()
		tween.set_loops()
		tween.tween_property(placeholder, "rotation", Vector3(0, TAU, 0), 2.0)

func _start_streaming_process():
	"""Start loading all streaming assets"""
	print("[GlobalAssetManager] Starting asset streaming process...")
	
	# Ensure we have a valid AssetStreamer reference
	_ensure_asset_streamer_reference()
	
	for node_path in pending_streams:
		var asset_info = streaming_nodes[node_path]
		var asset_path = asset_info.asset_path
		
		print("[GlobalAssetManager] Requesting asset: ", asset_path, " for node: ", asset_info.node_name)
		asset_stream_started.emit(asset_info.node_name, asset_path)
		
		# Request the asset from AssetStreamer
		asset_streamer.request_asset(asset_path, "high")

func _on_asset_ready(asset_identifier: String, resource: Resource):
	"""Handle asset successfully loaded"""
	print("[GlobalAssetManager] Asset ready: ", asset_identifier)
	
	# Find the node path(s) waiting for this asset
	var node_paths_for_asset = _find_nodes_for_asset(asset_identifier)
	
	for node_path in node_paths_for_asset:
		var node = node_references.get(node_path)
		if not node or not is_instance_valid(node):
			print("[GlobalAssetManager] WARNING: Node reference lost for path: ", node_path)
			continue
			
		_apply_asset_to_node(node, resource)
		
		var asset_info = streaming_nodes[node_path]
		asset_info.is_loaded = true
		completed_streams += 1
		
		asset_stream_completed.emit(asset_info.node_name, true)
		print("[GlobalAssetManager] ✅ Asset applied to node: ", asset_info.node_name)
	
	_check_streaming_completion()

func _on_asset_failed(asset_identifier: String, fallback_resource: Resource):
	"""Handle asset loading failed but with fallback"""
	print("[GlobalAssetManager] Asset failed but fallback available: ", asset_identifier)
	
	var node_paths_for_asset = _find_nodes_for_asset(asset_identifier)
	
	for node_path in node_paths_for_asset:
		var node = node_references.get(node_path)
		if not node or not is_instance_valid(node):
			print("[GlobalAssetManager] WARNING: Node reference lost for path: ", node_path)
			completed_streams += 1
			continue
			
		if fallback_resource:
			_apply_asset_to_node(node, fallback_resource)
		
		var asset_info = streaming_nodes[node_path]
		asset_info.is_loaded = true
		completed_streams += 1
		
		asset_stream_completed.emit(asset_info.node_name, false)
		print("[GlobalAssetManager] ⚠️ Fallback applied to node: ", asset_info.node_name)
	
	_check_streaming_completion()

func _on_streaming_error(asset_identifier: String, error_message: String):
	"""Handle complete asset loading failure"""
	print("[GlobalAssetManager] Asset streaming error: ", asset_identifier, " - ", error_message)
	
	var node_paths_for_asset = _find_nodes_for_asset(asset_identifier)
	
	for node_path in node_paths_for_asset:
		var asset_info = streaming_nodes[node_path]
		completed_streams += 1
		
		asset_stream_error.emit(asset_info.node_name, error_message)
		print("[GlobalAssetManager] ❌ Asset failed for node: ", asset_info.node_name)
	
	_check_streaming_completion()

func _find_nodes_for_asset(asset_identifier: String) -> Array:
	"""Find all node paths waiting for a specific asset"""
	var matching_node_paths = []
	
	for node_path in streaming_nodes:
		var asset_info = streaming_nodes[node_path]
		if asset_info.asset_path == asset_identifier or asset_info.asset_path.get_file() == asset_identifier.get_file():
			matching_node_paths.append(node_path)
	
	return matching_node_paths

func _apply_asset_to_node(node: Node, resource: Resource):
	"""Apply a loaded resource to its target node"""
	# Clean up placeholder first
	_cleanup_placeholder(node)
	
	# Apply the resource based on node and resource type
	if resource is PackedScene:
		_apply_scene_to_node(node, resource)
	elif resource is Mesh and node is MeshInstance3D:
		_apply_mesh_to_node(node, resource)
	elif resource is Texture2D:
		_apply_texture_to_node(node, resource)
	elif resource is AudioStream and node.has_method("set_stream"):
		node.set_stream(resource)
	else:
		print("[GlobalAssetManager] WARNING: Don't know how to apply resource type ", resource.get_class(), " to node ", node.name)

func _apply_scene_to_node(node: Node, scene: PackedScene):
	"""Replace a node with a loaded scene"""
	var parent = node.get_parent()
	if not parent:
		print("[GlobalAssetManager] WARNING: Cannot replace node without parent: ", node.name)
		return
	
	# Get the old node path for updating our references
	var old_node_path = node.get_path()
	
	# Instance the new scene
	var new_instance = scene.instantiate()
	if not new_instance:
		print("[GlobalAssetManager] ERROR: Failed to instantiate scene for ", node.name)
		return
	
	# Copy transform and other properties
	if node is Node3D and new_instance is Node3D:
		new_instance.global_transform = node.global_transform
	
	# Copy name and metadata
	new_instance.name = node.name
	for meta_key in node.get_meta_list():
		new_instance.set_meta(meta_key, node.get_meta(meta_key))
	
	# Replace in scene tree
	var node_index = node.get_index()
	parent.remove_child(node)
	parent.add_child(new_instance)
	parent.move_child(new_instance, node_index)
	
	# Update node reference (path should be the same since name is the same)
	node_references[old_node_path] = new_instance
	
	print("[GlobalAssetManager] Scene applied and node replaced: ", new_instance.name)

func _apply_mesh_to_node(node: MeshInstance3D, mesh: Mesh):
	"""Apply a mesh to a MeshInstance3D node"""
	node.mesh = mesh
	node.visible = true
	print("[GlobalAssetManager] Mesh applied to: ", node.name)

func _apply_texture_to_node(node: Node, texture: Texture2D):
	"""Apply a texture to an appropriate node"""
	if node.has_method("set_texture"):
		node.set_texture(texture)
	elif node is MeshInstance3D and node.get_surface_override_material(0):
		var material = node.get_surface_override_material(0)
		if material.has_property("texture_albedo"):
			material.texture_albedo = texture
	else:
		print("[GlobalAssetManager] WARNING: Don't know how to apply texture to node: ", node.name)

func _cleanup_placeholder(node: Node):
	"""Clean up loading placeholder for a node"""
	if placeholder_scenes.has(node):
		var placeholder = placeholder_scenes[node]
		if placeholder and is_instance_valid(placeholder):
			placeholder.queue_free()
		placeholder_scenes.erase(node)
	
	# Restore original visibility
	if node is Node3D:
		var node_path = node.get_path()
		if streaming_nodes.has(node_path):
			var asset_info = streaming_nodes[node_path]
			if asset_info.has("original_visible"):
				node.visible = asset_info.original_visible

func _check_streaming_completion():
	"""Check if all streaming assets are complete"""
	if completed_streams >= total_streams:
		print("[GlobalAssetManager] ✅ All streaming assets loaded! (", completed_streams, "/", total_streams, ")")
		all_streaming_assets_ready.emit()

func _debug_scene_tree():
	"""Debug the scene tree structure for web build troubleshooting"""
	print("[GlobalAssetManager] === SCENE TREE DEBUG ===")
	
	var root = get_tree().get_root()
	print("Root node: ", root.name, " (children: ", root.get_child_count(), ")")
	
	# Print all root children
	for i in range(root.get_child_count()):
		var child = root.get_child(i)
		print("  Child ", i, ": ", child.name, " (", child.get_class(), ")")
		
		# Print children of Main node if it exists
		if child.name == "Main":
			print("    Main node children: ", child.get_child_count())
			for j in range(child.get_child_count()):
				var main_child = child.get_child(j)
				print("      ", j, ": ", main_child.name, " (", main_child.get_class(), ")")
	
	# Check if we can find our current node's path
	print("GlobalAssetManager path: ", get_path())
	var parent = get_parent()
	print("GlobalAssetManager parent: ", parent.name if parent else "None")
	
	print("[GlobalAssetManager] === END SCENE TREE DEBUG ===")

func _find_asset_streamer() -> Node:
	"""Find AssetStreamer using multiple strategies for web compatibility"""
	var candidates = [
		# Strategy 1: Absolute path (works in local builds)
		"/root/Main/AssetStreamer",
		
		# Strategy 2: Direct under root (web builds)
		"/root/AssetStreamer",
		
		# Strategy 3: Relative to parent (if we're in Main)
		"../AssetStreamer",
		
		# Strategy 4: Sibling search (if we're both children of Main)
		"AssetStreamer",
		
		# Strategy 5: Search from parent's children
		null  # Will use manual search
	]
	
	for path in candidates:
		if path == null:
			# Strategy 4: Manual search through parent's children
			var parent = get_parent()
			if parent:
				print("[GlobalAssetManager] Searching manually in parent: ", parent.name)
				for i in range(parent.get_child_count()):
					var child = parent.get_child(i)
					if child.name == "AssetStreamer":
						print("[GlobalAssetManager] ✅ Found AssetStreamer via manual search: ", child.get_path())
						return child
		else:
			print("[GlobalAssetManager] Trying path: ", path)
			var node = get_node_or_null(path)
			if node:
				print("[GlobalAssetManager] ✅ Found AssetStreamer at: ", path, " -> ", node.get_path())
				return node
			else:
				print("[GlobalAssetManager] Not found at: ", path)
	
	# Strategy 5: Global search by name (last resort)
	print("[GlobalAssetManager] Attempting global search for AssetStreamer...")
	var all_nodes = get_tree().get_nodes_in_group("asset_streamer")
	if all_nodes.size() > 0:
		print("[GlobalAssetManager] ✅ Found AssetStreamer via group search: ", all_nodes[0].get_path())
		return all_nodes[0]
	
	# Strategy 6: Search entire tree (very last resort)
	print("[GlobalAssetManager] Attempting full tree search...")
	var found_node = _search_tree_for_asset_streamer(get_tree().get_root())
	if found_node:
		print("[GlobalAssetManager] ✅ Found AssetStreamer via tree search: ", found_node.get_path())
		return found_node
	
	# Strategy 7: Create AssetStreamer programmatically (web build fallback)
	print("[GlobalAssetManager] AssetStreamer missing from scene - creating programmatically...")
	return _create_asset_streamer_node()

func _search_tree_for_asset_streamer(node: Node) -> Node:
	"""Recursively search for AssetStreamer in the entire tree"""
	if node.name == "AssetStreamer" and node.get_script() != null:
		return node
	
	for child in node.get_children():
		var result = _search_tree_for_asset_streamer(child)
		if result:
			return result
	
	return null

func _create_asset_streamer_node() -> Node:
	"""Create AssetStreamer programmatically for web builds where it's missing"""
	print("[GlobalAssetManager] Creating AssetStreamer programmatically...")
	
	# Load AssetStreamer script
	var asset_streamer_script = load("res://src/assets/AssetStreamer.gd")
	if not asset_streamer_script:
		print("[GlobalAssetManager] ERROR: Cannot load AssetStreamer script!")
		return null
	
	# Create the node
	var streamer_node = Node.new()
	streamer_node.name = "AssetStreamer"
	streamer_node.set_script(asset_streamer_script)
	
	# Add it to the same parent as GlobalAssetManager
	var parent = get_parent()
	if not parent:
		parent = get_tree().get_root()
	
	parent.add_child(streamer_node)
	print("[GlobalAssetManager] ✅ Created AssetStreamer at: ", streamer_node.get_path())
	
	return streamer_node

func _ensure_asset_streamer_reference():
	"""Ensure we have a valid AssetStreamer reference, reacquire if necessary"""
	if not asset_streamer or not is_instance_valid(asset_streamer):
		print("[GlobalAssetManager] AssetStreamer reference lost, reacquiring...")
		asset_streamer = _find_asset_streamer()
		
		if not asset_streamer:
			print("[GlobalAssetManager] ERROR: Cannot find AssetStreamer!")
			return
		
		# Reconnect signals if we had to reacquire
		if not asset_streamer.is_connected("asset_ready", _on_asset_ready):
			asset_streamer.connect("asset_ready", _on_asset_ready)
			asset_streamer.connect("asset_failed", _on_asset_failed)
			asset_streamer.connect("streaming_error", _on_streaming_error)
			print("[GlobalAssetManager] ✅ AssetStreamer reference restored and signals reconnected")
		else:
			print("[GlobalAssetManager] ✅ AssetStreamer reference restored")

# ===== PUBLIC API =====

func request_additional_asset(asset_path: String, priority: String = "medium"):
	"""Request an additional asset outside of the automatic system"""
	_ensure_asset_streamer_reference()
	
	if not asset_streamer:
		print("[GlobalAssetManager] ERROR: AssetStreamer not available")
		return
	
	print("[GlobalAssetManager] Requesting additional asset: ", asset_path)
	asset_streamer.request_asset(asset_path, priority)

func is_streaming_complete() -> bool:
	"""Check if all streaming is complete"""
	return completed_streams >= total_streams and is_initialized

func get_streaming_progress() -> float:
	"""Get current streaming progress (0.0 to 1.0)"""
	if total_streams == 0:
		return 1.0
	
	return float(completed_streams) / float(total_streams)

func get_streaming_status() -> Dictionary:
	"""Get detailed streaming status"""
	return {
		"is_initialized": is_initialized,
		"total_streams": total_streams,
		"completed_streams": completed_streams,
		"pending_streams": pending_streams.size(),
		"progress": get_streaming_progress(),
		"is_complete": is_streaming_complete(),
		"streaming_enabled": enable_streaming
	}

func preload_critical_assets():
	"""Preload assets marked as critical priority"""
	if not asset_streamer:
		return
	
	# Request critical assets based on scene analysis
	# This can be extended to analyze the current scene and preload important assets
	print("[GlobalAssetManager] Preloading critical assets...")

# ===== DEBUGGING AND TESTING =====

func debug_print_streaming_nodes():
	"""Debug function to print all streaming nodes"""
	print("[GlobalAssetManager] === STREAMING NODES DEBUG ===")
	for node_path in streaming_nodes:
		var info = streaming_nodes[node_path]
		print("Path: ", node_path, " | Node: ", info.node_name, " | Asset: ", info.asset_path, " | Loaded: ", info.is_loaded)
	print("[GlobalAssetManager] === END DEBUG ===")

func force_reload_streaming_assets():
	"""Force reload all streaming assets (for debugging)"""
	print("[GlobalAssetManager] Force reloading all streaming assets...")
	completed_streams = 0
	
	for node_path in streaming_nodes:
		var asset_info = streaming_nodes[node_path]
		asset_info.is_loaded = false
		
		var node = node_references.get(node_path)
		if node and is_instance_valid(node):
			_setup_placeholder_for_node(node)
	
	_start_streaming_process() 

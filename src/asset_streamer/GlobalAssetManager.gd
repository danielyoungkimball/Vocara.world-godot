extends Node

## Global Asset Manager - Simple Stream Orchestrator
## Automatically detects nodes tagged for streaming and manages their asset loading
## Works with the simplified AssetStreamer for direct URL mapping
## 
## Usage:
## 1. Add nodes to "large_asset_stream" group
## 2. Set "asset_path" metadata on nodes (e.g. "models/characters/player.glb")
## 3. System handles streaming automatically

signal streaming_initialized()
signal asset_stream_started(node_name: String, asset_path: String)
signal asset_stream_completed(node_name: String, success: bool)
signal asset_stream_error(node_name: String, error_message: String)
signal all_streaming_assets_ready()

# Configuration
@export var enable_streaming: bool = true
@export var auto_process_on_ready: bool = true
@export var show_streaming_progress: bool = true
@export var immediate_fallbacks: bool = true  # Load fallbacks immediately while downloading

# Asset streaming state
var asset_streamer: AssetStreamer
var streaming_nodes: Dictionary = {}  # asset_path -> Array[node_info]
var pending_assets: Array = []
var completed_assets: Array = []
var failed_assets: Array = []
var is_initialized: bool = false

# Visual feedback
var placeholder_nodes: Dictionary = {}  # node -> placeholder
var fallback_applied_nodes: Dictionary = {}  # node -> fallback_resource

func _ready():
	name = "GlobalAssetManager"
	
	# Wait a frame for scene tree to initialize
	await get_tree().process_frame
	
	# Find AssetStreamer
	asset_streamer = _find_asset_streamer()
	if not asset_streamer:
		print("[GlobalAssetManager] ERROR: AssetStreamer not found!")
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
	
	# Check if streaming should be enabled
	if not enable_streaming:
		print("[GlobalAssetManager] Streaming disabled")
		is_initialized = true
		streaming_initialized.emit()
		return
	
	# Check if AssetStreamer wants to stream assets
	if not asset_streamer._should_stream_asset():
		print("[GlobalAssetManager] AssetStreamer reports streaming not needed for this build")
		is_initialized = true
		streaming_initialized.emit()
		return
	
	# Scan for streaming assets
	_scan_streaming_assets()
	
	if pending_assets.size() == 0:
		print("[GlobalAssetManager] No streaming assets found")
		is_initialized = true
		streaming_initialized.emit()
		all_streaming_assets_ready.emit()
		return
	
	print("[GlobalAssetManager] Found ", pending_assets.size(), " unique assets to stream")
	_start_streaming_process()
	
	is_initialized = true
	streaming_initialized.emit()

func _scan_streaming_assets():
	"""Scan the scene tree for nodes tagged for streaming"""
	streaming_nodes.clear()
	pending_assets.clear()
	completed_assets.clear()
	failed_assets.clear()
	
	# Find all nodes in the "large_asset_stream" group
	var streaming_group = get_tree().get_nodes_in_group("large_asset_stream")
	
	for node in streaming_group:
		if not is_instance_valid(node):
			continue
			
		var asset_path = node.get_meta("asset_path", "")
		
		if asset_path.is_empty():
			print("[GlobalAssetManager] WARNING: Node ", node.name, " in streaming group but no asset_path metadata")
			continue
		
		# Normalize asset path
		if asset_path.begins_with("/"):
			asset_path = asset_path.substr(1)
		
		print("[GlobalAssetManager] Found streaming asset: ", node.name, " -> ", asset_path)
		
		# Create node info
		var node_info = {
			"node": node,
			"node_name": node.name,
			"node_path": node.get_path(),
			"asset_path": asset_path,
			"is_loaded": false
		}
		
		# Group nodes by asset path (multiple nodes can use same asset)
		if not streaming_nodes.has(asset_path):
			streaming_nodes[asset_path] = []
			pending_assets.append(asset_path)
		
		streaming_nodes[asset_path].append(node_info)
		
		# Set up placeholder for node
		_setup_placeholder_for_node(node)

func _setup_placeholder_for_node(node: Node):
	"""Set up a placeholder for a node while its asset loads"""
	if immediate_fallbacks:
		# Load and apply fallback immediately
		_load_and_apply_immediate_fallback(node)
	elif show_streaming_progress:
		# For 3D nodes, create a loading placeholder
		if node is Node3D:
			_create_loading_placeholder(node)
	else:
		if node.has_method("set_visible"):
			node.visible = false

func _load_and_apply_immediate_fallback(node: Node):
	"""Load and apply fallback immediately while asset downloads"""
	print("[GlobalAssetManager] Applying immediate fallback for: ", node.name)
	
	var fallback_resource = _create_fallback_resource(node)
	if fallback_resource and _apply_asset_to_node(node, fallback_resource, true):
		fallback_applied_nodes[node] = fallback_resource
		print("[GlobalAssetManager] ✅ Immediate fallback applied to: ", node.name)
	else:
		print("[GlobalAssetManager] ⚠️ Failed to apply immediate fallback to: ", node.name)
		# Fall back to loading placeholder
		if node is Node3D:
			_create_loading_placeholder(node)

func _create_fallback_resource(node: Node) -> Resource:
	"""Create appropriate fallback resource based on node type"""
	# Always try to use the missing_model.tscn first
	if ResourceLoader.exists("res://assets/fallbacks/missing_model.tscn"):
		print("[GlobalAssetManager] Using missing_model.tscn fallback")
		return load("res://assets/fallbacks/missing_model.tscn")
	
	# If missing_model.tscn doesn't exist, create programmatic fallback
	print("[GlobalAssetManager] Creating programmatic fallback")
	var scene = PackedScene.new()
	var mesh_node = MeshInstance3D.new()
	mesh_node.name = "MissingModel"
	
	# Create bright magenta box
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2, 2, 2)
	mesh_node.mesh = box_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 1, 0.8)  # Bright magenta
	material.emission_enabled = true
	material.emission = Color(1, 0, 1) * 0.3
	mesh_node.material_override = material
	
	scene.pack(mesh_node)
	return scene

func _create_loading_placeholder(node: Node3D):
	"""Create a visual loading placeholder for 3D nodes"""
	var placeholder = MeshInstance3D.new()
	placeholder.name = node.name + "_Loading"
	
	# Create a spinning wireframe cube
	var mesh = BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	placeholder.mesh = mesh
	
	# Add wireframe material
	var material = StandardMaterial3D.new()
	material.flags_unshaded = true
	material.flags_use_point_size = true
	material.flags_wireframe = true
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.8)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.6, 1.0) * 0.5
	placeholder.material_override = material
	
	# Add to same parent
	var parent = node.get_parent()
	if parent:
		parent.add_child(placeholder)
		placeholder.global_transform = node.global_transform
		
		# Store reference and animate
		placeholder_nodes[node] = placeholder
		_animate_placeholder(placeholder)

func _animate_placeholder(placeholder: MeshInstance3D):
	"""Add rotation animation to placeholder"""
	var tween = get_tree().create_tween()
	tween.set_loops()
	tween.tween_property(placeholder, "rotation", Vector3(0, TAU, 0), 2.0)

func _start_streaming_process():
	"""Start loading all streaming assets"""
	print("[GlobalAssetManager] Starting asset streaming process...")
	
	for asset_path in pending_assets:
		print("[GlobalAssetManager] Requesting asset: ", asset_path)
		asset_streamer.request_asset(asset_path, "high")
		
		# Emit signals for all nodes using this asset
		var node_infos = streaming_nodes[asset_path]
		for node_info in node_infos:
			asset_stream_started.emit(node_info.node_name, asset_path)

func _on_asset_ready(asset_path: String, resource: Resource):
	"""Handle asset successfully loaded"""
	print("[GlobalAssetManager] ✅ Real asset ready: ", asset_path)
	
	if not streaming_nodes.has(asset_path):
		print("[GlobalAssetManager] WARNING: Received asset not in streaming list: ", asset_path)
		return
	
	var node_infos = streaming_nodes[asset_path]
	var success_count = 0
	
	for node_info in node_infos:
		var node = node_info.node
		if not is_instance_valid(node):
			print("[GlobalAssetManager] WARNING: Node reference lost for: ", node_info.node_name)
			continue
		
		print("[GlobalAssetManager] Replacing fallback with real asset for: ", node_info.node_name)
		if _apply_asset_to_node(node, resource, false):  # false = not a fallback
			node_info.is_loaded = true
			success_count += 1
			asset_stream_completed.emit(node_info.node_name, true)
		else:
			asset_stream_completed.emit(node_info.node_name, false)
	
	print("[GlobalAssetManager] Real asset applied to ", success_count, "/", node_infos.size(), " nodes")
	completed_assets.append(asset_path)
	_check_streaming_completion()

func _on_asset_failed(asset_path: String, fallback_resource: Resource):
	"""Handle asset loading failed but with fallback"""
	print("[GlobalAssetManager] ⚠️ Asset failed with fallback: ", asset_path)
	
	if not streaming_nodes.has(asset_path):
		return
	
	var node_infos = streaming_nodes[asset_path]
	
	for node_info in node_infos:
		var node = node_info.node
		if not is_instance_valid(node):
			continue
		
		if fallback_resource and _apply_asset_to_node(node, fallback_resource):
			node_info.is_loaded = true
			asset_stream_completed.emit(node_info.node_name, false)
		else:
			asset_stream_error.emit(node_info.node_name, "Failed to load asset and fallback")
	
	failed_assets.append(asset_path)
	_check_streaming_completion()

func _on_streaming_error(asset_path: String, error_message: String):
	"""Handle complete asset loading failure"""
	print("[GlobalAssetManager] ❌ Asset streaming error: ", asset_path, " - ", error_message)
	
	if not streaming_nodes.has(asset_path):
		return
	
	var node_infos = streaming_nodes[asset_path]
	
	for node_info in node_infos:
		asset_stream_error.emit(node_info.node_name, error_message)
		_cleanup_placeholder(node_info.node)
	
	failed_assets.append(asset_path)
	_check_streaming_completion()

func _apply_asset_to_node(node: Node, resource: Resource, is_fallback: bool = false) -> bool:
	"""Apply a loaded resource to its target node"""
	# Clean up placeholder first (but not if this is a fallback application)
	if not is_fallback:
		_cleanup_placeholder(node)
		_cleanup_fallback(node)
	
	# Apply the resource based on node and resource type
	if resource is PackedScene:
		return _apply_scene_to_node(node, resource, is_fallback)
	elif resource is Mesh and node is MeshInstance3D:
		return _apply_mesh_to_node(node, resource)
	elif resource is Texture2D and node.has_method("set_texture"):
		node.set_texture(resource)
		return true
	elif resource is AudioStream and node.has_method("set_stream"):
		node.set_stream(resource)
		return true
	else:
		print("[GlobalAssetManager] WARNING: Don't know how to apply ", resource.get_class(), " to ", node.name)
		return false

func _apply_scene_to_node(node: Node, scene: PackedScene, is_fallback: bool = false) -> bool:
	"""Replace a node with a loaded scene"""
	var parent = node.get_parent()
	if not parent:
		print("[GlobalAssetManager] WARNING: Cannot replace node without parent: ", node.name)
		return false
	
	# Instance the new scene
	var new_instance = scene.instantiate()
	if not new_instance:
		print("[GlobalAssetManager] ERROR: Failed to instantiate scene")
		return false
	
	# Copy transform and properties
	if node is Node3D and new_instance is Node3D:
		new_instance.global_transform = node.global_transform
	
	# Copy name and metadata - preserve original asset_path for real asset replacement
	new_instance.name = node.name
	for meta_key in node.get_meta_list():
		new_instance.set_meta(meta_key, node.get_meta(meta_key))
	
	# Add marker for fallback identification
	if is_fallback:
		new_instance.set_meta("is_fallback", true)
		# Also add to fallback group for easy finding
		new_instance.add_to_group("fallback_assets")
	
	# Replace in scene tree
	var node_index = node.get_index()
	parent.remove_child(node)
	parent.add_child(new_instance)
	parent.move_child(new_instance, node_index)
	
	# Update our node references to point to the new instance
	_update_node_references(node, new_instance)
	
	var status = "✅ Fallback applied" if is_fallback else "✅ Real asset applied"
	print("[GlobalAssetManager] ", status, " and node replaced: ", new_instance.name)
	return true

func _update_node_references(old_node: Node, new_node: Node):
	"""Update node references when a node is replaced"""
	# Find and update references in streaming_nodes
	for asset_path in streaming_nodes:
		var node_infos = streaming_nodes[asset_path]
		for node_info in node_infos:
			if node_info.node == old_node:
				node_info.node = new_node
				node_info.node_path = new_node.get_path()
				break

func _cleanup_fallback(node: Node):
	"""Clean up fallback resource reference"""
	if fallback_applied_nodes.has(node):
		fallback_applied_nodes.erase(node)

func _apply_mesh_to_node(node: MeshInstance3D, mesh: Mesh) -> bool:
	"""Apply a mesh to a MeshInstance3D node"""
	node.mesh = mesh
	node.visible = true
	print("[GlobalAssetManager] ✅ Mesh applied to: ", node.name)
	return true

func _cleanup_placeholder(node: Node):
	"""Clean up loading placeholder for a node"""
	if placeholder_nodes.has(node):
		var placeholder = placeholder_nodes[node]
		if is_instance_valid(placeholder):
			placeholder.queue_free()
		placeholder_nodes.erase(node)
	
	# Restore visibility if it was hidden
	if node.has_method("set_visible"):
		node.visible = true

func _check_streaming_completion():
	"""Check if all streaming assets are complete"""
	var total_assets = pending_assets.size()
	var finished_assets = completed_assets.size() + failed_assets.size()
	
	if finished_assets >= total_assets:
		print("[GlobalAssetManager] ✅ All streaming complete! (", completed_assets.size(), " success, ", failed_assets.size(), " failed)")
		all_streaming_assets_ready.emit()

func _find_asset_streamer() -> AssetStreamer:
	"""Find AssetStreamer node in the scene tree"""
	# Strategy 1: Look for AssetStreamer as sibling
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child is AssetStreamer:
				print("[GlobalAssetManager] ✅ Found AssetStreamer as sibling: ", child.get_path())
				return child
	
	# Strategy 2: Look in the asset_streamer group
	var group_nodes = get_tree().get_nodes_in_group("asset_streamer")
	if group_nodes.size() > 0:
		var streamer = group_nodes[0]
		if streamer is AssetStreamer:
			print("[GlobalAssetManager] ✅ Found AssetStreamer in group: ", streamer.get_path())
			return streamer
	
	# Strategy 3: Search entire tree by name
	var found_streamer = _search_for_asset_streamer(get_tree().root)
	if found_streamer:
		print("[GlobalAssetManager] ✅ Found AssetStreamer by search: ", found_streamer.get_path())
		return found_streamer
	
	print("[GlobalAssetManager] ❌ AssetStreamer not found anywhere!")
	return null

func _search_for_asset_streamer(node: Node) -> AssetStreamer:
	"""Recursively search for AssetStreamer"""
	if node is AssetStreamer:
		return node
	
	for child in node.get_children():
		var result = _search_for_asset_streamer(child)
		if result:
			return result
	
	return null

# ===== PUBLIC API =====

func request_additional_asset(asset_path: String, priority: String = "medium"):
	"""Request an additional asset outside of the automatic system"""
	if not asset_streamer:
		print("[GlobalAssetManager] ERROR: AssetStreamer not available")
		return
	
	print("[GlobalAssetManager] Requesting additional asset: ", asset_path)
	asset_streamer.request_asset(asset_path, priority)

func is_streaming_complete() -> bool:
	"""Check if all streaming is complete"""
	if not is_initialized:
		return false
	
	var total_assets = pending_assets.size()
	var finished_assets = completed_assets.size() + failed_assets.size()
	return finished_assets >= total_assets

func get_streaming_progress() -> float:
	"""Get current streaming progress (0.0 to 1.0)"""
	if pending_assets.size() == 0:
		return 1.0
	
	var finished_assets = completed_assets.size() + failed_assets.size()
	return float(finished_assets) / float(pending_assets.size())

func get_streaming_status() -> Dictionary:
	"""Get detailed streaming status"""
	return {
		"is_initialized": is_initialized,
		"total_assets": pending_assets.size(),
		"completed_assets": completed_assets.size(),
		"failed_assets": failed_assets.size(),
		"progress": get_streaming_progress(),
		"is_complete": is_streaming_complete(),
		"streaming_enabled": enable_streaming,
		"asset_streamer_found": asset_streamer != null
	}

# ===== DEBUGGING =====

func debug_print_streaming_nodes():
	"""Debug function to print all streaming nodes"""
	print("[GlobalAssetManager] === STREAMING ASSETS DEBUG ===")
	for asset_path in streaming_nodes:
		var node_infos = streaming_nodes[asset_path]
		print("Asset: ", asset_path, " (", node_infos.size(), " nodes)")
		for node_info in node_infos:
			print("  Node: ", node_info.node_name, " | Loaded: ", node_info.is_loaded)
	print("[GlobalAssetManager] === END DEBUG ===")

func force_reload_streaming_assets():
	"""Force reload all streaming assets (for debugging)"""
	print("[GlobalAssetManager] Force reloading all streaming assets...")
	
	completed_assets.clear()
	failed_assets.clear()
	
	# Reset all node states and add placeholders
	for asset_path in streaming_nodes:
		var node_infos = streaming_nodes[asset_path]
		for node_info in node_infos:
			node_info.is_loaded = false
			if is_instance_valid(node_info.node):
				_setup_placeholder_for_node(node_info.node)
	
	_start_streaming_process() 

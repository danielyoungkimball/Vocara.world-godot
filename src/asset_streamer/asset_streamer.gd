extends Node

## AssetStreamer - Safe Asset Loading System

# Signals
signal ready_for_use
##
## Detects missing assets in scenes and replaces them with fallbacks while preparing for streaming.
## Designed for web builds where the assets folder doesn't exist and everything must be streamed.

# Asset streaming configuration
var dev_asset_route = "https://asset.localhost:8080"
var asset_cdn_route = "https://assets.vocara-multiplayer.com"
var manifest_url = "https://assets.vocara-multiplayer.com/manifest.json"

# Fallback resources
var fallback_model_scene: PackedScene
var fallback_texture: Texture2D
var fallback_mesh: Mesh

# Asset tracking
var missing_assets = {}  # Tracks assets that need to be streamed
var placeholder_nodes = {}  # Maps placeholder nodes to their target assets
var manifest_data = {}  # Cached manifest data

func _ready() -> void:
	# Load fallback resources
	fallback_model_scene = load("res://src/asset_streamer/fallbacks/missing_model.tscn")
	fallback_texture = load("res://src/asset_streamer/fallbacks/missing_model_missing_texture.png")
	fallback_mesh = load("res://src/asset_streamer/fallbacks/mesh.res")
	
	ready_for_use.emit()

func _fetch_manifest() -> void:
	"""Fetch the asset manifest from CDN and wait for completion"""
	# print("[AssetStreamer] Fetching manifest from: ", manifest_url)
	
	# Create HTTPRequest node and add to scene tree
	var manifest_request = HTTPRequest.new()
	add_child(manifest_request)
	
	# Make the request
	var error = manifest_request.request(manifest_url)
	if error != OK:
		push_error("[AssetStreamer] Failed to start manifest request: %d" % error)
		manifest_request.queue_free()
		return

	# Wait for the request to complete
	var response = await manifest_request.request_completed
	
	# Handle the response directly here
	var result = response[0]
	var response_code = response[1]
	var _headers = response[2]
	var body = response[3]
	
	# Clean up
	manifest_request.queue_free()
	
	# print("[AssetStreamer] Manifest request completed - Result: %d, Response: %d" % [result, response_code])
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[AssetStreamer] Failed to fetch manifest (result: %d)" % result)
		return
	
	if response_code != 200:
		push_error("[AssetStreamer] HTTP error fetching manifest (code: %d)" % response_code)
		return

	var json_string = body.get_string_from_utf8()
	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_error("[AssetStreamer] Failed to parse manifest JSON at line %d: %s" % [json.error_line, json.error_string])
		return

	manifest_data = json.data
	var total = manifest_data.get("metadata", {}).get("total_assets", 0)
	print("✅ Loaded %d assets from manifest" % total)

func _fetch_asset_from_cdn(asset_path: String) -> Resource:
	"""Fetch an asset from the CDN and wait for completion"""
	print("⬇️  Downloading: %s" % asset_path.get_file())
	
	# Create HTTPRequest node and add to scene tree
	var asset_request = HTTPRequest.new()
	add_child(asset_request)
	
	# Make the request
	var error = asset_request.request(asset_cdn_route + asset_path)
	if error != OK:
		push_error("❌ Failed to start download: %s" % asset_path.get_file())
		asset_request.queue_free()
		return null

	# Wait for the request to complete
	var response = await asset_request.request_completed
	
	# Handle the response directly here
	var result = response[0]
	var response_code = response[1]
	var _headers = response[2]  
	var body = response[3]
	
	# Clean up
	asset_request.queue_free()
	
	# Handle the response
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("❌ Download failed: %s (network error)" % asset_path.get_file())
		return null

	if response_code != 200:
		push_error("❌ Download failed: %s (HTTP %d)" % [asset_path.get_file(), response_code])
		return null

	# Save downloaded asset to local cache
	_save_asset_to_local_cache(asset_path, body)
	print("✅ Downloaded: %s" % asset_path.get_file())
	
	# Load from cache using FileAccess-based method
	return _load_asset_from_cache(asset_path)

func safe_load_scene(scene_path: String) -> PackedScene:
	"""
	Safely load a scene by ensuring all dependencies are cached first
	Recursively loads other scenes and assets until everything is available
	"""
	print("[AssetStreamer] 🩹 Safe loading scene: ", scene_path)
	
	# Step 1: Use Godot's built-in dependency system (more reliable than node inspection)
	var dependencies = _extract_scene_dependencies(scene_path)
	
	print("Found %d dependencies" % dependencies.size())
	
	# Step 2: Download ALL assets first (no recursive scene loading needed!)
	var downloaded_count = 0
	var cached_count = 0
	for asset_path in dependencies:
		# Skip if already cached
		if _asset_exists_in_cache(asset_path):
			cached_count += 1
			continue
			
		# Validate and download
		var validated_path = _validate_asset_path(asset_path)
		if validated_path:
			await _fetch_asset_from_cdn(validated_path)
			downloaded_count += 1
		else:
			push_error("❌ Asset not found in manifest: %s" % asset_path.get_file())

	if downloaded_count > 0:
		print("✅ Downloaded %d assets successfully" % downloaded_count)
	if cached_count > 0:
		print("✅ %d assets already cached" % cached_count)
	
	# Step 3: ALL assets guaranteed available - load scene with rewritten paths
	print("⚙️ Loading ", scene_path, " with rewritten asset paths...")
	var scene = _load_scene_with_rewritten_paths(scene_path)
	
	if scene:
		return scene
	else:
		push_error("❌ Failed to load scene: %s" % scene_path)
		return null

func _save_asset_to_local_cache(asset_path: String, body: PackedByteArray) -> void:
	"""Save the asset to the local cache"""
	# Check if the asset is already in the cache
	if _asset_exists_in_cache(asset_path):
		return

	# Convert asset path to local cache path
	var cache_path = "user://assets" + asset_path
	var cache_dir = cache_path.get_base_dir()
	
	# Create the directory structure if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive(cache_dir)
	else:
		push_error("[AssetStreamer] Failed to access user directory")
		return
	
	# Save the asset to the local cache
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()
		print("[AssetStreamer] ✅ Saved to cache: ", asset_path)
	else:
		push_error("[AssetStreamer] Failed to save asset to local cache: ", cache_path)

func _asset_exists_in_cache(asset_path: String) -> bool:
	"""Check if an asset exists in the local cache"""
	var cache_path = "user://assets" + asset_path
	return FileAccess.file_exists(cache_path)

func _load_asset_from_cache(asset_path: String) -> Resource:
	"""Load an asset from the local cache using FileAccess since ResourceLoader can't handle user:// paths"""
	var cache_path = "user://assets" + asset_path
	
	if not FileAccess.file_exists(cache_path):
		push_error("[AssetStreamer] Asset not found in cache: ", cache_path)
		return null
	
	print("[AssetStreamer] 🔎 Loading from cache: ", asset_path)
	
	# Read the file as bytes
	var file = FileAccess.open(cache_path, FileAccess.READ)
	if not file:
		push_error("[AssetStreamer] Failed to open cached file: ", cache_path)
		return null
	
	var file_buffer = file.get_buffer(file.get_length())
	file.close()
	
	# Determine resource type by file extension and create appropriate resource
	var extension = asset_path.get_extension().to_lower()
	
	match extension:
		"png", "jpg", "jpeg":
			var image = Image.new()
			var error = image.load_png_from_buffer(file_buffer) if extension == "png" else image.load_jpg_from_buffer(file_buffer)
			if error == OK:
				var texture = ImageTexture.new()
				texture.set_image(image)
				return texture
			else:
				push_error("[AssetStreamer] Failed to load image from cache: ", cache_path)
		
		"glb", "gltf":
			# For 3D models, use GLTFDocument to load directly from buffer
			var doc = GLTFDocument.new()
			var state = GLTFState.new()
			var error = doc.append_from_buffer(file_buffer, "", state)
			
			if error == OK:
				var scene_node = doc.generate_scene(state)
				# Wrap the Node3D in a PackedScene (which is a Resource)
				var packed_scene = PackedScene.new()
				packed_scene.pack(scene_node)
				return packed_scene
			else:
				push_error("[AssetStreamer] Failed to load GLB/GLTF from buffer: " + error_string(error))
				return null
		
		"ogg", "wav":
			# Audio files
			if extension == "ogg":
				var audio_stream = AudioStreamOggVorbis.new()
				audio_stream.set_data(file_buffer)
				return audio_stream
			else:
				# WAV files are more complex, might need different handling
				push_error("[AssetStreamer] WAV loading from cache not implemented yet")
		
		_:
			push_error("[AssetStreamer] Unsupported cached file type: ", extension)
	
	return null

func _load_scene_with_rewritten_paths(scene_path: String) -> PackedScene:
	"""Load a TSCN scene with asset paths rewritten to point to our cache"""
	
	# Don't check file_exists() in web builds - it's unreliable
	# Just try to read the scene content directly
	var scene_file_bytes = FileAccess.get_file_as_bytes(scene_path)
	
	if scene_file_bytes.is_empty():
		push_error("❌ Could not read scene content from: %s" % scene_path)
		print("🔍 This might be a web build file access issue")
		return null
	
	var scene_content = scene_file_bytes.get_string_from_utf8()
	print("✅ Successfully read %d characters from scene file" % scene_content.length())
	
	# Rewrite all res://assets/ paths to user://assets/
	var rewritten_content = scene_content.replace("res://assets/", "user://assets/")
	
	# Save to temporary file
	var temp_path = "user://temp_scene_" + scene_path.get_file()
	var temp_file = FileAccess.open(temp_path, FileAccess.WRITE)
	if not temp_file:
		push_error("❌ Failed to create temporary scene file: %s" % temp_path)
		return null
	
	temp_file.store_string(rewritten_content)
	temp_file.close()
	
	# Load from temporary file
	var scene = ResourceLoader.load(temp_path, "PackedScene")
	
	if scene:
		print("✅ Loaded scene from: %s" % temp_path)
	
	# Clean up temporary file
	DirAccess.remove_absolute(temp_path)
	
	return scene

func _extract_scene_dependencies(scene_path: String) -> Array[String]:
	"""Extract ALL asset dependencies recursively using DFS"""
	var all_assets: Array[String] = []
	var processed_scenes: Array[String] = []  # Avoid infinite recursion
	
	_collect_all_assets_recursive(scene_path, all_assets, processed_scenes)
	
	return all_assets

func _collect_all_assets_recursive(scene_path: String, all_assets: Array[String], processed_scenes: Array[String]) -> void:
	"""Recursively collect all assets from a scene and its dependencies (DFS)"""
	
	# Avoid infinite recursion
	if scene_path in processed_scenes:
		return
	processed_scenes.append(scene_path)
	
	# print("[AssetStreamer] 🔍 Scanning %s..." % scene_path)
	
	# Get immediate dependencies
	var resource_dependencies = ResourceLoader.get_dependencies(scene_path)
	
	for dep_path in resource_dependencies:
		# Extract actual path from UID format
		var actual_path = dep_path
		if dep_path.contains("::::"):
			actual_path = dep_path.split("::::")[1]
		
		if actual_path.begins_with("res://assets/"):
			# It's an asset - add to collection
			var asset_path = actual_path.replace("res://assets", "")
			if asset_path not in all_assets:
				all_assets.append(asset_path)
				# print("[AssetStreamer] ➕ Asset: %s" % asset_path)
		
		elif actual_path.begins_with("res://scenes/") and actual_path.ends_with(".tscn"):
			# It's another scene - recursively scan it
			# print("[AssetStreamer] 📁 Recursing into: %s" % actual_path)
			_collect_all_assets_recursive(actual_path, all_assets, processed_scenes)

func _validate_asset_path(extracted_path: String) -> String:
	"""
	Validate and normalize an asset path against the manifest
	Returns the correct path if found, null if not in manifest
	"""
	# Normalize path - remove leading slash if present
	var normalized_path = extracted_path
	if normalized_path.begins_with("/"):
		normalized_path = normalized_path.substr(1)
	
	# Check if manifest is loaded
	if manifest_data.is_empty():
		push_error("❌ Manifest not loaded when validating: %s" % normalized_path.get_file())
		return ""
	
	# Look for the asset in the manifest
	var assets = manifest_data.get("assets", [])
	for asset in assets:
		var manifest_path = asset.get("path", "")
		if manifest_path == normalized_path:
			# print("[AssetStreamer] ✅ Path validated: ", extracted_path, " → ", manifest_path)
			return "/" + normalized_path  # Return with leading slash for consistency
	
	# Asset not found in manifest - try common variations
	# print("[AssetStreamer] ❌ Asset not found in manifest: ", extracted_path)
	# print("[AssetStreamer] Searching for similar paths...")
	
	var filename = normalized_path.get_file()
	for asset in assets:
		var manifest_path = asset.get("path", "")
		if manifest_path.get_file() == filename:
			# print("[AssetStreamer] 🔄 Found similar asset: ", manifest_path, " (for ", extracted_path, ")")
			return "/" + manifest_path
	
	# No match found
	push_error("❌ Asset not found in manifest: %s" % extracted_path.get_file())
	return ""  # Return empty string to indicate failure

func get_missing_asset_count() -> int:
	"""Get the number of missing assets that need streaming"""
	return missing_assets.size()

func get_placeholder_count() -> int:
	"""Get the number of placeholder nodes"""
	return placeholder_nodes.size()

func list_cached_assets() -> Array[String]:
	"""List all assets in the cache"""
	var cached_assets: Array[String] = []
	var cache_dir = "user://assets"
	
	if DirAccess.dir_exists_absolute(cache_dir):
		_scan_cache_directory(cache_dir, cached_assets)
	
	return cached_assets

func _scan_cache_directory(dir_path: String, assets: Array[String]) -> void:
	"""Recursively scan cache directory for assets"""
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			var full_path = dir_path + "/" + file_name
			
			if dir.current_is_dir():
				# Recursively scan subdirectories
				_scan_cache_directory(full_path, assets)
			else:
				# Add file to assets list
				var asset_path = full_path.replace("user://assets", "")
				assets.append(asset_path)
			
			file_name = dir.get_next()

func print_cache_contents() -> void:
	"""Print all cached assets to console"""
	print("\n=== ASSET CACHE CONTENTS ===")
	var cached = list_cached_assets()
	
	if cached.is_empty():
		print("Cache is empty")
	else:
		print("Found %d cached assets:" % cached.size())
		for asset in cached:
			var cache_path = "user://assets" + asset
			var file = FileAccess.open(cache_path, FileAccess.READ)
			if file:
				var size = file.get_length()
				file.close()
				print("  - %s (%d bytes)" % [asset, size])
			else:
				print("  - %s (error reading)" % asset)
	
	print("Cache location: %s" % ProjectSettings.globalize_path("user://assets"))
	print("=============================\n")

func print_manifest_assets() -> void:
	"""Print all assets in the manifest for debugging path issues"""
	print("\n=== MANIFEST ASSETS ===")
	
	if manifest_data.is_empty():
		print("Manifest not loaded yet")
		return
	
	var assets = manifest_data.get("assets", [])
	print("Found %d assets in manifest:" % assets.size())
	
	for asset in assets:
		var path = asset.get("path", "")
		var asset_name = asset.get("name", "")
		var type = asset.get("type", "")
		print("  - %s (%s) [%s]" % [path, asset_name, type])
	
	print("========================\n")

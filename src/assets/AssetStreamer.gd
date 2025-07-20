class_name AssetStreamer
extends Node

## Enhanced Asset Streaming System for Vocara.world  
## Cache-first loading with server fallback and fallback assets

enum LoadingState {
	PENDING,
	RESOLVING,    
	DOWNLOADING,  
	CACHING,      
	LOADING,      
	READY,        
	FAILED        
}

signal asset_ready(asset_identifier: String, resource: Resource)
signal asset_download_started(asset_path: String)
# signal asset_download_progress(asset_path: String, progress: float)
signal asset_download_completed(asset_path: String, success: bool)
signal asset_failed(asset_identifier: String, fallback_resource: Resource)
signal streaming_error(asset_identifier: String, error_message: String)

# Configuration
@export var server_url: String = ""  # Will be set by environment config
@export var enable_caching: bool = true
@export var max_concurrent_downloads: int = 3
@export var retry_attempts: int = 3
@export var chunk_timeout: float = 30.0

# Core components
var path_resolver
var asset_states: Dictionary = {}
var asset_resources: Dictionary = {} 
var download_queue: Array = []
var active_downloads: Dictionary = {}
var cache_directory: String = "user://asset_cache/"

# HTTP clients
var client_pool: Array[HTTPRequest] = []
var manifest_client: HTTPRequest

func _ready():
	name = "AssetStreamer"
	add_to_group("asset_streamer")  # Add to group for reliable finding in web builds
	print("[AssetStreamer] Initializing...")
	
	# Load environment configuration
	_load_environment_config()
	
	# Initialize path resolver
	var resolver_script = load("res://src/core/AssetPathResolver.gd")
	if resolver_script:
		path_resolver = resolver_script.new()
		print("[AssetStreamer] ✅ AssetPathResolver loaded")
	else:
		print("[AssetStreamer] ❌ Failed to load AssetPathResolver")
		return
	
	# Create cache directory
	if not DirAccess.dir_exists_absolute(cache_directory):
		DirAccess.open("user://").make_dir_recursive(cache_directory)
	
	# Initialize HTTP client pool
	for i in range(max_concurrent_downloads):
		var client = HTTPRequest.new()
		add_child(client)
		client.timeout = chunk_timeout
		client.connect("request_completed", _on_request_completed)
		client_pool.append(client)
	
	# Create manifest client
	manifest_client = HTTPRequest.new()
	add_child(manifest_client)
	manifest_client.connect("request_completed", _on_manifest_loaded)
	
	# Load asset manifest
	call_deferred("load_asset_manifest")
	
	print("[AssetStreamer] ✅ Initialization complete")

func _load_environment_config():
	"""Load environment-specific configuration"""
	var env_config_script = load("res://src/config/environment.gd")
	if env_config_script:
		var env_config = env_config_script.new()
		server_url = env_config.get_server_url()
		# Store R2 CDN URL for direct asset access
		var r2_cdn_url = env_config.get_r2_cdn_url()
		print("[AssetStreamer] ✅ Environment config loaded")
		print("  🌐 Server: ", server_url)
		print("  ☁️  R2 CDN: ", r2_cdn_url)
		print("  🏠 Environment: ", env_config.get_environment())
	else:
		# Fallback to localhost for development
		server_url = "http://localhost:8080"
		print("[AssetStreamer] ⚠️  Environment config not found, using localhost")

func load_asset_manifest():
	"""Load asset manifest from server"""
	print("[AssetStreamer] Loading asset manifest from: ", server_url + "/assets/manifest")
	var error = manifest_client.request(server_url + "/assets/manifest")
	if error != OK:
		print("[AssetStreamer] Failed to request manifest: ", error)
		streaming_error.emit("", "Failed to request asset manifest")

func _on_manifest_loaded(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	"""Handle manifest loading completion"""
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			var manifest = json.data
			if path_resolver:
				path_resolver.set_manifest(manifest)
			print("[AssetStreamer] ✅ Manifest loaded - Version: ", manifest.get("version", "unknown"))
		else:
			print("[AssetStreamer] Failed to parse manifest JSON")
			streaming_error.emit("", "Failed to parse asset manifest")
	else:
		print("[AssetStreamer] Failed to load manifest: HTTP ", response_code)
		streaming_error.emit("", "Failed to load asset manifest (HTTP " + str(response_code) + ")")

# ===== PUBLIC API =====

func request_asset(asset_identifier: String, priority: String = "medium") -> void:
	"""Request an asset with guaranteed state management"""
	print("[AssetStreamer] Requesting asset: ", asset_identifier, " (priority: ", priority, ")")
	
	# Check current state
	var current_state = asset_states.get(asset_identifier, LoadingState.PENDING)
	
	match current_state:
		LoadingState.READY:
			print("[AssetStreamer] Asset already loaded: ", asset_identifier)
			call_deferred("_emit_asset_ready", asset_identifier)
			return
		LoadingState.FAILED:
			print("[AssetStreamer] Retrying failed asset: ", asset_identifier) 
			asset_states[asset_identifier] = LoadingState.PENDING
		LoadingState.DOWNLOADING, LoadingState.CACHING, LoadingState.LOADING:
			print("[AssetStreamer] Asset already loading: ", asset_identifier)
			return
		_:
			pass
	
	# Set state to resolving
	asset_states[asset_identifier] = LoadingState.RESOLVING
	
	# Start the loading pipeline
	call_deferred("_start_loading_pipeline", asset_identifier, priority)

func _start_loading_pipeline(asset_identifier: String, priority: String):
	"""Start the complete loading pipeline for an asset"""
	print("[AssetStreamer] Starting loading pipeline for: ", asset_identifier)
	
	if not path_resolver:
		print("[AssetStreamer] No path resolver available, loading fallback")
		_load_fallback_asset(asset_identifier, null)
		return
	
	# Resolve asset path
	var asset_info = path_resolver.resolve_asset(asset_identifier)
	
	if asset_info.load_strategy == 0:  # BUNDLED
		_load_bundled_asset(asset_identifier, asset_info)
	elif asset_info.load_strategy == 1:  # STREAMED
		if path_resolver.is_cached(asset_info):
			_load_cached_asset(asset_identifier, asset_info)
		else:
			_download_and_cache_asset(asset_identifier, asset_info, priority)
	elif asset_info.load_strategy == 2:  # HYBRID
		if not asset_info.res_path.is_empty() and ResourceLoader.exists(asset_info.res_path):
			_load_bundled_asset(asset_identifier, asset_info)
		elif path_resolver.is_cached(asset_info):
			_load_cached_asset(asset_identifier, asset_info)
		else:
			_load_fallback_asset(asset_identifier, asset_info)
	else:
		_load_fallback_asset(asset_identifier, asset_info)

func _load_bundled_asset(asset_identifier: String, asset_info):
	"""Load asset from res:// path"""
	print("[AssetStreamer] Loading bundled asset: ", asset_info.res_path)
	asset_states[asset_identifier] = LoadingState.LOADING
	
	var resource = load(asset_info.res_path)
	
	if resource:
		asset_resources[asset_identifier] = resource
		asset_states[asset_identifier] = LoadingState.READY
		print("[AssetStreamer] ✅ Bundled asset loaded: ", asset_identifier)
		asset_ready.emit(asset_identifier, resource)
	else:
		print("[AssetStreamer] Failed to load bundled asset: ", asset_info.res_path)
		_load_fallback_asset(asset_identifier, asset_info)

func _load_cached_asset(asset_identifier: String, asset_info):
	"""Load asset from local cache"""
	print("[AssetStreamer] Loading cached asset: ", asset_info.local_cache_path)
	asset_states[asset_identifier] = LoadingState.LOADING
	
	var resource = _load_resource_from_file(asset_info)
	
	if resource:
		asset_resources[asset_identifier] = resource
		asset_states[asset_identifier] = LoadingState.READY
		print("[AssetStreamer] ✅ Cached asset loaded: ", asset_identifier)
		asset_ready.emit(asset_identifier, resource)
	else:
		print("[AssetStreamer] Failed to load cached asset, will re-download: ", asset_identifier)
		_download_and_cache_asset(asset_identifier, asset_info, "high")

func _download_and_cache_asset(asset_identifier: String, asset_info, priority: String):
	"""Download asset from server and cache it"""
	print("[AssetStreamer] Downloading asset: ", asset_identifier)
	asset_states[asset_identifier] = LoadingState.DOWNLOADING
	
	var download_info = {
		"asset_identifier": asset_identifier,
		"asset_info": asset_info,
		"priority": priority,
		"attempts": 0
	}
	
	_queue_download(download_info)

func _load_fallback_asset(asset_identifier: String, asset_info):
	"""Load fallback asset when primary loading fails"""
	print("[AssetStreamer] Loading fallback for: ", asset_identifier)
	asset_states[asset_identifier] = LoadingState.LOADING
	
	var fallback_resource = _create_fallback_resource(asset_info)
	
	if fallback_resource:
		asset_resources[asset_identifier] = fallback_resource
		asset_states[asset_identifier] = LoadingState.FAILED
		print("[AssetStreamer] ⚠️ Fallback asset loaded for: ", asset_identifier)
		asset_failed.emit(asset_identifier, fallback_resource)
	else:
		asset_states[asset_identifier] = LoadingState.FAILED
		print("[AssetStreamer] ❌ Complete failure for asset: ", asset_identifier)
		streaming_error.emit(asset_identifier, "No fallback available")

func _create_fallback_resource(asset_info) -> Resource:
	"""Create appropriate fallback resource based on asset type"""
	if not asset_info:
		return _create_simple_model_fallback()
	
	match asset_info.asset_type:
		0:  # MODEL
			if ResourceLoader.exists("res://src/assets/fallbacks/missing_model.tscn"):
				return load("res://src/assets/fallbacks/missing_model.tscn")
			else:
				return _create_simple_model_fallback()
		1:  # TEXTURE
			return _create_simple_texture_fallback()
		2:  # AUDIO
			return _create_simple_audio_fallback()
		_:
			return _create_simple_model_fallback()

func _create_simple_model_fallback() -> Resource:
	"""Create a simple model fallback"""
	# Return the fallback scene we created
	if ResourceLoader.exists("res://src/assets/fallbacks/missing_model.tscn"):
		return load("res://src/assets/fallbacks/missing_model.tscn")
	else:
		# Create a simple box mesh as absolute fallback
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(2, 2, 2)
		return box_mesh

func _create_simple_texture_fallback() -> ImageTexture:
	"""Create a simple texture fallback"""
	if ResourceLoader.exists("res://src/assets/fallbacks/missing_texture.png"):
		return load("res://src/assets/fallbacks/missing_texture.png")
	else:
		# Create programmatic fallback
		var image = Image.create(64, 64, false, Image.FORMAT_RGB8)
		image.fill(Color(1, 0.5, 1))  # Bright pink
		return ImageTexture.create_from_image(image)

func _create_simple_audio_fallback() -> AudioStream:
	"""Create a simple audio fallback (silence)"""
	var audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 22050
	audio_stream.buffer_length = 1.0
	return audio_stream

func _load_resource_from_file(asset_info) -> Resource:
	"""Load resource from cached file based on asset type"""
	var cache_path = asset_info.local_cache_path
	var extension = asset_info.name.get_extension().to_lower()
	
	match extension:
		"glb":
			return _load_glb_from_cache(cache_path)
		"png", "jpg", "jpeg", "webp":
			return _load_image_from_cache(cache_path)  
		"ogg", "mp3", "wav":
			return _load_audio_from_cache(cache_path, extension)
		_:
			print("[AssetStreamer] Unsupported file type: ", extension)
			return null

func _load_glb_from_cache(cache_path: String) -> PackedScene:
	"""Load GLB model from cache"""
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var error = gltf.append_from_file(cache_path, state)
	
	if error == OK:
		var scene_node = gltf.generate_scene(state)
		var packed_scene = PackedScene.new()
		packed_scene.pack(scene_node)
		return packed_scene
	else:
		print("[AssetStreamer] Failed to load GLB from cache: ", cache_path, " Error: ", error)
		return null

func _load_image_from_cache(cache_path: String) -> ImageTexture:
	"""Load image texture from cache"""
	var image = Image.new()
	var error = image.load(cache_path)
	
	if error == OK:
		return ImageTexture.create_from_image(image)
	else:
		print("[AssetStreamer] Failed to load image from cache: ", cache_path, " Error: ", error)
		return null

func _load_audio_from_cache(cache_path: String, extension: String) -> AudioStream:
	"""Load audio stream from cache"""
	match extension:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(cache_path)
		"wav":
			var file = FileAccess.open(cache_path, FileAccess.READ)
			if file:
				var buffer = file.get_buffer(file.get_length())
				file.close()
				var audio_stream = AudioStreamWAV.new()
				audio_stream.data = buffer
				return audio_stream
		"mp3":
			var file = FileAccess.open(cache_path, FileAccess.READ)
			if file:
				var buffer = file.get_buffer(file.get_length())
				file.close()
				var audio_stream = AudioStreamMP3.new()
				audio_stream.data = buffer
				return audio_stream
	
	return null

# ===== DOWNLOAD MANAGEMENT =====

func _queue_download(download_info: Dictionary):
	"""Add download to priority queue"""
	var priority_value = _get_priority_value(download_info.priority)
	var insert_index = download_queue.size()
	
	for i in range(download_queue.size()):
		if priority_value > _get_priority_value(download_queue[i].priority):
			insert_index = i
			break
	
	download_queue.insert(insert_index, download_info)
	_process_download_queue()

func _get_priority_value(priority: String) -> int:
	"""Convert priority string to numeric value"""
	match priority:
		"critical": return 3
		"high": return 2 
		"medium": return 1
		_: return 0

func _process_download_queue():
	"""Process pending downloads using available HTTP clients"""
	while download_queue.size() > 0 and client_pool.size() > 0:
		var download_info = download_queue.pop_front()
		var client = client_pool.pop_front()
		_start_download(download_info, client)

func _start_download(download_info: Dictionary, client: HTTPRequest):
	"""Start downloading an asset"""
	var asset_identifier = download_info.asset_identifier
	var asset_info = download_info.asset_info
	
	print("[AssetStreamer] Starting download: ", asset_identifier)
	
	active_downloads[client] = download_info
	asset_download_started.emit(asset_info.relative_path)
	
	# Determine download URL
	var url = path_resolver.get_stream_url(asset_info, server_url)
	print("[AssetStreamer] Download URL: ", url)
	
	var error = client.request(url)
	if error != OK:
		print("[AssetStreamer] Failed to start request for ", asset_identifier, ": ", error)
		_handle_download_failure(client, "Failed to start HTTP request")

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	"""Handle completed HTTP request"""
	var client = null
	
	# Find which client completed
	for http_client in active_downloads:
		if http_client.get_instance_id() == get_viewport().get_children().has(http_client):
			client = http_client
			break
	
	if not client or not active_downloads.has(client):
		print("[AssetStreamer] Warning: Completed request from unknown client")
		return
	
	var download_info = active_downloads[client]
	var asset_identifier = download_info.asset_identifier
	var asset_info = download_info.asset_info
	
	if response_code == 200:
		print("[AssetStreamer] Download completed successfully: ", asset_identifier)
		_save_and_load_asset(asset_identifier, asset_info, body)
	else:
		print("[AssetStreamer] Download failed for ", asset_identifier, ": HTTP ", response_code)
		_handle_download_failure(client, "HTTP " + str(response_code))
	
	# Return client to pool and process next download
	active_downloads.erase(client)
	client_pool.append(client)
	_process_download_queue()

func _save_and_load_asset(asset_identifier: String, asset_info, data: PackedByteArray):
	"""Save downloaded asset to cache and load it"""
	asset_states[asset_identifier] = LoadingState.CACHING
	
	var cache_path = asset_info.local_cache_path
	var dir_path = cache_path.get_base_dir()
	
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.open("user://").make_dir_recursive(dir_path.replace("user://", ""))
	
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if file:
		file.store_buffer(data)
		file.close()
		
		print("[AssetStreamer] Asset cached: ", cache_path)
		asset_download_completed.emit(asset_info.relative_path, true)
		
		_load_cached_asset(asset_identifier, asset_info)
	else:
		print("[AssetStreamer] Failed to save asset to cache: ", cache_path)
		asset_states[asset_identifier] = LoadingState.FAILED
		_load_fallback_asset(asset_identifier, asset_info)

func _handle_download_failure(client: HTTPRequest, _error_message: String):
	"""Handle download failure with retry logic"""
	var download_info = active_downloads[client]
	var asset_identifier = download_info.asset_identifier
	var asset_info = download_info.asset_info
	
	download_info.attempts += 1
	
	if download_info.attempts < retry_attempts:
		print("[AssetStreamer] Retrying download for ", asset_identifier, " (attempt ", download_info.attempts + 1, "/", retry_attempts, ")")
		download_queue.push_front(download_info)
	else:
		print("[AssetStreamer] Max retry attempts reached for ", asset_identifier)
		asset_states[asset_identifier] = LoadingState.FAILED
		asset_download_completed.emit(asset_info.relative_path, false)
		_load_fallback_asset(asset_identifier, asset_info)
	
	active_downloads.erase(client)
	client_pool.append(client)

# ===== UTILITY METHODS =====

func _emit_asset_ready(asset_identifier: String):
	"""Deferred emit for already loaded assets"""
	if asset_resources.has(asset_identifier):
		asset_ready.emit(asset_identifier, asset_resources[asset_identifier])

func is_asset_ready(asset_identifier: String) -> bool:
	"""Check if asset is ready to use"""
	return asset_states.get(asset_identifier, LoadingState.PENDING) == LoadingState.READY

func get_asset_state(asset_identifier: String) -> LoadingState:
	"""Get current loading state of asset"""
	return asset_states.get(asset_identifier, LoadingState.PENDING)

func get_loaded_resource(asset_identifier: String) -> Resource:
	"""Get loaded resource if available"""
	return asset_resources.get(asset_identifier, null)

func clear_cache():
	"""Clear all cached assets"""
	print("[AssetStreamer] Clearing asset cache")
	var dir = DirAccess.open(cache_directory)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	asset_resources.clear()
	for identifier in asset_states:
		asset_states[identifier] = LoadingState.PENDING

func get_cache_info() -> Dictionary:
	"""Get information about the cache and loaded assets"""
	var ready_count = 0
	var loading_count = 0
	var failed_count = 0
	
	for state in asset_states.values():
		match state:
			LoadingState.READY:
				ready_count += 1
			LoadingState.DOWNLOADING, LoadingState.CACHING, LoadingState.LOADING:
				loading_count += 1
			LoadingState.FAILED:
				failed_count += 1
	
	return {
		"ready_assets": ready_count,
		"loading_assets": loading_count,
		"failed_assets": failed_count,
		"cache_directory": cache_directory,
		"manifest_loaded": path_resolver != null and path_resolver.manifest.size() > 0 if path_resolver else false
	} 

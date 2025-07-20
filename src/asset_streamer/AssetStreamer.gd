class_name AssetStreamer
extends Node

## Simple Asset Streaming System for Vocara.world  
## Direct URL mapping with environment-based URL selection
## Streams ALL assets on web and debug builds

enum LoadingState {
	PENDING,
	DOWNLOADING,
	READY,
	FAILED
}

signal asset_ready(asset_identifier: String, resource: Resource)
signal asset_download_started(asset_path: String)
# signal _asset_download_progress(asset_path: String, progress: float)
signal asset_download_completed(asset_path: String, success: bool)
signal asset_failed(asset_identifier: String, fallback_resource: Resource)
signal streaming_error(asset_identifier: String, error_message: String)

# Configuration
@export var max_concurrent_downloads: int = 3
@export var retry_attempts: int = 3
@export var request_timeout: float = 30.0

# State management
var asset_states: Dictionary = {}
var asset_resources: Dictionary = {}
var download_queue: Array = []
var active_downloads: Dictionary = {}

# HTTP clients
var client_pool: Array[HTTPRequest] = []

# Environment URLs
var base_url: String = ""
var config: ConfigFile

func _ready():
	name = "AssetStreamer"
	add_to_group("asset_streamer")
	print("[AssetStreamer] Initializing simple streaming system...")
	
	# Load configuration
	_load_streaming_config()
	
	# Set base URL based on environment
	_setup_environment_url()
	
	# Initialize HTTP client pool
	_init_http_clients()
	
	print("[AssetStreamer] ✅ Initialization complete - Base URL: ", base_url)

func _load_streaming_config():
	"""Load streaming configuration"""
	config = ConfigFile.new()
	var err = config.load("res://src/asset_streamer/streaming_config.cfg")
	
	if err != OK:
		print("[AssetStreamer] ❌ Failed to load streaming config, using defaults")
		config = ConfigFile.new()
		config.set_value("streaming", "max_concurrent_downloads", 3)
		config.set_value("streaming", "request_timeout", 120)
		config.set_value("cdn", "development_url", "http://localhost:8080/assets")
		config.set_value("cdn", "production_url", "https://assets.vocara-multiplayer.com")
	else:
		print("[AssetStreamer] ✅ Streaming config loaded")
	
	# Apply configuration
	max_concurrent_downloads = config.get_value("streaming", "max_concurrent_downloads", 3)
	request_timeout = config.get_value("streaming", "request_timeout", 120.0)

func _setup_environment_url():
	"""Setup base URL based on environment"""
	# Try to get environment from EnvironmentSwitch
	var env_script = load("res://addons/EnvironmentSwitch/environment.gd")
	if env_script:
		var env = env_script.new()
		var is_development = env.is_development()
		
		if is_development:
			base_url = config.get_value("cdn", "development_url", "http://localhost:8080/assets")
		else:
			base_url = config.get_value("cdn", "production_url", "https://assets.vocara-multiplayer.com")
		
		print("[AssetStreamer] Environment detected: ", "development" if is_development else "production")
	else:
		# Fallback to development
		base_url = config.get_value("cdn", "development_url", "http://localhost:8080/assets")
		print("[AssetStreamer] ⚠️ EnvironmentSwitch not found, defaulting to development")
	
	# Ensure base URL doesn't end with slash for consistent joining
	if base_url.ends_with("/"):
		base_url = base_url.substr(0, base_url.length() - 1)

func _init_http_clients():
	"""Initialize HTTP client pool"""
	for i in range(max_concurrent_downloads):
		var client = HTTPRequest.new()
		client.name = "AssetHTTP_" + str(i)
		add_child(client)
		client.timeout = request_timeout
		# Create bound callable that includes the client reference
		var callable = Callable(_on_request_completed).bind(client)
		client.connect("request_completed", callable)
		client_pool.append(client)
	
	print("[AssetStreamer] ✅ ", max_concurrent_downloads, " HTTP clients ready")

# ===== PUBLIC API =====

func request_asset(asset_path: String, priority: String = "medium") -> void:
	"""Request an asset for streaming"""
	# Normalize asset path (remove leading slash if present)
	if asset_path.begins_with("/"):
		asset_path = asset_path.substr(1)
	
	print("[AssetStreamer] Requesting asset: ", asset_path, " (priority: ", priority, ")")
	
	# Check current state
	var current_state = asset_states.get(asset_path, LoadingState.PENDING)
	
	match current_state:
		LoadingState.READY:
			print("[AssetStreamer] Asset already loaded: ", asset_path)
			call_deferred("_emit_asset_ready", asset_path)
			return
		LoadingState.DOWNLOADING:
			print("[AssetStreamer] Asset already downloading: ", asset_path)
			return
		LoadingState.FAILED:
			print("[AssetStreamer] Retrying failed asset: ", asset_path)
			asset_states[asset_path] = LoadingState.PENDING
		_:
			pass
	
	# Check if we should stream this asset
	if not _should_stream_asset():
		print("[AssetStreamer] Streaming not enabled for this build, loading fallback")
		_load_fallback_asset(asset_path)
		return
	
	# Add to download queue
	var download_info = {
		"asset_path": asset_path,
		"priority": priority,
		"attempts": 0
	}
	
	_queue_download(download_info)

func _should_stream_asset() -> bool:
	"""Determine if we should stream assets based on build type"""
	# Stream on web builds
	if OS.has_feature("web"):
		return true
	
	# Stream on debug builds if simulate_web_in_debug is enabled
	if OS.has_feature("debug"):
		var simulate_web = config.get_value("debug", "simulate_web_in_debug", false)
		return simulate_web
	
	# Don't stream on release builds (use bundled assets)
	return false

func _queue_download(download_info: Dictionary):
	"""Add download to priority queue"""
	var priority_value = _get_priority_value(download_info.priority)
	var insert_index = download_queue.size()
	
	# Insert based on priority
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
	var asset_path = download_info.asset_path
	
	print("[AssetStreamer] Starting download: ", asset_path)
	
	asset_states[asset_path] = LoadingState.DOWNLOADING
	active_downloads[client] = download_info
	
	# Build direct URL: base_url + "/" + asset_path
	var url = base_url + "/" + asset_path
	print("[AssetStreamer] Download URL: ", url)
	
	asset_download_started.emit(asset_path)
	
	var error = client.request(url)
	if error != OK:
		print("[AssetStreamer] Failed to start request for ", asset_path, ": ", error)
		_handle_download_failure(client, "Failed to start HTTP request")
	else:
		print("[AssetStreamer] Request started with timeout: ", request_timeout, "s")

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, client: HTTPRequest):
	"""Handle completed HTTP request"""
	if not active_downloads.has(client):
		print("[AssetStreamer] Warning: Completed request from inactive client")
		return
	
	var download_info = active_downloads[client]
	var asset_path = download_info.asset_path
	
	if response_code == 200:
		print("[AssetStreamer] ✅ Download completed: ", asset_path, " (", body.size(), " bytes)")
		_process_downloaded_asset(asset_path, body)
		asset_download_completed.emit(asset_path, true)
	else:
		var error_msg = "HTTP " + str(response_code)
		if response_code == 0:
			error_msg += " (likely timeout or connection failure)"
		print("[AssetStreamer] ❌ Download failed for ", asset_path, ": ", error_msg)
		_handle_download_failure(client, error_msg)
	
	# Return client to pool and process next download
	active_downloads.erase(client)
	client_pool.append(client)
	_process_download_queue()

func _process_downloaded_asset(asset_path: String, data: PackedByteArray):
	"""Process downloaded asset data into a Godot resource"""
	var extension = asset_path.get_extension().to_lower()
	var resource: Resource = null
	
	match extension:
		"glb", "gltf":
			resource = _load_glb_from_data(data)
		"png", "jpg", "jpeg", "webp":
			resource = _load_image_from_data(data)
		"ogg", "mp3", "wav":
			resource = _load_audio_from_data(data, extension)
		"tscn":
			resource = _load_scene_from_data(data)
		_:
			print("[AssetStreamer] ⚠️ Unsupported file type: ", extension)
			resource = null
	
	if resource:
		asset_resources[asset_path] = resource
		asset_states[asset_path] = LoadingState.READY
		print("[AssetStreamer] ✅ Asset processed: ", asset_path)
		asset_ready.emit(asset_path, resource)
	else:
		print("[AssetStreamer] ❌ Failed to process asset: ", asset_path)
		_load_fallback_asset(asset_path)

func _load_glb_from_data(data: PackedByteArray) -> PackedScene:
	"""Load GLB/GLTF from binary data"""
	# Create temporary file for GLTF processing
	var temp_path = "user://temp_asset.glb"
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		print("[AssetStreamer] Failed to create temp file for GLB")
		return null
	
	file.store_buffer(data)
	file.close()
	
	# Load using GLTF
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var error = gltf.append_from_file(temp_path, state)
	
	# Clean up temp file
	DirAccess.open("user://").remove("temp_asset.glb")
	
	if error == OK:
		var scene_node = gltf.generate_scene(state)
		if scene_node:
			var packed_scene = PackedScene.new()
			packed_scene.pack(scene_node)
			return packed_scene
	
	print("[AssetStreamer] Failed to load GLB from data, error: ", error)
	return null

func _load_image_from_data(data: PackedByteArray) -> ImageTexture:
	"""Load image from binary data"""
	var image = Image.new()
	var error = image.load_from_buffer(data)
	
	if error == OK:
		return ImageTexture.create_from_image(image)
	else:
		print("[AssetStreamer] Failed to load image from data, error: ", error)
		return null

func _load_audio_from_data(data: PackedByteArray, extension: String) -> AudioStream:
	"""Load audio from binary data"""
	match extension:
		"ogg":
			var audio_stream = AudioStreamOggVorbis.new()
			var ogg_packet = OggPacketSequence.new()
			ogg_packet.packet_data = data
			audio_stream.packet_sequence = ogg_packet
			return audio_stream
		"wav":
			var audio_stream = AudioStreamWAV.new()
			audio_stream.data = data
			return audio_stream
		"mp3":
			var audio_stream = AudioStreamMP3.new()
			audio_stream.data = data
			return audio_stream
	
	return null

func _load_scene_from_data(_data: PackedByteArray) -> PackedScene:
	"""Load scene from binary data (for .tscn files)"""
	# This would need more complex parsing - for now return null
	print("[AssetStreamer] Scene loading from data not implemented yet")
	return null

func _load_fallback_asset(asset_path: String):
	"""Load fallback asset when streaming fails"""
	print("[AssetStreamer] Loading fallback for: ", asset_path)
	asset_states[asset_path] = LoadingState.FAILED
	
	var fallback_resource = _create_fallback_resource(asset_path)
	
	if fallback_resource:
		asset_resources[asset_path] = fallback_resource
		asset_failed.emit(asset_path, fallback_resource)
	else:
		streaming_error.emit(asset_path, "No fallback available")

func _create_fallback_resource(asset_path: String) -> Resource:
	"""Create appropriate fallback resource based on file extension"""
	var extension = asset_path.get_extension().to_lower()
	
	match extension:
		"glb", "gltf", "tscn":
			return _create_simple_model_fallback()
		"png", "jpg", "jpeg", "webp":
			return _create_simple_texture_fallback()
		"ogg", "mp3", "wav":
			return _create_simple_audio_fallback()
		_:
			return _create_simple_model_fallback()

func _create_simple_model_fallback() -> PackedScene:
	"""Create a simple model fallback"""
	var scene = PackedScene.new()
	var node = MeshInstance3D.new()
	node.name = "FallbackModel"
	
	# Create a bright magenta box to indicate missing asset
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2, 2, 2)
	node.mesh = box_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 1)  # Bright magenta
	material.emission_enabled = true
	material.emission = Color(1, 0, 1) * 0.3
	node.material_override = material
	
	scene.pack(node)
	return scene

func _create_simple_texture_fallback() -> ImageTexture:
	"""Create a simple texture fallback"""
	var image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color(1, 0, 1))  # Bright magenta
	return ImageTexture.create_from_image(image)

func _create_simple_audio_fallback() -> AudioStream:
	"""Create a simple audio fallback (silence)"""
	var audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 22050
	audio_stream.buffer_length = 1.0
	return audio_stream

func _handle_download_failure(client: HTTPRequest, _error_message: String):
	"""Handle download failure with retry logic"""
	var download_info = active_downloads[client]
	var asset_path = download_info.asset_path
	
	download_info.attempts += 1
	
	if download_info.attempts < retry_attempts:
		print("[AssetStreamer] Retrying download for ", asset_path, " (attempt ", download_info.attempts + 1, "/", retry_attempts, ")")
		download_queue.push_front(download_info)
	else:
		print("[AssetStreamer] Max retry attempts reached for ", asset_path)
		asset_download_completed.emit(asset_path, false)
		_load_fallback_asset(asset_path)
	
	active_downloads.erase(client)
	client_pool.append(client)

func _emit_asset_ready(asset_path: String):
	"""Deferred emit for already loaded assets"""
	if asset_resources.has(asset_path):
		asset_ready.emit(asset_path, asset_resources[asset_path])

# ===== UTILITY METHODS =====

func is_asset_ready(asset_path: String) -> bool:
	"""Check if asset is ready to use"""
	return asset_states.get(asset_path, LoadingState.PENDING) == LoadingState.READY

func get_asset_state(asset_path: String) -> LoadingState:
	"""Get current loading state of asset"""
	return asset_states.get(asset_path, LoadingState.PENDING)

func get_loaded_resource(asset_path: String) -> Resource:
	"""Get loaded resource if available"""
	return asset_resources.get(asset_path, null)

func get_streaming_status() -> Dictionary:
	"""Get detailed streaming status"""
	var ready_count = 0
	var downloading_count = 0
	var failed_count = 0
	
	for state in asset_states.values():
		match state:
			LoadingState.READY:
				ready_count += 1
			LoadingState.DOWNLOADING:
				downloading_count += 1
			LoadingState.FAILED:
				failed_count += 1
	
	return {
		"base_url": base_url,
		"ready_assets": ready_count,
		"downloading_assets": downloading_count,
		"failed_assets": failed_count,
		"active_downloads": active_downloads.size(),
		"download_queue": download_queue.size(),
		"streaming_enabled": _should_stream_asset()
	}

func clear_cache():
	"""Clear all loaded assets"""
	print("[AssetStreamer] Clearing asset cache")
	asset_resources.clear()
	for asset_path in asset_states:
		asset_states[asset_path] = LoadingState.PENDING 

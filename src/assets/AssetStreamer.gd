class_name AssetStreamer
extends Node

## Asset Streaming System for Vocara.world
## Handles downloading, caching, and loading of streaming assets

signal asset_download_started(asset_name: String)
signal asset_download_progress(asset_name: String, progress: float)
signal asset_download_completed(asset_name: String, success: bool)
signal asset_loaded(asset_name: String, resource: Resource)
signal streaming_error(error_message: String)

# Configuration
@export var server_url: String = "http://localhost:8080"
@export var enable_caching: bool = true
@export var cache_size_limit: int = 500 * 1024 * 1024  # 500MB cache limit
@export var max_concurrent_downloads: int = 3
@export var retry_attempts: int = 3
@export var chunk_timeout: float = 30.0

# Internal state
var asset_manifest: Dictionary = {}
var cached_assets: Dictionary = {}
var download_queue: Array = []
var active_downloads: Dictionary = {}
var loaded_resources: Dictionary = {}
var cache_directory: String = "user://asset_cache/"

# HTTP clients for downloading
var http_clients: Array[HTTPRequest] = []
var client_pool: Array[HTTPRequest] = []

func _ready():
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
	
	# Load asset manifest
	load_asset_manifest()

func load_asset_manifest():
	print("[AssetStreamer] Loading asset manifest...")
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_manifest_loaded)
	http.request(server_url + "/assets/manifest")

func _on_manifest_loaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			asset_manifest = json.data
			print("[AssetStreamer] Manifest loaded successfully")
			_validate_cache()
		else:
			print("[AssetStreamer] Failed to parse manifest JSON")
			streaming_error.emit("Failed to parse asset manifest")
	else:
		print("[AssetStreamer] Failed to load manifest: ", response_code)
		streaming_error.emit("Failed to load asset manifest")

func _validate_cache():
	# Check cached assets against manifest version
	var cache_info_path = cache_directory + "cache_info.json"
	if FileAccess.file_exists(cache_info_path):
		var file = FileAccess.open(cache_info_path, FileAccess.READ)
		var cache_info = JSON.parse_string(file.get_as_text())
		file.close()
		
		if cache_info and cache_info.has("version") and cache_info.version != asset_manifest.version:
			print("[AssetStreamer] Cache version mismatch, clearing cache")
			clear_cache()
	
	# Load cached asset index
	_load_cache_index()

func _load_cache_index():
	var cache_index_path = cache_directory + "index.json"
	if FileAccess.file_exists(cache_index_path):
		var file = FileAccess.open(cache_index_path, FileAccess.READ)
		cached_assets = JSON.parse_string(file.get_as_text()) or {}
		file.close()
	else:
		cached_assets = {}

func _save_cache_index():
	var cache_index_path = cache_directory + "index.json"
	var file = FileAccess.open(cache_index_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(cached_assets))
	file.close()
	
	# Save cache info
	var cache_info = {
		"version": asset_manifest.version,
		"last_updated": Time.get_unix_time_from_system()
	}
	var cache_info_path = cache_directory + "cache_info.json"
	file = FileAccess.open(cache_info_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(cache_info))
	file.close()

func request_asset(asset_name: String, priority: String = "medium") -> bool:
	print("[AssetStreamer] Requesting asset: ", asset_name)
	
	# Check if already loaded
	if loaded_resources.has(asset_name):
		asset_loaded.emit(asset_name, loaded_resources[asset_name])
		return true
	
	# Check if cached
	if cached_assets.has(asset_name):
		var cached_path = cache_directory + asset_name
		if FileAccess.file_exists(cached_path):
			_load_cached_asset(asset_name)
			return true
	
	# Add to download queue
	var download_info = {
		"asset_name": asset_name,
		"priority": priority,
		"attempts": 0
	}
	
	# Insert based on priority
	var insert_index = download_queue.size()
	for i in range(download_queue.size()):
		if _get_priority_value(priority) > _get_priority_value(download_queue[i].priority):
			insert_index = i
			break
	
	download_queue.insert(insert_index, download_info)
	_process_download_queue()
	return false

func _get_priority_value(priority: String) -> int:
	match priority:
		"critical": return 3
		"high": return 2
		"medium": return 1
		_: return 0

func _process_download_queue():
	while download_queue.size() > 0 and client_pool.size() > 0:
		var download_info = download_queue.pop_front()
		var client = client_pool.pop_front()
		
		_start_download(download_info, client)

func _start_download(download_info: Dictionary, client: HTTPRequest):
	var asset_name = download_info.asset_name
	print("[AssetStreamer] Starting download: ", asset_name)
	
	active_downloads[client] = download_info
	asset_download_started.emit(asset_name)
	
	# Check if asset should be downloaded in chunks
	var asset_info = _find_asset_info(asset_name)
	if asset_info and asset_info.has("chunks"):
		_download_chunked_asset(asset_name, asset_info, client)
	else:
		_download_full_asset(asset_name, client)

func _download_full_asset(asset_name: String, client: HTTPRequest):
	var url = server_url + "/assets/stream/" + asset_name
	client.request(url)

func _download_chunked_asset(asset_name: String, asset_info: Dictionary, client: HTTPRequest):
	# For now, start with the first chunk
	# This could be expanded to download multiple chunks in parallel
	var chunk_url = server_url + "/assets/chunks/" + asset_name + "/0"
	client.request(chunk_url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var client = null
	for http_client in http_clients:
		if http_client.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			client = http_client
			break
	
	if not client or not active_downloads.has(client):
		return
	
	var download_info = active_downloads[client]
	var asset_name = download_info.asset_name
	
	if response_code == 200:
		# Save asset to cache
		var cache_path = cache_directory + asset_name
		var file = FileAccess.open(cache_path, FileAccess.WRITE)
		file.store_buffer(body)
		file.close()
		
		# Update cache index
		cached_assets[asset_name] = {
			"size": body.size(),
			"downloaded": Time.get_unix_time_from_system()
		}
		_save_cache_index()
		
		# Load the asset
		_load_cached_asset(asset_name)
		
		asset_download_completed.emit(asset_name, true)
		print("[AssetStreamer] Download completed: ", asset_name)
	else:
		print("[AssetStreamer] Download failed: ", asset_name, " - ", response_code)
		download_info.attempts += 1
		
		if download_info.attempts < retry_attempts:
			# Retry download
			download_queue.push_front(download_info)
		else:
			asset_download_completed.emit(asset_name, false)
			streaming_error.emit("Failed to download asset: " + asset_name)
	
	# Return client to pool
	active_downloads.erase(client)
	client_pool.append(client)
	
	# Process next download
	_process_download_queue()

func _load_cached_asset(asset_name: String):
	var cache_path = cache_directory + asset_name
	var extension = asset_name.get_extension().to_lower()
	
	match extension:
		"glb":
			var gltf = GLTFDocument.new()
			var state = GLTFState.new()
			var error = gltf.append_from_file(cache_path, state)
			if error == OK:
				var scene = gltf.generate_scene(state)
				loaded_resources[asset_name] = scene
				asset_loaded.emit(asset_name, scene)
			else:
				print("[AssetStreamer] Failed to load GLB: ", asset_name)
		"png", "jpg", "jpeg", "webp":
			var image = Image.new()
			var error = image.load(cache_path)
			if error == OK:
				var texture = ImageTexture.create_from_image(image)
				loaded_resources[asset_name] = texture
				asset_loaded.emit(asset_name, texture)
			else:
				print("[AssetStreamer] Failed to load image: ", asset_name)
		_:
			print("[AssetStreamer] Unsupported asset type: ", extension)

func _find_asset_info(asset_name: String) -> Dictionary:
	# Search through manifest for asset info
	for category in asset_manifest.streaming_assets:
		for asset in asset_manifest.streaming_assets[category]:
			if asset.name == asset_name:
				return asset
	return {}

func clear_cache():
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
	
	cached_assets.clear()
	loaded_resources.clear()
	_save_cache_index()

func get_cache_size() -> int:
	var total_size = 0
	for asset_name in cached_assets:
		total_size += cached_assets[asset_name].size
	return total_size

func is_asset_cached(asset_name: String) -> bool:
	return cached_assets.has(asset_name) and FileAccess.file_exists(cache_directory + asset_name)

func is_asset_loaded(asset_name: String) -> bool:
	return loaded_resources.has(asset_name)

func get_download_progress(asset_name: String) -> float:
	# This would need to be implemented with proper progress tracking
	return 0.0

func preload_critical_assets():
	print("[AssetStreamer] Preloading critical assets")
	if asset_manifest.has("streaming_assets"):
		for category in asset_manifest.streaming_assets:
			for asset in asset_manifest.streaming_assets[category]:
				if asset.priority == "critical":
					request_asset(asset.name, "critical") 
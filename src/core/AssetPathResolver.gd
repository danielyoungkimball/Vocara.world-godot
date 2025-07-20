class_name AssetPathResolver
extends RefCounted

## Asset Path Resolver
## Ensures perfect path consistency between Godot client and backend server
## Handles manifest lookups, path validation, and asset resolution

enum AssetType {
	MODEL,
	TEXTURE, 
	AUDIO,
	UNKNOWN
}

enum LoadStrategy {
	BUNDLED,    # Load from res:// (included in build)
	STREAMED,   # Download and cache in user://
	HYBRID      # Check res:// first, fallback to streaming
}

class AssetInfo:
	var name: String
	var relative_path: String  # Path used for backend requests
	var local_cache_path: String  # Full path in user://asset_cache/
	var res_path: String # Original res:// path if it exists
	var asset_type: AssetType
	var load_strategy: LoadStrategy
	var size: int
	var priority: String
	var chunks: Array = []
	var fallback_path: String
	
	func _init(asset_name: String = "", rel_path: String = ""):
		name = asset_name
		relative_path = rel_path
		local_cache_path = "user://asset_cache/" + rel_path if not rel_path.is_empty() else ""

var manifest: Dictionary = {}
var logger_prefix: String = "[AssetPathResolver]"

func _init():
	pass

func set_manifest(asset_manifest: Dictionary):
	"""Set the asset manifest from the server"""
	manifest = asset_manifest
	print(logger_prefix, " Manifest loaded with ", _count_total_assets(), " assets")

func resolve_asset(asset_identifier: String) -> AssetInfo:
	"""
	Resolve an asset identifier to complete AssetInfo
	Supports multiple identifier formats:
	- Full relative path: "models/environment/floating_island.glb"
	- Asset name: "floating_island.glb" 
	- res:// path: "res://assets/models/environment/floating_island.glb"
	"""
	var info = AssetInfo.new()
	
	# Normalize the identifier
	var normalized_id = _normalize_identifier(asset_identifier)
	
	# Try to find in manifest
	var manifest_entry = _find_in_manifest(normalized_id)
	
	if manifest_entry.is_empty():
		# Asset not found in manifest - check if it's a bundled asset
		info = _resolve_bundled_asset(asset_identifier)
		if info.relative_path.is_empty():
			# Completely unknown asset
			info = _create_unknown_asset_info(asset_identifier)
	else:
		# Found in manifest - create streaming asset info
		info = _create_streaming_asset_info(manifest_entry, normalized_id)
	
	_validate_asset_info(info)
	return info

func _normalize_identifier(identifier: String) -> String:
	"""Normalize various asset identifier formats to consistent relative path"""
	var normalized = identifier
	
	# Remove res:// prefix if present
	if normalized.begins_with("res://"):
		normalized = normalized.substr(6)  # Remove "res://"
	
	# Remove assets/ prefix if present (common in res:// paths)
	if normalized.begins_with("assets/"):
		normalized = normalized.substr(7)  # Remove "assets/"
	
	# Ensure forward slashes (cross-platform compatibility)
	normalized = normalized.replace("\\", "/")
	
	return normalized

func _find_in_manifest(asset_path: String) -> Dictionary:
	"""Find asset entry in manifest by various lookup methods"""
	var filename = asset_path.get_file()
	
	# Method 1: Direct path lookup
	var direct_match = _find_by_path(asset_path)
	if not direct_match.is_empty():
		return direct_match
	
	# Method 2: Filename lookup (for backward compatibility)
	var filename_match = _find_by_filename(filename)
	if not filename_match.is_empty():
		return filename_match
	
	# Method 3: Fuzzy path matching (handles minor path differences)
	var fuzzy_match = _find_by_fuzzy_path(asset_path)
	return fuzzy_match

func _find_by_path(asset_path: String) -> Dictionary:
	"""Find asset by exact relative path match"""
	for category_name in ["streaming_assets", "core_assets"]:
		if not manifest.has(category_name):
			continue
			
		var category = manifest[category_name]
		for type_name in category:
			if not category[type_name] is Array:
				continue
				
			for asset in category[type_name]:
				if asset.has("path") and asset.path == asset_path:
					return asset
	
	return {}

func _find_by_filename(filename: String) -> Dictionary:
	"""Find asset by filename (less reliable, used as fallback)"""
	for category_name in ["streaming_assets", "core_assets"]:
		if not manifest.has(category_name):
			continue
			
		var category = manifest[category_name]
		for type_name in category:
			if not category[type_name] is Array:
				continue
				
			for asset in category[type_name]:
				var asset_filename = ""
				if asset.has("path"):
					asset_filename = asset.path.get_file()
				elif asset.has("name"):
					asset_filename = asset.name
				
				if asset_filename == filename:
					print(logger_prefix, " Found asset by filename: ", filename, " -> ", asset.get("path", asset.get("name", "")))
					return asset
	
	return {}

func _find_by_fuzzy_path(asset_path: String) -> Dictionary:
	"""Find asset using fuzzy path matching for minor variations"""
	var path_parts = asset_path.split("/")
	var filename = path_parts[-1]
	
	for category_name in ["streaming_assets", "core_assets"]:
		if not manifest.has(category_name):
			continue
			
		var category = manifest[category_name]
		for type_name in category:
			if not category[type_name] is Array:
				continue
				
			for asset in category[type_name]:
				if not asset.has("path"):
					continue
					
				var manifest_path = asset.path
				var manifest_parts = manifest_path.split("/")
				var manifest_filename = manifest_parts[-1]
				
				# If filenames match and paths are similar
				if manifest_filename == filename:
					var similarity = _calculate_path_similarity(asset_path, manifest_path)
					if similarity > 0.7:  # 70% similarity threshold
						print(logger_prefix, " Fuzzy match found: ", asset_path, " -> ", manifest_path)
						return asset
	
	return {}

func _calculate_path_similarity(path1: String, path2: String) -> float:
	"""Calculate similarity between two paths (0.0 to 1.0)"""
	var parts1 = path1.split("/")
	var parts2 = path2.split("/")
	
	var matches = 0
	var total_parts = max(parts1.size(), parts2.size())
	
	for i in range(min(parts1.size(), parts2.size())):
		if parts1[i] == parts2[i]:
			matches += 1
	
	return float(matches) / float(total_parts) if total_parts > 0 else 0.0

func _resolve_bundled_asset(asset_identifier: String) -> AssetInfo:
	"""Resolve asset as a bundled (res://) asset"""
	var info = AssetInfo.new()
	
	var res_path = asset_identifier
	if not res_path.begins_with("res://"):
		res_path = "res://assets/" + asset_identifier
	
	# Check if the resource actually exists
	if ResourceLoader.exists(res_path):
		info.name = res_path.get_file()
		info.res_path = res_path
		info.relative_path = _normalize_identifier(asset_identifier)
		info.asset_type = _detect_asset_type(info.name)
		info.load_strategy = LoadStrategy.BUNDLED
		info.priority = "bundled"
		
		print(logger_prefix, " Resolved as bundled asset: ", res_path)
	
	return info

func _create_streaming_asset_info(manifest_entry: Dictionary, normalized_path: String) -> AssetInfo:
	"""Create AssetInfo for a streaming asset from manifest entry"""
	var info = AssetInfo.new()
	
	info.name = manifest_entry.get("name", normalized_path.get_file())
	info.relative_path = manifest_entry.get("path", normalized_path)
	info.local_cache_path = "user://asset_cache/" + info.relative_path
	info.asset_type = _detect_asset_type(info.name)
	info.load_strategy = LoadStrategy.STREAMED
	info.size = manifest_entry.get("size", 0)
	info.priority = manifest_entry.get("priority", "medium")
	info.chunks = manifest_entry.get("chunks", [])
	
	# Set up fallback path
	info.fallback_path = _get_fallback_path(info.asset_type)
	
	print(logger_prefix, " Resolved as streaming asset: ", info.relative_path)
	return info

func _create_unknown_asset_info(asset_identifier: String) -> AssetInfo:
	"""Create AssetInfo for an unknown/missing asset"""
	var info = AssetInfo.new()
	
	info.name = asset_identifier.get_file()
	info.relative_path = _normalize_identifier(asset_identifier)
	info.asset_type = _detect_asset_type(info.name)
	info.load_strategy = LoadStrategy.HYBRID
	info.priority = "unknown"
	info.fallback_path = _get_fallback_path(info.asset_type)
	
	print(logger_prefix, " WARN: Unknown asset: ", asset_identifier, " -> fallback will be used")
	return info

func _detect_asset_type(filename: String) -> AssetType:
	"""Detect asset type from filename extension"""
	var ext = filename.get_extension().to_lower()
	
	match ext:
		"glb", "gltf":
			return AssetType.MODEL
		"png", "jpg", "jpeg", "webp", "bmp", "tga":
			return AssetType.TEXTURE
		"ogg", "mp3", "wav", "m4a":
			return AssetType.AUDIO
		_:
			return AssetType.UNKNOWN

func _get_fallback_path(asset_type: AssetType) -> String:
	"""Get fallback resource path for asset type"""
	match asset_type:
		AssetType.MODEL:
			return "res://src/assets/fallbacks/missing_model.tscn"
		AssetType.TEXTURE:
			return "res://src/assets/fallbacks/missing_texture.png"
		AssetType.AUDIO:
			return "res://src/assets/fallbacks/missing_audio.ogg"
		_:
			return ""

func _validate_asset_info(info: AssetInfo):
	"""Validate and potentially fix AssetInfo"""
	if info.relative_path.is_empty():
		print(logger_prefix, " ERROR: Empty relative path for asset: ", info.name)
	
	if info.local_cache_path.is_empty() and info.load_strategy == LoadStrategy.STREAMED:
		info.local_cache_path = "user://asset_cache/" + info.relative_path
		print(logger_prefix, " Fixed missing cache path: ", info.local_cache_path)
	
	if info.asset_type == AssetType.UNKNOWN:
		print(logger_prefix, " WARN: Unknown asset type for: ", info.name)

func _count_total_assets() -> int:
	"""Count total assets in manifest"""
	var count = 0
	
	for category_name in ["streaming_assets", "core_assets"]:
		if not manifest.has(category_name):
			continue
			
		var category = manifest[category_name]
		for type_name in category:
			if category[type_name] is Array:
				count += category[type_name].size()
	
	return count

# Utility functions for external use

func get_stream_url(asset_info: AssetInfo, server_url: String = "") -> String:
	"""Get streaming URL for asset"""
	var base_url = server_url if not server_url.is_empty() else "http://localhost:8080"
	return base_url + "/assets/stream/" + asset_info.relative_path

func get_chunk_url(asset_info: AssetInfo, chunk_index: int, server_url: String = "") -> String:
	"""Get chunk URL for asset"""
	var base_url = server_url if not server_url.is_empty() else "http://localhost:8080"
	return base_url + "/assets/chunks/" + asset_info.relative_path + "/" + str(chunk_index)

func is_cached(asset_info: AssetInfo) -> bool:
	"""Check if asset is cached locally"""
	return FileAccess.file_exists(asset_info.local_cache_path)

func get_cache_path(asset_info: AssetInfo) -> String:
	"""Get local cache path for asset"""
	return asset_info.local_cache_path 
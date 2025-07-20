extends Node
## Environment Configuration Loader  
## Loads fresh config every time to avoid caching issues

var _generated_config

func _ready():
	_load_fresh_config()

func _load_fresh_config():
	"""Load the generated config fresh each time"""
	# Check if we're in a release build - if so, FORCE production settings
	var is_release_build = OS.has_feature("release") or OS.has_feature("web")
	
	if is_release_build:
		print("[environment.gd] 🚀 RELEASE BUILD detected - forcing PRODUCTION environment")
		_generated_config = _create_production_config()
		print("  🌐 Server: ", _generated_config.get_server_url())
		print("  🏠 Environment: ", _generated_config.get_environment())
		print("  📅 Forced for release build")
		return
	
	# Development/editor mode - load from generated file
	var generated_script = ResourceLoader.load("res://src/config/environment_generated.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	
	if generated_script:
		_generated_config = generated_script.new()
		print("[environment.gd] Fresh config loaded with CACHE_MODE_IGNORE:")
		print("  🌐 Server: ", _generated_config.get_server_url())
		print("  🏠 Environment: ", _generated_config.get_environment())
		print("  📅 Timestamp: ", Time.get_datetime_string_from_system())
	else:
		push_error("[environment.gd] Generated config not found! Use the editor plugin to generate it.")
		# Set fallback values
		_generated_config = null

func get_server_url() -> String:
	if _generated_config:
		return _generated_config.get_server_url()
	return "http://localhost:8080"  # Fallback

func get_multiplayer_url() -> String:
	if _generated_config:
		return _generated_config.get_multiplayer_url()
	return "ws://localhost:8080"  # Fallback

func get_asset_base_url() -> String:
	if _generated_config:
		return _generated_config.get_asset_base_url()
	return "http://localhost:8080/api/assets"  # Fallback

func get_r2_cdn_url() -> String:
	if _generated_config:
		return _generated_config.get_r2_cdn_url()
	return "https://assets.vocara-multiplayer.com"  # Fallback

func is_debug_enabled() -> bool:
	if _generated_config:
		return _generated_config.is_debug_enabled()
	return true  # Fallback

func get_environment() -> String:
	if _generated_config:
		return _generated_config.get_environment()
	return "development"  # Fallback

func is_development() -> bool:
	if _generated_config:
		return _generated_config.is_development()
	return true  # Fallback

func is_production() -> bool:
	if _generated_config:
		return _generated_config.is_production()
	return false  # Fallback

func _create_production_config():
	"""Create a hardcoded production config for release builds"""
	var ProductionConfig = RefCounted.new()
	
	# Add methods to mimic the generated config structure
	ProductionConfig.get_server_url = func(): return "https://vocara-multiplayer.com"
	ProductionConfig.get_multiplayer_url = func(): return "wss://vocara-multiplayer.com"
	ProductionConfig.get_asset_base_url = func(): return "https://vocara-multiplayer.com/api/assets"
	ProductionConfig.get_r2_cdn_url = func(): return "https://assets.vocara-multiplayer.com"
	ProductionConfig.is_debug_enabled = func(): return false
	ProductionConfig.get_environment = func(): return "production"
	ProductionConfig.is_development = func(): return false
	ProductionConfig.is_production = func(): return true
	
	return ProductionConfig

extends Node
## Consolidated Environment Configuration
## Handles both editor preferences and production forcing for release builds

const ENVIRONMENT_PREF_PATH = "user://environment.cfg"

func _ready():
	var env_info = _get_environment_info()
	print("[Environment] 🌍 Environment: ", env_info.environment, " (", env_info.reason, ")")
	print("  🌐 Server: ", get_server_url())
	print("  🔌 Multiplayer: ", get_multiplayer_url())
	print("  📦 Assets: ", get_asset_base_url())

func _get_environment_info() -> Dictionary:
	"""Get current environment and why it was selected"""
	# CRITICAL: Force production for any release build
	var is_release_build = OS.has_feature("release") or OS.has_feature("web")
	
	if is_release_build:
		return {
			"environment": "production",
			"reason": "release build (forced)"
		}
	
	# Development/editor mode - read preference file
	var config = ConfigFile.new()
	if config.load(ENVIRONMENT_PREF_PATH) == OK:
		var env = config.get_value("environment", "current", "development")
		return {
			"environment": env,
			"reason": "editor preference"
		}
	
	return {
		"environment": "development",
		"reason": "default fallback"
	}

func get_environment() -> String:
	return _get_environment_info().environment

func is_development() -> bool:
	return get_environment() == "development"

func is_production() -> bool:
	return get_environment() == "production"

func is_debug_enabled() -> bool:
	return is_development()

func get_server_url() -> String:
	if is_production():
		return "https://vocara-multiplayer.com"
	return "http://localhost:8080"

func get_multiplayer_url() -> String:
	if is_production():
		return "wss://vocara-multiplayer.com"
	return "ws://localhost:8080"

func get_asset_base_url() -> String:
	if is_production():
		return "https://assets.vocara-multiplayer.com"
	return "http://localhost:8080/api/assets"

func get_r2_cdn_url() -> String:
	# Always use the production CDN URL
	return "https://assets.vocara-multiplayer.com"

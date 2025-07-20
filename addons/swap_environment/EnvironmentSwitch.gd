@tool
extends EditorPlugin

const ENVIRONMENT_CONFIG_PATH = "res://src/config/environment_generated.gd"

var dock_ui
var toolbar_button: Button

func _enter_tree():
	print("[EnvironmentPlugin] Activating environment switcher plugin")
	
	# Ensure the generated config exists with default development settings
	if not FileAccess.file_exists(ENVIRONMENT_CONFIG_PATH):
		_set_environment("development")
	
	# Create toolbar button
	toolbar_button = Button.new()
	toolbar_button.text = "Dev"
	toolbar_button.modulate = Color.GREEN
	toolbar_button.pressed.connect(_on_toggle_environment)
	toolbar_button.custom_minimum_size = Vector2(60, 24)
	
	# Add to main screen toolbar (this should appear immediately in editor)
	add_control_to_container(CONTAINER_TOOLBAR, toolbar_button)
	
	# Update button state
	call_deferred("_update_button_state")  # Defer to ensure proper initialization

func _exit_tree():
	print("[EnvironmentPlugin] Deactivating environment switcher plugin")
	
	if toolbar_button:
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar_button)
		toolbar_button.queue_free()
		toolbar_button = null

func _on_toggle_environment():
	var current_env = _get_current_environment()
	var new_env = "production" if current_env == "development" else "development"
	
	print("\n[EnvironmentPlugin] 🔄 Environment Switch Debug Info")
	print("=====================================")
	
	# Show current environment URLs
	var current_urls = _get_environment_urls(current_env)
	print("📍 CURRENT Environment (", current_env, "):")
	print("  🌐 Server URL: ", current_urls.server_url)
	print("  🔌 Multiplayer URL: ", current_urls.multiplayer_url)
	print("  📦 Asset Base URL: ", current_urls.asset_base_url)
	print("  ☁️  R2 CDN URL: ", current_urls.r2_cdn_url)
	
	# Show new environment URLs
	var new_urls = _get_environment_urls(new_env)
	print("🎯 NEW Environment (", new_env, "):")
	print("  🌐 Server URL: ", new_urls.server_url)
	print("  🔌 Multiplayer URL: ", new_urls.multiplayer_url)
	print("  📦 Asset Base URL: ", new_urls.asset_base_url)
	print("  ☁️  R2 CDN URL: ", new_urls.r2_cdn_url)
	
	print("=====================================")
	print("[EnvironmentPlugin] 🔄 Applying switch from ", current_env, " to ", new_env)
	
	_set_environment(new_env)
	_update_button_state()
	
	print("[EnvironmentPlugin] ✅ Environment switched to ", new_env)
	print("🎮 Run the game to use these URLs!\n")

func _get_current_environment() -> String:
	var file = FileAccess.open(ENVIRONMENT_CONFIG_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		if "localhost" in content:
			return "development"
		else:
			return "production"
	return "development"  # default

func _get_environment_urls(env: String) -> Dictionary:
	"""Get all URLs for a given environment without actually setting it"""
	var server_url: String
	var multiplayer_url: String
	var asset_base_url: String
	var r2_cdn_url = "https://assets.vocara-multiplayer.com"
	
	if env == "development":
		server_url = "http://localhost:8080"
		multiplayer_url = "ws://localhost:8080"
		asset_base_url = "http://localhost:8080/api/assets"
	else:  # production
		server_url = "https://vocara-multiplayer.com"
		multiplayer_url = "wss://vocara-multiplayer.com"  
		asset_base_url = "https://vocara-multiplayer.com/api/assets"
	
	return {
		"server_url": server_url,
		"multiplayer_url": multiplayer_url,
		"asset_base_url": asset_base_url,
		"r2_cdn_url": r2_cdn_url
	}

func _set_environment(env: String):
	var server_url: String
	var multiplayer_url: String
	var asset_base_url: String
	var r2_cdn_url = "https://assets.vocara-multiplayer.com"
	var debug_enabled: bool
	
	if env == "development":
		server_url = "http://localhost:8080"
		multiplayer_url = "ws://localhost:8080"
		asset_base_url = "http://localhost:8080/api/assets"
		debug_enabled = true
	else:  # production
		server_url = "https://vocara-multiplayer.com"
		multiplayer_url = "wss://vocara-multiplayer.com"  
		asset_base_url = "https://vocara-multiplayer.com/api/assets"
		debug_enabled = false
	
	var config_content = """# Auto-generated environment configuration
# Environment: %s
# Generated: %s

extends Node
## Static environment configuration

const SERVER_URL = "%s"
const MULTIPLAYER_URL = "%s" 
const ASSET_BASE_URL = "%s"
const R2_CDN_URL = "%s"
const DEBUG_ENABLED = %s
const ENVIRONMENT = "%s"

func get_server_url() -> String:
	return SERVER_URL

func get_multiplayer_url() -> String:
	return MULTIPLAYER_URL

func get_asset_base_url() -> String:
	return ASSET_BASE_URL

func get_r2_cdn_url() -> String:
	return R2_CDN_URL

func is_debug_enabled() -> bool:
	return DEBUG_ENABLED

func get_environment() -> String:
	return ENVIRONMENT

func is_development() -> bool:
	return ENVIRONMENT == "development"

func is_production() -> bool:
	return ENVIRONMENT == "production"
""" % [
		env.capitalize(),
		Time.get_datetime_string_from_system(),
		server_url,
		multiplayer_url,
		asset_base_url,
		r2_cdn_url,
		debug_enabled,
		env
	]
	
	var file = FileAccess.open(ENVIRONMENT_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(config_content)
		file.close()
		print("[EnvironmentPlugin] Generated config for: ", env)
		print("  🌐 Server: ", server_url)
		
		# Don't trigger reimport during runtime to avoid import errors
		# Config will be loaded fresh on next game run
	else:
		push_error("Failed to write environment config!")

func _update_button_state():
	if not toolbar_button:
		print("[EnvironmentPlugin] ERROR: Toolbar button not found!")
		return
		
	var env = _get_current_environment()
	if env == "development":
		toolbar_button.text = "🟢 Dev"
		toolbar_button.modulate = Color.WHITE
		toolbar_button.tooltip_text = "Environment: Development (localhost:8080)\nClick to switch to Production"
	else:
		toolbar_button.text = "🔴 Prod"
		toolbar_button.modulate = Color.WHITE  
		toolbar_button.tooltip_text = "Environment: Production (vocara-multiplayer.com)\nClick to switch to Development"
		
	print("[EnvironmentPlugin] Button updated: ", toolbar_button.text)

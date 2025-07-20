@tool
extends EditorPlugin

const ENVIRONMENT_PREF_PATH = "user://environment.cfg"

var toolbar_button: Button

func _enter_tree():
	print("[EnvironmentPlugin] Activating environment switcher plugin")
	
	# Ensure preference file exists with default development setting
	if not FileAccess.file_exists(ENVIRONMENT_PREF_PATH):
		_set_environment_preference("development")
	
	# Create toolbar button
	toolbar_button = Button.new()
	toolbar_button.text = "Dev"
	toolbar_button.modulate = Color.GREEN
	toolbar_button.pressed.connect(_on_toggle_environment)
	toolbar_button.custom_minimum_size = Vector2(60, 24)
	
	# Add to main screen toolbar
	add_control_to_container(CONTAINER_TOOLBAR, toolbar_button)
	
	# Update button state
	call_deferred("_update_button_state")

func _exit_tree():
	print("[EnvironmentPlugin] Deactivating environment switcher plugin")
	
	if toolbar_button:
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar_button)
		toolbar_button.queue_free()
		toolbar_button = null

func _on_toggle_environment():
	var current_env = _get_current_environment_preference()
	var new_env = "production" if current_env == "development" else "development"
	
	print("\n[EnvironmentPlugin] 🔄 Environment Switch Debug Info")
	print("=====================================")
	
	# Show current and new environment URLs
	var current_urls = _get_environment_urls(current_env)
	var new_urls = _get_environment_urls(new_env)
	
	print("📍 CURRENT Environment (", current_env, "):")
	print("  🌐 Server URL: ", current_urls.server_url)
	print("  🔌 Multiplayer URL: ", current_urls.multiplayer_url)
	print("  📦 Asset Base URL: ", current_urls.asset_base_url)
	
	print("🎯 NEW Environment (", new_env, "):")
	print("  🌐 Server URL: ", new_urls.server_url)
	print("  🔌 Multiplayer URL: ", new_urls.multiplayer_url)
	print("  📦 Asset Base URL: ", new_urls.asset_base_url)
	
	print("=====================================")
	print("[EnvironmentPlugin] 🔄 Applying switch from ", current_env, " to ", new_env)
	
	_set_environment_preference(new_env)
	_update_button_state()
	
	print("[EnvironmentPlugin] ✅ Environment switched to ", new_env)
	print("🎮 Run the game to use these URLs!\n")

func _get_current_environment_preference() -> String:
	var config = ConfigFile.new()
	if config.load(ENVIRONMENT_PREF_PATH) == OK:
		return config.get_value("environment", "current", "development")
	return "development"

func _set_environment_preference(env: String):
	var config = ConfigFile.new()
	config.set_value("environment", "current", env)
	config.set_value("environment", "last_updated", Time.get_datetime_string_from_system())
	config.save(ENVIRONMENT_PREF_PATH)
	print("[EnvironmentPlugin] Environment preference set to: ", env)

func _get_environment_urls(env: String) -> Dictionary:
	"""Get all URLs for a given environment"""
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
		asset_base_url = "https://assets.vocara-multiplayer.com"
	
	return {
		"server_url": server_url,
		"multiplayer_url": multiplayer_url,
		"asset_base_url": asset_base_url,
		"r2_cdn_url": r2_cdn_url
	}

func _update_button_state():
	if not toolbar_button:
		print("[EnvironmentPlugin] ERROR: Toolbar button not found!")
		return
		
	var env = _get_current_environment_preference()
	if env == "development":
		toolbar_button.text = "🟢 Dev"
		toolbar_button.modulate = Color.WHITE
		toolbar_button.tooltip_text = "Environment: Development (localhost:8080)\nClick to switch to Production"
	else:
		toolbar_button.text = "🔴 Prod"
		toolbar_button.modulate = Color.WHITE
		toolbar_button.tooltip_text = "Environment: Production (vocara-multiplayer.com)\nClick to switch to Development"
		
	print("[EnvironmentPlugin] Button updated: ", toolbar_button.text)

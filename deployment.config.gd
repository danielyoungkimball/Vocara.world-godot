# Vocara.world Game Client Deployment Configuration
# Generates environment-specific configuration for Godot builds

class_name DeploymentConfig
extends RefCounted

# Environment configurations
static var environments = {
	"development": {
		"name": "Development",
		"server_url": "http://localhost:8080",
		"multiplayer_url": "http://localhost:8081", 
		"asset_base_url": "http://localhost:8080/assets",
		"debug_enabled": true,
		"export_preset": "Web (Debug)",
		"features": {
			"multiplayer": false,
			"analytics": false,
			"error_reporting": false
		}
	},
	"staging": {
		"name": "Staging",
		"server_url": "https://staging-api.vocara.world",
		"multiplayer_url": "https://staging-multiplayer.vocara-multiplayer.com",
		"asset_base_url": "https://staging-assets.vocara.world", 
		"debug_enabled": true,
		"export_preset": "Web (Debug)",
		"features": {
			"multiplayer": true,
			"analytics": true,
			"error_reporting": true
		}
	},
	"production": {
		"name": "Production", 
		"server_url": "https://api.vocara.world",
		"multiplayer_url": "https://multiplayer.vocara-multiplayer.com",
		"asset_base_url": "https://assets.vocara.world",
		"debug_enabled": false,
		"export_preset": "Web (Production)",
		"features": {
			"multiplayer": true,
			"analytics": true,
			"error_reporting": true
		}
	}
}

# Generate environment configuration file
static func generate_config(environment: String) -> bool:
	if not environments.has(environment):
		print("Error: Environment '%s' not found" % environment)
		return false
	
	var config = environments[environment]
	var build_id = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	
	var config_content = """# Auto-generated environment configuration
# Environment: %s
# Build ID: %s
# Generated: %s

class_name EnvironmentConfig
extends RefCounted

const SERVER_URL = "%s"
const MULTIPLAYER_URL = "%s" 
const ASSET_BASE_URL = "%s"
const DEBUG_ENABLED = %s
const ENVIRONMENT = "%s"
const BUILD_ID = "%s"

static func get_server_url() -> String:
	return SERVER_URL

static func get_multiplayer_url() -> String:
	return MULTIPLAYER_URL

static func get_asset_base_url() -> String:
	return ASSET_BASE_URL

static func is_debug_enabled() -> bool:
	return DEBUG_ENABLED

static func get_environment() -> String:
	return ENVIRONMENT

static func get_build_id() -> String:
	return BUILD_ID

static func get_features() -> Dictionary:
	return %s
""" % [
		config.name,
		build_id,
		Time.get_datetime_string_from_system(),
		config.server_url,
		config.multiplayer_url,
		config.asset_base_url,
		config.debug_enabled,
		environment,
		build_id,
		var_to_str(config.features)
	]
	
	# Ensure config directory exists
	if not DirAccess.dir_exists_absolute("res://src/config/"):
		DirAccess.open("res://").make_dir_recursive("src/config")
	
	# Write configuration file
	var file = FileAccess.open("res://src/config/environment.gd", FileAccess.WRITE)
	if file:
		file.store_string(config_content)
		file.close()
		print("✅ Generated environment config for: %s" % config.name)
		print("🌐 Server URL: %s" % config.server_url)
		print("📦 Asset URL: %s" % config.asset_base_url)
		print("🔧 Export preset: %s" % config.export_preset)
		return true
	else:
		print("Error: Could not write environment config file")
		return false

# CLI usage for build scripts
static func main():
	var args = OS.get_cmdline_args()
	var environment = "development"
	
	# Look for environment argument
	for i in range(args.size()):
		if args[i] == "--env" and i + 1 < args.size():
			environment = args[i + 1]
			break
	
	generate_config(environment) 
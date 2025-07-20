# Auto-generated environment configuration
# Environment: Development
# Generated: 2025-07-20T00:41:08

extends Node
## Static environment configuration

const SERVER_URL = "http://localhost:8080"
const MULTIPLAYER_URL = "ws://localhost:8080" 
const ASSET_BASE_URL = "http://localhost:8080/api/assets"
const R2_CDN_URL = "https://assets.vocara-multiplayer.com"
const DEBUG_ENABLED = true
const ENVIRONMENT = "development"

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

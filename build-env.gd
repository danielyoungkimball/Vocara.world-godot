#!/usr/bin/env -S godot --headless --script
# Vocara.world Environment Builder
# Usage: godot --headless --script build-env.gd -- development
# Usage: godot --headless --script build-env.gd -- production  
# Usage: godot --headless --script build-env.gd -- staging

extends SceneTree

func _init():
	print("🎮 Vocara.world Environment Configuration Builder")
	print("================================================")
	
	var args = OS.get_cmdline_user_args()
	var environment = "development"  # default
	
	if args.size() > 0:
		environment = args[0]
	
	print("🌐 Building configuration for: ", environment)
	
	# Load the deployment config
	var deployment_script = load("res://deployment.config.gd")
	if not deployment_script:
		print("❌ Error: Could not load deployment.config.gd")
		quit(1)
		return
	
	var deployment_config = deployment_script.new()
	var success = deployment_config.generate_config(environment)
	
	if success:
		print("✅ Environment configuration generated successfully!")
		print("📁 File: res://src/config/environment.gd")
		print("")
		print("🚀 Next steps:")
		if environment == "development":
			print("   1. Start your local server: npm start")
			print("   2. Run Godot project for testing")
		else:
			print("   1. Export using '%s' preset" % deployment_config.environments[environment]["export_preset"])
			print("   2. Deploy to production server")
		print("")
		quit(0)
	else:
		print("❌ Failed to generate environment configuration")
		quit(1)

func _ready():
	# This won't be called in headless mode, but just in case
	pass 
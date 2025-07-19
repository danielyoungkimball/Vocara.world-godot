extends Node

## Test script for verifying the asset streaming system
## Run this to check if AssetStreamer and GlobalAssetManager are working correctly

func _ready():
	print("🧪 Asset Streaming System Test")
	print("===============================")
	
	# Wait a frame for scene tree to initialize
	await get_tree().process_frame
	
	# Test 1: Check if AssetStreamer exists
	test_asset_streamer_existence()
	
	# Test 2: Check if GlobalAssetManager can find AssetStreamer
	test_global_asset_manager()
	
	# Test 3: Check streaming groups
	test_streaming_groups()
	
	# Test 4: Test asset request
	await test_asset_request()

func test_asset_streamer_existence():
	print("\n📦 Test 1: AssetStreamer Existence")
	
	var asset_streamer = get_node_or_null("/root/Main/AssetStreamer")
	if asset_streamer:
		print("✅ AssetStreamer found at: ", asset_streamer.get_path())
		print("✅ AssetStreamer class: ", asset_streamer.get_class())
		print("✅ AssetStreamer script: ", asset_streamer.get_script())
	else:
		print("❌ AssetStreamer NOT found!")
		
		# Try to find it anywhere in the tree
		var streamers = get_tree().get_nodes_in_group("asset_streamer")
		if streamers.size() > 0:
			print("🔍 Found AssetStreamer in group: ", streamers[0].get_path())
		else:
			print("🔍 No AssetStreamer found in any group")

func test_global_asset_manager():
	print("\n🌐 Test 2: GlobalAssetManager")
	
	var global_manager = get_node_or_null("/root/Main/GlobalAssetManager")
	if global_manager:
		print("✅ GlobalAssetManager found at: ", global_manager.get_path())
		
		# Check if it can find AssetStreamer
		var asset_streamer = global_manager.get_node_or_null("../AssetStreamer")
		if asset_streamer:
			print("✅ GlobalAssetManager can find AssetStreamer")
		else:
			print("❌ GlobalAssetManager cannot find AssetStreamer!")
	else:
		print("❌ GlobalAssetManager NOT found!")

func test_streaming_groups():
	print("\n🏷️ Test 3: Streaming Groups")
	
	var streaming_nodes = get_tree().get_nodes_in_group("large_asset_stream")
	print("📊 Found ", streaming_nodes.size(), " nodes in large_asset_stream group:")
	
	for node in streaming_nodes:
		var asset_path = node.get_meta("asset_path", "")
		print("  - ", node.name, " -> ", asset_path)
		
		if asset_path.is_empty():
			print("    ❌ Missing asset_path metadata!")
		else:
			print("    ✅ Has asset_path metadata")

func test_asset_request():
	print("\n📥 Test 4: Asset Request")
	
	var asset_streamer = get_node_or_null("/root/Main/AssetStreamer")
	if not asset_streamer:
		print("❌ Cannot test - AssetStreamer not found")
		return
	
	# Connect to signals
	asset_streamer.connect("asset_ready", _on_asset_ready)
	asset_streamer.connect("asset_failed", _on_asset_failed)
	asset_streamer.connect("streaming_error", _on_streaming_error)
	
	print("🚀 Requesting test asset: models/environment/floating_island.glb")
	asset_streamer.request_asset("models/environment/floating_island.glb", "high")
	
	# Wait for result
	await get_tree().create_timer(5.0).timeout
	print("⏰ Asset request test completed (5 second timeout)")

func _on_asset_ready(asset_identifier: String, resource: Resource):
	print("✅ Asset ready: ", asset_identifier, " -> ", resource.get_class())

func _on_asset_failed(asset_identifier: String, fallback_resource: Resource):
	print("⚠️ Asset failed with fallback: ", asset_identifier, " -> ", fallback_resource.get_class() if fallback_resource else "null")

func _on_streaming_error(asset_identifier: String, error_message: String):
	print("❌ Asset streaming error: ", asset_identifier, " - ", error_message) 

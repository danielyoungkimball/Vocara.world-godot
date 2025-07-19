# Asset Streaming System Guide

## Overview

The Vocara.world asset streaming system provides seamless loading of large assets for web builds while maintaining compatibility with desktop builds. The system automatically handles cache-first loading, server fallbacks, and provides graceful error recovery with fallback assets.

## Architecture

### Core Components

1. **AssetPathResolver** - Ensures perfect path consistency between client and backend
2. **AssetStreamer** - Handles cache-first loading with server fallback 
3. **GlobalAssetManager** - Orchestrates automatic streaming for tagged nodes
4. **Backend AssetRoutes** - Serves assets with nested folder support

### Key Features

- ✅ **Perfect Path Consistency** - Automatic path resolution between client/server
- ✅ **Cache-First Strategy** - Always checks local cache before downloading
- ✅ **Graceful Fallbacks** - Provides placeholder/fallback assets on failure
- ✅ **Nested Folder Support** - Handles complex asset directory structures
- ✅ **Progress Tracking** - Visual loading indicators and progress monitoring
- ✅ **Web/Desktop Compatibility** - Seamless switching between bundled and streamed assets

## How to Add Streaming Assets

### Step 1: Organize Your Assets

Place assets in the backend asset directory with proper folder structure:

```
backend/assets/
├── models/
│   ├── characters/
│   │   ├── player.glb
│   │   └── npc.glb
│   └── environment/
│       ├── floating_island.glb
│       └── buildings.glb
├── textures/
│   ├── characters/
│   │   └── skin.png
│   └── environment/
│       └── grass.png
└── audio/
    ├── music/
    │   └── background.ogg
    └── sfx/
        └── footsteps.wav
```

### Step 2: Tag Nodes for Streaming

In your Godot scene, select nodes that should use streaming assets:

1. **Add to Group**: Add the node to the `"large_asset_stream"` group
2. **Set Metadata**: Add `asset_path` metadata with the relative path

#### Example: Streaming a 3D Model

```gdscript
# In Godot Editor or via script:
$FloatingIsland.add_to_group("large_asset_stream")
$FloatingIsland.set_meta("asset_path", "models/environment/floating_island.glb")
```

#### Scene File (.tscn) Format:

```
[node name="floating_island" parent="." groups=["large_asset_stream"]]
transform = Transform3D(0.25, 0, 0, 0, 0.25, 0, 0, 0, 0.25, 0, 0, 0)
metadata/asset_path = "models/environment/floating_island.glb"
```

### Step 3: That's It!

The system automatically:
- Detects tagged nodes on scene load
- Shows loading placeholders (spinning boxes) while downloading
- Replaces placeholders with actual assets when ready
- Handles fallbacks if loading fails

## Asset Path Resolution

The system supports multiple asset identifier formats:

| Format | Example | Description |
|--------|---------|-------------|
| Relative Path | `"models/environment/floating_island.glb"` | Preferred format |
| Filename Only | `"floating_island.glb"` | Fallback search by filename |
| res:// Path | `"res://assets/models/environment/floating_island.glb"` | Normalized to relative |

### Path Priority

1. **Exact relative path match** in manifest
2. **Filename match** in manifest (backward compatibility)
3. **Fuzzy path matching** (70% similarity threshold)
4. **Bundled res:// asset** check
5. **Fallback asset** generation

## Loading Strategies

### BUNDLED (res://)
- Asset is included in the build
- Loaded immediately from res://
- Used for core/small assets

### STREAMED
- Asset downloaded from server
- Cached in `user://asset_cache/`
- Used for large assets (>10MB)

### HYBRID
- Try bundled first, then streaming
- Fallback to placeholder if neither works
- Used for unknown assets

## API Reference

### GlobalAssetManager

#### Signals
```gdscript
# Emitted when streaming system is initialized
signal streaming_initialized()

# Emitted when asset streaming starts
signal asset_stream_started(node_name: String, asset_path: String)

# Emitted when asset streaming completes
signal asset_stream_completed(node_name: String, success: bool)

# Emitted on streaming errors
signal asset_stream_error(node_name: String, error_message: String)

# Emitted when all assets are ready
signal all_streaming_assets_ready()
```

#### Methods
```gdscript
# Request additional assets outside automatic system
func request_additional_asset(asset_path: String, priority: String = "medium")

# Check if all streaming is complete
func is_streaming_complete() -> bool

# Get progress (0.0 to 1.0)
func get_streaming_progress() -> float

# Get detailed status
func get_streaming_status() -> Dictionary
```

### AssetStreamer

#### Signals
```gdscript
# Asset fully loaded and ready to use
signal asset_ready(asset_identifier: String, resource: Resource)

# Asset failed but fallback available  
signal asset_failed(asset_identifier: String, fallback_resource: Resource)

# Complete loading failure
signal streaming_error(asset_identifier: String, error_message: String)
```

#### Methods
```gdscript
# Request asset with guaranteed state management
func request_asset(asset_identifier: String, priority: String = "medium")

# Check if asset is ready
func is_asset_ready(asset_identifier: String) -> bool

# Get loaded resource
func get_loaded_resource(asset_identifier: String) -> Resource
```

## Configuration

### GlobalAssetManager Configuration

```gdscript
# Enable/disable streaming (auto-detects web builds)
@export var enable_streaming: bool = true

# Process assets automatically on _ready
@export var auto_process_on_ready: bool = true  

# Show spinning loading placeholders
@export var show_streaming_progress: bool = true
```

### AssetStreamer Configuration

```gdscript
# Backend server URL
@export var server_url: String = "http://localhost:8080"

# Enable local caching
@export var enable_caching: bool = true

# Maximum concurrent downloads
@export var max_concurrent_downloads: int = 3

# Retry attempts for failed downloads
@export var retry_attempts: int = 3
```

## Priority Levels

| Priority | Use Case | Example Assets |
|----------|----------|----------------|
| `critical` | Environment >50MB or any >100MB | Large terrain models |
| `high` | Characters, players, key sprites | Player models, UI |
| `medium` | General assets 10-100MB | Decorative models |
| `low` | Small assets <10MB | Sound effects, icons |

## Backend Asset Manifest

The backend automatically generates a manifest with this structure:

```json
{
  "version": "1.0.0",
  "streaming_assets": {
    "model": [
      {
        "name": "floating_island.glb",
        "path": "models/environment/floating_island.glb",
        "size": 178456789,
        "priority": "critical",
        "chunks": [
          {"index": 0, "size": 5242880},
          {"index": 1, "size": 5242880}
        ]
      }
    ]
  },
  "core_assets": {
    "texture": [...]
  }
}
```

## URL Structure

### Streaming URLs
- Full asset: `/assets/stream/models/environment/floating_island.glb`
- Chunks: `/assets/chunks/models/environment/floating_island.glb/0`
- Manifest: `/assets/manifest`
- Status: `/assets/status`

## Troubleshooting

### Assets Not Loading

1. **Check Asset Path**: Verify the `asset_path` metadata matches the backend structure
2. **Check Network**: Ensure the backend server is running and accessible
3. **Check Console**: Look for `[AssetStreamer]` and `[GlobalAssetManager]` logs
4. **Check Cache**: Clear cache with `AssetStreamer.clear_cache()`

### Path Mismatch Issues

```gdscript
# DEBUG: Print all found streaming nodes
GlobalAssetManager.debug_print_streaming_nodes()

# DEBUG: Force reload all assets
GlobalAssetManager.force_reload_streaming_assets()
```

### Common Issues

#### Asset Not Found in Manifest
```
[AssetPathResolver] WARN: Unknown asset: models/my_asset.glb -> fallback will be used
```
**Solution**: Check that the asset exists in `backend/assets/` and restart the server

#### Node Not in Streaming Group
```
[GlobalAssetManager] WARNING: Node MyNode in streaming group but no asset_path metadata
```
**Solution**: Add `set_meta("asset_path", "path/to/asset.glb")` to the node

#### Download Failures
```
[AssetStreamer] Download failed for asset: HTTP 404
```
**Solution**: Verify the asset path and server URL configuration

## Best Practices

### 1. Asset Organization
- Use clear, consistent folder structures
- Group related assets together
- Keep paths short but descriptive

### 2. Performance
- Only stream assets >10MB
- Use appropriate priority levels
- Limit concurrent downloads (default: 3)

### 3. Error Handling
- Always provide fallback assets
- Handle streaming failures gracefully
- Monitor streaming progress for UX

### 4. Testing
- Test with empty cache regularly
- Verify fallback behavior
- Check both web and desktop builds

## Example: Complete Setup

### 1. Backend Asset Structure
```
backend/assets/models/environment/floating_island.glb (178MB)
```

### 2. Godot Scene Setup
```gdscript
# In scene or script
$Environment/FloatingIsland.add_to_group("large_asset_stream") 
$Environment/FloatingIsland.set_meta("asset_path", "models/environment/floating_island.glb")
```

### 3. Connect to Signals (Optional)
```gdscript
func _ready():
    var global_manager = get_node("/root/GlobalAssetManager")
    global_manager.connect("asset_stream_completed", _on_asset_ready)
    global_manager.connect("all_streaming_assets_ready", _on_all_ready)

func _on_asset_ready(node_name: String, success: bool):
    print("Asset loaded for ", node_name, ": ", success)

func _on_all_ready():
    print("All streaming assets ready!")
```

### 4. Manual Asset Requests
```gdscript
# Request additional assets at runtime
var asset_manager = get_node("/root/GlobalAssetManager")
asset_manager.request_additional_asset("models/characters/dragon.glb", "high")
```

## Migration from Old System

### From Static res:// Paths

**Old:**
```gdscript
var scene = load("res://assets/models/environment/floating_island.glb")
```

**New:**
```gdscript
# Add to scene node metadata and let system handle automatically
$FloatingIsland.set_meta("asset_path", "models/environment/floating_island.glb") 
$FloatingIsland.add_to_group("large_asset_stream")
```

### From Custom Loaders

Replace custom loading scripts with the unified system by:
1. Remove custom loader scripts
2. Add nodes to `"large_asset_stream"` group
3. Set `asset_path` metadata
4. Let GlobalAssetManager handle the rest

This unified system provides robust, maintainable asset streaming that scales with your project needs. 
# Perfect Camera Movement

A Godot 4 project implementing professional-grade camera systems and responsive combat movement for PVP games.

## 🎮 Features

### Camera System
- **RTS-style camera** with smooth following and edge scrolling
- **Target locking** - Shift+click to lock onto any targetable object
- **Smart indicators** - Animated target indicators with dynamic scaling
- **Smooth transitions** - Preserves camera angle when switching targets
- **Zoom & orbit controls** - Mouse wheel zoom, Q/E rotation

### Combat Movement
- **Souls-like dash system** - Directional rolling/dashing like Flash in LoL
- **Hyper-responsive movement** - Instant acceleration/deceleration for PVP
- **Collision recovery** - Automatic unstuck system for reliable movement
- **Slope following** - Proper navigation on multi-level terrain
- **Invincibility frames** - I-frames during dash for combat mechanics

## 🎯 Controls

| Input | Action |
|-------|--------|
| **Right Click** | Move to position |
| **Right Click + Drag** | Continuous movement |
| **Space** | Dash towards mouse cursor |
| **Shift + Left Click** | Lock camera onto target |
| **Y** | Recenter camera on player |
| **Q / E** | Rotate camera |
| **Mouse Wheel** | Zoom in/out |

## 🏗️ Project Structure

```
perfect-camera-movement/
├── src/                    # Source code
│   ├── camera/            # Camera system scripts
│   │   ├── camera_pivot.gd    # Main camera controller
│   │   └── target_indicator.gd # Target selection UI
│   └── player/            # Player scripts
│       └── player.gd      # Movement and combat system
├── assets/                 # Game assets
│   ├── models/            # 3D models
│   │   ├── characters/    # Character models (.glb)
│   │   └── environment/   # Environment models (.glb)
│   ├── sprites/           # 2D sprites and textures
│   └── textures/          # Environment textures
├── scenes/                 # Scene files
│   ├── characters/        # Character scenes (.tscn)
│   └── environments/      # Environment scenes (.tscn)
├── assets-raw/            # Source files (gitignored)
├── builds/                # Export builds (gitignored)
└── main.tscn              # Main scene
```

## 🚀 Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/perfect-camera-movement.git
   ```

2. **Open in Godot 4.4+**
   - Launch Godot Engine
   - Import the project
   - Run `main.tscn`

3. **Test the systems**
   - Right-click to move around
   - Try dashing with Space
   - Lock onto objects with Shift+click

## ⚙️ Configuration

### Camera Settings
```gdscript
# In src/camera/camera_pivot.gd
@export var follow_speed: float = 8.0
@export var zoom_speed: float = 3.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 20.0
```

### Movement Settings
```gdscript
# In src/player/player.gd
const MOVE_SPEED := 7.0
const DASH_SPEED := 15.0
const DASH_COOLDOWN := 1.0
const DASH_INVINCIBLE_TIME := 0.2
```

## 🎨 Asset Guidelines

### Recommended Formats
- **3D Models**: `.glb` (optimized for Godot)
- **Textures**: `.png`, `.jpg`, `.webp`
- **Audio**: `.ogg`, `.mp3`

### Asset Organization
- Keep source files (`.blend`, `.psd`, etc.) in `assets/raw/` (gitignored)
- Store large uncompressed assets in `assets/large/` (gitignored)
- Only commit optimized, game-ready assets

## 🛠️ Development

### Key Systems
1. **Navigation** - Uses Godot's NavigationAgent3D for pathfinding
2. **Target Selection** - Physics raycast + group-based targeting
3. **Collision Recovery** - Multi-stage unstuck system
4. **Camera Tracking** - Smooth interpolation with instant lock-on

### Adding Targetable Objects
```gdscript
# Add to any object you want to be targetable
add_to_group("targetable")
```

## 🐛 Debugging

Important log messages are prefixed:
- `[CAMERA]` - Camera system events
- `[PLAYER]` - Player movement/combat events

## 📝 License

[Add your license here]

## 🤝 Contributing

[Add contribution guidelines here] 
extends CharacterBody3D

@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D
@onready var entity_movement = $EntityMovement

# Slime behavior constants
const WANDER_SPEED := 2.0  # Slower than player for cute effect
const WANDER_RANGE := 8.0  # How far slimes wander from spawn
const JUMP_FORCE := 4.0    # How high slimes jump
const JUMP_FORWARD_FORCE := 3.0  # How much forward momentum when jumping
const JUMP_CHANCE := 0.02  # Probability per frame to jump (2% chance)
const DIRECTION_CHANGE_TIME := 3.0  # How often to pick new direction
const IDLE_TIME := 2.0     # How long to stay idle between movements
const SQUISH_SCALE := 1.3  # How much slime squishes when landing
const ROTATION_SPEED := 8.0  # How fast slimes turn to face movement direction

# State management
enum SlimeState {
	IDLE,
	WANDERING,
	JUMPING,
	SQUISHING
}

var current_state := SlimeState.IDLE
var state_timer := 0.0
var spawn_position: Vector3
var target_position: Vector3
var is_grounded := true
var original_scale: Vector3
var squish_timer := 0.0

# Movement variables
var movement_direction := Vector3.ZERO
var current_speed := 0.0

# Randomization
var direction_timer := 0.0
var idle_timer := 0.0

func _ready():
	# Store spawn position for wandering bounds
	spawn_position = global_position
	original_scale = scale
	
	# Configure navigation for slime movement
	navigation_agent_3d.radius = 0.5  # Slightly bigger than player
	navigation_agent_3d.height = 1.0  # Slimes are shorter
	navigation_agent_3d.path_desired_distance = 0.8
	navigation_agent_3d.target_desired_distance = 0.5
	navigation_agent_3d.max_speed = WANDER_SPEED
	navigation_agent_3d.path_max_distance = WANDER_RANGE
	
	# Connect to entity movement for ground detection
	if entity_movement:
		entity_movement.ground_state_changed.connect(_on_ground_state_changed)
	
	# Start in idle state
	_enter_idle_state()
	
	# Wait a frame for navigation to be ready
	await get_tree().process_frame
	
	print("[SLIME] Ready to bounce! Spawn position: ", spawn_position)

func _physics_process(delta: float) -> void:
	_update_state(delta)
	_handle_movement(delta)
	_handle_jumping(delta)
	_handle_squishing(delta)
	_handle_animation(delta)
	
	# Apply movement to velocity - EntityMovement will handle move_and_slide()
	velocity.x = movement_direction.x * current_speed
	velocity.z = movement_direction.z * current_speed

func _update_state(delta: float) -> void:
	state_timer += delta
	
	match current_state:
		SlimeState.IDLE:
			idle_timer += delta
			if idle_timer >= IDLE_TIME:
				if randf() < 0.7:  # 70% chance to wander
					_enter_wandering_state()
				else:
					_enter_idle_state()  # Stay idle a bit longer
		
		SlimeState.WANDERING:
			direction_timer += delta
			if direction_timer >= DIRECTION_CHANGE_TIME:
				_pick_new_wander_target()
				direction_timer = 0.0
			
			# Check if we reached target or are close enough
			if navigation_agent_3d.is_navigation_finished() or \
			   global_position.distance_to(target_position) < 1.0:
				_enter_idle_state()
		
		SlimeState.JUMPING:
			# Wait for landing
			if is_grounded and state_timer > 0.2:  # Minimum air time
				_enter_squishing_state()
		
		SlimeState.SQUISHING:
			if state_timer >= 0.3:  # Quick squish
				_enter_idle_state()

func _enter_idle_state() -> void:
	current_state = SlimeState.IDLE
	state_timer = 0.0
	idle_timer = 0.0
	current_speed = 0.0
	movement_direction = Vector3.ZERO
	print("[SLIME] Entering idle state")

func _enter_wandering_state() -> void:
	current_state = SlimeState.WANDERING
	state_timer = 0.0
	direction_timer = 0.0
	current_speed = WANDER_SPEED
	_pick_new_wander_target()
	print("[SLIME] Starting to wander")

func _enter_jumping_state() -> void:
	current_state = SlimeState.JUMPING
	state_timer = 0.0
	
	# Calculate jump direction - either current movement direction or facing direction
	var jump_direction = Vector3.ZERO
	if movement_direction.length() > 0.1:
		# Use current movement direction
		jump_direction = movement_direction.normalized()
	else:
		# Use facing direction (convert from rotation.y)
		jump_direction = Vector3(-sin(rotation.y), 0, -cos(rotation.y))
		# Add some random variation for idle jumps
		var random_offset = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		jump_direction = (jump_direction + random_offset).normalized()
	
	# Apply vertical jump force through EntityMovement
	if entity_movement:
		entity_movement.add_vertical_impulse(JUMP_FORCE, false)
	
	# Apply horizontal momentum directly to velocity for forward leap
	velocity.x += jump_direction.x * JUMP_FORWARD_FORCE
	velocity.z += jump_direction.z * JUMP_FORWARD_FORCE
	
	# Face the jump direction
	_face_direction(jump_direction, 0.1)
	
	print("[SLIME] *BOING!* Jumping with forward momentum!")

func _enter_squishing_state() -> void:
	current_state = SlimeState.SQUISHING
	state_timer = 0.0
	squish_timer = 0.0
	current_speed = 0.0
	movement_direction = Vector3.ZERO
	print("[SLIME] *squish* Landing!")

func _pick_new_wander_target() -> void:
	# Pick a random position within wander range of spawn
	var random_offset = Vector3(
		randf_range(-WANDER_RANGE, WANDER_RANGE),
		0,
		randf_range(-WANDER_RANGE, WANDER_RANGE)
	)
	
	target_position = spawn_position + random_offset
	
	# Use NavigationAgent3D to find path to target
	navigation_agent_3d.set_target_position(target_position)
	
	print("[SLIME] Picked new target: ", target_position)

func _handle_movement(delta: float) -> void:
	if current_state == SlimeState.WANDERING:
		# Get direction from navigation agent
		if not navigation_agent_3d.is_navigation_finished():
			var next_point = navigation_agent_3d.get_next_path_position()
			var direction = (next_point - global_position).normalized()
			
			# Set movement direction (EntityMovement will apply this via velocity)
			movement_direction.x = direction.x
			movement_direction.z = direction.z
			
			# Make slime face movement direction
			_face_direction(direction, delta)
		else:
			# Stop moving
			movement_direction = Vector3.ZERO
			current_speed = 0.0
	else:
		# Not wandering, stop horizontal movement
		movement_direction = movement_direction.lerp(Vector3.ZERO, delta * 5.0)
		if movement_direction.length() < 0.01:
			movement_direction = Vector3.ZERO
			current_speed = 0.0

# New function to handle directional facing
func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:  # Only rotate if there's significant movement
		# Calculate target rotation (only Y axis for ground movement)
		var target_angle = atan2(-direction.x, -direction.z)
		var current_angle = rotation.y
		
		# Smooth rotation using lerp_angle for proper wrapping
		var new_angle = lerp_angle(current_angle, target_angle, ROTATION_SPEED * delta)
		rotation.y = new_angle

func _handle_jumping(delta: float) -> void:
	# Random chance to jump when idle or wandering
	if is_grounded and (current_state == SlimeState.IDLE or current_state == SlimeState.WANDERING):
		if randf() < JUMP_CHANCE:
			_enter_jumping_state()

func _handle_squishing(delta: float) -> void:
	if current_state == SlimeState.SQUISHING:
		# Create squish effect by scaling
		var squish_progress = state_timer / 0.3
		var squish_factor = 1.0 + (SQUISH_SCALE - 1.0) * sin(squish_progress * PI)
		
		# Squish horizontally, stretch vertically
		scale.x = original_scale.x * squish_factor
		scale.z = original_scale.z * squish_factor
		scale.y = original_scale.y / squish_factor
	else:
		# Return to normal scale
		scale = scale.lerp(original_scale, delta * 8.0)

func _handle_animation(delta: float) -> void:
	# Gentle bobbing animation when idle
	if current_state == SlimeState.IDLE:
		var bob_amount = sin(state_timer * 2.0) * 0.02
		position.y = spawn_position.y + bob_amount
	
	# Slight rotation when moving for more organic feel
	if current_state == SlimeState.WANDERING:
		var movement_strength = current_speed
		if movement_strength > 0.1:
			# Wobble slightly when moving
			var wobble = sin(state_timer * 8.0) * 0.05 * movement_strength
			rotation.z = wobble

# Signal handlers
func _on_ground_state_changed(grounded: bool) -> void:
	is_grounded = grounded
	print("[SLIME] Ground state changed: ", grounded)

# Utility functions
func get_distance_from_spawn() -> float:
	return global_position.distance_to(spawn_position)

func is_too_far_from_spawn() -> bool:
	return get_distance_from_spawn() > WANDER_RANGE

# Debug function
func debug_slime_info() -> void:
	print("[SLIME DEBUG] State: ", SlimeState.keys()[current_state])
	print("[SLIME DEBUG] Position: ", global_position)
	print("[SLIME DEBUG] Distance from spawn: ", get_distance_from_spawn())
	print("[SLIME DEBUG] Is grounded: ", is_grounded)
	print("[SLIME DEBUG] Target position: ", target_position) 
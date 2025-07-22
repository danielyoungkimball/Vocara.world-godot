extends CharacterBody3D

@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D
@onready var camera_3d: Camera3D = $"../Camera/Camera3D"
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var entity_movement = $EntityMovement

# Combat movement constants - tuned for PVP responsiveness
const MOVE_SPEED := 7.0  # Increased for faster combat
const INSTANT_STOP := true  # No deceleration - instant stops
const ROTATION_SPEED := 25.0  # Very fast turning for combat
const SNAP_THRESHOLD := 0.05  # Instant direction changes

# Dash/roll system (souls-like)
const DASH_SPEED := 15.0  # Speed during dash
const DASH_DURATION := 0.4  # How long dash lasts
const DASH_COOLDOWN := 1.0  # Cooldown between dashes
const DASH_DISTANCE := 6.0  # How far the dash travels
const DASH_INVINCIBLE_TIME := 0.2  # I-frames duration

# Combat state
var is_dashing := false
var dash_timer := 0.0
var dash_direction := Vector3.ZERO
var dash_cooldown_timer := 0.0
var is_invincible := false
var invincible_timer := 0.0

# Movement state
var movement_direction := Vector3.ZERO
var is_moving := false
var target_reached := false

func _ready():
	# Configure navigation for reliable movement
	navigation_agent_3d.radius = 0.4
	navigation_agent_3d.height = 1.8
	navigation_agent_3d.path_desired_distance = 0.5  # Increased for better pathfinding
	navigation_agent_3d.target_desired_distance = 0.3  # Increased for reliability
	navigation_agent_3d.max_speed = MOVE_SPEED
	navigation_agent_3d.path_max_distance = 50.0  # Increased for longer paths
	
	# Wait for navigation to be ready
	call_deferred("_navigation_ready")
	
	# Configure collision system for better recovery
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(60)  # Reasonable slope limit
	wall_min_slide_angle = deg_to_rad(10)  # ~10 degrees in radians
	max_slides = 6  # Godot default
	
	# Connect to entity movement signals
	if entity_movement:
		entity_movement.ground_state_changed.connect(_on_ground_state_changed)
		entity_movement.left_navigation_region.connect(_on_left_navigation_region)
		entity_movement.entered_navigation_region.connect(_on_entered_navigation_region)
		entity_movement.fell_into_void.connect(_on_fell_into_void)
		entity_movement.recovered_from_void.connect(_on_recovered_from_void)

func _navigation_ready():
	# Ensure navigation is properly initialized
	await get_tree().process_frame

func _unhandled_input(event: InputEvent) -> void:
	# Right click movement
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click(event.position)
	
	# Dash input (space or controller button)
	if event.is_action_pressed("ui_accept") or Input.is_action_just_pressed("jump"):
		_handle_dash_input()

func _handle_right_click(mouse_pos: Vector2) -> void:
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return

	var ray_origin = camera_3d.project_ray_origin(mouse_pos)
	var ray_dir = camera_3d.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_dir * 1000.0

	var target = NavigationServer3D.map_get_closest_point_to_segment(map, ray_origin, ray_end)
	navigation_agent_3d.set_target_position(target)
	target_reached = false

func _handle_dash_input() -> void:
	# Check if dash is available (not on cooldown)
	if dash_cooldown_timer <= 0.0 and not is_dashing:
		_perform_dash()

func _perform_dash() -> void:
	# Dash towards mouse cursor (like Flash in LoL)
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = camera_3d
	
	# Raycast from camera to ground at mouse position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_dir * 1000.0
	
	# Get ground position under mouse
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray_origin
	query.to = ray_end
	query.collision_mask = 1  # Ground layer
	
	var result = space_state.intersect_ray(query)
	
	var target_pos: Vector3
	if result:
		# Dash towards mouse ground position
		target_pos = result.position
	else:
		# Fallback: dash in movement direction or forward
		if is_moving:
			target_pos = global_position + movement_direction * DASH_DISTANCE
		else:
			target_pos = global_position + (-transform.basis.z * DASH_DISTANCE)
	
	# Validate dash destination using EntityMovement
	if entity_movement:
		target_pos = entity_movement.validate_dash_destination(target_pos)
	
	dash_direction = (target_pos - global_position).normalized()
	dash_direction.y = 0  # Keep horizontal only
	
	# Start dash
	is_dashing = true
	dash_timer = DASH_DURATION
	dash_cooldown_timer = DASH_COOLDOWN
	
	# Start invincibility frames
	is_invincible = true
	invincible_timer = DASH_INVINCIBLE_TIME
	
	print("[PLAYER] Dashing to validated position: ", target_pos)

func _physics_process(delta: float) -> void:
	_handle_dash_system(delta)
	_handle_movement(delta)
	_handle_rotation(delta)
	_handle_animation()
	_update_dash_preview()
	
	# EntityMovement component handles physics movement (move_and_slide) and safety checks in its own _physics_process

func _update_dash_preview() -> void:
	# Optional: Show dash direction preview
	# You could add a visual indicator here showing where dash will go
	pass

func _handle_dash_system(delta: float) -> void:
	# Update dash timer
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			dash_direction = Vector3.ZERO
	
	# Update dash cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	# Update invincibility frames
	if is_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false

func _handle_movement(_delta: float) -> void:
	# Handle continuous right mouse hold for precise control
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_handle_right_click(get_viewport().get_mouse_position())
	
	# Dash movement takes priority
	if is_dashing:
		# Pure dash movement - no navigation interference
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		# Don't set velocity.y = 0 during dash - let it follow terrain
		return
	
	# Get movement direction from navigation
	if not navigation_agent_3d.is_navigation_finished():
		var next_point = navigation_agent_3d.get_next_path_position()
		var to_target = next_point - global_position
		
		# Include Y component for slope following
		var horizontal_distance = Vector2(to_target.x, to_target.z).length()
		
		if horizontal_distance > navigation_agent_3d.target_desired_distance:
			movement_direction = to_target.normalized()
			is_moving = true
			target_reached = false
		else:
			# Target reached - stop instantly for PVP precision
			movement_direction = Vector3.ZERO
			is_moving = false
			target_reached = true
	else:
		# No navigation target
		movement_direction = Vector3.ZERO
		is_moving = false
		target_reached = true
	
	# Apply normal movement
	if is_moving:
		# INSTANT movement - no acceleration, includes Y for slopes
		velocity.x = movement_direction.x * MOVE_SPEED
		velocity.z = movement_direction.z * MOVE_SPEED
		# Y movement is handled by EntityMovement component (gravity and ground snapping)
	else:
		# INSTANT stop for precise control
		if INSTANT_STOP:
			velocity.x = 0
			velocity.z = 0
			# Y velocity is handled by EntityMovement component

func _handle_rotation(delta: float) -> void:
	if is_moving and movement_direction.length() > SNAP_THRESHOLD:
		# Calculate target rotation
		var target_angle = atan2(movement_direction.x, movement_direction.z)
		# Removed the +PI adjustment - let you fix model import instead
		
		# VERY fast rotation for combat responsiveness
		var current_angle = rotation.y
		var angle_diff = angle_difference(current_angle, target_angle)
		
		# Instant snap for small differences, smooth for larger ones
		if abs(angle_diff) < 0.2:
			rotation.y = target_angle
		else:
			rotation.y += angle_diff * ROTATION_SPEED * delta

# Gravity removed - souls-like ground-based combat only

# Signal handlers for EntityMovement component
func _on_ground_state_changed(_is_grounded: bool):
	# print("[PLAYER] Ground state changed: ", is_grounded)
	pass

func _on_left_navigation_region():
	print("[PLAYER] Left navigation region")

func _on_entered_navigation_region():
	print("[PLAYER] Entered navigation region")

func _on_fell_into_void():
	print("[PLAYER] Oh no! Fell into the void!")
	# Could add screen effects, sounds, etc. here
	
func _on_recovered_from_void(recovery_position: Vector3):
	print("[PLAYER] Whew! Recovered from void at: ", recovery_position)
	# Could add teleport effects, sounds, etc. here

# Debug function to test void recovery
func debug_test_void_recovery():
	if entity_movement:
		entity_movement.debug_trigger_void_recovery()

func debug_show_edge_info():
	if entity_movement:
		entity_movement.debug_show_edge_position()

# Old unstuck methods removed - now handled by EntityMovement component

func _handle_wall_sliding() -> void:
	# Improve wall sliding for better movement feel
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var normal = collision.get_normal()
		
		# Prevent getting stuck in corners by adjusting velocity
		if normal.y < 0.7:  # It's a wall, not floor
			var wall_slide_factor = 1.0 - abs(normal.dot(velocity.normalized()))
			velocity *= clamp(wall_slide_factor, 0.5, 1.0)

func _handle_animation() -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# Priority: Dashing > Moving > Idle
	if is_dashing:
		if not anim_player.is_playing() or anim_player.current_animation != "Running":
			# Could add a dash animation here
			anim_player.play("Running")  # Use running for now
	elif horizontal_speed > 0.5:
		if not anim_player.is_playing() or anim_player.current_animation != "Running":
			anim_player.play("Running")
	else:
		if not anim_player.is_playing() or anim_player.current_animation != "A-Pose":
			anim_player.play("A-Pose")

# Utility function for smooth angle interpolation
func angle_difference(from: float, to: float) -> float:
	var diff = fmod(to - from, TAU)
	return fmod(2.0 * diff, TAU) - diff

# Combat utility functions
func is_in_combat() -> bool:
	return is_dashing or dash_cooldown_timer > 0

func get_movement_state() -> String:
	if is_dashing:
		return "dashing"
	elif is_moving:
		return "moving"
	else:
		return "idle"

func can_dash() -> bool:
	return dash_cooldown_timer <= 0.0 and not is_dashing

func get_dash_cooldown_remaining() -> float:
	return max(0.0, dash_cooldown_timer)

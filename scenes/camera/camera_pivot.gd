extends Node3D

# Camera settings
@export var follow_speed: float = 8.0
@export var edge_scroll_speed: float = 15.0
@export var edge_scroll_threshold: float = 50.0
@export var zoom_speed: float = 3.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 20.0
@export var orbit_speed: float = 120.0 # degrees per second
@export var tilt_angle: float = -45.0 # degrees, fixed tilt for RTS-style look
@export var smooth_factor: float = 0.15 # For smooth camera movement
@export var lock_on_speed: float = 5.0 # Speed for camera pivot to follow locked target

# Camera state
var target: Node3D = null
var locked_target: Node3D = null # The target we're locked onto
var offset_distance: float = 15.0
var target_zoom_distance: float = 15.0 # Target zoom for smooth lerping
var current_yaw: float = 0.0 # Y-axis rotation in degrees
var free_camera_pos: Vector3 = Vector3.ZERO # Position when not focused
var is_locked_on: bool = false # Whether we're in lock-on mode

@onready var camera: Camera3D = $Camera3D

func _ready():
	if get_node_or_null("../Player"):
		target = get_node("../Player")
		locked_target = target # Default to player
		free_camera_pos = target.global_transform.origin
		global_transform.origin = target.global_transform.origin
		is_locked_on = true # Start locked on to player
		print("[CAMERA] Initialized - locked on player")
	else:
		print("[CAMERA] ERROR: Player not found at ../Player")
	
	_update_camera_transform()

func _process(delta):
	if not target:
		return

	# Handle recenter with Y key
	if Input.is_action_just_pressed("recenter_camera"):
		if not is_locked_on or locked_target != target:
			snap_and_lock_to_player()
		else:
			unlock_and_freeze_camera()

	handle_edge_scrolling(delta)
	handle_mouse_wheel_zoom()
	handle_orbit(delta)
	handle_target_selection()
	update_camera_position(delta)
	# Smoothly lerp offset_distance toward target_zoom_distance
	offset_distance = lerp(offset_distance, target_zoom_distance, 0.15)
	_update_camera_transform()

func handle_edge_scrolling(delta):
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var viewport_size = viewport.get_visible_rect().size
	var movement = Vector3.ZERO

	if mouse_pos.x < edge_scroll_threshold:
		movement.x -= 1
	elif mouse_pos.x > viewport_size.x - edge_scroll_threshold:
		movement.x += 1
	if mouse_pos.y < edge_scroll_threshold:
		movement.z -= 1
	elif mouse_pos.y > viewport_size.y - edge_scroll_threshold:
		movement.z += 1

	if movement != Vector3.ZERO:
		# Exit lock-on mode when edge scrolling
		if is_locked_on:
			is_locked_on = false
			free_camera_pos = global_transform.origin
		movement = movement.normalized() * edge_scroll_speed * delta
		var yaw_rad = deg_to_rad(current_yaw)
		var forward = Vector3(sin(yaw_rad), 0, cos(yaw_rad))
		var right = Vector3(forward.z, 0, -forward.x)
		free_camera_pos += right * movement.x + forward * movement.z

func handle_mouse_wheel_zoom():
	# Use mouse wheel for zooming
	if Input.is_action_just_pressed("zoom_in"):
		target_zoom_distance -= zoom_speed
	if Input.is_action_just_pressed("zoom_out"):
		target_zoom_distance += zoom_speed
	target_zoom_distance = clamp(target_zoom_distance, min_zoom, max_zoom)

func handle_orbit(delta):
	var left = Input.is_action_pressed("rotate_left") # Q
	var right = Input.is_action_pressed("rotate_right") # E
	if left:
		current_yaw -= orbit_speed * delta
	if right:
		current_yaw += orbit_speed * delta
	current_yaw = fmod(current_yaw, 360.0)

func handle_target_selection():
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_SHIFT):
		var mouse_pos = get_viewport().get_mouse_position()
		
		# Try physics raycast first (for objects with collision shapes)
		var space_state = get_world_3d().direct_space_state
		var from = camera.project_ray_origin(mouse_pos)
		var to = from + camera.project_ray_normal(mouse_pos) * 1000
		var query = PhysicsRayQueryParameters3D.new()
		query.from = from
		query.to = to
		query.exclude = [camera]
		var result = space_state.intersect_ray(query)
		
		var target_found = false
		if result and result.has("collider"):
			var new_target = result.collider
			
			# If clicking the already locked-on target, unlock
			if is_locked_on and new_target == locked_target:
				print("[CAMERA] Unlocked from ", new_target.name)
				unlock_and_freeze_camera()
				target_found = true
			# Otherwise, check if the target is targetable and lock on
			elif is_targetable(new_target):
				print("[CAMERA] Locked onto ", new_target.name)
				lock_on_target(new_target)
				target_found = true
		
		# If no physics hit, try to find any 3D object under the mouse
		if not target_found:
			var all_nodes = get_tree().get_nodes_in_group("targetable")
			var closest_target = null
			var closest_distance = 1000 # Maximum distance to consider
			
			for node in all_nodes:
				if node is Node3D:
					var screen_pos = camera.unproject_position(node.global_transform.origin)
					var distance = mouse_pos.distance_to(screen_pos)
					
					# If mouse is close to this object and it's closer than previous closest
					if distance < 50 and distance < closest_distance: # 50 pixel tolerance
						closest_target = node
						closest_distance = distance
			
			if closest_target:
				if is_locked_on and closest_target == locked_target:
					print("[CAMERA] Unlocked from ", closest_target.name)
					unlock_and_freeze_camera()
				else:
					print("[CAMERA] Locked onto ", closest_target.name)
					lock_on_target(closest_target)

func is_targetable(obj: Node3D) -> bool:
	# Check if object is the camera itself
	if obj == camera:
		return false
		
	# Check the entire node hierarchy for targetable groups
	var current_node = obj
	while current_node != null:
		# Check if object has the "targetable" property set to true
		if current_node.has_meta("targetable") and current_node.get("targetable") == true:
			return true
		# Check if object is in a targetable group
		if current_node.is_in_group("targetable"):
			return true
		# Move up to parent node
		current_node = current_node.get_parent()
	
	# For now, also accept the player as targetable
	if obj == target:
		return true
	return false

func lock_on_target(new_target: Node3D):
	locked_target = new_target
	is_locked_on = true
	# Don't reset yaw for any target - preserve current camera angle

func recenter_on_player():
	if get_node_or_null("../Player"):
		locked_target = get_node("../Player")
		is_locked_on = true
		current_yaw = 0.0
		global_transform.origin = locked_target.global_transform.origin
		free_camera_pos = locked_target.global_transform.origin

func update_camera_position(delta):
	if is_locked_on and locked_target:
		# Instantly move the camera pivot to follow the locked target
		global_transform.origin = locked_target.global_transform.origin
	else:
		# Free camera movement
		global_transform.origin = global_transform.origin.lerp(free_camera_pos, follow_speed * delta)

func _update_camera_transform():
	# Simple RTS camera positioning
	# Camera is positioned at a fixed height and distance from the pivot
	var yaw_rad = deg_to_rad(current_yaw)
	
	# Calculate camera position relative to pivot
	var camera_x = sin(yaw_rad) * offset_distance
	var camera_z = cos(yaw_rad) * offset_distance
	var camera_y = offset_distance * 0.7 # Fixed height for RTS view
	
	# Set camera position
	camera.transform.origin = Vector3(camera_x, camera_y, camera_z)
	
	# Make camera look at the pivot point (target)
	camera.look_at(global_transform.origin, Vector3.UP)

# Public methods for external access
func get_camera() -> Camera3D:
	return camera

func is_camera_focused() -> bool:
	return is_locked_on

func get_current_target() -> Node3D:
	return locked_target if is_locked_on else null

func get_locked_target() -> Node3D:
	return locked_target

func is_locked_on_mode() -> bool:
	return is_locked_on 

# Instantly snap and lock to player
func snap_and_lock_to_player():
	if get_node_or_null("../Player"):
		locked_target = get_node("../Player")
		is_locked_on = true
		# Preserve current rotation instead of resetting to 0
		global_transform.origin = locked_target.global_transform.origin
		free_camera_pos = locked_target.global_transform.origin

# Unlock and freeze camera at current position
func unlock_and_freeze_camera():
	is_locked_on = false
	free_camera_pos = global_transform.origin 

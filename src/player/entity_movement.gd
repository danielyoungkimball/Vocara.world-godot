extends Node
class_name EntityMovement

## A comprehensive movement system for entities that handles:
## - Gravity and ground detection
## - Navigation mesh boundaries
## - Safe spawning and positioning
## - Collision recovery

signal ground_state_changed(is_grounded: bool)
signal left_navigation_region()
signal entered_navigation_region()
signal fell_into_void()
signal recovered_from_void(recovery_position: Vector3)

@export_group("Gravity System")
@export var gravity_enabled: bool = true
@export var gravity_force: float = 20.0
@export var terminal_velocity: float = 50.0
@export var ground_snap_distance: float = 0.5
@export var ground_detection_layers: int = 1  # Physics layers for ground

@export_group("Ground Detection")
@export var ground_check_distance: float = 1.2
@export var ground_check_margin: float = 0.1
@export var max_ground_angle: float = 60.0  # Max slope angle in degrees
@export var ground_stick_force: float = 5.0  # Force to stick to ground on slopes

@export_group("Navigation Safety")
@export var navigation_boundary_buffer: float = 0.5  # Distance from nav region edge
@export var auto_return_to_nav: bool = false  # Auto-return to navigation mesh when off (disabled for edge falling)
@export var max_off_nav_time: float = 2.0  # Max time allowed off navigation mesh

@export_group("Void Protection")
@export var void_y_threshold: float = -50.0  # Y position considered "void"
@export var void_detection_enabled: bool = true  # Enable void detection
@export var void_recovery_height: float = 5.0  # Height to spawn above ground when recovering

@export_group("Safe Spawning")
@export var spawn_height_offset: float = 2.0  # Height to spawn above ground
@export var spawn_search_radius: float = 5.0  # Radius to search for safe spawn
@export var max_spawn_attempts: int = 10  # Max attempts to find safe spawn

@export_group("Collision Recovery")
@export var stuck_threshold: float = 0.05  # Increased from 0.01 to 0.05 (5cm)
@export var stuck_time_limit: float = 1.0   # Increased from 0.1 to 1.0 seconds
@export var max_unstuck_attempts: int = 3
@export var unstuck_push_force: float = 3.0

# Internal state
var entity: CharacterBody3D
var navigation_agent: NavigationAgent3D
var last_position: Vector3
var last_valid_nav_position: Vector3
var edge_fall_position: Vector3  # Position where player left navigation mesh
var is_grounded: bool = false
var was_grounded: bool = false
var ground_normal: Vector3 = Vector3.UP
var off_nav_timer: float = 0.0
var stuck_timer: float = 0.0
var unstuck_attempts: int = 0
var ground_contact_point: Vector3
var navigation_map: RID
var was_on_nav_mesh: bool = true

func _ready():
	entity = get_parent() as CharacterBody3D
	if not entity:
		push_error("[EntityMovement] Parent must be a CharacterBody3D")
		return
	
	navigation_agent = entity.get_node_or_null("NavigationAgent3D")
	if not navigation_agent:
		push_error("[EntityMovement] NavigationAgent3D not found on entity")
		return
	
	last_position = entity.global_position
	last_valid_nav_position = entity.global_position
	navigation_map = entity.get_world_3d().navigation_map
	
	# Wait for navigation to be ready
	call_deferred("_initialize_navigation")

func _initialize_navigation():
	await entity.get_tree().process_frame
	last_valid_nav_position = get_closest_nav_point(entity.global_position)
	edge_fall_position = entity.global_position  # Initialize edge position
	
	# Ensure entity starts on valid ground
	ensure_safe_spawn_position()

func _physics_process(delta: float):
	if not entity or not navigation_agent:
		return
	
	update_ground_state()
	handle_gravity(delta)
	handle_navigation_boundaries(delta)
	handle_void_detection()
	handle_collision_recovery(delta)
	
	# Apply physics movement - this is essential for CharacterBody3D entities
	entity.move_and_slide()
	
	# Update tracking
	last_position = entity.global_position
	was_grounded = is_grounded

func update_ground_state():
	var space_state = entity.get_world_3d().direct_space_state
	var from = entity.global_position
	var to = from + Vector3(0, -ground_check_distance, 0)
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = ground_detection_layers
	query.exclude = [entity]
	
	var result = space_state.intersect_ray(query)
	
	var new_grounded = false
	if result:
		var distance = from.distance_to(result.position)
		if distance <= ground_snap_distance:
			new_grounded = true
			ground_normal = result.normal
			ground_contact_point = result.position
			
			# Check if slope is too steep
			var angle = rad_to_deg(acos(ground_normal.dot(Vector3.UP)))
			if angle > max_ground_angle:
				new_grounded = false
	
	if new_grounded != is_grounded:
		is_grounded = new_grounded
		ground_state_changed.emit(is_grounded)
		
		if is_grounded:
			print("[EntityMovement] Entity grounded at ", ground_contact_point)
		else:
			print("[EntityMovement] Entity airborne")

func handle_gravity(delta: float):
	if not gravity_enabled:
		return
	
	if is_grounded:
		# Snap to ground and apply ground stick force
		if ground_contact_point != Vector3.ZERO:
			var target_y = ground_contact_point.y
			var current_y = entity.global_position.y
			var diff = target_y - current_y
			
			# Smooth ground snapping
			if abs(diff) < ground_snap_distance:
				entity.velocity.y = diff * ground_stick_force
			else:
				entity.velocity.y = 0.0
	else:
		# Apply gravity
		entity.velocity.y -= gravity_force * delta
		entity.velocity.y = max(entity.velocity.y, -terminal_velocity)

func handle_navigation_boundaries(delta: float):
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return
	
	var current_pos = entity.global_position
	var closest_nav_point = get_closest_nav_point(current_pos)
	var distance_to_nav = current_pos.distance_to(closest_nav_point)
	var is_on_nav_mesh = distance_to_nav <= navigation_boundary_buffer
	
	# Check if we just left the navigation mesh
	if was_on_nav_mesh and not is_on_nav_mesh:
		# Store the closest point on the navigation mesh as the edge position
		edge_fall_position = closest_nav_point
		print("[EntityMovement] Player left navigation mesh, edge position: ", edge_fall_position)
		left_navigation_region.emit()
	
	# Check if we're off the navigation mesh
	if not is_on_nav_mesh:
		off_nav_timer += delta
		
		if off_nav_timer > max_off_nav_time and auto_return_to_nav:
			print("[EntityMovement] Auto-returning to navigation mesh")
			return_to_navigation_mesh()
	else:
		if off_nav_timer > 0.0:
			off_nav_timer = 0.0
			last_valid_nav_position = closest_nav_point
			entered_navigation_region.emit()
	
	# Update nav mesh state
	was_on_nav_mesh = is_on_nav_mesh

func handle_void_detection():
	if not void_detection_enabled:
		return
		
	var current_pos = entity.global_position
	
	# Check if entity has fallen into the void
	if current_pos.y <= void_y_threshold:
		print("[EntityMovement] Entity fell into void at Y=", current_pos.y)
		fell_into_void.emit()
		recover_from_void()

func recover_from_void():
	print("[EntityMovement] Recovering from void...")
	
	var recovery_position = Vector3.ZERO
	
	# First priority: respawn at the edge where they fell off
	if edge_fall_position != Vector3.ZERO:
		recovery_position = edge_fall_position
		print("[EntityMovement] Using edge fall position: ", recovery_position)
	else:
		# Fallback: use last valid navigation position
		recovery_position = last_valid_nav_position
		print("[EntityMovement] Using last valid nav position: ", recovery_position)
	
	# Ensure the recovery position is safe and on the navigation mesh
	var safe_recovery = find_safe_position_near(recovery_position)
	if safe_recovery != Vector3.ZERO:
		recovery_position = safe_recovery
	
	if recovery_position == Vector3.ZERO:
		# Emergency: find ANY position on the navigation mesh
		var nav_point = get_closest_nav_point(Vector3.ZERO)
		recovery_position = find_safe_position_near(nav_point)
	
	if recovery_position != Vector3.ZERO:
		# Add some height for dramatic effect and safety
		recovery_position.y += void_recovery_height
		
		entity.global_position = recovery_position
		entity.velocity = Vector3.ZERO
		
		# Reset timers and state
		off_nav_timer = 0.0
		last_valid_nav_position = recovery_position
		was_on_nav_mesh = true
		
		print("[EntityMovement] Recovered from void at: ", recovery_position)
		recovered_from_void.emit(recovery_position)
	else:
		print("[EntityMovement] CRITICAL: Could not find recovery position from void!")
		# Last resort: place at world origin and hope for the best
		entity.global_position = Vector3(0, 10, 0)
		entity.velocity = Vector3.ZERO

func get_closest_nav_point(position: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(navigation_map, position)

func is_position_on_navigation_mesh(position: Vector3) -> bool:
	var closest_point = get_closest_nav_point(position)
	return position.distance_to(closest_point) <= navigation_boundary_buffer

func return_to_navigation_mesh():
	# Only teleport if we're actually in danger (void), not just off nav mesh
	if entity.global_position.y < void_y_threshold:
		var safe_position = find_safe_position_near(last_valid_nav_position)
		if safe_position != Vector3.ZERO:
			entity.global_position = safe_position
			entity.velocity = Vector3.ZERO
			off_nav_timer = 0.0
			print("[EntityMovement] Returned to navigation mesh at ", safe_position)
		else:
			print("[EntityMovement] Failed to find safe return position")
	else:
		# Just slightly adjust position towards navigation mesh, don't teleport
		var closest_nav_point = get_closest_nav_point(entity.global_position)
		var direction = (closest_nav_point - entity.global_position).normalized()
		entity.global_position += direction * 0.1  # Small nudge
		print("[EntityMovement] Nudged towards navigation mesh")

func find_safe_position_near(center: Vector3) -> Vector3:
	# Try center first
	if is_safe_position(center):
		return center
	
	# Try positions in expanding circles
	for radius in range(1, int(spawn_search_radius) + 1):
		for angle in range(0, 360, 45):
			var test_pos = center + Vector3(
				cos(deg_to_rad(angle)) * radius,
				spawn_height_offset,
				sin(deg_to_rad(angle)) * radius
			)
			
			if is_safe_position(test_pos):
				return test_pos
	
	return Vector3.ZERO

func is_safe_position(position: Vector3) -> bool:
	# Check if position is on navigation mesh
	if not is_position_on_navigation_mesh(position):
		return false
	
	# Check if there's ground below
	var space_state = entity.get_world_3d().direct_space_state
	var from = position + Vector3(0, spawn_height_offset, 0)
	var to = position + Vector3(0, -10.0, 0)
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = ground_detection_layers
	query.exclude = [entity]
	
	var result = space_state.intersect_ray(query)
	if not result:
		return false
	
	# Check if ground angle is acceptable
	var ground_angle = rad_to_deg(acos(result.normal.dot(Vector3.UP)))
	if ground_angle > max_ground_angle:
		return false
	
	# Check if there's enough space for the entity
	var collision_check = PhysicsRayQueryParameters3D.new()
	collision_check.from = result.position + Vector3(0, 0.1, 0)
	collision_check.to = result.position + Vector3(0, 2.0, 0)
	collision_check.collision_mask = 1  # Check against walls/obstacles
	collision_check.exclude = [entity]
	
	var collision_result = space_state.intersect_ray(collision_check)
	return not collision_result  # Safe if no collision

func ensure_safe_spawn_position():
	var current_pos = entity.global_position
	
	# Only move entity if it's in a truly dangerous position (void)
	if current_pos.y < void_y_threshold:
		print("[EntityMovement] Entity spawned in void, moving to safe position...")
		
		# Try to find a safe position
		var safe_pos = find_safe_position_near(current_pos)
		if safe_pos != Vector3.ZERO:
			entity.global_position = safe_pos
			print("[EntityMovement] Moved to safe spawn position: ", safe_pos)
		else:
			# Last resort: get closest nav point and place on ground
			var nav_point = get_closest_nav_point(current_pos)
			var ground_pos = get_ground_position(nav_point)
			if ground_pos != Vector3.ZERO:
				entity.global_position = ground_pos
				print("[EntityMovement] Emergency spawn at ground position: ", ground_pos)
			else:
				print("[EntityMovement] WARNING: Could not find safe spawn position!")
	else:
		# Entity is above void threshold, let it fall naturally
		print("[EntityMovement] Entity at valid Y position (", current_pos.y, "), allowing natural fall")

func get_ground_position(position: Vector3) -> Vector3:
	var space_state = entity.get_world_3d().direct_space_state
	var from = position + Vector3(0, 10.0, 0)
	var to = position + Vector3(0, -10.0, 0)
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = ground_detection_layers
	query.exclude = [entity]
	
	var result = space_state.intersect_ray(query)
	if result:
		return result.position + Vector3(0, 0.1, 0)  # Slightly above ground
	
	return Vector3.ZERO

func handle_collision_recovery(delta: float):
	var movement_distance = entity.global_position.distance_to(last_position)
	var horizontal_velocity = Vector2(entity.velocity.x, entity.velocity.z).length()
	var is_trying_to_move = horizontal_velocity > 0.2  # Increased threshold for "trying to move"
	var moved_very_little = movement_distance < stuck_threshold
	
	# Only trigger if we're actually trying to move AND grounded (not during dashes or falls)
	if is_trying_to_move and moved_very_little and is_grounded:
		stuck_timer += delta
		
		if stuck_timer >= stuck_time_limit and unstuck_attempts < max_unstuck_attempts:
			# Additional check: only unstuck if we're colliding with something
			if entity.get_slide_collision_count() > 0:
				attempt_unstuck()
				unstuck_attempts += 1
				stuck_timer = 0.0
			else:
				# Not actually stuck, just moving slowly - reset timer
				stuck_timer = 0.0
	else:
		stuck_timer = 0.0
		unstuck_attempts = 0

func attempt_unstuck():
	print("[EntityMovement] Stuck detected, attempting recovery (", unstuck_attempts + 1, "/", max_unstuck_attempts, ")")
	
	match unstuck_attempts:
		0:
			# Method 1: Push upward
			entity.velocity.y = unstuck_push_force
			entity.global_position.y += 0.1
		1:
			# Method 2: Push away from collisions
			var push_dir = get_push_direction()
			if push_dir != Vector3.ZERO:
				entity.global_position += push_dir * 0.3
		2:
			# Method 3: Return to last valid navigation position
			return_to_navigation_mesh()

func get_push_direction() -> Vector3:
	var push_direction = Vector3.ZERO
	
	for i in entity.get_slide_collision_count():
		var collision = entity.get_slide_collision(i)
		var normal = collision.get_normal()
		push_direction += normal
	
	return push_direction.normalized()

func validate_dash_destination(destination: Vector3) -> Vector3:
	# Allow dashing off the edge - players can fall and will be respawned
	# Only prevent dashing directly into the void (way below the map)
	if destination.y <= void_y_threshold:
		print("[EntityMovement] Dash destination rejected: would fall into void")
		return entity.global_position
	
	# Check if destination has ground - if not, that's okay, they'll fall and respawn
	var ground_pos = get_ground_position(destination)
	if ground_pos != Vector3.ZERO:
		destination = ground_pos
	
	# Allow the dash even if it's off the navigation mesh
	# The void detection system will handle recovery if they fall
	return destination

func get_movement_state() -> Dictionary:
	return {
		"is_grounded": is_grounded,
		"ground_normal": ground_normal,
		"on_navigation_mesh": is_position_on_navigation_mesh(entity.global_position),
		"off_nav_timer": off_nav_timer,
		"stuck_timer": stuck_timer,
		"ground_contact_point": ground_contact_point
	}

func force_ground_snap():
	"""Force the entity to snap to the ground immediately"""
	var ground_pos = get_ground_position(entity.global_position)
	if ground_pos != Vector3.ZERO:
		entity.global_position = ground_pos
		entity.velocity.y = 0.0
		print("[EntityMovement] Force snapped to ground at ", ground_pos)

func teleport_to_safe_position(position: Vector3):
	"""Teleport entity to a safe position"""
	var safe_pos = find_safe_position_near(position)
	if safe_pos != Vector3.ZERO:
		entity.global_position = safe_pos
		entity.velocity = Vector3.ZERO
		last_position = safe_pos
		last_valid_nav_position = safe_pos
		print("[EntityMovement] Teleported to safe position: ", safe_pos)
	else:
		print("[EntityMovement] Failed to find safe teleport position")

func set_void_threshold(threshold: float):
	"""Set the void Y threshold for this map"""
	void_y_threshold = threshold
	print("[EntityMovement] Void threshold set to: ", threshold)

func get_void_threshold() -> float:
	"""Get the current void Y threshold"""
	return void_y_threshold

func add_vertical_impulse(force: float, require_grounded: bool = true):
	"""Add a vertical impulse to the entity (for jumping, bouncing, etc.)"""
	if not entity:
		return
	
	# Optional grounding check - items/projectiles might not need it
	if require_grounded and not entity.is_on_floor():
		return
	
	entity.velocity.y += force
	print("[EntityMovement] Added vertical impulse: ", force)

func debug_trigger_void_recovery():
	"""Debug function to test void recovery system"""
	print("[EntityMovement] DEBUG: Triggering void recovery")
	recover_from_void()

func debug_show_edge_position():
	"""Debug function to show current edge fall position"""
	print("[EntityMovement] DEBUG: Edge fall position: ", edge_fall_position)
	print("[EntityMovement] DEBUG: Last valid nav position: ", last_valid_nav_position)
	print("[EntityMovement] DEBUG: Current position: ", entity.global_position)
	print("[EntityMovement] DEBUG: On navigation mesh: ", is_position_on_navigation_mesh(entity.global_position)) 

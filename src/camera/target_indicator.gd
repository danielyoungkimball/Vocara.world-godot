extends Sprite3D

# Animation settings
@export var animation_speed: float = 1.0 # seconds per cycle
@export var frame_count: int = 2
@export var base_scale: float = 2.0 # Base scale multiplier (reduced for better scaling)
@export var sprite_scale: float = 2.0 # Overall sprite scale multiplier (for 32x32 pixel sprites)
@export var height_offset: float = 0.0 # How high above the target (reduced for feet level)

# Animation state
var animation_time: float = 0.0
var current_frame: int = 0

# Reference to camera pivot
var camera_pivot: Node3D = null

func _ready() -> void:
	# Get reference to camera pivot
	camera_pivot = get_parent()
	# Start hidden
	visible = false

func _process(delta: float) -> void:
	# Check if camera is locked onto a target
	if camera_pivot and camera_pivot.is_locked_on_mode():
		var locked_target = camera_pivot.get_locked_target()
		if locked_target:
			# Show indicator and animate
			visible = true
			
			# Calculate target size and scale indicator
			var target_scale = get_target_scale(locked_target)
			scale = Vector3(target_scale * sprite_scale, target_scale * sprite_scale, target_scale * sprite_scale)
			
			# Position indicator above the target
			global_transform.origin = locked_target.global_transform.origin + Vector3(0, height_offset, 0)
			
			# Animate the sprite
			animation_time += delta
			if animation_time >= animation_speed / frame_count:
				animation_time = 0.0
				current_frame = (current_frame + 1) % frame_count
				frame = current_frame
		else:
			visible = false
	else:
		visible = false

func get_target_scale(target: Node3D) -> float:
	# Try to get the target's size from various sources
	var target_size = 1.0
	
	# Check if it's a CharacterBody3D (player)
	if target is CharacterBody3D:
		var collision_shape = target.get_node_or_null("CollisionShape3D")
		if collision_shape and collision_shape.shape:
			if collision_shape.shape is BoxShape3D:
				var shape_size = collision_shape.shape.size
				target_size = max(shape_size.x, shape_size.z)
			elif collision_shape.shape is CapsuleShape3D:
				target_size = collision_shape.shape.radius * 2.0
			elif collision_shape.shape is SphereShape3D:
				target_size = collision_shape.shape.radius * 2.0
			else:
				target_size = 1.0
	
	# Check if it has a MeshInstance3D
	elif target is MeshInstance3D:
		if target.mesh:
			var aabb = target.mesh.get_aabb()
			target_size = max(aabb.size.x, aabb.size.z)
	
	# Check if it has a child MeshInstance3D
	else:
		var mesh_child = target.get_node_or_null("MeshInstance3D")
		if mesh_child and mesh_child.mesh:
			var aabb = mesh_child.mesh.get_aabb()
			target_size = max(aabb.size.x, aabb.size.z)
	
	# Also check for any MeshInstance3D children recursively
	if target_size <= 1.0:
		var mesh_children = find_mesh_children(target)
		for mesh_child in mesh_children:
			if mesh_child.mesh:
				var aabb = mesh_child.mesh.get_aabb()
				var child_size = max(aabb.size.x, aabb.size.z)
				target_size = max(target_size, child_size)
	
	# Apply base scale and clamp to reasonable range
	var final_scale = clamp(target_size * base_scale, 0.5, 10.0)
	return final_scale

func find_mesh_children(node: Node3D) -> Array:
	var mesh_children = []
	for child in node.get_children():
		if child is MeshInstance3D:
			mesh_children.append(child)
		elif child is Node3D:
			mesh_children.append_array(find_mesh_children(child))
	return mesh_children

func get_target_height(target: Node3D) -> float:
	# Get the target's height for proper positioning
	var target_height = 0.0
	
	if target is CharacterBody3D:
		var collision_shape = target.get_node_or_null("CollisionShape3D")
		if collision_shape and collision_shape.shape:
			if collision_shape.shape is BoxShape3D:
				target_height = collision_shape.shape.size.y
			elif collision_shape.shape is CapsuleShape3D:
				target_height = collision_shape.shape.height
			elif collision_shape.shape is SphereShape3D:
				target_height = collision_shape.shape.radius * 2.0
			else:
				target_height = 1.0
	
	elif target is MeshInstance3D:
		if target.mesh:
			var aabb = target.mesh.get_aabb()
			target_height = aabb.size.y
	
	else:
		var mesh_child = target.get_node_or_null("MeshInstance3D")
		if mesh_child and mesh_child.mesh:
			var aabb = mesh_child.mesh.get_aabb()
			target_height = aabb.size.y
	
	return target_height

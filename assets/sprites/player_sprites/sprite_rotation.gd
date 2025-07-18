extends Sprite3D
## Generic 2.5D billboard sprite that rotates toward camera with 16-point animation
## Attach this script directly to any Sprite3D node

var camera_3d: Camera3D

func _ready():
	# Find the active camera in the scene - works universally
	camera_3d = get_viewport().get_camera_3d()
	if not camera_3d:
		push_error("[SpriteRotation] No active camera found in scene")

func _process(_delta: float) -> void:
	if camera_3d:
		update_sprite_rotation()

func update_sprite_rotation():
	var cam_dir = (camera_3d.global_transform.origin - global_transform.origin).normalized()
	var forward = -global_transform.basis.z.normalized()

	# Project both vectors onto the horizontal XZ plane (ignore Y component)
	var cam_dir_horizontal = Vector3(cam_dir.x, 0, cam_dir.z).normalized()
	var forward_horizontal = Vector3(forward.x, 0, forward.z).normalized()

	var angle = forward_horizontal.signed_angle_to(cam_dir_horizontal, Vector3.UP)
	angle = wrapf(rad_to_deg(angle), 0, 360)
	
	var frame_index = get_frame_index(angle)
	var should_flip = should_flip_sprite(angle)
	
	# print("Angle: ", angle, " | Frame: ", frame_index, " | Flip: ", should_flip)
	
	frame = frame_index
	flip_h = should_flip

func get_frame_index(angle: float) -> int:
	angle = wrapf(angle, 0, 360)
	
	# Handle the special case for frame 8 (348.75-11.25)
	if angle >= 348.75 or angle < 11.25:
		return 8
	
	# For angles 11.25-348.75, calculate frame based on 22.5° divisions
	var frame = int((angle - 11.25) / 22.5)
	
	# Map to correct frame numbers:
	# 11.25-33.75° -> frame 7
	# 33.75-56.25° -> frame 6
	# 56.25-78.75° -> frame 5
	# 78.75-101.25° -> frame 4
	# 101.25-123.75° -> frame 3
	# 123.75-146.25° -> frame 2
	# 146.25-168.75° -> frame 1
	# 168.75-191.25° -> frame 0
	# 191.25-348.75° -> mirrored frames (handled by flip)
	
	if angle >= 11.25 and angle < 191.25:
		# Right side frames: 7, 6, 5, 4, 3, 2, 1, 0
		return 7 - frame
	else:
		# Left side frames: same as right but will be flipped
		var left_frame = int((angle - 191.25) / 22.5)
		return left_frame + 1

func should_flip_sprite(angle: float) -> bool:
	angle = wrapf(angle, 0, 360)
	
	# Flip when angle is in the left half (191.25-348.75)
	return angle >= 191.25 and angle < 348.75

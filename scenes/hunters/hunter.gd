extends CharacterBody3D

@export var nav_agent : NavigationAgent3D
@export var anim_tree : AnimationTree
@export var flashlight : Node3D
@export var detect_area : Area3D
@export var model : Node3D
@export var follow_timer: Timer

@export var GHOST_TRAP : PackedScene

@export var exit_location := Vector3.ZERO

enum STATE {
	IDLE,
	EXPLORING,
	INVESTIGATING,
	FOLLOWING,
	HUNTING,
	SCARED,
	LEAVING
}
	
const SPEED := 1.0
const JOG_SPEED := 1.3
const RUN_SPEED := 1.6
const ACCEL := 5.0
const MAX_FEAR := 100.0

const GRAVITY = -9.8

var random = null

var state = STATE.EXPLORING
var nav_point := Vector3.ZERO
var fear := 0.0
var ghost : Node3D = null
var interact : Possessable = null

var compute_first_frame := false

func _ready():
	random = RandomNumberGenerator.new()
	random.randomize()
	anim_tree.active = true

func _physics_process(delta):
	
	if (!compute_first_frame):
		compute_first_frame = true
		return	
		
	if state == STATE.LEAVING:
		var next_path_position: Vector3 = nav_agent.get_next_path_position()
		velocity = velocity.move_toward(global_position.direction_to(next_path_position) * RUN_SPEED,  delta * ACCEL)
		
		if nav_agent.is_navigation_finished():
	
			queue_free()
			
	if state == STATE.SCARED:
		if nav_agent.is_navigation_finished():
			switch_state(STATE.EXPLORING)
			
	if state == STATE.INVESTIGATING:
		var next_path_position: Vector3 = nav_agent.get_next_path_position()
		velocity = velocity.move_toward(global_position.direction_to(next_path_position) * RUN_SPEED,  delta * ACCEL)
		
		if global_position.distance_to(interact.trigger_area.global_position) < 1.5:
			switch_state(STATE.EXPLORING)
		
		if nav_agent.is_navigation_finished():		
			switch_state(STATE.EXPLORING)
		
	if state == STATE.HUNTING: # chase the ghost
		var result = ghost_raycast(ghost.global_position)
		
		if !result.has("collider") or result["collider"] != ghost:
			switch_state(STATE.FOLLOWING)
			return
		
		nav_agent.set_target_position(ghost.global_position)
		
		var next_path_position: Vector3 = nav_agent.get_next_path_position()
		
		if global_position.distance_to(ghost.global_position) < 2: # ghost is too close
			velocity = velocity.move_toward(-1 * global_position.direction_to(next_path_position) * SPEED,  delta * ACCEL * .5)	
		else:
			velocity = velocity.move_toward(global_position.direction_to(next_path_position) * RUN_SPEED,  delta * ACCEL)	
			
		var g_pos = ghost.global_position
		var new_transform = model.global_transform.looking_at(Vector3(g_pos.x, position.y, g_pos.z), Vector3.UP, true)

		model.global_transform = model.global_transform.interpolate_with(new_transform, ACCEL * delta)
		
	elif state == STATE.EXPLORING or state == STATE.FOLLOWING:
		if detect_area.has_overlapping_bodies(): # TODO decide on collison layers for ghost detection
			for body in detect_area.get_overlapping_bodies():
				if body.is_in_group("ghost"):
					var result = ghost_raycast(body.global_position)
						
					if result.has("collider") and result["collider"] == body:
						ghost = body
						switch_state(STATE.HUNTING)
						return
				 		
		if (nav_agent.is_navigation_finished()): # find a new random point to move towards
			
			var search_expand := 0.0
			while(true):
				var rand_dist = randf_range(3, 10)
				var rand_rot = PI/3 * search_expand * random.randfn()
				
				var curr_velocity_norm = velocity.normalized()
				if curr_velocity_norm == Vector3.ZERO:
					curr_velocity_norm = Vector3.BACK
				
				var target_random : Vector3 = curr_velocity_norm * rand_dist
				target_random = target_random.rotated(Vector3.UP, rand_rot) + global_transform.origin
			
				nav_agent.set_target_position(target_random)
				
				if (nav_agent.is_target_reachable()):
					break
					
				search_expand += 1.0
				
				if (search_expand > 10.0):
					return

		var next_path_position: Vector3 = nav_agent.get_next_path_position()
		var speed = SPEED
		if state == STATE.FOLLOWING:
			speed = JOG_SPEED

		velocity = velocity.move_toward(global_position.direction_to(next_path_position) * speed, delta * ACCEL)

		var p_pos = next_path_position
		
		var new_transform = model.global_transform.looking_at(Vector3(p_pos.x, position.y + 0.01 , p_pos.z), Vector3.UP, true)
		model.global_transform = model.global_transform.interpolate_with(new_transform, ACCEL * delta)
		#model.look_at(next_path_position, Vector3.UP, true) # TODO LERP

	anim_tree.set("parameters/move_anim/blend_amount", remap(velocity.length(), 0, RUN_SPEED, -1, 1))
	velocity += Vector3(0, GRAVITY * delta, 0)
	
	move_and_slide()
	
	
func ghost_raycast(ghost_pos: Vector3):
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.25, 0), 
		ghost_pos + Vector3(0, 0.25, 0), 
		0x9,  # 1 in hexadecimal for 1st collision layer
		[self])
	return space_state.intersect_ray(query)
	
func switch_state(new_state : STATE):
	if new_state == state:
		return
		
	if state == STATE.HUNTING || state == STATE.FOLLOWING || new_state == STATE.SCARED:
		ghost = null
		anim_tree.set("parameters/hold_blend/blend_amount", 0)
		flashlight.hide()
		
	if new_state == STATE.HUNTING || new_state == STATE.FOLLOWING || new_state == STATE.SCARED || new_state == STATE.LEAVING:
		anim_tree.set("parameters/hold_blend/blend_amount", 1)
		flashlight.show()	

	state = new_state


func scare(fear_amount: float, global_scare_location: Vector3):
	fear += fear_amount

	if fear >= 100.0:
		switch_state(STATE.LEAVING)
		nav_agent.set_target_position(exit_location)
		return
		
	if state != STATE.SCARED: # TODO add scare timer? continue nav away?
		switch_state(STATE.SCARED)
		
		var search_expand := 0.0
		while(true):
			var rand_dist = randf_range(5, 10)
			var rand_rot = PI/3 * search_expand * random.randfn()
			
			var reverse_scare_dir_norm = (global_position - global_scare_location).normalized()
			
			var target_random : Vector3 = reverse_scare_dir_norm * rand_dist
			target_random = target_random.rotated(Vector3.UP, rand_rot) + global_transform.origin
		
			nav_agent.set_target_position(target_random)
			
			if (nav_agent.is_target_reachable()):
				return
				
			search_expand += 1.0
			
			if (search_expand > 10.0):
				return


func _on_navigation_agent_3d_velocity_computed(safe_velocity):
	velocity = safe_velocity
	move_and_slide()
	print(velocity)


func _on_follow_timer_timeout():
	if state == STATE.FOLLOWING:
		state = STATE.EXPLORING
		anim_tree.set("parameters/hold_blend/blend_amount", 0)
		flashlight.hide()
		

func _on_interact_rand_timer_timeout():
	if state == STATE.EXPLORING:
		var possessables = ParanormalActivity.sort_by_distance(ParanormalActivity.get_possessables(), global_position)
		if possessables and possessables.size() > 0:
			switch_state(STATE.INVESTIGATING)
			interact = possessables[0]
			nav_agent.set_target_position(interact.trigger_area.global_position)
		

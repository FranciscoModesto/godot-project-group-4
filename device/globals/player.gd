tool

extends Node2D

var task
var walk_destination
var animation
var vm
var terrain
var walk_path
var walk_context
var path_ofs
export var speed = 300
export var v_speed_damp = 1.0
export(Script) var animations
var last_dir = 0
var last_scale
var pose_scale = 1
var params_queue
var camera
export var camera_limits = Rect2()

export var telekinetic = false

var anim_notify = null
var anim_scale_override = null
var sprites = []
export var placeholders = {}

func set_active(p_active):
	if p_active:
		show()
	else:
		hide()

func walk_to(pos, context = null):
	walk_path = terrain.get_path(get_pos(), pos)
	walk_context = context
	if walk_path.size() == 0:
		task = null
		params_queue = null
		walk_stop(get_pos())
		set_process(false)
		return
	walk_destination = walk_path[walk_path.size()-1]
	if terrain.is_solid(pos):
		walk_destination = walk_path[walk_path.size()-1]
	path_ofs = 0.0
	task = "walk"
	set_process(true)
	params_queue = null

func walk(pos, speed, context = null):
	walk_to(pos, context)

func anim_finished():
	if typeof(anim_notify) != typeof(null):
		vm.finished(anim_notify)
		anim_notify = null

	if typeof(anim_scale_override) != typeof(null):
		set_scale(get_scale() * anim_scale_override)
		anim_scale_override = null

	animation.play(animations.idles[last_dir])
	pose_scale = animations.idles[last_dir + 1]
	_update_terrain()

func set_speaking(p_speaking):
	if p_speaking:
		animation.play(animations.speaks[last_dir])
		pose_scale = animations.speaks[last_dir + 1]
	else:
		animation.play(animations.idles[last_dir])
		pose_scale = animations.idles[last_dir + 1]
	_update_terrain()

func _find(p_val, p_array, p_flip):
	var i = 0
	for v in p_array:
		if typeof(v) == typeof(p_val) && v == p_val:
			if p_flip == null:
				return i
			else:
				if p_array[i+1] == p_flip:
					return i

		i += 1
	return -1

func anim_get_ph_paths(p_anim):
	if !(p_anim in placeholders):
		return null

	var ret = []
	for p in placeholders[p_anim]:
		var n = get_node(p)
		if !(n extends InstancePlaceholder):
			continue
		ret.push_back(n.get_instance_path())
	return ret

func play_anim(p_anim, p_notify = null, p_reverse = false, p_flip = null):
	if typeof(p_notify) != typeof(null) && (!has_node("animation") || !get_node("animation").has_animation(p_anim)):
		vm.finished(p_notify)
		return

	if p_anim in placeholders:
		for npath in placeholders[p_anim]:
			var node = get_node(npath)
			if !(node extends InstancePlaceholder):
				continue
			var path = node.get_instance_path()
			var res = vm.res_cache.get_resource(path)
			node.replace_by_instance(res)
			_find_sprites(get_node(npath))


	pose_scale = 1
	_update_terrain()
	if p_flip != null:
		var scale = get_scale()
		set_scale(scale * p_flip)
		anim_scale_override = p_flip
	else:
		anim_scale_override = null

	if p_reverse:
		get_node("animation").play(p_anim, -1, -1, true)
	else:
		get_node("animation").play(p_anim)
		#get_node("animation").seek(0, true)

	anim_notify = p_notify
	var dir = _find(p_anim, animations.directions, p_flip.x)
	if dir == -1:
		dir = _find(p_anim, animations.idles, p_flip.x)
	if dir != -1:
		last_dir = dir

	set_process(false)

func interact(p_params):
	var pos
	if p_params[0].has_node("interact_pos"):
		pos = p_params[0].get_node("interact_pos").get_global_pos()
	else:
		pos = p_params[0].get_global_pos()
	if !telekinetic && get_global_pos().distance_to(pos) > 10:
		walk_to(pos)
		params_queue = p_params
	else:
		if animations.dir_angles.size() > 0 && p_params[0].interact_angle != -1:
			last_dir = _get_dir_deg(p_params[0].interact_angle)
			animation.play(animations.idles[last_dir])
			pose_scale = animations.idles[last_dir + 1]
			_update_terrain()
		get_tree().call_group(0, "game", "interact", p_params)

func walk_stop(pos):
	set_pos(pos)
	walk_path = []
	task = null
	set_process(false)
	if typeof(params_queue) != typeof(null):
		if animations.dir_angles.size() > 0 && params_queue[0].interact_angle != -1:
			last_dir = _get_dir_deg(params_queue[0].interact_angle)
			animation.play(animations.idles[last_dir])
			pose_scale = animations.idles[last_dir + 1]
			_update_terrain()
		else:
			animation.play(animations.idles[last_dir])
			pose_scale = animations.idles[last_dir + 1]
		get_tree().call_group(0, "game", "interact", params_queue)
	else:
		animation.play(animations.idles[last_dir])
		pose_scale = animations.idles[last_dir + 1]
	_update_terrain()
	if walk_context != null:
		vm.finished(walk_context)
		walk_context = null

func _get_dir(angle):
	var deg = rad2deg(angle) + 180
	return _get_dir_deg(deg)

func _get_dir_deg(deg):
	var dir = 0
	var i = 0
	for ang in animations.dir_angles:
		if deg < ang:
			dir = i
			break
		i+=2
	return dir


func _notification(what):
	if !get_tree() || !get_tree().is_editor_hint():
		return

	if what == CanvasItem.NOTIFICATION_TRANSFORM_CHANGED:
		call_deferred("_editor_transform_changed")

func _editor_transform_changed():
	_update_terrain()
	_check_bounds()

func _check_bounds():
	#printt("checking bouds for pos ", get_pos(), terrain.is_solid(get_pos()))
	if terrain.is_solid(get_pos()):
		if has_node("terrain_icon"):
			get_node("terrain_icon").hide()
	else:
		if !has_node("terrain_icon"):
			var node = Sprite.new()
			var tex = load("res://globals/terrain.png")
			node.set_texture(tex)
			add_child(node)
			node.set_name("terrain_icon")
		get_node("terrain_icon").show()

func _update_terrain():
	var pos = get_pos()
	var color = terrain.get_terrain(pos)
	var scale = terrain.get_scale_range(color.b)
	scale.x = scale.x * pose_scale
	#if scale != last_scale:
	if scale != get_scale():
		last_scale = scale
		set_scale(last_scale)
	color = terrain.get_light(pos)
	for s in sprites:
		s.set_modulate(color)

func _process(time):
	if task == "walk":
		var pos = get_pos()
		var old_pos = pos
		var next
		if walk_path.size() > 1:
			next = walk_path[path_ofs + 1]
		else:
			next = walk_path[path_ofs]

		var dist = speed * time * last_scale.x * last_scale.x
		var dir = (next - pos).normalized()

		# assume that x^2 + y^2 == 1, apply v_speed_damp the y axis
		#printt("dir before", dir)
		dir = dir * (dir.x * dir.x +  dir.y * dir.y * v_speed_damp)
		#printt("dir after", dir, dist)

		var new_pos
		if pos.distance_to(next) < dist:
			new_pos = next
			path_ofs += 1
		else:
			new_pos = pos + dir * dist

		if path_ofs >= walk_path.size() - 1:
			walk_stop(walk_destination)
			return

		pos = new_pos

		var angle = old_pos.angle_to_point(pos)
		set_pos(pos)

		last_dir = _get_dir(angle)

		if animation.get_current_animation() != animations.directions[last_dir]:
			animation.play(animations.directions[last_dir])
		pose_scale = animations.directions[last_dir+1]

	_update_terrain()


func teleport(obj):
	if animations.dir_angles.size() > 0 && obj.interact_angle != -1:
		last_dir = _get_dir(obj.interact_angle)
		animation.play(animations.idles[last_dir])
		pose_scale = animations.idles[last_dir + 1]

	var pos
	if obj.has_node("interact_pos"):
		pos = obj.get_node("interact_pos").get_global_pos()
	else:
		pos = obj.get_global_pos()

	set_pos(pos)
	_update_terrain()

func teleport_pos(x, y):
	set_pos(Vector2(x, y))
	_update_terrain()


func _find_sprites(p = null):
	if p.is_type("Sprite") || p.is_type("AnimatedSprite"):
		sprites.push_back(p)
	for i in range(0, p.get_child_count()):
		_find_sprites(p.get_child(i))

func _ready():

	terrain = get_parent().get_node("terrain")
	_find_sprites(self)
	if get_tree().is_editor_hint():
		return

	animation = get_node("animation")
	vm = get_tree().get_root().get_node("vm")
	vm.register_object("player", self)
	#_update_terrain();
	if has_node("animation"):
		get_node("animation").connect("finished", self, "anim_finished")

	last_scale = get_scale()
	set_process(true)

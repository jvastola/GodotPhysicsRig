extends MeshInstance3D

@export var painter: NodePath = NodePath("/root/MainScene/GridPainterTest")
@export var paint_color: Color = Color(1,0,0)
@export var brush_size: int = 1
@export var flip_v: bool = true
@export var debug_uv: bool = false

func _compute_uv_from_local_pos(mi: MeshInstance3D, lp: Vector3) -> Vector2:
	var aabb: AABB = mi.mesh.get_aabb()
	# find two axes that have non-zero size in the AABB (the surface plane)
	var axes: Array = []
	if aabb.size.x > 0.00001:
		axes.append(0)
	if aabb.size.y > 0.00001:
		axes.append(1)
	if aabb.size.z > 0.00001:
		axes.append(2)
	if axes.size() < 2:
		return Vector2(-1, -1)

	var au: int = axes[0]
	var av: int = axes[1]

	var coord_u: float = lp[au]
	var coord_v: float = lp[av]
	var pos_u: float = aabb.position[au]
	var pos_v: float = aabb.position[av]
	var size_u: float = aabb.size[au]
	var size_v: float = aabb.size[av]

	var u: float = (coord_u - pos_u) / size_u
	var v: float = (coord_v - pos_v) / size_v
	if flip_v:
		v = 1.0 - v
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)

	if debug_uv:
		push_warning("UV computed: u=%s v=%s (axes=%s) local_pos=%s aabb=%s" % [str(u), str(v), str(axes), str(lp), str(aabb)])

	return Vector2(u, v)

func _closest_point_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# From Real-Time Collision Detection (Christer Ericson)
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ap: Vector3 = p - a
	var d1: float = ab.dot(ap)
	var d2: float = ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a

	var bp: Vector3 = p - b
	var d3: float = ab.dot(bp)
	var d4: float = ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b

	var vc: float = d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v: float = d1 / (d1 - d3)
		return a + ab * v

	var cp: Vector3 = p - c
	var d5: float = ab.dot(cp)
	var d6: float = ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c

	var vb: float = d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w: float = d2 / (d2 - d6)
		return a + ac * w

	var va: float = d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var bc: Vector3 = c - b
		var w2: float = (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return b + bc * w2

	# P inside face region. Compute projection onto plane
	var denom: float = 1.0 / (ab.cross(ac).length_squared())
	var n: Vector3 = ab.cross(ac)
	var distance: float = (p - a).dot(n) / n.length()
	return p - n.normalized() * distance

func _find_triangle_uv(mi: MeshInstance3D, lp: Vector3) -> Vector2:
	var mesh := mi.mesh
	if not mesh:
		return Vector2(-1, -1)

	var best_uv: Vector2 = Vector2(-1, -1)
	var best_dist2: float = 1e30
	var uvA: Vector2 = Vector2()
	var uvB: Vector2 = Vector2()
	var uvC: Vector2 = Vector2()
	var uvA2: Vector2 = Vector2()
	var uvB2: Vector2 = Vector2()
	var uvC2: Vector2 = Vector2()
	var surf_count: int = mesh.get_surface_count()
	for s in surf_count:
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() == 0:
			continue
		var verts: PackedVector3Array = PackedVector3Array()
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			verts = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var uvs: PackedVector2Array = PackedVector2Array()
		if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] != null:
			uvs = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		var inds: PackedInt32Array = PackedInt32Array()
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			inds = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array

		if inds and inds.size() > 0:
			var tri_count: int = inds.size() / 3
			for ti in tri_count:
				var i0: int = inds[ti * 3 + 0]
				var i1: int = inds[ti * 3 + 1]
				var i2: int = inds[ti * 3 + 2]
				var a: Vector3 = verts[i0]
				var b: Vector3 = verts[i1]
				var c: Vector3 = verts[i2]
				var cp: Vector3 = _closest_point_on_triangle(lp, a, b, c)
				var d2: float = cp.distance_squared_to(lp)
				if d2 < best_dist2:
					# compute barycentric coords
					var v0: Vector3 = b - a
					var v1: Vector3 = c - a
					var v2: Vector3 = lp - a
					var d00: float = v0.dot(v0)
					var d01: float = v0.dot(v1)
					var d11: float = v1.dot(v1)
					var d20: float = v2.dot(v0)
					var d21: float = v2.dot(v1)
					var denom: float = d00 * d11 - d01 * d01
					if abs(denom) < 1e-9:
						continue
					var vv: float = (d11 * d20 - d01 * d21) / denom
					var ww: float = (d00 * d21 - d01 * d20) / denom
					var uu: float = 1.0 - vv - ww
					if uvs and uvs.size() > max(i0, max(i1, i2)):
						uvA = uvs[i0]
						uvB = uvs[i1]
						uvC = uvs[i2]
						var uv: Vector2 = uvA * uu + uvB * vv + uvC * ww
						best_uv = uv
						best_dist2 = d2
		else:
			# no indices: triangle list in vertex order
			var tri_count2: int = verts.size() / 3
			for ti in tri_count2:
				var a2: Vector3 = verts[ti * 3 + 0]
				var b2: Vector3 = verts[ti * 3 + 1]
				var c2: Vector3 = verts[ti * 3 + 2]
				var cp2: Vector3 = _closest_point_on_triangle(lp, a2, b2, c2)
				var d22: float = cp2.distance_squared_to(lp)
				if d22 < best_dist2:
					if uvs and uvs.size() >= (ti * 3 + 3):
						uvA2 = uvs[ti * 3 + 0]
						uvB2 = uvs[ti * 3 + 1]
						uvC2 = uvs[ti * 3 + 2]
					else:
						continue
					# compute barycentric
					var vv0: Vector3 = b2 - a2
					var vv1: Vector3 = c2 - a2
					var vv2v: Vector3 = lp - a2
					var dd00: float = vv0.dot(vv0)
					var dd01: float = vv0.dot(vv1)
					var dd11: float = vv1.dot(vv1)
					var dd20: float = vv2v.dot(vv0)
					var dd21: float = vv2v.dot(vv1)
					var denom2: float = dd00 * dd11 - dd01 * dd01
					if abs(denom2) < 1e-9:
						continue
					var vvv: float = (dd11 * dd20 - dd01 * dd21) / denom2
					var www: float = (dd00 * dd21 - dd01 * dd20) / denom2
					var uuu: float = 1.0 - vvv - www
					var uv2: Vector2 = uvA2 * uuu + uvB2 * vvv + uvC2 * www
					best_uv = uv2
					best_dist2 = d22

	return best_uv

func handle_pointer_event(event: Dictionary) -> void:
	# Only respond to pointer events with a local position
	if not event.has("local_position"):
		return

	# Support both press and hold depending on event fields
	var just_pressed: bool = event.has("action_just_pressed") and event["action_just_pressed"]
	var pressed: bool = event.has("action_pressed") and event["action_pressed"]
	if not just_pressed and not pressed:
		return

	var pnode := get_node_or_null(painter) as Node
	if not pnode:
		return

	var lp: Vector3 = event["local_position"]
	var mi := self as MeshInstance3D
	if not mi or not mi.mesh:
		return

	# Try triangle-level UV sampling first for accurate results on cubes and arbitrary meshes
	var uv: Vector2 = _find_triangle_uv(mi, lp)
	if uv.x < 0.0:
		# fallback to AABB-based mapping (works well for planar quads)
		uv = _compute_uv_from_local_pos(mi, lp)
		if uv.x < 0.0:
			return

	var color_to_paint: Color = paint_color
	if event.has("pointer_color") and event["pointer_color"] is Color:
		color_to_paint = event["pointer_color"]

	if pnode.has_method("paint_at_uv"):
		pnode.call_deferred("paint_at_uv", uv, color_to_paint)

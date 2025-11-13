# Mirror Rendering Reference

## Goals
- Achieve a VR-style planar mirror that accurately reproduces head pose, depth, and parallax.
- Avoid visual artifacts: warping, inversion, clipping, and wobble.
- Understand the mathematics necessary for reflecting a camera across a plane in 3D space and Godot-specific concerns.

## Core Concepts
### Plane Definition
- A mirror surface is described by a point **p** on the plane (use the mirror mesh origin) and a unit-length normal vector **n** pointing *out of* the mirror.
- For a `MeshInstance3D` whose local forward axis is `-Z`, the plane normal in world space is `-global_transform.basis.z`.

### Reflecting Points
- Given a world-space point **x**, the reflected point **x'** across plane (**p**, **n**) is:
  - `x' = x - 2 ⋅ dot(x - p, n) ⋅ n`
- This yields the mirrored camera position when **x** is the viewer's camera origin.

### Reflecting Directions
- For direction vectors (no translation), reflect via:
  - `v' = v - 2 ⋅ dot(v, n) ⋅ n`
- Apply this to the camera's forward (`-Z`) and up (`+Y`) axes. The right axis can be re-derived using a cross product to maintain orthogonality.

### Transform Composition
1. Compute main camera state:
   - Position `c`
   - Forward `f = -basis.z`
   - Up `u = basis.y`
2. Reflect position and a point along the forward ray to obtain a mirrored look target:
   - `c' = ReflectPoint(c)`
   - `t = ReflectPoint(c + f)`
3. Reflect the up vector as a direction: `u' = ReflectVector(u)`.
4. Use `look_at` with `c'`, `t`, `u'` to construct a valid orientation matrix. Godot ensures a right-handed basis while using the supplied up vector.

## Projection Considerations
- Copy `projection`, `fov` or `size`, `near`, `far`, `keep_aspect`, `cull_mask`. Mirrors need the same projection properties as the observed camera to avoid stretching.
- Keep the mirrored camera slightly offset (`c' += n * ε`) to avoid clipping exactly on the plane.
- Clamp `near` to a small positive value to prevent Z-fighting on the mirror surface.

## Rendering Pipeline in Godot
1. Create a `SubViewport` with the scene's `world_3d` and appropriate resolution.
2. Child a `Camera3D` inside the `SubViewport`; do **not** mark it current on the main viewport, only on the `SubViewport`.
3. Assign the `SubViewport` texture to a mirror material (typically `StandardMaterial3D` with high metallic, low roughness).
4. Update the mirror camera every frame with the reflected transform.

## Common Pitfalls
- **Flipped / Upside-Down Image**: Caused by basis determinant turning negative. `look_at` recomputes a valid orientation, avoiding manual determinant errors.
- **Warping / Distortion**: Occurs when the mirrored camera's projection differs or the look target is not the reflected forward point, causing a skewed frustum.
- **Black Output**: `SubViewport` lacks a `World3D`, camera not current, or user behind mirror (culling logic).
- **Precision Artifacts Near the Plane**: Push the mirrored camera slightly along the normal.

## Alternative Approaches
- **Duplicated Scene Graph**: Render a mirrored copy of the scene inside the mirror. Guarantees correct depth but doubles scene management; rarely necessary for planar mirrors.
- **Screen-Space Planar Reflection**: Advanced technique using render passes/shading to approximate reflections without an extra camera; complex but performant for multiple mirrors.

## Implementation Checklist
- [ ] Shared `world_3d`
- [ ] Mirror camera reflection math matches above
- [ ] Projection parameters copied
- [ ] Near plane clamped and camera offset slightly
- [ ] Optional debug gizmos to visualize plane normal and reflected position

Use this document as a reference when iterating on the mirror script.

# ZeroGravityController and ZeroGCameraRig Fixes Plan (Updated)

We need to address several bugs and stability issues when entering, playing in, and exiting zero-gravity (0G) mode.

## User Review Required

> [!IMPORTANT]
> - We are prioritizing a rapid visual feedback cycle: implement, you test in-game, I correct.
> - Automated unit tests are excluded from this verification cycle as they will naturally break until the complex 6-DOF Quaternion system is fully integrated.

## Proposed Changes

### ZeroG Camera Rig

#### [MODIFY] [ZeroGCameraRig.gd](file:///home/icarito/Proyectos/Odisea_Game/src/core_v2/camera/ZeroGCameraRig.gd)
- Remove `apply_orientation(yaw, pitch, roll)` which assumes global axes.
- Add `update_orientation_local(mouse_delta, sens, roll_rate, dt)` to accumulate rotations locally via Quaternions:
  ```gdscript
  var yaw_quat = Quat(Vector3.UP, -mouse_delta.x * sens)
  var pitch_quat = Quat(Vector3.RIGHT, -mouse_delta.y * sens)
  var roll_quat = Quat(Vector3.FORWARD, roll_rate * dt)
  var current_quat = transform.basis.get_rotation_quat()
  var new_quat = (current_quat * yaw_quat * pitch_quat * roll_quat).normalized()
  transform.basis = Basis(new_quat)
  ```
- Add `get_orientation_euler() -> Vector3` to extract yaw, pitch, and roll in radians from the basis in a stable manner.
- Add `set_orientation_euler(yaw, pitch, roll)` to allow initialization or external override of the rig's basis.
- Update `_apply_camera_layout()` to make the camera look at the real mesh center `(0.0, target_offset_y, 0.0)` in rig-local space instead of always looking at `(0.0, 0.0, 0.0)`. This resolves the issue where the player jumps to the opposite edge on a 180° roll (Problema 3).

### Zero Gravity Controller

#### [MODIFY] [ZeroGravityController.gd](file:///home/icarito/Proyectos/Odisea_Game/src/core_v2/player/ZeroGravityController.gd)
- Initialize `_last_sync_yaw`, `_last_sync_pitch`, and `_last_sync_roll` to track last synchronized values.
- In `step_zero_g(dt, input)`:
  - Detect if `_body.yaw`, `_body.pitch`, or `roll_angle` were changed externally, and update the rig's basis using `_camera_rig.set_orientation_euler(...)`.
  - Pass the mouse delta and roll rate to `_camera_rig.update_orientation_local(...)`.
  - Extract the new yaw, pitch, and roll from the rig using `_camera_rig.get_orientation_euler()` and synchronize them back to `_body.yaw`, `_body.pitch`, `yaw`, and `roll_angle`.
- **Fix Salto Al Salir (Problema 1)**: In `get_standard_exit_orientation()`, project the 0G camera's forward vector (`-basis.z`) onto the horizontal plane (`Y = 0`) to calculate `exit_yaw` and set `exit_pitch` as `asin(forward.normalized().y)`:
  ```gdscript
  var basis := _get_movement_basis()
  var forward := -basis.z
  # Project to horizontal plane
  var forward_h := Vector3(forward.x, 0.0, forward.z)
  var exit_yaw = atan2(-forward_h.x, -forward_h.z)
  var exit_pitch = clamp(asin(forward.normalized().y), min_p, max_p)
  ```
- Remove `_pilot_mesh_base_transform`, `_has_pilot_mesh_base_transform`, and `reset_visual_state()`.
- **Fix Rotación Mesh (Problema 4 & 5)**: Update `_update_visual_mesh()` to:
  - If not moving forward (no W input / move_vec.y >= deadzone), **do not modify** the mesh basis.
  - If moving forward, **slerp** the mesh basis towards `Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll_angle)` (no pitch included) smoothly to avoid instant snaps:
    ```gdscript
    var target_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll_angle)
    _pilot_mesh.transform.basis = _pilot_mesh.transform.basis.slerp(target_basis, clamp(smooth * dt, 0.0, 1.0))
    ```

### Controller Manager

#### [MODIFY] [ControllerManager.gd](file:///home/icarito/Proyectos/Odisea_Game/src/core_v2/player/ControllerManager.gd)
- **Fix Salto Al Entrar (Problema 1)**: In `_align_zero_g_pivot_to_standard(root)`, align both the origin AND the basis of `ZeroGCameraRig` with `_standard_camera_rig`'s current basis at the moment of switching:
  ```gdscript
  _zero_g_camera_rig.transform.origin = _standard_camera_rig.transform.origin
  _zero_g_camera_rig.transform.basis = _standard_camera_rig.transform.basis
  _zero_g_camera_rig.force_update_transform()
  ```
- Implement `_on_gravity_zone_changed(body, mode)` to receive signals from the `ZeroGravityZone`.
- In `_ready()`, dynamically find and connect to all `ZeroGravityZone`s in the `"zero_gravity_zones"` group.

### Zero Gravity Zone

#### [MODIFY] [ZeroGravityZone.gd](file:///home/icarito/Proyectos/Odisea_Game/src/core_v2/props/ZeroGravityZone.gd)
- Declare `signal gravity_zone_changed(body, mode)`.
- Add the zone to the `"zero_gravity_zones"` group in `_ready()`.
- Emit the `gravity_zone_changed` signal in `_on_body_entered` and `_on_body_exited`.
- Dynamically check and connect to the `ControllerManager` on the player body upon entry to guarantee signal delivery.

## Verification Plan

### Manual Verification
1. Launch the game in `TestScene_v2.tscn` or a scene with a `ZeroGravityZone`.
2. Walk into the 0G zone: Verify the camera transitions seamlessly without any spatial or rotation jump.
3. Fly around and rotate the mouse, press Q/E to roll: Verify mouse controls do not get disoriented post-roll.
4. Do a 180° roll: Verify the mesh does not jump to the opposite edge and the camera tracks the mesh center perfectly.
5. Move forward (W): Verify the mesh smoothly rotates (slerps) to align with the movement direction instead of snapping.
6. Exit the 0G zone: Verify the transition back to 1G is smooth, with the standard camera pointing in the same direction.

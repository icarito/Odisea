# Remote Skeleton UDP Addon for Godot 3

## 1. Overview

The `RemoteSkeletonUDP` addon provides a custom `Spatial` node for **low-latency, live motion capture (mocap) streaming** from an external source (like the Python agent **Kohai**).

It functions as a **plug-and-play** remote skeleton control. Simply add the `RemoteSkeletonUDP` node to your scene, configure its parameters, and your character will instantly mirror the poses received via UDP/JSON packets.

### Features
- **Live Mocap Integration:** Facilitates real-time streaming of bone transformations (Translation, Rotation).
- **Low Latency:** Uses UDP for minimal overhead, targeting a 60Hz update rate.
- **Resilient:** Tolerates packet loss by applying the latest available data.
- **Simple:** No external dependencies. Core logic is contained within a single GDScript file.

---

## 2. Setup and Usage

### Step 1: Enable the Addon
1. Go to `Project -> Project Settings`.
2. Navigate to the `Plugins` tab.
3. Find **"Remote Skeleton UDP"** in the list and check the **"Enable"** box.

### Step 2: Add the Node
1. Open the scene containing your character's `Skeleton`.
2. Click the `+` button to add a new node (`Ctrl+A`).
3. Search for `RemoteSkeletonUDP` and create it.

### Step 3: Configure the Node
1. Select the `RemoteSkeletonUDP` node in the scene tree.
2. In the Inspector panel, assign the `Skeleton Path` by selecting your character's `Skeleton` node.
3. Adjust the `Udp Port` to match the port your external mocap application is sending data to.
4. Tweak the `Smoothing` factor to balance latency and jitter.

---

## 3. Scene Structure

For the node to function correctly, it must be a sibling or an ancestor of the target `Skeleton` node.

**Example Hierarchy:**

```
- MyCharacter (Spatial)
  - RemoteSkeletonUDP   <-- This node
  - Armature
    - Skeleton          <-- Target skeleton, assigned in the Inspector
  - MeshInstance        <-- Your character's mesh
```

---

## 4. Inspector Parameters

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `udp_port` | `int` | `5555` | The local UDP port to listen on for incoming data. |
| `skeleton_path` | `NodePath` | `(empty)` | **(Required)** Path to the target `Skeleton` node. |
| `smoothing` | `float` | `0.1` | Linear Interpolation factor (0.0 = instant, 1.0 = max smoothing). |
| `auto_start` | `bool` | `True` | If `True`, the UDP listener starts automatically when the scene runs. |
| `heartbeat_timeout`| `float` | `2.0` | Seconds without data before the skeleton resets to T-pose. |
| `print_packets` | `bool` | `False` | Debug feature. If `True`, prints incoming JSON to the console. |
| `manual_reset_timer`| `float` | `0.0` | Debug feature. Setting to > 0 forces an immediate T-pose reset. |

---

## 5. UDP Input Format (JSON)

The external mocap agent must transmit a single JSON packet per frame via UDP.

### JSON Structure
```json
{
  "t": 1234.56,
  "h": 1.78,
  "bones": {
    "hips": [0, 1.2, 0,  0, 0, 0, 1],
    "spine": [0, 0, 0,  0, 0, 0, 1],
    "shoulder.L": [0, 0, 0,  0, 0, 0, 1]
  }
}
```
- `t` (optional): Unix timestamp.
- `h` (optional): Calibrated height/scale factor.
- `bones` (required): A dictionary where each key is a bone name.

### Bone Data Array
Each bone's value is a 7-float array representing its transform:
- `[Tx, Ty, Tz, Qx, Qy, Qz, Qw]`
  - **Translation:** `Vector3(Tx, Ty, Tz)`
  - **Rotation:** `Quat(Qx, Qy, Qz, Qw)`

The coordinate system is assumed to be Godot's standard (+Y up, +Z forward).

---

## 6. Bone Naming Convention

The bone names in the JSON `bones` dictionary **must** match the names in your Godot `Skeleton` node. The following names are recommended as they follow a common standard (Mixamo/Godot):

| Core | Left Arm | Right Arm | Left Leg | Right Leg |
| :--- | :--- | :--- | :--- | :--- |
| `hips` | `shoulder.L` | `shoulder.R` | `upperLeg.L` | `upperLeg.R` |
| `spine` | `elbow.L` | `elbow.R` | `knee.L` | `knee.R` |
| `chest` | `wrist.L` | `wrist.R` | `ankle.L` | `ankle.R` |
| `neck` | | | | |
| `head` | | | | |

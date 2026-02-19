# Project A.N.N.A. (Automated Neural Network Auditor)

A.N.N.A. is an AI agent interface designed for automated QA testing and Reinforcement Learning within the Odisea `core_v2` engine. It exposes a TCP interface to stream game state observations and receive control actions.

## Enabling the Agent

To enable the A.N.N.A. bridge, you must set the following environment variable before launching Godot:

```bash
export ANNA_ENABLED=1
```

By default, the server listens on **TCP port 5000**. You can customize this port:

```bash
export ANNA_PORT=6000
```

## Architecture

The system consists of two main components:
1.  **AnnaBridge (`core_v2/anna/AnnaBridge.gd`)**: A TCP Server that handles client connections and message framing (newline-delimited JSON).
2.  **AnnaInterface (`core_v2/anna/AnnaInterface.gd`)**: Handles gathering data from the game simulation and injecting inputs into the `PlayerController`.

## Protocol Specification

Communication uses line-delimited JSON.

### Observation Space (Output)

The server sends a JSON object every physics frame containing:

*   **`proximity`** (Array of Objects): List of interactable objects within 10m.
    *   `name`: Node name.
    *   `type`: Scene filename or type.
    *   `pos`: [x, y, z] global position.
    *   `dist`: Distance to player.
*   **`buffer`** (Array of Strings): Recent OYS-Console log entries.
*   **`metrics`** (Object): Performance telemetry.
    *   `fps`: Current frames per second.
    *   `mem_static`: Static memory usage in bytes.
    *   `objects`: Total object count.
*   **`collisions`** (Array of Floats): LIDAR-like sensor array (32 rays) representing distance to obstacles around the player (max 20m).

### Action Space (Input)

The client sends a JSON object to control the agent:

*   **`move`** (Array[float]): `[x, y]` movement vector (-1.0 to 1.0).
*   **`look`** (Array[float]): `[x, y]` look/rotation delta (emulates mouse movement).
*   **`jump`** (bool): Trigger jump.
*   **`interact`** (bool): Trigger interaction (E).
*   **`sprint`** (bool): Hold sprint.
*   **`crouch`** (bool): Hold crouch.
*   **`command`** (String, optional): Execute a raw console command (e.g., `"echo Hello"`).

## Example Client

A Python client is provided in `core_v2/anna/client/anna_client.py`.

**Usage:**

1.  Start Godot with the environment variable set.
2.  Run the client:

```bash
python3 core_v2/anna/client/anna_client.py
```

The client will connect, print stats to the terminal, and make the character perform a random walk.

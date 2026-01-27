OdysseyScript (OYS): Input and Testing DSL Specification

1. Overview

OdysseyScript is a Domain-Specific Language (DSL) designed to write deterministic player input sequences within the Odisea engine. It solves the issue of "fragile" binary replays by allowing developers to define intent (e.g., "walk for 5 seconds") instead of raw binary input buffers.

2. Structural Elements

A. Sections (SECTION ... END)

Sections group logical commands and define a success or failure context.

Isolation: They help identify exactly which part of a test failed.

Asserts: Asserts within a section validate the state upon completion of that specific section.

Reporting: The test engine logs SECTION PASSED or SECTION FAILED.

B. Sequentiality and Blocking

By default, commands are blocking. A line does not execute until the previous one completes its duration or reaches its goal.

C. The AT Modifier (Parallelism)

The AT modifier allows triggering an action while a movement command is still active.

Syntax: [COMMAND] [VALUE] AT [TIME/DIST] [ACTION]

Example: FW 5 AT 2 JUMP (Move forward 5 units, but at second 2, press Jump).

3. Command Vocabulary

| Command | Arguments | Example | Notes |
| SET | prop val | SET pos (0,0,0) | Forces player state (teleport). |
| FW / BW | value | FW 5.0 | Move Forward/Backward for X seconds or meters. |
| LT / RT | degrees | LT 90 | Rotate camera Left/Right. |
| JUMP | [time] | JUMP 0.5 | Jump. Optionally holds the button down. |
| WAIT | time | WAIT 1.0 | Character remains still (idle input). |
| LOOK | pitch | LOOK -45 | Sets the vertical camera angle. |
| INTERACT | - | INTERACT | Presses the interaction key ("E"). |
| ASSERT | cond [msg] | ASSERT pos.y > 2 | Verifies a physics or state condition. |

4. Script Example: Backflip and Precision Test

// Initial Setup
SET pos (0, 0, 0)
SET rot 0

SECTION "Backflip Validation"
    FW 4.0                 // Walk 4 seconds forward
    LOOK -20               // Look slightly down
    WAIT 0.5               // Small pause
    BW 2.0 AT 0.1 JUMP 0.3 // Start retreating and jump almost simultaneously
    LT 180                 // Turn 180 degrees upon landing
    ASSERT pos.z < -1.0    // Verify the backflip moved us backward
END

SECTION "Object Interaction"
    FW 2.0 AT 1.5 INTERACT // Walk toward an object and interact halfway
    ASSERT door_open == true "The door did not open"
END



5. Resolver Logic (Technical Implementation)

The OYS Resolver transforms these lines into a Dictionary<int, InputFrame> where each int is the absolute frame number from the start of the test.

Frame Calculation: If the engine runs at 60fps, FW 2.0 generates 120 frames with the 'W' key pressed.

Camera Smoothing: Commands like LT 180 should distribute the rotation across multiple frames to avoid "snapping" that might break timing-dependent scripts, unless an INSTANT modifier is used.

State Injection: The SET command must be applied directly to the character's Transform on the specified frame.

Assert Verification: At the end of each line or section, the resolver queries the KinematicBody properties or global variables and compares them against the script condition.

6. Integration with the Replay System

The current Odisea replay system should be able to "record" the output of an OYS script. This allows:

Writing the script (Human-readable).

Generating the replay (Deterministic buffer).

Using that replay for future regression comparisons.
extends Control

class_name Joystick

# A simple virtual joystick for touchscreens, with useful options.

# The GitHub page of the project is: https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot

# MIT License
# Copyright (c) 2018 Marco Fazio

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


# Emitted when the joystick is pressed
signal pressed

# Emitted when the joystick is released
signal released

# Emitted when the joystick's output vector changes
signal input_vector_changed(vector)

# The node with the handle texture
onready var handle = $Handle

# The node with the background texture
onready var background = $Background

# The radius of the handle
onready var handle_radius = handle.rect_size.x / 2

# The radius of the background
onready var background_radius = background.rect_size.x / 2

# The output of the joystick, a Vector2 with x and y in [-1, 1]
var output = Vector2()

# A unique id for the touch event, so multiple joysticks can be used on the same screen
var touch_id = -1

# A timer to debounce the release event
var release_timer = Timer.new()

enum JoystickMode {FIXED, DYNAMIC}
enum VisibilityMode {ALWAYS, TOUCHSCREEN_ONLY}

# The behavior of the joystick
export(JoystickMode) var joystick_mode = JoystickMode.FIXED

# The visibility of the joystick
export(VisibilityMode) var visibility_mode = VisibilityMode.ALWAYS

# If the joystick should trigger input actions
export var use_input_actions = false

# The actions to be triggered
export var action_left = "ui_left"
export var action_right = "ui_right"
export var action_up = "ui_up"
export var action_down = "ui_down"

# The size of the dead zone. If the handle is inside this range the output is zero
export(float, 0, 0.9, 0.01) var dead_zone_size = 0.2

# The max distance the handle can reach
export(float, 0, 1, 0.01) var clamp_zone_size = 0.8


func _ready():
	# If the device doesn't have a touchscreen, and the visibility mode is set to TOUCHSCREEN_ONLY
	if not OS.has_touchscreen_ui_hint() and visibility_mode == VisibilityMode.TOUCHSCREEN_ONLY:
		# hide the joystick
		hide()

	# Set absolute positions for background and handle
	background.rect_position = Vector2(0, 0)
	background.rect_size = Vector2(background_radius * 2, background_radius * 2)
	handle.rect_position = Vector2(background_radius - handle_radius, background_radius - handle_radius)
	handle.rect_size = Vector2(handle_radius * 2, handle_radius * 2)


func _input(event):
	# If the event is a touch event
	if event is InputEventScreenTouch:
		# If the event is a pressed event and no touch is being tracked
		if event.pressed and touch_id == -1:
			print("[Joystick] Press event, index: ", event.index, " pos: ", event.position)
			# If the joystick is dynamic
			if joystick_mode == JoystickMode.DYNAMIC:
				# Set the joystick position to the touch position
				set_position(event.position - Vector2(background_radius, background_radius))

			# Calculate the distance between the touch and el centro del joystick
			var distance = event.position.distance_to(background.rect_global_position + Vector2(background_radius, background_radius))
			# If the distance is in the background radius
			if distance <= background_radius:
				# Start tracking the touch
				touch_id = event.index
				print("[Joystick] Touch started, touch_id: ", touch_id)
				# Emit the pressed signal
				emit_signal("pressed")
				# The event is handled SOLO si el touch está dentro del área del joystick
				get_tree().set_input_as_handled()

		# If the event is a released event and the touch is being tracked
		elif not event.pressed and event.index == touch_id:
			# Stop tracking the touch
			touch_id = -1
			# Reset the output
			output = Vector2()
			# Emit the vector changed signal
			emit_signal("input_vector_changed", output)
			# Center the handle
			handle.rect_position = Vector2(background_radius - handle_radius, background_radius - handle_radius)
			# If the joystick is dynamic
			if joystick_mode == JoystickMode.DYNAMIC:
				# hide the joystick
				hide()
			# Emit the released signal
			emit_signal("released")
			# The event is handled SOLO si el touch era del joystick
			get_tree().set_input_as_handled()
			# Release the input actions if they are being used
			if use_input_actions:
				Input.action_release(action_left)
				Input.action_release(action_right)
				Input.action_release(action_up)
				Input.action_release(action_down)
			print("[Joystick] Touch stopped.")

	# If the event is a drag event
	if event is InputEventScreenDrag:
		# If the touch is being tracked por el joystick
		if event.index == touch_id:
			print("[Joystick] Drag event, index: ", event.index, " pos: ", event.position)
			# Calculate the vector from the center of the joystick to the touch position
			var local_event_pos = make_input_local(event).position
			var center = Vector2(background_radius, background_radius)
			var vector = local_event_pos - center
			# Clamp the vector to the clamp zone
			vector = vector.clamped(background_radius * clamp_zone_size)

			# Move the handle
			handle.rect_position = center + vector - Vector2(handle_radius, handle_radius)

			# Normalize the vector
			vector = vector / (background_radius * clamp_zone_size)

			# Apply the dead zone
			if vector.length() < dead_zone_size:
				output = Vector2()
			else:
				output = vector.normalized() * ( (vector.length() - dead_zone_size) / (1 - dead_zone_size) )

			# Emit the vector changed signal
			emit_signal("input_vector_changed", output)
			print("[Joystick] Emitted vector: ", output)
			
			# The event is handled SOLO si el drag es del joystick
			get_tree().set_input_as_handled()

			# If input actions should be used
			if use_input_actions:
				# Press/Release the correct actions based on the joystick output
				if output.x < -0.5:
					Input.action_press(action_left)
					Input.action_release(action_right)
				elif output.x > 0.5:
					Input.action_press(action_right)
					Input.action_release(action_left)
				else:
					Input.action_release(action_left)
					Input.action_release(action_right)

				if output.y < -0.5:
					Input.action_press(action_up)
					Input.action_release(action_down)
				elif output.y > 0.5:
					Input.action_press(action_down)
					Input.action_release(action_up)
				else:
					Input.action_release(action_up)
					Input.action_release(action_down)


func get_output():
	return output


func get_joystick_mode():
	return joystick_mode


func set_joystick_mode(mode):
	joystick_mode = mode


func get_visibility_mode():
	return visibility_mode


func set_visibility_mode(mode):
	visibility_mode = mode


func get_use_input_actions():
	return use_input_actions


func set_use_input_actions(use):
	use_input_actions = use


func get_action_left():
	return action_left


func set_action_left(action):
	action_left = action


func get_action_right():
	return action_right


func set_action_right(action):
	action_right = action


func get_action_up():
	return action_up


func set_action_up(action):
	action_up = action


func get_action_down():
	return action_down


func set_action_down(action):
	action_down = action


func get_dead_zone_size():
	return dead_zone_size


func set_dead_zone_size(size):
	dead_zone_size = size


func get_clamp_zone_size():
	return clamp_zone_size


func set_clamp_zone_size(size):
	clamp_zone_size = size

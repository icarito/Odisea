tool
extends WindowDialog
class_name ComplexityHelpDialog

# Plain-language help for dock metrics and status labels (Godot 3).
# Uses WindowDialog + editor theme isolation like config_dialog.

const HELP_TEXT = """Know what to fix before you hate the project.

WHAT TO DO
• Click Find what to fix.
• Start with Top fixes (red / yellow).
• Select a row and click Open (or double-click) to jump there.
• Fix the hard-to-read code, then run again.

STATUS LABELS
• OK — fine for now; no rush.
• Hard to read — getting messy; plan a cleanup.
• Fix soon — high complexity; this is where bugs and confusion grow.

CC (Cyclomatic Complexity)
Counts decision paths: if, elif, for, while, match, and similar branches.
Higher CC => more paths to test and more ways the code can behave.
Useful for: "How many routes does this function have?"

C-COG (Cognitive Complexity)
Estimates how hard the code is for a human to read and hold in their head.
Nesting (ifs inside loops inside matches) raises the score a lot.
Useful for: "Will future-me (or a teammate) hate opening this file?"
Usually more important than CC for day-to-day maintainability.

WHY BOTH?
CC is about paths / testing. C-COG is about readability.
A function can have medium CC but high C-COG if it is deeply nested.
Top fixes prefer high C-COG so you open the scary code first.

CONFIDENCE ("Pretty sure", etc.)
How sure the analyzer is that it understood the file.
Not a grade for your code quality.
Low confidence => weird syntax, parse trouble, or edge cases — treat scores carefully.
High confidence => safer to trust the numbers.

OTHER COLUMNS
• Nest — deepest indentation / nesting in the file.
• Params — most parameters on a function in that file.
• LOC — lines of code (rough size).

TREND
Compares this run to the previous saved run.
"Getting harder" means average C-COG or fail counts went up — debt is growing.

WHY THIS SCORE
Select a function (Top fixes or Project Results). The dock shows plain-language
reasons: which ifs, loops, nesting, and branches drove CC and C-COG.

IGNORE / PIN (in your .gd files)
Put a comment on the line above a function, or at the end of the func line:
• # gdmetrics:ignore — skip this function in Top fixes and fail counts
• # gdmetrics:pin — always keep it in Top fixes (your watch list)
Scores are still calculated; ignore only stops the nagging.

BIG SCARY FILES
Whole scripts that are Fix soon at file totals, or large + many hard functions.
Status Hot means that file is also recently changed in git (optional; skipped if no git).

TREND / REGRESSION
If avg C-COG rises or new Fix soon items appear vs the last run, the dock says
"Regression — project got harder."

CONFIG
Change warn/fail thresholds and which folders to scan.
Defaults are fine for most projects.
Optional: report.churn_hotspots = auto|on|off; report.churn_since (git --since).

This tool measures complexity. It does not auto-fix or lint style.
"""

var _editor_theme = null

func _init():
	window_title = "Help — what these numbers mean"
	resizable = true
	rect_min_size = Vector2(520, 480)

func _ready():
	_setup_ui()
	_apply_safe_theme()

func set_editor_theme(editor_theme):
	_editor_theme = editor_theme
	_apply_safe_theme()

func _apply_safe_theme():
	if _editor_theme != null:
		theme = _editor_theme
	else:
		theme = Theme.new()

func popup_help():
	_apply_safe_theme()
	popup_centered(Vector2(540, 500))

func _setup_ui():
	var existing = find_node("HelpRoot", true, false)
	if existing != null:
		existing.free()

	var root = MarginContainer.new()
	root.name = "HelpRoot"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.margin_left = 12
	root.margin_right = -12
	root.margin_top = 12
	root.margin_bottom = -12
	add_child(root)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 8)
	root.add_child(vbox)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.rect_min_size = Vector2(500, 380)
	vbox.add_child(scroll)

	var label = Label.new()
	label.text = HELP_TEXT
	label.autowrap = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.rect_min_size = Vector2(480, 0)
	scroll.add_child(label)

	var close_button = Button.new()
	close_button.text = "Got it"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.connect("pressed", self, "hide")
	vbox.add_child(close_button)

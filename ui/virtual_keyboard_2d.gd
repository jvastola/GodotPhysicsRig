extends Control

signal code_entered(code: String)

const KEYS = [
	"A","B","C","D","E","F","G","H","J","K","L","M","N","P","Q","R","S","T","U","V","W","X","Y","Z",
	"2","3","4","5","6","7","8","9"
]

var code := ""
var max_length := 6

func _ready():
	# Dynamically create key buttons
	var grid = GridContainer.new()
	grid.columns = 8
	add_child(grid)
	for key in KEYS:
		var btn = Button.new()
		btn.text = key
		btn.pressed.connect(_on_key_pressed.bind(key))
		grid.add_child(btn)
	# Add backspace and clear
	var backspace = Button.new()
	backspace.text = "←"
	backspace.pressed.connect(_on_backspace)
	grid.add_child(backspace)
	var clear = Button.new()
	clear.text = "Clear"
	clear.pressed.connect(_on_clear)
	grid.add_child(clear)
	# Add submit
	var submit = Button.new()
	submit.text = "Enter"
	submit.pressed.connect(_on_submit)
	grid.add_child(submit)
	# Display
	var label = Label.new()
	label.name = "CodeLabel"
	label.text = code
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(label)

func _on_key_pressed(key: String):
	if code.length() < max_length:
		code += key
		_update_label()

func _on_backspace():
	if code.length() > 0:
		code = code.left(code.length() - 1)
		_update_label()

func _on_clear():
	code = ""
	_update_label()

func _on_submit():
	emit_signal("code_entered", code)

func _update_label():
	get_node("CodeLabel").text = code

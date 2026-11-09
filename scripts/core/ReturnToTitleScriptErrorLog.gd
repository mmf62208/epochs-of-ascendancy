extends Logger

## Counts Godot script errors for HeadlessReturnToTitle1Test.
var script_errors: int = 0
var samples: PackedStringArray = PackedStringArray()


func _log_message(message: String, _error: bool) -> void:
	if message.find("SCRIPT ERROR") >= 0 or message.find("previously freed") >= 0:
		_note(message)


func _log_error(
	_function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	_error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	var blob := "%s:%d %s %s" % [file, line, code, rationale]
	if (
		blob.find("SCRIPT ERROR") >= 0
		or blob.find("previously freed") >= 0
		or blob.find("freed instance") >= 0
		or blob.find("Array[Dictionary]") >= 0
		or blob.find("Trying to assign an array") >= 0
	):
		_note(blob)


func _note(text: String) -> void:
	script_errors += 1
	if samples.size() < 6:
		samples.append(text)

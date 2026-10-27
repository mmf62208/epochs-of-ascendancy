# scripts/core/SaveReload1Io.gd
## Portable paths for SAVE-RELOAD-1 tests. Evidence never goes to a developer
## home directory. Fixtures live under res:// and load from there.
class_name SaveReload1Io
extends RefCounted

const V1_DAY0 := "res://tests/fixtures/save_reload_1/sr1test_v1_day0.json"
const DEFAULT_USER_EVIDENCE := "user://sr1_evidence/"


static func evidence_dir() -> String:
	var env := OS.get_environment("EOA_EVIDENCE_DIR").strip_edges()
	var path := ""
	if env.is_empty():
		path = ProjectSettings.globalize_path(DEFAULT_USER_EVIDENCE)
	elif env.begins_with("user://") or env.begins_with("res://"):
		path = ProjectSettings.globalize_path(env)
	else:
		path = env
	if not path.ends_with("/"):
		path += "/"
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func evidence_file(file_name: String) -> String:
	return evidence_dir() + file_name


static func v1_day0_path() -> String:
	return V1_DAY0

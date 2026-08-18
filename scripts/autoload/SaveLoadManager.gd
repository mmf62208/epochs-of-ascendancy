# scripts/autoload/SaveLoadManager.gd
## Foundational Save / Load system for Epochs of Ascendancy.
##
## This is the first implementation (v1, pragmatic scope). It provides a working
## save/load loop for the most critical runtime state so that play sessions can
## be persisted and resumed. It is explicitly designed to be extended.
##
## === SAVE FORMAT (JSON, human-readable for debugging) ===
## Root dictionary:
## {
##   "save_version": 1,                    # Integer. Bump on breaking changes.
##   "metadata": {
##     "timestamp": "2026-05-18T14:30:00", # ISO-ish from Time.get_datetime_string_from_system
##     "scenario_id": "1936",              # Future: ScenarioLoader scenario identifier
##     "player_tag": "USA",
##     "play_time_seconds": 0              # Future: accumulated real play time
##   },
##   "time": {
##     "current_date": { "year": 1937, "month": 3, "day": 12, "date_string": "..." },
##     "scenario_start_date": "1936-01-01",
##     "paused": false,
##     "time_scale": 1.0
##   },
##   "technology": {
##     "country_state": { "USA": { "completed": {...}, "active": [...], ... }, ... }
##     # Mirrors TechnologyManager.country_state exactly for now.
##   },
##   "agents": {
##     "agents": { "USA": [ {agent dicts with @export + runtime fields}, ... ], ... },
##     "networks": { "123": { network dict }, ... }   # keyed by province_id string
##   },
##   "map": {
##     "provinces": [
##       { "id": 42, "owner_tag": "GER", "controller_tag": "GER",
##         "development_level": 5, "infrastructure": 8, ... }
##     ]
##   },
##   "supply": {
##     "depots": { "42": { "stockpile": ..., "sabotage_level": ... } },
##     "division_deployments": { "german_infantry_...": { "province_id": 5, "country_tag": "GER" } }
##   },
##   "national_modifiers": {
##     "country_modifiers": { "GER": [ {effect dicts with remaining_months etc.}, ... ] }
##   },
##   "misc": {},   # Future expansion
##   "infrastructure_projects": { "version": 1, "active_projects": { "42": {project dict}, ... } }
##   "land_war": { "version": 1, "open_battles": [ battle dicts ], "marches": { fid: order },
##                 "next_seq": 1, "last_aar": {} }
## }
## }
##
## === EXTENSIBILITY CONTRACT (how other managers participate - REQUIRED READING) ===
## Any manager with runtime state worth persisting should implement:
##
##   func get_save_data() -> Dictionary:
##       return { "my_mutable_thing": my_state.duplicate(true), "version": 1, ... }
##
##   func apply_save_data(data: Dictionary) -> void:
##       if data.has("my_mutable_thing"):
##           my_state = data["my_mutable_thing"].duplicate(true)
##       # Rebuild any caches, re-emit signals so UI reacts, re-wire listeners if needed.
##       print("MyManager: state restored")
##
##   (optional) func clear_for_load() -> void:  # if you want SaveLoad to call a full reset first
##
## Then SaveLoadManager will automatically call them (see _gather_save_data and _apply).
## Put a comment in *your* file header describing exactly what your section contains.
##
## Example for a brand new manager "FooManager":
##   - Add the two funcs above.
##   - In SaveLoadManager _gather, it will be picked up if you also add a "foo" key
##     or let the manager put whatever it wants under a conventional key.
##   - Document the dict shape in FooManager.gd so future developers know what to expect.
##
## This pattern keeps SaveLoadManager small and delegates all per-system knowledge
## to the owning manager.
##
## Current implementation mixes direct access (for speed on core singletons) with the
## method pattern. All accesses are guarded.
##
## === LOAD BEHAVIOR ===
## - Assumes a compatible scenario is already loaded (Map/Supply hubs/provinces exist).
## - Performs targeted clears on mutable runtime state before applying.
## - Applies in a deliberate order: Time → Map provinces → Supply depots → NMM effects
##   → Technology → Agents (networks reference provinces + agents).
## - Existing signals (province_data_changed, research_state_changed, etc.) are used
##   so UI, overlays, and daily ticks react correctly after load.
## - Does NOT re-advance time or fire daily ticks during load (avoids double-processing).
##
## === WHAT IS SAVED (current full state) ===
## - Time (date, start date, pause/scale)
## - Technology (full country research state + active progress)
## - Agents + Networks (full resources + daily effect trackers)
## - Map provinces (owner/controller, development, infrastructure)
## - Supply depots (stockpile, throughput, sabotage_level) + division_deployments
## - Leader formations (stationed_province_id per division)
## - NationalModifierManager temporary effects
## - Scenario metadata (scenario_id captured on save via ScenarioLoader.get_current_scenario_name(); richer metadata added in 0.2-dev: last_played, game_version)
## - Production (stance, national stockpiles/equipment, per-line progress/retooling/shortage state)
## - Factories (full Factory resources: damage, owner, retooling, assigned lines, efficiencies)
## - Leaders (full Leader resources + XP/status/assignments/traits, national positions, officer training, pending retirements/replacements)
## - Design lifecycle (if DesignManager provides it)
## - InfrastructureDevelopmentManager (active provincial investment projects only; dev/infra levels live under "map")
## - Land war loop (open multi-day battles + FormationMovement own-land march queues + last AAR)
##
## Metadata structure (in every save root["metadata"]):
##   timestamp, scenario_id, player_tag, last_played, game_version, play_time_seconds (0 for now)
##
## === LIMITATIONS / WHAT IS NOT SAVED YET ===
## - Combat presence beyond open land battles / march queues (intel caches, air/naval in-flight)
## - Most NationalSpirit / doctrine beyond Tech
## - UI caches, camera, selection state
## - Mod or highly transient data
## - Comprehensive migration for very old saves (basic stub exists; see _migrate_save_data)
## - (Note: "design_lifecycle" section is opportunistically saved if DesignManager provides it)
##
## These can (and should) be added by implementing the two methods below on the manager.
##
## File location: user://saves/<slot>.json  (persistent, cross-session)
## Slots are simple names (quicksave, slot1, autosave_1937-03, etc.).
##
## Usage from code / debug:
##   SaveLoadManager.save_game("quicksave")
##   SaveLoadManager.load_game("quicksave")
##   var saves := SaveLoadManager.list_saves()   # Rich data for future menu
##
## Future Save Menu UI should rely on:
##   - list_saves() → rich [{slot, path, metadata: {timestamp, scenario_id, last_played, game_version, ...}}]
##   - delete_save(slot), rename_save(old, new) for management
##   - save_game_detailed / load_game_detailed for error objects + consistent toasts
##   - get_saved_scenario_id(slot) / check_scenario_compatibility(slot) for validation
##   - get_save_path, quicksave/quickload for convenience
##   - _migrate_save_data hook for version upgrades
##
## The existing TopInfoBar code-driven "Save Manager" popup already demonstrates
## these APIs (list + load + delete).
##
## Authoring note: Keep this file relatively small. Heavy per-system logic belongs
## in the managers' get/apply methods.

extends Node

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 1
const SAVE_GAME_VERSION := "0.2-dev"   # Bumped for richer metadata support
const DEFAULT_SLOT := "quicksave"

var _last_save_path: String = ""

func _ready() -> void:
	_ensure_save_dir()
	print("SaveLoadManager: Initialized (JSON format v%d, user://saves/)" % SAVE_VERSION)

	# Year boundary + every 7 calendar days (20–60d 1936 never hits a year tick).
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_year_advanced_for_autosave):
			TimeManager.game_year_advanced.connect(_on_year_advanced_for_autosave)
		if TimeManager.has_signal("game_day_advanced") \
				and not TimeManager.game_day_advanced.is_connected(_on_day_advanced_for_autosave):
			TimeManager.game_day_advanced.connect(_on_day_advanced_for_autosave)

func _on_day_advanced_for_autosave(_year: int = 0, _month: int = 0, _day: int = 0) -> void:
	if OS.get_environment("EOA_CALENDAR_AUTOSAVE").strip_edges() == "0":
		return
	var elapsed := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		elapsed = int(TimeManager.get_total_days_elapsed())
	if elapsed <= 0 or (elapsed % 7) != 0:
		return
	var res := save_game_detailed("autosave")
	if res.get("ok", false):
		print("SaveLoadManager: Calendar autosave day=%d -> autosave.json" % elapsed)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Autosaved · day %d" % elapsed, 2.0)
	else:
		push_warning("SaveLoadManager: Calendar autosave failed: %s" % res.get("error", "unknown"))

func _on_year_advanced_for_autosave(_year: int) -> void:
	# Autosave to a fixed slot; keeps only the latest autosave for simplicity.
	# Silent on success (print only), non-spammy toast on failure.
	var res := save_game_detailed("autosave")
	if res.get("ok", false):
		print("SaveLoadManager: Autosaved on year change -> autosave.json")
	else:
		push_warning("SaveLoadManager: Autosave failed: %s" % res.get("error", "unknown"))
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Autosave failed", 2.0, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		# Light autosave on quit / exit to main menu (non-intrusive, best-effort).
		# Guard against double-fire during shutdown.
		if not has_meta("autosave_on_quit_done"):
			set_meta("autosave_on_quit_done", true)
			var res := save_game_detailed("autosave")
			if res.get("ok", false):
				print("SaveLoadManager: Autosaved on exit/quit -> autosave.json")
			else:
				push_warning("SaveLoadManager: Quit autosave failed: %s" % res.get("error", "unknown"))
				# No toast on shutdown to avoid UI issues
		# Do not block exit

## OS absolute path for user://saves/ (DirAccess absolute APIs are flaky with user:// alone).
func get_saves_dir_global() -> String:
	return ProjectSettings.globalize_path(SAVE_DIR)


func _ensure_save_dir() -> void:
	var global_dir := get_saves_dir_global()
	# Prefer user:// relative open; fall back to globalized absolute.
	var exists := DirAccess.dir_exists_absolute(SAVE_DIR) or DirAccess.dir_exists_absolute(global_dir)
	if not exists:
		var err := DirAccess.make_dir_recursive_absolute(global_dir)
		if err != OK:
			# Second try with user:// form
			err = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			push_error("SaveLoadManager: Failed to create saves dir: %s (global=%s err=%d)" % [SAVE_DIR, global_dir, err])
		else:
			print("SaveLoadManager: Created saves dir → %s" % global_dir)
	# Verify we can open it
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		push_error("SaveLoadManager: Cannot open saves dir after ensure: %s" % SAVE_DIR)


func get_save_path(slot_name: String) -> String:
	var safe := _sanitize_slot(slot_name)
	return SAVE_DIR + safe + ".json"


func get_save_path_global(slot_name: String) -> String:
	return ProjectSettings.globalize_path(get_save_path(slot_name))


func _sanitize_slot(slot_name: String) -> String:
	var safe := slot_name.strip_edges().to_lower()
	safe = safe.replace(" ", "_").replace("/", "_").replace("\\", "_").replace(":", "_")
	var cleaned := ""
	for i in safe.length():
		var ch := safe[i]
		var code := ch.unicode_at(0)
		var is_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if is_alnum or ch == "_" or ch == "-":
			cleaned += ch
	if cleaned.is_empty():
		cleaned = DEFAULT_SLOT
	return cleaned

## Returns rich data for a future save menu UI:
##   [{ "slot": "quicksave", "path": "...", "metadata": {
##        "timestamp": "...", "scenario_id": "1936", "player_tag": "USA",
##        "last_played": "...", "game_version": "0.2-dev", "play_time_seconds": 0, ...
##   }}]
## Sorted newest first by timestamp/last_played.
## Future menu should use this + delete_save/rename_save + detailed save/load for errors/toasts.
func list_saves() -> Array[Dictionary]:
	_ensure_save_dir()
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		# Fallback: absolute path
		dir = DirAccess.open(get_saves_dir_global())
	if dir == null:
		push_warning("SaveLoadManager: list_saves — cannot open %s" % SAVE_DIR)
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full := SAVE_DIR + file_name
			var slot := file_name.get_basename()
			var meta := _peek_metadata(full)
			result.append({ "slot": slot, "path": full, "metadata": meta })
		file_name = dir.get_next()
	dir.list_dir_end()
	# Sort by timestamp desc if present
	result.sort_custom(func(a, b):
		var ta := str(a.get("metadata", {}).get("timestamp", ""))
		var tb := str(b.get("metadata", {}).get("timestamp", ""))
		return ta > tb
	)
	return result


## Fixed browser slots always shown in Save Manager (empty vs occupied).
const BROWSER_SLOTS: PackedStringArray = [
	"quicksave", "autosave", "slot1", "slot2", "slot3", "slot4", "slot5"
]


## Player-facing slot list: fixed empty slots + occupied files from list_saves().
## Each row: slot, occupied, status, label, can_load, can_save, api_save, api_load, metadata.
## Load/save actions must use save_game_detailed / load_game_detailed (not reimplemented).
func list_slots_for_ui() -> Array[Dictionary]:
	var occupied: Dictionary = {}  # slot -> entry from list_saves
	for e in list_saves():
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var s := str(e.get("slot", "")).strip_edges()
		if s.is_empty():
			continue
		occupied[s] = e
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot in BROWSER_SLOTS:
		var name := str(slot).strip_edges()
		if name.is_empty() or seen.has(name):
			continue
		seen[name] = true
		if occupied.has(name):
			rows.append(_format_slot_ui_row(name, true, occupied[name].get("metadata", {})))
		else:
			rows.append(_format_slot_ui_row(name, false, {}))
	# Extra discovered slots
	var extras: Array = []
	for s in occupied.keys():
		if seen.has(str(s)):
			continue
		extras.append(occupied[s])
	extras.sort_custom(func(a, b):
		var ta := str(a.get("metadata", {}).get("timestamp", a.get("metadata", {}).get("last_played", "")))
		var tb := str(b.get("metadata", {}).get("timestamp", b.get("metadata", {}).get("last_played", "")))
		return ta > tb
	)
	for e in extras:
		var sn := str(e.get("slot", ""))
		rows.append(_format_slot_ui_row(sn, true, e.get("metadata", {})))
	return rows


func _format_slot_ui_row(slot: String, occupied: bool, metadata: Variant) -> Dictionary:
	var meta: Dictionary = metadata if typeof(metadata) == TYPE_DICTIONARY else {}
	var name := slot.strip_edges()
	if name.is_empty():
		name = "unnamed"
	var label := ""
	var status := "empty"
	if occupied:
		status = "occupied"
		var bits: PackedStringArray = [name]
		var scenario := str(meta.get("scenario_id", "")).strip_edges()
		var player := str(meta.get("player_tag", "")).strip_edges().to_upper()
		var ts := str(meta.get("timestamp", meta.get("last_played", "")))
		if not scenario.is_empty():
			bits.append(scenario)
		if not player.is_empty():
			bits.append(player)
		if not ts.is_empty():
			bits.append(ts.substr(0, mini(16, ts.length())))
		label = " · ".join(bits)
	else:
		label = "%s · empty" % name
	return {
		"slot": name,
		"occupied": occupied,
		"status": status,
		"label": label,
		"metadata": meta.duplicate(true) if not meta.is_empty() else {},
		"can_load": occupied,
		"can_save": true,
		"api_save": "save_game_detailed",
		"api_load": "load_game_detailed",
	}

func _peek_metadata(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d.get("metadata", {}) as Dictionary

func save_game(slot_name: String = DEFAULT_SLOT) -> bool:
	var path := get_save_path(slot_name)
	var data := _gather_save_data()
	var json_text := JSON.stringify(data, "\t")   # Pretty for human debugging

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err_msg = "Save failed: cannot write " + path
		push_error("SaveLoadManager: " + err_msg)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(err_msg, 3.0, true)  # error style if supported
		return false
	f.store_string(json_text)
	f.close()

	_last_save_path = path
	print("SaveLoadManager: Game saved → %s (v%d, %d bytes)" % [path, SAVE_VERSION, json_text.length()])

	# Consistent non-intrusive feedback
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Game saved (" + slot_name + ")", 2.0)

	return true

func load_game(slot_name: String = DEFAULT_SLOT) -> bool:
	var path := get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		var err_msg = "Load failed: file not found " + path
		push_error("SaveLoadManager: " + err_msg)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(err_msg, 3.0, true)
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SaveLoadManager: Cannot open %s for reading" % path)
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveLoadManager: Corrupt save file (root not a Dictionary)")
		return false

	var data: Dictionary = parsed
	var file_version := int(data.get("save_version", 0))
	if file_version > SAVE_VERSION:
		push_warning("SaveLoadManager: Save is v%d (current v%d). Best-effort load may drop fields." % [file_version, SAVE_VERSION])

	_apply_save_data(data)
	print("SaveLoadManager: Game loaded ← %s (v%d)" % [path, file_version])

	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Game loaded (" + slot_name + ")", 2.5)

	return true

## === INTERNAL GATHER / APPLY ===

func _find_scenario_loader() -> ScenarioLoader:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var loader_node: Node = tree.root.find_child("ScenarioLoader", true, false)
	return loader_node as ScenarioLoader


func _gather_save_data() -> Dictionary:
	var data := {
		"save_version": SAVE_VERSION,
		"metadata": {
			"timestamp": Time.get_datetime_string_from_system(true),
			"scenario_id": "1936",
			"player_tag": "USA",
			"play_time_seconds": 0,
			"game_version": SAVE_GAME_VERSION,
		},
		"time": {},
		"technology": {},
		"agents": {},
		"map": {},
		"supply": {},
		"national_modifiers": {},
		"leaders": {},
		"infrastructure_projects": {},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
		"production": {},
		"misc": {},
	}

	# --- TimeManager ---
	if typeof(TimeManager) != TYPE_NIL:
		data["time"] = {
			"current_date": TimeManager.get_current_date(),
			"scenario_start_date": TimeManager.get_scenario_start_date(),
			"paused": TimeManager.is_paused(),
			"time_scale": TimeManager.time_scale,
			"total_days_elapsed": TimeManager.get_total_days_elapsed(),
		}

	# --- TechnologyManager ---
	if typeof(TechnologyManager) != TYPE_NIL:
		if TechnologyManager.has_method("get_save_data"):
			data["technology"] = TechnologyManager.get_save_data()
		else:
			data["technology"] = {
				"country_state": TechnologyManager.country_state.duplicate(true)
			}

	# --- AgentManager ---
	if typeof(AgentManager) != TYPE_NIL:
		data["agents"] = _serialize_agent_state()

	# --- MapManager ---
	if typeof(MapManager) != TYPE_NIL:
		data["map"] = _serialize_map_state()

	# --- WeatherManager (snow coverage from layers + sim, ground_state, events, power blackouts; snow_potential on provinces is in map state) ---
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_save_state"):
			data["weather"] = WeatherManager.get_save_state()
		else:
			data["weather"] = {}

	# --- SupplyManager ---
	if typeof(SupplyManager) != TYPE_NIL:
		data["supply"] = _serialize_supply_state()

	# --- NationalModifierManager ---
	if typeof(NationalModifierManager) != TYPE_NIL:
		data["national_modifiers"] = {
			"country_modifiers": NationalModifierManager.country_modifiers.duplicate(true)
		}

	# --- Scenario metadata ---
	var scenario_name := ""
	var loader := _find_scenario_loader()
	if loader != null:
		scenario_name = loader.get_current_scenario_name()
	data["metadata"]["scenario_id"] = scenario_name

	# Richer metadata for future save menu (timestamp already set above, scenario captured)
	data["metadata"]["last_played"] = Time.get_datetime_string_from_system(true)
	data["metadata"]["game_version"] = SAVE_GAME_VERSION
	# play_time_seconds left as 0 for now (future: accumulate in _ready or day ticks)

	# --- Production + Factories ---
	if typeof(ProductionManager) != TYPE_NIL:
		if ProductionManager.has_method("get_save_data"):
			data["production"] = ProductionManager.get_save_data()
		else:
			data["production"] = {}

	if typeof(FactoryManager) != TYPE_NIL:
		if FactoryManager.has_method("get_save_data"):
			data["factories"] = FactoryManager.get_save_data()
		else:
			data["factories"] = {}

	if typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("get_save_data"):
		data["design_lifecycle"] = DesignManager.get_save_data()

	if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_save_data"):
		data["trade"] = TradeManager.get_save_data()

	if typeof(SpaceLayerManager) != TYPE_NIL and SpaceLayerManager.has_method("get_save_data"):
		data["space_layer"] = SpaceLayerManager.get_save_data()

	# --- GameData (demographic/policy state for Ascendancy Initiatives, Policy/Law screen, Trust Erosion, manpower, relocation/settlement) ---
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_save_data"):
		data["game_data"] = GameData.get_save_data()

	# --- Leaders ---
	if typeof(LeaderManager) != TYPE_NIL:
		if LeaderManager.has_method("get_save_data"):
			data["leaders"] = LeaderManager.get_save_data()
		else:
			data["leaders"] = {}

	# --- Infrastructure Development (active projects only; levels are in "map") ---
	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		if InfrastructureDevelopmentManager.has_method("get_save_data"):
			data["infrastructure_projects"] = InfrastructureDevelopmentManager.get_save_data()
		else:
			data["infrastructure_projects"] = {}

	# --- Open land battles + own-land march queues (L1 war loop continuity) ---
	var land_war := {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}}
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_save_data"):
		var bm_blob: Dictionary = BattleManager.get_save_data()
		land_war["open_battles"] = bm_blob.get("open_battles", [])
		land_war["next_seq"] = int(bm_blob.get("next_seq", 1))
		land_war["last_aar"] = bm_blob.get("last_aar", {})
	if typeof(FormationMovement) != TYPE_NIL:
		var fm_blob: Dictionary = FormationMovement.get_save_data()
		land_war["marches"] = fm_blob.get("marches", {})
	data["land_war"] = land_war

	# --- Province Editor (in-game map design tool - debug only, persists drawn provinces across saves) ---
	# Uses the get_save_data/apply interface like other managers.
	var pe := get_tree().get_first_node_in_group("province_editor")
	if pe and pe.has_method("get_save_data"):
		data["province_editor"] = pe.get_save_data()

	# --- Pass 22: MapRenderer UI (compare slots, tint intensities, last mapmode) ---
	var mr_save := get_tree().get_first_node_in_group("map_renderer") if get_tree() != null else null
	if mr_save and mr_save.has_method("get_save_data"):
		data["map_ui"] = mr_save.get_save_data()

	# --- Pass 24: RelationsManager (formal alliances / guarantees / CRS pairs) ---
	if typeof(RelationsManager) != TYPE_NIL and RelationsManager.has_method("get_save_data"):
		data["relations"] = RelationsManager.get_save_data()

	return data


func _apply_save_data(data: Dictionary) -> void:
	# Deliberate order matters because of cross-references and signal side-effects.

	# 1. Time (affects many yearly/monthly trackers)
	if data.has("time") and typeof(TimeManager) != TYPE_NIL:
		_apply_time_state(data["time"])

	# 2. Map provinces (owner/controller/dev/infra + now settlement/built_road/rail for Phase 3 persistence) — triggers province_data_changed + MapRenderer tints/inspector/layers
	if data.has("map") and typeof(MapManager) != TYPE_NIL:
		var map_check: Dictionary = validate_map_save_payload(data["map"] as Dictionary, data)
		if not bool(map_check.get("ok", false)):
			push_warning("SaveLoad: map payload missing keys %s (continuing best-effort)" % str(map_check.get("missing", [])))
		_apply_map_state(data["map"])
		# Re-init hook for MapManager/MapRenderer on load (per WORLD_CLASS_MAP_ROADMAP Phase 3): force full refresh so runtime province state (settlement_level, built_* from actions) + owner changes survive roundtrip and drive live visuals on 460-prov map. Uses existing force + emit listeners.
		var mr_refresh := get_tree().get_first_node_in_group("map_renderer") if get_tree() != null else null
		if mr_refresh == null:
			mr_refresh = get_node_or_null("/root/WorldMap")
		if mr_refresh and mr_refresh.has_method("force_full_map_refresh"):
			mr_refresh.call_deferred("force_full_map_refresh")
		elif mr_refresh and mr_refresh.has_method("_refresh_province_fill_colors"):
			mr_refresh.call_deferred("_refresh_province_fill_colors")
		# Also nudge MapManager for pick/centroid if needed post heavy apply (safe no-op if no method)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("_recompute_centroids_and_bounds"):
			MapManager.call("_recompute_centroids_and_bounds")

	# Weather after map (provinces) + time; restores dynamic snow/ground/events from save (layer snow_potential re-applied via provinces on load)
	if data.has("weather") and typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("load_save_state"):
			WeatherManager.load_save_state(data["weather"])

	# Re-apply regional control bonuses (full control effects on supply throughput, production output via factory_output etc.) after owners/provinces restored
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
		SupplyManager._apply_regional_control_throughput_bonuses()
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("clear_all_caches"):
		ProductionManager.clear_all_caches()

	# 2b. Active infrastructure / development projects (must be after map provinces exist)
	var infra_data := _get_infrastructure_save_data(data)
	if not infra_data.is_empty() and typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		if InfrastructureDevelopmentManager.has_method("apply_loaded_data"):
			InfrastructureDevelopmentManager.apply_loaded_data(infra_data)
		# Explicit visual refresh pass after load (as requested for map overlays / InfoPanel)
		if InfrastructureDevelopmentManager.has_method("refresh_all_project_visuals"):
			InfrastructureDevelopmentManager.refresh_all_project_visuals()
		if InfrastructureDevelopmentManager.has_method("initialize_with_time"):
			InfrastructureDevelopmentManager.initialize_with_time()

	# 3. Supply depots only (deployments after leaders — step 7b)
	if data.has("supply") and typeof(SupplyManager) != TYPE_NIL:
		_apply_supply_depots_state(data["supply"])

	# 4. National modifiers (daily agent sabotage effects etc.)
	if data.has("national_modifiers") and typeof(NationalModifierManager) != TYPE_NIL:
		_apply_national_modifier_state(data["national_modifiers"])

	# 5. Technology research state + unlocks
	if data.has("technology") and typeof(TechnologyManager) != TYPE_NIL:
		_apply_technology_state(data["technology"])

	# 6. Agents + Networks (reference provinces + lead agents)
	if data.has("agents") and typeof(AgentManager) != TYPE_NIL:
		_apply_agent_state(data["agents"])

	# 7. Leaders (formations include stationed_province_id)
	if data.has("leaders") and typeof(LeaderManager) != TYPE_NIL:
		_apply_leader_state(data["leaders"])

	# 7b. Division map deployments (after leaders; syncs CombatPresenceRegistry engineers)
	if data.has("supply") and typeof(SupplyManager) != TYPE_NIL:
		_apply_supply_deployments_state(data["supply"])

	# 7c. Open land battles + march queues (after formations exist)
	if data.has("land_war") and data["land_war"] is Dictionary:
		var lw: Dictionary = data["land_war"]
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("apply_save_data"):
			BattleManager.apply_save_data({
				"open_battles": lw.get("open_battles", []),
				"next_seq": int(lw.get("next_seq", 1)),
				"last_aar": lw.get("last_aar", {}),
			})
		if typeof(FormationMovement) != TYPE_NIL:
			FormationMovement.apply_save_data({"marches": lw.get("marches", {})})

	# 8. Production + Factories (factories feed lines; apply after map provinces)
	if data.has("factories") and typeof(FactoryManager) != TYPE_NIL:
		_apply_factory_state(data["factories"])
		if FactoryManager.has_method("reconcile_factory_owners_with_map"):
			FactoryManager.reconcile_factory_owners_with_map()
	if data.has("production") and typeof(ProductionManager) != TYPE_NIL:
		_apply_production_state(data["production"])

	if data.has("design_lifecycle") and typeof(DesignManager) != TYPE_NIL:
		if DesignManager.has_method("apply_save_data"):
			DesignManager.apply_save_data(data["design_lifecycle"])

	if data.has("trade") and typeof(TradeManager) != TYPE_NIL:
		if TradeManager.has_method("apply_save_data"):
			TradeManager.apply_save_data(data["trade"])
		# Re-apply regional convoy bonuses to trade flows post-load (full control may have changed; re-assign routes for updated risk)
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
			SupplyManager._apply_regional_control_throughput_bonuses()
		if typeof(TradeManager) != TYPE_NIL:
			for f in TradeManager.get_active_trade_flows():
				if f and TradeManager.has_method("_try_assign_supply_route_to_flow"):
					TradeManager._try_assign_supply_route_to_flow(f)

	if data.has("space_layer") and typeof(SpaceLayerManager) != TYPE_NIL:
		if SpaceLayerManager.has_method("apply_save_data"):
			SpaceLayerManager.apply_save_data(data["space_layer"])

	# --- GameData demographic/policy state (after core managers) ---
	if data.has("game_data") and typeof(GameData) != TYPE_NIL:
		if GameData.has_method("clear_for_load"):
			GameData.clear_for_load()
		if GameData.has_method("apply_save_data"):
			GameData.apply_save_data(data["game_data"])

	# --- Province Editor (debug map design persistence) ---
	if data.has("province_editor"):
		var pe := get_tree().get_first_node_in_group("province_editor")
		if pe and pe.has_method("apply_save_data"):
			pe.apply_save_data(data["province_editor"])

	# --- Pass 22: MapRenderer UI (compare slots / intensities / mapmode) ---
	if data.has("map_ui"):
		var mr_load := get_tree().get_first_node_in_group("map_renderer") if get_tree() != null else null
		if mr_load and mr_load.has_method("apply_save_data"):
			mr_load.apply_save_data(data["map_ui"])

	# --- Pass 24: RelationsManager alliances / guarantees ---
	if data.has("relations") and typeof(RelationsManager) != TYPE_NIL:
		if RelationsManager.has_method("apply_save_data"):
			RelationsManager.apply_save_data(data["relations"])

	# Future: after all core state, allow other managers to react
	# e.g. if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("on_game_loaded"):
	#     ProductionManager.on_game_loaded()

## --- Time ---

func _apply_time_state(t: Dictionary) -> void:
	if t.has("current_date"):
		var d: Dictionary = t["current_date"]
		TimeManager.current_year = int(d.get("year", 1936))
		TimeManager.current_month = int(d.get("month", 1))
		TimeManager.current_day = int(d.get("day", 1))
	if t.has("scenario_start_date"):
		TimeManager.scenario_start_date = str(t["scenario_start_date"])
	if t.has("paused"):
		TimeManager.set_paused(bool(t["paused"]))
	if t.has("time_scale"):
		TimeManager.set_time_scale(float(t.get("time_scale", 1.0)))
	if t.has("total_days_elapsed"):
		TimeManager.total_days_elapsed = maxi(0, int(t.get("total_days_elapsed", 0)))
	# Do not fire game_day_advanced etc. here — we are restoring state, not simulating.

## --- Agents (most complex because of Resource instances) ---

func _serialize_agent_state() -> Dictionary:
	var out := { "agents": {}, "networks": {} }

	# Agents
	for ctag in AgentManager.agents.keys():
		var list: Array = []
		for a in (AgentManager.agents[ctag] as Array):
			if a is Agent:
				list.append(_agent_to_dict(a))
		out["agents"][ctag] = list

	# Networks
	for pid in AgentManager.networks.keys():
		var net: AgentNetwork = AgentManager.networks[pid]
		if net != null:
			out["networks"][str(pid)] = _network_to_dict(net)

	return out

func _agent_to_dict(a: Agent) -> Dictionary:
	# Use inst_to_dict for all @export fields, then add runtime non-exported ones
	var d: Dictionary = inst_to_dict(a)
	d["compromised_until_year"] = a.compromised_until_year
	d["assigned_province_id"] = a.assigned_province_id
	d["total_missions_completed"] = a.total_missions_completed
	d["successful_missions"] = a.successful_missions
	d["mission_history"] = (a.mission_history as Array).duplicate(true)
	d["traits"] = (a.traits as Array).duplicate()
	return d

func _dict_to_agent(d: Dictionary) -> Agent:
	var a := Agent.new()
	# Core identity / stats (@export + runtime)
	a.agent_id = str(d.get("agent_id", ""))
	a.name = str(d.get("name", ""))
	a.country_tag = str(d.get("country_tag", ""))
	a.level = int(d.get("level", 1))
	a.experience = int(d.get("experience", 0))
	a.intelligence = int(d.get("intelligence", 4))
	a.sabotage = int(d.get("sabotage", 4))
	a.influence = int(d.get("influence", 4))
	a.technology = int(d.get("technology", 4))
	a.counter_intelligence = int(d.get("counter_intelligence", 3))
	a.status = str(d.get("status", "available"))
	a.current_mission_id = str(d.get("current_mission_id", ""))
	a.mission_progress = float(d.get("mission_progress", 0.0))
	a.assigned_target_tag = str(d.get("assigned_target_tag", ""))
	a.assigned_target_tech_id = str(d.get("assigned_target_tech_id", ""))
	a.birth_year = int(d.get("birth_year", 1900))
	a.start_year = int(d.get("start_year", 1930))
	a.portrait_path = str(d.get("portrait_path", ""))

	# Runtime
	a.compromised_until_year = int(d.get("compromised_until_year", 0))
	a.assigned_province_id = int(d.get("assigned_province_id", 0))
	a.total_missions_completed = int(d.get("total_missions_completed", 0))
	a.successful_missions = int(d.get("successful_missions", 0))
	a.mission_history = (d.get("mission_history", []) as Array).duplicate(true)
	var raw_t = d.get("traits", [])
	a.traits = []
	if raw_t is Array:
		for t in raw_t:
			a.traits.append(str(t))

	return a

func _network_to_dict(net: AgentNetwork) -> Dictionary:
	var d: Dictionary = inst_to_dict(net)
	# Add runtime daily trackers
	d["total_intel_gathered"] = net.total_intel_gathered
	d["total_disruption_caused"] = net.total_disruption_caused
	d["last_daily_note"] = net.last_daily_note
	d["last_daily_effect"] = net.last_daily_effect
	d["last_daily_effect_scalar"] = net.last_daily_effect_scalar
	return d

func _dict_to_network(d: Dictionary) -> AgentNetwork:
	var net := AgentNetwork.new()
	net.network_id = str(d.get("network_id", ""))
	net.province_id = int(d.get("province_id", 0))
	net.controlling_country = str(d.get("controlling_country", ""))
	net.lead_agent_id = str(d.get("lead_agent_id", ""))
	net.strength = float(d.get("strength", 0.0))
	net.local_operatives = int(d.get("local_operatives", 0))
	net.focus = str(d.get("focus", "intelligence"))
	net.last_activity_month = int(d.get("last_activity_month", 0))
	net.detection_risk_accumulated = float(d.get("detection_risk_accumulated", 0.0))

	# Runtime
	net.total_intel_gathered = int(d.get("total_intel_gathered", 0))
	net.total_disruption_caused = float(d.get("total_disruption_caused", 0.0))
	net.last_daily_note = str(d.get("last_daily_note", ""))
	net.last_daily_effect = str(d.get("last_daily_effect", ""))
	net.last_daily_effect_scalar = float(d.get("last_daily_effect_scalar", 0.0))
	return net

func _apply_agent_state(a: Dictionary) -> void:
	# Clear existing runtime agent state
	AgentManager.agents.clear()
	AgentManager.networks.clear()
	AgentManager._agent_screen_cache.clear()

	# Restore agents
	var agents_by_country: Dictionary = a.get("agents", {}) as Dictionary
	for ctag in agents_by_country.keys():
		var arr: Array = []
		for entry in (agents_by_country[ctag] as Array):
			if typeof(entry) == TYPE_DICTIONARY:
				arr.append(_dict_to_agent(entry))
		AgentManager.agents[ctag] = arr

	# Restore networks
	var nets: Dictionary = a.get("networks", {}) as Dictionary
	for pid_str in nets.keys():
		var pid := int(pid_str)
		var entry: Dictionary = nets[pid_str] as Dictionary
		if typeof(entry) == TYPE_DICTIONARY:
			AgentManager.networks[pid] = _dict_to_network(entry)

	# Note: We do not re-emit every signal here; UI that cares can refresh on demand
	# or we can emit a single "agents_state_restored" if we add the signal later.
	print("SaveLoad: Restored %d agent countries + %d networks" % [agents_by_country.size(), nets.size()])

## --- Map (provinces) ---

func _serialize_map_state() -> Dictionary:
	var out := { "provinces": [] }
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_all_provinces"):
		return out

	# Use the public query API (added/strengthened during Save/Load work)
	var provinces_dict: Dictionary = MapManager.get_all_provinces()
	for pid in provinces_dict.keys():
		var p: Province = provinces_dict[pid]
		if p == null:
			continue
		out["provinces"].append({
			"id": p.id,
			"owner_tag": p.owner_tag,
			"controller_tag": p.controller_tag,
			"development_level": p.development_level,
			"infrastructure": p.infrastructure,
			"settlement_level": p.settlement_level,
			"built_road_neighbors": p.built_road_neighbors.duplicate(),
			"built_rail_neighbors": p.built_rail_neighbors.duplicate(),
			"special_sites": _serialize_special_sites(p),
			# Add more mutables (factories, resources, special_features deltas, cores, etc.) as they gain runtime mutation.
		})
	return out


## Required keys per province entry in save["map"] (audit / unit tests / load hardening).
static func map_province_required_keys() -> PackedStringArray:
	return PackedStringArray([
		"id",
		"owner_tag",
		"controller_tag",
		"development_level",
		"infrastructure",
		"settlement_level",
		"built_road_neighbors",
		"built_rail_neighbors",
	])


## Validate a map save blob: provinces array + required keys + optional infrastructure_projects sibling.
## Pure structure check — used by tests and can be called after serialize/before apply.
static func validate_map_save_payload(map_data: Dictionary, full_save: Dictionary = {}) -> Dictionary:
	var missing: Array[String] = []
	if not map_data.has("provinces"):
		return {"ok": false, "missing": ["map.provinces"], "province_count": 0}
	var list: Array = map_data.get("provinces", []) as Array
	var req := map_province_required_keys()
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			missing.append("non_dict_province_entry")
			continue
		var e: Dictionary = entry
		for k in req:
			if not e.has(k):
				missing.append("province.%s" % k)
				break
	# Full save should also carry active infra projects when InfrastructureDevelopmentManager exists
	if not full_save.is_empty() and not full_save.has("infrastructure_projects"):
		missing.append("infrastructure_projects")
	return {
		"ok": missing.is_empty(),
		"missing": missing,
		"province_count": list.size(),
	}


func _apply_map_state(m: Dictionary) -> void:
	var list: Array = m.get("provinces", []) as Array
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var pid := int(e.get("id", -1))
		if pid < 0:
			continue

		# Use the public mutation helpers so signals fire and overlays react
		if e.has("owner_tag") or e.has("controller_tag"):
			var owner := str(e.get("owner_tag", ""))
			var ctrl := str(e.get("controller_tag", ""))
			MapManager.update_province_owner(pid, owner, ctrl, true)

		if e.has("development_level"):
			MapManager.update_province_development(pid, int(e["development_level"]))

		if e.has("infrastructure"):
			MapManager.update_province_infrastructure(pid, int(e["infrastructure"]))

		if e.has("settlement_level"):
			var sl := float(e.get("settlement_level", 0.0))
			if MapManager.has_method("update_province_settlement"):
				MapManager.update_province_settlement(pid, sl)
			else:
				# fallback direct + emit (preserves Province getter data for combat/preview)
				var pp: Province = MapManager.get_province(pid)
				if pp != null:
					pp.settlement_level = clampf(sl, 0.0, 5.0)
					MapManager.notify_province_changed(pid, "settlement")

		if e.has("built_road_neighbors"):
			var p_road: Province = MapManager.get_province(pid)
			if p_road != null:
				p_road.built_road_neighbors = Array(e.get("built_road_neighbors", []), TYPE_INT, "", null)
				MapManager.notify_province_changed(pid, "infrastructure")
		if e.has("built_rail_neighbors"):
			var p_rail: Province = MapManager.get_province(pid)
			if p_rail != null:
				p_rail.built_rail_neighbors = Array(e.get("built_rail_neighbors", []), TYPE_INT, "", null)
				MapManager.notify_province_changed(pid, "infrastructure")

		if e.has("special_sites"):
			_apply_special_sites(pid, e["special_sites"])

	print("SaveLoad: Applied province state to %d provinces (signals emitted)" % list.size())

	# Re-seed weather from (possibly updated) provinces snow_potential after map restore (preserves layer-driven high elev snow on reload)
	var wm := get_node_or_null("/root/WeatherManager") if get_tree() else null
	if wm == null and Engine.has_singleton("WeatherManager"):
		wm = Engine.get_singleton("WeatherManager")
	if wm and wm.has_method("initialize_province") and typeof(MapManager) != TYPE_NIL:
		var allp := MapManager.get_all_provinces() if MapManager.has_method("get_all_provinces") else {}
		for pidv in allp:
			var p: Province = allp[pidv]
			if p and p.snow_potential > 0.0:
				wm.initialize_province(pidv, {"is_northern": p.snow_potential > 0.05, "lat": 55.0, "high_ground_fraction": p.snow_potential, "snow_potential": p.snow_potential})


## Helper to serialize special sites on a province
func _serialize_special_sites(p: Province) -> Array:
	var out := []
	if p == null or p.special_sites.is_empty():
		return out
	for site in p.special_sites:
		if site == null:
			continue
		out.append({
			"id": site.id,
			"site_type": int(site.site_type),
			"tier": site.tier,
			"construction_state": int(site.construction_state),
			"construction_progress": site.construction_progress,
			"damage_level": site.damage_level,
			"owner_tag": site.owner_tag,
			"upgrade_target_id": site.upgrade_target_id if site.has_method("get_upgrade_target_id") or "upgrade_target_id" in site else ""
		})
	return out

func _apply_special_sites(pid: int, sites_data: Array) -> void:
	var province: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
	if province == null:
		return

	province.special_sites.clear()

	for sdata in sites_data:
		if typeof(sdata) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = sdata

		var site := SpecialSite.new()
		site.id = d.get("id", "")
		site.site_type = SpecialSite.SiteType.values()[int(d.get("site_type", 0))]
		site.tier = int(d.get("tier", 1))
		site.construction_state = SpecialSite.ConstructionState.values()[int(d.get("construction_state", 2))]
		site.construction_progress = float(d.get("construction_progress", 1.0))
		site.damage_level = int(d.get("damage_level", 0))
		site.owner_tag = d.get("owner_tag", "")
		site.upgrade_target_id = d.get("upgrade_target_id", "")

		province.special_sites.append(site)

	if not sites_data.is_empty():
		MapManager.notify_province_changed(pid, "special_site")


## --- Supply depots ---

func _serialize_supply_state() -> Dictionary:
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_save_data"):
		return SupplyManager.get_save_data()
	var out := { "depots": {}, "division_deployments": {} }
	if typeof(SupplyManager) == TYPE_NIL:
		return out

	for pid in SupplyManager.depot_states.keys():
		var depot: ProvinceDepotState = SupplyManager.depot_states[pid]
		if depot == null:
			continue
		out["depots"][str(pid)] = {
			"stockpile": depot.stockpile,
			"throughput_capacity": depot.throughput_capacity,
			"sabotage_level": depot.sabotage_level,
			# inbound/outbound are transient; usually not worth persisting
		}
	if "division_deployments" in SupplyManager:
		for fid in SupplyManager.division_deployments.keys():
			out["division_deployments"][str(fid)] = (
				SupplyManager.division_deployments[fid] as Dictionary
			).duplicate(true)
	return out

func _apply_supply_depots_state(s: Dictionary) -> void:
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("apply_save_data"):
		SupplyManager.apply_save_data(s, true, false)
		return
	_apply_supply_depots_legacy(s)


func _apply_supply_deployments_state(s: Dictionary) -> void:
	if typeof(SupplyManager) == TYPE_NIL:
		return
	var slice: Dictionary = s as Dictionary
	if not slice.has("division_deployments"):
		return
	if SupplyManager.has_method("apply_save_data"):
		SupplyManager.apply_save_data(slice, false, true)
		return
	SupplyManager.division_deployments = (
		slice.get("division_deployments", {}) as Dictionary
	).duplicate(true)
	if SupplyManager.has_method("resync_division_deployments_to_registry"):
		SupplyManager.resync_division_deployments_to_registry()


func _apply_supply_depots_legacy(s: Dictionary) -> void:
	var depots: Dictionary = s.get("depots", {}) as Dictionary
	var restored := 0
	for pid_str in depots.keys():
		var pid := int(pid_str)
		var entry: Dictionary = depots[pid_str] as Dictionary
		var depot: ProvinceDepotState = SupplyManager.depot_states.get(pid)
		if depot != null and typeof(entry) == TYPE_DICTIONARY:
			depot.stockpile = float(entry.get("stockpile", depot.stockpile))
			if entry.has("throughput_capacity"):
				depot.throughput_capacity = float(entry["throughput_capacity"])
			if entry.has("sabotage_level"):
				depot.sabotage_level = float(entry["sabotage_level"])
			restored += 1
	print("SaveLoad: Restored %d depot states (stock/sabotage/throughput)" % restored)

## --- NationalModifierManager ---

func _apply_national_modifier_state(n: Dictionary) -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		return
	# Replace wholesale — tick_modifiers will continue decaying on next monthly tick
	NationalModifierManager.country_modifiers = (n.get("country_modifiers", {}) as Dictionary).duplicate(true)
	print("SaveLoad: National modifier effects restored")

## --- Technology ---

func _apply_technology_state(t: Dictionary) -> void:
	if typeof(TechnologyManager) == TYPE_NIL:
		return

	var cs: Dictionary = t.get("country_state", {}) as Dictionary
	if not cs.is_empty():
		TechnologyManager.country_state = cs.duplicate(true)

	# Rebuild any derived indices that depend on the restored state
	if TechnologyManager.has_method("_rebuild_unlock_indices"):
		TechnologyManager._rebuild_unlock_indices()

	# Let screens / UI that listen to research_state_changed refresh
	for tag in TechnologyManager.country_state.keys():
		if TechnologyManager.has_signal("research_state_changed"):
			TechnologyManager.research_state_changed.emit(str(tag))

	print("SaveLoad: Technology country_state restored for %d countries" % TechnologyManager.country_state.size())

## Convenience / debug helpers

func quicksave() -> bool:
	return save_game(DEFAULT_SLOT)

func quickload() -> bool:
	return load_game(DEFAULT_SLOT)

func get_last_save_path() -> String:
	return _last_save_path

## === Save Menu / Scenario helpers (foundation for future UI) ===

## Returns the scenario_id stored in the save (or "" if not present).
func get_saved_scenario_id(slot_name: String) -> String:
	var meta := _peek_metadata(get_save_path(slot_name))
	return str(meta.get("scenario_id", ""))

## Lightweight compatibility check. Returns { "compatible": bool, "saved_scenario": "...", "current_scenario": "..." }
## Future menu can use this to warn or offer to load the matching scenario first.
func check_scenario_compatibility(slot_name: String) -> Dictionary:
	var saved := get_saved_scenario_id(slot_name)
	var current := ""
	var loader := _find_scenario_loader()
	if loader != null:
		current = loader.get_current_scenario_name()
	return {
		"compatible": saved.is_empty() or current.is_empty() or saved == current,
		"saved_scenario": saved,
		"current_scenario": current
	}

## === New apply helpers for expanded state ===

func _apply_leader_state(l: Dictionary) -> void:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("apply_save_data"):
		LeaderManager.apply_save_data(l)
		return
	# Fallback direct (if no method yet)
	print("SaveLoad: Leader state present but no apply_save_data on LeaderManager (direct apply limited)")

func _apply_factory_state(f: Dictionary) -> void:
	if typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("apply_save_data"):
		FactoryManager.apply_save_data(f)
		return
	print("SaveLoad: Factory state present but no apply on FactoryManager")

func _apply_production_state(p: Dictionary) -> void:
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("apply_save_data"):
		ProductionManager.apply_save_data(p)
		return
	print("SaveLoad: Production state present but no apply on ProductionManager")

## === Robustness: version migration stub + improved error handling ===

## Called for old save versions to upgrade data in-place before _apply.
## Add cases here as SAVE_VERSION increases (e.g. key renames, default sections, data shape fixes).
## This is the central place for forward/backward compat.
func _migrate_save_data(data: Dictionary) -> void:
	var v := int(data.get("save_version", 0))
	if v >= SAVE_VERSION:
		return
	print("SaveLoad: Migrating save from v%d to v%d" % [v, SAVE_VERSION])

	# Example future migration (uncomment and extend as needed):
	# if v < 2:
	#     if not data.has("production"):
	#         data["production"] = {}
	#     if data.has("old_key_name"):
	#         data["new_key_name"] = data.pop("old_key_name")
	#     # Provide defaults for new sections, fix shapes, etc.

	data["save_version"] = SAVE_VERSION  # mark as upgraded

## === Infrastructure migration support (added May 2026) ===
## Handles old saves that pre-date the "infrastructure_projects" section.
## Supports:
##   - Modern key "infrastructure_projects"
##   - Legacy key "infrastructure" (user sketch format or early experiments)
##   - Per-province "active_project" entries
func _get_infrastructure_save_data(save_root: Dictionary) -> Dictionary:
	if save_root.is_empty():
		return {}

	# Preferred modern format
	if save_root.has("infrastructure_projects"):
		var d: Dictionary = save_root["infrastructure_projects"]
		if typeof(d) == TYPE_DICTIONARY and d.has("active_projects"):
			return d

	# Legacy top-level "infrastructure" key (user's original sketch or early saves)
	if save_root.has("infrastructure"):
		var legacy: Dictionary = save_root["infrastructure"]
		if typeof(legacy) == TYPE_DICTIONARY:
			# Convert user's example shape into the real manager shape if needed
			var converted := { "version": 1, "active_projects": {} }
			for pid_str in legacy.keys():
				var entry: Dictionary = legacy[pid_str] as Dictionary
				if entry == null:
					continue
				var proj_data: Variant = entry.get("active_project", null)
				if proj_data != null and typeof(proj_data) == TYPE_DICTIONARY:
					converted["active_projects"][pid_str] = proj_data
				elif entry.has("project"):  # alternative legacy shape
					converted["active_projects"][pid_str] = entry["project"]
			if not converted["active_projects"].is_empty():
				print("SaveLoad: Migrated legacy 'infrastructure' section to infrastructure_projects format.")
				return converted

	# Also check inside "map" for any stray per-province project data (very old experiments)
	if save_root.has("map"):
		var map_section: Dictionary = save_root["map"]
		if map_section.has("provinces") and typeof(map_section["provinces"]) == TYPE_ARRAY:
			var converted2 := { "version": 1, "active_projects": {} }
			for p in map_section["provinces"]:
				if typeof(p) != TYPE_DICTIONARY:
					continue
				var pid := str(p.get("id", ""))
				var proj: Variant = p.get("active_infra_project", null)
				if proj == null:
					proj = p.get("active_project", null)
				if proj != null and typeof(proj) == TYPE_DICTIONARY:
					converted2["active_projects"][pid] = proj
			if not converted2["active_projects"].is_empty():
				print("SaveLoad: Found stray per-province project data in map section — migrated.")
				return converted2

	return {}

## Enhanced save with better error object (for future UI).
func save_game_detailed(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	_ensure_save_dir()
	var safe_slot := _sanitize_slot(slot_name)
	var path := get_save_path(safe_slot)
	var abs_path := get_save_path_global(safe_slot)
	print("SaveLoadManager: Saving slot=%s → %s" % [safe_slot, abs_path])

	var data: Dictionary = {}
	# Guard: gather can be heavy on world_accurate; never let a script error leave silent UI.
	data = _gather_save_data()
	if data.is_empty():
		var empty_msg := "Save data empty (gather failed)"
		push_error("SaveLoadManager: %s" % empty_msg)
		return {"ok": false, "error": empty_msg, "path": path, "absolute_path": abs_path}
	# Never write a partial mid-war blob: refuse a missing land_war key.
	# Always emit the land_war {} shape (empty open_battles / marches are valid).
	if not data.has("land_war") or typeof(data["land_war"]) != TYPE_DICTIONARY:
		var missing_lw := "Save data missing land_war key (gather incomplete)"
		push_error("SaveLoadManager: %s" % missing_lw)
		return {"ok": false, "error": missing_lw, "path": path, "absolute_path": abs_path}
	var lw_out: Dictionary = data["land_war"]
	if not lw_out.has("open_battles") or typeof(lw_out["open_battles"]) != TYPE_ARRAY:
		lw_out["open_battles"] = []
	if not lw_out.has("marches") or typeof(lw_out["marches"]) != TYPE_DICTIONARY:
		lw_out["marches"] = {}
	if not lw_out.has("next_seq"):
		lw_out["next_seq"] = 1
	if not lw_out.has("last_aar") or typeof(lw_out.get("last_aar", null)) != TYPE_DICTIONARY:
		lw_out["last_aar"] = {}
	data["land_war"] = lw_out

	var json_text := JSON.stringify(data, "\t")
	if json_text.is_empty() or json_text == "null":
		var jmsg := "JSON stringify failed"
		push_error("SaveLoadManager: %s" % jmsg)
		return {"ok": false, "error": jmsg, "path": path, "absolute_path": abs_path}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		# Retry with absolute path
		f = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		var msg := "Cannot write save (error %d) — path %s" % [err, abs_path]
		push_error("SaveLoadManager: %s" % msg)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Save failed: " + msg, 4.0, true)
		return {"ok": false, "error": msg, "path": path, "absolute_path": abs_path, "code": err}

	f.store_string(json_text)
	f.close()
	_last_save_path = path
	var bytes := json_text.length()
	print("SaveLoadManager: Game saved → %s (v%d, %d bytes, slot=%s)" % [abs_path, SAVE_VERSION, bytes, safe_slot])
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Saved %s (%d KB)" % [safe_slot, int(bytes / 1024)], 2.5)
	return {
		"ok": true,
		"path": path,
		"absolute_path": abs_path,
		"slot": safe_slot,
		"bytes": bytes,
		"version": SAVE_VERSION,
	}

## Enhanced load with migration + feedback.
func load_game_detailed(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	var path := get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		var msg := "File not found: " + path
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Load failed: " + msg, 3.0, true)
		return {"ok": false, "error": msg, "path": path}

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot open for read", "path": path}

	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Corrupt JSON (not object)", "path": path}

	var data: Dictionary = parsed
	_migrate_save_data(data)  # upgrades in place if old

	var file_version := int(data.get("save_version", 0))
	if file_version > SAVE_VERSION:
		push_warning("SaveLoadManager: Save v%d > current v%d; best-effort only" % [file_version, SAVE_VERSION])

	_apply_save_data(data)
	return {"ok": true, "path": path, "version": file_version}

## === UX helpers (delete, rename) for save menu ===

func delete_save(slot_name: String) -> bool:
	var path := get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("SaveLoadManager: Failed to delete %s (err %d)" % [path, err])
		return false
	print("SaveLoadManager: Deleted save %s" % slot_name)
	return true

func rename_save(old_slot: String, new_slot: String) -> bool:
	var old_path := get_save_path(old_slot)
	var new_path := get_save_path(new_slot)
	if not FileAccess.file_exists(old_path):
		return false
	if FileAccess.file_exists(new_path):
		push_warning("SaveLoadManager: Target name already exists: %s" % new_slot)
		return false

	var content := FileAccess.get_file_as_string(old_path)
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()

	DirAccess.remove_absolute(old_path)
	print("SaveLoadManager: Renamed %s -> %s" % [old_slot, new_slot])
	return true

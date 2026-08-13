class_name MapNextListHelpers
extends RefCounted

static func default_harness_visible() -> bool:
	return false

static func is_dev_harness_section(title: String) -> bool:
	var low := title.to_lower()
	if low.find("harness") >= 0 or low.find("playtest") >= 0:
		return true
	if low.find("editor") >= 0 or low.find("map gen") >= 0:
		return true
	if low.find("prototyping") >= 0 or low.find("test tools") >= 0:
		return true
	if low.find("demographic map test") >= 0:
		return true
	return false

static func section_start_collapsed(title: String) -> bool:
	return is_dev_harness_section(title)

static func section_kind(title: String) -> String:
	if is_dev_harness_section(title):
		return "dev_harness"
	return "player_map"

static func default_player_map_visible() -> bool:
	return true

static func classify_map_damage(state: Dictionary) -> Dictionary:
	var under := false
	var depot := 0.0
	var sites := 0
	var proj := false
	var kind := ""
	var infra := 50
	if state.has("under_infra_sabotage"):
		under = bool(state["under_infra_sabotage"])
	if state.has("depot_sabotage_level"):
		depot = float(state["depot_sabotage_level"])
	if state.has("site_damaged_count"):
		sites = int(state["site_damaged_count"])
	if state.has("project_sabotaged"):
		proj = bool(state["project_sabotaged"])
	if state.has("agent_pressure_kind"):
		kind = str(state["agent_pressure_kind"])
	if state.has("infrastructure"):
		infra = int(state["infrastructure"])
	var out: Dictionary = {}
	if under or kind == "sabotage":
		var strength := 0.42 if under else 0.28
		if infra <= 15:
			strength = minf(0.65, strength + 0.12)
		out["role"] = "infra_sabotage"
		out["tint_key"] = "infra_sabotage"
		out["marker"] = "!"
		out["strength"] = strength
		out["label"] = "Infrastructure sabotage"
		out["is_damaged"] = true
		return out
	if depot > 0.05:
		out["role"] = "depot_sabotage"
		out["tint_key"] = "depot_sabotage"
		out["marker"] = "D"
		out["strength"] = minf(0.55, 0.18 + depot * 0.45)
		out["label"] = "Depot sabotage"
		out["is_damaged"] = true
		return out
	if sites > 0:
		out["role"] = "site_damage"
		out["tint_key"] = "site_damage"
		out["marker"] = "X"
		out["strength"] = minf(0.5, 0.2 + float(sites) * 0.1)
		out["label"] = "Special site damage"
		out["is_damaged"] = true
		return out
	if proj:
		out["role"] = "project_sabotage"
		out["tint_key"] = "project_sabotage"
		out["marker"] = "!"
		out["strength"] = 0.32
		out["label"] = "Investment project sabotaged"
		out["is_damaged"] = true
		return out
	out["role"] = "clean"
	out["tint_key"] = "clean"
	out["marker"] = ""
	out["strength"] = 0.0
	out["label"] = ""
	out["is_damaged"] = false
	return out

static func format_hh_monthly_map_signal(year: int, month: int, province_id: int, province_name: String, action_class: String, influence: float, owner_tag: String = "") -> Dictionary:
	var action := action_class.strip_edges().to_lower()
	if action != "sabotage" and action != "propaganda" and action != "influence" and action != "black_market" and action != "economic_pressure" and action != "infiltration":
		action = "influence"
	var pname := province_name
	if pname.is_empty():
		pname = "Province %d" % province_id
	var title := "Hidden Hand influence"
	var marker := "H"
	if action == "sabotage":
		title = "Hidden Hand sabotage"
		marker = "!"
	elif action == "propaganda":
		title = "Hidden Hand propaganda"
		marker = "P"
	elif action == "black_market":
		title = "Hidden Hand black market"
		marker = "B"
	elif action == "economic_pressure":
		title = "Hidden Hand economic pressure"
		marker = "$"
	elif action == "infiltration":
		title = "Hidden Hand infiltration"
		marker = "◈"
	var inf := clampf(influence, 0.0, 1.0)
	var body := "%s in %s (#%d) - influence %.0f%%. Counter with agents or policy." % [title, pname, province_id, inf * 100.0]
	var tint_key := "hh_influence"
	var sfx := "select"
	if action == "sabotage":
		tint_key = "infra_sabotage"
		sfx = "error"
	elif action == "economic_pressure":
		tint_key = "supply_pressure"
		sfx = "confirm"
	elif action == "infiltration":
		tint_key = "loyalty_strain"
		sfx = "map"
	var out: Dictionary = {}
	out["active"] = true
	out["year"] = year
	out["month"] = month
	out["province_id"] = province_id
	out["province_name"] = pname
	out["owner_tag"] = owner_tag
	out["action_class"] = action
	out["action_kind"] = "hh_signal"
	out["influence"] = inf
	out["title"] = title
	out["marker"] = marker
	out["tint_key"] = tint_key
	out["strength"] = 0.22 + inf * 0.28
	out["toast"] = body
	out["sfx"] = sfx
	out["duration"] = 4.5
	out["news_headline"] = title
	out["news_body"] = body
	out["inspector_line"] = "[color=#c084fc]%s %s[/color] [color=#8899aa]%s - %04d-%02d[/color]" % [marker, title, pname, year, month]
	out["label"] = "%s %s" % [marker, title]
	out["tooltip_chip"] = out["inspector_line"]
	out["map_effect"] = ""
	if action == "sabotage":
		out["map_effect"] = "infra_damage"
	elif action == "economic_pressure":
		out["map_effect"] = "industrial_pressure"
	elif action == "infiltration":
		out["map_effect"] = "loyalty_infiltration"
	return out

static func pick_hh_action_class(month: int, hand_influence: float) -> String:
	var m := month % 12
	if hand_influence >= 0.45 and m % 3 == 0:
		return "sabotage"
	if hand_influence >= 0.35 and m % 3 == 1:
		return "economic_pressure"
	# Third map-visible class (loyalty / institutional infiltration)
	if hand_influence >= 0.30 and m % 3 == 2:
		return "infiltration"
	if m % 4 == 1:
		return "propaganda"
	if m % 5 == 2:
		return "black_market"
	return "influence"

## Second concurrent pulse class (distinct fingerprint from primary monthly action).
static func pick_hh_secondary_action_class(month: int, hand_influence: float, primary_action: String) -> String:
	var primary := primary_action.strip_edges().to_lower()
	var m := month % 12
	var hand := clampf(hand_influence, 0.0, 1.0)
	# Prefer complementary class so two fingerprints show on the map.
	if primary == "sabotage":
		return "infiltration" if hand >= 0.35 else "economic_pressure"
	if primary == "economic_pressure":
		return "infiltration" if hand >= 0.3 else "sabotage"
	if primary == "infiltration":
		return "sabotage" if hand >= 0.4 else "economic_pressure"
	if primary == "propaganda":
		return "infiltration" if m % 2 == 0 else "black_market"
	if primary == "black_market":
		return "infiltration" if hand >= 0.3 else "propaganda"
	# primary influence
	if hand >= 0.4 and m % 2 == 0:
		return "economic_pressure"
	return "infiltration" if hand >= 0.28 else "propaganda"

static func format_province_select_flair(
	province_name: String,
	owner_tag: String = "",
	region_name: String = "",
	terrain: String = "",
	damage_label: String = "",
	hh_active: bool = false,
	is_chokepoint: bool = false,
	sea_zone_name: String = "",
	is_coastal: bool = false,
) -> Dictionary:
	var pname := province_name.strip_edges()
	if pname.is_empty():
		pname = "Province"
	var toast := "Selected - " + pname
	if not owner_tag.is_empty():
		toast += " - " + owner_tag.strip_edges().to_upper()
	if not region_name.is_empty():
		toast += " - " + region_name.strip_edges()
	if not sea_zone_name.is_empty():
		toast += " - ⚓ " + sea_zone_name.strip_edges()
	elif is_chokepoint:
		toast += " - ⚓ Naval chokepoint"
	elif is_coastal:
		toast += " - 🌊 Coast"
	if not terrain.is_empty():
		toast += " - " + terrain.strip_edges().capitalize()
	if not damage_label.is_empty():
		toast += " - ! " + damage_label
	if hh_active:
		toast += " - Hand activity here"
	var tooltip_chip := "[color=#6eb5ff]Selected[/color] [color=#8899aa]%s[/color]" % pname
	if not owner_tag.is_empty():
		tooltip_chip += " [color=#a0c0ff]%s[/color]" % owner_tag.strip_edges().to_upper()
	if not sea_zone_name.is_empty():
		tooltip_chip += " [color=#5ec8ff]⚓ %s[/color]" % sea_zone_name.strip_edges()
	elif is_chokepoint:
		tooltip_chip += " [color=#5ec8ff]⚓ Chokepoint[/color]"
	elif is_coastal:
		tooltip_chip += " [color=#5ec8ff]🌊 Coast[/color]"
	var sfx := "select"
	if is_chokepoint or not sea_zone_name.is_empty() or is_coastal:
		sfx = "confirm"  # weightier cue for naval-critical / coastal tiles
	var out: Dictionary = {}
	out["toast"] = toast
	out["tooltip_chip"] = tooltip_chip
	out["sfx"] = sfx
	out["duration"] = 2.0 if is_chokepoint or not sea_zone_name.is_empty() or is_coastal else 1.8
	out["province_name"] = pname
	out["owner_tag"] = owner_tag.strip_edges().to_upper()
	out["is_chokepoint"] = is_chokepoint
	out["sea_zone_name"] = sea_zone_name.strip_edges()
	out["is_coastal"] = is_coastal
	out["action_kind"] = "select"
	return out

static func format_infra_project_flair(province_name: String, kind: String = "complete", new_level: int = 0, eta_days: int = 0, cost_pp: int = 0) -> Dictionary:
	var pname := province_name.strip_edges()
	if pname.is_empty():
		pname = "Province"
	var k := kind.strip_edges().to_lower()
	var toast := ""
	var sfx := "achievement"
	var title := "Infrastructure complete"
	var duration := 3.0
	var action_kind := "invest_complete"
	if k == "start" or k == "invest" or k == "started":
		toast = "Infrastructure investment started in " + pname
		if eta_days > 0:
			toast += " - ETA ~%d days" % eta_days
		if cost_pp > 0:
			toast += " (spent %d Mandate)" % cost_pp
		sfx = "confirm"
		title = "Investment started"
		action_kind = "invest_start"
	elif k == "cancel" or k == "cancelled":
		toast = "Infrastructure project cancelled in " + pname
		sfx = "error"
		title = "Investment cancelled"
		duration = 2.2
		action_kind = "invest_cancel"
	else:
		toast = "Infrastructure project complete in " + pname
		if new_level > 0:
			toast += " -> level %d" % new_level
		sfx = "achievement"
		title = "Infrastructure complete"
		action_kind = "invest_complete"
	var out: Dictionary = {}
	out["toast"] = toast
	out["title"] = title
	out["sfx"] = sfx
	out["duration"] = duration
	out["province_name"] = pname
	out["kind"] = k
	out["new_level"] = new_level
	out["news_headline"] = title
	out["news_body"] = toast
	out["action_kind"] = action_kind
	out["tooltip_chip"] = "[color=#6ec8ff]%s[/color] [color=#8899aa]%s[/color]" % [title, pname]
	return out


## Alias for flair-contract audits / callers that use the shorter name.
static func format_capture_flair(
	province_name: String,
	attacker_tag: String = "",
	defender_tag: String = "",
	captured: bool = false,
	outcome: String = "",
	winner: String = "",
) -> Dictionary:
	return format_capture_assault_flair(
		province_name, attacker_tag, defender_tag, captured, outcome, winner
	)


## Player-facing toast/sfx after province assault (capture, repulse, or hold).
static func format_capture_assault_flair(
	province_name: String,
	attacker_tag: String = "",
	defender_tag: String = "",
	captured: bool = false,
	outcome: String = "",
	winner: String = "",
) -> Dictionary:
	var pname := province_name.strip_edges()
	if pname.is_empty():
		pname = "Province"
	var atk := attacker_tag.strip_edges().to_upper()
	var dfn := defender_tag.strip_edges().to_upper()
	var win := winner.strip_edges().to_lower()
	var outc := outcome.strip_edges()
	var toast := ""
	var sfx := "map"
	var title := "Province held"
	var action_kind := "assault_hold"
	var tooltip := ""
	if captured:
		toast = "%s captured %s" % [atk if not atk.is_empty() else "Attacker", pname]
		if not outc.is_empty():
			toast += " (%s)" % outc
		sfx = "achievement"
		title = "Province captured"
		action_kind = "capture"
		tooltip = "[color=#7dffb2]⚔ Captured[/color] [color=#8899aa]%s[/color]" % pname
		if not atk.is_empty():
			tooltip += " [color=#a0c0ff]%s[/color]" % atk
	elif win == "attacker":
		toast = "Attack repulsed at %s" % pname
		if not outc.is_empty():
			toast += " — %s" % outc
		sfx = "confirm"
		title = "Assault repulsed"
		action_kind = "assault_repulse"
		tooltip = "[color=#ff9a6e]⚔ Repulsed[/color] [color=#8899aa]%s[/color]" % pname
	else:
		toast = "%s held %s" % [dfn if not dfn.is_empty() else "Defender", pname]
		if not outc.is_empty():
			toast += " — %s" % outc
		sfx = "map"
		title = "Province held"
		action_kind = "assault_hold"
		tooltip = "[color=#6eb5ff]⚔ Held[/color] [color=#8899aa]%s[/color]" % pname
		if not dfn.is_empty():
			tooltip += " [color=#a0c0ff]%s[/color]" % dfn
	return {
		"toast": toast,
		"title": title,
		"sfx": sfx,
		"duration": 4.0 if captured else 3.5,
		"province_name": pname,
		"attacker_tag": atk,
		"defender_tag": dfn,
		"captured": captured,
		"winner": win,
		"outcome": outc,
		"action_kind": action_kind,
		"tooltip_chip": tooltip,
		"news_headline": title,
		"news_body": toast,
	}

static func apply_hh_counterplay(hand_influence: float, hh_signal: Dictionary, method: String = "counter_intel", clear_signal: bool = true, reduction: float = 0.12) -> Dictionary:
	var old := clampf(hand_influence, 0.0, 1.0)
	var red := clampf(reduction, 0.02, 0.5)
	var method_key := method.strip_edges().to_lower()
	if method_key == "policy" or method_key == "reform":
		red = maxf(red, 0.08)
	elif method_key == "agent" or method_key == "counter_intel" or method_key == "sweep":
		red = maxf(red, 0.12)
	var new_inf := clampf(old - red, 0.0, 1.0)
	var sig: Dictionary = {}
	if not hh_signal.is_empty():
		sig = hh_signal.duplicate(true)
	var pid := -1
	var pname := ""
	if sig.has("province_id"):
		pid = int(sig["province_id"])
	if sig.has("province_name"):
		pname = str(sig["province_name"])
	var cleared := false
	var sig_active := false
	if sig.has("active"):
		sig_active = bool(sig["active"])
	if clear_signal and not sig.is_empty() and sig_active:
		sig["active"] = false
		sig["cleared_by"] = method_key
		sig["strength"] = 0.0
		sig["toast"] = "Hand activity disrupted"
		cleared = true
	var delta := old - new_inf
	var toast := "Counter-intel: Hidden Hand influence -%.0f%% (now %.0f%%)" % [delta * 100.0, new_inf * 100.0]
	if cleared and not pname.is_empty():
		toast += " - map signal cleared on " + pname
	elif cleared:
		toast += " - monthly map signal cleared"
	var out: Dictionary = {}
	out["success"] = delta > 0.001 or cleared
	out["method"] = method_key
	out["old_influence"] = old
	out["new_influence"] = new_inf
	out["reduction"] = delta
	out["signal_cleared"] = cleared
	out["province_id"] = pid
	out["province_name"] = pname
	out["updated_signal"] = sig
	out["toast"] = toast
	out["news_headline"] = "Hidden Hand pushed back"
	out["news_body"] = toast
	out["inspector_line"] = "[color=#6ec8ff]Counter-intel[/color] [color=#8899aa]Hand -%.0f%% -> %.0f%%[/color]" % [delta * 100.0, new_inf * 100.0]
	out["label"] = "Counter-intel"
	return out

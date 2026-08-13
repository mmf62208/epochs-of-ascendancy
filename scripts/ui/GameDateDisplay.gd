class_name GameDateDisplay
extends RefCounted

## Formats calendar text from TimeManager for HUD and tooltips.
## Keeps date presentation in one place until daily simulation ticks live here.

const MONTH_NAMES: PackedStringArray = [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
]

const MONTH_SHORT: PackedStringArray = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]


static func has_time_manager() -> bool:
	return typeof(TimeManager) != TYPE_NIL


static func get_current_date_dict() -> Dictionary:
	if not has_time_manager():
		return {"year": 1936, "month": 1, "day": 1, "date_string": "1936-01-01"}
	return TimeManager.get_current_date()


static func format_calendar_date(year: int, month: int, day: int, short_month: bool = false) -> String:
	var m := clampi(month, 1, 12)
	var d := clampi(day, 1, 31)
	var month_name: String = MONTH_SHORT[m - 1] if short_month else MONTH_NAMES[m - 1]
	return "%d %s %d" % [d, month_name, year]


static func format_iso_date_readable(iso: String) -> String:
	var parts := iso.strip_edges().split("-")
	if parts.size() < 3:
		return iso
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return iso
	return format_calendar_date(int(parts[0]), int(parts[1]), int(parts[2]), false)


static func days_since_scenario_start() -> int:
	if not has_time_manager():
		return 0
	var start_parts := TimeManager.get_scenario_start_date().split("-")
	var cur := get_current_date_dict()
	if start_parts.size() < 3:
		return 0
	var sy := int(start_parts[0]) if start_parts[0].is_valid_int() else 1936
	var sm := int(start_parts[1]) if start_parts[1].is_valid_int() else 1
	var sd := int(start_parts[2]) if start_parts[2].is_valid_int() else 1
	var cy := int(cur.get("year", sy))
	var cm := int(cur.get("month", sm))
	var cd := int(cur.get("day", sd))
	# MVP day count (no leap years; matches TimeManager rollover).
	var days := 0
	var y := sy
	var m := sm
	var d := sd
	while y < cy or (y == cy and (m < cm or (m == cm and d < cd))):
		var dim := _days_in_month(m, y)
		if d < dim:
			d += 1
		else:
			d = 1
			if m < 12:
				m += 1
			else:
				m = 1
				y += 1
		days += 1
		if days > 50000:
			break
	return days


static func _days_in_month(month: int, _year: int) -> int:
	match clampi(month, 1, 12):
		2:
			return 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


static func months_since_scenario_start() -> int:
	if not has_time_manager():
		return 0
	var start_parts := TimeManager.get_scenario_start_date().split("-")
	var cur := get_current_date_dict()
	if start_parts.size() < 2:
		return 0
	var sy := int(start_parts[0]) if start_parts[0].is_valid_int() else 1936
	var sm := int(start_parts[1]) if start_parts[1].is_valid_int() else 1
	var cy := int(cur.get("year", sy))
	var cm := int(cur.get("month", sm))
	return maxi(0, (cy - sy) * 12 + (cm - sm))


static func format_elapsed_suffix() -> String:
	var days := days_since_scenario_start()
	if days <= 0:
		return ""
	var months := months_since_scenario_start()
	if months >= 1:
		return " (+%dmo)" % months
	return " (+%dd)" % days


static func format_top_bar_line(include_pause_glyph: bool = true) -> String:
	var date := get_current_date_dict()
	var line := format_calendar_date(
		int(date.get("year", 1936)),
		int(date.get("month", 1)),
		int(date.get("day", 1)),
		true,
	)
	# Hour hand (1× advances hour-by-hour).
	var hour := int(date.get("hour", 0))
	line += " %02d:00" % hour
	line += format_elapsed_suffix()
	if include_pause_glyph and has_time_manager():
		if TimeManager.is_paused():
			line += "  ⏸"
		elif TimeManager.time_scale > 1.01:
			line += "  · %.0f×" % TimeManager.time_scale
	return line


static func format_top_bar_tooltip() -> String:
	if not has_time_manager():
		return "Game calendar (TimeManager not loaded)."
	var current := TimeManager.get_current_date()
	var start_iso := TimeManager.get_scenario_start_date()
	var start_readable := format_iso_date_readable(start_iso)
	var now_readable := "%s %02d:00" % [
		format_iso_date_readable(str(current.get("date_day_only", current.get("date_string", "")))),
		int(current.get("hour", 0)),
	]
	var elapsed := days_since_scenario_start()
	var lines: PackedStringArray = [
		"Scenario start: %s" % start_readable,
		"Current: %s" % now_readable,
	]
	var months := months_since_scenario_start()
	if elapsed > 0:
		if months >= 1:
			lines.append(
				"Time elapsed: %d day(s) · %d month(s) since scenario start"
				% [elapsed, months]
			)
		else:
			lines.append("Time elapsed: %d day(s) since scenario start" % elapsed)
	else:
		lines.append("Day 1 — unpause: 1× advances ~1 game hour per real second.")
	lines.append(
		"1× = hour-by-hour · 2×/3×/4× faster hours · full day sim fires at midnight."
	)
	if TimeManager.is_paused():
		lines.append("Simulation paused.")
	elif TimeManager.time_scale > 1.01:
		lines.append("Game speed: %.0f×" % TimeManager.time_scale)
	return "\n".join(lines)


static func format_map_date_plain(include_elapsed: bool = true) -> String:
	if not has_time_manager():
		return ""
	var elapsed := days_since_scenario_start()
	if elapsed <= 0:
		return ""
	var date := get_current_date_dict()
	var text := format_calendar_date(
		int(date.get("year", 1936)),
		int(date.get("month", 1)),
		int(date.get("day", 1)),
		true,
	)
	if include_elapsed:
		var months := months_since_scenario_start()
		if months >= 1:
			text += " +%dmo" % months
		else:
			text += " +%dd" % elapsed
	return text


static func build_map_time_pulse_bbcode(
	kind: String,
	year: int,
	month: int,
	day: int = 1,
) -> String:
	## Short-lived note when the map legend refreshes after a calendar boundary.
	var m := clampi(month, 1, 12)
	var d := clampi(day, 1, 31)
	match kind:
		"year":
			return (
				"[color=#6ec8ff]⏭ New year — %d (yearly simulation tick)[/color]"
				% year
			)
		"month":
			return (
				"[color=#9eb8d8]⏭ New month — %s %d (monthly tick)[/color]"
				% [MONTH_SHORT[m - 1], year]
			)
		"day":
			return (
				"[color=#8aa0b8]▸ %d %s %d[/color]"
				% [d, MONTH_SHORT[m - 1], year]
			)
		_:
			return ""


static func time_pulse_priority(kind: String) -> int:
	match kind:
		"year":
			return 3
		"month":
			return 2
		"day":
			return 1
		_:
			return 0


static func build_map_date_glance_bbcode(include_elapsed: bool = true, emphasize: bool = false) -> String:
	## Minimal date hint for map legend / tooltips (omit at scenario start).
	if not has_time_manager():
		return ""
	var elapsed := days_since_scenario_start()
	if elapsed <= 0:
		return ""
	var text := format_map_date_plain(include_elapsed)
	if text.is_empty():
		return ""
	var months := months_since_scenario_start()
	var color := "#9eb8d8" if emphasize or months >= 1 else "#8899aa"
	return "[color=%s]📅 %s[/color]" % [color, text]


static func build_map_date_footer_bbcode(
	time_pulse_bbcode: String = "",
	pulse_kind: String = "",
) -> String:
	## Legend/tooltip footer: optional boundary flash + current date.
	if pulse_kind == "day" and not time_pulse_bbcode.is_empty():
		return time_pulse_bbcode
	var parts: PackedStringArray = []
	if not time_pulse_bbcode.is_empty():
		parts.append(time_pulse_bbcode)
	var glance := build_map_date_glance_bbcode(true, true)
	if not glance.is_empty():
		parts.append(glance)
	if parts.is_empty():
		return ""
	return "  ·  ".join(parts)


static func format_map_date_compact() -> String:
	## Short date for chips (day + month + elapsed days).
	if not has_time_manager():
		return ""
	var elapsed := days_since_scenario_start()
	if elapsed <= 0:
		return ""
	var date := get_current_date_dict()
	return "%d %s +%dd" % [
		int(date.get("day", 1)),
		MONTH_SHORT[clampi(int(date.get("month", 1)), 1, 12) - 1],
		elapsed,
	]

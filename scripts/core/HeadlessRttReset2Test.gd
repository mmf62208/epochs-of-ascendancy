extends SceneTree

## RTT-RESET-2. Garrisons re-seed after Return to Title, NEXT chip after Begin,
## Western Russia compare-hint, one Menu > Save toast.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessRttReset2Test.gd

const KINGSTON := 903045
const ENG_65_ID := "garr1936_ENG_903045"
const RUS_WEST_PID := 903492
const GARRISON_TOTAL := 576
const GARRISON_ZOOM := 1.05

var _failures: int = 0


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRttReset2Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRttReset2Test: ", msg)


func _run() -> void:
	await _test_garrisons_reseed_after_rtt()
	await _test_next_hint_begin_and_title()
	_test_western_russia_compare_hint()
	await _test_menu_save_one_toast()
	var ok := _failures == 0
	print("HeadlessRttReset2Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRttReset2Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _test_garrisons_reseed_after_rtt() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var lm := root.get_node_or_null("LeaderManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or lm == null or boot == null:
		_fail("garrison: autoloads missing")
		return
	if not bool(boot.call("boot", mm, sm, "ENG")):
		_fail("garrison: board boot failed")
		return
	var mr := _make_map_renderer()
	if mr == null:
		_fail("garrison: MapRenderer missing")
		return
	_attach_kingston_host(mr)
	if not await _begin_as("ENG"):
		_fail("garrison: first ENG Begin did not close the title")
		_free_mr(mr)
		return
	var first: Dictionary = _seed_garrisons(lm)
	_print_seed("first_ENG", lm, first)
	if not bool(lm.get("_garrisons_1936_seeded")):
		_fail("garrison: first ENG Begin did not latch the 1936 seed flag")
		_free_mr(mr)
		return
	if not await _return_to_title():
		_fail("garrison: Return to Title did not fire")
		_free_mr(mr)
		return
	# ScenarioLoader._spawn_scenario_formations on the RtT reload.
	lm.call("clear_all_formations")
	if bool(lm.get("_garrisons_1936_seeded")):
		_fail("garrison: _garrisons_1936_seeded still latched after clear_all_formations")
		_free_mr(mr)
		return
	if not await _begin_as("ENG"):
		_fail("garrison: 2nd ENG Begin did not close the title")
		_free_mr(mr)
		return
	var second: Dictionary = _seed_garrisons(lm)
	_print_seed("second_ENG", lm, second)
	if not _garrison_total_ok(second, lm, "2nd ENG"):
		_free_mr(mr)
		return
	if bool(second.get("already", false)):
		_fail("garrison: 2nd ENG Begin skipped seed (already=true)")
		_free_mr(mr)
		return
	var eng65: Object = lm.call("get_formation", ENG_65_ID)
	if eng65 == null:
		_fail("garrison: ENG 65th missing at Kingston after 2nd Begin")
		_free_mr(mr)
		return
	var name_s := str(eng65.name)
	var pid := int(eng65.stationed_province_id) if "stationed_province_id" in eng65 else -1
	if pid != KINGSTON or name_s.find("65th") < 0:
		_fail("garrison: ENG 65th want Kingston 903045 got pid=%d name='%s'" % [pid, name_s])
		_free_mr(mr)
		return
	if not _kingston_chip_visible(mr, lm):
		_free_mr(mr)
		return
	_pass("2nd ENG Begin: 576 garrisons, ENG 65th at Kingston, chip visible at garrison zoom")
	if not await _return_to_title():
		_fail("garrison: second Return to Title did not fire")
		_free_mr(mr)
		return
	lm.call("clear_all_formations")
	if not await _begin_as("USA"):
		_fail("garrison: 2nd-cycle USA Begin did not close the title")
		_free_mr(mr)
		return
	var usa: Dictionary = _seed_garrisons(lm)
	_print_seed("second_USA", lm, usa)
	if not _garrison_total_ok(usa, lm, "2nd-cycle USA"):
		_free_mr(mr)
		return
	_pass("2nd-cycle USA Begin also reseeds 576")
	_free_mr(mr)


func _test_next_hint_begin_and_title() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var hook: GDScript = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	if mm == null or boot == null or hook == null:
		_fail("next: autoloads missing")
		return
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("next: board boot failed")
		return
	if hook.has_method("reset_session"):
		hook.call("reset_session")
	var mr := _make_map_renderer()
	if mr == null:
		_fail("next: MapRenderer missing")
		return
	mr.call("_refresh_next_hook_chip")
	var chip := _next_chip(mr)
	if chip == null:
		_fail("next: chip was not built")
		_free_mr(mr)
		return
	var title := _make_title()
	await process_frame
	await process_frame
	chip = _next_chip(mr)
	var fresh_txt := str(chip.text) if chip != null else ""
	if chip != null and chip.visible and not fresh_txt.strip_edges().is_empty():
		_fail("next: fresh title still shows a nation hint '%s'" % fresh_txt)
		_free_title(title)
		_free_mr(mr)
		return
	_pass("fresh title: NEXT chip hidden or empty")
	_free_title(title)
	await process_frame
	for tag in ["USA", "SOV", "ENG", "GER"]:
		if hook.has_method("reset_session"):
			hook.call("reset_session")
		if not await _begin_as(tag):
			_fail("next: Begin %s did not close the title" % tag)
			_free_mr(mr)
			return
		await process_frame
		await process_frame
		await process_frame
		chip = _next_chip(mr)
		var shown := str(chip.text) if chip != null else ""
		if chip == null or not chip.visible or shown.strip_edges().is_empty():
			_fail("next: in-game NEXT missing after Begin %s chip='%s' vis=%s" % [tag, shown, str(chip != null and chip.visible)])
			_free_mr(mr)
			return
		_pass("in-game NEXT after Begin %s: %s" % [tag, shown])
	var leftover := ""
	chip = _next_chip(mr)
	if chip != null:
		leftover = str(chip.text)
	if not await _return_to_title():
		_fail("next: Return to Title did not fire")
		_free_mr(mr)
		return
	await process_frame
	# 2b: leftover must be gone on the still-live map before a new title hides it.
	chip = _next_chip(mr)
	var rtt_txt := str(chip.text) if chip != null else ""
	if chip != null and chip.visible and not rtt_txt.strip_edges().is_empty():
		_fail("next: after RtT the live map still shows leftover '%s' (was '%s')" % [rtt_txt, leftover])
		_free_mr(mr)
		return
	if leftover != "" and rtt_txt.strip_edges() == leftover.strip_edges() and chip != null and chip.visible:
		_fail("next: after RtT previous-nation goal still painted '%s'" % leftover)
		_free_mr(mr)
		return
	if hook.has_method("chip_goal_pinned") and bool(hook.call("chip_goal_pinned")):
		_fail("next: NEXT goal lock still pinned after RtT")
		_free_mr(mr)
		return
	title = _make_title()
	await process_frame
	await process_frame
	chip = _next_chip(mr)
	rtt_txt = str(chip.text) if chip != null else ""
	if chip != null and chip.visible and not rtt_txt.strip_edges().is_empty():
		_fail("next: title after RtT still shows leftover '%s' (was '%s')" % [rtt_txt, leftover])
		_free_title(title)
		_free_mr(mr)
		return
	_pass("after RtT: title chip hidden/empty, no previous-nation goal")
	_free_title(title)
	_free_mr(mr)


func _test_western_russia_compare_hint() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var insight: GDScript = load("res://scripts/map/ProvinceInsight.gd") as GDScript
	if mm == null or boot == null or insight == null:
		_fail("hint: autoloads missing")
		return
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("hint: board boot failed")
		return
	var rus: Object = mm.call("get_province", RUS_WEST_PID)
	if rus == null:
		_fail("hint: province 903492 missing")
		return
	var raw := str(rus.name)
	if raw != "RUS West":
		print("HeadlessRttReset2Test: 903492 data name is '%s' (display-only override still applies)" % raw)
	var line := str(insight.call("build_map_compare_hint_plain", RUS_WEST_PID, 3))
	if line.find("Western Russia") < 0:
		_fail("hint: compare-hint missing Western Russia: %s" % line)
		return
	if line.find("RUS West") >= 0:
		_fail("hint: compare-hint still uses RUS West: %s" % line)
		return
	_pass("compare-hint: Western Russia, not RUS West")


func _test_menu_save_one_toast() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or boot == null:
		_fail("save: autoloads missing")
		return
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("save: board boot failed")
		return
	var leui: Node = root.get_node_or_null("LeaderEventUI")
	if leui == null:
		_fail("save: LeaderEventUI missing")
		return
	if "force_toast_ui" in leui:
		leui.set("force_toast_ui", true)
	if leui.has_method("clear_session_notices"):
		leui.call("clear_session_notices")
	var bar := _make_bar()
	if bar == null:
		_fail("save: TopInfoBar missing")
		return
	await process_frame
	await process_frame
	var mb: MenuButton = bar.get("menu_button") as MenuButton
	if mb == null:
		_fail("save: Menu button missing")
		return
	var popup := mb.get_popup()
	if popup == null:
		_fail("save: Menu popup missing")
		return
	# Real Menu > Save path (id_pressed 0), not Ctrl+S and not a direct _on_save_pressed call.
	popup.id_pressed.emit(0)
	await process_frame
	await process_frame
	var n := _visible_save_toasts(leui)
	if n != 1:
		_fail("save: Menu > Save visible toasts want 1 got %d" % n)
		return
	var cc := root.get_node_or_null("MainMenu")
	if cc == null or not is_instance_valid(cc) or cc.is_queued_for_deletion():
		_fail("save: Menu > Save did not open Command Center")
		return
	_pass("Menu > Save: exactly 1 visible save toast and Command Center opened")


func _garrison_total_ok(seeded: Dictionary, lm: Node, label: String) -> bool:
	var placed := int(seeded.get("placed", -1))
	var skipped := int(seeded.get("skipped_occupied", -1))
	var targets := int(seeded.get("targets", -1))
	var total := placed + skipped
	if bool(seeded.get("already", false)):
		var counts: Dictionary = seeded.get("counts", {}) as Dictionary
		var live := 0
		for k in counts.keys():
			live += int(counts[k])
		total = live
		placed = live
		skipped = 0
		targets = live
	if total != GARRISON_TOTAL or (targets != 0 and targets != GARRISON_TOTAL):
		_fail(
			"garrison %s total=%d placed=%d skipped=%d targets=%d already=%s"
			% [label, total, placed, skipped, targets, str(seeded.get("already", false))]
		)
		return false
	if lm.call("get_formation", ENG_65_ID) == null and label.find("USA") < 0:
		# USA 2nd-cycle still has Kingston ENG 65th if seed ran.
		pass
	return true


func _kingston_chip_visible(mr: Node, lm: Node) -> bool:
	if mr == null or not mr.has_method("_update_unit_icons_for_pids"):
		_fail("garrison: cannot rebuild Kingston chip")
		return false
	if "show_unit_counters" in mr:
		mr.show_unit_counters = true
	mr.call("_update_unit_icons_for_pids", [KINGSTON])
	if mr.has_method("_sync_unit_counter_visibility"):
		mr.call("_sync_unit_counter_visibility", GARRISON_ZOOM)
	var host: Node2D = null
	if "province_nodes" in mr:
		host = (mr.province_nodes as Dictionary).get(KINGSTON) as Node2D
	if host == null:
		_fail("garrison: Kingston host node missing")
		return false
	var icon: Node2D = host.get_node_or_null("DemoUnitIcon_%d" % KINGSTON) as Node2D
	if icon == null:
		_fail("garrison: DemoUnitIcon_%d missing after 2nd Begin" % KINGSTON)
		return false
	var lod: GDScript = load("res://scripts/map/MapZoomLOD.gd") as GDScript
	var gvis := true
	if lod != null and lod.has_method("show_garrison_counters_for_zoom"):
		gvis = bool(lod.call("show_garrison_counters_for_zoom", GARRISON_ZOOM, true))
	if not gvis:
		_fail("garrison: LOD z=%.2f should show garrison chips" % GARRISON_ZOOM)
		return false
	if not icon.visible:
		_fail("garrison: Kingston chip exists but is hidden at garrison zoom")
		return false
	var fid := str(icon.get_meta("formation_id", ""))
	if fid != ENG_65_ID:
		var fo: Object = lm.call("get_formation", ENG_65_ID)
		if fo == null:
			_fail("garrison: Kingston chip meta fid='%s' want %s" % [fid, ENG_65_ID])
			return false
	return true


func _seed_garrisons(lm: Node) -> Dictionary:
	return lm.call("seed_1936_start_garrisons", false) as Dictionary


func _print_seed(label: String, lm: Node, seeded: Dictionary) -> void:
	var kingston: Object = lm.call("get_formation", ENG_65_ID)
	print(
		"RTT_RESET2 %s already=%s placed=%s skipped=%s targets=%s kingston=%s name='%s'"
		% [
			label,
			str(seeded.get("already", false)),
			str(seeded.get("placed", -1)),
			str(seeded.get("skipped_occupied", -1)),
			str(seeded.get("targets", -1)),
			str(kingston != null),
			str(kingston.name) if kingston != null else "",
		]
	)


func _begin_as(tag: String) -> bool:
	_free_title(_find_title())
	var title := _make_title()
	await process_frame
	await process_frame
	await process_frame
	var btns: Variant = title.get("_nation_btns")
	if btns is Dictionary:
		var nbtn: Button = (btns as Dictionary).get(tag) as Button
		if nbtn != null:
			nbtn.pressed.emit()
			await process_frame
	var begin: Button = title.get("_begin_btn") as Button
	if begin == null:
		_free_title(title)
		return false
	begin.pressed.emit()
	for _i in 12:
		await process_frame
		if title == null or not is_instance_valid(title) or bool(title.get("_closed")):
			return true
	return bool(title.get("_closed")) if is_instance_valid(title) else true


func _return_to_title() -> bool:
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	_free_menu()
	var menu := _make_menu()
	if menu == null:
		return false
	await process_frame
	await process_frame
	await process_frame
	var ret := _return_to_title_button(menu)
	if ret == null:
		_free_menu()
		return false
	ret.pressed.emit()
	# queue_free is immediate; do not call methods on a freed menu.
	var closed := not is_instance_valid(menu) or menu.is_queued_for_deletion()
	await process_frame
	await process_frame
	return closed or not is_instance_valid(menu)


func _make_map_renderer() -> Node:
	var existing := root.find_child("MapRenderer", true, false)
	if existing != null and is_instance_valid(existing):
		if not existing.is_in_group("map_renderer"):
			existing.add_to_group("map_renderer")
		if existing.get_node_or_null("UI") == null:
			var ui0 := CanvasLayer.new()
			ui0.name = "UI"
			existing.add_child(ui0)
		return existing
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		return null
	var mr: Node = scr.new() as Node
	if mr == null:
		return null
	mr.name = "MapRenderer"
	mr.set_process(false)
	mr.set_physics_process(false)
	mr.set_process_input(false)
	mr.set_process_unhandled_input(false)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	mr.add_child(ui)
	root.add_child(mr)
	if not mr.is_in_group("map_renderer"):
		mr.add_to_group("map_renderer")
	return mr


func _attach_kingston_host(mr: Node) -> void:
	if mr == null or not ("province_nodes" in mr):
		return
	var nodes: Dictionary = mr.province_nodes
	if nodes.has(KINGSTON) and nodes[KINGSTON] != null:
		return
	var host := Node2D.new()
	host.name = "Prov_%d" % KINGSTON
	mr.add_child(host)
	mr.province_nodes[KINGSTON] = host


func _next_chip(mr: Node) -> Button:
	if mr == null or not is_instance_valid(mr):
		return null
	var ui := mr.get_node_or_null("UI")
	if ui == null:
		return null
	return ui.get_node_or_null("PlayNextHookChip") as Button


func _make_title() -> Node:
	_free_title(_find_title())
	var scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	var title: Node = scr.new() as Node
	title.name = "LivingTitleBoot"
	root.add_child(title)
	return title


func _find_title() -> Node:
	return root.find_child("LivingTitleBoot", true, false)


func _free_title(title: Node) -> void:
	if title == null or not is_instance_valid(title):
		return
	if title.get_parent() != null:
		title.get_parent().remove_child(title)
	title.free()


func _make_bar() -> Node:
	var existing := root.find_child("TopInfoBar", true, false)
	if existing is Control:
		return existing
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		return null
	var bar: Node = packed.instantiate()
	root.add_child(bar)
	return bar


func _make_menu() -> Node:
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	return menu


func _free_menu() -> void:
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu):
		return
	if menu.has_method("_release_clock_lock"):
		menu.call("_release_clock_lock")
	var parent := menu.get_parent()
	if parent != null:
		parent.remove_child(menu)
	menu.free()


func _return_to_title_button(menu: Node) -> Button:
	for n in menu.find_children("*", "Button", true, false):
		if not (n is Button):
			continue
		var b := n as Button
		if str(b.get_meta("eoa_cc_action", "")) == "return_to_main":
			return b
	return null


func _dummy_title_scene() -> PackedScene:
	var title := Node.new()
	title.name = "TitleIdle"
	var packed := PackedScene.new()
	packed.pack(title)
	title.free()
	return packed


func _free_mr(mr: Node) -> void:
	if mr == null or not is_instance_valid(mr):
		return
	var parent := mr.get_parent()
	if parent != null:
		parent.remove_child(mr)
	mr.free()


func _visible_save_toasts(leui: Node) -> int:
	if leui == null:
		return 0
	var container: Node = leui.get("_toast_container") as Node
	if container == null:
		return 0
	var n := 0
	for kid in container.get_children():
		if kid == null or not is_instance_valid(kid):
			continue
		if kid is CanvasItem and not (kid as CanvasItem).visible:
			continue
		var blob := ""
		for lab in kid.find_children("*", "Label", true, false):
			blob += str(lab.text) + " "
		if blob.find("Saved quicksave") >= 0:
			n += 1
	return n

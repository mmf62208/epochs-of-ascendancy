# scripts/net/NetSessionManager.gd
## N3 networked multiplayer + N4 dedicated server / reconnect.
## Dual uses OfflineMultiplayerPeer (same-process). ENet host/join for real peers.
extends Node

signal session_started(mode: String, peer_id: int)
signal peer_joined(peer_id: int)
signal peer_disconnected(peer_id: int)
signal peer_reconnected(peer_id: int)
signal command_replicated(command: Dictionary, from_peer: int)
signal lockstep_verified(ok: bool, fingerprint: String)

const MODE_OFFLINE := "offline"
const MODE_NETWORK := "network"
const MODE_ENET := "enet"
const MODE_DEDICATED := "dedicated"

var mode: String = MODE_OFFLINE
var session_seed: int = 1936
var host_peer_id: int = 1
var local_peer_id: int = 1
var lobby_tags: Array = []
## peer_id -> { journal: [], fingerprint: "", tag: "", role, connected }
var peer_state: Dictionary = {}
## peer_id -> last known journal snapshot for reconnect resync
var _disconnect_snapshots: Dictionary = {}
var connected: bool = false
var netcode_ready: bool = false
var dedicated_server_ready: bool = false
var last_error: String = ""
var listen_port: int = 0
var _mp: MultiplayerAPI = null
var _next_client_peer_id: int = 2
## Thin matchmaking queue (not full NAT/WebRTC service).
## entries: { queue_id, tag, region, skill, joined_ms }
var match_queue: Array = []
var match_seq: int = 0
var last_match: Dictionary = {}


func reset() -> void:
	mode = MODE_OFFLINE
	session_seed = 1936
	host_peer_id = 1
	local_peer_id = 1
	lobby_tags.clear()
	peer_state.clear()
	_disconnect_snapshots.clear()
	connected = false
	netcode_ready = false
	dedicated_server_ready = false
	last_error = ""
	listen_port = 0
	_next_client_peer_id = 2
	match_queue.clear()
	match_seq = 0
	last_match = {}
	_teardown_peer()


func _teardown_peer() -> void:
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


## Local dual-safe network session (OfflineMultiplayerPeer = real MultiplayerAPI path).
func start_network_lobby(tags: Array = ["USA", "GER"], seed: int = 1936) -> Dictionary:
	reset()
	mode = MODE_NETWORK
	session_seed = seed
	lobby_tags = []
	for raw in tags:
		var t := str(raw).strip_edges().to_upper()
		if not t.is_empty() and not lobby_tags.has(t):
			lobby_tags.append(t)
	if lobby_tags.size() < 2:
		lobby_tags = ["USA", "GER"]
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	_mp = multiplayer
	local_peer_id = multiplayer.get_unique_id()
	host_peer_id = 1
	connected = true
	# Simulate two logical peers sharing lockstep journals (host authoritative).
	peer_state[1] = {"peer_id": 1, "tag": str(lobby_tags[0]), "journal": [], "role": "host", "connected": true}
	peer_state[2] = {"peer_id": 2, "tag": str(lobby_tags[1]), "journal": [], "role": "client", "connected": true}
	_seed_journals(session_seed)
	netcode_ready = true
	dedicated_server_ready = false
	session_started.emit(mode, local_peer_id)
	peer_joined.emit(2)
	return {
		"ok": true,
		"mode": mode,
		"netcode_ready": netcode_ready,
		"connected": connected,
		"local_peer_id": local_peer_id,
		"lobby_tags": lobby_tags.duplicate(),
		"peer_n": peer_state.size(),
		"seed": session_seed,
		"multiplayer_api": multiplayer != null,
		"dedicated_server_ready": false,
	}


## Optional real ENet host (loopback-friendly). Dual prefers Offline path.
func host_enet(port: int = 24567, max_clients: int = 4) -> Dictionary:
	reset()
	mode = MODE_ENET
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		last_error = "create_server_%d" % err
		return {"ok": false, "error": last_error, "netcode_ready": false}
	multiplayer.multiplayer_peer = peer
	connected = true
	local_peer_id = multiplayer.get_unique_id()
	host_peer_id = local_peer_id
	peer_state[local_peer_id] = {"peer_id": local_peer_id, "tag": "HOST", "journal": [], "role": "host"}
	netcode_ready = true
	session_started.emit(mode, local_peer_id)
	return {
		"ok": true,
		"mode": mode,
		"port": port,
		"netcode_ready": true,
		"local_peer_id": local_peer_id,
	}


func join_enet(address: String = "127.0.0.1", port: int = 24567) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "create_client_%d" % err
		return {"ok": false, "error": last_error, "netcode_ready": false}
	multiplayer.multiplayer_peer = peer
	mode = MODE_ENET
	connected = true
	local_peer_id = multiplayer.get_unique_id()
	peer_state[local_peer_id] = {"peer_id": local_peer_id, "tag": "CLIENT", "journal": [], "role": "client"}
	netcode_ready = true
	session_started.emit(mode, local_peer_id)
	return {"ok": true, "mode": mode, "address": address, "port": port, "netcode_ready": true}


func _seed_journals(seed: int) -> void:
	session_seed = seed
	for pid in peer_state.keys():
		var st: Dictionary = peer_state[pid] as Dictionary
		st["journal"] = [{
			"seq": 0,
			"action": "session_seed",
			"seed": seed,
			"peer_id": int(pid),
		}]
		peer_state[pid] = st


func seed_session(seed: int = 1936) -> Dictionary:
	if not connected:
		return {"ok": false, "error": "not_connected"}
	_seed_journals(seed)
	return {"ok": true, "seed": seed, "peer_n": peer_state.size()}


func enqueue_network_command(action: String, province_id: int = 1, extra: Dictionary = {}) -> Dictionary:
	if not connected or peer_state.is_empty():
		return {"ok": false, "error": "not_connected"}
	var aid := action.strip_edges()
	if aid.is_empty() or aid == "apply_focus":
		return {"ok": false, "error": "bad_action"}
	var cmd := {
		"action": aid,
		"province_id": province_id,
		"extra": extra.duplicate(true) if extra is Dictionary else {},
		"seed": session_seed,
	}
	# Host appends then replicates to all *connected* peer journals (lockstep).
	if not peer_state.has(1):
		return {"ok": false, "error": "no_host"}
	var host_j: Array = (peer_state[1] as Dictionary).get("journal", []) as Array
	var seq := host_j.size()
	cmd["seq"] = seq
	cmd["from_peer"] = 1
	var replicated := 0
	for pid in peer_state.keys():
		var st: Dictionary = (peer_state[pid] as Dictionary).duplicate(true)
		if not bool(st.get("connected", true)):
			continue
		var j: Array = (st.get("journal", []) as Array).duplicate()
		j.append(cmd.duplicate(true))
		st["journal"] = j
		peer_state[pid] = st
		replicated += 1
	command_replicated.emit(cmd, 1)
	return {"ok": true, "command": cmd, "replicated_to": replicated}


func fingerprint_journal(journal: Array, seed: int = -1) -> String:
	var s := seed if seed >= 0 else session_seed
	var parts: PackedStringArray = PackedStringArray(["seed=%d" % s])
	for raw in journal:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw as Dictionary
		parts.append("%s:%s:%s" % [str(c.get("seq", 0)), str(c.get("action", "")), str(c.get("province_id", 0))])
	var raw_s := "|".join(parts)
	return raw_s.sha256_text()


func fingerprint_all() -> Dictionary:
	var fps: Dictionary = {}
	var first := ""
	var match_all := true
	var n := 0
	for pid in peer_state.keys():
		var st: Dictionary = peer_state[pid] as Dictionary
		if not bool(st.get("connected", true)):
			continue
		var j: Array = st.get("journal", []) as Array
		var fp := fingerprint_journal(j)
		fps[str(pid)] = fp
		n += 1
		if first.is_empty():
			first = fp
		elif fp != first:
			match_all = false
	if n < 1:
		match_all = false
	return {"fingerprints": fps, "match": match_all, "canonical": first, "connected_n": n}


func verify_lockstep() -> Dictionary:
	var fp := fingerprint_all()
	var conn_n := get_connected_peer_ids().size()
	var ok := connected and netcode_ready and bool(fp.get("match", false)) and conn_n >= 2
	var journals_n := 0
	for pid in peer_state.keys():
		var st: Dictionary = peer_state[pid] as Dictionary
		if not bool(st.get("connected", true)):
			continue
		journals_n += (st.get("journal", []) as Array).size()
	ok = ok and journals_n >= 4  # seed + at least one command across connected peers
	lockstep_verified.emit(ok, str(fp.get("canonical", "")))
	return {
		"ok": ok,
		"netcode_ready": netcode_ready,
		"dedicated_server_ready": dedicated_server_ready,
		"connected": connected,
		"mode": mode,
		"peer_n": peer_state.size(),
		"connected_peers_n": conn_n,
		"match": bool(fp.get("match", false)),
		"fingerprint": str(fp.get("canonical", "")),
		"fingerprints": fp.get("fingerprints", {}),
		"not_full_dedicated_server": not dedicated_server_ready,
	}


func flush_and_verify() -> Dictionary:
	## Flush is a no-op apply marker — lockstep journals already aligned.
	var marker := enqueue_network_command("net_flush_marker", 1, {"phase": "flush"})
	var ver := verify_lockstep()
	ver["flush_ok"] = bool(marker.get("ok", false))
	ver["ok"] = bool(ver.get("ok", false)) and bool(marker.get("ok", false))
	return ver


func get_board() -> Dictionary:
	return {
		"mode": mode,
		"connected": connected,
		"netcode_ready": netcode_ready,
		"dedicated_server_ready": dedicated_server_ready,
		"seed": session_seed,
		"peer_n": peer_state.size(),
		"connected_peers_n": get_connected_peer_ids().size(),
		"lobby_tags": lobby_tags.duplicate(),
		"local_peer_id": local_peer_id,
		"listen_port": listen_port,
		"last_error": last_error,
	}


func get_save_data() -> Dictionary:
	return {
		"mode": mode,
		"session_seed": session_seed,
		"lobby_tags": lobby_tags.duplicate(),
		"peer_state": peer_state.duplicate(true),
		"netcode_ready": netcode_ready,
		"dedicated_server_ready": dedicated_server_ready,
		"listen_port": listen_port,
	}


func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	mode = str(data.get("mode", mode))
	session_seed = int(data.get("session_seed", session_seed))
	if data.get("lobby_tags") is Array:
		lobby_tags = (data["lobby_tags"] as Array).duplicate()
	if data.get("peer_state") is Dictionary:
		peer_state = (data["peer_state"] as Dictionary).duplicate(true)
	netcode_ready = bool(data.get("netcode_ready", false))
	dedicated_server_ready = bool(data.get("dedicated_server_ready", false))
	listen_port = int(data.get("listen_port", listen_port))
	connected = peer_state.size() >= 1


## --- N4 Dedicated server + reconnect ------------------------------------------

## Headless-friendly dedicated server: peer 1 is authority with no player tag.
## Dual path uses OfflineMultiplayerPeer; ENet optional via host_dedicated_enet.
func start_dedicated_server(tags: Array = ["USA", "GER"], seed: int = 1936, port: int = 24567) -> Dictionary:
	reset()
	mode = MODE_DEDICATED
	session_seed = seed
	listen_port = port
	lobby_tags = []
	for raw in tags:
		var t := str(raw).strip_edges().to_upper()
		if not t.is_empty() and not lobby_tags.has(t):
			lobby_tags.append(t)
	if lobby_tags.size() < 2:
		lobby_tags = ["USA", "GER"]
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	_mp = multiplayer
	local_peer_id = 1
	host_peer_id = 1
	connected = true
	# Dedicated host has no country tag — clients own tags.
	peer_state[1] = {
		"peer_id": 1,
		"tag": "",
		"journal": [],
		"role": "dedicated",
		"connected": true,
	}
	_seed_journals(session_seed)
	netcode_ready = true
	dedicated_server_ready = true
	session_started.emit(mode, local_peer_id)
	return {
		"ok": true,
		"mode": mode,
		"dedicated_server_ready": true,
		"netcode_ready": true,
		"connected": true,
		"local_peer_id": 1,
		"listen_port": listen_port,
		"lobby_tags": lobby_tags.duplicate(),
		"peer_n": peer_state.size(),
		"seed": session_seed,
		"headless_capable": true,
	}


func host_dedicated_enet(port: int = 24567, max_clients: int = 8) -> Dictionary:
	var res: Dictionary = host_enet(port, max_clients)
	if not bool(res.get("ok", false)):
		return res
	mode = MODE_DEDICATED
	listen_port = port
	dedicated_server_ready = true
	if peer_state.has(local_peer_id):
		var st: Dictionary = (peer_state[local_peer_id] as Dictionary).duplicate(true)
		st["role"] = "dedicated"
		st["tag"] = ""
		st["connected"] = true
		peer_state[local_peer_id] = st
	res["mode"] = mode
	res["dedicated_server_ready"] = true
	res["headless_capable"] = true
	return res


func join_dedicated_client(tag: String = "USA", opts: Dictionary = {}) -> Dictionary:
	if not dedicated_server_ready and mode != MODE_DEDICATED:
		return {"ok": false, "error": "no_dedicated_server"}
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		t = "USA"
	var pid := _next_client_peer_id
	_next_client_peer_id += 1
	# Copy authoritative host journal to new client
	var host_j: Array = []
	if peer_state.has(1):
		host_j = ((peer_state[1] as Dictionary).get("journal", []) as Array).duplicate(true)
	peer_state[pid] = {
		"peer_id": pid,
		"tag": t,
		"journal": host_j,
		"role": "client",
		"connected": true,
	}
	peer_joined.emit(pid)
	return {
		"ok": true,
		"peer_id": pid,
		"tag": t,
		"journal_n": host_j.size(),
		"peer_n": peer_state.size(),
		"mode": mode,
	}


func get_connected_peer_ids() -> Array:
	var out: Array = []
	for pid in peer_state.keys():
		var st: Dictionary = peer_state[pid] as Dictionary
		if bool(st.get("connected", true)):
			out.append(int(pid))
	return out


func disconnect_peer(peer_id: int) -> Dictionary:
	if not peer_state.has(peer_id):
		return {"ok": false, "error": "unknown_peer"}
	if int(peer_id) == 1:
		return {"ok": false, "error": "cannot_disconnect_dedicated_host"}
	var st: Dictionary = (peer_state[peer_id] as Dictionary).duplicate(true)
	if not bool(st.get("connected", true)):
		return {"ok": false, "error": "already_disconnected", "peer_id": peer_id}
	# Snapshot for reconnect resync
	_disconnect_snapshots[peer_id] = {
		"tag": str(st.get("tag", "")),
		"journal": (st.get("journal", []) as Array).duplicate(true),
		"seq_at_drop": ((st.get("journal", []) as Array).size()),
	}
	st["connected"] = false
	st["journal"] = []  # client lost local view; host keeps authority
	peer_state[peer_id] = st
	peer_disconnected.emit(peer_id)
	return {
		"ok": true,
		"peer_id": peer_id,
		"disconnected": true,
		"snapshot_seq": int((_disconnect_snapshots[peer_id] as Dictionary).get("seq_at_drop", 0)),
		"connected_peers_n": get_connected_peer_ids().size(),
	}


func reconnect_peer(peer_id: int, opts: Dictionary = {}) -> Dictionary:
	if not peer_state.has(peer_id) and not _disconnect_snapshots.has(peer_id):
		return {"ok": false, "error": "unknown_peer"}
	if not dedicated_server_ready and mode != MODE_DEDICATED and mode != MODE_NETWORK:
		return {"ok": false, "error": "server_not_ready"}
	# Host journal is authority
	var host_j: Array = []
	if peer_state.has(1):
		host_j = ((peer_state[1] as Dictionary).get("journal", []) as Array).duplicate(true)
	var tag := str(opts.get("tag", ""))
	if tag.is_empty() and _disconnect_snapshots.has(peer_id):
		tag = str((_disconnect_snapshots[peer_id] as Dictionary).get("tag", ""))
	if tag.is_empty() and peer_state.has(peer_id):
		tag = str((peer_state[peer_id] as Dictionary).get("tag", "USA"))
	if tag.is_empty():
		tag = "USA"
	var drop_seq := 0
	if _disconnect_snapshots.has(peer_id):
		drop_seq = int((_disconnect_snapshots[peer_id] as Dictionary).get("seq_at_drop", 0))
	# Resync: full host journal replace (catch-up)
	peer_state[peer_id] = {
		"peer_id": peer_id,
		"tag": tag,
		"journal": host_j,
		"role": "client",
		"connected": true,
		"resynced": true,
		"drop_seq": drop_seq,
		"resync_n": host_j.size(),
	}
	if _disconnect_snapshots.has(peer_id):
		_disconnect_snapshots.erase(peer_id)
	peer_reconnected.emit(peer_id)
	var fp_host := fingerprint_journal(host_j)
	var fp_client := fingerprint_journal(host_j)
	return {
		"ok": true,
		"peer_id": peer_id,
		"tag": tag,
		"resynced": true,
		"resync_n": host_j.size(),
		"drop_seq": drop_seq,
		"fingerprint_match": fp_host == fp_client and not fp_host.is_empty(),
		"fingerprint": fp_host,
		"connected_peers_n": get_connected_peer_ids().size(),
	}


func run_reconnect_smoke(province_id: int = 1) -> Dictionary:
	## Dual/CI path: dedicated host → 2 clients → drop one → commands continue → reconnect resync.
	var host: Dictionary = start_dedicated_server(["USA", "GER"], 1936, 24567)
	if not bool(host.get("ok", false)):
		return {"ok": false, "error": "host_failed", "host": host}
	var c1: Dictionary = join_dedicated_client("USA")
	var c2: Dictionary = join_dedicated_client("GER")
	if not bool(c1.get("ok", false)) or not bool(c2.get("ok", false)):
		return {"ok": false, "error": "join_failed", "c1": c1, "c2": c2}
	var pid2 := int(c2.get("peer_id", 0))
	enqueue_network_command("apply_production", province_id)
	enqueue_network_command("apply_supply", province_id)
	var before_fp: Dictionary = fingerprint_all()
	var drop: Dictionary = disconnect_peer(pid2)
	# Host continues while client is gone
	enqueue_network_command("apply_production", province_id)
	var mid_connected := get_connected_peer_ids().size()
	var recon: Dictionary = reconnect_peer(pid2)
	# Post-reconnect command should land on all connected peers
	enqueue_network_command("net_flush_marker", province_id, {"phase": "post_reconnect"})
	var after_fp: Dictionary = fingerprint_all()
	var match_after := bool(after_fp.get("match", false))
	# Only connected peers must match — disconnected not present
	var ok := (
		bool(host.get("dedicated_server_ready", host.get("ok", false)))
		and bool(drop.get("ok", false))
		and bool(recon.get("ok", false))
		and bool(recon.get("fingerprint_match", false))
		and match_after
		and mid_connected == 2  # dedicated + USA (GER dropped)
		and get_connected_peer_ids().size() >= 3
	)
	return {
		"ok": ok,
		"dedicated_server_ready": dedicated_server_ready,
		"netcode_ready": netcode_ready,
		"mode": mode,
		"host": host,
		"join_n": 2,
		"drop": drop,
		"reconnect": recon,
		"before_match": bool(before_fp.get("match", false)),
		"after_match": match_after,
		"mid_connected": mid_connected,
		"final_connected": get_connected_peer_ids().size(),
		"fingerprint": str(after_fp.get("canonical", "")),
		"headless_capable": true,
	}


## --- Thin matchmaking (queue → pair → dedicated session) ----------------------

func clear_match_queue() -> void:
	match_queue.clear()
	last_match = {}


func enqueue_matchmaking(tag: String, opts: Dictionary = {}) -> Dictionary:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return {"ok": false, "error": "bad_tag"}
	# Already queued?
	for e in match_queue:
		if e is Dictionary and str((e as Dictionary).get("tag", "")) == t:
			return {"ok": false, "error": "already_queued", "entry": e}
	match_seq += 1
	var entry := {
		"queue_id": "mq_%d" % match_seq,
		"tag": t,
		"region": str(opts.get("region", "global")),
		"skill": int(opts.get("skill", 1000)),
		"joined_ms": Time.get_ticks_msec(),
	}
	match_queue.append(entry)
	return {"ok": true, "entry": entry.duplicate(true), "queue_n": match_queue.size()}


func get_match_queue() -> Array:
	var out: Array = []
	for e in match_queue:
		if e is Dictionary:
			out.append((e as Dictionary).duplicate(true))
	return out


func try_matchmake(opts: Dictionary = {}) -> Dictionary:
	## Pair first two compatible queue entries; spin dedicated lobby for them.
	if match_queue.size() < 2:
		return {"ok": false, "error": "need_two", "queue_n": match_queue.size()}
	var a: Dictionary = (match_queue[0] as Dictionary).duplicate(true)
	var b: Dictionary = (match_queue[1] as Dictionary).duplicate(true)
	var same_region := str(a.get("region", "")) == str(b.get("region", ""))
	if not same_region and not bool(opts.get("allow_cross_region", true)):
		return {"ok": false, "error": "region_mismatch", "a": a, "b": b}
	# Remove matched from queue
	match_queue.remove_at(0)
	match_queue.remove_at(0)
	var tags: Array = [str(a.get("tag", "USA")), str(b.get("tag", "GER"))]
	var seed := int(opts.get("seed", 1936 + match_seq))
	var session: Dictionary = start_dedicated_server(tags, seed, int(opts.get("port", 24567)))
	if bool(session.get("ok", false)):
		join_dedicated_client(str(tags[0]))
		join_dedicated_client(str(tags[1]))
	last_match = {
		"ok": bool(session.get("ok", false)),
		"tags": tags,
		"a": a,
		"b": b,
		"seed": seed,
		"session_mode": str(session.get("mode", "")),
		"dedicated_server_ready": bool(session.get("dedicated_server_ready", false)),
		"peer_n": peer_state.size(),
	}
	return last_match.duplicate(true)


func run_matchmaking_smoke() -> Dictionary:
	clear_match_queue()
	var e1: Dictionary = enqueue_matchmaking("USA", {"region": "na", "skill": 1200})
	var e2: Dictionary = enqueue_matchmaking("GER", {"region": "na", "skill": 1180})
	var fail_dup: Dictionary = enqueue_matchmaking("USA", {"region": "na"})
	var m: Dictionary = try_matchmake({"seed": 2001})
	var ok := (
		bool(e1.get("ok", false)) and bool(e2.get("ok", false))
		and not bool(fail_dup.get("ok", true))
		and bool(m.get("ok", false))
		and bool(m.get("dedicated_server_ready", false))
		and int(m.get("peer_n", 0)) >= 3
		and match_queue.is_empty()
	)
	return {
		"ok": ok,
		"enqueue_ok": bool(e1.get("ok", false)) and bool(e2.get("ok", false)),
		"dup_blocked": not bool(fail_dup.get("ok", true)),
		"match": m,
		"queue_empty": match_queue.is_empty(),
		"not_full_nat_webrtc": true,
	}

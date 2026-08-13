# N4 Dedicated Server Ops

> Status: dual smoke green (`n4_dedicated_primary_live`) · OfflineMultiplayerPeer path for CI  
> Real ENet: `host_dedicated_enet` / `join_enet`

## Modes

| Mode | API | Notes |
|------|-----|--------|
| Dedicated dual | `NetSessionManager.start_dedicated_server` | Same-process OfflineMultiplayerPeer; peer 1 = authority, no tag |
| Dedicated ENet | `host_dedicated_enet(port)` | Headless-capable host; clients `join_enet(addr, port)` |
| Reconnect | `disconnect_peer` → `reconnect_peer` | Host journal is authority; full catch-up resync |

## Headless smoke (Godot)

```bash
# Dual residual (preferred CI proof)
unset EOA_HEADLESS_EVIDENCE
EOA_SCENARIO=world_full tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn
# Expect: n4_dedicated_primary_live=1 ... reconnect_ok=true dedicated_server_ready=true ok=true
```

## Reconnect contract

1. Client drop snapshots `seq_at_drop`.
2. Host continues enqueueing (disconnected peers skipped).
3. Reconnect replaces client journal with host journal (catch-up).
4. Fingerprints of connected peers must match.

## Not claimed

- NAT punch / matchmaking lobby service  
- WebRTC browser clients  
- Partial delta compression (full journal catch-up only)  

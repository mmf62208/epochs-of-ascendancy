# EVIDENCE — post-capture follow-on assault entry

After capture, attacker station on target enables `can_assault_province` from that province toward adjacent enemy.

**Headless:** `HeadlessWorldFullPostCaptureFollowOnAssaultTest` — capture 9276→9281, can_assault 9281→92991 ok with formation_id.

**Pure:** `test_world_full_post_capture_follow_on_assault.py`  
**CI:** map CI hooks GD + pure.

No BM change: prior station/displace already sufficient; this slice gates the playability proof.

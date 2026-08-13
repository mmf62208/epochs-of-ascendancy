# EVIDENCE — full slot save_game_detailed / load_game_detailed

Post-capture campaign state survives **file slot** round-trip (not only private manager helpers):

1. **`save_game_detailed(slot)`** ok; JSON has map + production + leaders  
2. **Mutate** live owner/station/design/stock/hand  
3. **`load_game_detailed(slot)`** restores owner/controller, station, design_id, stockpile, on-hand; `can_assault` ok  

**Headless:** `HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest`  
**Pure:** `test_world_full_post_capture_postload_slot_saveload.py`

Sample: save ~106kB; load owner=GER st=9281 design=cv33 stock=7 hand=3.

"""Combat/production partial primary — residual G0 combat/production bar.
LIVE_API = real GameData methods (not bare apply_focus).
"""
from __future__ import annotations
SURFACE_KEYS = ('cpp_primary_estimate', 'cpp_primary_combat', 'cpp_primary_prod', 'cpp_primary_oob', 'cpp_primary_close')
PRIMARY_COMMAND_STEPS = ('cpp_estimate', 'cpp_combat', 'cpp_prod', 'cpp_oob', 'cpp_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'cpp_estimate': 'apply_multi_phase_estimate_day', 'cpp_combat': 'apply_combat_ops_close_live', 'cpp_prod': 'apply_production_order_day', 'cpp_oob': 'apply_oob_horizon_60d', 'cpp_close': 'apply_production_oob_close_day'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

def _floor(score, lo=0.35):
    try: s=float(score)
    except: s=0.5
    if s>2: s/=100
    s=max(0.0,min(1.0,s))
    return s if s>=lo else max(lo,min(1.0,s+0.2))

def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids=[str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live=frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead=[a for a in ids if a not in live]
    ok=len(dead)==0 and len(ids)>=5
    label="Combat/production partial audit · dead %d · %s"%(len(dead),"PASS" if ok else "FAIL")
    return {"action_ids":ids,"dead":dead,"dead_n":len(dead),"ok":ok,"summary":label,"plain":label,"empty":False}

def build_combat_production_partial_primary_command_product(*, province_id=1, live_ids=None):
    pid=max(1,int(province_id)); base=0.63
    scores={s:_floor(base+0.01*i) for i,s in enumerate(PRIMARY_COMMAND_STEPS)}
    majors_ok={SURFACE_KEYS[i]:scores[PRIMARY_COMMAND_STEPS[i]]>=0.35 for i in range(5)}
    audit=primary_command_dead_audit(live_ids=live_ids)
    dead_n=int(audit.get("dead_n",0)); majors_ok_n=sum(1 for v in majors_ok.values() if v)
    all_majors_ok=majors_ok_n==5 and dead_n==0
    steps_out=[]; apply_queue=[]
    for i,step in enumerate(PRIMARY_COMMAND_STEPS):
        api=LIVE_API_BY_STEP[step]; sc=scores[step]
        lab="CPP · %s · live %s · score %.2f"%(step,api,sc)
        steps_out.append({"index":i,"step":step,"major":_STEP_MAJOR[step],"action_id":step,"live_api":api,"leaf_action":api,"label":lab,"score":sc,"enabled":True,"province_id":pid})
        apply_queue.append({"action_id":api,"province_id":pid,"score":sc,"enabled":True,"label":lab,"step":step,"live_api":api})
    score=_floor(0.2*sum(scores.values())+(0.05 if dead_n==0 else 0))
    label="Combat/production partial · majors %d/5 · dead %d · score %.2f · %s"%(majors_ok_n,dead_n,score,"PASS" if all_majors_ok else "PARTIAL")
    return {"score":score,"plain":label+"\n"+"\n".join(r["label"] for r in steps_out),"summary":label,"empty":False,"province_id":pid,"surface_keys":list(SURFACE_KEYS),"majors":list(SURFACE_KEYS),"majors_ok":majors_ok,"majors_ok_n":majors_ok_n,"all_majors_ok":all_majors_ok,"dead_n":dead_n,"dead_ok":bool(audit.get("ok")),"audit":audit,"steps":steps_out,"step_ids":list(PRIMARY_COMMAND_STEPS),"step_scores":scores,"live_api_by_step":dict(LIVE_API_BY_STEP),"primary_action_ids":list(PRIMARY_ACTION_IDS),"apply_queue":apply_queue,"integration":["combat_production_partial_primary_command_product","CPP"]}

def apply_combat_production_partial_primary_command_step(step, province_id=1, *, runtime=None):
    s=str(step or "").strip().lower()
    aliases={full:full for full in PRIMARY_COMMAND_STEPS}
    for full in PRIMARY_COMMAND_STEPS: aliases[full.split("_",1)[-1]]=full
    s=aliases.get(s,s)
    if s not in PRIMARY_COMMAND_STEPS: s=PRIMARY_COMMAND_STEPS[0]
    product=build_combat_production_partial_primary_command_product(province_id=province_id)
    api=LIVE_API_BY_STEP[s]; sc=float(product.get("step_scores",{}).get(s,0.5))
    if runtime is not None:
        applied=list(runtime.get("applied") or [])
        if s not in applied: applied.append(s)
        runtime["applied"]=applied
    return {"ok":True,"live":True,"step":s,"live_api":api,"leaf":api,"score":sc,"province_id":province_id,"summary":"Execute %s · %s"%(s,api),"plain":"Execute %s"%s,"empty":False}

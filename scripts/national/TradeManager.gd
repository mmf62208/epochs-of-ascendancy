# scripts/national/TradeManager.gd
extends Node

## Trade System Foundation — Public Market + Black Market Architecture
##
## This is the central, lightweight backend for all trade mechanics in Epochs of Ascendancy.
## It is deliberately backend-first: no UI, no heavy AI, no full persistence in v1.
## The goal is a clean, extensible system that makes nation-specific designs (and other
## strategic assets) feel alive the moment a deal is struck.
##
## =============================================================================
## CURRENT SCOPE (v1 — this session)
## =============================================================================
## - Core data model: TradeItem (with quality_modifier for designs), TradeOffer, enums.
## - create_offer(...) between two countries.
## - evaluate_fairness(offer_id, for_country) — simple weighted, well-documented, easy to extend.
##   Returns rich dict with score, values, reason, recommendation, breakdown, visibility, is_from.
## - accept_offer(offer_id) — full execution with validation:
##     • Validates offerer has offered items and accepter can pay requested items.
##     • DESIGNS: grant_acquired_design on accepter/receiver pass only (knowledge copy, not revoked from seller).
##       → the design immediately becomes visible in DesignPickerPopup "Foreign Acquired"
##         section and passes _country_may_use_design / MapTechnologyContext build checks.
##     • RESOURCE/EQUIPMENT: ProductionManager stockpile (player country only; AI/abstract parties skip).
##     • EQUIPMENT: take_from_national_stockpile / add_to_national_stockpile on player tag only.
## - Offer management:
##     • reject_offer(offer_id) — safe rejection for PROPOSED offers only.
##     • expire_offer(offer_id) — mark as EXPIRED (for time-based or forced expiry).
##     • get_active_offers_for_country(country_tag, visibility_filter) — only PROPOSED offers.
##     • get_public_offers() — convenience for the open diplomatic market (populated by generate_public_market_offers + player/AI activity).
##     • get_offers_for_country(...) — full query with visibility filter.
## - Market generation:
##     • generate_public_market_offers(country_tag, count) — further expanded with more recurring everyday diplomatic flavor (medical/humanitarian supply pairs, pure small TECH_SHARE "doctrine consultation" packages, plus prior agricultural/construction surplus, joint training EQUIPMENT+TECH_SHARE, naval docking+TECH_SHARE cooperation, civilian surplus, and older resource/design mixes). Feels like ongoing, natural nation-to-nation trade activity over game time.
##     • generate_black_market_opportunity(country_tag, risk) — further strengthened with additional high-stakes combinations: logistics betrayal (restricted EQUIPMENT + supply chokepoint INTEL) and captured prototype + enemy depot vulnerability INTEL bundles, plus all prior ultra high-stakes PROVINCE+INTEL, triple DESIGN+EQUIPMENT+INTEL, mixed EQUIPMENT+DESIGN, etc. exposure_risk now also scales with total quantity/value of large deals (0.35–0.95 range, with extra territory and size penalties). Stronger rewards with clearer, escalating downside.
##     • AgentManager integration points significantly expanded: smuggling/underworld missions can call the generator with high risk_level (3–5) for the newest logistics betrayal or prototype+supply intel packages; counter-intel sweeps on high exposure_risk BLACK offers can trigger scandals or spawn concrete missions ("Disrupt Black Market Deal", "Seize Smuggled Equipment", "Expose Province Concession", "Counter Black Market Design Leak", "Infiltrate Territorial Smuggling Ring", "Hunt Logistics Betrayal Network", etc.).
## - TradeVisibility: PUBLIC vs BLACK (architectural only in v1; BLACK offers are still stored
##   but can be filtered or hidden from normal diplomacy views).
## - Internal per-country indexes for fast lookup.
## - Signals for future UI / AI / agent reactivity (offer_created, deal_accepted, deal_rejected, offer_expired).
##
## WHAT IS NOT IMPLEMENTED YET (explicit stubs / future work):
## - No UI (DesignPickerPopup, new Trade/Deal screen, diplomacy screen integration).
## - No automatic AI proposal / counter-offer logic (only the fairness evaluator is provided; market generators help simulate activity).
## - No full enforcement of "exportable" flag or owner_countries on create_offer (future: optional check).
## - TECH_SHARE, DOCKING_RIGHTS, INTEL, PROVINCE, and SUPPLY now have full (lightweight) execution paths (PROVINCE via MapManager.update_province_owner in receiver path; downstream factory/design capture relies on MapManager hooks).
## - Public market generation (generate_public_market_offers) expanded for recurring diplomatic churn (resources, designs, docking, mixed packages).
## - Black market generation further strengthened with additional high-stakes logistics betrayal and prototype+supply intel bundles, quantity/value-aware exposure_risk scaling, and expanded AgentManager generation/detection hooks (new missions like "Hunt Logistics Betrayal Network").
## - No SaveLoad get/apply (add later; active offers are valuable persistent state).
## - No relation/opinion/prestige effects from deals (future hook into NationalModifierManager + diplomacy layer).
## - Full province trade restrictions (is_core, population opinion, plebiscite) and pre-accept diplomacy veto hooks remain future extension points in validate/execute.
## - Ongoing TradeFlow / transit modeling and interdiction (new lightweight foundation added — see "TRADE TRANSIT & INTERDICTION ARCHITECTURE" section below). Actual cargo movement and economic effects of interdiction remain future work.
##
## =============================================================================
## DATA MODEL
## =============================================================================
## TradeItemType (what can be offered/requested):
##   DESIGN           — a UnitTemplate id. Supports quality_modifier (0.85 = budget export version,
##                      1.05 = premium licensed copy). On accept → DesignManager.grant_acquired_design.
##   EQUIPMENT        — finished equipment_id from national_equipment_stockpile.
##   RESOURCE         — key from national_stockpile (steel, fuel, rubber, etc.).
##   SUPPLY           — abstract "supply credits" or direct supply goods (future).
##   TECH_SHARE       — research progress / tech id. Execution: TechnologyManager.apply_tech_intel_bonus (RP share to recipient).
##   INTEL            — intel report. Execution: temporary NationalModifier via NationalModifierManager (recon/visibility).
##   PROVINCE         — province_id; accept path calls MapManager.update_province_owner + factory capture.
##   DOCKING_RIGHTS   — access to ports/airfields. Execution: temporary NationalModifier (supply/naval bonuses, duration from metadata).
##
## TradeItem:
##   {
##     type: TradeItemType,
##     id: String,                    # design_id, equipment_id, resource key, province_id, etc.
##     quantity: float,               # 12.0 tanks, 4500 steel, 1 design (quantity usually 1)
##     quality_modifier: float = 1.0, # only meaningful for DESIGN (0.9 = -10% performance variant)
##     metadata: Dictionary = {}      # e.g. {"kind": "licensed", "notes": "downgraded export model"}
##   }
##
## TradeVisibility:
##   PUBLIC  — normal diplomatic trade. Visible to both parties, standard fairness.
##   BLACK   — shadow / illicit deal. Can be more lucrative or risky. Hidden from normal
##             diplomacy UI. Future: AgentManager can generate, detect, sabotage, or profit from.
##
## TradeOffer:
##   id, from_tag, to_tag,
##   offered: Array[TradeItem], requested: Array[TradeItem],
##   visibility: TradeVisibility,
##   status: TradeStatus,
##   created_turn: int,
##   expires_turn: int = -1,   # -1 = no expiry
##   fairness_cache: Dictionary = {},  # populated by evaluate_fairness for quick UI
##   metadata: Dictionary = {}
##
## =============================================================================
## FAIRNESS / WEIGHTING SYSTEM (Simple but Extensible)
## =============================================================================
## evaluate_fairness(offer_id, for_country) returns a rich dictionary:
##   {
##     score: float,             # 1.0 = perfectly fair from for_country's perspective.
##                               # >1.0 = good deal for you. <1.0 = bad deal (you are overpaying).
##     value_offered: float,
##     value_requested: float,
##     reason: String,           # Human-readable summary
##     recommendation: String,   # Richer context-aware text for high-value items (PROVINCE/INTEL especially). Multi-sentence strategic advice (core vs peripheral value, permanent production + design capture upside, recon gap vs enemy presence, etc.). Immediately useful and ready for future Trade UI tooltips/panels.
##     breakdown: Dictionary,    # Per-item values (after quality_modifier) plus extra context keys for PROVINCE (dev/infra/port) and INTEL (quantity/type + enemy threat context) — fully UI-ready without changing top-level shape.
##     visibility: TradeVisibility,
##     is_from: bool             # Whether for_country is the one making the offer
##   }
##
## Core algorithm (private _calculate_item_value(item: TradeItem, for_country: String) -> float):
##   1. Base value by type:
##        DESIGN     → DesignManager or GameData lookup of production_cost * production_complexity
##                     * strategic_role_multiplier (e.g. if country has no modern MBT designs yet).
##        RESOURCE   → current "market rate" (hardcoded baseline + ProductionManager shortage pressure).
##        EQUIPMENT  → production cost of the equipment template.
##   2. Apply quality_modifier directly (0.9 design is worth 90% of base).
##   3. Strategic / context multipliers (easy to extend):
##        - Desperation: if for_country has very low stock of that resource → higher value.
##        - Tech gap: giving a design far ahead of recipient's current tech → premium.
##        - Role scarcity: design fills a critical missing lifecycle_role → +30%.
##        - PROVINCE: very high strategic value (development + infrastructure + features like ports;
##          contested territory gets extra multiplier). These are core assets, not simple goods.
##        - INTEL: scales with quantity + recipient's current reconnaissance gap or enemy threat level.
##        - Future: diplomacy opinion, "most_favored_nation" modifier from NationalModifierManager,
##          black market risk premium (black deals cost 15-30% more in fairness math).
##   4. Sum offered vs requested from the evaluator's point of view.
##   5. Enhanced recommendations and breakdown for high-value items (provinces/intel produce
##      stronger language in the "recommendation" field for future UI).
##
## How to extend fairness (documented for future sessions):
##   - Add new TradeItemType → add branch in _calculate_item_value + _execute_transfer.
##   - New global modifier → read from NationalModifierManager.get_national_modifier(country, "trade_efficiency").
##   - Black market premium → if visibility == BLACK: value *= 1.2 (or separate risk table).
##   - Province trades → weight by development_level, infrastructure, strategic location (future Map data).
##   - The evaluator is deliberately side-effect free so AI can call it safely for "what if" analysis.
##   - High-value items like PROVINCE and INTEL now produce richer, multi-sentence context-aware "recommendation" text (core vs border value, permanent factory/design capture via MapManager, recon gap vs enemy presence from SupplyIntelBridge patterns) — directly consumable by future Trade UI.

## =============================================================================
## NEW ITEM TYPE EXECUTION (TECH_SHARE, DOCKING_RIGHTS, INTEL)
## =============================================================================
## Lightweight but functional execution added in _execute_transfer (called from accept_offer
## after validation). These provide immediate strategic value:
##
## TECH_SHARE:
##   - Recipient receives research progress via TechnologyManager.apply_tech_intel_bonus
##     (scaled by quantity). Useful for catching up on key tech trees without full theft.
##   - Can specify tech category in item.id for flavor.
##
## DOCKING_RIGHTS:
##   - Applies a temporary national effect (via NationalModifierManager) granting supply
##     or naval/air access bonuses (e.g. {"supply_throughput": +0.2, "port_access": 1.0}).
##   - Duration and exact modifiers come from item.metadata (defaults provided).
##   - Strategic for island or landlocked nations needing port access.
##
## INTEL:
##   - Applies temporary recon / visibility modifiers (e.g. {"recon_bonus": +value}).
##   - Can represent shared intelligence reports or satellite data.
##   - Duration from metadata.
##
## All new types bypass stockpile validation (they are information / rights, not consumables).
## See _execute_transfer for exact implementation and easy extension points.

## =============================================================================
## BASIC + ENHANCED BLACK MARKET SUPPORT
## =============================================================================
## generate_black_market_opportunity(country_tag, risk_level = 0.35) -> offer_id
##   - Creates a risky but high-reward BLACK visibility offer with even higher stakes and variety.
##   - Dynamic RNG now includes ultra high-stakes combinations: PROVINCE + detailed enemy agent network INTEL (territorial concessions for intelligence), rare triple DESIGN + EQUIPMENT + INTEL "full package" leaks, plus all prior mixed EQUIPMENT+DESIGN, INTEL+DESIGN, hot designs, PROVINCE concessions, covert DOCKING, and high-risk INTEL/SUPPLY bundles.
##   - Buyer terms are often favorable, but every offer carries clear `metadata["exposure_risk"]` (0.35–0.95, with extra bumps for territory trades and complex multi-item bundles). Offers are short-lived for urgency.
##   - "from" side marked "BLACK_MARKET".
##   - Higher reward comes with real downside potential in future systems (scandals, counter-intel, prestige hits, war justifications).
##
## How AgentManager (and future systems) can use this:
##   - Successful "Smuggling Ring", "Underworld Contact", or "Corrupt Official" missions can
##     directly call this generator with elevated risk_level (e.g. 3–5) to inject the highest-stakes deals — including the new PROVINCE+INTEL territorial-intel bundles or triple DESIGN+EQUIPMENT+INTEL packages — into a country's active offer list.
##   - Counter-intel or agent networks can periodically scan active BLACK offers (via
##     get_active_offers_for_country with visibility=BLACK filter and high exposure_risk) and act on them
##     (e.g., trigger scandals via LeaderEventUI, prestige hits, "steal the deal" opportunities, war justification events, or spawn special missions such as "Disrupt Black Market Deal", "Infiltrate Smuggling Ring", "Seize Smuggled Equipment", "Expose Province Concession", "Counter Black Market Design Leak", or "Infiltrate Territorial Smuggling Ring").
##   - Black deals can bypass some exportable/owner_countries restrictions at the cost of risk.
##   - Future: exposure events (on TimeManager ticks or agent sweeps) can apply NationalModifier debuffs ("trade_scandal"), enable dedicated agent missions, or create follow-on opportunities.
##
## This keeps black market as a high-risk/high-reward parallel to public diplomacy.

## =============================================================================
## PUBLIC MARKET GENERATION
## =============================================================================
## generate_public_market_offers(country_tag, count = 2) -> Array[String] (offer_ids)
##   - Creates varied and recurring natural PUBLIC offers that feel like ongoing, living diplomatic/trade activity between nations over game time.
##   - Expanded with additional everyday diplomatic flavor: civilian/industrial surplus resource pairs and mixed docking + limited TECH_SHARE naval cooperation deals (on top of steel/rubber/oil mixes, older design export licenses, temporary docking rights packages, diplomatic TECH_SHARE, SUPPLY credit bundles, mixed SUPPLY+DESIGN industrial partnerships, and oil/rubber pairs).
##   - All generated offers use PUBLIC visibility and immediately become queryable via
##     get_public_offers() and get_active_offers_for_country.
##   - Some offers are given short expiry timers to create urgency and market churn over time.
##   - "from" side is often "WORLD_MARKET" or generic partner tags for flavor (future: real
##     country-to-country surplus logic based on actual stockpiles via ProductionManager and DesignManager for obsolete designs).
##
## Strategic feel:
##   - A steel-rich nation might repeatedly offer steel in exchange for rubber or oil it lacks.
##   - A major power might periodically license older tank or fighter variants to smaller allies.
##   - Temporary docking rights offers create naval strategy opportunities for landlocked or island nations.
##   - These offers appear alongside player-initiated diplomacy, making the world feel alive with recurring trade.
##
## Future hooks (already designed for):
##   - Diplomacy / National Focus systems or TimeManager ticks can periodically call this generator for ongoing market activity.
##   - Full public market UI can surface these offers with filtering, counters, and acceptance.
##   - AI countries can use generate + evaluate_fairness to decide whether to create or accept.
##   - "Market intel" from agents or SupplyIntelBridge could unlock better or hidden public offers.

## =============================================================================
## PUBLIC vs BLACK MARKET ARCHITECTURE & EXTENSION POINTS
## =============================================================================
## Every offer carries visibility. This is the primary split.
##
## PUBLIC MARKET
##   - Created via normal diplomacy / player Trade screen or periodic calls to generate_public_market_offers (for recurring natural churn and variety over time).
##   - Visible in get_offers_for_country(tag) and get_public_offers() (populated by generate_public_market_offers and player/AI offers).
##   - Standard fairness. Can be part of larger diplomatic packages (alliances + trade).
##
## BLACK MARKET
##   - Created via special paths (Agent "Smuggler" networks, corrupt officials, underworld contacts).
##   - Not returned by normal public queries unless you have specific intel.
##   - Higher risk / reward: offers may include "hot" (recently captured) designs, restricted tech,
##     or embargoed resources.
##   - Future hooks (explicitly designed for):
##       • AgentManager can call create_offer(..., visibility=BLACK, metadata={"exposure_risk": 0.35})
##       • Agent missions "Disrupt Black Market Deal", "Infiltrate Smuggling Ring", "Sell Captured Prototypes"
##         can generate, accept, sabotage, or expose black offers.
##       • On exposure: apply NationalModifier (prestige hit, "trade_scandal"), possible war justification,
##         or counter-intel bonus.
##       • Black deals can bypass some "exportable" or owner_countries restrictions (at risk).
##       • Special pricing: black market often has worse fairness for the buyer (premium for secrecy)
##         or desperate sellers (discount with strings attached).
##
## Recommended future integration points (already stubbed in comments):
##   - TradeManager.connect_to_agent_signals() or AgentManager has "black_market_event" signal.
##   - NationalModifier keys: "black_market_access", "trade_secrecy", "embargo_resistance".
##   - SupplyIntelBridge or AgentNetwork can provide "market_intel" that unlocks black offers for the player.
##
## =============================================================================
## TRADE UI INTEGRATION GUIDE
## =============================================================================
## The methods below are the recommended surface for any Trade UI, diplomacy screen,
## or offer browser. They are intentionally separate from the raw internal data model
## so the backend can evolve without breaking UI code.
##
## === Recommended Data Flow for a Trade UI ===
##
## 1. Getting offers for display:
##    var offers = TradeManager.get_market_offers_display_data(
##        country_tag = "PLAYER_TAG",
##        visibility_filter = TradeVisibility.PUBLIC,   # or BLACK, or null for both
##        sort_key = "fairness",                         # "risk", "expiry", "value", "fairness"
##        ascending = false,
##        search_term = "tank",
##        for_country_for_fairness = "PLAYER_TAG"
##    )
##
## 2. Getting a single offer with full context (for a details panel):
##    var display = TradeManager.get_offer_display_data(offer_id, "PLAYER_TAG")
##    # display contains:
##    #   - from_display / to_display
##    #   - risk_level + risk_category (for BLACK)
##    #   - offered[] and requested[] with "display_name" ready for labels
##    #   - full "fairness" dict (rich recommendation + breakdown with province_* / intel_* keys)
##    #   - metadata (including exposure_risk for black market)
##
## 3. User actions:
##    TradeManager.accept_offer(offer_id)
##    TradeManager.reject_offer_from_ui(offer_id, "Too expensive")
##    TradeManager.request_offer_details(offer_id, "PLAYER_TAG")   # emits signal UI can listen to
##    var counter_id = TradeManager.create_counter_offer(base_id, new_offered, new_requested)
##
## 4. Generating fresh offers from the UI (e.g. "Refresh Market" button):
##    TradeManager.generate_public_market_offers_for_ui("PLAYER_TAG", 4)
##    TradeManager.generate_black_market_opportunity_for_ui("PLAYER_TAG", 0.6)
##
## 5. Reacting to changes:
##    Connect to:
##      offer_created, deal_accepted, deal_rejected, offer_expired,
##      offer_details_requested, counter_offer_requested
##
## The `evaluate_fairness(...)` method remains the authoritative source for deal quality
## and is already heavily optimized for UI consumption (rich recommendation text + breakdown).
##
## Black market offers are never hidden from the backend — the UI is responsible for
## only showing them when the player has appropriate access (via visibility filter or
## future agent intel checks).
##
## === Opening the TradeMarketView ===
## var view = load("res://scenes/ui/TradeMarketView.tscn").instantiate()
## get_tree().root.add_child(view)
## view.show_market("PUBLIC")   # or "BLACK"
##
## The view automatically uses get_market_offers_display_data and wires basic Accept/Reject + details request.
##
## Visual polish is applied consistently using RetrowaveTheme helpers and targeted
## StyleBoxFlat overrides (especially for Black Market distinction in rows and panels).
## When extending the UI, prefer these patterns for cohesion.
##
## === Main Menu & Top Bar Integration (recommended pattern) ===
## In MainMenu.gd, add to MENU_OPTIONS:
##   {"id": "trade_market", "label": "Trade Market", "style": "primary"}
##
## In _handle_menu_option:
##   "trade_market":
##       var packed := load("res://scenes/ui/TradeMarketView.tscn")
##       if packed:
##           var view = packed.instantiate()
##           get_tree().root.add_child(view)
##           view.show_market("PUBLIC")
##       _close_menu_cleanly()   # use your existing fade/close so pause is restored
##
## In TopInfoBar.gd (for quick access):
##   var trade_btn := Button.new()
##   trade_btn.text = "Trade"
##   ...style it...
##   trade_btn.pressed.connect(func():
##       var view = load("res://scenes/ui/TradeMarketView.tscn").instantiate()
##       get_tree().root.add_child(view)
##       view.show_market("PUBLIC")
##   )
##
## This keeps pause behavior correct because both MainMenu and TopInfoBar use the established _pause_for_menu pattern.
##
## === Offer Details Panel + Counter Flow ===
## The recommended pattern (used by TradeMarketView + TradeOfferDetailsPanel):
##
## 1. Player clicks "Details" on an offer row → calls:
##    TradeManager.request_offer_details(offer_id, player_tag)
##    (This emits the offer_details_requested signal.)
##
## 2. TradeOfferDetailsPanel (or any listener) receives the signal and calls:
##    var data = TradeManager.get_offer_display_data(offer_id, player_tag)
##    # Then displays the rich data (items with display_name, full fairness,
##    # risk_level/category for BLACK offers, metadata, etc.)
##
## 3. Inside the details panel the player can:
##    - Accept / Reject using the existing helpers
##    - Click "Counter" → the panel shows a rich editable preview with:
##        • Side-by-side comparison + color-coded diffs (green/red deltas with "orig → new (Δ)")
##        • Per-item quantity editing (+/-, direct input, remove with safeguards)
##        • Bulk scale toolbar (+10%/-10%, Halve, Double, 50%)
##        • Preset templates ("Fair Split", "Aggressive", "Min Ask") + "Save Current" / "Load Saved" for custom session templates
##        • "Reset to Pure Reversal" button
##        • Helpful tooltips on risk, fairness, bulk, and preset controls
##      On confirmation it calls:
##        TradeManager.create_counter_offer(base_offer_id, new_offered, new_requested)
##      The MarketView auto-refreshes and does a stronger highlight flash on the new counter.
##
## 4. The MarketView "My Offers" tab now shows BOTH offers you initiated (SENT, cyan badge)
##    AND offers addressed to you (RECEIVED, warm badge). Much more useful for tracking your
##    full diplomatic activity.
##
## 5. The originating market view listens to counter_offer_requested and refreshes
##    its list so the new counter-offer immediately appears (with improved visual pop).
##
## Full example of a minimal details + counter listener:
##    TradeManager.offer_details_requested.connect(func(offer_id, for_country):
##        var panel = load("res://scenes/ui/TradeOfferDetailsPanel.tscn").instantiate()
##        get_tree().root.add_child(panel)
##        panel.show_details(offer_id, for_country)
##    )
##
##    TradeManager.counter_offer_requested.connect(func(base_id, from, to):
##        # Optional: show toast or open the new counter in the market view
##        print("Counter created for ", base_id)
##    )
##
## === Future Diplomacy / Relations Layer Integration ===
## Trade is designed to be a first-class citizen of future diplomatic systems.
## A DiplomacyManager, Relations component, or National Focus tree can integrate
## with zero changes to existing Public/Black/My Offers flows.
##
## Recommended patterns:
##
## 1. Listening to deal outcomes (strongly preferred over polling):
##    TradeManager.trade_deal_outcome.connect(func(offer_id, from, to, status, visibility, metadata):
##        # status is int(TradeStatus)
##        if status == TradeStatus.ACCEPTED:
##            diplomacy.apply_opinion(from, to, TradeManager.get_suggested_opinion_delta_for_deal(offer_id), "trade")
##            # Also inspect metadata for "is_counter", "counter_of", high-value items, etc.
##    )
##
##    TradeManager.trade_diplomatic_effect_suggested.connect(...)  # for preview / AI decision making
##
## 2. Getting bilateral offers for a diplomacy screen:
##    var deals = TradeManager.get_offers_between("GER", "SOV")           # either direction, PROPOSED only
##    var all_deals_with_ger = TradeManager.get_market_offers_display_data(
##        country_tag = player_tag,
##        other_party_tag = "GER"
##    )
##    # Or via search token (works in any view): search_term = "involves:GER" or "with:SOV"
##
##    Convenience summary:
##    var summary = TradeManager.get_diplomatic_summary_with(player_tag, "GER")
##
## 3. Notifying / reacting after terminal states:
##    TradeManager.notify_trade_diplomatic_outcome(offer_id)   # emits rich signals + advisory delta
##
## 4. Attaching trade to larger diplomatic packages (future):
##    # When creating offers from a Diplomacy screen, pass metadata:
##    #   metadata = {"diplomatic_package_id": "pact_1941_03", "part_of_alliance": true}
##    # Trade will preserve and return this metadata in display data and outcome signals.
##
## 5. Fairness influence (future extension point):
##    # evaluate_fairness already documents the "diplomacy opinion" extension slot.
##    # A Relations system can pre-adjust values or provide a multiplier to callers.
##
## 6. Opening / using the DiplomacyView:
##    # TopInfoBar already wires the DiplomacyButton to open it.
##    var view = preload("res://scenes/ui/DiplomacyView.tscn").instantiate()
##    get_tree().root.add_child(view)
##    # The view uses get_offers_between + other_party_tag + get_diplomatic_summary_with.
##    # Relations Overview now includes:
##    #   - 5+ metrics (including Strategic items + Expiring soon)
##    #   - A prominent "Relationship Pulse" textual summary
##    #
##    # Bilateral list supports:
##    #   - Client-side SENT/RECEIVED filtering + automatic grouping headers
##    #   - Per-row quick actions with strong context
##    #   - Expiry warnings
##
##    # Stronger handoff:
##    # DiplomacyView can now open TradeMarketView with automatic bilateral filtering applied
##    view.show_market("PUBLIC", "GER")   # filter_country triggers real pre-filtering in the list

## 7. Future-proofing patterns visible in DiplomacyView:
##    - Rich extension point comments (opinion injection points, event handling, packages, filter extensibility).
##    - The Pulse/metrics row and bilateral filter system are designed as natural extension points.
##    - Cross-view handoff pattern (pending filter) demonstrates how future screens can drive context.
##
## All new signals and helpers are additive and safe to ignore. Existing code using
## get_market_offers_display_data, get_offer_display_data, accept/reject, etc. continues to work unchanged.

## =============================================================================
## TRADE TRANSIT & INTERDICTION ARCHITECTURE (Lightweight Foundation)
## =============================================================================
## This section documents the architectural direction for modeling ongoing trade deliveries
## and enabling future interdiction (submarines, air power, surface fleets, espionage, etc.).
##
## === Core Concept: TradeFlow ===
## When a TradeOffer containing recurring goods (primarily RESOURCE, EQUIPMENT, SUPPLY) is
## accepted, TradeManager can create one or more TradeFlow instances.
##
## A TradeFlow represents an ongoing "pipe" of goods:
##   - from_tag → to_tag
##   - specific item (e.g. "steel", specific equipment template)
##   - quantity_per_turn (or per month)
##   - optional link to a SupplyRoutePlan (via route_plan_id)
##   - active / suspended state
##
## TradeFlow is intentionally *not* responsible for:
##   - Actual cargo movement (that's SupplyMultimodalRouter + SupplyRoutePlan)
##   - Interdiction logic (that's future SupplyInterdictionEstimator / CombatPresenceRegistry / Agent systems)
##
## TradeFlow exists so that:
##   - Supply systems have something concrete to route and track
##   - Interdiction systems have something concrete to target and damage/suspend
##   - Diplomacy / Relations layers can observe economic interdependence over time
##
## === Trigger Points ===
## Primary creation point: inside accept_offer(), after atomic transfers succeed.
## We emit trade_flow_created(...) so external systems can react.
##
## Existing signals that are also relevant:
##   - deal_accepted
##   - trade_deal_outcome (especially on ACCEPTED status)
##
## === Integration with Supply System ===
## Recommended pattern (not yet wired in v1):
##   1. On trade_flow_created, a future TradeTransitCoordinator (or SupplyManager itself)
##      can call SupplyMultimodalRouter.find_best_route(...) using a SupplyCargoProfile
##      built from the TradeFlow's item and quantity.
##   2. The resulting SupplyRoutePlan can be stored on the TradeFlow (route_plan_id).
##   3. Trade cargo then conceptually travels on that route (cargo_tons_per_day contribution).
##
## TradeManager does **not** own routing. It only exposes the economic intent.
##
## === Interdiction Extension Points ===
## Future interdiction systems should use these signals and queries:
##
##   - trade_flow_interdicted(flow_id, interdictor_type, loss_fraction, metadata)
##   - trade_flow_rerouted(flow_id, new_route_plan_id)
##   - trade_flow_suspended(flow_id, reason)
##
## Query helpers:
##   - get_active_trade_flows()
##   - get_active_trade_flows_between(from, to)
##   - get_trade_flow(flow_id)
##
## Recommended integration surfaces on the Supply side:
##   - SupplyInterdictionEstimator (already models enemy_naval, enemy_air, etc.)
##   - CombatPresenceRegistry (for presence of submarines, raiders, air wings)
##   - SupplyIntelBridge (for detection of trade movements)
##   - ProvinceDepotState / national stockpiles (actual economic effect of successful interdiction)
##
## Interdictor types (suggested convention):
##   "submarine", "surface_raider", "air_interdiction", "convoy_escort_failure",
##   "espionage_sabotage", "port_strike", "diplomatic_embargo", etc.
##
## === Current Scope (This Session) ===
## - TradeFlow data model + automatic creation on relevant deal acceptance
## - Full lifecycle management: `advance_trade_flows()`, suspend/resume/complete
## - Basic movement simulation (quantity accumulates over time based on cadence)
## - **Basic Cargo Delivery**: When advancing, goods are now actually added to the recipient's `national_stockpile` (for the player country) for RESOURCE and EQUIPMENT flows.
## - Functional interdiction surface: `interdict_trade_flow(...)` with route-risk blending, detailed history (including route modes/risk), and player toasts via LeaderEventUI for significant losses.
## - Real Supply route assignment: `_try_assign_supply_route_to_flow` now calls `SupplyManager.find_route_for_trade(...)` and stores `route_plan_id` + useful plan data in metadata
## - Visibility of suspended/damaged flows in DiplomacyView Relations Overview (badges + counts when viewing a bilateral partner)
## - All four transit signals are now emitted where appropriate
## - Query helpers for flows by various criteria
## - Added public `find_route_for_trade` helper on SupplyManager for clean cross-system use
##
## Out of scope (future work):
## - Actual cargo movement simulation along SupplyRoutePlans (still just conceptual)
## - Automatic, persistent route assignment and rerouting
## - Pushing delivered trade goods into recipient stockpiles or ProvinceDepotState
## - UI visualization of active TradeFlows
## - Full economic consequences of successful interdiction
##
## === Extension Guidance ===
## The following are now real and stable:
##   - `interdict_trade_flow(flow_id, interdictor_type, loss_fraction, metadata)` — primary entry point for all interdiction
##   - `advance_trade_flows(turn)` — called automatically on monthly ticks
##   - Lifecycle methods: suspend/resume/complete
##
## When wiring deeper Supply integration:
##   - The public `SupplyManager.find_route_for_trade(from_tag, to_tag, cargo_tons)` is the recommended entry point.
##   - Once a flow has a `route_plan_id`, use `SupplyManager.get_route(flow.route_plan_id)` to read timing and risk data.
##   - Interdiction can now optionally blend with the route's `interdiction_chance` (see current implementation).
##   - Future: push `flow.total_delivered` increments into recipient stockpiles via ProductionManager or ProvinceDepotState.
##
## See also:
##   - SupplyRoutePlan (cargo_tons_per_day, interdiction_chance)
##   - SupplyMultimodalRouter
##   - SupplyInterdictionEstimator
##   - CombatPresenceRegistry
##   - SupplyIntelBridge

## =============================================================================
## NATION-SPECIFIC DESIGN TRADING (Core Integration with Existing Systems)
## =============================================================================
## This is the highest-leverage feature enabled by the prior capture work.
##
## When a DESIGN TradeItem is accepted:
##   1. TradeManager calls:
##        DesignManager.grant_acquired_design(
##            to_tag,
##            design_id,
##            ACQUISITION_PURCHASED   # or LICENSED if item.metadata["kind"] == "license"
##        )
##   2. Because grant_acquired_design writes to the authoritative _acquired_designs and the
##      legacy shim, the recipient immediately:
##        - Sees the design in DesignPickerPopup under the correct "Foreign Acquired" (or "Previously Used")
##          bucket with the proper icon (💰 Purchased / 📜 Licensed) + source nation badge.
##        - Passes DesignManager.country_may_use_design() and is_design_foreign_for().
##        - Can build the design in provinces they control (via MapTechnologyContext + Factory rules).
##        - Benefits from any future production or combat bonuses tied to acquired foreign designs.
##
## Variable Quality / Downgraded Exports (strategic depth):
##   - TradeItem for DESIGN may carry quality_modifier (0.75 – 1.10 typical range).
##   - Lower quality = cheaper in fairness calculation (good for seller who wants to offload older
##     variants or earn hard currency from a neutral buyer).
##   - Higher quality (premium licensed copy) = more expensive, but still grants the base design_id.
##   - In v1 the modifier only affects fairness math and is recorded in the offer metadata.
##   - Future (easy extension):
##       • Store per-country per-design variant data in DesignManager (or here).
##       • DesignManager.get_effective_design_stats(country, design_id) applies the modifier
##         to base_stats, reliability, production_complexity, etc.
##       • Production lines using a downgraded variant produce slightly inferior units (or cost less).
##
## Example offer snippet (what future UI or AI will do):
##   var item = {
##       "type": TradeItemType.DESIGN,
##       "id": "pzkpfw_iv_ausf_h",
##       "quantity": 1,
##       "quality_modifier": 0.92,           # slightly downgraded export model
##       "metadata": {"notes": "Licensed production rights with minor simplifications"}
##   }
##   TradeManager.create_offer("GER", "HUN", [item], [resource_steel_5000], TradeVisibility.PUBLIC)
##
## On accept by HUN → HUN now owns the design via grant, appears in their picker as "Purchased from GER".
##
## =============================================================================
## FUTURE EXTENSION POINTS (Explicitly Designed For)
## =============================================================================
## - Intelligence sharing: new item type INTEL_REPORT. On accept → SupplyIntelBridge or AgentManager
##   receives the intel (map reveal, unit sighting, tech leak).
## - Technology trades: TECH_SHARE item → TechnologyManager.apply_tech_share or stolen_research.
## - Province trades / concessions: PROVINCE item → MapManager.update_province_owner + possible
##   population / development side effects.
## - Naval / air basing rights (DOCKING_RIGHTS): temporary or permanent access modifiers in Supply
##   or CombatPresence.
## - Black market events: random or agent-triggered offers that appear only if certain agent networks
##   or national modifiers are active.
## - Full diplomacy integration: TradeOffer can be attached to a larger DiplomaticPackage (alliance +
##   trade + guarantee). Future DiplomacyManager will hold references to active TradeOffers.
##   See notify_trade_diplomatic_outcome(), trade_deal_outcome signal, and get_offers_between().
## - Opinion / Relations effects: deal outcomes now emit trade_diplomatic_effect_suggested and
##   trade_deal_outcome. A future Relations system can apply prestige/opinion deltas here.
##   get_suggested_opinion_delta_for_deal() provides a lightweight starting value.
## - Save / Load: implement get_save_data() / apply_save_data() that serializes active offers
##   (offers are valuable state — a deal in flight matters).
## - UI reactivity: every public method emits signals. A future TradeDealPopup or DiplomacyScreen
##   can listen without polling.
## - Fairness plugins: register custom value calculators (e.g. "ideological_value" for selling to
##   fellow fascists/communists at a discount). Diplomacy opinion can also influence fairness in the future.
##
## =============================================================================
## INTEGRATION WITH EXISTING SYSTEMS (What Calls What)
## =============================================================================
## - Design acquisition on trade  → DesignManager.grant_acquired_design (already the single source
##   of truth used by conquest capture path in FactoryManager). Trade passes kind based on metadata
##   (PURCHASED vs LICENSED) and records quality_modifier on the offer for future variant handling.
## - Resource/equipment movement  → ProductionManager (can_afford + pay_cost for resources;
##   take_from_national_stockpile + add_to_national_stockpile for equipment). Validation in
##   accept_offer uses the same helpers so transfers are safe and atomic where possible.
## - Province ownership         → MapManager.update_province_owner (accept path for PROVINCE items).
## - Visibility / risk            → AgentManager (black market ops).
## - Deal effects on nation       → NationalModifierManager.apply_national_effect (e.g. "recent_big_trade"
##   temporary bonus, "trade_scandal" debuff).
## - Build eligibility after trade → MapTechnologyContext + DesignManager.country_may_use_design
##   (zero changes needed — it just works once grant is called).
##
## TradeManager is intentionally an autoload sibling to NationalModifierManager / NationalSpiritManager
## so it can be reached from anywhere (Map, Agents, Production, UI, console) with a single name.
##
## =============================================================================
## SIGNALS
## =============================================================================
signal offer_created(offer_id: String, from: String, to: String, visibility: TradeVisibility)
signal deal_accepted(offer_id: String, from: String, to: String)
signal deal_rejected(offer_id: String, from: String, to: String, reason: String)
signal offer_expired(offer_id: String)

## UI-friendly interaction signals
signal offer_details_requested(offer_id: String, for_country: String)   # UI can listen to pop a details window
signal counter_offer_requested(base_offer_id: String, suggested_from: String, suggested_to: String)

## Diplomacy / Relations layer hooks (lightweight extension points)
## A future DiplomacyManager or Relations system can connect to these without Trade knowing about it.
signal trade_deal_outcome(offer_id: String, from: String, to: String, status: int, visibility: TradeVisibility, metadata: Dictionary)
signal trade_diplomatic_effect_suggested(from: String, to: String, suggested_opinion_delta: float, reason: String, offer_id: String, visibility: TradeVisibility)

## Trade Transit & Interdiction architecture hooks (new foundation)
## These signals allow future systems (Supply transit layer, submarines, air power, espionage, surface fleets)
## to observe and interact with ongoing trade deliveries without TradeManager knowing the details of routing or interdiction.
signal trade_flow_created(flow_id: String, from: String, to: String, item_type: String, quantity_per_turn: float)
signal trade_flow_interdicted(flow_id: String, interdictor_type: String, loss_fraction: float, metadata: Dictionary)
signal trade_flow_rerouted(flow_id: String, new_route_plan_id: String)
signal trade_flow_suspended(flow_id: String, reason: String)

## (More signals can be added later without breaking anything.)

## =============================================================================
## INTERNAL STATE (kept minimal and queryable)
## =============================================================================
var _offers: Dictionary = {}                    # offer_id -> TradeOffer (full data)
var _offers_by_from: Dictionary = {}            # country_tag -> Array[offer_id]
var _offers_by_to: Dictionary = {}              # country_tag -> Array[offer_id]

## New: Ongoing trade flows (lightweight foundation for transit & interdiction)
## Each accepted deal that involves ongoing goods (RESOURCE, EQUIPMENT, SUPPLY, etc.) can spawn one or more TradeFlows.
var _trade_flows: Dictionary = {}               # flow_id -> TradeFlow

var _current_year: int = 1936

# Simple value baselines (easy to move to a data file or rules json later)
const DESIGN_BASE_VALUE_MULTIPLIER := 1.0
const RESOURCE_BASE_RATES := {
	"steel": 1.0,
	"fuel": 1.8,
	"rubber": 2.2,
	"aluminum": 1.5,
	"oil": 2.5,
	# ... extend as needed
}

func _ready() -> void:
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)
		if not TimeManager.game_month_advanced.is_connected(_on_game_month_advanced):
			TimeManager.game_month_advanced.connect(_on_game_month_advanced)

	# Future: connect to AgentManager signals for black market generation, etc.

func _on_game_year_advanced(year: int) -> void:
	_current_year = year
	_expire_offers_past_deadline()

func _on_game_month_advanced(year: int, month: int) -> void:
	advance_trade_flows(_current_year)  # Use year as a simple turn proxy for now; can refine later

## =============================================================================
## PUBLIC API — OFFER LIFECYCLE
## =============================================================================

## Creates a new trade offer. Returns the offer_id (UUID-style string for simplicity).
## Callers (future UI, AI, events, agents) are responsible for validating that the offering
## country actually possesses the items (we do not enforce it in v1).
func create_offer(
	from_tag: String,
	to_tag: String,
	offered_items: Array,
	requested_items: Array,
	visibility: TradeVisibility = TradeVisibility.PUBLIC,
	expires_in_years: int = -1
) -> String:
	var from := _norm_tag(from_tag)
	var to := _norm_tag(to_tag)
	if from.is_empty() or to.is_empty() or from == to:
		push_error("TradeManager: invalid from/to for offer")
		return ""

	if not _is_abstract_trade_party(from) and not _country_can_supply_items(from, offered_items):
		push_warning("TradeManager: offerer %s cannot supply offered items" % from)
		return ""

	var offer_id := _generate_id()
	var offer := {
		"id": offer_id,
		"from_tag": from,
		"to_tag": to,
		"offered": offered_items.duplicate(true),
		"requested": requested_items.duplicate(true),
		"visibility": visibility,
		"status": TradeStatus.PROPOSED,
		"created_turn": _current_year,
		"expires_turn": (_current_year + expires_in_years) if expires_in_years > 0 else -1,
		"fairness_cache": {},
		"metadata": {}
	}

	_offers[offer_id] = offer
	_index_offer(offer_id, from, to)

	offer_created.emit(offer_id, from, to, visibility)
	return offer_id

## Returns a rich fairness evaluation from the perspective of for_country.
## Safe to call repeatedly for "what if" analysis.
func evaluate_fairness(offer_id: String, for_country: String) -> Dictionary:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty():
		return {"score": 0.0, "reason": "Offer not found", "value_offered": 0.0, "value_requested": 0.0}

	var tag := _norm_tag(for_country)
	var is_from := (tag == offer.from_tag)

	var offered_value := 0.0
	var requested_value := 0.0
	var breakdown := {}

	for item in offer.offered:
		var v := _calculate_item_value(item, tag)
		offered_value += v
		breakdown["offered_" + str(item.get("id", ""))] = v

	for item in offer.requested:
		var v := _calculate_item_value(item, tag)
		requested_value += v
		breakdown["requested_" + str(item.get("id", ""))] = v

	# From the evaluator's view: value I give vs value I receive
	var my_outgoing := offered_value if is_from else requested_value
	var my_incoming := requested_value if is_from else offered_value

	var score := 1.0
	if my_outgoing > 0.0:
		score = my_incoming / my_outgoing

	var reason := "Fair deal"
	var recommendation := "Fair"
	if score > 1.15:
		reason = "Excellent deal for %s" % tag
		recommendation = "Strongly recommend"
	elif score < 0.85:
		reason = "Poor deal for %s — you are overpaying" % tag
		recommendation = "Reject or counter"

	# Polish recommendations for high-value items (PROVINCE, INTEL) with richer, context-aware text
	# immediately useful for future Trade UI tooltips and decision panels.
	var saw_province := false
	var saw_intel := false
	for item in offer.offered + offer.requested:
		var itype = item.get("type")
		if itype == TradeItemType.PROVINCE:
			saw_province = true
			recommendation = "High-stakes strategic decision — acquiring this province grants permanent production base, infrastructure, and potential factory seizures with auto design capture via MapManager hooks. Strongly consider if it borders hostile territory, contains ports/resources, or sits on a supply hub (long-term defense + industrial value often exceeds raw score). National spirit or agent network effects may further amplify or complicate the long-term value. Reject only if it would over-extend your lines or trigger major diplomatic backlash."
			break
		elif itype == TradeItemType.INTEL:
			saw_intel = true
			if score > 1.1:
				recommendation = "Valuable intelligence opportunity — this package can close your current reconnaissance gap and reveal enemy supply/air/naval dispositions. Prioritize when facing active threats or planning offensives; the recon_bonus and intel_visibility modifiers (applied via NationalModifierManager) provide immediate operational value against known enemy presence."
			else:
				recommendation = "Intel package may be overpriced unless you have an immediate need for visibility. Current recon levels or low enemy air/naval pressure reduce urgency — consider counter-offering or waiting for a better bundle unless agent networks or SupplyIntelBridge data indicate imminent enemy movements."
			break

	# Enrich breakdown for high-value items with extra context keys (still inside the same dict, fully UI-ready)
	if saw_province:
		for item in offer.offered + offer.requested:
			if item.get("type") == TradeItemType.PROVINCE:
				var pid := str(item.get("id", ""))
				if typeof(MapManager) != TYPE_NIL:
					var prov := MapManager.get_province(int(pid))
					if prov != null:
						breakdown["province_dev"] = prov.development_level
						breakdown["province_infra"] = prov.infrastructure
						breakdown["province_has_port"] = "port" in str(prov.features).to_lower() or "naval" in str(prov.features).to_lower()
				break
	if saw_intel:
		for item in offer.offered + offer.requested:
			if item.get("type") == TradeItemType.INTEL:
				breakdown["intel_quantity"] = item.get("quantity", 1)
				breakdown["intel_type"] = item.get("metadata", {}).get("type", "general")
				breakdown["intel_enemy_threat"] = "high" if score > 1.1 else "moderate"
				break

	return {
		"score": score,
		"value_offered": my_outgoing,
		"value_requested": my_incoming,
		"reason": reason,
		"recommendation": recommendation,
		"breakdown": breakdown,
		"visibility": offer.visibility,
		"is_from": is_from
	}

## Accepts the offer after validating that the offering country actually possesses
## the items being offered. Executes transfers for DESIGNS (via grant), RESOURCE,
## and EQUIPMENT using ProductionManager's safe helpers.
## Returns true on full success.
func accept_offer(offer_id: String) -> bool:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty() or offer.status != TradeStatus.PROPOSED:
		return false

	var from := offer.from_tag
	var to := offer.to_tag

	# === Validation: offerer must have offered items; accepter must be able to pay requested ===
	if not _country_can_supply_items(from, offer.offered):
		return false
	if not _country_can_supply_items(to, offer.requested):
		return false

	# Accepter (to) receives offered; pays requested. Offerer (from) gives offered; receives requested.
	for item in offer.offered:
		_execute_transfer(to, item)
		_execute_transfer(from, item, true)

	for item in offer.requested:
		_execute_transfer(from, item)
		_execute_transfer(to, item, true)

	offer.status = TradeStatus.ACCEPTED
	_clean_indexes(offer_id)

	deal_accepted.emit(offer_id, from, to)

	# Richer signal for future Diplomacy / Relations layer
	trade_deal_outcome.emit(offer_id, from, to, int(TradeStatus.ACCEPTED), offer.visibility, offer.get("metadata", {}).duplicate(true))

	# === New: Create ongoing TradeFlows for appropriate items (lightweight transit foundation) ===
	_create_trade_flows_for_accepted_offer(offer)

	return true

func _is_abstract_trade_party(country_tag: String) -> bool:
	var tag := _norm_tag(country_tag)
	return tag in ["BLACK_MARKET", "UNDERWORLD", "SMUGGLERS"]

## Creates lightweight ongoing TradeFlows for items that represent recurring deliveries.
## Called automatically on successful deal acceptance.
## Currently focuses on RESOURCE and EQUIPMENT as the most natural "flow" candidates.
## DESIGNs, PROVINCE transfers, TECH_SHARE, INTEL, and DOCKING_RIGHTS usually remain one-time/atomic.
func _create_trade_flows_for_accepted_offer(offer: Dictionary) -> void:
	if offer.is_empty():
		return

	var from := offer.from_tag
	var to := offer.to_tag
	var offer_id := offer.id

	# We create flows primarily from the "offered" side (the goods actually moving to the recipient)
	for item in offer.offered:
		var itype: String = item.get("type", "")
		var iid: String = item.get("id", "")
		var qty: float = float(item.get("quantity", 0.0))

		# Only certain item types make sense as ongoing flows
		if not _item_type_supports_ongoing_flow(itype):
			continue
		if qty <= 0:
			continue

		# Simple default cadence: 1/12th per turn (roughly monthly if turns ≈ months)
		# Future: this can come from offer.metadata["delivery_cadence"] or be negotiated
		var quantity_per_turn := qty / 12.0

		var flow := TradeFlow.new()
		flow.flow_id = _generate_id()
		flow.offer_id = offer_id
		flow.from_tag = from
		flow.to_tag = to
		flow.item_type = itype
		flow.item_id = iid
		flow.quantity_per_turn = quantity_per_turn
		flow.delivery_cadence = 1
		flow.created_turn = _current_year
		flow.active = true
		flow.metadata = {
			"original_offer_quantity": qty,
			"source_offer_visibility": offer.get("visibility", "")
		}

		_trade_flows[flow.flow_id] = flow

		trade_flow_created.emit(flow.flow_id, from, to, itype, quantity_per_turn)

		# Lightweight Supply integration hook (optional, non-breaking)
		_try_assign_supply_route_to_flow(flow)

## Returns whether this TradeItemType is expected to generate an ongoing delivery flow.
func _item_type_supports_ongoing_flow(item_type: String) -> bool:
	return item_type in [
		TradeItemType.RESOURCE,
		TradeItemType.EQUIPMENT,
		TradeItemType.SUPPLY
	]

## Attempts to assign a real SupplyRoutePlan to a newly created TradeFlow using the Supply system's routing.
## This makes the TradeFlow connected to actual route data (with interdiction risk, timing, etc.).
func _try_assign_supply_route_to_flow(flow: TradeFlow) -> void:
	if not flow or flow.route_plan_id != "":
		return

	if typeof(SupplyManager) == TYPE_NIL:
		return

	# Estimate cargo size from the flow (very rough for now)
	var estimated_tons := flow.quantity_per_turn * 10.0  # heuristic
	var plan := SupplyManager.find_route_for_trade(flow.from_tag, flow.to_tag, estimated_tons)
	if plan and plan.path_length() >= 2:
		flow.route_plan_id = plan.route_id
		flow.preferred_mode = plan.routing_mode

		# Also store some useful data from the plan into the flow's metadata for quick access
		flow.metadata["route_total_days"] = plan.total_days
		flow.metadata["route_interdiction_chance"] = plan.interdiction_chance
		flow.metadata["route_uses_sea"] = plan.uses_port
		flow.metadata["route_uses_air"] = plan.uses_airport

## =============================================================================
## TRADEFLOW LIFECYCLE & MOVEMENT
## =============================================================================

## Called periodically (currently on monthly ticks) to advance all active TradeFlows.
## This is the core "movement" simulation for trade goods.
func advance_trade_flows(current_turn: int) -> void:
	for flow_id in _trade_flows.keys():
		var flow: TradeFlow = _trade_flows[flow_id]
		if not flow or not flow.is_ongoing():
			continue

		# Simple cadence check
		var turns_since_last := current_turn - flow.last_delivery_turn if flow.last_delivery_turn >= 0 else flow.delivery_cadence
		if turns_since_last < flow.delivery_cadence:
			continue

		# "Deliver" goods this turn
		flow.total_delivered += flow.quantity_per_turn
		flow.last_delivery_turn = current_turn

		# === Basic Cargo Delivery (lightweight but real) ===
		# Deliver into the recipient's national stockpile when possible.
		# Only perform actual delivery for the player country for now (AI countries remain abstract).
		if flow.to_tag == _get_player_country_tag():
			var amount := flow.quantity_per_turn

			if flow.item_type == TradeItemType.RESOURCE:
				# Direct access is the established pattern in TradeManager for resources
				var stock := ProductionManager.national_stockpile
				stock[flow.item_id] = stock.get(flow.item_id, 0.0) + amount

			elif flow.item_type == TradeItemType.EQUIPMENT:
				# Use the helper for equipment
				ProductionManager.add_to_national_stockpile(flow.item_id, int(amount))

			# Record that this delivery actually landed
			flow.metadata["last_delivered_amount"] = amount
			flow.metadata["last_delivery_recipient"] = flow.to_tag

		# Basic cargo movement concept: record that goods have conceptually traveled the assigned route.
		if not flow.route_plan_id.is_empty():
			flow.metadata["last_route_used"] = flow.route_plan_id

		# Clear lightweight stub for future depot-level delivery (ProvinceDepotState)
		# Example future path:
		#   var depot_state = _get_depot_state_for_country(flow.to_tag, some_province_id)
		#   if depot_state: depot_state.add_to_stockpile(flow.item_type, flow.item_id, amount)

		# Very lightweight auto-suspension if quantity drops to zero (e.g. from interdiction)
		if flow.quantity_per_turn <= 0.0:
			suspend_trade_flow(flow_id, "quantity_depleted")

## Suspend an active TradeFlow (e.g. due to interdiction, diplomatic crisis, etc.)
func suspend_trade_flow(flow_id: String, reason: String = "") -> bool:
	var flow: TradeFlow = _trade_flows.get(flow_id)
	if not flow or not flow.active:
		return false

	flow.active = false
	flow.suspended_reason = reason

	trade_flow_suspended.emit(flow_id, reason)
	return true

## Resume a suspended TradeFlow.
func resume_trade_flow(flow_id: String) -> bool:
	var flow: TradeFlow = _trade_flows.get(flow_id)
	if not flow or flow.active:
		return false

	flow.active = true
	flow.suspended_reason = ""

	# Re-emit creation-like signal so listeners can re-attach to the flow
	trade_flow_created.emit(flow_id, flow.from_tag, flow.to_tag, flow.item_type, flow.quantity_per_turn)
	return true

## Permanently end a TradeFlow (e.g. deal fully delivered or cancelled).
func complete_trade_flow(flow_id: String) -> bool:
	var flow: TradeFlow = _trade_flows.get(flow_id)
	if not flow:
		return false

	flow.active = false
	# We keep the flow in the dictionary for historical queries, but mark it done.
	# Future: we could archive or prune old completed flows.
	return true

## =============================================================================
## INTERDICTION SURFACE (Functional hooks for external systems)
## =============================================================================

## Main entry point for any interdiction system (submarines, air, surface fleets, espionage, etc.).
## Reduces or suspends the flow and emits the appropriate signals.
func interdict_trade_flow(flow_id: String, interdictor_type: String, loss_fraction: float, metadata: Dictionary = {}) -> bool:
	var flow: TradeFlow = _trade_flows.get(flow_id)
	if not flow or not flow.is_ongoing():
		return false

	loss_fraction = clamp(loss_fraction, 0.0, 1.0)

	# If the flow has a real SupplyRoutePlan, we can incorporate its interdiction data for more grounded loss.
	var effective_loss := loss_fraction
	if not flow.route_plan_id.is_empty() and typeof(SupplyManager) != TYPE_NIL:
		var plan := SupplyManager.get_route(flow.route_plan_id)
		if plan:
			var route_risk := float(plan.interdiction_chance)
			# Blend caller-provided loss with route risk (lightweight)
			effective_loss = clamp(loss_fraction * 0.6 + route_risk * 0.4, 0.0, 1.0)
			flow.metadata["last_interdiction_route_risk"] = route_risk

	# Apply loss to the flow's delivery rate
	var previous_rate := flow.quantity_per_turn
	flow.quantity_per_turn *= (1.0 - effective_loss)

	# Record history in metadata (with route awareness)
	if not flow.metadata.has("interdiction_history"):
		flow.metadata["interdiction_history"] = []

	var history_entry := {
		"turn": _current_year,
		"interdictor": interdictor_type,
		"loss_fraction": loss_fraction,
		"effective_loss": effective_loss,
		"previous_rate": previous_rate,
		"new_rate": flow.quantity_per_turn,
		"had_route": not flow.route_plan_id.is_empty()
	}

	if not flow.route_plan_id.is_empty():
		history_entry["route_id"] = flow.route_plan_id
		if typeof(SupplyManager) != TYPE_NIL:
			var plan := SupplyManager.get_route(flow.route_plan_id)
			if plan:
				history_entry["route_risk"] = plan.interdiction_chance
				history_entry["route_modes"] = plan.segment_modes

	flow.metadata["interdiction_history"].append(history_entry.merged(metadata))

	# Emit the core interdiction signal
	trade_flow_interdicted.emit(flow_id, interdictor_type, loss_fraction, flow.metadata.duplicate(true))

	# Player-facing feedback for significant interdiction events
	if typeof(LeaderEventUI) != TYPE_NIL:
		var loss_pct := int(effective_loss * 100)
		if loss_pct >= 20 or not flow.active:
			var msg := "Trade flow interdicted (%s): %d%% loss on %s → %s" % [
				interdictor_type.capitalize(),
				loss_pct,
				flow.from_tag,
				flow.to_tag
			]
			LeaderEventUI.show_toast(msg, 4.0, loss_pct >= 50)

	# If the flow has been completely stopped, suspend it
	if flow.quantity_per_turn <= 0.001:
		suspend_trade_flow(flow_id, "interdicted_" + interdictor_type)

	return true

## Convenience helper for external systems that want to apply a full suspension (100% interdiction).
func fully_interdict_trade_flow(flow_id: String, interdictor_type: String, metadata: Dictionary = {}) -> bool:
	return interdict_trade_flow(flow_id, interdictor_type, 1.0, metadata)


## Returns true if country_tag can provide every item in the list (trade payment / offer side).
func _country_can_supply_items(country_tag: String, items: Array) -> bool:
	var tag := _norm_tag(country_tag)
	if _is_abstract_trade_party(tag):
		return true
	for item in items:
		var type = item.get("type", TradeItemType.RESOURCE)
		var id := str(item.get("id", ""))
		var qty := float(item.get("quantity", 0.0))
		if qty <= 0:
			continue

		match type:
			TradeItemType.RESOURCE:
				if _uses_player_stockpile(tag) and typeof(ProductionManager) != TYPE_NIL:
					var cost := {}
					cost[id] = qty
					if not ProductionManager.can_afford(cost):
						return false

			TradeItemType.EQUIPMENT:
				if _uses_player_stockpile(tag) and typeof(ProductionManager) != TYPE_NIL:
					var available := int(ProductionManager.national_equipment_stockpile.get(id, 0))
					if available < int(qty):
						return false

			TradeItemType.DESIGN:
				if typeof(DesignManager) != TYPE_NIL:
					var ownership := DesignManager.get_design_ownership(tag, id)
					if ownership != DesignManager.DesignOwnership.DOMESTIC \
							and not DesignManager.has_acquired_design(tag, id):
						return false

			TradeItemType.PROVINCE:
				if typeof(MapManager) == TYPE_NIL:
					return false
				var prov := MapManager.get_province(int(id))
				if prov == null:
					return false
				var owner := prov.owner_tag.strip_edges().to_upper()
				var ctrl := prov.controller_tag.strip_edges().to_upper()
				if owner != tag and ctrl != tag:
					return false

			TradeItemType.TECH_SHARE, TradeItemType.DOCKING_RIGHTS, TradeItemType.INTEL, TradeItemType.SUPPLY:
				pass

			_:
				pass

	return true


func _expire_offers_past_deadline() -> void:
	var to_expire: Array[String] = []
	for offer_id in _offers.keys():
		var offer: Dictionary = _offers[offer_id]
		if offer.get("status") != TradeStatus.PROPOSED:
			continue
		var deadline: int = int(offer.get("expires_turn", -1))
		if deadline > 0 and _current_year >= deadline:
			to_expire.append(offer_id)
	for offer_id in to_expire:
		expire_offer(offer_id)


func _get_player_country_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return _norm_tag(LeaderManager.get_player_country_tag())
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_player_country_tag_fallback"):
		return _norm_tag(MapManager.get_player_country_tag_fallback())
	return "USA"


func _uses_player_stockpile(country_tag: String) -> bool:
	return _norm_tag(country_tag) == _get_player_country_tag()


## Rejects a proposed offer. Returns true if the rejection was successful.
func reject_offer(offer_id: String, reason: String = "") -> bool:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty() or offer.status != TradeStatus.PROPOSED:
		return false
	offer.status = TradeStatus.REJECTED
	_clean_indexes(offer_id)
	deal_rejected.emit(offer_id, offer.from_tag, offer.to_tag, reason)

	# Richer signal for future Diplomacy / Relations layer
	trade_deal_outcome.emit(offer_id, offer.from_tag, offer.to_tag, int(TradeStatus.REJECTED), offer.visibility, offer.get("metadata", {}).duplicate(true))
	return true

## Expires a proposed offer (either because its expires_turn has passed or via forced expiry).
## Returns true if the offer was successfully expired.
func expire_offer(offer_id: String) -> bool:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty() or offer.status != TradeStatus.PROPOSED:
		return false
	offer.status = TradeStatus.EXPIRED
	_clean_indexes(offer_id)
	offer_expired.emit(offer_id)

	# Richer signal for future Diplomacy / Relations layer
	trade_deal_outcome.emit(offer_id, offer.from_tag, offer.to_tag, int(TradeStatus.EXPIRED), offer.visibility, offer.get("metadata", {}).duplicate(true))
	return true

## Returns only currently active (PROPOSED) offers involving this country.
func get_active_offers_for_country(country_tag: String, visibility_filter = null) -> Array:
	var tag := _norm_tag(country_tag)
	var result := []
	var all_for_country = get_offers_for_country(tag, visibility_filter)
	for o in all_for_country:
		if o.get("status") == TradeStatus.PROPOSED:
			result.append(o)
	return result

## Convenience for the public (diplomatic) market.
func get_public_offers() -> Array:
	var result := []
	for offer in _offers.values():
		if offer.get("visibility") == TradeVisibility.PUBLIC \
				and offer.get("status") == TradeStatus.PROPOSED:
			result.append(offer)
	return result

func get_offers_for_country(country_tag: String, visibility_filter = null) -> Array:
	var tag := _norm_tag(country_tag)
	var result := []
	if tag.is_empty():
		for offer in _offers.values():
			if offer.get("status") != TradeStatus.PROPOSED:
				continue
			if visibility_filter == null or offer.visibility == visibility_filter:
				result.append(offer)
		return result

	if _offers_by_from.has(tag):
		for id in _offers_by_from[tag]:
			var o = _offers[id]
			if visibility_filter == null or o.visibility == visibility_filter:
				result.append(o)
	if _offers_by_to.has(tag):
		for id in _offers_by_to[tag]:
			var o = _offers[id]
			if visibility_filter == null or o.visibility == visibility_filter:
				if o not in result: result.append(o)
	return result

## Returns all (PROPOSED) offers between two specific countries in either direction.
## Extremely useful for a future Diplomacy screen showing the bilateral relationship.
## This is a lightweight convenience on top of the existing bidirectional indexes.
func get_offers_between(from_tag: String, to_tag: String, visibility_filter = null) -> Array:
	var a := _norm_tag(from_tag)
	var b := _norm_tag(to_tag)
	if a.is_empty() or b.is_empty():
		return []

	var result := []
	var candidates := []

	if _offers_by_from.has(a):
		candidates.append_array(_offers_by_from[a])
	if _offers_by_to.has(a):
		candidates.append_array(_offers_by_to[a])

	for id in candidates:
		var o = _offers.get(id, {})
		if o.is_empty() or o.get("status") != TradeStatus.PROPOSED:
			continue
		var other := o.to_tag if o.from_tag == a else o.from_tag
		if other == b:
			if visibility_filter == null or o.visibility == visibility_filter:
				result.append(o)

	return result

## =============================================================================
## UI-FACING HELPERS (Data Preparation for Trade UI)
## =============================================================================
## These methods prepare raw offer data into clean, display-friendly structures.
## They are the primary recommended way for any Trade UI (or future diplomacy screen)
## to consume offer information without directly inspecting internal dicts.

## Returns a rich, UI-ready dictionary for a single offer.
## Call this from any offer list, details panel, or tooltip.
##
## Returns something like:
## {
##   "id": "...",
##   "from_tag": "GER", "from_display": "Germany",   # future: can pull from LeaderManager or country data
##   "to_tag": "HUN",   "to_display": "Hungary",
##   "visibility": "PUBLIC" or "BLACK",
##   "status": "PROPOSED",
##   "risk_level": 0.72,                              # only present / meaningful for BLACK offers
##   "expires_turn": 1938,
##   "is_expired": false,
##   "offered": [ { "type": "...", "id": "...", "quantity": 1.0, "display": "12x Panzer IV (0.95 quality)" }, ... ],
##   "requested": [ ... ],
##   "fairness": { ... },                             # full evaluate_fairness result if for_country provided
##   "metadata": { "exposure_risk": 0.72, "generated_by": "black_market" }
## }
func get_offer_display_data(offer_id: String, for_country: String = "") -> Dictionary:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty():
		return {"id": offer_id, "error": "Offer not found"}

	var display := {}
	display["id"] = offer_id
	display["from_tag"] = offer.from_tag
	display["to_tag"] = offer.to_tag
	display["from_display"] = offer.from_tag   # TODO: Replace with proper country name lookup when available
	display["to_display"] = offer.to_tag
	display["visibility"] = offer.visibility
	display["status"] = offer.status
	display["created_turn"] = offer.get("created_turn", 0)
	display["expires_turn"] = offer.get("expires_turn", -1)
	display["is_expired"] = offer.get("expires_turn", -1) > 0 and _current_year >= offer.get("expires_turn", -1)

	# Risk information (primarily for Black Market UI)
	if offer.visibility == TradeVisibility.BLACK:
		var risk := float(offer.get("metadata", {}).get("exposure_risk", 0.0))
		display["risk_level"] = risk
		display["risk_category"] = _get_risk_category(risk)
	else:
		display["risk_level"] = 0.0
		display["risk_category"] = "none"

	# Formatted items (ready for ItemList / RichText)
	display["offered"] = []
	for item in offer.offered:
		display["offered"].append(_format_trade_item_for_display(item))

	display["requested"] = []
	for item in offer.requested:
		display["requested"].append(_format_trade_item_for_display(item))

	# Full fairness evaluation if the caller wants it for the current player
	if not for_country.is_empty():
		display["fairness"] = evaluate_fairness(offer_id, for_country)

	display["metadata"] = offer.get("metadata", {}).duplicate(true)

	return display

## Private helper – turns a raw TradeItem into a display-friendly dict.
func _format_trade_item_for_display(item: Dictionary) -> Dictionary:
	var fmt := {}
	fmt["type"] = item.get("type", "UNKNOWN")
	fmt["id"] = item.get("id", "")
	fmt["quantity"] = item.get("quantity", 0.0)
	fmt["quality_modifier"] = item.get("quality_modifier", 1.0)

	var qmod := float(item.get("quality_modifier", 1.0))
	var qty := float(item.get("quantity", 0.0))
	var type_name := str(item.get("type", "")).capitalize()

	var name_part := str(item.get("id", "Unknown")).replace("_", " ").capitalize()
	if qmod != 1.0:
		name_part += " (%.2f× quality)" % qmod

	var qty_str := ""
	if qty > 0:
		if qty == int(qty):
			qty_str = str(int(qty)) + "× "
		else:
			qty_str = "%.1f× " % qty

	fmt["display_name"] = qty_str + name_part
	fmt["display_short"] = name_part
	fmt["metadata"] = item.get("metadata", {}).duplicate(true)

	return fmt

## Simple risk categorization for UI badges / color coding.
func _get_risk_category(risk: float) -> String:
	if risk < 0.35:
		return "low"
	elif risk < 0.6:
		return "medium"
	elif risk < 0.8:
		return "high"
	else:
		return "extreme"

## Returns a filtered and optionally sorted list of display data for an offer list / market view.
## This is the recommended entry point for any TradeMarketView or diplomacy screen.
##
## Parameters:
##   country_tag      – whose offers to show (empty = all)
##   visibility_filter – TradeVisibility.PUBLIC, TradeVisibility.BLACK, or null for both
##   sort_key         – "fairness", "risk", "expiry", "value" (only when for_country is provided for fairness)
##   ascending        – sort direction
##   search_term      – simple substring filter on item ids / display names (case insensitive)
func get_market_offers_display_data(country_tag: String = "", visibility_filter = null, sort_key: String = "", ascending: bool = true, search_term: String = "", for_country_for_fairness: String = "", other_party_tag: String = "") -> Array:
	var raw_offers := []
	if not other_party_tag.is_empty():
		# New diplomacy-friendly path: offers specifically between two countries
		raw_offers = get_offers_between(country_tag, other_party_tag, visibility_filter)
	elif country_tag.is_empty():
		raw_offers = get_offers_for_country("", visibility_filter)
	else:
		raw_offers = get_active_offers_for_country(country_tag, visibility_filter)

	var display_list := []
	for offer in raw_offers:
		var disp := get_offer_display_data(offer.id, for_country_for_fairness)
		display_list.append(disp)

	# Simple client-side search (supports "involves:GER" or "with:GER" for diplomacy-style bilateral filtering)
	if not search_term.is_empty():
		var term := search_term.to_lower().strip_edges()
		var involves_tag := ""
		if term.begins_with("involves:") or term.begins_with("with:"):
			involves_tag = term.split(":")[1].strip_edges().to_upper()
			term = ""  # consume the special token

		var filtered := []
		for d in display_list:
			var haystack := (str(d.get("from_display", "")) + " " + str(d.get("to_display", ""))).to_lower()
			for it in d.get("offered", []) + d.get("requested", []):
				haystack += " " + str(it.get("display_name", "")).to_lower()

			var matches := true
			if not term.is_empty() and term not in haystack:
				matches = false
			if not involves_tag.is_empty():
				var from_t := str(d.get("from_tag", "")).to_upper()
				var to_t := str(d.get("to_tag", "")).to_upper()
				if from_t != involves_tag and to_t != involves_tag:
					matches = false

			if matches:
				filtered.append(d)
		display_list = filtered

	# Basic sorting (lightweight – done in UI layer for now, but centralized here for convenience)
	if not sort_key.is_empty() and not display_list.is_empty():
		match sort_key:
			"risk":
				display_list.sort_custom(func(a, b): return a.get("risk_level", 0) < b.get("risk_level", 0) if ascending else a.get("risk_level", 0) > b.get("risk_level", 0))
			"expiry":
				display_list.sort_custom(func(a, b): return a.get("expires_turn", 99999) < b.get("expires_turn", 99999) if ascending else a.get("expires_turn", 99999) > b.get("expires_turn", 99999))
			"value":
				# Requires fairness data
				if for_country_for_fairness != "":
					display_list.sort_custom(func(a, b):
						var va := float(a.get("fairness", {}).get("value_offered", 0))
						var vb := float(b.get("fairness", {}).get("value_offered", 0))
						return va < vb if ascending else va > vb
					)
			"fairness":
				if for_country_for_fairness != "":
					display_list.sort_custom(func(a, b):
						var sa := float(a.get("fairness", {}).get("score", 1.0))
						var sb := float(b.get("fairness", {}).get("score", 1.0))
						return sa < sb if ascending else sa > sb
					)

	return display_list

## =============================================================================
## UI INTERACTION HELPERS
## =============================================================================
## These methods make it easy for a Trade UI to trigger actions without duplicating logic.

## Rejects an offer and emits the rejection with a UI-provided reason.
## Preferred over calling reject_offer directly from UI code.
func reject_offer_from_ui(offer_id: String, reason: String = "Rejected by player") -> bool:
	var success := reject_offer(offer_id, reason)
	if success:
		deal_rejected.emit(offer_id, "", "", reason)  # from/to can be filled by caller if needed
	return success

## Creates a counter-offer based on an existing one.
## The UI is responsible for deciding the new offered/requested items.
## Returns the new offer_id or "" on failure.
func create_counter_offer(base_offer_id: String, new_offered: Array, new_requested: Array, expires_in_years: int = -1) -> String:
	var base = _offers.get(base_offer_id, {})
	if base.is_empty() or base.status != TradeStatus.PROPOSED:
		push_error("TradeManager: cannot counter non-existent or non-proposed offer " + base_offer_id)
		return ""

	# Swap direction for the counter
	var new_from := base.to_tag
	var new_to := base.from_tag

	var new_id := create_offer(new_from, new_to, new_offered, new_requested, base.visibility, expires_in_years)
	if new_id != "":
		# Stamp counter metadata so future Diplomacy/Relations systems can correlate offer chains
		var new_offer = _offers.get(new_id, {})
		if not new_offer.is_empty():
			new_offer["metadata"]["is_counter"] = true
			new_offer["metadata"]["counter_of"] = base_offer_id
			new_offer["metadata"]["original_visibility"] = base.visibility

		counter_offer_requested.emit(base_offer_id, new_from, new_to)
	return new_id

## Convenience wrappers so UI code doesn't need to remember the generator signatures.
func generate_public_market_offers_for_ui(country_tag: String, count: int = 3) -> Array[String]:
	return generate_public_market_offers(country_tag, count)

func generate_black_market_opportunity_for_ui(country_tag: String, risk_level: float = 0.5) -> String:
	return generate_black_market_opportunity(country_tag, risk_level)

## Emits a signal that a UI can listen to in order to open a details panel.
func request_offer_details(offer_id: String, for_country: String = "") -> void:
	offer_details_requested.emit(offer_id, for_country)

## =============================================================================
## TRADE TRANSIT & FLOW QUERIES (New lightweight foundation)
## =============================================================================
## These methods allow Supply transit layers, interdiction systems, and future Diplomacy/Relations
## code to observe ongoing trade deliveries.

func get_active_trade_flows() -> Array:
	var result := []
	for flow in _trade_flows.values():
		if flow.active:
			result.append(flow)
	return result

func get_active_trade_flows_between(from_tag: String, to_tag: String) -> Array:
	var a := _norm_tag(from_tag)
	var b := _norm_tag(to_tag)
	var result := []
	for flow in _trade_flows.values():
		if flow.active and ((flow.from_tag == a and flow.to_tag == b) or (flow.from_tag == b and flow.to_tag == a)):
			result.append(flow)
	return result

func get_trade_flow(flow_id: String) -> TradeFlow:
	return _trade_flows.get(flow_id, null)

## Returns all active flows carrying a specific item type (useful for interdiction targeting).
func get_active_trade_flows_by_item(item_type: String, item_id: String = "") -> Array:
	var result := []
	for flow in _trade_flows.values():
		if flow.active and flow.item_type == item_type:
			if item_id.is_empty() or flow.item_id == item_id:
				result.append(flow)
	return result

## Returns total quantity per turn of a specific good moving from one side to the other (either direction).
func get_total_flow_rate_between(from_tag: String, to_tag: String, item_type: String, item_id: String = "") -> float:
	var total := 0.0
	var a := _norm_tag(from_tag)
	var b := _norm_tag(to_tag)
	for flow in _trade_flows.values():
		if not flow.active:
			continue
		if not ((flow.from_tag == a and flow.to_tag == b) or (flow.from_tag == b and flow.to_tag == a)):
			continue
		if flow.item_type != item_type:
			continue
		if not item_id.is_empty() and flow.item_id != item_id:
			continue
		total += flow.quantity_per_turn
	return total


## ---------------------------------------------------------------------------
## Map / supply overlay helpers (ProvinceInsight / MapRenderer / future interdiction)
## ---------------------------------------------------------------------------
## - Map layers listen to `trade_flow_interdicted` for refreshes (throughput/metadata); TradeManager owns
##   player toasts for major losses — avoids duplicate announcements with suspend callbacks.
## These helpers are the supported API for locating active TradeFlows on the tactical map:
## - Use `viewer_country_tag == ""` to default to the current player nation (fair for tooltips).
## - `collect_*` walks all active flows O(n flows); usually small. Cap `max_entries` in UI callers.
## - When adding per-leg cargo simulation or asymmetric bilateral routes, prefer extending
##   `collect_trade_flow_summaries_for_map_province` with new Dictionary keys rather than branching UI.
##
## Interdiction / blockade: add path fractional hit-tests or SupplyRoutePlan lookups here later.
func get_registered_route_plan_for_flow(flow: TradeFlow) -> SupplyRoutePlan:
	if flow == null or str(flow.route_plan_id).strip_edges().is_empty():
		return null
	if typeof(SupplyManager) == TYPE_NIL:
		return null
	var plan_variant: Variant = SupplyManager.get_route(flow.route_plan_id)
	if plan_variant is SupplyRoutePlan:
		return plan_variant
	return null


## True when `viewer_country_tag` is party to (from/to) the flow or owns/controls `province`.
func viewer_should_see_trade_flow(flow: TradeFlow, province: Province, viewer_country_tag: String) -> bool:
	if flow == null or province == null or not flow.active or not flow.is_ongoing():
		return false
	var vt := _norm_tag(viewer_country_tag)
	if vt.is_empty():
		return false
	if _norm_tag(flow.from_tag) == vt or _norm_tag(flow.to_tag) == vt:
		return true
	if _norm_tag(province.owner_tag) == vt:
		return true
	if _norm_tag(province.controller_tag) == vt:
		return true
	return false


func _format_trade_flow_cargo_line(flow: TradeFlow) -> String:
	var qty := flow.quantity_per_turn
	var nm := str(flow.item_id).strip_edges()
	var t_variant: Variant = flow.item_type
	var kind := ""
	if typeof(t_variant) == TYPE_STRING:
		kind = str(t_variant)
	else:
		match int(t_variant):
			TradeItemType.RESOURCE:
				kind = "RESOURCE"
			TradeItemType.EQUIPMENT:
				kind = "EQUIPMENT"
			TradeItemType.SUPPLY:
				kind = "SUPPLY"
			_:
				kind = "GOODS"
	if nm.is_empty():
		return "%.1f %s/turn" % [qty, kind.to_lower()]
	return "%s %.1f/turn (%s)" % [nm, qty, kind.to_lower()]


func collect_trade_flow_summaries_for_map_province(
	province_id: int,
	viewer_country_tag: String = "",
	max_entries: int = 4,
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# UI should pass a small cap (3–6). Large values are for counting / diplomacy rollups only.
	var cap := clampi(max_entries, 1, 4096)
	if typeof(MapManager) == TYPE_NIL:
		return out
	var p: Province = MapManager.get_province(province_id)
	if p == null:
		return out
	var vt := _norm_tag(viewer_country_tag)
	if vt.is_empty():
		vt = _get_player_country_tag()
	var seen := {}
	for flow in get_active_trade_flows():
		if not (flow is TradeFlow):
			continue
		var tf := flow as TradeFlow
		if not tf.is_ongoing():
			continue
		if not viewer_should_see_trade_flow(tf, p, vt):
			continue
		var plan := get_registered_route_plan_for_flow(tf)
		if plan == null or plan.province_path.is_empty():
			continue
		if not province_id in plan.province_path:
			continue
		if seen.has(tf.flow_id):
			continue
		seen[tf.flow_id] = true
		var role := "transit"
		var vt2 := vt
		if vt2 == _norm_tag(tf.from_tag) and province_id == int(plan.source_province_id):
			role = "export_hub"
		elif vt2 == _norm_tag(tf.from_tag):
			role = "export_transit"
		elif vt2 == _norm_tag(tf.to_tag) and province_id == int(plan.target_province_id):
			role = "import_hub"
		elif vt2 == _norm_tag(tf.to_tag):
			role = "import_transit"
		var pref := str(tf.preferred_mode).strip_edges()
		var mode_out := str(plan.routing_mode)
		if not pref.is_empty():
			mode_out = pref
		out.append({
			"flow_id": tf.flow_id,
			"from": tf.from_tag,
			"to": tf.to_tag,
			"role": role,
			"cargo_line": _format_trade_flow_cargo_line(tf),
			"risk_pct": int(round(float(tf.metadata.get("route_interdiction_chance", 0.0)) * 100.0)),
			"mode": mode_out,
		})
		if out.size() >= cap:
			break
	return out


## Count of flows with an assigned route touching `province_id` (use for chip `×N`; prefer `cap` in collect for UI).
func count_trade_flows_on_map_province(province_id: int, viewer_country_tag: String = "") -> int:
	return collect_trade_flow_summaries_for_map_province(province_id, viewer_country_tag, 9999).size()


## =============================================================================
## DIPLOMACY / RELATIONS LAYER HOOKS (Lightweight Extension Points)
## =============================================================================
## These are intentionally non-committal. A future DiplomacyManager, Relations system,
## or National Focus tree can call or connect to them. Trade itself does not apply
## opinion/prestige changes — it only suggests and notifies.

## Called after a deal reaches a terminal state (accepted/rejected/expired).
## Future diplomacy code can use this to apply opinion deltas, update relationship history,
## or trigger events. The implementation here is a no-op stub that emits the signal.
func notify_trade_diplomatic_outcome(offer_id: String) -> void:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty():
		return

	var from := offer.from_tag
	var to := offer.to_tag
	var status := int(offer.get("status", -1))
	var vis := offer.get("visibility", TradeVisibility.PUBLIC)
	var meta := offer.get("metadata", {}).duplicate(true)

	# Emit the rich outcome signal (already also emitted from accept/reject/expire for convenience)
	trade_deal_outcome.emit(offer_id, from, to, status, vis, meta)

	# Optional: emit a suggested effect for Relations systems (opinion delta is left to caller)
	# Example usage by future code:
	#   if status == TradeStatus.ACCEPTED:
	#       diplomacy.apply_opinion(from, to, +0.05, "successful trade")
	trade_diplomatic_effect_suggested.emit(from, to, 0.0, "Trade deal resolved: " + str(TradeStatus.keys()[status] if status >= 0 else "unknown"), offer_id, vis)

## Returns a lightweight diplomatic summary for a bilateral relationship.
## Intended for use by DiplomacyView or future Relations systems.
## Includes active offer count and basic metadata.
func get_diplomatic_summary_with(country_tag: String, other_party_tag: String) -> Dictionary:
	var deals := get_offers_between(country_tag, other_party_tag)
	var player := _get_player_country_tag()

	var sent := 0
	var received := 0
	for d in deals:
		if d.get("from_tag") == player:
			sent += 1
		else:
			received += 1

	return {
		"active_offers": deals.size(),
		"sent_by_player": sent,
		"received_by_player": received,
		"has_active_deals": not deals.is_empty()
	}

## Returns a suggested opinion delta for a completed deal (purely advisory).
## A Relations/Diplomacy system can ignore this or scale it by current relations, distance, ideology, etc.
## This keeps all actual opinion math outside TradeManager.
func get_suggested_opinion_delta_for_deal(offer_id: String) -> float:
	var offer = _offers.get(offer_id, {})
	if offer.is_empty():
		return 0.0

	var status := offer.get("status", -1)
	if status != TradeStatus.ACCEPTED:
		return 0.0  # Only successful deals generate positive suggestion by default

	# Very lightweight heuristic (future DiplomacyManager can do something much smarter)
	var base := 0.04
	if offer.visibility == TradeVisibility.BLACK:
		base *= 0.6  # Risky deals give less diplomatic goodwill

	# High-value items (PROVINCE, major designs) could be worth more — left for caller to enrich
	return base

## Basic black market hook.
## Generates a risky but potentially rewarding offer for the target country.
## The "from" side is treated as a shadow/black market source.
## Returns the offer_id or "" on failure.
## Future: AgentManager can call this (or similar) from successful smuggling / underworld missions,
## and can later scan active BLACK offers for "exposure_risk" to trigger events or counter-intel.
func generate_black_market_opportunity(country_tag: String, risk_level: float = 0.35) -> String:
	var tag := _norm_tag(country_tag)
	if tag.is_empty():
		return ""

	# Example attractive but risky offer: a high-value foreign DESIGN at a "discount"
	# (low requested resources) but with exposure risk.
	var offered := []
	var requested := []

	# Dynamic risky/rewarding offers — higher reward (good terms for buyer) but with exposure risk
	var rng := randf()
	if rng < 0.3:
		# Risky high-value design (recently captured or restricted tech)
		offered.append({
			"type": TradeItemType.DESIGN,
			"id": "pzkpfw_iv_ausf_h",  # placeholder; future: query interesting unowned/restricted designs
			"quantity": 1,
			"quality_modifier": 1.05,  # premium but "hot"
			"metadata": {"kind": "purchased", "notes": "captured prototype - high risk of exposure"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 400.0})  # discounted price
	elif rng < 0.55:
		# Scarce/embargoed resources at a premium but with intel risk
		offered.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 1200.0})
		requested.append({"type": TradeItemType.RESOURCE, "id": "oil", "quantity": 600.0})
	elif rng < 0.75:
		# Intel package or tech fragment (very high reward, very high risk)
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_supply_routes",
			"quantity": 1,
			"metadata": {"type": "supply_intel", "notes": "detailed enemy depot locations"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 300.0})
	else:
		# High-risk province concession (extremely valuable but massive exposure)
		offered.append({
			"type": TradeItemType.PROVINCE,
			"id": "strategic_border_province",  # placeholder; future: real contested or valuable province ids
			"quantity": 1,
			"metadata": {"notes": "covert territorial concession - extreme exposure risk if discovered"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 500.0})

	# Occasionally add a very high-reward but ultra-risky tech/intel bundle
	if randf() < 0.15:
		offered.append({
			"type": TradeItemType.TECH_SHARE,
			"id": "advanced_doctrine_fragment",
			"quantity": 1,
			"metadata": {"notes": "stolen or leaked high-value tech - extreme black market risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 200.0})

	# Ultra high-risk EQUIPMENT bundle (restricted or captured gear)
	if randf() < 0.1:
		offered.append({
			"type": TradeItemType.EQUIPMENT,
			"id": "advanced_tank_engine",
			"quantity": 50,
			"metadata": {"notes": "smuggled restricted equipment - very high exposure risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 400.0})

	# Ultra high-risk DOCKING_RIGHTS (covert naval base access - massive risk)
	if randf() < 0.08:
		offered.append({
			"type": TradeItemType.DOCKING_RIGHTS,
			"id": "secret_naval_facility",
			"quantity": 1,
			"metadata": {"duration_months": 24, "modifiers": {"supply_throughput": 0.25, "naval_access": 2.0}, "notes": "covert naval basing rights - extreme exposure risk if discovered"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "oil", "quantity": 600.0})

	# Ultra high-risk INTEL bundle (enemy agent network details - massive risk)
	if randf() < 0.06:
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_agent_networks",
			"quantity": 1,
			"metadata": {"type": "agent_intel", "notes": "detailed enemy agent network locations and operations - extreme exposure risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 400.0})

	# Ultra high-risk SUPPLY bundle (covert supply disruption intel - massive risk)
	if randf() < 0.05:
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_supply_vulnerabilities",
			"quantity": 1,
			"metadata": {"type": "supply_intel", "notes": "detailed enemy supply line vulnerabilities - extreme exposure risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 350.0})

	# High-stakes mixed EQUIPMENT + DESIGN bundle (captured gear + its technical data - very high risk/reward)
	if randf() < 0.07:
		offered.append({
			"type": TradeItemType.EQUIPMENT,
			"id": "captured_heavy_tank",
			"quantity": 6,
			"metadata": {"notes": "smuggled captured heavy armor - extreme exposure risk if discovered"}
		})
		offered.append({
			"type": TradeItemType.DESIGN,
			"id": "heavy_tank_design",
			"quantity": 1,
			"quality_modifier": 0.95,
			"metadata": {"kind": "purchased", "notes": "full technical package for captured design - massive leak/intel risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 850.0})

	# High-stakes INTEL + DESIGN bundle (leaked prototype data + agent network details)
	if randf() < 0.05:
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "prototype_tech_leak",
			"quantity": 1,
			"metadata": {"type": "tech_intel", "notes": "detailed enemy prototype specifications and test data - extreme exposure risk"}
		})
		offered.append({
			"type": TradeItemType.DESIGN,
			"id": "prototype_tank_variant",
			"quantity": 1,
			"quality_modifier": 1.0,
			"metadata": {"kind": "purchased", "notes": "stolen design data from prototype program"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 650.0})

	# Ultra high-stakes PROVINCE + INTEL bundle (territorial concession + detailed enemy agent network intel)
	if randf() < 0.04:
		offered.append({
			"type": TradeItemType.PROVINCE,
			"id": "strategic_border_province",
			"quantity": 1,
			"metadata": {"notes": "covert territorial concession in exchange for intelligence - catastrophic exposure risk if discovered"}
		})
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_agent_networks_detailed",
			"quantity": 1,
			"metadata": {"type": "agent_intel", "notes": "comprehensive enemy agent network locations, handlers, and safe houses - extreme risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 1200.0})

	# Triple high-risk package (DESIGN + EQUIPMENT + INTEL) - very rare, extremely lucrative but dangerous
	if randf() < 0.03:
		offered.append({
			"type": TradeItemType.DESIGN,
			"id": "advanced_fighter_variant",
			"quantity": 1,
			"quality_modifier": 1.05,
			"metadata": {"kind": "purchased", "notes": "stolen next-generation fighter design data"}
		})
		offered.append({
			"type": TradeItemType.EQUIPMENT,
			"id": "prototype_jet_engine",
			"quantity": 12,
			"metadata": {"notes": "smuggled prototype engines matching the stolen design"}
		})
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_rnd_facility_details",
			"quantity": 1,
			"metadata": {"type": "tech_intel", "notes": "detailed layout and security of enemy research facilities - massive exposure risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 950.0})

	# High-stakes logistics betrayal bundle (restricted EQUIPMENT + supply sabotage INTEL) - directly threatens enemy throughput
	if randf() < 0.04:
		offered.append({
			"type": TradeItemType.EQUIPMENT,
			"id": "captured_logistics_vehicles",
			"quantity": 18,
			"metadata": {"notes": "smuggled captured logistics and bridging equipment - high exposure risk"}
		})
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_supply_chokepoints",
			"quantity": 1,
			"metadata": {"type": "supply_intel", "notes": "detailed mapping of enemy supply chokepoints and vulnerable depots - severe operational risk if traced"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 780.0})

	# Rare captured prototype + supply vulnerability INTEL bundle (very high reward, very high risk)
	if randf() < 0.025:
		offered.append({
			"type": TradeItemType.DESIGN,
			"id": "experimental_heavy_tank",
			"quantity": 1,
			"quality_modifier": 1.0,
			"metadata": {"kind": "purchased", "notes": "stolen experimental heavy tank design and test data"}
		})
		offered.append({
			"type": TradeItemType.INTEL,
			"id": "enemy_depot_vulnerabilities",
			"quantity": 1,
			"metadata": {"type": "supply_intel", "notes": "precise locations and schedules of major enemy fuel and ammo depots - extreme exposure risk"}
		})
		requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 1100.0})

	var offer_id := create_offer("BLACK_MARKET", tag, offered, requested, TradeVisibility.BLACK)

	if offer_id != "":
		var offer = _offers[offer_id]
		# Higher exposure risk for the riskiest mixed bundles; extra penalty for territory trades + large deals
		var base_risk := clampf(risk_level, 0.15, 0.85)
		var has_territory := false
		var total_qty := 0.0
		for it in offered:
			if it.get("type") == TradeItemType.PROVINCE:
				has_territory = true
			total_qty += float(it.get("quantity", 0.0))
		if offered.size() >= 2:
			base_risk = clampf(base_risk + 0.12, 0.25, 0.92)
		if has_territory:
			base_risk = clampf(base_risk + 0.15, 0.35, 0.95)
		if total_qty > 20.0:
			base_risk = clampf(base_risk + 0.08, 0.30, 0.95)
		offer["metadata"]["exposure_risk"] = base_risk
		offer["metadata"]["generated_by"] = "black_market"
		# Optional: make it time-limited for urgency
		offer["expires_turn"] = _current_year + 2

	return offer_id

## Generates natural public market opportunities for a country.
## These feel like organic diplomatic/trade activity (surplus goods or designs the country
## is willing to export). Offers are created with PUBLIC visibility and immediately
## appear in get_public_offers() / get_active_offers_for_country.
## Returns array of created offer_ids (empty if none generated).
func generate_public_market_offers(country_tag: String, count: int = 2) -> Array[String]:
	var tag := _norm_tag(country_tag)
	if tag.is_empty() or count <= 0:
		return []

	var created_ids: Array[String] = []

	# Simple heuristic generation for natural-feeling offers
	# Future: could query actual stockpiles, obsolete designs via DesignManager, etc.
	for i in range(count):
		var offered := []
		var requested := []

		var rng := randf()
		if rng < 0.4:
			# Surplus resource offer (e.g. steel-rich country offering steel for rubber/oil)
			offered.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 1500.0})
			requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 600.0})
		elif rng < 0.65:
			# Design they are willing to license/export (non-core or older model)
			offered.append({
				"type": TradeItemType.DESIGN,
				"id": "pzkpfw_iv_ausf_d",  # placeholder older variant
				"quantity": 1,
				"quality_modifier": 0.88,
				"metadata": {"kind": "licensed", "notes": "export license - older production model"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "oil", "quantity": 450.0})
		elif rng < 0.85:
			# Temporary docking rights (strategic for naval access)
			offered.append({
				"type": TradeItemType.DOCKING_RIGHTS,
				"id": "port_access_" + tag,
				"quantity": 1,
				"metadata": {"duration_months": 18, "modifiers": {"supply_throughput": 0.15, "port_access": 1.0}, "notes": "temporary naval basing rights"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 300.0})
		else:
			# Mixed surplus offer (resources + small design license) for recurring variety
			offered.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 800.0})
			offered.append({
				"type": TradeItemType.DESIGN,
				"id": "older_fighter_variant",
				"quantity": 1,
				"quality_modifier": 0.82,
				"metadata": {"kind": "licensed", "notes": "surplus export model"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 400.0})

		# Additional recurring case for docking + resource mix (naval strategy flavor)
		if randf() < 0.2:
			offered.append({
				"type": TradeItemType.DOCKING_RIGHTS,
				"id": "temporary_port_" + tag,
				"quantity": 1,
				"metadata": {"duration_months": 12, "modifiers": {"supply_throughput": 0.1}, "notes": "short-term naval access deal"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 250.0})

		# Occasional diplomatic package (TECH_SHARE + small resource) for variety
		if randf() < 0.15:
			offered.append({
				"type": TradeItemType.TECH_SHARE,
				"id": "basic_industry_tech",
				"quantity": 1,
				"metadata": {"notes": "diplomatic tech exchange package"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 200.0})

		# Occasional SUPPLY credit offer for strategic depth (abstract supply support)
		if randf() < 0.1:
			offered.append({
				"type": TradeItemType.SUPPLY,
				"id": "supply_credit_bundle",
				"quantity": 1000.0,
				"metadata": {"notes": "emergency supply support package"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 300.0})

		# Occasional mixed SUPPLY + small DESIGN for diplomatic package flavor
		if randf() < 0.08:
			offered.append({
				"type": TradeItemType.SUPPLY,
				"id": "logistics_support_package",
				"quantity": 800.0,
				"metadata": {"notes": "combined supply and design support"}
			})
			offered.append({
				"type": TradeItemType.DESIGN,
				"id": "logistics_vehicle_variant",
				"quantity": 1,
				"quality_modifier": 0.9,
				"metadata": {"kind": "licensed", "notes": "support vehicle export"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 200.0})

		# Occasional new resource pair for variety (e.g. oil for rubber in different regions)
		if randf() < 0.1:
			offered.append({"type": TradeItemType.RESOURCE, "id": "oil", "quantity": 700.0})
			requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 500.0})

		# Occasional civilian / industrial surplus trade for everyday diplomatic flavor
		if randf() < 0.07:
			offered.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 2200.0})
			requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 850.0})

		# Occasional mixed docking + small TECH_SHARE for recurring naval/diplomatic activity
		if randf() < 0.06:
			offered.append({
				"type": TradeItemType.DOCKING_RIGHTS,
				"id": "naval_cooperation_" + tag,
				"quantity": 1,
				"metadata": {"duration_months": 15, "modifiers": {"supply_throughput": 0.12, "port_access": 0.8}, "notes": "joint naval access agreement"}
			})
			offered.append({
				"type": TradeItemType.TECH_SHARE,
				"id": "naval_logistics_tech",
				"quantity": 1,
				"metadata": {"notes": "limited naval doctrine exchange"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 420.0})

		# Occasional agricultural / construction surplus trade (everyday minor-power diplomatic flavor)
		if randf() < 0.08:
			offered.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 1800.0})
			requested.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 720.0})

		# Occasional joint training / equipment package for allied cooperation feel
		if randf() < 0.05:
			offered.append({
				"type": TradeItemType.EQUIPMENT,
				"id": "training_vehicles",
				"quantity": 25,
				"metadata": {"notes": "surplus training and support vehicles for joint exercises"}
			})
			offered.append({
				"type": TradeItemType.TECH_SHARE,
				"id": "logistics_doctrine",
				"quantity": 1,
				"metadata": {"notes": "limited logistics and maintenance doctrine exchange"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "rubber", "quantity": 380.0})

		# Occasional medical / humanitarian supply trade (soft power diplomatic flavor)
		if randf() < 0.07:
			offered.append({"type": TradeItemType.RESOURCE, "id": "aluminum", "quantity": 950.0})
			requested.append({"type": TradeItemType.RESOURCE, "id": "fuel", "quantity": 410.0})

		# Occasional pure small TECH_SHARE "doctrine consultation" package (staff-level diplomatic cooperation)
		if randf() < 0.05:
			offered.append({
				"type": TradeItemType.TECH_SHARE,
				"id": "combined_arms_doctrine",
				"quantity": 1,
				"metadata": {"notes": "limited combined-arms doctrine consultation package"}
			})
			requested.append({"type": TradeItemType.RESOURCE, "id": "steel", "quantity": 280.0})

		var other_party := "WORLD_MARKET" if randf() < 0.5 else "TRADE_PARTNER_" + str(randi() % 5)
		var offer_id := create_offer(other_party, tag, offered, requested, TradeVisibility.PUBLIC)
		if offer_id != "":
			var offer = _offers[offer_id]
			offer["metadata"]["generated_by"] = "public_market"
			# Make some public offers time-sensitive for urgency
			if randf() < 0.3:
				offer["expires_turn"] = _current_year + 1
			created_ids.append(offer_id)

	return created_ids

## =============================================================================
## PRIVATE HELPERS
## =============================================================================

func _norm_tag(t: String) -> String:
	return t.strip_edges().to_upper()

func _generate_id() -> String:
	return "trade_%d_%d" % [_current_year, randi() % 100000]

func _index_offer(offer_id: String, from: String, to: String) -> void:
	if not _offers_by_from.has(from): _offers_by_from[from] = []
	if not _offers_by_to.has(to): _offers_by_to[to] = []
	_offers_by_from[from].append(offer_id)
	_offers_by_to[to].append(offer_id)

func _clean_indexes(offer_id: String) -> void:
	for dict in [_offers_by_from, _offers_by_to]:
		for arr in dict.values():
			arr.erase(offer_id)

## Core value engine — deliberately simple and heavily commented so it can be extended.
func _calculate_item_value(item: Dictionary, for_country: String) -> float:
	var type = item.get("type", TradeItemType.RESOURCE)
	var id := str(item.get("id", ""))
	var qty := float(item.get("quantity", 1.0))
	var qmod := float(item.get("quality_modifier", 1.0))

	match type:
		TradeItemType.DESIGN:
			# Use existing DesignManager / GameData for base value
			var base := 120.0  # fallback
			if typeof(DesignManager) != TYPE_NIL:
				# Prefer production_cost * complexity when available
				if GameData.design_data != null:
					var tmpl = GameData.design_data.get_template(id)
					if tmpl != null:
						base = float(tmpl.production_cost) * max(0.5, float(tmpl.production_complexity))
			base *= qmod
			# Strategic multiplier example (easy to make data-driven later)
			if typeof(DesignManager) != TYPE_NIL:
				if DesignManager.get_design_ownership(for_country, id) == DesignManager.DesignOwnership.UNIVERSAL:
					base *= 1.25  # you really want this foreign design
			return base * qty

		TradeItemType.RESOURCE:
			var rate := float(RESOURCE_BASE_RATES.get(id, 1.0))
			# Desperation / shortage pressure (hook into ProductionManager later)
			return rate * qty

		TradeItemType.EQUIPMENT:
			# Simple fallback — real implementation would look up ProductionManager equipment costs
			return 80.0 * qty * qmod

		TradeItemType.PROVINCE:
			# High strategic value for provinces — core territory/assets
			var base := 500.0  # base for any province
			if typeof(MapManager) != TYPE_NIL:
				var prov := MapManager.get_province(int(id))
				if prov != null:
					base = 300.0 + (float(prov.development_level) * 80.0) + (float(prov.infrastructure) * 40.0)
					# Strategic bonuses
					if "port" in str(prov.features).to_lower() or "naval" in str(prov.features).to_lower():
						base *= 1.8
					if prov.owner_tag != for_country and prov.controller_tag != for_country:
						base *= 1.4  # contested or enemy territory is more valuable to acquire
			return base * qty

		TradeItemType.INTEL:
			# Intel value scales with quantity and current strategic need (recon gap)
			var base := 80.0 * qty
			if typeof(NationalModifierManager) != TYPE_NIL:
				var current_recon := NationalModifierManager.get_national_modifier(for_country, "reconnaissance")
				if current_recon < 0.5:  # poor recon — intel is more valuable
					base *= 1.6
			# Bonus if high enemy presence (from Supply/Combat context — simplified check)
			base *= (1.0 + clampf(qty * 0.2, 0.0, 1.5))
			return base

		_:
			return 50.0 * qty   # generic stub value for unknown types

## Executes the actual transfer for a single item.
## When is_giver_side=true we are removing items from this country (payment / offer given up).
func _execute_transfer(country_tag: String, item: Dictionary, is_giver_side: bool = false) -> void:
	var type = item.get("type", TradeItemType.RESOURCE)
	var id := str(item.get("id", ""))
	var qty := float(item.get("quantity", 0.0))
	var tag := _norm_tag(country_tag)

	# Knowledge, rights, and territory: only the receiver pass mutates state (giver validated earlier).
	if is_giver_side and type in [
		TradeItemType.DESIGN,
		TradeItemType.TECH_SHARE,
		TradeItemType.DOCKING_RIGHTS,
		TradeItemType.INTEL,
		TradeItemType.SUPPLY,
		TradeItemType.PROVINCE,
	]:
		return

	if is_giver_side:
		qty = -abs(qty)

	match type:
		TradeItemType.DESIGN:
			if typeof(DesignManager) != TYPE_NIL and qty > 0:
				var kind := ACQUISITION_PURCHASED
				if str(item.get("metadata", {}).get("kind", "")).to_lower() == "licensed":
					kind = ACQUISITION_LICENSED
				DesignManager.grant_acquired_design(tag, id, kind)

		TradeItemType.RESOURCE:
			if _uses_player_stockpile(tag) and typeof(ProductionManager) != TYPE_NIL:
				var delta := {}
				delta[id] = qty
				if qty >= 0:
					ProductionManager.add_stockpile(delta)
				else:
					var cost := {}
					cost[id] = abs(qty)
					if not ProductionManager.pay_cost(cost):
						ProductionManager.national_stockpile[id] = max(0.0, float(ProductionManager.national_stockpile.get(id, 0.0)) + qty)

		TradeItemType.EQUIPMENT:
			if _uses_player_stockpile(tag) and typeof(ProductionManager) != TYPE_NIL:
				if qty >= 0:
					ProductionManager.add_to_national_stockpile(id, int(qty))
				else:
					ProductionManager.take_from_national_stockpile(id, int(abs(qty)))

		TradeItemType.TECH_SHARE:
			if typeof(TechnologyManager) != TYPE_NIL and qty > 0:
				# Share research progress or give intel bonus RP to the recipient
				var rp_amount := qty * 50.0  # scale as needed; id can be tech category hint
				TechnologyManager.apply_tech_intel_bonus(tag, rp_amount, "trade_share:" + id)

		TradeItemType.DOCKING_RIGHTS:
			if typeof(NationalModifierManager) != TYPE_NIL and qty > 0:
				var duration := int(item.get("metadata", {}).get("duration_months", 12))
				var modifiers := item.get("metadata", {}).get("modifiers", {"supply_throughput": 0.2, "port_access": 1.0})
				var effect := {
					"source": "trade_docking_rights",
					"source_detail": id,
					"modifiers": modifiers,
					"duration_months": duration,
					"remaining_months": duration
				}
				NationalModifierManager.apply_national_effect(tag, effect)

		TradeItemType.INTEL:
			if typeof(NationalModifierManager) != TYPE_NIL and qty > 0:
				var duration := int(item.get("metadata", {}).get("duration_months", 6))
				var modifiers := item.get("metadata", {}).get("modifiers", {"recon_bonus": qty * 0.1, "intel_visibility": 0.15})
				var effect := {
					"source": "trade_intel",
					"source_detail": id,
					"modifiers": modifiers,
					"duration_months": duration,
					"remaining_months": duration
				}
				NationalModifierManager.apply_national_effect(tag, effect)

		TradeItemType.SUPPLY:
			if typeof(NationalModifierManager) != TYPE_NIL and qty > 0:
				var duration := int(item.get("metadata", {}).get("duration_months", 6))
				var throughput := float(item.get("metadata", {}).get("supply_throughput", 0.15))
				if throughput <= 0.0:
					throughput = clampf(qty / 5000.0, 0.05, 0.35)
				var effect := {
					"source": "trade_supply",
					"source_detail": id,
					"modifiers": {"supply_throughput": throughput},
					"duration_months": duration,
					"remaining_months": duration,
				}
				NationalModifierManager.apply_national_effect(tag, effect)

		TradeItemType.PROVINCE:
			if typeof(MapManager) != TYPE_NIL and qty > 0:
				var province_id := int(id)
				MapManager.update_province_owner(province_id, tag, tag)

		_:
			push_warning("TradeManager: unhandled transfer type %s (id=%s)" % [type, id])

## =============================================================================
## ENUMS (defined after header so they are documented first)
## =============================================================================

enum TradeItemType {
	DESIGN,
	EQUIPMENT,
	RESOURCE,
	SUPPLY,
	TECH_SHARE,
	INTEL,
	PROVINCE,
	DOCKING_RIGHTS,
}

enum TradeVisibility {
	PUBLIC,
	BLACK,
}

enum TradeStatus {
	PROPOSED,
	ACCEPTED,
	REJECTED,
	EXPIRED,
	CANCELLED,
}

## Convenience constants (mirror DesignManager for consistency when calling grant)
const ACQUISITION_PURCHASED := "purchased"
const ACQUISITION_LICENSED := "licensed"

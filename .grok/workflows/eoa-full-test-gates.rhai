let meta = #{
    name: "eoa-full-test-gates",
    description: "Run EOA world_accurate full-test gates (unit + QC + optional Godot headless) and report PASS/FAIL",
    when_to_use: "After map, densify, WarLoop, save, or HOI-path changes; before claiming full-test green",
    phases: [
        #{ title: "Pure gates", detail: "unit suites + map QC + HOI matrix" },
        #{ title: "Headless", detail: "capital pick + multi-front assault (skipped if quick)" },
        #{ title: "Report", detail: "structured PASS/FAIL summary" },
    ],
};

let report_schema = #{
    "type": "object",
    "required": ["passed", "summary", "failed_steps"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "failed_steps": #{
            "type": "array",
            "items": #{ "type": "string" },
        },
        "notes": #{ "type": "string" },
    },
};

// args.quick = true → pure only (no Godot)
// args.with_perf = true → include map-tick perf sample
let quick = false;
let with_perf = false;
if args != () {
    if args.quick != () { quick = args.quick; }
    if args.with_perf != () { with_perf = args.with_perf; }
}

phase("Pure gates");

let pure_prompt = "";
pure_prompt += "You are verifying Epochs of Ascendancy full-test pure gates on the real repo. ";
pure_prompt += "Working directory must be the EOA repo root (epochs-of-ascendancy). ";
pure_prompt += "Run this exact command and capture full stdout/stderr:\n\n";
pure_prompt += "  tools/eoa_full_test_gates.sh --quick\n\n";
pure_prompt += "Use the shell/run_terminal_command tool. Do not re-implement tests. ";
pure_prompt += "After it finishes, set passed=true only if exit code is 0. ";
pure_prompt += "List any FAIL steps in failed_steps. summary = one short sentence. ";
pure_prompt += "Constraints: world_accurate ~3520; never renumber world_full; soft 30fps is not required here.";

let pure = agent(pure_prompt, #{
    label: "pure-gates",
    capability_mode: "execute",
    output_schema: report_schema,
});

if pure == () || pure.success != true {
    complete(#{
        passed: false,
        summary: "Pure-gates agent failed to run",
        failed_steps: ["pure-gates-agent"],
    });
}

if pure.output.passed != true {
    complete(#{
        passed: false,
        summary: pure.output.summary,
        failed_steps: pure.output.failed_steps,
        notes: pure.output.notes,
        mode: "quick",
    });
}

if quick == true {
    complete(#{
        passed: true,
        summary: pure.output.summary,
        failed_steps: [],
        notes: "quick mode — Godot headless skipped",
        mode: "quick",
    });
}

phase("Headless");

let head_prompt = "";
head_prompt += "EOA full-test headless Godot gates. Repo root = epochs-of-ascendancy. ";
head_prompt += "Run:\n\n";
head_prompt += "  tools/eoa_full_test_gates.sh --log /tmp/eoa-workflow-gates\n\n";
if with_perf == true {
    head_prompt += "Actually run with perf:\n  tools/eoa_full_test_gates.sh --with-perf --log /tmp/eoa-workflow-gates\n\n";
}
head_prompt += "Require exit 0. Also confirm launch_pick.log has ok=true and 0 SCRIPT ERROR lines; ";
head_prompt += "launch_assault.log has PASS (failures=0) and 0 SCRIPT ERROR. ";
head_prompt += "Use shell tools; read logs if needed. passed=true only if all hold. ";
head_prompt += "soft 30fps FAIL on perf is OK and must not set passed=false.";

let head = agent(head_prompt, #{
    label: "headless-gates",
    capability_mode: "execute",
    output_schema: report_schema,
});

if head == () || head.success != true {
    complete(#{
        passed: false,
        summary: "Headless-gates agent failed to run",
        failed_steps: ["headless-gates-agent"],
        pure_ok: true,
    });
}

phase("Report");

if head.output.passed != true {
    complete(#{
        passed: false,
        summary: head.output.summary,
        failed_steps: head.output.failed_steps,
        notes: head.output.notes,
        pure_ok: true,
        mode: "full",
    });
}

complete(#{
    passed: true,
    summary: "EOA full-test gates green (pure + headless)",
    failed_steps: [],
    pure_summary: pure.output.summary,
    headless_summary: head.output.summary,
    mode: "full",
});

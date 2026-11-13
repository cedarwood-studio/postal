#!/usr/bin/env python3
"""Parity check for one commit, run in CI.

Compares this commit's test results and recorded HTTP behaviors with the
baseline recorded before the upgrade began (.upgrade/baseline/). Fails when
an example that passed at the baseline fails or is missing, or when a
recorded response differs without a declared reason in
.upgrade/accepted-differences.json.

Standard library only. `parity.py` beside this file holds the comparison.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import parity  # noqa: E402


def load(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def main():
    out = os.path.join(HERE, "out")
    base = os.path.join(HERE, "baseline")
    problems, lines = [], ["## Upgrade parity", ""]
    before = load(os.path.join(base, "examples.json"), {})
    rspec = load(os.path.join(out, "rspec.json"))
    if rspec is None:
        problems.append("the test run left no results file")
        after = {}
    else:
        after = {e["id"]: e["status"] for e in rspec.get("examples", [])}
    # Examples whose status differed between the sandbox and CI on the baseline
    # commit itself (same code, different environment) are reported, not gated.
    env_dep = load(os.path.join(base, "environment-dependent.json"), {})
    gated_before = {k: v for k, v in before.items() if k not in env_dep}
    gated_after = {k: v for k, v in after.items() if k not in env_dep}
    cmp_ = parity.compare_examples(gated_before, gated_after)
    lines += ["| Check | Baseline | This commit |", "|---|---|---|",
              "| Examples run | %d | %d |" % (cmp_["before_total"], cmp_["after_total"]),
              "| Examples passing | %d | %d |" % (cmp_["before_passed"], cmp_["after_passed"]),
              "| Passing at baseline, failing or missing now | | %d |" % (len(cmp_["regressed"]) + len(cmp_["missing_passing"])),
              "| Failing at baseline, passing now | | %d |" % len(cmp_["fixed"]),
              "| New examples (failing) | | %d (%d) |" % (cmp_["added"], len(cmp_["added_failing"])),
              "| Environment-dependent examples, not gated (passing here) | %d | %d |" % (
                  len(env_dep), sum(1 for k in env_dep if after.get(k) == "passed"))]
    if not cmp_["ok"]:
        problems.append("test parity: %d regressed, %d passing examples missing, %d new examples failing"
                        % (len(cmp_["regressed"]), len(cmp_["missing_passing"]), len(cmp_["added_failing"])))
    text = ""
    for name in ("test-output.txt",):
        p = os.path.join(out, name)
        if os.path.exists(p):
            with open(p, errors="replace") as f:
                text = f.read()
    dep = re.findall(r"DEPRECATION WARNING: (.*)", text)
    distinct = {re.sub(r"\s*\(called from .*$", "", d)[:300] for d in dep}
    meta = load(os.path.join(base, "meta.json"), {})
    lines.append("| Rails deprecation warnings (distinct / occurrences) | %s / %s | %d / %d |" % (
        meta.get("deprecations_distinct", "?"), meta.get("deprecations_occurrences", "?"), len(distinct), len(dep)))
    b_rec = load(os.path.join(base, "parity.json"))
    if b_rec is not None:
        a_rec = load(os.path.join(out, "parity.json"))
        if a_rec is None:
            problems.append("the behavior recording did not complete")
        else:
            mask = load(os.path.join(base, "parity-noise-mask.json"), {})
            accepted = load(os.path.join(HERE, "accepted-differences.json"), [])
            diff = parity.compare(b_rec, a_rec, mask)
            unexplained = []
            for d in diff["differences"]:
                for fld in [c["field"] for c in d.get("changes", [])] or [d.get("kind")]:
                    if not any(e.get("name") in (d["name"], "*") and e.get("field") in (fld, "*") and e.get("reason")
                               for e in accepted):
                        unexplained.append("%s: %s" % (d["name"], fld))
            lines.append("| Recorded HTTP behaviors identical | %d | %d |" % (diff["requests_before"], diff["identical"]))
            lines.append("| Differences with a declared reason / without | | %d / %d |" % (
                sum(len(d.get("changes", [])) or 1 for d in diff["differences"]) - len(unexplained), len(unexplained)))
            with open(os.path.join(out, "parity-diff.json"), "w") as f:
                json.dump(diff, f, indent=1)
            if unexplained:
                problems.append("behavior parity: %d difference(s) with no declared reason: %s"
                                % (len(unexplained), "; ".join(unexplained[:8])))
            rw = a_rec.get("recorded_with") or {}
            lines += ["", "Recorded on Rails %s, Ruby %s." % (rw.get("rails"), rw.get("ruby"))]
    lines += ["", "**Result:** " + ("parity holds." if not problems else "parity does not hold.")]
    for p in problems:
        lines.append("- " + p)
    for k in ("regressed", "missing_passing", "added_failing"):
        for x in cmp_[k][:30]:
            lines.append("- %s: `%s`" % (k, x))
    summary = "\n".join(lines) + "\n"
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(summary)
    with open(os.path.join(out, "summary.md"), "w") as f:
        f.write(summary)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

"""Compare two behavior recordings.

A recording is a list of named interactions, each with a status, headers and
a body (an HTTP exchange) or an exit code and output (a CLI call). Recording
the same version twice shows which fields move without any change; those
are masked before the before/after comparison, and the mask is reported.
"""
import difflib
import hashlib
import re

NORMALIZERS = [
    (re.compile(r'(name="authenticity_token"[^>]*value=")[^"]+'), r"\1<token>"),
    (re.compile(r'(name="csrf-token" content=")[^"]+'), r"\1<token>"),
    (re.compile(r'(nonce=")[^"]+'), r"\1<nonce>"),
    (re.compile(r"-[0-9a-f]{8,64}(\.(?:js|css|png|svg|jpg|woff2?|ico|map))"), r"-<digest>\1"),
    (re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"), "<uuid>"),
]


def normalize(body):
    for rx, repl in NORMALIZERS:
        body = rx.sub(repl, body or "")
    return body


def _index(rec):
    return {r["name"]: r for r in rec.get("requests", [])}


def noise_mask(a1, a2):
    """Fields that differ between two recordings of the same code."""
    mask = {}
    i1, i2 = _index(a1), _index(a2)
    for name, r1 in i1.items():
        r2 = i2.get(name)
        if not r2:
            continue
        m = {"headers": [], "body": False, "status": False}
        if r1.get("status") != r2.get("status") or r1.get("error") != r2.get("error"):
            m["status"] = True
        h1, h2 = r1.get("headers") or {}, r2.get("headers") or {}
        m["headers"] = sorted(k for k in set(h1) | set(h2) if h1.get(k) != h2.get(k))
        if normalize(r1.get("body")) != normalize(r2.get("body")):
            m["body"] = True
        if m["headers"] or m["body"] or m["status"]:
            mask[name] = m
    return mask


def compare(before, after, mask=None, max_diff_lines=40):
    mask = mask or {}
    ib, ia = _index(before), _index(after)
    diffs, same = [], 0
    for name in sorted(set(ib) | set(ia)):
        b, a = ib.get(name), ia.get(name)
        if b is None or a is None:
            diffs.append({"name": name, "kind": "missing-in-" + ("before" if b is None else "after")})
            continue
        m = mask.get(name, {})
        d = {"name": name, "changes": []}
        if not m.get("status"):
            if b.get("status") != a.get("status"):
                d["changes"].append({"field": "status", "before": b.get("status"), "after": a.get("status")})
            if (b.get("error") or {}).get("class") != (a.get("error") or {}).get("class"):
                d["changes"].append({"field": "error", "before": b.get("error"), "after": a.get("error")})
        hb, ha = b.get("headers") or {}, a.get("headers") or {}
        for k in sorted(set(hb) | set(ha)):
            if k in m.get("headers", []):
                continue
            if hb.get(k) != ha.get(k):
                d["changes"].append({"field": "header:" + k, "before": hb.get(k), "after": ha.get(k)})
        if b.get("cookie_names") != a.get("cookie_names"):
            d["changes"].append({"field": "cookie_names", "before": b.get("cookie_names"),
                                 "after": a.get("cookie_names")})
        if not m.get("body"):
            nb, na = normalize(b.get("body")), normalize(a.get("body"))
            if nb != na:
                ud = list(difflib.unified_diff(nb.split("\n"), na.split("\n"), "before", "after",
                                               lineterm="", n=1))
                d["changes"].append({"field": "body", "diff": ud[:max_diff_lines],
                                     "diff_lines_total": len(ud)})
        if d["changes"]:
            diffs.append(d)
        else:
            same += 1
    statuses = {}
    for r in ib.values():
        k = str(r.get("status") or (r.get("error") or {}).get("class"))
        statuses[k] = statuses.get(k, 0) + 1
    return {"requests_before": len(ib), "requests_after": len(ia), "identical": same,
            "different": len(diffs), "masked_as_noise": len(mask), "noise_mask": mask,
            "before_status_counts": statuses, "differences": diffs}


def compare_examples(before, after):
    """The test half of 'same behavior'."""
    regressed = sorted(k for k, v in before.items() if v == "passed" and after.get(k) not in ("passed",)
                       and k in after)
    missing = sorted(k for k, v in before.items() if k not in after)
    missing_passing = [k for k in missing if before[k] == "passed"]
    fixed = sorted(k for k, v in before.items() if v == "failed" and after.get(k) == "passed")
    added = sorted(k for k in after if k not in before)
    added_failing = [k for k in added if after[k] == "failed"]
    return {"before_total": len(before), "after_total": len(after),
            "before_passed": sum(1 for v in before.values() if v == "passed"),
            "after_passed": sum(1 for v in after.values() if v == "passed"),
            "regressed": regressed, "missing": missing, "missing_passing": missing_passing,
            "fixed": fixed, "added": len(added), "added_failing": added_failing,
            "ok": not regressed and not missing_passing and not added_failing}


def digest(rec):
    h = hashlib.sha256()
    for r in rec.get("requests", []):
        h.update(repr((r["name"], r.get("status"), sorted((r.get("headers") or {}).items()),
                       normalize(r.get("body")))).encode())
    return h.hexdigest()[:16]

#!/usr/bin/env python3
"""並列で流したテスト（tests/run_tests.gd --shard=i/n --timing-out=...）の結果をまとめる。

    python3 tools/test_shards.py summary build/test-shards/*/result.json
        組ごとの結果を合わせ、直列と同じ形の「X passed, Y failed」を出す。失敗したテストと、
        遅いファイル・テストの上位 20 件も出す。どのテストファイルもちょうど 1 つの組で流れたかも確かめる
        （組の分け方の不具合でテストが抜けたり二重に流れたりしたら失敗）。失敗が 1 件でもあれば終了コード 1。
    python3 tools/test_shards.py summary --write-timings build/test-shards/*/result.json
        上に加えて、ファイルごとの実測を tests/test_timings.json に書く（組の分け方に使う。全件を流したときだけ）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMINGS = ROOT / "tests" / "test_timings.json"
TEST_DIRS = ("tests/unit", "tests/integration")
TOP = 20


def discover() -> list[str]:
    """run_tests.gd と同じ規則で、テストファイルを tests/... の相対パスで返す。"""
    found: list[str] = []
    for d in TEST_DIRS:
        found.extend(f"{d}/{p.name}" for p in (ROOT / d).glob("test_*.gd"))
    return sorted(found)


def load(paths: list[Path]) -> list[dict]:
    results = []
    for p in paths:
        try:
            results.append(json.loads(p.read_text(encoding="utf-8")))
        except (OSError, ValueError) as e:
            print(f"cannot read shard result {p}: {e}", file=sys.stderr)
            results.append(None)
    return results


def top(durations: dict[str, int]) -> list[tuple[int, str]]:
    return sorted(((int(ms), name) for name, ms in durations.items()), key=lambda e: (-e[0], e[1]))[:TOP]


def summary(paths: list[Path], write_timings: bool) -> int:
    results = load(paths)
    ok = True
    passed = failed = 0
    files: dict[str, int] = {}
    tests: dict[str, int] = {}
    failed_tests: list[str] = []
    seen: dict[str, int] = {}
    for p, r in zip(paths, results):
        if r is None:
            ok = False
            continue
        passed += int(r["passed"])
        failed += int(r["failed"])
        failed_tests.extend(r.get("failed_tests", []))
        for name, ms in r.get("files", {}).items():
            seen[name] = seen.get(name, 0) + 1
            files[name] = int(ms)
        tests.update({k: int(v) for k, v in r.get("tests", {}).items()})
        print(f"  {p.parent.name}: {r['passed']} passed, {r['failed']} failed ({int(r['elapsed_ms']) / 1000:.1f} s)")

    expected = discover()
    missing = [f for f in expected if f not in seen and not any(f in t for t in failed_tests)]
    twice = sorted(f for f, n in seen.items() if n > 1)
    if missing or twice:
        ok = False
        for f in missing:
            print(f"NOT RUN in any shard: {f}", file=sys.stderr)
        for f in twice:
            print(f"RUN TWICE: {f}", file=sys.stderr)

    if files:
        print("\nslowest files:")
        for ms, name in top(files):
            print(f"  {ms:7d} ms  {name}")
        print("slowest tests:")
        for ms, name in top(tests):
            print(f"  {ms:7d} ms  {name}")

    if failed_tests:
        print("\nfailed tests (details in build/logs/test_shard_*.log):", file=sys.stderr)
        for name in failed_tests:
            print(f"  FAIL {name}", file=sys.stderr)

    if write_timings:
        if not ok or set(files) != set(expected):
            print("not writing timings: the run did not cover every test file", file=sys.stderr)
        else:
            data = {
                "comment": "tests/run_tests.gd --shard の分け方に使う実測（ms）。tools/test_shards.py --write-timings で更新する",
                "files": dict(sorted(files.items())),
            }
            TIMINGS.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            print(f"wrote {TIMINGS.relative_to(ROOT)}")

    print(f"\n{passed} passed, {failed} failed")
    return 0 if ok and failed == 0 and passed > 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    s = sub.add_parser("summary")
    s.add_argument("--write-timings", action="store_true")
    s.add_argument("results", nargs="+", type=Path)
    args = parser.parse_args()
    return summary(args.results, args.write_timings)


if __name__ == "__main__":
    sys.exit(main())

"""Validate that api.json5 matches the ORM wrapper surface."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import json5

ROOT = Path(__file__).resolve().parents[1]
API_JSON = ROOT / "api.json5"
PDB_SYMBOL_RE = re.compile(r"\bpdb\.[A-Za-z_][A-Za-z0-9_]*\b")


def load_json(path: Path) -> object:
    try:
        return json5.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise FileNotFoundError(f"{path} not found") from exc
    except ValueError as exc:
        raise ValueError(f"invalid JSON5 in {path}: {exc}") from exc


def source_paths() -> list[Path]:
    paths: list[Path] = []
    for directory in ("lib", "spec"):
        paths.extend(ROOT.glob(f"{directory}/**/*.rb"))
    return sorted(paths)


def read_source(paths: list[Path]) -> str:
    try:
        return "\n".join(path.read_text(encoding="utf-8") for path in paths)
    except OSError as exc:
        raise OSError(f"failed to read {exc.filename}: {exc.strerror}") from exc


def _quoted(name: str) -> str:
    return rf"""['"]{re.escape(name)}['"]"""


def main() -> int:
    try:
        api = load_json(API_JSON)
    except (FileNotFoundError, ValueError) as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1

    if not isinstance(api, dict):
        print("❌ api.json5 must contain a JSON object.", file=sys.stderr)
        return 1

    try:
        operators = api["operators"]
        functions = api["functions"]
        types = api["types"]
    except KeyError as exc:
        print(f"❌ api.json5 missing required section: {exc}", file=sys.stderr)
        return 1

    if not all(isinstance(section, dict) for section in (operators, functions, types)):
        print(
            "❌ api.json5 sections operators/functions/types must all be objects.",
            file=sys.stderr,
        )
        return 1

    expected_operator_symbols = {str(value) for value in operators.values()}
    expected_pdb_symbols = {
        *(str(value) for value in functions.values()),
        *(str(value) for value in types.values()),
    }

    referenced_pdb_symbols: set[str] = set()
    referenced_operator_symbols: set[str] = set()

    try:
        paths = source_paths()
        source = read_source(paths)
    except OSError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1

    observed_pdb_symbols = set(PDB_SYMBOL_RE.findall(source))
    referenced_pdb_symbols = {
        symbol for symbol in expected_pdb_symbols if symbol in observed_pdb_symbols
    }
    referenced_operator_symbols = {
        symbol
        for symbol in expected_operator_symbols
        if re.search(_quoted(symbol), source)
    }

    missing_pdb_symbols = sorted(expected_pdb_symbols - referenced_pdb_symbols)
    missing_operator_symbols = sorted(
        expected_operator_symbols - referenced_operator_symbols
    )

    issues: list[str] = []
    if missing_pdb_symbols:
        issues.append(
            "api.json5 pdb.* symbols not referenced by the codebase: "
            + ", ".join(missing_pdb_symbols)
        )
    if missing_operator_symbols:
        issues.append(
            "api.json5 operators not referenced by ORM wrappers: "
            + ", ".join(missing_operator_symbols)
        )

    if issues:
        print("❌ API coverage check failed:", file=sys.stderr)
        for issue in issues:
            print(f"   - {issue}", file=sys.stderr)
        print(
            "\nUpdate api.json5 or the codebase so they stay in sync.",
            file=sys.stderr,
        )
        return 1

    print("✅ API coverage check passed.")
    covered_total = len(expected_pdb_symbols & referenced_pdb_symbols) + len(
        expected_operator_symbols & referenced_operator_symbols
    )
    expected_total = len(expected_pdb_symbols) + len(expected_operator_symbols)
    print(f"   api symbols referenced: {covered_total}/{expected_total}")
    print(
        f"   source files: {len(paths)}, concrete API references checked: "
        f"{len(referenced_pdb_symbols) + len(referenced_operator_symbols)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

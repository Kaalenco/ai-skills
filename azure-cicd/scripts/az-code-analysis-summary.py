#!/usr/bin/env python3
"""
Writes a Code Analysis section to the Azure DevOps pipeline summary.

Reads:
  - Cobertura coverage XML produced by coverlet (XPlat Code Coverage)
  - Cyclomatic complexity data from lizard (--csv output)

Outputs a markdown summary to PIPELINE_SUMMARY_FILE (Azure DevOps) or
GITHUB_STEP_SUMMARY (GitHub Actions) when set, otherwise to stdout.

Azure DevOps usage (in a bash step):
  SUMMARY="$(Agent.TempDirectory)/summary.md"
  PIPELINE_SUMMARY_FILE="$SUMMARY" python3 scripts/az-code-analysis-summary.py \\
    --source src/MyProject \\
    --coverage-dir $(COVERAGE_DIR)
  echo "##vso[task.uploadsummary]$SUMMARY"

Usage:
  python3 scripts/az-code-analysis-summary.py [--source <path>] [--coverage-dir <path>]
"""

import argparse
import csv
import glob
import io
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

CCN_THRESHOLD = 10


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source",       default="src",                     help="Source root to analyse (may contain multiple projects)")
    parser.add_argument("--exclude",      default="*.UnitTests",             help="Lizard -x pattern for directories to exclude from complexity analysis")
    parser.add_argument("--coverage-dir", default="src/TestResults/Coverage", help="Root directory containing coverage.cobertura.xml files")
    return parser.parse_args()


def read_coverage(coverage_dir: str) -> tuple[str, str]:
    files = glob.glob(f"{coverage_dir}/**/coverage.cobertura.xml", recursive=True)
    if not files:
        return "N/A", "N/A"
    lines_covered = lines_valid = branches_covered = branches_valid = 0
    for f in files:
        root = ET.parse(f).getroot()
        lines_covered     += int(root.get("lines-covered",     0))
        lines_valid       += int(root.get("lines-valid",       0))
        branches_covered  += int(root.get("branches-covered",  0))
        branches_valid    += int(root.get("branches-valid",    0))
    line_rate   = f"{lines_covered   / lines_valid   * 100:.1f}%" if lines_valid   else "N/A"
    branch_rate = f"{branches_covered / branches_valid * 100:.1f}%" if branches_valid else "N/A"
    return line_rate, branch_rate


def read_complexity(source_dir: str, exclude: str | None = None) -> tuple[list, int, float, float]:
    cmd = [sys.executable, "-m", "lizard", source_dir, "--csv"]
    if exclude:
        cmd += ["-x", exclude]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 and not result.stdout:
        print(f"lizard failed: {result.stderr}", file=sys.stderr)
        return [], 0, 0.0, 0.0

    all_fns = []
    for row in csv.reader(io.StringIO(result.stdout)):
        if len(row) < 7:
            continue
        try:
            all_fns.append((
                int(row[0]),            # nloc
                int(row[1]),            # ccn
                int(row[3]),            # param count
                row[5].split("@")[0],   # Class::Method
                row[6].replace(f"{source_dir}/", ""),
            ))
        except (ValueError, IndexError):
            continue

    total_nloc = sum(r[0] for r in all_fns)
    total_fns  = len(all_fns)
    avg_ccn    = sum(r[1] for r in all_fns) / total_fns if total_fns else 0.0
    avg_nloc   = total_nloc / total_fns if total_fns else 0.0
    return all_fns, total_nloc, avg_ccn, avg_nloc


def write_summary(out, line_rate: str, branch_rate: str, all_fns: list, total_nloc: int, avg_ccn: float, avg_nloc: float) -> None:
    total_fns = len(all_fns)
    warnings  = [r for r in all_fns if r[1] > CCN_THRESHOLD]

    out.write("## Code Analysis\n\n")

    out.write("### Test Coverage (net8.0)\n\n")
    out.write("| Metric | Value |\n|---|---|\n")
    out.write(f"| Line Coverage   | {line_rate} |\n")
    out.write(f"| Branch Coverage | {branch_rate} |\n\n")

    out.write("### Code Complexity\n\n")
    out.write(f"| Total Code Lines | Functions | Avg. Lines / Function | Avg. CCN | Above CCN {CCN_THRESHOLD} |\n")
    out.write("|---:|---:|---:|---:|---:|\n")
    out.write(f"| {total_nloc:,} | {total_fns} | {avg_nloc:.1f} | {avg_ccn:.1f} | {len(warnings)} |\n\n")

    if warnings:
        out.write(f"#### Functions exceeding CCN {CCN_THRESHOLD}\n\n")
        out.write("| Method | File | Code Lines | CCN | Parameters |\n")
        out.write("|---|---|---:|---:|---:|\n")
        for nloc, ccn, params, method, file in sorted(warnings, key=lambda x: -x[1]):
            out.write(f"| `{method}` | `{file}` | {nloc} | **{ccn}** | {params} |\n")
        out.write("\n")
    else:
        out.write(f"_All {total_fns} functions are within the complexity threshold (CCN <= {CCN_THRESHOLD})._\n\n")

    out.write("> Full HTML reports are in the **code-analysis** artifact.\n")


def main() -> None:
    args = parse_args()

    line_rate, branch_rate = read_coverage(args.coverage_dir)
    all_fns, total_nloc, avg_ccn, avg_nloc = read_complexity(args.source, args.exclude)

    # PIPELINE_SUMMARY_FILE is the Azure DevOps convention used in this pattern.
    # GITHUB_STEP_SUMMARY is supported as a fallback for GitHub Actions compatibility.
    summary_path = os.environ.get("PIPELINE_SUMMARY_FILE") or os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            write_summary(f, line_rate, branch_rate, all_fns, total_nloc, avg_ccn, avg_nloc)
    else:
        write_summary(sys.stdout, line_rate, branch_rate, all_fns, total_nloc, avg_ccn, avg_nloc)


if __name__ == "__main__":
    main()

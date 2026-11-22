#!/bin/bash
# ==============================================================================
# Script: build_report.sh
# Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
# Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
# Description: Rebuilds the final two-column IEEE report from its sources.
#   1. scripts/make_report_numbers.py  -> docs/report/numbers.tex   (all numbers)
#   2. scripts/make_report_figures.py  -> docs/report/figures/*     (all figures)
#   3. tectonic compiles TensoraX_Final_Report.tex (IEEEtran, conference option)
#   4. the PDF is copied to docs/TensoraX_Final_Report.pdf
# Usage (repo root): ./docs/report/build_report.sh
# Requires: python3 + matplotlib, tectonic (downloads IEEEtran.cls on first use)
# ==============================================================================
set -e
cd "$(dirname "$0")/../.."
python3 scripts/make_report_numbers.py
python3 scripts/make_report_figures.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
(cd docs/report && tectonic -X compile --outdir "$TMP" TensoraX_Final_Report.tex)
cp "$TMP/TensoraX_Final_Report.pdf" docs/TensoraX_Final_Report.pdf
echo "wrote docs/TensoraX_Final_Report.pdf"

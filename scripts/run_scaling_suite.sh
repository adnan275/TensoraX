#!/bin/bash

set -e

if ! command -v python3 &> /dev/null; then
    echo "[ERROR] python3 not found in system PATH."
    exit 1
fi

echo "=========================================================="
echo " [TensoraX] Running Architectural Scaling Evaluation      "
echo " Lead Microarchitect: Adnan Rizvi                         "
echo "=========================================================="

python3 scripts/scaling_analysis.py
python3 scripts/roofline_model.py

echo "=========================================================="
echo " [TensoraX] Scaling & Roofline Analysis Completed!        "
echo "=========================================================="

#!/usr/bin/env bash
# Stage-A1 QC pipeline (FastQC + MultiQC) for one BioProject. Runs on VM.
# Usage: run_qc.sh <BIOPROJECT>   e.g. run_qc.sh PRJNA900592
set -euo pipefail
shopt -s nullglob

BP="${1:?usage: run_qc.sh <BIOPROJECT>}"
WORK="$HOME/qc_work/$BP"
RAW="$WORK/raw"
FQ_OUT="$WORK/fastqc_out"
MQ_OUT="$WORK/multiqc_out"
GCS_DATA="gs://bioinformatics4/bioproject/$BP"
GCS_RESULTS="gs://bioinformatics4/results/qc/$BP"

echo "[$(date)] === QC start: $BP ==="
mkdir -p "$RAW" "$FQ_OUT" "$MQ_OUT"

# 1. Pull FASTQs from GCS (gs:// glob must be passed LITERALLY to gcloud)
local_files=("$RAW"/*.fastq.gz)
if [ "${#local_files[@]}" -lt 2 ]; then
  echo "[$(date)] copying FASTQs from GCS ..."
  gcloud storage cp "$GCS_DATA/*.fastq.gz" "$RAW/"
fi
local_files=("$RAW"/*.fastq.gz)
echo "[$(date)] local FASTQs: ${#local_files[@]}"

# 2. FastQC on every FASTQ (8 threads)
echo "[$(date)] running FastQC ..."
fastqc -t 8 -q "$RAW"/*.fastq.gz -o "$FQ_OUT"
echo "[$(date)] FastQC done: $(ls "$FQ_OUT"/*_fastqc.zip | wc -l) reports"

# 3. MultiQC aggregation (module form: multiqc not on PATH)
echo "[$(date)] running MultiQC ..."
python3 -m multiqc "$FQ_OUT" -o "$MQ_OUT" -n "${BP}_multiqc" -f
echo "[$(date)] MultiQC done: $(ls "$MQ_OUT"/${BP}_multiqc.html)"

# 4. Stage results to GCS for download to local results/
echo "[$(date)] uploading results to $GCS_RESULTS ..."
gcloud storage cp -r "$FQ_OUT"/*_fastqc.html "$FQ_OUT"/*_fastqc.zip "$GCS_RESULTS/fastqc/"
gcloud storage cp -r "$MQ_OUT"/* "$GCS_RESULTS/multiqc/"

echo "[$(date)] === QC COMPLETE: $BP ==="
echo "results staged at: $GCS_RESULTS"

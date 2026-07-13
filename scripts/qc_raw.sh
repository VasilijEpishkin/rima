#!/usr/bin/env bash
# qc_raw.sh — FastQC + MultiQC на сырые FASTQ (этап A1).
#
# Запуск:
#   qc_raw.sh <DATASET> [<SRC_DIR>]
#
#   <DATASET>  — имя датасета (PRJEB40348, PRJNA848968, ...)
#   <SRC_DIR>  — путь к сырым FASTQ (по умолчанию глядит в gs://bioinformatics4/bioproject/<DS>)
#
# Результаты:    results/<DS>/qc_raw/{fastqc, multiqc}/
#
# Для запуска с локальной папки:
#   qc_raw.sh PRJEB40348 /path/to/raw/fastqs
#
# Для запуска из GCS (требуется gcloud auth):
#   qc_raw.sh PRJEB40348
#
set -euo pipefail
shopt -s nullglob

DS="${1:?usage: qc_raw.sh <DATASET> [<SRC_DIR>]}"
SRC="${2:-gs://bioinformatics4/bioproject/$DS}"

BASE=results/$DS/qc_raw
FQ_OUT=$BASE/fastqc
MQ_OUT=$BASE/multiqc
LOCALDATA=$BASE/raw

echo "=== [$(date -u)] qc_raw: $DS ==="
mkdir -p "$FQ_OUT" "$MQ_OUT"

# --- 0. Получить сырые FASTQ ---
if [[ "$SRC" == gs://* ]]; then
    echo "[$DS] fetching from GCS: $SRC"
    mkdir -p "$LOCALDATA"
    gcloud storage cp "${SRC}*.fastq.gz" "$LOCALDATA/" 2>&1 || {
        echo "[$DS] GCS copy FAILED"; exit 1; }
    SRC_DIR="$LOCALDATA"
elif [ -d "$SRC" ]; then
    SRC_DIR="$SRC"
    echo "[$DS] using local data: $SRC_DIR"
else
    echo "[$DS] ERROR: $SRC neither GCS path nor local directory"
    exit 1
fi

# --- 1. FastQC ---
echo "[$DS] FastQC ..."
N=$(ls "$SRC_DIR"/*.fastq.gz 2>/dev/null | wc -l)
[ "$N" -gt 0 ] || { echo "[$DS] no FASTQ files found"; exit 1; }
fastqc -t 8 -q "$SRC_DIR"/*.fastq.gz -o "$FQ_OUT" 2>&1
echo "[$DS] FastQC done: $(ls "$FQ_OUT"/*_fastqc.html 2>/dev/null | wc -l) reports"

# --- 2. MultiQC ---
echo "[$DS] MultiQC ..."
python3 -m multiqc "$FQ_OUT" -o "$MQ_OUT" -n "${DS}_multiqc" -f 2>&1
echo "[$DS] MultiQC done: $(ls "$MQ_OUT"/*.html 2>/dev/null)"

# --- 3. Убрать сырые (оставляем только QC-отчёты) ---
rm -rf "$LOCALDATA"

echo "=== [$(date -u)] qc_raw: $DS COMPLETE ==="
echo "  FastQC:  $FQ_OUT/"
echo "  MultiQC: $MQ_OUT/"

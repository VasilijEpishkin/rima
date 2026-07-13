#!/usr/bin/env bash
# adapter_trim.sh — cutadapt (Illumina адаптер) + fastp (Q30, minlen).
#
# Только адаптер-тримминг и фильтрация. FastQC/MultiQC — отдельный шаг (qc_raw.sh).
#
# Pipeline: cutadapt (TruSeq/Nextera адаптер по всей длине рида)
#           → fastp (авто-детект остатков, Q30, minlen 250, 8 потоков)
#
# Запуск:
#   adapter_trim.sh <DATASET> [<SRC_DIR>]
#
#   <DATASET>  — имя датасета (PRJEB40348, PRJNA848968, ...)
#   <SRC_DIR>  — путь к сырым FASTQ (по умолчанию GCS)
#
# Результаты:    results/<DS>/trimmed/{fastq, fastp_reports}/
#
# Зависимости: cutadapt, fastp
set -euo pipefail
shopt -s nullglob

export PATH="$HOME/.local/bin:$PATH"

DS="${1:?usage: adapter_trim.sh <DATASET> [<SRC_DIR>]}"
SRC="${2:-gs://bioinformatics4/bioproject/$DS}"

ILL_ADAPTER=AGATCGGAAGAGCGGTTCAG    # полный Illumina TruSeq/Nextera адаптер
BASE=results/$DS/trimmed
CUT=$BASE/cutadapt                   # cutadapt output (intermediate, удаляется)
TRIM=$BASE/fastq                     # fastp output (финальные trimmed)
FPR=$BASE/fastp_reports              # fastp JSON/HTML отчёты
LOCALDATA=$BASE/raw_work             # сырые (если из GCS)

echo "=== [$(date -u)] adapter_trim: $DS ==="
mkdir -p "$CUT" "$TRIM" "$FPR"

# --- 0. Получить сырые FASTQ ---
if [[ "$SRC" == gs://* ]]; then
    echo "[$DS] fetching from GCS: $SRC"
    mkdir -p "$LOCALDATA"
    gcloud storage cp "${SRC}*.fastq.gz" "$LOCALDATA/" 2>&1 || {
        echo "[$DS] GCS copy FAILED"; exit 1; }
    echo "[$DS] downloaded $(ls "$LOCALDATA"/*.fastq.gz | wc -l) files"
    SRC_DIR="$LOCALDATA"
elif [ -d "$SRC" ]; then
    SRC_DIR="$SRC"
    echo "[$DS] using local data: $SRC_DIR"
else
    echo "[$DS] ERROR: $SRC neither GCS path nor local directory"
    exit 1
fi

# --- 1. Построить список пар ---
PAIRS=$(cd "$SRC_DIR" && ls *.fastq.gz 2>/dev/null | sed -E 's/_[12]\.fastq\.gz$//' | sort -u)
NPAIR=$(echo "$PAIRS" | grep -c . 2>/dev/null || echo 0)
echo "[$DS] found $NPAIR pairs"
[ "$NPAIR" -gt 0 ] || { echo "[$DS] no pairs found, abort"; exit 1; }

# --- 2. cutadapt (адаптер) → fastp (QC + фильтр) ---
for base in $PAIRS; do
    r1="$SRC_DIR/${base}_1.fastq.gz"
    r2="$SRC_DIR/${base}_2.fastq.gz"
    [ -f "$r1" ] && [ -f "$r2" ] || { echo "  WARN: missing $base, skip"; continue; }

    # Пропустить, если уже есть результат
    [ -f "$TRIM/${base}_1.trim.fastq.gz" ] && { echo "  $base already done, skip"; continue; }

    # --- cutadapt: точное удаление Illumina адаптера ---
    echo "  [$base] cutadapt ..."
    cutadapt -a "$ILL_ADAPTER" -A "$ILL_ADAPTER" \
        --compression-level 1 \
        -o "$CUT/${base}_1.cut.fastq.gz" \
        -p "$CUT/${base}_2.cut.fastq.gz" \
        "$r1" "$r2" 2>> "$FPR/${base}.cutadapt.log"

    # --- fastp: авто-детект остатков + Q30 + minlen 250 ---
    echo "  [$base] fastp ..."
    fastp -i "$CUT/${base}_1.cut.fastq.gz" \
        -I "$CUT/${base}_2.cut.fastq.gz" \
        -o "$TRIM/${base}_1.trim.fastq.gz" \
        -O "$TRIM/${base}_2.trim.fastq.gz" \
        --detect_adapter_for_pe -q 30 -l 250 -w 8 \
        -h "$FPR/${base}.html" -j "$FPR/${base}.json" \
        2>> "$FPR/${base}.fastp.log"

    # чистим intermediate cutadapt
    rm -f "$CUT/${base}_1.cut.fastq.gz" "$CUT/${base}_2.cut.fastq.gz"
done
echo "[$DS] cutadapt + fastp done"

# убрать временные
rmdir "$CUT" 2>/dev/null || true
rm -rf "$LOCALDATA"

echo "=== [$(date -u)] adapter_trim: $DS COMPLETE ==="
echo "  trimmed:    $TRIM/"
echo "  fastp QC:   $FPR/"

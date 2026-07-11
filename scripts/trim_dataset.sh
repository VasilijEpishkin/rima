#!/usr/bin/env bash
# trim_dataset.sh — Adapter trimming + QC for one dataset.
#
# Pipeline: cutadapt (Illumina TruSeq/Nextera) → fastp (auto-detect, Q30, len250)
#            → FastQC → MultiQC
# Результаты: results/<DS>/trimmed/{fastp_reports,fastqc,multiqc}
#
# cutadapt ПЕРВЫМ — ищет полную последовательность Illumina адаптера
# (AGATCGGAAGAGCGGTTCAG) по всей длине рида, независимо от PE-оверлапа.
# fastp потом дочищает остатки через PE-overlap + делает QC.
#
# Запуск:
#   trim_dataset.sh <DATASET>              # сырые из gs://bioinformatics4/bioproject/<DS>/
#   trim_dataset.sh <DATASET> <SRC_DIR>    # сырые из локальной папки
#
# Пример:
#   trim_dataset.sh PRJEB40348
#   trim_dataset.sh PRJEB40348 /path/to/raw/fastqs
#
# Зависимости: cutadapt, fastp, fastqc, multiqc (python3 -m multiqc), gsutil (для GCS)
set -euo pipefail
shopt -s nullglob

export PATH="$HOME/.local/bin:$PATH"   # cutadapt живёт тут

DS="${1:?usage: trim_dataset.sh <DATASET> [<SRC_DIR>]}"
SRC="${2:-gs://bioinformatics4/bioproject/$DS}"

# --- пути ---
ILL_ADAPTER=AGATCGGAAGAGCGGTTCAG       # полный Illumina TruSeq/Nextera адаптер
BASE=~/results/qc_trim_pipeline/$DS    # рабочий каталог
CUT=$BASE/cutadapt                     # cutadapt output (intermediate)
TRIM=$BASE/trim                        # fastp output (final)
FPR=$BASE/fastp_reports                # fastp JSON/HTML отчёты
FQC=$BASE/qc_trimmed                   # FastQC на trimmed
MQC=$BASE/multiqc                      # MultiQC на trimmed
LOG=$BASE/trim_dataset.log

echo "=== [$(date -u)] trim_dataset: $DS ===" | tee "$LOG"
mkdir -p "$CUT" "$TRIM" "$FPR" "$FQC" "$MQC"

# --- 0. Получить сырые FASTQ ---
LOCALDATA=$BASE/raw
if [[ "$SRC" == gs://* ]]; then
  echo "[$DS] fetching from GCS: $SRC" | tee -a "$LOG"
  mkdir -p "$LOCALDATA"
  gsutil -m cp "${SRC}*.fastq.gz" "$LOCALDATA/" >> "$LOG" 2>&1 || {
    echo "[$DS] GCS copy FAILED" | tee -a "$LOG"; exit 1; }
  echo "[$DS] downloaded $(ls "$LOCALDATA"/*.fastq.gz | wc -l) files" | tee -a "$LOG"
elif [ -d "$SRC" ]; then
  LOCALDATA="$SRC"
  echo "[$DS] using local data: $LOCALDATA" | tee -a "$LOG"
else
  echo "[$DS] ERROR: $SRC neither GCS path nor local directory" | tee -a "$LOG"
  exit 1
fi

# --- 1. Построить список пар ---
PAIRS=$(cd "$LOCALDATA" && ls *.fastq.gz 2>/dev/null | sed -E 's/_[12]\.fastq\.gz$//' | sort -u)
NPAIR=$(echo "$PAIRS" | grep -c . 2>/dev/null || echo 0)
echo "[$DS] found $NPAIR pairs" | tee -a "$LOG"
[ "$NPAIR" -gt 0 ] || { echo "[$DS] no pairs found, abort" | tee -a "$LOG"; exit 1; }

# --- 2. cutadapt (адаптер) → fastp (QC + фильтр) ---
for base in $PAIRS; do
  r1="$LOCALDATA/${base}_1.fastq.gz"
  r2="$LOCALDATA/${base}_2.fastq.gz"
  [ -f "$r1" ] && [ -f "$r2" ] || { echo "[$DS] WARN: missing $base" | tee -a "$LOG"; continue; }

  # Пропустить, если уже есть результат
  [ -f "$TRIM/${base}_1.trim.fastq.gz" ] && {
    echo "  $base already done, skip" | tee -a "$LOG"; continue; }

  # --- cutadapt: точное удаление Illumina адаптера ---
  echo "  [$base] cutadapt ..." | tee -a "$LOG"
  cutadapt -a "$ILL_ADAPTER" -A "$ILL_ADAPTER" \
    --compression-level 1 \
    -o "$CUT/${base}_1.cut.fastq.gz" \
    -p "$CUT/${base}_2.cut.fastq.gz" \
    "$r1" "$r2" \
    >> "$LOG" 2>&1

  # --- fastp: авто-детект остатков + Q30 + minlen 250 ---
  echo "  [$base] fastp ..." | tee -a "$LOG"
  fastp -i "$CUT/${base}_1.cut.fastq.gz" \
    -I "$CUT/${base}_2.cut.fastq.gz" \
    -o "$TRIM/${base}_1.trim.fastq.gz" \
    -O "$TRIM/${base}_2.trim.fastq.gz" \
    --detect_adapter_for_pe -q 30 -l 250 -w 8 \
    -h "$FPR/${base}.html" -j "$FPR/${base}.json" \
    >> "$LOG" 2>&1

  # чистим intermediate (cutadapt output уже не нужен)
  rm -f "$CUT/${base}_1.cut.fastq.gz" "$CUT/${base}_2.cut.fastq.gz"
done
echo "[$DS] cutadapt + fastp done" | tee -a "$LOG"

# --- 3. FastQC на trimmed ---
echo "[$DS] FastQC ..." | tee -a "$LOG"
fastqc -t 8 -o "$FQC" "$TRIM"/*.trim.fastq.gz >> "$LOG" 2>&1
echo "[$DS] FastQC done: $(ls "$FQC"/*_fastqc.html 2>/dev/null | wc -l) reports" | tee -a "$LOG"

# --- 4. MultiQC на trimmed только ---
echo "[$DS] MultiQC ..." | tee -a "$LOG"
cd "$BASE" && python3 -m multiqc "$FQC" -o "$MQC" -f >> "$LOG" 2>&1
echo "[$DS] MultiQC done: $(ls "$MQC"/*.html 2>/dev/null)" | tee -a "$LOG"

# --- 5. Убрать пустой cutadapt/ ---
rmdir "$CUT" 2>/dev/null || true

echo "=== [$(date -u)] trim_dataset: $DS COMPLETE ===" | tee -a "$LOG"
echo "  trimmed:    $TRIM/"
echo "  fastp QC:   $FPR/"
echo "  FastQC:     $FQC/"
echo "  MultiQC:    $MQC/"

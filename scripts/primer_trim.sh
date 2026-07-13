#!/usr/bin/env bash
# primer_trim.sh — V-праймерный тримминг + post-primer QC.
#
# Для датасетов с V-праймерами (human PRJEB40348, horse PRJNA848968).
# Macaque и sheep не требуют — у них 5'RACE.
#
# Pipeline для КАЖДОЙ пары:
#   1. MaskPrimers.py align — local alignment, режет 5'-V-праймер
#      (mismatch 0.2, maxlen 50). Ловит праймер даже после адаптера.
#   2. fastp — фильтрация (Q30, minlen 200) + QC-отчёт
#   3. FastQC + MultiQC на post-primer риды
#
# Вход: риды ПОСЛЕ adapter_trim.sh (*.trim.fastq.gz)
# Выход: results/<DS>/pr_trimmed/{fastq, fastp_reports, fastqc, multiqc}/
#
# Запуск:
#   primer_trim.sh <DATASET> [<SRC_DIR>]
#
#   <DATASET>  — PRJEB40348 (human) или PRJNA848968 (horse)
#   <SRC_DIR>  — путь к adapter-trimmed FASTQ (по умолчанию results/<DS>/trimmed/fastq/)
#
# Пример:
#   primer_trim.sh PRJEB40348
#   primer_trim.sh PRJNA848968 /path/to/trimmed/fastqs
#
# Зависимости: pRESTO (MaskPrimers.py), fastp, fastqc, multiqc
set -u
export PATH="$HOME/.local/bin:$PATH"

DS="${1:?usage: primer_trim.sh <DATASET> [<SRC_DIR>]}"
SRC="${2:-results/$DS/trimmed/fastq}"

# Только human и horse имеют V-праймеры
case "$DS" in
    PRJEB40348)  PRIMERS=primer_refs/human_primers.fasta ;;
    PRJNA848968) PRIMERS=primer_refs/horse_primers.fasta ;;
    *) echo "ERROR: $DS не требует V-праймерного тримминга (macaque/sheep = 5'RACE)"; exit 2 ;;
esac
[ -f "$PRIMERS" ] || { echo "ERROR: $PRIMERS не найден (запусти setup_vm_tools.sh)"; exit 3; }
[ -d "$SRC" ] || { echo "ERROR: входная папка $SRC не найдена (запусти adapter_trim.sh сначала)"; exit 3; }

PAR=4          # параллельных пар (8 vCPU; MaskPrimers --nproc 4 => 16 потоков)
NPROC=4        # потоков на один MaskPrimers

# --- пути ---
OUT=results/$DS/pr_trimmed
PR=$OUT/fastp_reports
FQ=$OUT/fastqc
MQ=$OUT/multiqc
TMP=$OUT/fastq    # промежуточные + итоговые post-primer риды

mkdir -p "$PR" "$FQ" "$MQ" "$TMP"
echo "[$(date -u)] === primer_trim: $DS (primers: $(basename $PRIMERS), PAR=$PAR) ==="

# --- обработчик ОДНОЙ пары (вызывается из xargs) ---
process_pair() {
    local base="$1"
    local R1="$SRC/${base}_1.trim.fastq.gz"
    local R2="$SRC/${base}_2.trim.fastq.gz"
    [ -f "$R1" ] || { echo "  skip $base (нет $R1)"; return 0; }

    # 1) MaskPrimers ALIGN: режем 5'-V-праймер
    #   Вход .gz → MaskPrimers пишет выход <outname>_primers-pass.fastq.gz
    local MP1=${TMP}/${base}_1.pr_primers-pass.fastq.gz
    local MP2=${TMP}/${base}_2.pr_primers-pass.fastq.gz
    MaskPrimers.py align -s "$R1" -p "$PRIMERS" \
        --mode cut --maxerror 0.2 --nproc "$NPROC" --maxlen 50 \
        --outdir "$TMP" --outname ${base}_1.pr 2> "$PR/${base}_R1.maskprimer.log"
    MaskPrimers.py align -s "$R2" -p "$PRIMERS" \
        --mode cut --maxerror 0.2 --nproc "$NPROC" --maxlen 50 \
        --outdir "$TMP" --outname ${base}_2.pr 2> "$PR/${base}_R2.maskprimer.log"

    # 2) fastp: Q30 + minlen 200 (риды после вырезания праймера
    #    короче исходных; для horse ~250-300bp, после праймера ~200-280)
    local M1=${TMP}/${base}_1.pr.fastq.gz
    local M2=${TMP}/${base}_2.pr.fastq.gz
    fastp -i "$MP1" -I "$MP2" -o "$M1" -O "$M2" \
        -q 30 -l 200 --detect_adapter_for_pe \
        -w "$NPROC" \
        -h "${PR}/${base}.html" -j "${PR}/${base}.json" \
        2>> "${PR}/${base}.fastp.log"

    # 3) FastQC на финальных post-primer ридах
    fastqc -t "$NPROC" -o "$FQ" "$M1" "$M2" 2>/dev/null || true

    # чистим промежуточные MaskPrimers output (fastp output сохраняем)
    rm -f "$MP1" "$MP2"
    echo "  [$(date -u)] $base done"
}
export -f process_pair
export SRC PRIMERS PR FQ TMP NPROC

# --- собрать пары и гнать параллельно ---
PAIRS=$(cd "$SRC" && ls *_1.trim.fastq.gz 2>/dev/null | sed 's/_1\.trim\.fastq\.gz$//' | sort)
if [ -z "$PAIRS" ]; then
    echo "ERROR: нет пар в $SRC"
    exit 3
fi
printf '%s\n' $PAIRS | xargs -P "$PAR" -I{} bash -c 'process_pair "$@"' _ {}

echo "[$(date -u)] primer-trim + fastp-QC: OK"

# 4) MultiQC
multiqc "$FQ" -o "$MQ" -n "${DS}_primer_multiqc" -f 2>&1

echo "[$(date -u)] === primer_trim: $DS COMPLETE ==="
echo "  fastq:        $TMP/"
echo "  fastp report: $PR/"
echo "  FastQC:       $FQ/"
echo "  MultiQC:      $MQ/"

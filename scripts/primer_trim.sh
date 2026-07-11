#!/usr/bin/env bash
# primer_trim.sh — V-primer trimming + post-primer QC.
#
# Для КАЖДОГО целевого датасета (PRJEB40348=human, PRJNA848968=horse):
#   1. MaskPrimers (pRESTO) ALIGN режет 5'-V-праймер по primers.fasta (mismatch=0.2)
#   2. fastp: сжимает итоговые риды (.gz) + пишет честный QC-отчёт в fastp_reports
#   3. FastQC -> pr_trimmed/fastqc
#   4. MultiQC -> pr_trimmed/multiqc
#   5. копируем pr_trimmed/ в ~/rima_clone/results/<DS>/pr_trimmed/
#
# ВНИМАНИЕ: Адаптеры (Illumina TruSeq/Nextera) вырезаются НА ЭТАПЕ 2
# (scripts/trim_dataset.sh), а не здесь. cutadapt оттуда убран.
# Праймеры — это только V-специфичные последовательности.
#
# Пары обрабатываются ПАРАЛЛЕЛЬНО (xargs -P $PAR), т.к. VM = 8 vCPU, load ~0.
#
# Запуск:  primer_trim.sh <DATASET_ACCESSION>
# Пример:  primer_trim.sh PRJNA848968
#
set -u
export PATH=~/.local/bin:$PATH   # pRESTO (MaskPrimers.py) + cutadapt живут тут

DS="$1"
if [ -z "$DS" ]; then echo "USAGE: primer_trim.sh <DATASET>"; exit 1; fi

PAR=4          # параллельных пар (8 vCPU; внутри MaskPrimers --nproc 4 => 16 потоков)
NPROC=4        # потоков на MaskPrimers (в одной паре)

# --- пути ---
TRIM_SRC=~/results/qc_trim_pipeline/${DS}/trim          # adapter-trimmed риды (*.trim.fastq.gz)
REF=~/primer_refs
REPO=~/rima_clone/results/${DS}
OUT=${REPO}/pr_trimmed
PR=${OUT}/fastp_reports
FQ=${OUT}/fastqc
MQ=${OUT}/multiqc
TMP=${OUT}/fastq                                     # промежуточные + итоговые post-primer риды

# --- выбор primers.fasta по датасету ---
# horse: РЕАЛЬНЫЕ EquPD v2020 V-части (uppercase из Table 1 статьи Centaur,
#   PMID 36059507). Human: стандартный VH/VL FR1 multiplex (VBASE2-стиль).
case "$DS" in
  PRJEB40348)  PRIMERS=${REF}/human_primers.fasta ;;
  PRJNA848968) PRIMERS=${REF}/horse_primers.fasta ;;
  *) echo "ERROR: $DS не требует V-праймерного тримминга (macaque/sheep = 5'RACE)"; exit 2 ;;
esac
[ -f "$PRIMERS" ] || { echo "ERROR: $PRIMERS не найден"; exit 3; }

mkdir -p "$PR" "$FQ" "$MQ" "$TMP"

echo "[$(date -u)] === primer_trim: $DS (primers: $(basename $PRIMERS), PAR=$PAR) ==="

# --- обработчик ОДНОЙ пары (вызывается из xargs) ---
process_pair() {
  local base="$1"
  local R1="$TRIM_SRC/${base}_1.trim.fastq.gz"
  local R2="$TRIM_SRC/${base}_2.trim.fastq.gz"
  [ -f "$R1" ] || { echo "  skip $base (нет R1)"; return 0; }

  # 1) MaskPrimers ALIGN: режем 5'-V-праймер (local alignment, ловит праймер
  #    даже если перед ним сидит библиотечный адаптер). mismatch 20%.
  #    Вход .gz => MaskPrimers пишет выход <outname>_primers-pass.fastq.gz.
  local MP1=${TMP}/${base}_1.pr_primers-pass.fastq.gz
  local MP2=${TMP}/${base}_2.pr_primers-pass.fastq.gz
  MaskPrimers.py align -s "$R1" -p "$PRIMERS" \
      --mode cut --maxerror 0.2 --nproc "$NPROC" --maxlen 50 \
      --outdir "$TMP" --outname ${base}_1.pr 2> "$PR/${base}_R1.maskprimer.log"
  MaskPrimers.py align -s "$R2" -p "$PRIMERS" \
      --mode cut --maxerror 0.2 --nproc "$NPROC" --maxlen 50 \
      --outdir "$TMP" --outname ${base}_2.pr 2> "$PR/${base}_R2.maskprimer.log"

  # 2) fastp: фильтрация (Q30, min len 250, дочистка адаптеров в оверлапе) +
  #    сжатие итоговых ридов + QC-отчёт (те же критерии, что в adapter-trim шаге).
  #    Адаптеры уже вырезаны на этапе 2 (trim_dataset.sh), --detect_adapter_for_pe
  #    тут для единообразия (harmless redundancy).
  local M1=${TMP}/${base}_1.pr.fastq.gz
  local M2=${TMP}/${base}_2.pr.fastq.gz
  fastp -i "$MP1" -I "$MP2" -o "$M1" -O "$M2" \
      -q 30 -l 250 --detect_adapter_for_pe \
      -w "$NPROC" \
      -h ${PR}/${base}.html -j ${PR}/${base}.json \
      2>> ${PR}/${base}.fastp.log

  # 4) FastQC на финальных post-primer ридах
  fastqc -t "$NPROC" -o "$FQ" "$M1" "$M2" 2>/dev/null || true

  # чистим промежуточные (MaskPrimers output; fastp .pr.fastq.gz сохраняются)
  rm -f "$MP1" "$MP2"
  echo "  [$(date -u)] $base done"
}
export -f process_pair
export TRIM_SRC PRIMERS PR FQ TMP NPROC

# --- собрать пары и гнать параллельно ---
PAIRS=$(cd "$TRIM_SRC" && ls *_1.trim.fastq.gz | sed 's/_1\.trim\.fastq\.gz$//' | sort)
printf '%s\n' $PAIRS | xargs -P "$PAR" -I{} bash -c 'process_pair "$@"' _ {}

echo "[$(date -u)] primer-trim + fastp-QC пройдены; запуск MultiQC"
# 5) MultiQC на pr_trimmed/fastqc
multiqc "$FQ" -o "$MQ" -f

echo "[$(date -u)] готово: $OUT"
echo "  (коммит и пуш вручную: cd ~/rima_clone && git add results/${DS}/pr_trimmed && git commit -m 'primer trim ${DS}' && git push)"

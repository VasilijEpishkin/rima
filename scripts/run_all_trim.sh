#!/usr/bin/env bash
# run_all_trim.sh — Оркестратор: adapter trim + QC для всех 4 датасетов.
#
# Запускает trim_dataset.sh для каждого датасета ПОСЛЕДОВАТЕЛЬНО.
# Падение одного датасета не убивает остальные (set +e на каждый).
#
# Запуск:
#   bash scripts/run_all_trim.sh             # обычный запуск
#   nohup bash scripts/run_all_trim.sh &      # отвязать от терминала
#
# Зависимости: scripts/trim_dataset.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG=~/run_all_trim.log

exec > >(tee -a "$LOG") 2>&1
echo "############## [$(date -u)] RUN_ALL_TRIM START ##############"

run_one() {
  local ds="$1"
  echo ">>>> ENTER $ds"
  bash "$SCRIPT_DIR/trim_dataset.sh" "$ds" \
    && echo ">>>> OK $ds" \
    || echo ">>>> FAIL $ds (continuing)"
}

# Datasets: human, horse, macaque, sheep
run_one PRJEB40348
run_one PRJNA848968
run_one PRJNA1247978
run_one PRJNA900592

echo "############## [$(date -u)] RUN_ALL_TRIM FINISH ##############"
echo "FINAL STATUS:"
grep -E "COMPLETE|FAIL|FAILED" "$LOG" | tail -20

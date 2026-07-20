#!/usr/bin/env bash
# setup_vm_conda.sh — воссоздание рабочего окружения на OneQ VM (jupyter/base-notebook).
#
# ЧТО ДЕЛАЕТ:
#   1. Создаёт conda-env bcr_env в /opt/conda/envs/bcr_env (python 3.11)
#   2. Ставит fastqc + fastp (conda, channel bioconda)
#   3. Ставит cutadapt + multiqc + presto (pip, внутрь env)
#   4. Регистрирует ipykernel "BCR Pipeline" для Jupyter
#   5. Проверяет что все 5 инструментов видны
#
# ПОЧЕМУ ТАК (а не в ~/.local/bin + apt):
#   - На OneQ jupyter/base-notebook НЕТ sudo и apt недоступен для системных пакетов.
#   - Ранний вариант ставил в /data/user/epishkin/conda_env — ЭТОГО ПУТИ БОЛЬШЕ НЕТ
#     (env переименован в bcr_env и живёт в /opt/conda/envs/bcr_env).
#   - SSH к VM не поднимается (нет sshd в контейнере, oneq-прокси refuses),
#     поэтому работаем через Jupyter Terminal (вкладка Terminal в Jupyter).
#
# ЗАПУСК (в Jupyter Terminal или oneq terminal, НЕ через sudo):
#   bash /data/user/epishkin/scripts/setup_vm_conda.sh
#
# ПОСЛЕ ЗАПУСКА:
#   - В Jupyter: Kernel -> Change Kernel -> "BCR Pipeline"
#   - ИЛИ в первой ячейке ноутбука (если kernel не зарегистрирован):
#       import os, sys
#       _E = "/opt/conda/envs/bcr_env"
#       os.environ["PATH"] = _E + "/bin:" + os.environ.get("PATH", "")
#       sys.path.insert(0, _E + "/lib/python3.11/site-packages")
#
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date -u +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

ENV_NAME="bcr_env"
ENV_PREFIX="/opt/conda/envs/${ENV_NAME}"

log "=== 1. Создание conda-env: ${ENV_NAME} ==="
if [ -x "${ENV_PREFIX}/bin/python3" ]; then
    log "  уже существует -> ${ENV_PREFIX}"
else
    conda create -y -p "${ENV_PREFIX}" python=3.11
fi

# активация (source необходим, иначе PATH не обновится)
source /opt/conda/etc/profile.d/conda.sh
conda activate "${ENV_NAME}"

log "=== 2. fastqc + fastp (conda bioconda) ==="
conda install -y -c bioconda fastqc fastp
fastp --version 2>&1 | head -1
fastqc --version 2>&1 | head -1

log "=== 3. cutadapt + multiqc + presto (pip) ==="
pip install --upgrade pip setuptools wheel
pip install cutadapt multiqc presto
cutadapt --version 2>&1 | head -1
multiqc --version 2>&1 | head -1
MaskPrimers.py --version 2>&1 | head -1

log "=== 4. Регистрация Jupyter kernel ==="
pip install ipykernel
python3 -m ipykernel install --user --name "${ENV_NAME}" --display-name "BCR Pipeline"
log "  kernel 'BCR Pipeline' зарегистрирован"

# Прописываем PATH в kernel.json, чтобы subprocess (cutadapt/fastp/...) видел
# инструменты без ручной env-ячейки в ноутбуке. Jupyter-сервер стартует с
# системным PATH, поэтому даже при kernel=bcr_env вызовы через subprocess.run
# ищут бинарники в системном PATH и падают с FileNotFoundError.
KJSON=$(python3 -c "import jupyter_core,os; \
print(os.path.join(jupyter_core.paths.jupyter_data_dir(),'kernels',${ENV_NAME},'kernel.json'))")
log "  kernel.json: ${KJSON}"
if [ -f "${KJSON}" ]; then
    python3 - "$KJSON" "${ENV_PREFIX}" <<'PY'
import json, sys
kjson, envp = sys.argv[1], sys.argv[2]
d = json.load(open(kjson))
d["env"] = {"PATH": f"{envp}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
json.dump(d, open(kjson, "w"), indent=2)
print("  [OK] env.PATH прописан в kernel.json")
PY
else
    warn "  kernel.json не найден, env-cell в ноутбуке остаётся обязательным"
fi

log "=== 5. Финальная проверка ==="
RC=0
for cmd in fastp fastqc cutadapt multiqc MaskPrimers.py; do
    if which "${cmd}" >/dev/null 2>&1; then
        echo "  [OK] ${cmd} -> $(which ${cmd})"
    else
        echo "  [MISS] ${cmd}"; RC=1
    fi
done

echo
if [ "${RC}" -eq 0 ]; then
    log "=== ВСЁ ГОТОВО ==="
    log "Открой ноутбук -> Kernel -> Change Kernel -> BCR Pipeline"
else
    warn "=== НЕ ВСЕ ИНСТРУМЕНТЫ УСТАНОВЛЕНЫ (RC=${RC}) ==="
fi
exit "${RC}"

#!/usr/bin/env bash
#
# setup_qc_trim_stack.sh
# Устанавливает стек QC -> trimming -> assembly для проекта rima
# на чистую Debian 12 (bookworm). Снят со снапшота bcr-analysis-vm (2026-07-08).
#
# Использование:  bash setup_qc_trim_stack.sh
# (sudo запрашивается только для apt; pip-пакеты ставятся в ~/.local)
#
set -euo pipefail

LOG=/tmp/qc_trim_stack_install.log
exec > >(tee -a "$LOG") 2>&1

echo "=== [$(date)] Start rima QC/trim/assembly stack install ==="

# ---------------------------------------------------------------------------
# 0. Окружение
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# ---------------------------------------------------------------------------
# 1. Системные пакеты (apt)
# ---------------------------------------------------------------------------
echo "=== [1/5] apt: build tools, Java, utils ==="
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    default-jdk-headless \
    unzip \
    pigz \
    git \
    curl \
    wget

# ---------------------------------------------------------------------------
# 2. Python-пакеты (pip, системный Python 3.11)
#    --break-system-packages нужен, т.к. Python "externally managed" в Debian 12
# ---------------------------------------------------------------------------
echo "=== [2/5] pip: multiqc, presto, cutadapt ==="
python3 -m pip install --break-system-packages --upgrade pip
python3 -m pip install --break-system-packages multiqc
python3 -m pip install --break-system-packages presto
python3 -m pip install --break-system-packages cutadapt

# ---------------------------------------------------------------------------
# 3. TRUST4 (git clone + make)
# ---------------------------------------------------------------------------
echo "=== [3/5] TRUST4 build ==="
cd "$HOME"
if [ ! -d TRUST4 ]; then
    git clone https://github.com/liulab-dfci/TRUST4.git
fi
cd TRUST4
make

# ---------------------------------------------------------------------------
# 4. IgReC (git clone + CMake)
# ---------------------------------------------------------------------------
echo "=== [4/5] IgReC build ==="
cd "$HOME"
if [ ! -d ig_repertoire_constructor ]; then
    git clone https://github.com/ig-r/ig_repertoire_constructor.git
fi
cd ig_repertoire_constructor
cmake -S . -B build/release -DCMAKE_BUILD_TYPE=Release
cmake --build build/release -j"$(nproc)"

# ---------------------------------------------------------------------------
# 5. PATH для pip-скриптов (~/.local/bin)
# ---------------------------------------------------------------------------
echo "=== [5/5] PATH setup ==="
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# Итоговая проверка
# ---------------------------------------------------------------------------
echo "=== Verification ==="
fastp --version            | head -1 || echo "fastp MISSING"
fastqc --version           | head -1 || echo "fastqc MISSING"
python3 -m multiqc --version | tail -1 || echo "multiqc MISSING"
cutadapt --version         || echo "cutadapt MISSING"
MaskPrimers.py --version   | head -1 || echo "pRESTO MISSING"
ls "$HOME/TRUST4/run-trust4"        && echo "TRUST4 OK" || echo "TRUST4 MISSING"
ls "$HOME/ig_repertoire_constructor/build/release/bin/igrec" && echo "IgReC OK" || echo "IgReC MISSING"

echo "=== DONE. Run: source ~/.bashrc ==="

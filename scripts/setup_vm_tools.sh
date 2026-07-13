#!/usr/bin/env bash
# setup_vm_tools.sh — установка инструментов QC + adapter-trim + primer-trim + assembly.
#
# Для новой VM (Debian 12). Ставит ТОЛЬКО инструменты — без датасетов,
# без праймеров, без клонирования репозитория.
#
# Stacks:
#   QC:            fastqc, multiqc
#   Adapter-trim:  cutadapt, fastp
#   Primer-trim:   pRESTO (MaskPrimers.py)
#   Assembly:      TRUST4, IgReC
#
# Зависимости: build-essential, cmake, git, pigz, default-jdk-headless
#
# Запуск:
#   sudo bash scripts/setup_vm_tools.sh 2>&1 | tee setup_vm_tools.log
#
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { echo -e "${GREEN}[$(date -u)]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

export DEBIAN_FRONTEND=noninteractive
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# =============================================================
# 1. СИСТЕМНЫЕ ПАКЕТЫ
# =============================================================
log "=== 1. Системные пакеты ==="
apt-get update -qq
apt-get install -y -qq \
    build-essential cmake git wget curl unzip \
    python3-pip python3-venv python3-dev \
    default-jdk-headless pigz parallel \
    libncurses5-dev libncursesw5-dev \
    libbz2-dev liblzma-dev zlib1g-dev
log "  Системные пакеты: OK"

# =============================================================
# 2. QC + ADAPTER-TRIM ИНСТРУМЕНТЫ (pip / apt)
# =============================================================
log "=== 2. QC + trim инструменты ==="

# fastp — бинарник
log "  fastp..."
apt-get install -y -qq fastp 2>/dev/null || {
    wget -q https://github.com/OpenGene/fastp/archive/refs/tags/v0.23.4.tar.gz -O /tmp/fastp.tar.gz
    cd /tmp && tar xzf fastp.tar.gz && cd fastp-* && make -j"$(nproc)" && cp fastp /usr/local/bin/
}
fastp --version 2>&1 | head -1

# FastQC
log "  FastQC..."
apt-get install -y -qq fastqc 2>/dev/null || {
    wget -q https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip -O /tmp/fastqc.zip
    cd /opt && unzip -q /tmp/fastqc.zip && chmod +x /opt/FastQC/fastqc
    ln -sf /opt/FastQC/fastqc /usr/local/bin/fastqc
}
fastqc --version 2>&1 | head -1

# cutadapt, MultiQC, pRESTO (pip в ~/.local/bin)
log "  cutadapt, MultiQC, pRESTO..."
python3 -m pip install --break-system-packages --upgrade pip setuptools wheel
python3 -m pip install --break-system-packages cutadapt multiqc presto
cutadapt --version 2>&1 | head -1
multiqc --version 2>&1 | head -1
python3 -c "import presto; print('pRESTO:', presto.__version__)" 2>/dev/null || true

# PATH для pip-скриптов
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# =============================================================
# 3. СБОРКА TRUST4
# =============================================================
log "=== 3. TRUST4 ==="
cd "$HOME"
if [ ! -d TRUST4 ]; then
    git clone --depth 1 https://github.com/liulab-dfci/TRUST4.git
fi
cd TRUST4
make -j"$(nproc)"
ls run-trust4 >/dev/null && log "  TRUST4: OK"

# =============================================================
# 4. СБОРКА IgReC
# =============================================================
log "=== 4. IgReC ==="
cd "$HOME"
if [ ! -d ig_repertoire_constructor ]; then
    git clone --depth 1 https://github.com/ig-r/ig_repertoire_constructor.git
fi
cd ig_repertoire_constructor
cmake -S . -B build/release -DCMAKE_BUILD_TYPE=Release
cmake --build build/release -j"$(nproc)"
ls build/release/bin/igrec >/dev/null && log "  IgReC: OK"

# =============================================================
# 5. ФИНАЛЬНАЯ ПРОВЕРКА
# =============================================================
log "=== 5. Финальная проверка ==="
echo ""
echo "--- Инструменты ---"
RC=0
for cmd in fastp fastqc cutadapt multiqc MaskPrimers.py; do
    if which "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $cmd"
    else
        echo "  ✗ $cmd"; RC=1
    fi
done
for bin in "$HOME/TRUST4/run-trust4" "$HOME/ig_repertoire_constructor/build/release/bin/igrec"; do
    if [ -f "$bin" ]; then
        echo "  ✓ $(basename $bin)"
    else
        echo "  ✗ $bin"; RC=1
    fi
done
echo ""
if [ "$RC" -eq 0 ]; then
    log "=== ВСЁ ГОТОВО ==="
    echo "Запусти: source ~/.bashrc"
else
    warn "=== НЕ ВСЕ ИНСТРУМЕНТЫ УСТАНОВЛЕНЫ (RC=$RC) ==="
fi
exit "$RC"

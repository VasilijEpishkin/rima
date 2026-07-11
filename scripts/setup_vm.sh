#!/usr/bin/env bash
# setup_vm.sh — установка стека QC + тримминг для BCR-пайплайна.
#
# Запуск:
#   chmod +x setup_vm.sh && sudo bash setup_vm.sh 2>&1 | tee setup_vm.log
#
# Что делает:
#   1. Системные пакеты (build-essential, git, pigz, parallel, python3, ...)
#   2. Инструменты: fastp, cutadapt, FastQC, MultiQC, pRESTO (MaskPrimers.py)
#   3. SRA Toolkit (fasterq-dump для загрузки датасетов из ENA)
#   4. Клонирование репозитория с результатами (github.com/VasilijEpishkin/rima)
#   5. Праймер-референсы (horse + human)
#   6. Скачивание датасетов из ENA
#
# Время выполнения: ~30-60 мин (в основном скачивание датасетов)

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date -u)]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# =============================================================
# 1. СИСТЕМНЫЕ ПАКЕТЫ
# =============================================================
log "=== 1. Системные пакеты ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    build-essential cmake git wget curl unzip \
    python3-pip python3-venv python3-dev \
    pigz parallel \
    libncurses5-dev libncursesw5-dev \
    libbz2-dev liblzma-dev zlib1g-dev  \
    && log "  Системные пакеты: OK"

# =============================================================
# 2. ИНСТРУМЕНТЫ
# =============================================================
log "=== 2. Python-инструменты ==="
python3 -m venv /opt/bcr_env 2>/dev/null || true
source /opt/bcr_env/bin/activate
pip install -q --upgrade pip setuptools wheel

# fastp — бинарник
log "  fastp..."
apt-get install -y -qq fastp 2>/dev/null || {
    wget -q https://github.com/OpenGene/fastp/archive/refs/tags/v0.23.4.tar.gz -O /tmp/fastp.tar.gz
    cd /tmp && tar xzf fastp.tar.gz && cd fastp-* && make -j"$(nproc)" && cp fastp /usr/local/bin/
}
fastp --version 2>&1 | head -1

# cutadapt, MultiQC, pRESTO
log "  cutadapt, MultiQC, pRESTO..."
pip install -q cutadapt multiqc presto
cutadapt --version 2>&1 | head -1
multiqc --version 2>&1 | head -1
python3 -c "import presto; print('pRESTO:', presto.__version__)" 2>/dev/null || true

# FastQC
log "  FastQC..."
apt-get install -y -qq fastqc 2>/dev/null || {
    wget -q https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip -O /tmp/fastqc.zip
    cd /opt && unzip -q /tmp/fastqc.zip && chmod +x /opt/FastQC/fastqc
    ln -sf /opt/FastQC/fastqc /usr/local/bin/fastqc
}
fastqc --version 2>&1 | head -1

# Проверка
log "  Проверка..."
for cmd in fastp cutadapt multiqc MaskPrimers.py fastqc; do
    which "$cmd" >/dev/null 2>&1 && log "  ✓ $cmd" || warn "  ✗ $cmd НЕ НАЙДЕН"
done

# =============================================================
# 3. SRA TOOLKIT (fasterq-dump)
# =============================================================
log "=== 3. SRA Toolkit ==="
apt-get install -y -qq sra-toolkit 2>/dev/null || {
    cd /tmp
    wget -q https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/sratoolkit.current-ubuntu64.tar.gz
    tar xzf sratoolkit.*-ubuntu64.tar.gz
    cp sratoolkit.*/bin/* /usr/local/bin/
    rm -rf sratoolkit.*
}
vdb-config --set /repository/user/main/public/root="/opt/ncbi/public" 2>/dev/null || true
which fasterq-dump >/dev/null && log "  ✓ fasterq-dump" || warn "  ✗ fasterq-dump"

# =============================================================
# 4. КЛОНИРОВАНИЕ РЕПОЗИТОРИЯ
# =============================================================
log "=== 4. Клонирование репозитория rima ==="
cd ~
if [ -d ~/rima ]; then
    warn "  ~/rima уже существует, обновляю..."
    cd ~/rima && git pull --ff-only
else
    git clone https://github.com/VasilijEpishkin/rima.git
fi
log "  Репозиторий: OK"

# =============================================================
# 5. ПРАЙМЕР-РЕФЕРЕНСЫ
# =============================================================
log "=== 5. Праймер-референсы ==="
mkdir -p ~/primer_refs

# Horse: EquPD v2020 (Centaur, PMID 36059507)
cat > ~/primer_refs/horse_primers.fasta << 'HORSE'
>Equ-VH-PD_For1
CAGGTGCAACTGAAGGAGTC
>Equ-VH-PD_For2
CAGGTGCAACTGCTGGAGTC
>Equ-VH-PD_For3
CAGGTGCAGCTGAAGGAGTC
>Equ-VH-PD_For4
CAGGTGCAGCTGCAGGAGTC
>Equ-VH-PD_For5
CAGGTGCAGCTGCAGGAGTCGGG
>Equ-VH-PD_For6
CAGGTGCAACTGCTGGAGTCGGG
>Equ-VH-PD_For7
CAGGTGCAGCTGAAGGAGTCGGG
>Equ-Vk-PD_For1
GACRTCGTGATGACSAGTCTCC
>Equ-Vk-PD_For3
GACRTCGTGATGACCCAGTCTCC
>Equ-Vk-PD_For4
GACATCCAGATGACCCAGTCTCC
>Equ-Vk-PD_For5
GACATCCAGATGACCCAGTCTCCA
>Equ-Vk-PD_For6
GACATCGTGATGACCCAGTCTCC
>Equ-Vk-PD_For7
GAAACACAGTGAACCCAGTCTCC
>Equ-Vk-PD_For8
GAAACACAGTGAACCCAGTCTCCA
>Equ-Vk-PD_For9
GAAATTGTGCTGACTCAATCTCC
>Equ-VL-PD_For1
CAGTCTGTGACCCAGCCCGC
>Equ-VL-PD_For2
CAGTCTGTGACCCAGCCCGCC
>Equ-VL-PD_For3
CAGTCTGTGACCCAGCCGCC
>Equ-VL-PD_For4
CAGTCTGTGACCCAGCCTCC
>Equ-VL-PD_For5
CAGTCTGTGACCCAGCCACC
>Equ-VL-PD_For6
CAGTCTGTGACCCAGCCACCGGG
>Equ-VL-PD_For7
TCTTCTGCAGTGACTCAGCC
>Equ-VL-PD_For8
TCTTCTGCAGTGACTCAGCCCTT
>Equ-VL-PD_For9
TCTTCTGAGGTGACTCAGCC
>Equ-VL-PD_For10
TCTTCTGAGGTGACTCAGCCCTT
>Equ-VL-PD_For11
TCTTCTATGCTGACTCAGCC
>Equ-VL-PD_For12
TCTTCTATGCTGACTCAGCCCTT
>Equ-VL-PD_For13
CAAAGTAACCTGACTCAGCCGG
>Equ-VL-PD_For14
CAAAGTAACCTGACTCATCCGGG
HORSE

# Human: FR1 multiplex (Cheng 2011 / BIOMED-2)
cat > ~/primer_refs/human_primers.fasta << 'HUMAN'
>VH1_1
CAGGTCCAGCTTGTGCAGTCTGG
>VH1_2
CAGGTCCAGCTKGTGCAGTCTGG
>VH1_3
CAGATCCAGCTGGTGCAGTCTGG
>VH2_1
CAGATCACCTTGAAGGAGTCTGG
>VH3_1
GAGGTGCAGCTGGTGGAGTCTGG
>VH3_2
GAGGTGCAGCTGGTGGAGTCTGGG
>VH4_1
CAGGTGCAGCTACAGCAGTGG
>VH4_2
CAGGTGCAGCTACAGCAATGGG
>VH5_1
GAGGTGCAGCTGTTGCAGTCTGC
>VH6_1
CAGGTACAGCTGCAGCAGTCAG
>VH7_1
CAGGTGCAASTGGTGCAATCTGG
>Vk1_1
GACATCCAGATGACCCAGTCTCC
>Vk1_2
GACATCCAGTTGACCCAGTCTCC
>Vk2_1
GATGTTGTGATGACTCAGTCTCC
>Vk2_2
GATATTGTGATGACTCAGTCTCC
>Vk3_1
GAAATTGTGTTGACGCAGTCTCC
>Vk4_1
GACATCGTGATGACCCAGTCTCC
>Vk5_1
GAAACGACACTCACGCAGTCTCC
>Vk6_1
GAAATTGTGCTGACTCAGTCTCC
>Vk7_1
GACATTGTGATGACCCAGTCTCC
>Vl1_1
CAGTCTGTGCTGACTCAGCCACC
>Vl1_2
CAGTCTGTGCTGACACAGCCACC
>Vl2_1
CAGTCTGCCCTGACTCAGCCT
>Vl3_1
TCCTATGTGCTGACTCAGCCACC
>Vl3_2
TCTTCTGAGCTGACTCAGGACCC
>Vl4_1
CAGTCTGTGCTGACTCAGCCGC
>Vl5_1
CAGCCTGTGCTGACTCAGCCT
>Vl6_1
AATTTTATGCTGACTCAGCCCC
>Vl7_1
CAGRCTGTGGTGACTCAGGAGCC
>Vl8_1
CAGACTGTGGTGACCCAGGAGCC
>Vl9_1
CAGCCTGTGCTGACTCAGCCTTC
>Vl10_1
CAGCCAGGGCTGACTCAGCCT
HUMAN

log "  ✓ horse_primers.fasta ($(grep -c '^>' ~/primer_refs/horse_primers.fasta) seqs)"
log "  ✓ human_primers.fasta ($(grep -c '^>' ~/primer_refs/human_primers.fasta) seqs)"

# =============================================================
# 6. СКАЧИВАНИЕ ДАТАСЕТОВ ИЗ ENA
# =============================================================
log "=== 6. Скачивание датасетов из ENA ==="
mkdir -p ~/fastq

download_dataset() {
    local accession="$1"
    local label="$2"
    mkdir -p ~/fastq/$accession/raw
    cd ~/fastq/$accession/raw

    local srr_list=$(curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=$accession&result=read_run&fields=run_accession,fastq_ftp" 2>/dev/null | grep -v "^run_accession" | cut -d$'\t' -f1)
    if [ -z "$srr_list" ]; then
        warn "  $label: список SRR пуст"
        return 1
    fi
    local n=0
    for srr in $srr_list; do
        n=$((n+1))
        if [ -f "${srr}_1.fastq.gz" ]; then
            log "  $label: $srr уже скачан"; continue
        fi
        log "  $label: [$n] $srr..."
        fasterq-dump --split-files --outdir . --progress "$srr" 2>&1 | tail -1 || {
            warn "  $srr: fasterq-dump упал, пробую curl..."
            local url=$(curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=$accession&result=read_run&fields=fastq_ftp" 2>/dev/null | grep "$srr" | cut -d$'\t' -f2)
            if [ -n "$url" ]; then
                wget -q "$(echo $url | tr ';' '\n' | head -1)" -O "${srr}_1.fastq.gz"
                wget -q "$(echo $url | tr ';' '\n' | tail -1)" -O "${srr}_2.fastq.gz"
            fi
        }
        # сжимаем если fasterq-dump выдал несжатые
        [ -f "${srr}_1.fastq" ] && pigz -p "$(nproc)" "${srr}_1.fastq"
        [ -f "${srr}_2.fastq" ] && pigz -p "$(nproc)" "${srr}_2.fastq"
        log "  $label: $srr готов"
    done
    log "  ✓ $label: $n пар"
}

download_dataset PRJEB40348  "Human-MultipleSclerosis" &
download_dataset PRJNA848968 "Horse-EquPD" &
download_dataset PRJNA1247978 "Macaque-5RACE" &
download_dataset PRJNA900592  "Sheep-5RACE" &
wait
log "  Все датасеты: OK"

# =============================================================
# 7. ФИНАЛЬНАЯ ПРОВЕРКА
# =============================================================
log "=== 7. Финальная проверка ==="
echo ""
echo "--- Инструменты ---"
for cmd in fastp cutadapt multiqc MaskPrimers.py fastqc fasterq-dump; do
    which "$cmd" 2>/dev/null && echo "  ✓ $cmd" || echo "  ✗ $cmd"
done
echo ""
echo "--- Датасеты ---"
for ds in PRJEB40348 PRJNA848968 PRJNA1247978 PRJNA900592; do
    n=$(ls ~/fastq/$ds/raw/*_1.fastq.gz 2>/dev/null | wc -l)
    echo "  $ds: $n пар"
done
echo ""
log "=== ГОТОВО ==="
echo "Скрипты тримминга: ~/rima/scripts/primer_trim.sh"
echo "Праймеры:          ~/primer_refs/{horse,human}_primers.fasta"
echo "Датасеты:          ~/fastq/<DS>/raw/"
echo ""
echo "Запуск adapter-trim:  fastp --detect_adapter_for_pe -q 30 -l 250 -w 8 ..."
echo "Запуск primer-trim:   cd ~ && bash ~/rima/scripts/primer_trim.sh <DATASET>"
echo "Коммит результатов:   cd ~/rima && git add results/ && git commit -m '...' && git push"

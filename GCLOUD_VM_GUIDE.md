# GCP VM Operations Guide — rima (BCR/TCR benchmark)

Полный справочник по работе с виртуальной машиной `bcr-analysis-vm`,
GCS-бакетом `bioinformatics4` и пайплайном Stage A.

> Все команды приведены с переменными `$PROJECT/$ZONE/$VM` — задайте их один раз
> в начале сессии (см. §1) и копируйте далее.

---

## 1. Окружение и доступ

| Ресурс | Значение |
|--------|----------|
| GCP Project | `cs-poc-eat9v8av8rsg0ahe0t75icw` |
| VM | `bcr-analysis-vm` (e2-standard-8, `us-central1-a`) |
| Bucket | `gs://bioinformatics4` (US multi-region) |
| Доступ | **IAP SSH tunnel** (без external IP — org policy) |
| VM-пользователь | `umoxinacuve54_gmail_com` (HOME=`/home/umoxinacuve54_gmail_com`) |
| Стоимость | ~$144/мес, пока VM RUNNING — **стопайте, когда не нужна** |

### Базовые переменные (выполнить один раз в терминале)

```bash
export PROJECT=cs-poc-eat9v8av8rsg0ahe0t75icw
export ZONE=us-central1-a
export VM=bcr-analysis-vm
```

### Управление VM

```bash
# Статус
gcloud compute instances list --project=$PROJECT

# Запустить / остановить
gcloud compute instances start $VM --project=$PROJECT --zone=$ZONE
gcloud compute instances stop  $VM --project=$PROJECT --zone=$ZONE   # экономия денег

# Интерактивный SSH через IAP
gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE --tunnel-through-iap

# Одноразовая команда без входа
gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE --tunnel-through-iap --command='<команда>'

# Долгую задачу — в фон на VM (отвязать от SSH):
gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE --tunnel-through-iap \
  --command='nohup bash ~/run_qc.sh PRJNA1247978 > ~/qc.log 2>&1 & echo "PID=$!"'
```

### Копирование файлов

```bash
# Локально → VM
gcloud compute scp --tunnel-through-iap run_qc.sh $VM:~/run_qc.sh --project=$PROJECT --zone=$ZONE

# VM → локально
gcloud compute scp --tunnel-through-iap $VM:~/qc.log ./qc.log --project=$PROJECT --zone=$ZONE

# Дать права на выполнение
gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE --tunnel-through-iap --command='chmod +x ~/run_qc.sh'
```

> IAP-туннель пишет `WARNING: ... NumPy ...` — это безобидно, можно игнорировать.

---

## 2. Структура VM

### Спеки машины
- **8 vCPU, 31 GiB RAM, 200 GB pd-ssd** (148 GB свободно на момент написания)
- **R 4.2.2** (Bioc 3.16) — **важно**: лимитирует установку части пакетов (см. §6 dowser)

### Ключевые директории

| Путь | Назначение |
|------|-----------|
| `~/qc_work/<BIOPROJECT>/` | Рабочие данные QC: `raw/`, `fastqc_out/`, `multiqc_out/` |
| `~/run_qc.sh` | Stage A1 QC pipeline (FastQC + MultiQC) |
| `~/ig_repertoire_constructor/` | Исходники IgReC + сборка |
| `~/ig_repertoire_constructor/build/release/bin/` | **IgReC бинарники (28 шт)** |
| `~/TRUST4/run-trust4` | TRUST4 — альтернативная реконструкция репертуара |
| `~/dowser_install*.log`, `~/qc_PRJNA*.log` | Логи установки/прогонов |
| `/usr/local/lib/R/site-library/` | R-пакеты (через `sudo`) |

### Установленный стек инструментов

| Инструмент | Версия | Вызов / путь |
|------------|--------|--------------|
| FastQC | 0.11.9 | `fastqc` |
| fastp | 0.23.2 | `fastp` |
| MultiQC | 1.35 | `python3 -m multiqc` **(НЕ на PATH — только как модуль)** |
| bowtie2 | 2.5.0 | `bowtie2` |
| samtools | 1.16.1 | `samtools` |
| pRESTO | 0.7.9 | `python3 -c "import presto"` (модуль) |
| IgReC | — | `~/ig_repertoire_constructor/build/release/bin/` |
| TRUST4 | — | `~/TRUST4/run-trust4` |

**Python:** `/usr/bin/python3` — presto 0.7.9, Biopython, google-cloud-storage, requests, python-dotenv.
Конды/envs **нет** (системный python).

**R-пакеты Immcantation:** shazam 1.3.2, alakazam 1.4.3, scoper 1.5.0, tigger 1.1.3,
Biostrings 2.66.0, GenomicAlignments, IRanges, BiocManager, phangorn 2.12.1.

### НЕ установлено (потребуется для Stage B)
- **InSilicoSeq (`iss`)** — симуляция ридов (Stage B2)
- **IgBLAST (`igblastn`)** — V(D)J-аннотация (если нужен вместо внутреннего IgReC VJFinder)
- **dowser** — клониальная филогения (не встаёт на R 4.2, см. §6)

---

## 3. Структура GCS-бакета `bioinformatics4`

```
gs://bioinformatics4/
├── bioproject/                 # сырые FASTQ (~30 GiB, 4 датасета)
│   ├── PRJEB40348/             # human    — PE ~350 bp, VH+VL
│   ├── PRJNA848968/            # horse    — PE ~250-300 bp, H+L
│   ├── PRJNA900592/            # sheep    — PE 602 bp/pair, IGH+IGK+IGL
│   └── PRJNA1247978/           # macaque  — PE 602 bp/pair, IGHV+IGKV+IGLV
└── results/
    └── qc/                     # QC-отчёты (заливаются run_qc.sh)
        ├── PRJNA900592/{fastqc,multiqc}/
        └── PRJNA1247978/{fastqc,multiqc}/
```

```bash
# Навигация по бакету
gsutil ls gs://bioinformatics4/bioproject/
gsutil ls gs://bioinformatics4/results/qc/
gsutil du -s gs://bioinformatics4/bioproject/      # суммарный размер

# Чтение/запись с VM (работает через ADC, без SA-ключа)
gcloud storage cp gs://bioinformatics4/bioproject/PRJNA1247978/*.fastq.gz ./
gcloud storage cp -r ./multiqc_out gs://bioinformatics4/results/qc/PRJNA1247978/
```

> human (PRJEB40348) и horse (PRJNA848968) QC-отчёты **ещё не залиты** в
> `results/qc/` — только локально в `results/`. Залить при необходимости.

---

## 4. Воркфлоу Stage A

```
A1 QC (FastQC+MultiQC)
 ↓
A2 adapter/primer trim (fastp ИЛИ pRESTO MaskPrimers)
 ↓
A3 merge PE reads (pRESTO AssemblePairs)
 ↓
A4 filter non-productive
 ↓
A5 reconstruction (IgReC ИЛИ TRUST4)
 ↓
A6 assembly QC (IgQUAST)
 ↓
A7 SHM profile (Immcantation: shazam/alakazam)
```

### A1 — QC (FastQC + MultiQC) — автоматизировано

```bash
# На VM (скрипт копирует FASTQ из GCS, гонит FastQC, собирает MultiQC, льёт отчёты в GCS):
bash ~/run_qc.sh PRJNA1247978

# Скачать отчёты локально (с VM staging-area в GCS → results/):
gcloud storage cp -r gs://bioinformatics4/results/qc/PRJNA1247978/multiqc/* results/multiqc/
gcloud storage cp -r gs://bioinformatics4/results/qc/PRJNA1247978/fastqc/*  results/fastqc_PRJNA1247978/
```

### A2 — adapter/primer trimming

```bash
# ВАРИАНТ 1 — fastp (быстро, авто-детект адаптеров PE):
fastp -i R1.fq.gz -I R2.fq.gz -o R1.trim.fq.gz -O R2.trim.fq.gz \
  --detect_adapter_for_pe --cut_front --cut_tail --correction -h fastp.html -j fastp.json

# ВАРИАНТ 2 — pRESTO MaskPrimers (primer-aware, для известных V/J праймеров):
MaskPrimers.py score -s R1.fq -p V_PRIMER.fa --mode cut --name VPRIMER \
  --start 0 --maxerror 0.2 --outdir .
```

### A3 — merge overlapping PE reads

```bash
AssemblePairs.py align -1 R1.fq -2 R2.fq --outdir . --nproc 8
```

### A4 — filter non-productive

```bash
FilterSeq.py quality  -s assembled.fq -q 20 --outname filt --outdir .
ParseHeaders.py ...
```

### A5 — repertoire reconstruction

```bash
# ВАРИАНТ 1 — IgReC (VJFinder + Hamming-кластеризация + consensus):
IGREC=~/ig_repertoire_constructor/build/release/bin
$IGREC/ig_rec.py --loci ig ...   # см. документацию IgReC под конкретный датасет

# ВАРИАНТ 2 — TRUST4 (de novo, для bam/fastq):
~/TRUST4/run-trust4 -t 8 -f ~/TRUST4/hg38_bcRtcr.fa -1 R1.fq -2 R2.fq -o trust_out
```

### A6 — assembly QC

IgQUAST / сравнение сборок IgReC vs TRUST4.

### A7 — SHM profile (Immcantation R)

```bash
# Порядок Immcantation: TIGGER genotyping → createGermlines → distToNearest/findThreshold
# → clonal clustering → per-clone createGermlines → observedMutations
Rscript -e 'library(shazam); library(alakazam); ...'
# Формат вывода: AIRR Rearrangement TSV (lowercase snake_case).
```

---

## 5. Полезные команды

### Базовые

```bash
# Проверить, что задача на VM ещё работает
gcloud compute ssh $VM --tunnel-through-iap --command='pgrep -af run_qc.sh; tail -5 ~/qc.log'

# Свободное место / память
gcloud compute ssh $VM --tunnel-through-iap --command='df -h ~; free -h; nproc'

# Список FASTQ в датасете
gsutil ls gs://bioinformatics4/bioproject/PRJNA1247978/*.fastq.gz | wc -l
```

### Опциональные

```bash
# Запустить QC сразу для нескольких датасетов последовательно
for BP in PRJNA900592 PRJNA1247978; do
  gcloud compute ssh $VM --tunnel-through-iap --command="bash ~/run_qc.sh $BP"
done

# Очистить рабочие данные QC на VM (освободить диск) после выгрузки в GCS
gcloud compute ssh $VM --tunnel-through-iap --command='rm -rf ~/qc_work/PRJNA1247978/raw'

# Список всех R-пакетов Immcantation и их версий
gcloud compute ssh $VM --tunnel-through-iap \
  --command='Rscript -e "for(p in c(\"shazam\",\"alakazam\",\"scoper\",\"tigger\",\"dowser\")) print(packageVersion(p))"'

# Приостановить VM — НЕ забыть:
#   gcloud compute instances stop $VM --project=$PROJECT --zone=$ZONE
```

---

## 6. Known Issues

1. **SA-ключ GCP не найден** — `~/Downloads/cs-poc-...e2b53034a982.json` отсутствует.
   `lib/gcs.py` падает на fallback к ADC и env `GCS_SA_KEY_PATH`.
   С VM bucket-операции (`gcloud storage cp/ls`) работают через ADC — для пайплайна это не блокер.

2. **dowser не устанавливается на R 4.2.2** — ggtree 3.6.2 (Bioc 3.16) требует ggplot2 3.4.x,
   а на VM ggplot2 4.0.3 (`object 'check_linewidth' not found`). Каскадное понижение пакетов
   рискует сломать рабочие shazam/alakazam. **dowser отложен** — он нужен только для клониальной
   филогении (downstream), не для Stage A. Решения при необходимости: обновить R до 4.4+,
   Docker `immcantation/lab:4.8.0`, или renv-lockfile Bioc 3.16.

3. **VM ~$144/мес** — стопать `gcloud compute instances stop ...`, когда работа не ведётся.

4. **MultiQC не на PATH** — вызывать только `python3 -m multiqc` (так и сделано в `run_qc.sh`).

---

## 7. Быстрый старт (copy-paste)

```bash
# 0. Переменные
export PROJECT=cs-poc-eat9v8av8rsg0ahe0t75icw ZONE=us-central1-a VM=bcr-analysis-vm

# 1. Проверить/запустить VM
gcloud compute instances list --project=$PROJECT

# 2. Прогнать QC на датасете (фон на VM)
gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE --tunnel-through-iap \
  --command='nohup bash ~/run_qc.sh PRJNA1247978 > ~/qc.log 2>&1 & echo PID=$!'

# 3. Дождаться и забрать отчёты локально
gcloud storage cp -r gs://bioinformatics4/results/qc/PRJNA1247978/multiqc/* results/multiqc/
gcloud storage cp -r gs://bioinformatics4/results/qc/PRJNA1247978/fastqc/*  results/fastqc_PRJNA1247978/

# 4. Остановить VM
gcloud compute instances stop $VM --project=$PROJECT --zone=$ZONE
```

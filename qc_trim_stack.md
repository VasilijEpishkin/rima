# QC → Trimming → Assembly stack (rima)

Снапшот программного стека для контура Stage A1–A3 проекта rima:
**FastQC/MultiQC (QC) → fastp/pRESTO/cutadapt (trimming) → pRESTO AssemblePairs + TRUST4/IgReC (assembly/сшивание)**.

Снят с `bcr-analysis-vm` (Debian 12, GCP) 2026-07-08. По этому файлу и `setup_qc_trim_stack.sh`
можно поднять идентичный стек на любой чистой Debian 12 VM.

---

## Инвентарь (версии, зафиксированные на исходной VM)

| Инструмент | Версия | Назначение | Как проверить |
|------------|--------|-----------|---------------|
| Debian GNU/Linux | 12 (bookworm) | ОС | `cat /etc/os-release` |
| Python | 3.11.2 (системный) | среда для pip-пакетов | `python3 --version` |
| OpenJDK | 17.0.19 | нужен FastQC (Java) | `java -version` |
| build-essential | 12.9 | компиляция IgReC/TRUST4 | `dpkg -l build-essential` |
| cmake | 3.25.1 | сборка IgReC | `cmake --version` |
| fastp | 0.23.2 | all-in-one триммер (Q30, авто-адаптеры, длина, пара) | `fastp --version` |
| FastQC | 0.11.9 | перичный QC каждого файла | `fastqc --version` |
| MultiQC | 1.35 | агрегация отчётов до/после | `python3 -m multiqc --version` |
| pRESTO | 0.7.9 (2026.04.14) | MaskPrimers (праймеры), FilterSeq (Q), AssemblePairs (сшивание PE) | `MaskPrimers.py --version` |
| cutadapt | 5.2 | точная резка адаптеров/праймеров (альтернатива pRESTO для праймеров) | `cutadapt --version` |
| TRUST4 | (из git master, Jul 2026) | сборка репертуара из ридов | `~/TRUST4/run-trust4 --help` |
| IgReC | (из git master, Jul 2026) | сборка репертуара (VJFinder + кластеринг + консенсус) | `~/ig_repertoire_constructor/build/release/bin/igrec` |

### Пути на исходной VM (для справки)
- fastp: `/usr/bin/fastp`
- fastqc: `/usr/bin/fastqc`
- multiqc: `python3 -m multiqc` (pip, --break-system-packages)
- pRESTO: `/home/<user>/.local/bin/{MaskPrimers.py,FilterSeq.py,AssemblePairs.py}`
- cutadapt: `/home/<user>/.local/bin/cutadapt`
- TRUST4: `~/TRUST4/run-trust4`
- IgReC: `~/ig_repertoire_constructor/build/release/bin/`

> ВНИМАНИЕ: pip ставит исполняемые файлы в `~/.local/bin`, который НЕ в PATH по
> умолчанию. Скрипт установки добавляет его в `~/.bashrc`. Без этого
> `cutadapt`/`MaskPrimers.py` не найдутся по имени.

---

## Установка

Полностью автоматически — `bash setup_qc_trim_stack.sh` (запускать от пользователя,
не обязательно root; sudo запрашивается только для apt). Скрипт делает:

1. `apt-get update` + установка `build-essential cmake default-jdk-headless unzip pigz`.
2. pip: `multiqc`, `presto`, `cutadapt` (все с `--break-system-packages`, т.к. системный Python).
3. Клонирование и сборка **TRUST4** (`git clone` → `make`).
4. Клонирование и сборка **IgReC** (CMake → `build/release/bin`).
5. Добавление `~/.local/bin` в PATH (`~/.bashrc`).

После запуска перелогинься или `source ~/.bashrc`, затем проверь:
```
fastp --version
fastqc --version
python3 -m multiqc --version
cutadapt --version
MaskPrimers.py --version
~/TRUST4/run-trust4 --help
~/ig_repertoire_constructor/build/release/bin/igrec --help
```

---

## Пример контура на human (PRJEB40348, PE amplicon VH/VL)

### 1. Первичный QC (до тримминга)
```
fastqc -t 8 -o qc/raw/ raw/*.fastq.gz
python3 -m multiqc qc/raw/ -o qc/multiqc_raw/ -f
```

### 2. Тримминг (fastp: Q30 + авто-адаптеры + длина 250 + удаление пары)
```
fastp -i R1.fq.gz -I R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz \
      --detect_adapter_for_pe \
      -q 30 --cut_right --cut_window_size 4 --cut_mean_quality 30 \
      -l 250 -w 8 -h sample.html -j sample.json
```
- `-q 30` — дроп ридов с долей низкокачественных баз <Q30.
- `--cut_right` + `--cut_mean_quality 30` — sliding-window срезка 3'-хвоста до Q30.
- `-l 250` — если ОДИН из пары короче 250, fastp выкидывает ОБА (синхронно).
- `--detect_adapter_for_pe` — авто-детект адаптеров по перекрытию пар (не надо задавать).

### 3. Праймеры (ампликон) — опционально, отдельным шагом
fastp праймеры НЕ режет. Два варианта:
- **cutadapt** (точная резка, нужен файл/последовательность праймеров):
  ```
  cutadapt -g ^FWDPRIMER -a REVPRIMER -o trim_R1.fq.gz -p trim_R2.fq.gz clean_R1.fq.gz clean_R2.fq.gz
  ```
- **pRESTO MaskPrimers** (по проекту, режим `align`/`score`):
  ```
  MaskPrimers.py align -s clean_R1.fq.gz -p primers.fa --rc --failed prim_fail.fq.gz -o prim_R1.fq.gz
  ```
  Последовательности праймеров берутся из метаданных run (ENA/SRA) или статьи —
  FastQC их не печатает в adapter-панели; смотри панель **Overrepresented sequences**.

### 4. Q-фильтр (если режем праймеры через pRESTO, а не fastp)
```
FilterSeq.py quality -s prim_R1.fq.gz -q 30 --outname q30_R1
```

### 5. Сшивание перекрывающихся PE (pRESTO AssemblePairs)
```
AssemblePairs.py align -1 q30_R1.fq.gz -2 q30_R2.fq.gz --rc -o assembled.fq.gz
```

### 6. Сборка репертуара (НЕ trimming, но входит в «сшивание» по проекту)
- **TRUST4**: `~/TRUST4/run-trust4 -f assembled.fq.gz -o out_prefix ...`
- **IgReC**: `~/ig_repertoire_constructor/build/release/bin/igrec ...`
  (точные команды зависят от баз данных V/D/J — см. соответствующие README на VM).

### 7. Финальный QC (после тримминга) + сравнение до/после
```
fastqc -t 8 -o qc/trimmed/ clean/*.fastq.gz
python3 -m multiqc qc/ -o qc/multiqc_compare/ -f   # подхватит raw/ и trimmed/
```

---

## Заметки
- Адаптеры в PRJEB40348 = стандартный Illumina universal (виден в FastQC как
  `illumina_universal_adapter`); fastp снимает автоматически.
- Праймеры fastp НЕ снимает — только cutadapt/pRESTO MaskPrimers, и только если
  ты подал им последовательности праймеров (их нет «вшитыми» ни в одном инструменте).
- Для сравнения до/после смотри форму графиков, а не pass/warn/fail: ампликон
  закономерно «фейлит» duplication и GC (это ожидаемо, не дефект).

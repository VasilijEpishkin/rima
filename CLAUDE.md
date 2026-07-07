---

# RIMA — BCR/TCR Repertoire Analysis

## What This Is

**Benchmark project** for BCR/TCR repertoire reconstruction tools. Takes real BCR sequence data as ground truth, simulates pre-sequencing library-prep (splitting heavy/light chains into overlapping ~150bp reads), adds SHM (somatic hypermutation) if absent, then runs assembly/reconstruction with TRUST4/IgReC and evaluates accuracy.

**Goal:** Measure how well reconstruction tools perform on realistic short-read data using real biological diversity as substrate.

## Memory & Context Tools

Use all three **without asking** — they work automatically.

### claude-mem (primary memory)
Plugin `claude-mem@thedotmack` is enabled. **Semantic injection is ON.**

**At session start** — call immediately when user's first message relates to ongoing work:
```
mcp__plugin_claude-mem_mcp-search__memory_context({ projectId: "rima", query: "<topic>" })
```

**After decisions / fixes:**
```
mcp__plugin_claude-mem_mcp-search__memory_add({ projectId: "rima", content: "...", kind: "decision" })
```

### File-based memory (`/home/vasilij/workspace/rima/memory/`)
- `MEMORY.md` — index of memories
- `project_bcr_benchmark.md` — full project state

### GitNexus — Code Intelligence

Available via MCP: `gitnexus_impact()`, `gitnexus_query()`, `gitnexus_context()`
- **Before editing:** run `gitnexus_impact({target: "symbol", direction: "upstream"})`
- **Before committing:** run `gitnexus_detect_changes()`

---

## Session-Start Checklist

1. **Check VM status:** `gcloud compute instances list --project=cs-poc-eat9v8av8rsg0ahe0t75icw`
   - `bcr-analysis-vm` — e2-standard-8, us-central1-a, ~$144/month if running
   - Stop if not needed: `gcloud compute instances stop bcr-analysis-vm --project=... --zone=us-central1-a`
2. **Load memory:** `mcp__plugin_claude-mem_mcp-search__memory_context({ projectId: "rima", query: "current status" })`
3. **Check data:** `gsutil ls gs://bioinformatics4/bioproject/` — all 4 datasets should be present
4. **Verify MCP servers:** `claude mcp list` — gitnexus, tavily, bioinformatics should be connected

---

## Architecture

### Dataset Selection (Final 4)

| Accession | Organism | Size | Reads | Heavy+Light | Status |
|-----------|----------|--------|-------|-------------|--------|
| PRJEB40348 | Human | 5.92 GB | PE ~350bp | VH+VL | ✅ Downloaded (35/35 runs) |
| PRJNA848968 | Horse | 5.11 GB | PE ~250-300bp | H+L (separate libs) | ✅ Downloaded |
| PRJNA900592 | Sheep | 2.33 GB | PE 602bp/pair | IGH+IGK+IGL | ✅ Downloaded |
| PRJNA1247978 | Macaque | 18.81 GB | PE 602bp/pair | IGHV+IGKV+IGLV | ✅ Downloaded |

**Total:** ~30 GiB in `gs://bioinformatics4/bioproject/`

### Pipeline Design

**Stage A — Ground-truth reference DB:**
```
A1 FastQC/MultiQC (QC)
  ↓
A2 fastp or pRESTO MaskPrimers (adapter/primer trim)
  ↓
A3 pRESTO AssemblePairs (merge overlapping PE reads)
  ↓
A4 discard unmerged/non-productive
  ↓
A5 IgReC (VJFinder + Hamming clustering + consensus)
  ↓
A6 IgQUAST (QC of assembly)
  ↓
A7 Diversity Analyzer (SHM profile per chain)
```

**Stage B — Benchmark on simulated reads:**
```
B1 check SHM status (naive = needs synthetic SHM)
  ↓
B2 simulate realistic 150bp PE reads (InSilicoSeq)
  ↓
B3 inject SHM via SHazaM (if B1 = naive)
  ↓
B4 reconstruct with TRUST4 / IgReC
  ↓
B5 compare vs ground truth (identity, CDR3, V/J calls)
```

### Immcantation Correction (from bioSkills research)

**Critical order:** TIGGER genotyping → per-sequence `createGermlines` → `distToNearest`/`findThreshold` → clonal clustering → per-clone `createGermlines` → `observedMutations`

**Never use exact-CDR3 clonotyping for BCR** — SHM shatters one clone into hundreds of variants.

**Format:** AIRR Rearrangement TSV (lowercase snake_case, legacy Change-O UPPERCASE deprecated)

---

## GCP Infrastructure

- **Project:** `cs-poc-eat9v8av8rsg0ahe0t75icw`
- **Bucket:** `bioinformatics4` (US multi-region)
- **VM:** `bcr-analysis-vm` — e2-standard-8, 200GB pd-ssd, us-central1-a
- **Service Account:** `healthos@...` key **NOT FOUND** in ~/Downloads/ (was: `cs-poc-eat9v8av8rsg0ahe0t75icw-e2b53034a982.json`). Need to upload or locate key to enable bucket operations beyond listing.
- **Access:** IAP SSH tunnel only (no external IP per org policy)
- **NAT:** `bcr-router/bcr-nat` created for PyPI/GitHub access

---

## VM Tool Stack (bcr-analysis-vm)

**Installed:** FastQC, fastp, TRUST4, InSilicoSeq, Biopython, pRESTO, MultiQC. Также установлены базовые системные утилиты, `bowtie2`, `samtools`.

**Installed (verified 2026-07-07):**
|- IgReC: **✅ Завершено** (бинарные файлы в `~/ig_repertoire_constructor/build/release/bin/`)
|- SHazaM / Immcantation (R): shazam, alakazam, scoper, tigger, Biostrings, GenomicAlignments, IRanges, BiocManager — **✅ установлены**.
|- **dowser ❌ НЕ установлен** — единственный незавершённый R-пакет (филогения клонов; не критичен для Stage A1–A7).
---

## Active Issues

1. **SA-ключ GCP недоступен** — требуется загрузить `cs-poc-eat9v8av8rsg0ahe0t75icw-e2b53034a982.json` в ~/Downloads/ (или устранить ссылку в lib/gcs.py).
2. **dowser (R)** — единственный незавершённый R-пакет из Immcantation. Поставить (`BiocManager::install("dowser")`), если нужна клониальная филогения. Лог `~/shazam_install.log` отсутствует — установка шла без него.
3. **VM running** — costs ~$144/month, stop if not needed
4. **R-доступное место:** /usr/local/lib/R/site-library не writable; установка пакетов будет требовать sudo или другого lib-пути. Опытная работа ожидается при возобновлении установки BiocManager.

---

## Completed (as of 2026-07-07)

1. ✅ All 4 datasets downloaded to GCS (~30 GiB)
2. ✅ VM `bcr-analysis-vm` created with tools installed
3. ✅ Cloud NAT `bcr-nat` created for external access
4. ✅ TRUST4 собран (`~/TRUST4/run-trust4`)
5. ✅ IgReC собран (`~/ig_repertoire_constructor/build/release/bin/*.o` -> binaries)
6. ✅ Основные системные инструменты установлены (FastQC, fastp, bowtie2, samtools, multiqc, InSilicoSeq)
7. ✅ Python-среда готова (presto, google-cloud-storage, biopython, requests, python-dotenv)
8. ✅ Memory transferred from old session
9. ✅ MCP servers configured (gitnexus, tavily, bioinformatics, fff, serena)
10. ✅ QC (FastQC+MultiQC) выполнен для всех 4 датасетов — human, horse, sheep, **macaque** — отчёты в `results/multiqc/`
11. ✅ fff/serena/token-optimizer перерегистрированы в `~/.claude.json` (раньше были только в `settings.json`, который Claude Code для MCP не читает) — активны после рестарта Claude Code

---

## Upcoming

1. **Stage A** — запустить IgReC/BioInformatics на одном наборе данных (PRJEB40348) и записать результаты в GCS.
2. ~~SHazaM~~ — R-пакеты доступны (кроме dowser). Готов запуск Stage A5–A7 (IgReC → IgQUAST → SHM profile).
3. **Дизайн Stage B** — синтезирование данных, решение недостающего SA-ключа для записи.
4. **Обеспечение доступа к Sa-key для некоторых bucket операций (чтение/запись) если требуется.

---

## Credential / Security Rules

- **NEVER write API keys in Bash args** — visible in `ps` and shell history
- **GCP SA key** — Put the key `cs-poc-eat9v8av8rsg0ahe0t75icw-e2b53034a982.json` в ~/Downloads/
- **NVIDIA API key** — in `.env` (NVIDIA_API_KEY)

| `.mcp.json` | Project MCP servers (gitnexus, tavily, bioinformatics, fff, serena) |
| `memory/MEMORY.md` | Memory index |
| `memory/project_bcr_benchmark.md` | Full project state |
| `skills/` | Project-specific bioinformatics skills |

---

## Project Skills

| Skill | Purpose |
|-------|---------|
| `bio-read-qc-adapter-trimming` | Cutadapt/Trimmomatic adapter removal |
| `bio-read-qc-fastp-workflow` | All-in-one FASTQ preprocessing |
| `bio-read-qc-quality-reports` | FastQC/MultiQC reports |
| `bio-tcr-bcr-analysis-immcantation-analysis` | Immcantation R suite for BCR |
| `bio-tcr-bcr-vdjtools-analysis` | VDJtools diversity, clonal structure |
| `bio-tcr-bcr-repertoire-visualization` | V-J chord diagrams, spectratype, tracking |
| `bio-workflows-tcr-pipeline` | End-to-end TCR/BCR pipeline |

---

## Active Issues

1. **SHazaM installation incomplete** — check `~/shazim_install.log` on VM
2. **IgReC output format** — confirm it can produce AIRR TSV or needs conversion
3. **VM running** — costs ~$144/month, stop if not needed

---

## Key Decisions

- **4 organisms exceed minimum** — human, horse, sheep, macaque
- **Stage B simulation** — must be realistic (InSilicoSeq with error model, not naive split)
- **Germline-aware SHM** — naive chains get synthetic SHM before benchmarking
- **Exact-CDR3 forbidden for BCR** — SHM creates near-identical variants
- **AIRR format required** — lowercase snake_case, not legacy UPPERCASE

---

## Completed (as of 2026-07-06)

1. ✅ All 4 datasets downloaded to GCS (~30 GiB)
2. ✅ VM `bcr-analysis-vm` created with tools installed
3. ✅ Cloud NAT `bcr-nat` created for external access
4. ✅ Skills installed from bioSkills
5. ✅ Memory transferred from old session
6. ✅ MCP servers configured (gitnexus, tavily, bioinformatics, fff, serena)

---

## Upcoming

1. Run Stage A on PRJEB40348 (human, smallest dataset)
2. Confirm IgReC → AIRR TSV format
3. Complete SHazaM installation
4. Design Stage B simulation parameters
5. Run benchmark comparison

---

## Credential / Security Rules

- **NEVER write API keys in Bash args** — visible in `ps` and shell history
- **GCP SA key** — `~/Downloads/cs-poc-eat9v8av8rsg0ahe0t75icw-e2b53034a982.json`
- **NVIDIA API key** — in `.env` (NVIDIA_API_KEY)

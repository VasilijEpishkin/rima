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

### Dataset → Primary Source (verified 2026-07-18)

| Accession | Organism | Primary source | Verification |
|-----------|----------|----------------|-------------|
| PRJNA848968 | Horse | Rosenfeld R et al. (2022). *Centaur antibodies: Engineered chimeric equine-human recombinant antibodies.* Front. Immunol. 13:942317. **PMID 36059507**, doi:10.3389/fimmu.2022.942317 | ✅ VERIFIED — `PRJNA848968` cited in paper's Data Availability (PMC9437483); BioProject description matches abstract verbatim; submitter = Israel Institute for Biological Research |
| PRJNA900592 | Sheep | Park M, de Villavicencio Diaz TN, Lange V, Wu L, Le Bihan T, Ma B (2023). *Exploring the sheep (Ovis aries) immunoglobulin repertoire by next generation sequencing.* Mol. Immunol. 156:20–30. **PMID 36867981**, doi:10.1016/j.molimm.2023.02.008 | 🟡 Strong — BioProject description matches abstract verbatim (4 healthy sheep, IGH/IGK/IGL, NGS CDR3); submitter = Rapid Novor Inc. NCBI has no formal BioProject→PubMed link (elink empty) |
| PRJEB40348 (E-MTAB-9573) | Human | Lomakin YA et al. (2022). *Deconvolution of B cell receptor repertoire in multiple sclerosis patients revealed a delay in tBreg maturation.* Front. Immunol. 13:803229. **PMID 36052064**, doi:10.3389/fimmu.2022.803229; AND Lomakin YA et al. (2022). *Multiple Sclerosis Is Associated with Immunoglobulin Germline Gene Variation of Transitional B Cells.* Acta Naturae 14(4):84–93. **PMID 36694905**, doi:10.32607/actanaturae.11794 | 🟡 Strong — papers describe exact cohort (CD19⁺CD24ʰⁱᵍʰCD38ʰⁱᵍʰ tBreg, 5 HAMS + 4 BMS + 6 HD, VH/VL NGS); same authors/institutes (Lomakin, Gabibov, IBCh RAS / Research Center of Neurology, Moscow). **NOTE:** papers cite **E-MTAB-10859**, not E-MTAB-9573 — E-MTAB-9573 (first public 2020-09-24) is the raw-read sibling of the processed E-MTAB-10859 cited in the 2022 papers. No separate 2020–21 publication exists for this cohort. |
| PRJNA1247978 | Macaque | **No associated publication.** Data-only submission, Duke University, first public 2025-04-09 (60 runs, SRR33022240…), grant R01 AI128832. Europe PMC & NCBI elink return nothing. | ⚪ No paper — do NOT cite Rosenfeld 2019 as the "source"; it is at most a methodological antecedent, not referenced by the BioProject |

**Caveat:** NCBI `elink` (BioProject→PubMed) returns empty for ALL three NCBI projects — links rest on description/organization matches, except Horse which has a direct in-paper citation of `PRJNA848968`.

**NotebookLM cross-check (2026-07-20):** Notebook "Antibody Structure and Function for Therapeutic Engineering" (27 source files) queried to map file→dataset. Horse → `fimmu-13-942317.pdf` (✅ exact PRJNA848968 citation); Sheep → `1-s2.0-S0161589023000305-main.pdf` (✅ PRJNA900592); Human → `fimmu-13-803229.pdf` + `11794-10511-1-PB.pdf` + `ENA Browser` (🟡, cite E-MTAB-10859 not 9573); **Macaque → NO matching file exists** — NotebookLM confabulated `Multi-compartmental diversification of neutralizing antibody lineages dissected in SARS-CoV-2 spike-immunized macaques` (Mandolesi 2024, deposits ERR12544449–ERR12544478 — a *different* macaque study) and `rosenfeld2019.pdf` (primer-set methods paper, no link to PRJNA1247978). Confirms PRJNA1247978 is publication-less.

**NotebookLM MD notes (verified 2026-07-20):** User moved 4 markdown notes into notebook sources (now 31 sources total). All 4 studied:
- **Human** «Протокол секвенирования репертуаров антител человека на платформе Illumina MiSeq» → confirms **PRJEB40348 / ERP123974**; MiSeq 2×300 bp; Cheng 2011 universal set (15 VH fwd + 4 JH rev); MMLV RT; MiXCR clonotyping; FACS CD19⁺CD24ʰⁱᵍʰCD38ʰⁱᵍʰ (tBreg); SHM vs germline.
- **Horse** «Анализ антител лошади: система EquPD v2020 и профилирование MiSeq» → confirms **PRJNA848968** (explicit note line); EquPD v2020 custom panel (35 primers: 7 VH-f/2 VH-r, 7 Vκ-f/4 Vκ-r, 13 Vλ-f/2 Vλ-r); MiSeq 2×300; scFv phage display; pRESTO + IMGT/HighV-QUEST + Change-O.
- **Sheep** «Анализ иммуноглобулинового репертуара овец методом 5' RACE и NGS» → confirms **PRJNA900592** (+SUB12234127, SUB12276555); 5' RACE (SMARTer, universal anchor, no V-gene-specific fwd); MiSeq 2×300 (600 cycles), 30% PhiX; genespecific rev Sh_IGHG_rev_1 / Sh_IGKC_rev_1 / Sh_IGLC_rev_1.
- **Macaque** «Анализ B-клеточного репертуара макаки-резус: протокол и набор праймеров v2018» → **METHODS ONLY** (Rosenfeld 2019 v2018 primer set for rhesus V-genes); **NO PRJNA1247978 reference**. Confirms PRJNA1247978 publication-less; the macaque note is a primer-design reference, not a dataset description.
Note: MD notes are reproducible pipeline specs (primer sets, platforms, read lengths) — directly usable for Stage B simulation design.

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

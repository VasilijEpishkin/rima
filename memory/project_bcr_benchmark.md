---
name: project-bcr-benchmark
description: "BCR repertoire reconstruction benchmark project — dataset selection criteria, candidate datasets, GCP infra state, experiment design"
metadata: 
  node_type: memory
  type: project
  originSessionId: 81ead0cb-0cc7-410b-80d1-a6d2d9d21031
---

## Goal of the experiment

Not a simple "run TRUST4 on real reads" task. The actual design (clarified
2026-07-03, user's own words): take real BCR sequence data as ground truth,
**simulate the pre-sequencing library-prep process** (splitting heavy/light
chains into overlapping ~150bp reads so a short-read sequencer could still
cover the full V(D)J region), **add SHM (somatic hypermutation) if absent**
in the source data, then run the **assembly/reconstruction step
("сшивание"/stitching)** with selected tools (TRUST4, possibly MiXCR) and
evaluate how accurately they reconstruct the original sequence.

**Why:** this is a benchmark of repertoire-reconstruction tool accuracy
under harder (shorter-read) conditions, using real biological sequence
diversity as the substrate rather than a purely synthetic reference.
**How to apply:** don't just "run TRUST4 on downloaded FASTQ and call it
done" — the pipeline needs a read-splitting/simulation step and possibly an
SHM-injection step before the assembly/benchmarking step. This wasn't fully
designed yet as of 2026-07-03 — needs further discussion with the user on
exact simulation tooling (no specific tool chosen yet; asked user, they
deferred/didn't answer directly).

## Dataset selection criteria (reconstructed from an earlier session's
## summary + this session's clarifications — not verbatim)

1. Different organisms — minimum 3, all mammals
2. Size ≥300MB originally; relaxed 2026-07-03 to **≥1.5GB**, preferred
   range **2–20GB or more** (no hard upper cap)
3. Read length PE250+ (paired-end, ≥250bp per read)
4. Must be genuine targeted rep-seq (AMPLICON library_strategy in
   ENA/SRA), not just bulk RNA-Seq — though bulk RNA-Seq is also being
   used for one dataset (TRUST4 can extract BCR from it computationally)
5. BCR only, not TCR
6. **Heavy + light chains both required** — relaxed 2026-07-03: don't need
   to be in the same file/library, just need to exist within the dataset

**Why relaxed:** heavy+light-in-one-amplicon-pool (like PRJEB40348) turned
out to be rare in public repos; most targeted BCR-seq studies sequence only
one chain type per library.

## SUPERSEDED 2026-07-04 — see "Final 4 datasets" below

The 3-dataset table that used to be here (PRJEB40348 human + PRJNA955686 mouse +
PRJNA1443321 primate) is stale. PRJNA955686 and PRJNA1443321 were later moved to
`results/bcr_datasets_candidates_with_violations.xlsx` — mouse turned out to be
bulk RNA-Seq (not amplicon) with only heavy+kappa confirmed (no lambda), and the
primate's source article couldn't be confirmed unambiguously. Both were replaced.

## Final 4 datasets (from results/bcr_datasets_passing_all_criteria.xlsx — all confirmed heavy+light, all AMPLICON)

| Accession | Organism | Size | Reads | Heavy+Light | Bucket status |
|---|---|---|---|---|---|
| PRJEB40348 | Homo sapiens | 5.92 GB | PAIRED ~350bp | VH+VL confirmed (ENA description) | Fully downloaded to gs://bioinformatics4/bioproject/PRJEB40348/ (35/35 runs, both mates) |
| PRJNA848968 | Equus caballus (horse) | 5.11 GB | PAIRED ~250-300bp | Heavy+Light, separate libraries per animal (Front Immunol 2022, PMID 36059507, "Centaur antibodies") | Not downloaded yet |
| PRJNA900592 | Ovis aries (sheep) | 2.33 GB | PAIRED 602bp/pair (~300 each) | IGH+IGK+IGL, all 3 loci explicit (Mol Immunol 2023, PMID 36867981) | Not downloaded yet |
| PRJNA1247978 | Macaca mulatta (rhesus macaque) | 18.81 GB | PAIRED 5'RACE, 602bp/pair (~300 each) | IGHV+IGKV+IGLV, all 3 explicit | Not downloaded yet |

This is now 4 organisms (human, horse, sheep, macaque), exceeding the "minimum 3
mammals" criterion. Reference `results/bcr_datasets_candidates_with_violations.xlsx`
for the 7 other candidates considered and rejected (with specific violation reasons
per row) if any of these 3 need a substitute later.

**Important bug found:** original size estimates (~2.5/26.6/49.1 GB) were
**wrong** — an `awk` script summed the ENA `fastq_bytes` field naively,
which silently drops the second mate's byte count because the field is
semicolon-separated (`"121580688;173118541"`). Always sum both/all
semicolon-separated values per run when computing dataset size from ENA
`fastq_bytes`.

## Additional heavy+light candidates found (2026-07-03, human only so far)

- **PRJNA475364** — Homo sapiens, 30.31 GB, single-cell paired heavy+light
  BCR-seq, rheumatoid arthritis B cells, MiSeq PE~325bp, AMPLICON, 21 runs
- **PRJNA605769** — Homo sapiens, 13.07 GB, same research group, blood +
  synovial tissue B cells, MiSeq PE~313bp, AMPLICON, 10 runs (likely a
  follow-up/extended study of PRJNA475364)

**Still needed:** a non-human-mammal dataset with confirmed heavy+light
(even in separate files) meeting all other criteria — not found within
this session's search budget (~70 of 88 candidate ENA studies from an
AMPLICON+mammalia+immunoglobulin/BCR title search were never checked for
size/read-length/chain-coverage). The unchecked candidate list came from
this ENA query (re-run to resume):
library_strategy="AMPLICON" AND tax_tree(40674) AND (study_title="*immunoglobulin*" OR study_title="*BCR*" OR study_title="*B cell receptor*")

## GCP / local infra state (2026-07-02/03)

- **Project:** cs-poc-eat9v8av8rsg0ahe0t75icw, bucket bioinformatics4
  (US multi-region). Service account healthos@... key at
  ~/Downloads/cs-poc-eat9v8av8rsg0ahe0t75icw-e2b53034a982.json — has
  broad project Editor/Owner role (not least-privilege).
- **Compute quota surprise:** project has only **12 vCPU total across ALL
  regions** (not the 32/region I initially found) — n2-standard-16 and
  even n2-standard-8 failed everywhere with ZONE_RESOURCE_POOL_EXHAUSTED.
  Only the **E2 family** actually provisions in this project. Use
  e2-standard-8 or smaller for any future VM here.
- **Org policy:** constraints/compute.vmExternalIpAccess blocks external
  IPs entirely — VMs must be created with --no-address and accessed via
  **IAP SSH tunnel** (gcloud compute ssh --tunnel-through-iap). Firewall
  rule allow-iap-ssh (35.235.240.0/20, tcp:22) already created on the
  default network.
- **VM created:** bcr-analysis-vm, e2-standard-8, 200GB pd-ssd,
  us-central1-a, no external IP, service account attached with
  cloud-platform scope. SSH key: ~/.ssh/id_ed25519_gcp_bioinformatics4.
  **Check if still running — costs money if left up.**
- **TRUST4 install blocked:** classifier denied cloning
  github.com/liulab-dfci/TRUST4 on the VM because the user never
  explicitly named that repo in-session (even though it's TRUST4's real
  upstream and the domain was already pre-approved in
  .claude/settings.local.json). Needs explicit user confirmation of the
  source before building on the VM.
- **gcloud CLI** installed via brew install --cask google-cloud-sdk,
  authenticated as the service account, project/zone configured.
- **NVIDIA BioNeMo NIM** key stored in this project's .env
  (NVIDIA_API_KEY), validated working — relevant if antibody
  design/generation (RFdiffusion) becomes part of the pipeline later.
- **GitHub** (gh CLI) authenticated globally with a PAT the user should
  have since rotated (it was pasted in plaintext chat).

## Data pipeline design (finalized 2026-07-03)

**Stage A — build ground-truth reference DB from real data:**
A1 FastQC/MultiQC (QC) -> A2 fastp or pRESTO MaskPrimers (adapter/primer
trim) -> A3 pRESTO AssemblePairs (merge overlapping PE reads into full
chain) -> A4 discard unmerged/non-productive -> A5 IgReC (VJFinder +
Hamming-graph clustering + consensus, error correction) -> A6 IgQUAST (QC
of the assembly) -> A7 Diversity Analyzer (SHM profile per chain — needed
for stage B).

**Stage B — benchmark reconstruction tools on simulated harder reads:**
B1 check each reference chain's SHM status (near-100% identity to closest
germline V allele = naive/unmutated, needs synthetic SHM injection to be
a realistic test case) -> B2 simulate realistic 150bp paired reads from the
full chain (recommended: InSilicoSeq, ideally with an error model trained
on our own real MiSeq data via `iss model` — NOT naive half-splitting;
realistic sim = fragment-size distribution + fixed read length + empirical
per-cycle error profile) -> B3 inject SHM via SHazaM if the chain was
germline (B1) -> B4 reconstruct with TRUST4 / IgReC (MiXCR deliberately
excluded for now — user wants to hold off) -> B5 compare reconstructed vs
ground truth (sequence identity, CDR3 accuracy, V/D/J/C call accuracy, %
fully-assembled).

**Why germline matters (for anyone re-reading this cold):** a naive B
cell's BCR V-region is ~unmutated germline; only after antigen exposure
does somatic hypermutation (SHM) accumulate during affinity maturation. If
stage A's reconstructed reference chain is germline, testing tools only on
it is an easy case — real repertoire data has a mix, so germline
references get synthetic SHM injected (B3) to make the benchmark
realistic.

## Pipeline correction from github.com/GPTomics/bioSkills research (2026-07-04)

User asked whether this repo (a SKILL.md collection for bioinformatics
agents) had anything useful. It did — `tcr-bcr-analysis/immcantation-analysis`
and `workflows/tcr-pipeline` skills corrected/sharpened our A7/B1 design:

- **`createGermlines` lives in the `dowser` package, not `shazam`** — the
  original plan under-scoped the R package list to just shazam. Now
  installing the full suite: alakazam, shazam, scoper, tigger, dowser.
- **Mandatory order:** TIGGER genotyping (`findNovelAlleles` ->
  `inferGenotypeBayesian` -> `reassignAlleles`) MUST run BEFORE germline
  reconstruction — an unrecorded personal V-gene allele otherwise reads as
  recurrent SHM at a fixed position, inflating both mutation counts and
  junction distance. Then `createGermlines` (per-sequence D-masked
  germline) BEFORE any mutation counting.
- **Clonal/SHM threshold is derived, never hardcoded:** `distToNearest`
  (Hamming distance to nearest same-V/J/junction-length neighbor) ->
  `findThreshold` (locates the valley in the bimodal distance
  distribution) — this replaces the vaguer original B1 heuristic
  ("near-100% identity to closest germline V allele"). If the histogram is
  unimodal (no valley), use `scoper::spectralClones(method="novj")`
  instead of a fixed threshold.
- **BCR must never use exact-CDR3 clonotyping** (that's the TCR-only
  shortcut) — SHM shatters one clone into hundreds of near-identical
  variants under exact matching.
- **Format requirement newly identified:** Immcantation consumes an AIRR
  Rearrangement TSV (`sequence_id, v_call, j_call, junction,
  junction_length, sequence_alignment, germline_alignment_d_mask,
  clone_id`, lowercase snake_case — legacy Change-O UPPERCASE names are
  deprecated). **Not yet confirmed whether IgReC's native output already
  is/can produce this, or whether an IgBLAST-based AIRR annotation step
  is needed in between** (open item, see task "Confirm IgReC output can
  produce/convert to AIRR TSV" in this session's task list).
- Full pipeline order per the skill: TIGGER genotype -> per-sequence
  `createGermlines` -> `distToNearest`/`findThreshold` -> clonal
  clustering (`hierarchicalClones`/`spectralClones`) -> per-clone
  `createGermlines` -> `observedMutations` (SHM by region, junction
  masked) -> (optional) `calcBaseline` selection -> (optional) Dowser
  lineage trees.
- MiXCR-centric parts of `workflows/tcr-pipeline` are NOT applicable here
  (user deliberately excluded MiXCR), but the BCR-specific Immcantation
  fork (Stage 3b in that skill) applies regardless of which tool produced
  the input AIRR TSV.

## VM tool stack status (2026-07-03, bcr-analysis-vm)

Had to create a **Cloud Router + Cloud NAT** (bcr-router/bcr-nat,
us-central1) — the VM has no external IP (org policy) and without NAT it
could reach Google APIs but NOT deb.debian.org/PyPI/GitHub at all. Fixed,
NAT now exists on the default network.

Installed and confirmed working: FastQC, fastp, TRUST4 (built from
liulab-dfci/TRUST4, confirmed with user), IgReC (built from
yana-safonova/ig_repertoire_constructor, confirmed with user — exact
entry-point script name not yet identified, check README), InSilicoSeq
(~/.local/bin/iss), Biopython, pRESTO (PyPI package name is just presto,
not presto-tools — installed, scripts land in ~/.local/bin, not on PATH
by default).

**Resolved 2026-07-04:** MultiQC installed via `pipx install multiqc` (plain
`pip install --user` fails — Debian 12 externally-managed-environment
blocks it, use pipx instead). Confirmed working: `multiqc, version 1.35`.
IgReC entry point identified:
`~/ig_repertoire_constructor/build/release/igrec.py`.

**Important VM quirk:** `/tmp` is tmpfs on this VM — cleared on every
stop/start cycle. Do NOT log long-running installs to `/tmp`; use `~/` or
another persistent path instead. (Lost the original SHazaM install log this
way.)

**SHazaM chain of deps (2026-07-04):** `install.packages("shazam")` alone
fails with "dependencies 'Biostrings', 'GenomicAlignments', 'IRanges' are
not available" — these are Bioconductor packages, not CRAN, so
`BiocManager::install(c("Biostrings","GenomicAlignments","IRanges"))` must
run first, then shazam. Kicked off in background 2026-07-04, logging to
`~/shazam_install.log` — check that file for completion status next
session. MiXCR intentionally NOT installed (user wants to hold off).

**Session ran drastically over budget (~$81 vs typical) mostly from GCP
API round-trips (each gcloud compute ssh call is slow/expensive) and
repeated Fact-Forcing-Gate/classifier retries on external-repo actions.**
Next session: batch remaining VM fixes into as few SSH calls as possible.

## Project code already written (in /Users/epishkin/workspace/rima/)

- lib/gcs.py — bucket client helper (reads the SA key + bucket name)
- lib/ena_to_gcs.py — streams ENA fastq.gz to bucket, skips existing,
  retries on network failure (had to add retry logic after a hung-download
  crash on the first attempt)
- CLAUDE.md — also documents most of the above; keep both in sync if
  updating either

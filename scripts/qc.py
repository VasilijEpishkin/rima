#!/usr/bin/env python3
"""
qc.py — FastQC + MultiQC на FASTQ риды (сырые или уже trimmed).

Запуск:
  python3 qc.py <DATASET> [<SRC_DIR>] [--label raw|trimmed]

  <DATASET> — PRJEB40348, PRJNA848968, ...
  <SRC_DIR> — путь к FASTQ (по умолч. gs://bioinformatics4/bioproject/<DS>)
  --label   — подпапка для результата: raw (default), trimmed, pr_trimmed

Результаты: results/<DS>/qc_<label>/{fastqc, multiqc}/

Примеры:
  python3 qc.py PRJEB40348                              # QC сырых из GCS
  python3 qc.py PRJEB40348 results/PRJEB40348/trimmed/fastq --label trimmed
  python3 qc.py PRJNA848968 results/PRJNA848968/pr_trimmed/fastq --label pr_trimmed
"""

import argparse
import subprocess
import sys
from pathlib import Path


def log(msg: str) -> None:
    print(f"[{__file__}] {msg}")


def run(cmd: list[str], desc: str, **kwargs) -> subprocess.CompletedProcess:
    log(f"{desc}: {' '.join(str(c) for c in cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if res.returncode != 0:
        log(f"  FAILED (rc={res.returncode})")
        if res.stderr:
            print(res.stderr[:500], file=sys.stderr)
        sys.exit(res.returncode)
    if res.stdout:
        for line in res.stdout.strip().splitlines()[-3:]:
            log(f"  {line}")
    return res


def main() -> None:
    ap = argparse.ArgumentParser(description="FastQC + MultiQC on FASTQ reads")
    ap.add_argument("dataset", help="BioProject accession (PRJEB40348, ...)")
    ap.add_argument("src", nargs="?", default=None,
                    help="Path to FASTQ dir (default: gs://bioinformatics4/bioproject/<DS>)")
    ap.add_argument("--label", default="raw", choices=["raw", "trimmed", "pr_trimmed"],
                    help="QC label (affects output subdir name)")
    args = ap.parse_args()

    ds = args.dataset
    label = args.label
    src = args.src or f"gs://bioinformatics4/bioproject/{ds}"
    base = Path(f"results/{ds}/qc_{label}")
    fq_out = base / "fastqc"
    mq_out = base / "multiqc"
    work_dir = base / "raw"

    fq_out.mkdir(parents=True, exist_ok=True)
    mq_out.mkdir(parents=True, exist_ok=True)
    log(f"=== qc: {ds} (label={label}) ===")

    # --- 0. Получить FASTQ ---
    src_is_gcs = str(src).startswith("gs://")
    if src_is_gcs:
        work_dir.mkdir(parents=True, exist_ok=True)
        run(["gcloud", "storage", "cp", f"{src}*.fastq.gz", f"{work_dir}/"],
            f"[{ds}] gcloud cp")
        src_dir = work_dir
    else:
        src_dir = Path(src)
        if not src_dir.is_dir():
            log(f"ERROR: {src_dir} is not a directory")
            sys.exit(1)

    fastq_files = sorted(src_dir.glob("*.fastq.gz"))
    if not fastq_files:
        log(f"ERROR: no *.fastq.gz in {src_dir}")
        sys.exit(1)
    log(f"[{ds}] found {len(fastq_files)} FASTQ files")

    # --- 1. FastQC ---
    run(["fastqc", "-t", "8", "-q", "--noextract"] +
        [str(f) for f in fastq_files] + ["-o", str(fq_out)],
        f"[{ds}] FastQC")

    n_html = len(list(fq_out.glob("*_fastqc.html")))
    log(f"[{ds}] FastQC done: {n_html} reports")

    # --- 2. MultiQC ---
    run(["python3", "-m", "multiqc", str(fq_out),
         "-o", str(mq_out), "-n", f"{ds}_{label}_multiqc", "-f"],
        f"[{ds}] MultiQC")

    # --- 3. Убрать временные сырые ---
    if src_is_gcs:
        for f in work_dir.glob("*.fastq.gz"):
            f.unlink()
        work_dir.rmdir() if work_dir.exists() else None

    log(f"=== qc: {ds} COMPLETE ===")
    log(f"  FastQC:  {fq_out}/")
    log(f"  MultiQC: {mq_out}/")


if __name__ == "__main__":
    main()

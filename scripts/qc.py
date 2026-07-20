#!/usr/bin/env python3
"""
qc.py — FastQC + MultiQC на любые FASTQ риды (сырые, trimmed, pr_trimmed).

Один скрипт для оценки качества на любом этапе пайплайна.

Запуск:
  python3 qc.py <volume_path> <dataset> --label <этап>

  <volume_path>  — путь к монтированному volume (например /mnt/cd232e9d-...)
  <dataset>      — PRJEB40348, PRJNA848968, PRJNA1247978, PRJNA900592 (или любой другой)
  --label        — подпапка результата: raw / trimmed / pr_trimmed

Результаты:
  {volume_path}/results/{dataset}/qc_{label}/{fastqc, multiqc}/

Пример:
  python3 qc.py /mnt/cd232e9d-d23e-42e4-ae61-5a83964073bb PRJEB40348 --label raw
  python3 qc.py /mnt/volume PRJNA848968 --label trimmed

Скрипт ищет FASTQ в:
  --label raw        → {vol}/raw/{ds}/*.fastq.gz
  --label trimmed    → {vol}/results/{ds}/trimmed/fastq/*.trim.fastq.gz
  --label pr_trimmed → {vol}/results/{ds}/pr_trimmed/fastq/*.pr.fastq.gz
"""

import argparse
import subprocess
import sys
from pathlib import Path


def log(msg: str) -> None:
    print(f"[qc] {msg}")


def run(cmd, desc):
    log(f"{desc}: {cmd}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        log(f"  FAILED (rc={res.returncode})")
        if res.stderr:
            print(res.stderr[:500], file=sys.stderr)
        sys.exit(res.returncode)
    return res


def main():
    ap = argparse.ArgumentParser(description="FastQC + MultiQC on FASTQ reads")
    ap.add_argument("volume", help="Path to mounted volume (e.g. /mnt/cd232e9d-...)")
    ap.add_argument("dataset", help="Dataset accession (PRJEB40348, ...)")
    ap.add_argument("--label", required=True, choices=["raw", "trimmed", "pr_trimmed"],
                    help="Pipeline stage")
    args = ap.parse_args()

    vol = Path(args.volume)
    ds = args.dataset
    label = args.label

    # Определяем где искать FASTQ в зависимости от этапа
    if label == "raw":
        src_dir = vol / "raw" / ds
    elif label == "trimmed":
        src_dir = vol / "results" / ds / "trimmed" / "fastq"
    elif label == "pr_trimmed":
        src_dir = vol / "results" / ds / "pr_trimmed" / "fastq"
    else:
        log(f"ERROR: unknown label '{label}'")
        sys.exit(1)

    if not src_dir.is_dir():
        log(f"ERROR: папка {src_dir} не найдена")
        sys.exit(1)

    base = vol / "results" / ds / f"qc_{label}"
    fq_out = base / "fastqc"
    mq_out = base / "multiqc"

    fq_out.mkdir(parents=True, exist_ok=True)
    mq_out.mkdir(parents=True, exist_ok=True)

    fastq_files = sorted(src_dir.glob("*.fastq.gz"))
    if not fastq_files:
        log(f"ERROR: нет *.fastq.gz в {src_dir}")
        sys.exit(1)

    log(f"=== QC {ds} ({label}): {len(fastq_files)} FASTQ ===")

    # FastQC
    run(["fastqc", "-t", "4", "-q", "--noextract"] +
        [str(f) for f in fastq_files] + ["-o", str(fq_out)],
        "FastQC")
    log(f"  FastQC: {len(list(fq_out.glob('*_fastqc.html')))} html")

    # MultiQC
    run(["multiqc", str(fq_out), "-o", str(mq_out),
         "-n", f"{ds}_{label}_multiqc", "-f"],
        "MultiQC")
    log(f"  MultiQC: {len(list(mq_out.glob('*.html')))} html")

    log(f"=== QC {ds} ({label}) COMPLETE ===")
    log(f"  FastQC:  {fq_out}/")
    log(f"  MultiQC: {mq_out}/")


if __name__ == "__main__":
    main()

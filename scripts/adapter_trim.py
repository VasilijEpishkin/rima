#!/usr/bin/env python3
"""
adapter_trim.py — cutadapt (Illumina адаптер) + fastp (Q30, minlen 250).
Только тримминг адаптеров + фильтрация. БЕЗ FastQC/MultiQC.

Запуск:
  python3 adapter_trim.py <volume_path> <dataset>

  <volume_path>  — путь к монтированному volume
  <dataset>      — PRJEB40348, PRJNA848968, ...

Вход:   {volume_path}/raw/{dataset}/*_{1,2}.fastq.gz
Выход:  {volume_path}/results/{dataset}/trimmed/{fastq, fastp_reports}/

Пример:
  python3 adapter_trim.py /mnt/cd232e9d-... PRJEB40348
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ILL_ADAPTER = "AGATCGGAAGAGCGGTTCAG"
LOG = None  # будет файл


def log(msg):
    print(f"[adapter_trim] {msg}")


def run(cmd, desc, logfile=None):
    log(f"{desc}: {' '.join(str(c) for c in cmd[:5])} ...")
    with open(logfile, "a") if logfile else open("/dev/null", "w") as lf:
        res = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT)
    if res.returncode != 0:
        log(f"  FAILED (rc={res.returncode})")
        sys.exit(res.returncode)
    return res


def main():
    ap = argparse.ArgumentParser(description="Adapter trim + filter (cutadapt + fastp)")
    ap.add_argument("volume", help="Path to mounted volume")
    ap.add_argument("dataset", help="Dataset accession")
    args = ap.parse_args()

    vol = Path(args.volume)
    ds = args.dataset
    src_dir = vol / "raw" / ds
    base = vol / "results" / ds / "trimmed"
    cut_dir = base / "cutadapt"
    trim_dir = base / "fastq"
    fpr_dir = base / "fastp_reports"

    if not src_dir.is_dir():
        log(f"ERROR: {src_dir} не найден")
        sys.exit(1)

    cut_dir.mkdir(parents=True, exist_ok=True)
    trim_dir.mkdir(parents=True, exist_ok=True)
    fpr_dir.mkdir(parents=True, exist_ok=True)

    # Собираем пары
    pairs = sorted(set(
        f.name.rsplit("_", 1)[0]
        for f in src_dir.glob("*.fastq.gz")
    ))
    log(f"=== adapter_trim: {ds}, {len(pairs)} pairs ===")
    if not pairs:
        log("ERROR: no pairs found")
        sys.exit(1)

    for base_name in pairs:
        r1 = src_dir / f"{base_name}_1.fastq.gz"
        r2 = src_dir / f"{base_name}_2.fastq.gz"
        if not r1.exists() or not r2.exists():
            log(f"  WARN: {base_name} — missing pair, skip")
            continue

        out_r1 = trim_dir / f"{base_name}_1.trim.fastq.gz"
        if out_r1.exists():
            log(f"  {base_name} already done, skip")
            continue

        # cutadapt
        c1 = cut_dir / f"{base_name}_1.cut.fastq.gz"
        c2 = cut_dir / f"{base_name}_2.cut.fastq.gz"
        log(f"  [{base_name}] cutadapt ...")
        run(["cutadapt",
             "-a", ILL_ADAPTER, "-A", ILL_ADAPTER,
             "--compression-level", "1",
             "-o", str(c1), "-p", str(c2),
             str(r1), str(r2)],
            f"  [{base_name}] cutadapt",
            logfile=fpr_dir / f"{base_name}.cutadapt.log")

        # fastp: Q30 + minlen 250
        log(f"  [{base_name}] fastp ...")
        run(["fastp",
             "-i", str(c1), "-I", str(c2),
             "-o", str(out_r1), "-O", str(trim_dir / f"{base_name}_2.trim.fastq.gz"),
             "--detect_adapter_for_pe", "-q", "30", "-l", "250", "-w", "4",
             "-h", str(fpr_dir / f"{base_name}.html"),
             "-j", str(fpr_dir / f"{base_name}.json")],
            f"  [{base_name}] fastp",
            logfile=fpr_dir / f"{base_name}.fastp.log")

        # чистим промежуточные cutadapt
        c1.unlink(missing_ok=True)
        c2.unlink(missing_ok=True)

    # убрать пустой cutadapt/
    if cut_dir.exists():
        shutil.rmtree(cut_dir, ignore_errors=True)

    n = len(list(trim_dir.glob("*.trim.fastq.gz")))
    log(f"=== adapter_trim: {ds} COMPLETE ({n} trimmed FASTQ) ===")
    log(f"  trimmed:  {trim_dir}/")
    log(f"  fastp QC: {fpr_dir}/")


if __name__ == "__main__":
    main()

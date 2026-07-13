#!/usr/bin/env python3
"""
adapter_trim.py — cutadapt (Illumina адаптер) + fastp (Q30, minlen) для ОДНОЙ пары ридов.
БЕЗ FastQC/MultiQC — это отдельный шаг (qc.py).

Запуск:
  python3 adapter_trim.py <DATASET> [<SRC_DIR>]

  <DATASET> — PRJEB40348, PRJNA848968, ...
  <SRC_DIR> — путь к сырым FASTQ (по умолч. gs://bioinformatics4/bioproject/<DS>)

Результаты: results/<DS>/trimmed/{fastq, fastp_reports}/

Примеры:
  python3 adapter_trim.py PRJEB40348
  python3 adapter_trim.py PRJNA848968 /path/to/raw/fastqs
"""

import argparse
import subprocess
import sys
from pathlib import Path


ILLUMINA_ADAPTER = "AGATCGGAAGAGCGGTTCAG"  # TruSeq/Nextera универсальный
QC = "-q 30"
MINLEN = "-l 250"


def log(msg: str) -> None:
    print(f"[{__file__}] {msg}")


def run(cmd: list[str], desc: str, logfile: Path | None = None) -> subprocess.CompletedProcess:
    log(f"{desc}: {' '.join(str(c) for c in cmd)}")
    kwargs = {"capture_output": True, "text": True}
    if logfile:
        kwargs["stdout"] = open(logfile, "a")
        kwargs["stderr"] = subprocess.STDOUT
        res = subprocess.run(cmd, **kwargs)
        kwargs["stdout"].close()
    else:
        res = subprocess.run(cmd, **kwargs)
    if res.returncode != 0:
        log(f"  FAILED (rc={res.returncode})")
        if res.stderr:
            print(res.stderr[:300], file=sys.stderr)
        sys.exit(res.returncode)
    return res


def main() -> None:
    ap = argparse.ArgumentParser(description="Adapter trim (cutadapt + fastp) without QC")
    ap.add_argument("dataset", help="BioProject accession")
    ap.add_argument("src", nargs="?", default=None,
                    help="Path to raw FASTQs (default: gs://bioinformatics4/bioproject/<DS>)")
    args = ap.parse_args()

    ds = args.dataset
    src = args.src or f"gs://bioinformatics4/bioproject/{ds}"
    base = Path(f"results/{ds}/trimmed")
    cut_dir = base / "cutadapt"       # intermediate, удаляется
    trim_dir = base / "fastq"        # финальные trimmed
    fpr_dir = base / "fastp_reports"  # fastp JSON/HTML
    work_dir = base / "raw_work"      # сырые, если из GCS

    cut_dir.mkdir(parents=True, exist_ok=True)
    trim_dir.mkdir(parents=True, exist_ok=True)
    fpr_dir.mkdir(parents=True, exist_ok=True)

    log(f"=== adapter_trim: {ds} ===")

    # --- 0. Получить сырые FASTQ ---
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

    # --- 1. Собрать пары ---
    pairs: set[str] = set()
    for f in sorted(src_dir.glob("*.fastq.gz")):
        stem = f.stem.replace(".fastq", "")  # *_1.fastq.gz → *_1
        base_name = stem.rsplit("_", 1)[0]    # *_1 → *
        pairs.add(base_name)
    pairs = sorted(pairs)
    log(f"[{ds}] found {len(pairs)} pairs")
    if not pairs:
        log("ERROR: no pairs found")
        sys.exit(1)

    # --- 2. cutadapt + fastp на каждую пару ---
    for base_name in pairs:
        r1 = src_dir / f"{base_name}_1.fastq.gz"
        r2 = src_dir / f"{base_name}_2.fastq.gz"
        if not r1.exists() or not r2.exists():
            log(f"  WARN: {base_name} — missing pair, skip")
            continue

        # skip if already done
        out_r1 = trim_dir / f"{base_name}_1.trim.fastq.gz"
        if out_r1.exists():
            log(f"  {base_name} already done, skip")
            continue

        # --- cutadapt ---
        c1 = cut_dir / f"{base_name}_1.cut.fastq.gz"
        c2 = cut_dir / f"{base_name}_2.cut.fastq.gz"
        log(f"  [{base_name}] cutadapt ...")
        run([
            "cutadapt",
            "-a", ILLUMINA_ADAPTER, "-A", ILLUMINA_ADAPTER,
            "--compression-level", "1",
            "-o", str(c1), "-p", str(c2),
            str(r1), str(r2),
        ], f"  [{base_name}] cutadapt", logfile=fpr_dir / f"{base_name}.cutadapt.log")

        # --- fastp ---
        log(f"  [{base_name}] fastp ...")
        run([
            "fastp",
            "-i", str(c1), "-I", str(c2),
            "-o", str(out_r1), "-O", str(trim_dir / f"{base_name}_2.trim.fastq.gz"),
            "--detect_adapter_for_pe", QC, MINLEN, "-w", "8",
            "-h", str(fpr_dir / f"{base_name}.html"),
            "-j", str(fpr_dir / f"{base_name}.json"),
        ], f"  [{base_name}] fastp", logfile=fpr_dir / f"{base_name}.fastp.log")

        # чистим intermediate
        c1.unlink(missing_ok=True)
        c2.unlink(missing_ok=True)

    # убрать пустой cutadapt/
    try:
        cut_dir.rmdir()
    except OSError:
        pass

    # убрать сырые (если качали из GCS)
    if src_is_gcs:
        for f in work_dir.glob("*.fastq.gz"):
            f.unlink()
        try:
            work_dir.rmdir()
        except OSError:
            pass

    n = len(list(trim_dir.glob("*.trim.fastq.gz")))
    log(f"=== adapter_trim: {ds} COMPLETE ({n} trimmed FASTQ) ===")
    log(f"  trimmed:  {trim_dir}/")
    log(f"  fastp QC: {fpr_dir}/")


if __name__ == "__main__":
    main()

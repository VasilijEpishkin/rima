#!/usr/bin/env python3
"""
primer_trim.py — MaskPrimers (V-праймер) + fastp (Q30, minlen 200) для ОДНОЙ пары ридов.
Для human (PRJEB40348) и horse (PRJNA848968). БЕЗ FastQC/MultiQC.

Вход: adapter-trimmed .fastq.gz (из adapter_trim.py)
Выход: results/<DS>/pr_trimmed/{fastq, fastp_reports}/

Запуск:
  python3 primer_trim.py <DATASET> [<SRC_DIR>]

  <DATASET>  — PRJEB40348 (human) или PRJNA848968 (horse)
  <SRC_DIR>  — путь к adapter-trimmed FASTQ (по умолч. results/<DS>/trimmed/fastq/)

Пример:
  python3 primer_trim.py PRJEB40348
  python3 primer_trim.py PRJNA848968 /custom/path/to/trimmed/fastqs
"""

import argparse
import subprocess
import sys
from pathlib import Path


PRIMER_FILES = {
    "PRJEB40348": "primer_refs/human_primers.fasta",
    "PRJNA848968": "primer_refs/horse_primers.fasta",
}
PAR = 4       # параллельных пар
NPROC = 4     # потоков на MaskPrimers


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


def process_pair(base_name: str, src_dir: Path, tmp_dir: Path, fpr_dir: Path,
                 primers_fasta: str) -> None:
    """Обработать одну пару: MaskPrimers → fastp."""
    r1 = src_dir / f"{base_name}_1.trim.fastq.gz"
    r2 = src_dir / f"{base_name}_2.trim.fastq.gz"
    if not r1.exists():
        log(f"    skip {base_name} (no R1)")
        return

    # MaskPrimers output (intermediate, удаляется после fastp)
    mp1 = tmp_dir / f"{base_name}_1.pr_primers-pass.fastq.gz"
    mp2 = tmp_dir / f"{base_name}_2.pr_primers-pass.fastq.gz"

    # fastp output (final)
    m1 = tmp_dir / f"{base_name}_1.pr.fastq.gz"
    m2 = tmp_dir / f"{base_name}_2.pr.fastq.gz"

    # 1) MaskPrimers ALIGN
    run([
        "MaskPrimers.py", "align",
        "-s", str(r1), "-p", primers_fasta,
        "--mode", "cut", "--maxerror", "0.2", "--nproc", str(NPROC), "--maxlen", "50",
        "--outdir", str(tmp_dir), "--outname", f"{base_name}_1.pr",
    ], f"  [{base_name}] MaskPrimers R1", logfile=fpr_dir / f"{base_name}_R1.maskprimer.log")

    run([
        "MaskPrimers.py", "align",
        "-s", str(r2), "-p", primers_fasta,
        "--mode", "cut", "--maxerror", "0.2", "--nproc", str(NPROC), "--maxlen", "50",
        "--outdir", str(tmp_dir), "--outname", f"{base_name}_2.pr",
    ], f"  [{base_name}] MaskPrimers R2", logfile=fpr_dir / f"{base_name}_R2.maskprimer.log")

    # 2) fastp: Q30 + minlen 200 (риды после праймера короче)
    run([
        "fastp",
        "-i", str(mp1), "-I", str(mp2),
        "-o", str(m1), "-O", str(m2),
        "-q", "30", "-l", "200", "--detect_adapter_for_pe",
        "-w", str(NPROC),
        "-h", str(fpr_dir / f"{base_name}.html"),
        "-j", str(fpr_dir / f"{base_name}.json"),
    ], f"  [{base_name}] fastp", logfile=fpr_dir / f"{base_name}.fastp.log")

    # чистим intermediate
    mp1.unlink(missing_ok=True)
    mp2.unlink(missing_ok=True)
    log(f"  [{base_name}] done")


def main() -> None:
    ap = argparse.ArgumentParser(description="V-primer trimming (MaskPrimers + fastp) without QC")
    ap.add_argument("dataset", help="BioProject accession (PRJEB40348 or PRJNA848968)")
    ap.add_argument("src", nargs="?", default=None,
                    help="Path to adapter-trimmed FASTQs (default: results/<DS>/trimmed/fastq/)")
    args = ap.parse_args()

    ds = args.dataset

    if ds not in PRIMER_FILES:
        log(f"ERROR: {ds} не требует V-праймерного тримминга (macaque/sheep = 5'RACE)")
        sys.exit(2)

    primers_fasta = PRIMER_FILES[ds]
    if not Path(primers_fasta).exists():
        log(f"ERROR: {primers_fasta} не найден (клонируй репо или скопируй primer_refs/)")
        sys.exit(3)

    src = args.src or f"results/{ds}/trimmed/fastq"
    src_dir = Path(src)
    if not src_dir.is_dir():
        log(f"ERROR: {src_dir} не найден (запусти adapter_trim.py сначала)")
        sys.exit(3)

    base = Path(f"results/{ds}/pr_trimmed")
    fpr_dir = base / "fastp_reports"
    tmp_dir = base / "fastq"  # промежуточные + итоговые

    fpr_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    log(f"=== primer_trim: {ds} (primers: {Path(primers_fasta).name}) ===")

    # --- собрать пары ---
    pairs = sorted(set(
        f.stem.replace("_1.trim.fastq", "").replace("_2.trim.fastq", "")
        for f in src_dir.glob("*_1.trim.fastq.gz")
    ))
    log(f"[{ds}] found {len(pairs)} pairs")

    if not pairs:
        log(f"ERROR: нет пар в {src_dir}")
        sys.exit(3)

    # --- обработать параллельно (как xargs -P) ---
    from concurrent.futures import ProcessPoolExecutor, as_completed

    with ProcessPoolExecutor(max_workers=PAR) as pool:
        futures = {
            pool.submit(process_pair, p, src_dir, tmp_dir, fpr_dir, primers_fasta): p
            for p in pairs
        }
        for future in as_completed(futures):
            p = futures[future]
            try:
                future.result()
            except Exception as e:
                log(f"  ERROR: {p} — {e}")

    log(f"=== primer_trim: {ds} COMPLETE ===")
    log(f"  fastq:        {tmp_dir}/")
    log(f"  fastp report: {fpr_dir}/")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
primer_trim.py — ТОЛЬКО MaskPrimers (V-праймерный тримминг). БЕЗ fastp, БЕЗ фильтрации.

Для датасетов с V-праймерами: human PRJEB40348, horse PRJNA848968.
Для macaque (PRJNA1247978) и sheep (PRJNA900592) НЕ ИСПОЛЬЗОВАТЬ — у них 5'RACE.

Запуск:
  python3 primer_trim.py <volume_path> <dataset>

  <volume_path>  — путь к монтированному volume
  <dataset>      — PRJEB40348 или PRJNA848968

Вход:   {volume_path}/results/{dataset}/trimmed/fastq/*.trim.fastq.gz
Выход:  {volume_path}/results/{dataset}/pr_trimmed/{fastq, maskprimer_logs}/

Пример:
  python3 primer_trim.py /mnt/cd232e9d-... PRJEB40348
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


PRIMER_FILES = {
    "PRJEB40348": "primer_refs/human_primers.fasta",
    "PRJNA848968": "primer_refs/horse_primers.fasta",
}
NPROC = 4  # потоков на один MaskPrimers


def log(msg):
    print(f"[primer_trim] {msg}")


def run(cmd, desc, logfile=None):
    log(f"{desc}: {' '.join(str(c) for c in cmd[:6])} ...")
    with open(logfile, "a") if logfile else open("/dev/null", "w") as lf:
        res = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT)
    if res.returncode != 0:
        log(f"  FAILED (rc={res.returncode})")
        sys.exit(res.returncode)
    return res


def main():
    ap = argparse.ArgumentParser(description="V-primer trimming ONLY (MaskPrimers)")
    ap.add_argument("volume", help="Path to mounted volume")
    ap.add_argument("dataset", help="Dataset: PRJEB40348 or PRJNA848968")
    args = ap.parse_args()

    vol = Path(args.volume)
    ds = args.dataset

    if ds not in PRIMER_FILES:
        log(f"ERROR: {ds} не требует V-праймерного тримминга (5'RACE)")
        sys.exit(2)

    primers = PRIMER_FILES[ds]
    if not Path(primers).exists():
        log(f"ERROR: {primers} не найден. Скопируй primer_refs/ из репо в текущую папку")
        sys.exit(3)

    src_dir = vol / "results" / ds / "trimmed" / "fastq"
    if not src_dir.is_dir():
        log(f"ERROR: {src_dir} не найден (запусти adapter_trim сначала)")
        sys.exit(3)

    base = vol / "results" / ds / "pr_trimmed"
    out_dir = base / "fastq"
    logs_dir = base / "maskprimer_logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    # Собираем пары
    pairs = sorted(set(
        f.name.replace("_1.trim.fastq.gz", "").replace("_2.trim.fastq.gz", "")
        for f in src_dir.glob("*.trim.fastq.gz")
    ))
    log(f"=== primer_trim: {ds}, {len(pairs)} pairs ===")
    if not pairs:
        log("ERROR: нет пар")
        sys.exit(3)

    # Последовательная обработка (4 CPU, не плодим гонку)
    for base_name in pairs:
        r1 = src_dir / f"{base_name}_1.trim.fastq.gz"
        r2 = src_dir / f"{base_name}_2.trim.fastq.gz"
        if not r1.exists():
            log(f"  skip {base_name} (no R1)")
            continue

        log(f"  [{base_name}] MaskPrimers R1...")
        run(["MaskPrimers.py", "align",
             "-s", str(r1), "-p", primers,
             "--mode", "cut", "--maxerror", "0.2",
             "--nproc", str(NPROC), "--maxlen", "50",
             "--outdir", str(out_dir), "--outname", f"{base_name}_1.pr"],
            f"  [{base_name}] MaskPrimers R1",
            logfile=logs_dir / f"{base_name}_R1.maskprimers.log")

        log(f"  [{base_name}] MaskPrimers R2...")
        run(["MaskPrimers.py", "align",
             "-s", str(r2), "-p", primers,
             "--mode", "cut", "--maxerror", "0.2",
             "--nproc", str(NPROC), "--maxlen", "50",
             "--outdir", str(out_dir), "--outname", f"{base_name}_2.pr"],
            f"  [{base_name}] MaskPrimers R2",
            logfile=logs_dir / f"{base_name}_R2.maskprimers.log")

        log(f"  [{base_name}] done")

    # MaskPrimers пишет *_primers-pass.fastq.gz. Переименуем в *.pr.fastq.gz
    for f in sorted(out_dir.glob("*_primers-pass.fastq.gz")):
        new_name = f.name.replace("_primers-pass", "")
        f.rename(out_dir / new_name)

    n = len(list(out_dir.glob("*.pr.fastq.gz"))) // 2
    log(f"=== primer_trim: {ds} COMPLETE ({n} pairs) ===")
    log(f"  fastq:  {out_dir}/")
    log(f"  logs:   {logs_dir}/")


if __name__ == "__main__":
    main()

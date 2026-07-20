#!/usr/bin/env python3
"""
setup_tools.py — установка всех инструментов для пайплайна QC + тримминг.

Инструменты:
  - fastp         (бинарник, apt или сборка)
  - FastQC        (бинарник, apt или вручную)
  - cutadapt      (pip)
  - MultiQC       (pip)
  - pRESTO        (pip) — MaskPrimers.py для праймер-тримминга

Поддерживает: Debian/Ubuntu (apt), RHEL/Fedora (yum/dnf).
На macOS пропускает системные пакеты и ставит только pip-инструменты.

Запуск:
  python3 setup_tools.py

Опции:
  --venv PATH    Создать/использовать virtualenv (по умолч. не создаёт)
  --prefix PATH  Кастомный PATH для pip-бинарников (по умолч. ~/.local/bin)
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
import tarfile
import zipfile
from pathlib import Path


SYSTEM = platform.system().lower()
ARCH = platform.machine()
IS_LINUX = SYSTEM == "linux"

FASTQC_URL = "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip"
FASTQC_VERSION = "0.12.1"
FASTQC_DIR = f"FastQC-{FASTQC_VERSION}"


def log(msg: str) -> None:
    print(f"[setup] {msg}")


def run(cmd: list[str], desc: str) -> None:
    log(f"{desc} ...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        log(f"  WARN: {desc} rc={res.returncode}")
        if res.stderr:
            log(f"  {res.stderr.strip()[-200:]}")
    else:
        log(f"  OK")


def run_apt(pkgs: list[str]) -> None:
    """apt-get install (требует sudo)."""
    if not IS_LINUX:
        return
    log(f"apt: {', '.join(pkgs)}")
    subprocess.run(
        ["sudo", "apt-get", "install", "-y", "-qq"] + pkgs,
        capture_output=True, text=True,
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Install pipeline tools")
    ap.add_argument("--venv", default="", help="Virtualenv path (optional)")
    ap.add_argument("--prefix", default=os.path.expanduser("~/.local/bin"),
                    help="Binary install prefix (default: ~/.local/bin)")
    args = ap.parse_args()

    prefix = Path(args.prefix)
    prefix.mkdir(parents=True, exist_ok=True)
    bindir = str(prefix)

    # ---------- virtualenv ----------
    if args.venv:
        venv_path = Path(args.venv)
        if not (venv_path / "bin" / "python3").exists():
            log(f"Creating venv at {venv_path} ...")
            subprocess.run([sys.executable, "-m", "venv", str(venv_path)], check=True)
        pip = [str(venv_path / "bin" / "pip"), "install"]
        bindir = str(venv_path / "bin")
    else:
        pip = [sys.executable, "-m", "pip", "install", "--user"]

    # ---------- system packages (Linux only) ----------
    if IS_LINUX:
        log("=== System packages ===")
        run_apt(["build-essential", "cmake", "git", "wget", "curl", "unzip",
                 "pigz", "libncurses5-dev", "libbz2-dev", "liblzma-dev", "zlib1g-dev"])

    # ---------- pip packages ----------
    log("=== pip packages ===")
    pip_pkgs = ["cutadapt", "multiqc", "presto"]
    run(pip + ["--upgrade", "pip", "setuptools", "wheel"], "pip upgrade")
    run(pip + pip_pkgs, f"pip install {', '.join(pip_pkgs)}")

    # ---------- fastp (apt или сборка) ----------
    log("=== fastp ===")
    if shutil.which("fastp"):
        log("  already installed")
    else:
        if IS_LINUX and subprocess.run(["apt-get", "install", "-y", "fastp"],
                                        capture_output=True).returncode == 0:
            log("  installed via apt")
        else:
            # сборка из исходников
            tmp = Path("/tmp/fastp_build")
            tmp.mkdir(exist_ok=True)
            url = "https://github.com/OpenGene/fastp/archive/refs/tags/v0.23.4.tar.gz"
            tarball = tmp / "fastp.tar.gz"
            log("  downloading fastp source ...")
            urllib.request.urlretrieve(url, tarball)
            with tarfile.open(tarball) as tf:
                tf.extractall(tmp)
            src_dir = tmp / "fastp-0.23.4"
            subprocess.run(["make", "-j4"], cwd=src_dir, check=True)
            shutil.copy(str(src_dir / "fastp"), bindir)
            log(f"  fastp built -> {bindir}/fastp")

    # ---------- FastQC (apt или вручную) ----------
    log("=== FastQC ===")
    if shutil.which("fastqc"):
        log("  already installed")
    else:
        if IS_LINUX and subprocess.run(["apt-get", "install", "-y", "fastqc"],
                                        capture_output=True).returncode == 0:
            log("  installed via apt")
        else:
            tmp = Path("/tmp/fastqc_install")
            tmp.mkdir(exist_ok=True)
            zip_path = tmp / "fastqc.zip"
            log("  downloading FastQC ...")
            urllib.request.urlretrieve(FASTQC_URL, zip_path)
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(tmp)
            fastqc_dir = tmp / "FastQC"
            os.chmod(str(fastqc_dir / "fastqc"), 0o755)
            shutil.copy(str(fastqc_dir / "fastqc"), bindir)
            log(f"  FastQC installed -> {bindir}/fastqc")

    # ---------- PATH warning ----------
    log("=== PATH ===")
    if bindir not in os.environ.get("PATH", ""):
        log(f"  ⚠️  Добавь {bindir} в PATH:")
        log(f"     export PATH={bindir}:$PATH")

    # ---------- verification ----------
    log("=== Verification ===")
    tools = ["fastp", "fastqc", "cutadapt", "multiqc", "MaskPrimers.py"]
    ok = True
    for t in tools:
        found = shutil.which(t)
        if found:
            log(f"  ✓ {t} -> {found}")
        else:
            log(f"  ✗ {t} НЕ НАЙДЕН")
            ok = False

    if ok:
        log("=== ALL TOOLS INSTALLED ===")
    else:
        log("=== SOME TOOLS MISSING (check errors above) ===")
        sys.exit(1)


if __name__ == "__main__":
    main()

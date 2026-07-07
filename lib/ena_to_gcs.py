"""Stream ENA FASTQ files straight into the project's GCS bucket.

For each run in a `filereport?...&fields=run_accession,fastq_ftp,fastq_bytes`
TSV (from ENA Portal API), downloads each fastq.gz to a local temp file,
uploads it to gs://bioinformatics4/bioproject/<accession>/<filename>, then
deletes the local copy. Idempotent: skips files already present in the
bucket (checked by name + size).

Usage:
    python lib/ena_to_gcs.py PRJNA955686 /tmp/prjna955686_filereport.tsv
"""

import csv
import sys
import tempfile
import time
from pathlib import Path

import requests
from google.cloud.storage.retry import DEFAULT_RETRY

from lib.gcs import bucket

CHUNK = 8 * 1024 * 1024
UPLOAD_TIMEOUT = 600  # slow uplink observed (~500KB/s) needs more than the 120s default
MAX_ATTEMPTS = 5


def existing_blobs(prefix):
    return {b.name.rsplit("/", 1)[-1]: b.size for b in bucket().list_blobs(prefix=prefix)}


def _download_and_upload_once(https_url, dest_blob_name):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        with requests.get(https_url, stream=True, timeout=120) as r:
            r.raise_for_status()
            with open(tmp_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=CHUNK):
                    f.write(chunk)
        blob = bucket().blob(dest_blob_name)
        blob.upload_from_filename(
            str(tmp_path), timeout=UPLOAD_TIMEOUT, retry=DEFAULT_RETRY
        )
        return tmp_path.stat().st_size
    finally:
        tmp_path.unlink(missing_ok=True)


def download_and_upload(url, dest_blob_name, expected_size, existing):
    fname = dest_blob_name.rsplit("/", 1)[-1]
    if existing.get(fname) == expected_size:
        print(f"  skip (already in bucket): {fname}")
        return

    https_url = "https://" + url if not url.startswith("http") else url
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            size = _download_and_upload_once(https_url, dest_blob_name)
            print(f"  uploaded: {dest_blob_name} ({size} bytes)")
            return
        except Exception as e:
            wait = min(60, 5 * attempt)
            print(f"  attempt {attempt}/{MAX_ATTEMPTS} failed for {fname}: {e} — retrying in {wait}s")
            time.sleep(wait)
    print(f"  GAVE UP on {fname} after {MAX_ATTEMPTS} attempts")


def main():
    accession, tsv_path = sys.argv[1], sys.argv[2]
    prefix = f"bioproject/{accession}/"
    existing = existing_blobs(prefix)
    print(f"{len(existing)} files already in gs://bioinformatics4/{prefix}")

    with open(tsv_path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        rows = list(reader)

    for i, row in enumerate(rows, 1):
        run = row["run_accession"]
        urls = row["fastq_ftp"].split(";")
        sizes = [int(s) for s in row["fastq_bytes"].split(";")]
        print(f"[{i}/{len(rows)}] {run}")
        for url, size in zip(urls, sizes):
            fname = url.rsplit("/", 1)[-1]
            download_and_upload(url, f"{prefix}{fname}", size, existing)


if __name__ == "__main__":
    main()

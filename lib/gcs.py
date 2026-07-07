"""Thin helper around the project's GCS bucket (see CLAUDE.md for details).

Usage:
    from lib.gcs import bucket
    bucket().blob("PRJNA955686/sample1.fastq.gz").upload_from_filename("...")
    for b in bucket().list_blobs(prefix="PRJNA955686/"):
        print(b.name, b.size)
"""

import os
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import storage
from google.oauth2 import service_account

PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_ROOT / ".env")

KEY_PATH = os.path.expanduser(
    "~/Downloads/cs-poc-eat9v8av8rsg0ahe0t75icw-e2b53034a982.json"
)
BUCKET_NAME = "bioinformatics4"

_client = None


def client() -> storage.Client:
    global _client
    if _client is None:
        creds = service_account.Credentials.from_service_account_file(KEY_PATH)
        _client = storage.Client(credentials=creds, project=creds.project_id)
    return _client


def bucket(name: str = BUCKET_NAME) -> storage.Bucket:
    return client().bucket(name)

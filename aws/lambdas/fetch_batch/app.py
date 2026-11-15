"""Lambda fetch_batch (app.handler): download the 4 NYC TLC trip files for the month to S3 raw

input : {"year_month": "2024-01", "force_download": false, ...}
output: {**input, "run_id": "...", "fetch": {...}}

- idempotent: files already in S3 are skipped (unless force_download)
- streams HTTP straight to S3 (multipart), no /tmp staging -> handles the ~500MB HVFHV file
- HTTP status not 200 -> raise SourceNotAvailable (no broken file written)
- checks size matches Content-Length and the 'PAR1' magic bytes
- stores lineage (source_url, fetched_at) in S3 object metadata
"""
import json
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

from boto3.s3.transfer import TransferConfig

from nyc_common import BUCKET, TAXI_TYPES, object_exists, raw_key, require_month, s3

BASE_URL = "https://d37ci6vzurychx.cloudfront.net"
TRANSFER = TransferConfig(multipart_chunksize=64 * 1024 * 1024, max_concurrency=4)


class SourceNotAvailable(Exception):
    pass


class FetchValidationError(Exception):
    pass


def download(url, key, force):
    if not force and object_exists(key):
        return {"status": "skipped", "key": key}
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (cs341-nyc-taxi-pipeline)"})
    try:
        resp = urllib.request.urlopen(req, timeout=60)
    except urllib.error.HTTPError as e:
        raise SourceNotAvailable(f"{url} -> HTTP {e.code}") from e
    except urllib.error.URLError as e:
        raise SourceNotAvailable(f"{url} -> {e.reason}") from e

    expected = resp.headers.get("Content-Length")
    fetched_at = datetime.now(timezone.utc).isoformat()
    # if it fails midway the multipart upload is aborted -> no partial file in S3
    s3.upload_fileobj(resp, BUCKET, key, Config=TRANSFER,
                      ExtraArgs={"Metadata": {"source_url": url, "fetched_at": fetched_at}})
    size = s3.head_object(Bucket=BUCKET, Key=key)["ContentLength"]
    if expected is not None and int(expected) != size:
        s3.delete_object(Bucket=BUCKET, Key=key)
        raise FetchValidationError(f"{key}: size {size} != Content-Length {expected}")
    head = s3.get_object(Bucket=BUCKET, Key=key, Range="bytes=0-3")["Body"].read()
    tail = s3.get_object(Bucket=BUCKET, Key=key, Range=f"bytes={size - 4}-{size - 1}")["Body"].read()
    if head != b"PAR1" or tail != b"PAR1":
        s3.delete_object(Bucket=BUCKET, Key=key)
        raise FetchValidationError(f"{key}: not a complete Parquet file")
    return {"status": "downloaded", "key": key, "bytes": size, "fetched_at": fetched_at}


def handler(event, context):
    ym = require_month(event)
    force = bool(event.get("force_download", False))
    run_id = event.get("run_id") or f"run-{ym}-{uuid.uuid4().hex[:8]}"

    result = {t: download(f"{BASE_URL}/trip-data/{t}_tripdata_{ym}.parquet", raw_key(t, ym), force)
              for t in TAXI_TYPES}

    print(json.dumps({"stage": "fetch_batch", "year_month": ym, "result": result}))
    return {**event, "bucket": BUCKET, "run_id": run_id, "fetch": result}

"""Shared helpers for all Lambdas (deploy.sh copies this file + sql/ into every Lambda zip)

- Read / render SQL templates from sql/
- Run Athena queries and wait for results
- Validate input (prevents SQL injection, since some values are concatenated into SQL)
- S3 paths (raw / marker / staging)
"""
import json
import os
import pathlib
import re
import time

import boto3
from botocore.exceptions import ClientError

BUCKET = os.environ["BUCKET"]
DB = os.environ.get("DATABASE", "nyc_taxi")
WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "primary")
TAXI_TYPES = ["yellow", "green", "fhv", "fhvhv"]
SQL_DIR = pathlib.Path(__file__).parent / "sql"

MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_\-]{1,80}$")

s3 = boto3.client("s3")
athena = boto3.client("athena")


class AthenaQueryError(Exception):
    pass


class InvalidInput(Exception):
    pass


# ---------------------------------------------------------------- input
def require_month(event):
    ym = event.get("year_month", "")
    if not isinstance(ym, str) or not MONTH_RE.match(ym):
        raise InvalidInput(f"year_month must be YYYY-MM: {ym!r}")
    return ym


def require_run_id(event):
    rid = event.get("run_id", "")
    if not isinstance(rid, str) or not RUN_ID_RE.match(rid):
        raise InvalidInput(f"invalid run_id: {rid!r}")
    return rid


# ---------------------------------------------------------------- S3 paths
def raw_key(taxi_type, ym):
    return f"raw/{taxi_type}/year_month={ym}/{taxi_type}_tripdata_{ym}.parquet"




def marker_key(ym):
    return f"curated/year_month={ym}/_SUCCESS.json"


def staging_prefixes(run_id, ym):
    return [f"staging/{kind}/run_id={run_id}/year_month={ym}/" for kind in ("curated", "rejected")]


def object_exists(key):
    try:
        s3.head_object(Bucket=BUCKET, Key=key)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def read_json(key):
    try:
        return json.loads(s3.get_object(Bucket=BUCKET, Key=key)["Body"].read())
    except ClientError as e:
        if e.response["Error"]["Code"] in ("NoSuchKey", "404", "NotFound"):
            return None
        raise


def write_json(key, body):
    s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(body, indent=2, ensure_ascii=False).encode(),
                  ContentType="application/json")


def delete_prefix(prefix):
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
        objs = [{"Key": o["Key"]} for o in page.get("Contents", [])]
        if objs:
            s3.delete_objects(Bucket=BUCKET, Delete={"Objects": objs})


# ---------------------------------------------------------------- SQL
def render(name, **params):
    """Read sql/<name>.sql, substitute {{DB}} {{BUCKET}} and parameters, then strip comments"""
    text = (SQL_DIR / f"{name}.sql").read_text(encoding="utf-8")
    # strip comments before substitution (so substituted values are never cut even if they contain "--")
    lines = [re.sub(r"--.*$", "", ln).rstrip() for ln in text.splitlines()]
    text = "\n".join(ln for ln in lines if ln.strip()).rstrip(";")
    for k, v in {"DB": DB, "BUCKET": BUCKET, **params}.items():
        text = text.replace("{{" + k + "}}", str(v))
    if "{{" in text:
        raise ValueError(f"{name}.sql has unsubstituted placeholders")
    return text


def start_query(sql, output=None):
    return athena.start_query_execution(
        QueryString=sql, WorkGroup=WORKGROUP,
        ResultConfiguration={"OutputLocation": output or f"s3://{BUCKET}/athena-results/"},
    )["QueryExecutionId"]


def wait_query(qid, poll=2):
    while True:
        q = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        state = q["Status"]["State"]
        if state == "SUCCEEDED":
            return q
        if state in ("FAILED", "CANCELLED"):
            raise AthenaQueryError(f"{qid} {state}: {q['Status'].get('StateChangeReason', '')}")
        time.sleep(poll)


def run_query(sql, output=None):
    """Run a query and wait until it finishes; returns QueryExecution"""
    return wait_query(start_query(sql, output))


def query_rows(sql):
    """Run a SELECT and return rows as a list of dicts (all values are strings or None)"""
    qid = run_query(sql)["QueryExecutionId"]
    rows, header = [], None
    for page in athena.get_paginator("get_query_results").paginate(QueryExecutionId=qid):
        for r in page["ResultSet"]["Rows"]:
            vals = [c.get("VarCharValue") for c in r["Data"]]
            if header is None:
                header = vals
                continue
            rows.append(dict(zip(header, vals)))
    return rows

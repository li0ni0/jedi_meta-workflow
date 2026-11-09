"""
extract_ena_run_metadata.py

Retrieves sequencing platform, library preparation, and yield information
(instrument platform/model, library strategy/source/selection/layout,
base count, read count) for every sample in your input table, from ENA's
run/experiment records.

ONE SAMPLE CAN HAVE MULTIPLE RUNS - OUTPUT IS EXPANDED, NOT AGGREGATED
--------------------------------------------------------------------------
A single BioSample accession can be associated with more than one
sequencing run (e.g. technical replicates, multiple libraries, or
re-sequencing). This script outputs one row per run, with a new `Run_ID` column
formed as "{Sample_ID}_{N}" (N = 1, 2, 3... in run_accession order) to
uniquely identify each run belonging to that sample.

This means that the output table will have more rows than the input table whenever
any sample has multiple runs.

Samples with no associated run data in ENA still get exactly one output
row (Run_ID = "{Sample_ID}_1", all run-specific columns blank) so that no
input sample silently disappears from the output.

SETUP
-----
    pip install requests pandas numpy

USAGE
-----
    python extract_ena_run_metadata.py --input samples.tsv --output ena_run_metadata.tsv
    python extract_ena_run_metadata.py --input samples.tsv --output ena_run_metadata.tsv --sample-column My_Sample_ID_Column

Output columns: <your sample ID column>, Run_ID, n_runs, run_accession,
experiment_accession, instrument_platform, instrument_model,
library_strategy, library_source, library_selection, library_layout,
base_count, read_count.
"""

import argparse
import logging
import re
import sys
import time

import numpy as np
import pandas as pd

try:
    import requests
except ImportError:
    print("Missing dependency. Run:\n  pip install requests")
    sys.exit(1)

#####
# CONFIG
#####

ACCESSION_REGEX = re.compile(r"(SAMEA\d+|SAMN\d+|SAMD\d+|ERS\d+|SRS\d+|DRS\d+)")

BULK_BATCH_SIZE = 500
BULK_FIELDS = [
    "run_accession", "sample_accession", "experiment_accession",
    "instrument_platform", "instrument_model",
    "library_strategy", "library_source", "library_selection", "library_layout",
    "base_count", "read_count",
]

MAX_RETRIES = 4
RETRY_BACKOFF_SEC = 4
ENA_PORTAL_SEARCH_URL = "https://www.ebi.ac.uk/ena/portal/api/search"

RUN_FIELDS = [
    "run_accession", "experiment_accession", "instrument_platform", "instrument_model",
    "library_strategy", "library_source", "library_selection", "library_layout",
    "base_count", "read_count",
]

# Output column names: the ENA field names above with the first letter
# capitalised (e.g. run_accession -> Run_accession). Your own sample ID column
# keeps whatever name you gave it, and Run_ID is already capitalised.
OUTPUT_COLUMN_NAMES = {f: f[0].upper() + f[1:] for f in RUN_FIELDS + ["n_runs"]}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(), logging.FileHandler("ena_run_metadata_retrieval.log")],
)
log = logging.getLogger(__name__)


def retry(fn, *args, **kwargs):
    delay = RETRY_BACKOFF_SEC
    last_exc = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            last_exc = e
            log.warning(f"  attempt {attempt}/{MAX_RETRIES} failed: {e}. Retrying in {delay}s...")
            time.sleep(delay)
            delay *= 2
    log.error(f"  giving up after {MAX_RETRIES} attempts: {last_exc}")
    raise last_exc


def extract_accession(sample_id):
    m = ACCESSION_REGEX.search(str(sample_id))
    return m.group(1) if m else None

def bulk_fetch_read_run(accessions):
    """Queries ENA Portal API's read_run result in batches, filtering by
    sample_accession. Returns a list of run-level row dicts (one per run -
    a sample with 3 runs contributes 3 rows here)."""
    all_rows = []
    n_batches = (len(accessions) + BULK_BATCH_SIZE - 1) // BULK_BATCH_SIZE
    for b in range(n_batches):
        lo, hi = b * BULK_BATCH_SIZE, min((b + 1) * BULK_BATCH_SIZE, len(accessions))
        batch = accessions[lo:hi]
        log.info(f"Bulk fetch batch {b+1}/{n_batches} ({len(batch)} accessions)...")

        def _query():
            resp = requests.post(
                ENA_PORTAL_SEARCH_URL,
                data={
                    "result": "read_run",
                    "query": " OR ".join(f'sample_accession="{a}"' for a in batch),
                    "fields": ",".join(BULK_FIELDS),
                    "format": "json",
                    "limit": 0,
                },
                timeout=60,
            )
            resp.raise_for_status()
            return resp.json() if resp.text.strip() else []

        try:
            rows = retry(_query)
        except Exception as e:
            log.error(f"  batch {b+1} failed after retries: {e}")
            continue
        all_rows.extend(rows)
    log.info(f"Bulk fetch complete: {len(all_rows)} run(s) returned across "
             f"{len(accessions)} requested sample accession(s).")
    return all_rows


def group_runs_by_sample(run_rows):
    """Groups run-level rows by sample_accession, sorted by run_accession
    for deterministic Run_ID numbering across repeated executions."""
    by_sample = {}
    for row in run_rows:
        sample_acc = row.get("sample_accession")
        if not sample_acc:
            continue
        by_sample.setdefault(sample_acc, []).append(row)
    for sample_acc in by_sample:
        by_sample[sample_acc].sort(key=lambda r: r.get("run_accession") or "")
    return by_sample


def main(input_path, output_path, sample_column):
    log.info(f"Loading only the '{sample_column}' column from {input_path} "
             f"(everything else in your table is left completely untouched).")
    try:
        df = pd.read_csv(input_path, sep="\t", encoding="utf-8", usecols=[sample_column])
    except UnicodeDecodeError:
        df = pd.read_csv(input_path, sep="\t", encoding="latin-1", usecols=[sample_column])
    except ValueError:
        log.error(f"Column '{sample_column}' not found. Pass the correct column name "
                  f"via --sample-column.")
        raise SystemExit(1)

    df["__accession"] = df[sample_column].apply(extract_accession)
    n_no_accession = df["__accession"].isna().sum()
    if n_no_accession:
        log.warning(f"{n_no_accession} row(s) had no extractable accession - these will be skipped.")

    accessions = sorted(df["__accession"].dropna().unique().tolist())
    log.info(f"{len(accessions)} unique sample accessions to retrieve run/experiment data for.")

    run_rows = bulk_fetch_read_run(accessions)
    runs_by_sample = group_runs_by_sample(run_rows)

    n_no_runs = sum(1 for a in accessions if a not in runs_by_sample)
    if n_no_runs:
        log.warning(f"{n_no_runs} sample accession(s) had no associated run data in ENA "
                    f"(unusual, but possible for withdrawn/suppressed runs) - these still "
                    f"get one output row each, with run-specific columns left blank.")

    log.info("Expanding to one output row per run...")
    output_rows = []
    for _, row in df.iterrows():
        sample_id = row[sample_column]
        acc = row["__accession"]
        runs = runs_by_sample.get(acc, []) if acc else []

        if not runs:
            output_rows.append({
                sample_column: sample_id, "Run_ID": f"{sample_id}_1", "n_runs": 0,
                **{f: None for f in RUN_FIELDS},
            })
            continue

        for i, run in enumerate(runs, start=1):
            output_rows.append({
                sample_column: sample_id, "Run_ID": f"{sample_id}_{i}", "n_runs": len(runs),
                **{f: run.get(f) for f in RUN_FIELDS},
            })

    out_df = pd.DataFrame(output_rows)
    out_cols = [sample_column, "Run_ID", "n_runs"] + RUN_FIELDS
    out_df = out_df[out_cols].rename(columns=OUTPUT_COLUMN_NAMES)
    out_cols = out_df.columns.tolist()
    out_df.to_csv(output_path, sep="\t", index=False)

    log.info(f"Done. {len(df)} input samples expanded to {len(out_df)} output rows "
             f"(one per run). Saved to {output_path} (columns: {out_cols}).")
    log.info(f"  Merge this into your master table on {sample_column} - note this "
             f"will fan out any sample with more than one run across multiple rows.")
    n_multi_run = (out_df.groupby(sample_column)["Run_ID"].transform("count") > 1).sum()
    log.info(f"  {n_multi_run} output row(s) belong to a sample with more than one run.")
    n_disagree = out_df.groupby(sample_column)["Instrument_platform"].transform("nunique")
    n_disagree_samples = (n_disagree > 1).groupby(out_df[sample_column]).any().sum()
    if n_disagree_samples:
        log.warning(f"  {n_disagree_samples} sample(s) have runs on different "
                    f"Instrument_platform values - worth a look.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Retrieves sequencing platform, library type, and base/read counts "
                     "for every RUN associated with each sample in the input table, from "
                     "ENA's run/experiment records (a single fast bulk query - see the top "
                     "of this script for why no per-sample XML fetch is needed here, "
                     "unlike retrieve_ena_metadata.py). Output has one row per run (not "
                     "per sample)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--input", required=True,
                         help="Tab-delimited input table. Must contain a column (see "
                              "--sample-column) whose value contains a valid ENA/SRA/DDBJ "
                              "sample accession (embedded within a longer ID is fine). Only "
                              "this column is read - everything else in the table is "
                              "ignored and left untouched.")
    parser.add_argument("--output", required=True,
                         help="Path to write the output table (tab-delimited): the sample "
                              "ID column, Run_ID ('{Sample_ID}_{N}', N=1,2,3... per run), "
                              "and the associated sequencing metadata. "
                              "One row per RUN, not per sample - a "
                              "sample with 3 runs produces 3 rows.")
    parser.add_argument("--sample-column", default="Sample_ID",
                         help="Name of the column containing the ENA/SRA/DDBJ sample "
                              "accession (SAMEA/SAMN/SAMD/ERS/SRS/DRS followed by digits). "
                              "The accession can also be embedded within a longer string "
                              "(default = Sample_ID).")
    args = parser.parse_args()
    main(args.input, args.output, args.sample_column)
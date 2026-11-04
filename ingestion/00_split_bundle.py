"""Split a browser-captured NPCI bundle into immutable landing files.

Usage: python3 -I ingestion/00_split_bundle.py <bundle.json> <out_dir>
Writes <out_dir>/<dataset>/<year>/<year>_<mm>.json, each {dataset, year, month, source_url,
fetched_at, body} with body exactly as NPCI's API returned it. Existing identical files are left
alone, so reruns are idempotent.
"""
import json, os, sys

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

def main(bundle_path, out_dir):
    with open(bundle_path, encoding="utf-8") as fh:
        files = json.load(fh)
    written = skipped = 0
    for f in files:
        mm = MONTHS.index(f["month"]) + 1
        path = os.path.join(out_dir, f["dataset"], str(f["year"]), f"{f['year']}_{mm:02d}.json")
        text = json.dumps(f, ensure_ascii=False, sort_keys=True)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                old = json.load(fh)
            if old.get("body") == f["body"]:
                skipped += 1
                continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        written += 1
    print(f"{written} written, {skipped} unchanged, {len(files)} in bundle")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

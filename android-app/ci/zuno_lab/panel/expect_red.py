"""A bad compiler, missing Worker, or flaky process must never certify the baseline."""
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
samples = [row for row in rows if row["step"] == "watch"]
assert len(samples) == 4, "incomplete baseline"
assert [r["rows"]["rows"] for r in samples] == [5000, 20000, 20000, 20000]
assert all(row["read_rev"] is None for row in samples)
bad = samples[2]
assert bad["requests"]["0"] > 0 and bad["report"] == "loaded"
assert bad["accepted_id"] and bad["accepted_at"] >= bad["wire_rev"]
assert rows[-1]["db"]["rows"] == 20000
print("Témoin reproduit : accusé numérique réussi après un 404 et révision perdue.")

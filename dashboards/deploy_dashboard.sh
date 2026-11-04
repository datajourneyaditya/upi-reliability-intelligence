#!/usr/bin/env bash
# Create or update the AI/BI dashboard from upi_reliability.lvdash.json and publish it.
set -euo pipefail
cd "$(dirname "$0")"
D=${DATABRICKS_CLI:-$HOME/.local/bin/databricks}
P=${DATABRICKS_PROFILE:-DEFAULT}
WH=b36027f0bc1ea75e
PARENT=/Workspace/Users/adityasawant2205@gmail.com/upi_reliability
python3 build_dashboard.py > upi_reliability.lvdash.json
ID=$(cat .dashboard_id 2>/dev/null || true)
BODY_FILE=$(mktemp)
python3 -c "import json,sys;b={'display_name':'UPI Reliability Intelligence','warehouse_id':'$WH','serialized_dashboard':open('upi_reliability.lvdash.json').read()}
if not sys.argv[1]: b['parent_path']='$PARENT'
json.dump(b,open('$BODY_FILE','w'))" "$ID"
if [ -z "$ID" ]; then
  ID=$($D lakeview create -p "$P" --json @"$BODY_FILE" -o json | python3 -c "import json,sys;print(json.load(sys.stdin)['dashboard_id'])")
  echo "$ID" > .dashboard_id; echo "created $ID"
else
  $D lakeview update "$ID" -p "$P" --json @"$BODY_FILE" -o json >/dev/null; echo "updated $ID"
fi
$D lakeview publish "$ID" -p "$P" --json "{\"embed_credentials\": true, \"warehouse_id\": \"$WH\"}" -o json >/dev/null
echo "https://dbc-df33b073-3796.cloud.databricks.com/dashboardsv3/$ID/published"

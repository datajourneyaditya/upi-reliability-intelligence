"""Generate the AI/BI (Lakeview) dashboard JSON for UPI Reliability Intelligence.
Usage: python3 build_dashboard.py > upi_reliability.lvdash.json
"""
import json
from datasets import DATASETS

def lines(sql):
    return [l + "\n" for l in sql.strip().splitlines()]

def fld(col, agg=None):
    if agg is None:
        return {"name": col, "expression": f"`{col}`"}
    name = f"{agg.lower()}({col})"
    return {"name": name, "expression": f"{agg}(`{col}`)"}

def W(name, ds, fields, spec, pos, disagg=False):
    return {"widget": {"name": name,
                       "queries": [{"name": "main_query",
                                    "query": {"datasetName": ds, "fields": fields, "disaggregated": disagg}}],
                       "spec": spec},
            "position": dict(zip(["x", "y", "width", "height"], pos))}

def text(name, md, pos):
    return {"widget": {"name": name, "multilineTextboxSpec": {"lines": [l + "\n" for l in md.strip().splitlines()]}},
            "position": dict(zip(["x", "y", "width", "height"], pos))}

def counter(name, col, title, pos, fmt=None, places=1):
    enc = {"fieldName": col, "displayName": title}
    enc["format"] = fmt or {"type": "number-plain", "decimalPlaces": {"type": "max", "places": places}}
    return W(name, "ds_kpi", [fld(col)], {"version": 2, "widgetType": "counter",
             "encodings": {"value": enc}, "frame": {"showTitle": True, "title": title}}, pos, disagg=True)

def chart(kind, name, ds, x, y, title, pos, color=None, y_agg="SUM", x_type="temporal", y_title=None, x_title=None, sort_y=False, color_map=None, color_title=None):
    fields = [fld(x), fld(y, y_agg)]
    enc = {"x": {"fieldName": x, "scale": {"type": x_type}, "displayName": x_title or x},
           "y": {"fieldName": f"{y_agg.lower()}({y})", "scale": {"type": "quantitative"}, "displayName": y_title or y}}
    if sort_y:
        enc["x"]["scale"]["sort"] = {"by": "y-reversed"}
    if color:
        fields.append(fld(color))
        scale = {"type": "categorical"}
        if color_map:
            scale["mappings"] = [{"value": v, "color": c} for v, c in color_map]
        enc["color"] = {"fieldName": color, "scale": scale, "displayName": color_title or color}
    return W(name, ds, fields, {"version": 3, "widgetType": kind, "encodings": enc,
             "frame": {"showTitle": True, "title": title}}, pos)

def table(name, ds, cols, title, pos):
    """cols: list of (field, display, format-or-None)"""
    enc_cols = []
    for c, disp, fmt in cols:
        e = {"fieldName": c, "displayName": disp}
        if fmt is not None:
            e["format"] = fmt
        enc_cols.append(e)
    return W(name, ds, [fld(c) for c, _, _ in cols], {"version": 2, "widgetType": "table",
             "encodings": {"columns": enc_cols}, "frame": {"showTitle": True, "title": title}}, pos, disagg=True)

def single_filter(name, title, col, datasets, pos, default=None):
    queries, fields = [], []
    for ds in datasets:
        qn = f"filter_{name}_{ds}"
        queries.append({"name": qn, "query": {"datasetName": ds, "fields": [fld(col)], "disaggregated": False}})
        fields.append({"fieldName": col, "queryName": qn, "displayName": title})
    spec = {"version": 2, "widgetType": "filter-single-select", "encodings": {"fields": fields},
            "frame": {"showTitle": True, "title": title}}
    if default:
        spec["selection"] = {"defaultSelection": {"values": {"dataType": "STRING", "values": [{"value": default}]}}}
    return {"widget": {"name": name, "queries": queries, "spec": spec},
            "position": dict(zip(["x", "y", "width", "height"], pos))}

N1 = {"type": "number", "decimalPlaces": {"type": "exact", "places": 1}}
N2 = {"type": "number", "decimalPlaces": {"type": "exact", "places": 2}}
N3 = {"type": "number", "decimalPlaces": {"type": "exact", "places": 3}}

overview = [
    text("t_overview", """
# UPI Reliability Intelligence
Real NPCI statistics, Jan 2022 to the latest published month. **TD** = technical decline (bank / network side), **BD** = business decline (customer side: wrong PIN, low balance, limits). Bank figures cover NPCI's top 50 remitter and beneficiary banks (~97% of successful volume).
""", (0, 0, 12, 2)),
    counter("k_month", "month_label", "Latest month", (0, 2, 2, 3), fmt={"type": "string"}),
    counter("k_volume", "upi_volume_bn", "UPI transactions (bn)", (2, 2, 2, 3), places=2),
    counter("k_td", "top50_td_pct", "Technical decline %", (4, 2, 2, 3), places=3),
    counter("k_bd", "top50_bd_pct", "Business decline %", (6, 2, 2, 3), places=2),
    counter("k_failed", "est_tech_failures_mn", "Est. technical failures (mn)", (8, 2, 2, 3)),
    counter("k_degraded", "degraded_partner_sides", "Degraded partner alerts", (10, 2, 2, 3), places=0),
    chart("line", "c_rates", "ds_eco_rates", "period_month", "td_pct", "Technical decline %, top-50 payer banks (volume-weighted)",
          (0, 5, 6, 6), y_title="TD %", x_title="Month"),
    chart("line", "c_td_type", "ds_td_by_type", "period_month", "td_pct", "Technical decline % by bank type (metric view)",
          (6, 5, 6, 6), color="bank_type", y_agg="AVG", y_title="TD %", x_title="Month", color_title="Bank type"),
    chart("line", "c_bd", "ds_eco_rates", "period_month", "bd_pct", "Business decline %, top-50 payer banks",
          (0, 11, 4, 5), y_title="BD %", x_title="Month"),
    chart("bar", "c_volume", "ds_eco_volume", "period_month", "upi_volume_bn", "UPI transactions per month (bn)",
          (4, 11, 4, 5), y_title="Transactions (bn)", x_title="Month"),
    chart("bar", "c_failed", "ds_eco_volume", "period_month", "est_tech_failures_mn", "Estimated technical failures per month (mn)",
          (8, 11, 4, 5), y_title="Failures (mn)", x_title="Month"),
]

merchants = [
    text("t_merch", """
## Which bank should a merchant collect into?
Beneficiary (payee) bank reliability for the latest month. **Reliability score** (0-100) ranks banks on trailing 3-month TD (50%), TD trend (25%) and volatility (25%). Rates are bank-wide risk indicators, not any merchant's own checkout.
""", (0, 0, 12, 2)),
    table("tb_scorecard", "ds_scorecard", [
        ("reliability_rank", "Rank", None), ("bank_name", "Bank", None), ("bank_type", "Type", None),
        ("credits_received_mn", "Credits received (mn)", N1), ("td_pct", "TD %", N2), ("td_pct_3m", "TD % 3m", N3),
        ("deemed_approved_pct", "Pending credit %", N2), ("reliability_score", "Score", N1),
        ("collection_risk_tier", "Risk tier", None), ("recommendation", "Recommendation", None)],
        "Beneficiary bank scorecard, latest month", (0, 2, 12, 15)),
    chart("bar", "c_tiers", "ds_tier_mix", "period_month", "banks", "Top-50 beneficiary banks by collection risk tier",
          (0, 17, 12, 6), color="collection_risk_tier", y_title="Banks", x_title="Month", color_title="Risk tier",
          color_map=[("Low", "#2E9E5B"), ("Medium", "#E8A33D"), ("High", "#D64545")]),
]

partners = [
    text("t_partner", """
## Partner bank health
Every partner across the four NPCI views: remitter bank, beneficiary bank, payer PSP and payee PSP. **Degraded** = TD at least 0.30 pp above the bank's own trailing 3-month baseline and at least 2x it. **Excess failures** = failures above what the baseline would have produced.
""", (0, 0, 12, 2)),
    table("tb_alerts", "ds_alerts", [
        ("bank_name", "Partner", None), ("partner_side", "Side", None), ("health_status", "Status", None),
        ("td_pct", "TD %", N2), ("td_baseline_3m", "Baseline %", N3), ("td_trend_3m", "3m trend (pp)", N3),
        ("consecutive_degraded_months", "Months degraded", None), ("excess_failures_mn", "Excess failures (mn)", N2),
        ("volume_mn", "Volume (mn)", N1)],
        "Partners not healthy in the latest month", (0, 2, 12, 9)),
    single_filter("f_bank", "Partner bank", "bank_name", ["ds_partner_trend"], (0, 11, 4, 2), default="State Bank of India"),
    single_filter("f_side", "Side", "partner_side", ["ds_partner_trend", "ds_degraded_trend"], (4, 11, 4, 2), default="Remitter bank"),
    text("t_filter_hint", "Pick a partner and side to see its TD against its own baseline.", (8, 11, 4, 2)),
    chart("line", "c_partner", "ds_partner_trend", "period_month", "rate_pct", "TD % vs 3-month baseline",
          (0, 13, 8, 6), color="series", y_agg="AVG", y_title="%", x_title="Month"),
    chart("bar", "c_degraded", "ds_degraded_trend", "period_month", "degraded", "Degraded partners per month",
          (8, 13, 4, 6), y_title="Partners", x_title="Month"),
]

checkout = [
    text("t_checkout", """
## Consumer checkout risk
Which payer banks and apps drive UPI checkout failures. App exposure is **indicative**: NPCI publishes no decline rates per app, so it uses the payer-side TD of each app's sponsor PSP banks (from public VPA handles).
""", (0, 0, 12, 2)),
    chart("bar", "c_pareto", "ds_pareto_top", "bank_name", "failure_share_pct", "Top 15 payer banks by share of technical failures, latest month",
          (0, 2, 12, 6), x_type="categorical", y_title="% of technical failures", x_title="Payer bank", sort_y=True),
    table("tb_pareto", "ds_pareto", [
        ("failure_contribution_rank", "Rank", None), ("bank_name", "Payer bank", None), ("bank_type", "Type", None),
        ("volume_share_pct", "Volume share %", N1), ("failure_share_pct", "Failure share %", N1),
        ("cumulative_failure_pct", "Cumulative %", N1), ("td_pct", "TD %", N2), ("td_vs_market", "TD vs market", N2),
        ("checkout_action", "Suggested checkout action", None)],
        "Payer banks, latest month", (0, 8, 12, 9)),
    table("tb_apps", "ds_apps", [
        ("npci_volume_rank", "Rank", None), ("app_name", "App", None), ("parent_company", "Parent", None),
        ("volume_share_pct", "Volume share %", N2), ("sponsors_reported", "Sponsor PSP banks", None),
        ("sponsor_td_pct", "Sponsor TD %", N3), ("market_td_pct", "Market TD %", N3),
        ("indicative_failures_mn", "Indicative failures (mn)", N2), ("psp_risk_status", "Status", None)],
        "UPI apps, latest month", (0, 17, 12, 8)),
]

def page(name, display, layout):
    return {"name": name, "displayName": display, "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1", "layout": layout}

dash = {
    "datasets": [{"name": k, "displayName": v[0], "queryLines": lines(v[1])} for k, v in DATASETS.items()],
    "pages": [page("overview", "Overview", overview), page("merchants", "Merchants", merchants),
              page("partners", "Fintech partners", partners), page("checkout", "Consumer checkout", checkout)],
    "uiSettings": {"theme": {"widgetHeaderAlignment": "ALIGNMENT_UNSPECIFIED"}},
}
print(json.dumps(dash, indent=1))

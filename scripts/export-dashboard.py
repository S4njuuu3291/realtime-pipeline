"""
Export dashboard "Data Monitoring Dev" dari Grafana ke provisioning.
Kredensial & URL diambil dari environment (GRAFANA_*), bukan hardcoded.
"""

import json

import requests

import os

GRAFANA_BASE = os.getenv("GRAFANA_BASE_URL", "http://localhost:3000")
GRAFANA_USER = os.getenv("GRAFANA_ADMIN_USER", "admin")
GRAFANA_PASSWORD = os.getenv("GRAFANA_ADMIN_PASSWORD", "")
_GRAFANA_AUTH = (GRAFANA_USER, GRAFANA_PASSWORD)

DEV_URL = f"{GRAFANA_BASE}/api/search?query=Data%20Monitoring%20Dev"
PROV_URL = f"{GRAFANA_BASE}/api/search?query=Data%20Monitoring"
DEV_UID = ""
PROV_UID = ""
PROV_ID = ""
try:
    resp = requests.get(DEV_URL, auth=_GRAFANA_AUTH)
    resp.raise_for_status()
    uid = resp.json()[0]["uid"]
    print(f"UID for Data Monitoring Dev: {uid}")
    DEV_UID = uid

    resp = requests.get(PROV_URL, auth=_GRAFANA_AUTH)
    resp.raise_for_status()
    uid = resp.json()[0]["uid"]
    id = resp.json()[0]["id"]
    print(f"UID for Data Monitoring: {uid}")
    print(f"ID for Data Monitoring: {id}")
    PROV_UID = uid
    PROV_ID = id
except requests.exceptions.RequestException as e:
    print(f"Error fetching UID: {e}")
    exit(1)

DASHBOARD_URL_TEMPLATE = f"{GRAFANA_BASE}/api/dashboards/uid/"

try:
    resp = requests.get(DASHBOARD_URL_TEMPLATE + DEV_UID, auth=_GRAFANA_AUTH)
    resp.raise_for_status()
    dashboard = resp.json().get("dashboard")
    dashboard["uid"] = PROV_UID
    dashboard["id"] = PROV_ID
    dashboard["title"] = "Data Monitoring"
    with open("services/grafana/dashboards/data-monitoring.json", "w") as f:
        json.dump(dashboard, f, indent=2)
    print(
        "Data Monitoring Dev dashboard successfully overwriten to Data Monitoring dashboard"
    )
except requests.exceptions.RequestException as e:
    print(f"Error fetching dashboard for Data Monitoring Dev: {e}")

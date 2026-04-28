"""
curl -s http://admin:admin@localhost:3000/api/dashboards/uid/adwxscm | jq '.dashboard' > services/grafana/dashboards/data-monitoring.json
"""

import json

import requests

"""
http://admin:admin@localhost:3000/api/search?query=Data%20Monitoring%20Dev | jq -r '.[0].uid'

"""
DEV_URL = "http://admin:admin@localhost:3000/api/search?query=Data%20Monitoring%20Dev"
PROV_URL = "http://admin:admin@localhost:3000/api/search?query=Data%20Monitoring"
DEV_UID = ""
PROV_UID = ""
PROV_ID = ""
try:
    resp = requests.get(DEV_URL)
    resp.raise_for_status()
    uid = resp.json()[0]["uid"]
    print(f"UID for Data Monitoring Dev: {uid}")
    DEV_UID = uid

    resp = requests.get(PROV_URL)
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

DASHBOARD_URL_TEMPLATE = "http://admin:admin@localhost:3000/api/dashboards/uid/"

try:
    resp = requests.get(DASHBOARD_URL_TEMPLATE + DEV_UID)
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

#!/bin/bash
set -e

echo "Upgrading Superset DB..."
superset db upgrade

echo "Creating Admin user..."
superset fab create-admin \
              --username admin \
              --firstname Superset \
              --lastname Admin \
              --email admin@superset.com \
              --password admin

echo "Initializing Superset..."
superset init

echo "Registering ClickHouse database..."
: "${CLICKHOUSE_SUPERSET_PASSWORD:?CLICKHOUSE_SUPERSET_PASSWORD belum diset}"
superset set-database-uri \
    --database-name "ClickHouse_Connect_Superset" \
    --uri "clickhousedb://superset_user:${CLICKHOUSE_SUPERSET_PASSWORD}@clickhouse:8123/default" \
    --skip_create

# Auto-import dashboard jika ada file export di folder dashboards
DASHBOARD_DIR="/app/dashboards"
if [ -d "$DASHBOARD_DIR" ] && [ "$(ls -A $DASHBOARD_DIR/*.zip 2>/dev/null)" ]; then
    echo "Importing dashboards..."
    for f in $DASHBOARD_DIR/*.zip; do
        echo "  -> Importing: $f"
        /app/.venv/bin/python - "$f" <<'PY'
import os
import sys
from zipfile import ZipFile

import yaml
from sqlalchemy.engine import URL
from flask import g
from superset.app import create_app

app = create_app()
with app.app_context():
    from superset.commands.dashboard.importers.dispatcher import ImportDashboardsCommand
    from superset.commands.importers.v1.utils import get_contents_from_bundle
    from superset.extensions import security_manager
    from superset import db
    from superset.models.core import Database

    g.user = security_manager.find_user(username="admin")
    with ZipFile(sys.argv[1]) as bundle:
        contents = get_contents_from_bundle(bundle)
    passwords = {}
    database_uuids = []
    for path, content in list(contents.items()):
        if path == "databases/ClickHouse_Connect_Superset.yaml":
            config = yaml.safe_load(content)
            database_uuids.append(config["uuid"])
            config["sqlalchemy_uri"] = (
                "clickhousedb://superset_user@clickhouse:8123/default"
            )
            contents[path] = yaml.safe_dump(config)
            passwords[path] = os.environ["CLICKHOUSE_SUPERSET_PASSWORD"]
    ImportDashboardsCommand(
        contents, overwrite=True, passwords=passwords
    ).run()
    # Dashboard imports preserve connection details for existing databases.
    for uuid in database_uuids:
        database = db.session.query(Database).filter_by(uuid=uuid).one()
        database.set_sqlalchemy_uri(URL.create(
            "clickhousedb",
            username="superset_user",
            password=os.environ["CLICKHOUSE_SUPERSET_PASSWORD"],
            host="clickhouse", port=8123, database="default",
        ).render_as_string(hide_password=False))
    db.session.commit()
PY
    done
    echo "✓ Dashboards imported successfully!"
else
    echo "No dashboards found to import, skipping..."
fi

echo "Superset is ready!"

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
superset set-database-uri \
    --database-name "ClickHouse" \
    --uri "clickhouse+connect://default:admin123@clickhouse:8123/default" \
    --skip_create

echo "Registering ClickHouse analytics database..."
superset set-database-uri \
    --database-name "ClickHouse (Analytics)" \
    --uri "clickhouse+connect://default:admin123@clickhouse:8123/analytics" \
    --skip_create

# Auto-import dashboard jika ada file export di folder dashboards
DASHBOARD_DIR="/app/dashboards"
if [ -d "$DASHBOARD_DIR" ] && [ "$(ls -A $DASHBOARD_DIR/*.zip 2>/dev/null)" ]; then
    echo "Importing dashboards..."
    for f in $DASHBOARD_DIR/*.zip; do
        echo "  -> Importing: $f"
        superset import-dashboards -p "$f" -u admin
    done
    echo "✓ Dashboards imported successfully!"
else
    echo "No dashboards found to import, skipping..."
fi

echo "Superset is ready!"

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

# Auto-import dashboard jika ada file export di folder dashboards
DASHBOARD_DIR="/app/dashboards"
if [ -d "$DASHBOARD_DIR" ] && [ "$(ls -A $DASHBOARD_DIR/*.zip 2>/dev/null)" ]; then
    echo "Importing dashboards..."
    for f in $DASHBOARD_DIR/*.zip; do
        echo "  -> Importing: $f"
        superset import-dashboards -p "$f" --overwrite
    done
    echo "✓ Dashboards imported successfully!"
else
    echo "No dashboards found to import, skipping..."
fi

echo "Superset is ready!"

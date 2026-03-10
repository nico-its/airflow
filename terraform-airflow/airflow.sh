#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data ) 2>&1

INSTANCE_NAME="${INSTANCE_NAME}"
AIRFLOW_VERSION="${AIRFLOW_VERSION}"
AIRFLOW_ADMIN_USER="${AIRFLOW_ADMIN_USER}"
AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD}"
AIRFLOW_ADMIN_EMAIL="${AIRFLOW_ADMIN_EMAIL}"

export DEBIAN_FRONTEND=noninteractive

echo "=== Hostname ==="
hostnamectl set-hostname "${INSTANCE_NAME}"

echo "=== Packages ==="
apt-get update
apt-get install -y \
  python3 \
  python3-venv \
  python3-pip \
  python3-dev \
  build-essential \
  libssl-dev \
  libffi-dev \
  curl \
  jq \
  unzip

echo "=== User airflow ==="
id airflow >/dev/null 2>&1 || useradd -m -s /bin/bash airflow

mkdir -p /opt/airflow
chown -R airflow:airflow /opt/airflow

export AIRFLOW_VERSION
export AIRFLOW_ADMIN_USER
export AIRFLOW_ADMIN_PASSWORD
export AIRFLOW_ADMIN_EMAIL

echo "=== Install Airflow ==="
sudo -u airflow -E bash <<'EOF'
set -euo pipefail

cd /opt/airflow

python3 -m venv venv
source /opt/airflow/venv/bin/activate

pip install --upgrade pip setuptools wheel

PYTHON_MINOR=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-$${PYTHON_MINOR}.txt"

pip install "apache-airflow==${AIRFLOW_VERSION}" --constraint "$${CONSTRAINT_URL}"

export AIRFLOW_HOME=/opt/airflow/airflow-home
mkdir -p "$${AIRFLOW_HOME}"
mkdir -p "$${AIRFLOW_HOME}/dags" "$${AIRFLOW_HOME}/logs" "$${AIRFLOW_HOME}/plugins"

airflow db migrate

airflow users create \
  --username "${AIRFLOW_ADMIN_USER}" \
  --password "${AIRFLOW_ADMIN_PASSWORD}" \
  --firstname "Airflow" \
  --lastname "Admin" \
  --role "Admin" \
  --email "${AIRFLOW_ADMIN_EMAIL}" || true
EOF

echo "=== Example DAG ==="
cat >/opt/airflow/airflow-home/dags/example_hello.py <<'EOF'
from datetime import datetime
from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="example_hello",
    start_date=datetime(2025, 1, 1),
    schedule=None,
    catchup=False,
    tags=["example"],
) as dag:
    hello = BashOperator(
        task_id="hello",
        bash_command="echo 'Airflow est prêt sur cette EC2'; hostname; date"
    )
EOF

chown airflow:airflow /opt/airflow/airflow-home/dags/example_hello.py

echo "=== systemd env ==="
cat >/etc/default/airflow <<'EOF'
AIRFLOW_HOME=/opt/airflow/airflow-home
PATH=/opt/airflow/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__WEBSERVER__EXPOSE_CONFIG=False
AIRFLOW__API__AUTH_BACKENDS=airflow.api.auth.backend.session
AIRFLOW__WEBSERVER__WEB_SERVER_HOST=0.0.0.0
EOF

echo "=== airflow-webserver.service ==="
cat >/etc/systemd/system/airflow-webserver.service <<'EOF'
[Unit]
Description=Apache Airflow Webserver
After=network.target

[Service]
User=airflow
Group=airflow
EnvironmentFile=/etc/default/airflow
WorkingDirectory=/opt/airflow
ExecStart=/opt/airflow/venv/bin/airflow webserver --port 8080
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

echo "=== airflow-scheduler.service ==="
cat >/etc/systemd/system/airflow-scheduler.service <<'EOF'
[Unit]
Description=Apache Airflow Scheduler
After=network.target

[Service]
User=airflow
Group=airflow
EnvironmentFile=/etc/default/airflow
WorkingDirectory=/opt/airflow
ExecStart=/opt/airflow/venv/bin/airflow scheduler
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable airflow-webserver airflow-scheduler
systemctl restart airflow-webserver airflow-scheduler

echo "=== Done ==="
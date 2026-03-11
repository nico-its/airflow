#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data ) 2>&1

INSTANCE_NAME="${INSTANCE_NAME}"
AIRFLOW_VERSION="${AIRFLOW_VERSION}"
AIRFLOW_ADMIN_USER="${AIRFLOW_ADMIN_USER}"
AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD}"
AIRFLOW_ADMIN_EMAIL="${AIRFLOW_ADMIN_EMAIL}"
GIT_DAGS_REPO_URL="${GIT_DAGS_REPO_URL}"
GIT_DAGS_BRANCH="${GIT_DAGS_BRANCH}"

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
  unzip \
  git

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

export AIRFLOW_HOME=/opt/airflow/airflow-home

cd /opt/airflow

python3 -m venv venv
source /opt/airflow/venv/bin/activate

pip install --upgrade pip setuptools wheel

PYTHON_MINOR=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-$${PYTHON_MINOR}.txt"

pip install "apache-airflow==${AIRFLOW_VERSION}" --constraint "$${CONSTRAINT_URL}"

mkdir -p "$${AIRFLOW_HOME}"
mkdir -p "$${AIRFLOW_HOME}/dags" "$${AIRFLOW_HOME}/logs" "$${AIRFLOW_HOME}/plugins"

airflow db migrate
EOF

echo "=== Clone DAGs from GitLab ==="
mkdir -p /opt/airflow/airflow-home/dags
chown -R airflow:airflow /opt/airflow/airflow-home

if [ -n "${GIT_DAGS_REPO_URL}" ]; then
  rm -rf /opt/airflow/airflow-home/dags
  mkdir -p /opt/airflow/airflow-home/dags
  chown airflow:airflow /opt/airflow/airflow-home/dags

  sudo -u airflow git clone \
    --branch "${GIT_DAGS_BRANCH}" \
    "${GIT_DAGS_REPO_URL}" \
    /opt/airflow/airflow-home/dags
else
  echo "=== No Git repo provided, creating local example DAG ==="
  cat >/opt/airflow/airflow-home/dags/example_hello.py <<'EOF'
from datetime import datetime
from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="dag_formation",
    start_date=datetime(2025, 1, 1),
    schedule=None,
    catchup=False,
    tags=["guide"],
) as dag:
    hello = BashOperator(
        task_id="hello",
        bash_command="echo 'Airflow est prêt sur cette EC2'; hostname; date"
    )
EOF

  chown airflow:airflow /opt/airflow/airflow-home/dags/example_hello.py
fi

echo "=== Git sync script ==="
cat >/usr/local/bin/airflow-dags-sync.sh <<EOF
#!/bin/bash
set -euo pipefail

REPO_DIR="/opt/airflow/airflow-home/dags"
BRANCH="${GIT_DAGS_BRANCH}"

if [ -d "\$${REPO_DIR}/.git" ]; then
  cd "\$${REPO_DIR}"
  git fetch origin
  git checkout "\$${BRANCH}"
  git reset --hard "origin/\$${BRANCH}"
fi
EOF

chmod +x /usr/local/bin/airflow-dags-sync.sh

echo "=== systemd env ==="
cat >/etc/default/airflow <<'EOF'
AIRFLOW_HOME=/opt/airflow/airflow-home
PATH=/opt/airflow/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AIRFLOW__CORE__LOAD_EXAMPLES=True
AIRFLOW__WEBSERVER__EXPOSE_CONFIG=False
AIRFLOW__API__AUTH_BACKENDS=airflow.api.auth.backend.session
AIRFLOW__API__HOST=0.0.0.0
AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_ALL_ADMINS=True
EOF

echo "=== airflow-webserver.service ==="
cat >/etc/systemd/system/airflow-webserver.service <<'EOF'
[Unit]
Description=Apache Airflow API Server
After=network.target

[Service]
User=airflow
Group=airflow
EnvironmentFile=/etc/default/airflow
WorkingDirectory=/opt/airflow
ExecStart=/opt/airflow/venv/bin/airflow api-server --port 8080
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

echo "=== airflow-dag-processor.service ==="
cat >/etc/systemd/system/airflow-dag-processor.service <<'EOF'
[Unit]
Description=Apache Airflow DAG Processor
After=network.target

[Service]
User=airflow
Group=airflow
EnvironmentFile=/etc/default/airflow
WorkingDirectory=/opt/airflow
ExecStart=/opt/airflow/venv/bin/airflow dag-processor
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

echo "=== airflow-dags-sync.service ==="
cat >/etc/systemd/system/airflow-dags-sync.service <<'EOF'
[Unit]
Description=Sync Airflow DAGs from Git

[Service]
Type=oneshot
User=airflow
Group=airflow
EnvironmentFile=/etc/default/airflow
WorkingDirectory=/opt/airflow
ExecStart=/usr/local/bin/airflow-dags-sync.sh
EOF

echo "=== airflow-dags-sync.timer ==="
cat >/etc/systemd/system/airflow-dags-sync.timer <<'EOF'
[Unit]
Description=Run Airflow DAG sync every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=airflow-dags-sync.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload

systemctl enable airflow-webserver airflow-scheduler airflow-dag-processor airflow-dags-sync.timer
systemctl start airflow-dags-sync.timer
systemctl restart airflow-dag-processor
systemctl restart airflow-scheduler
systemctl restart airflow-webserver

echo "=== Initial DAG reserialize ==="
sudo -u airflow env AIRFLOW_HOME=/opt/airflow/airflow-home /opt/airflow/venv/bin/airflow dags reserialize || true

echo "=== Done ==="
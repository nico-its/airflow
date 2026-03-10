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

# airflow users create \
#   --username "${AIRFLOW_ADMIN_USER}" \
#   --password "${AIRFLOW_ADMIN_PASSWORD}" \
#   --firstname "Airflow" \
#   --lastname "Admin" \
#   --role "Admin" \
#   --email "${AIRFLOW_ADMIN_EMAIL}" || true
EOF

echo "=== Clone DAGs from GitLab ==="
if [ -n "${GIT_DAGS_REPO_URL}" ]; then
  rm -rf /opt/airflow/airflow-home/dags
  mkdir -p /opt/airflow/airflow-home/dags
  chown airflow:airflow /opt/airflow/airflow-home/dags

  sudo -u airflow git clone \
    --branch "${GIT_DAGS_BRANCH}" \
    "${GIT_DAGS_REPO_URL}" \
    /opt/airflow/airflow-home/dags
fi

cat >/usr/local/bin/airflow-dags-sync.sh <<'EOF'
#!/bin/bash
set -euo pipefail

REPO_DIR="/opt/airflow/airflow-home/dags"

if [ -d "${REPO_DIR}/.git" ]; then
  cd "${REPO_DIR}"
  git fetch origin
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  git reset --hard "origin/${CURRENT_BRANCH}"
fi
EOF

chmod +x /usr/local/bin/airflow-dags-sync.sh
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

echo "=== airflow-dag.sync ==="

cat >/etc/systemd/system/airflow-dags-sync.service <<'EOF'
[Unit]
Description=Sync Airflow DAGs from Git

[Service]
Type=oneshot
User=airflow
Group=airflow
ExecStart=/usr/local/bin/airflow-dags-sync.sh
EOF

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
systemctl enable airflow-webserver airflow-scheduler
systemctl restart airflow-webserver airflow-scheduler

echo "=== Done ==="
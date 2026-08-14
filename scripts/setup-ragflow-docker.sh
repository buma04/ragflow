#!/usr/bin/env bash
set -euo pipefail

socket=${RAGFLOW_DOCKER_SOCKET:-/run/docker-ragflow.sock}
data_root=${RAGFLOW_DOCKER_DATA_ROOT:-/u01/docker-ragflow}
config_dir=/etc/docker-ragflow
config_file=$config_dir/daemon.json
unit_file=/etc/systemd/system/docker-ragflow.service

if ((EUID != 0)); then
  echo "ERROR: run this script as root (or through sudo)" >&2
  exit 1
fi

command -v dockerd >/dev/null || { echo "ERROR: dockerd not found" >&2; exit 1; }
command -v systemctl >/dev/null || { echo "ERROR: systemd not found" >&2; exit 1; }
nvidia_runtime=$(command -v nvidia-container-runtime) || {
  echo "ERROR: nvidia-container-runtime not found" >&2
  exit 1
}

[[ -d /u01 ]] || { echo "ERROR: /u01 does not exist" >&2; exit 1; }
mkdir -p "$data_root" "$config_dir"

config_tmp=$(mktemp)
unit_tmp=$(mktemp)
trap 'rm -f "$config_tmp" "$unit_tmp"' EXIT

cat >"$config_tmp" <<EOF
{
  "data-root": "$data_root",
  "exec-root": "/run/docker-ragflow",
  "pidfile": "/run/docker-ragflow.pid",
  "hosts": ["unix://$socket"],
  "bridge": "none",
  "storage-driver": "overlay2",
  "features": {"containerd-snapshotter": false},
  "default-address-pools": [
    {"base": "10.231.0.0/16", "size": 24}
  ],
  "runtimes": {
    "nvidia": {
      "path": "$nvidia_runtime",
      "runtimeArgs": []
    }
  }
}
EOF

cat >"$unit_tmp" <<EOF
[Unit]
Description=Dedicated Docker Engine for RAGFlow
Documentation=https://docs.docker.com/reference/cli/dockerd/#run-multiple-daemons
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=$(command -v dockerd) --config-file=$config_file
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=2
TimeoutStartSec=0
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

dockerd --validate --config-file="$config_tmp" >/dev/null

changed=false
if ! cmp -s "$config_tmp" "$config_file"; then
  install -m 0644 "$config_tmp" "$config_file"
  changed=true
fi
if ! cmp -s "$unit_tmp" "$unit_file"; then
  install -m 0644 "$unit_tmp" "$unit_file"
  changed=true
fi

systemctl daemon-reload
systemctl enable docker-ragflow.service >/dev/null
if [[ "$changed" == true ]] || ! systemctl is-active --quiet docker-ragflow.service; then
  systemctl restart docker-ragflow.service
fi

for _ in {1..30}; do
  if docker -H "unix://$socket" info >/dev/null 2>&1; then
    echo "Dedicated RAGFlow Docker daemon is ready: unix://$socket"
    echo "Docker data root: $data_root"
    exit 0
  fi
  sleep 1
done

systemctl status docker-ragflow.service --no-pager >&2 || true
exit 1

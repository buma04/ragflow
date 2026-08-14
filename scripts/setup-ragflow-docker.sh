#!/usr/bin/env bash
set -euo pipefail

socket=${RAGFLOW_DOCKER_SOCKET:-/run/docker-ragflow.sock}
data_root=${RAGFLOW_DOCKER_DATA_ROOT:-/u01/docker-ragflow}
config_dir=/etc/docker-ragflow
config_file=$config_dir/daemon.json
unit_file=/etc/systemd/system/docker-ragflow.service
containerd_unit_file=/etc/systemd/system/containerd-ragflow.service
containerd_socket=/run/containerd-ragflow/containerd.sock
containerd_root=/u01/containerd-ragflow

if ((EUID != 0)); then
  echo "ERROR: run this script as root (or through sudo)" >&2
  exit 1
fi

command -v dockerd >/dev/null || { echo "ERROR: dockerd not found" >&2; exit 1; }
containerd_command=$(command -v containerd) || { echo "ERROR: containerd not found" >&2; exit 1; }
command -v systemctl >/dev/null || { echo "ERROR: systemd not found" >&2; exit 1; }
nvidia_runtime=$(command -v nvidia-container-runtime) || {
  echo "ERROR: nvidia-container-runtime not found" >&2
  exit 1
}
ip_command=$(command -v ip) || { echo "ERROR: ip command not found" >&2; exit 1; }

[[ -d /u01 ]] || { echo "ERROR: /u01 does not exist" >&2; exit 1; }
mkdir -p "$data_root" "$containerd_root" "$config_dir"

config_tmp=$(mktemp)
unit_tmp=$(mktemp)
containerd_unit_tmp=$(mktemp)
trap 'rm -f "$config_tmp" "$unit_tmp" "$containerd_unit_tmp"' EXIT

cat >"$config_tmp" <<EOF
{
  "data-root": "$data_root",
  "exec-root": "/run/docker-ragflow",
  "pidfile": "/run/docker-ragflow.pid",
  "hosts": ["unix://$socket"],
  "bridge": "docker-ragflow0",
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

cat >"$containerd_unit_tmp" <<EOF
[Unit]
Description=Dedicated containerd for RAGFlow Docker Engine
Documentation=https://containerd.io
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
RuntimeDirectory=containerd-ragflow
ExecStart=$containerd_command --root $containerd_root --state /run/containerd-ragflow --address $containerd_socket
Restart=always
RestartSec=2
Delegate=yes
KillMode=process
OOMScoreAdjust=-500
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

cat >"$unit_tmp" <<EOF
[Unit]
Description=Dedicated Docker Engine for RAGFlow
Documentation=https://docs.docker.com/reference/cli/dockerd/#run-multiple-daemons
Requires=containerd-ragflow.service
After=network-online.target containerd-ragflow.service
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=-$ip_command link add name docker-ragflow0 type bridge
ExecStartPre=$ip_command address replace 10.230.0.1/24 dev docker-ragflow0
ExecStartPre=$ip_command link set docker-ragflow0 up
ExecStart=$(command -v dockerd) --config-file=$config_file --containerd=$containerd_socket
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

docker_changed=false
containerd_changed=false
if ! cmp -s "$config_tmp" "$config_file"; then
  install -m 0644 "$config_tmp" "$config_file"
  docker_changed=true
fi
if ! cmp -s "$unit_tmp" "$unit_file"; then
  install -m 0644 "$unit_tmp" "$unit_file"
  docker_changed=true
fi
if ! cmp -s "$containerd_unit_tmp" "$containerd_unit_file"; then
  install -m 0644 "$containerd_unit_tmp" "$containerd_unit_file"
  containerd_changed=true
fi

systemctl daemon-reload
systemctl enable containerd-ragflow.service docker-ragflow.service >/dev/null
if [[ "$containerd_changed" == true ]] || ! systemctl is-active --quiet containerd-ragflow.service; then
  systemctl restart containerd-ragflow.service
  docker_changed=true
fi
if [[ "$docker_changed" == true ]] || ! systemctl is-active --quiet docker-ragflow.service; then
  systemctl restart docker-ragflow.service
fi

for _ in {1..30}; do
  if docker -H "unix://$socket" info >/dev/null 2>&1; then
    echo "Dedicated RAGFlow Docker daemon is ready: unix://$socket"
    echo "Docker data root: $data_root"
    echo "Dedicated containerd socket: $containerd_socket"
    exit 0
  fi
  sleep 1
done

systemctl status docker-ragflow.service --no-pager >&2 || true
exit 1

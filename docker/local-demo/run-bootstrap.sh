#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import os
import re
from pathlib import Path

template = Path("/ragflow/conf/service_conf.yaml.template").read_text()
pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")


def replace(match):
    name, default = match.groups()
    return os.environ.get(name) or (default or "")


Path("/ragflow/conf/service_conf.yaml").write_text(pattern.sub(replace, template))
PY

exec python /ragflow/bootstrap-models.py

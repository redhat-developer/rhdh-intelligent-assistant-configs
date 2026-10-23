#!/usr/bin/env bash
#
#
# Copyright Red Hat
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Generate a local pgvector variant of lightspeed-stack.yaml for compose dev.
# lightspeed-stack.yaml (FAISS) stays the single source of truth; only the
# notebooks vector_store provider is rewritten to pgvector so local dev mirrors
# the cluster. The rewrite matches notebooks_vector_store_faiss_to_pgvector in
# generate-gitops-manifests.sh, so the notebooks block is identical to the
# cluster manifest.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_ROOT}/lightspeed-core-configs/lightspeed-stack.yaml"
OUT_DIR="${REPO_ROOT}/generated"
OUT="${OUT_DIR}/lightspeed-stack.pgvector.yaml"

mkdir -p "${OUT_DIR}"

awk '
  /^    - id: notebooks$/ {
    skip = 1
    print "    - id: notebooks"
    print "      type: pgvector"
    print "      embedding_model: nomic-ai/nomic-embed-text-v1.5"
    print "      embedding_dimension: 768"
    print "      config:"
    print "        host: ${env.PGVECTOR_HOST:=lightspeed-postgres-svc.lightspeed-postgres.svc.cluster.local}"
    print "        port: \"5432\""
    print "        db: ${env.PGVECTOR_DB}"
    print "        user: ${env.PGVECTOR_USER}"
    print "        password: ${env.PGVECTOR_PASSWORD}"
    next
  }
  skip && /^    - id:/ { skip = 0 }
  skip && /^[a-zA-Z]/ { skip = 0 }
  skip { next }
  { print }
' "${SRC}" > "${OUT}"

echo "Wrote ${OUT}"

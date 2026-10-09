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
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/generated"
GITOPS_REPO="${GITOPS_REPO:-${REPO_ROOT}/../ai-rolling-demo-gitops}"

mkdir -p "${OUTPUT_DIR}"

indent() {
  sed 's/^/    /'
}

strip_license() {
  sed -n '/^[^#]/,$p' "$1"
}

strip_comments() {
  sed -E '/^[[:space:]]*#/d'
}

get_image() {
  local key="$1"
  awk -v key="${key}" '
    /^[^[:space:]]/ { in_section = ($0 == key":") }
    in_section && /^[[:space:]]+image:/ { print $2; exit }
  ' "${REPO_ROOT}/images.yaml"
}

# Uncomment commented inference provider blocks whose id is vllm, openai, or vertexai.
uncomment_inference_providers() {
  awk '
    function uncomment_line(text) {
      comment_pos = index(text, "#")
      if (comment_pos == 0) {
        return text
      }

      prefix = substr(text, 1, comment_pos - 1)
      rest = substr(text, comment_pos + 1)
      sub(/^[[:space:]]/, "", rest)
      return prefix rest
    }

    function flush_block(    i, line_out) {
      if (!buffering) {
        return
      }

      for (i = 1; i <= block_len; i++) {
        line_out = block_lines[i]
        if (block_id in enable) {
          line_out = uncomment_line(line_out)
        }
        print line_out
      }

      delete block_lines
      block_len = 0
      block_id = ""
      buffering = 0
    }

    BEGIN {
      enable["vllm"] = 1
      enable["openai"] = 1
      enable["vertexai"] = 1
    }

    {
      line = $0

      if (in_inference && line ~ /^[^[:space:]]/ && line != "inference:") {
        flush_block()
        in_inference = 0
        in_providers = 0
      }

      if (line == "inference:") {
        flush_block()
        in_inference = 1
        print line
        next
      }

      if (in_inference && line == "  providers:") {
        flush_block()
        in_providers = 1
        print line
        next
      }

      if (in_providers && line ~ /^  [^[:space:]#-]/) {
        flush_block()
        in_providers = 0
      }

      if (in_providers && line ~ /^[[:space:]]*#[[:space:]]*- type:/) {
        flush_block()
        buffering = 1
        block_lines[++block_len] = line
        next
      }

      if (buffering) {
        if (line ~ /^[[:space:]]*#/) {
          block_lines[++block_len] = line
          if (line ~ /^[[:space:]]*#[[:space:]]*id:[[:space:]]*/) {
            block_id = line
            sub(/^[[:space:]]*#[[:space:]]*id:[[:space:]]*/, "", block_id)
            sub(/[[:space:]].*$/, "", block_id)
          }
          next
        }

        flush_block()
      }

      print line
    }

    END {
      flush_block()
    }
  '
}

# Overlay production allowed_models onto uncommented OpenAI/Vertex extra blocks.
add_inference_allowed_models() {
  awk '
    /^    - type:/ {
      current_provider = ""
    }

    /^      id: / {
      current_provider = $0
      sub(/^      id: /, "", current_provider)
    }

    {
      print
    }

    current_provider == "openai" && /^      api_key_env: OPENAI_API_KEY$/ {
      print "      extra:"
      print "        allowed_models:"
      print "          - gpt-4o-mini"
      print "          - gpt-5.1"
      print "          - gpt-4.1-mini"
      print "          - gpt-4.1-nano"
    }

    current_provider == "vertexai" && /^        location: \$\{env.VERTEX_AI_LOCATION:=global\}$/ {
      print "        allowed_models:"
      print "          - publishers/google/models/gemini-2.5-pro"
      print "          - publishers/google/models/gemini-2.5-flash-lite"
      print "          - publishers/google/models/gemini-3.1-pro-preview"
      print "          - publishers/google/models/gemini-3.5-flash-lite"
    }
  '
}

inject_byok_rag() {
  awk '
    /^rag:$/ {
      print
      print "  byok:"
      print "    stores:"
      print "      - rag_id: custom-org-docs"
      print "        backend: faiss"
      print "        embedding_model: nomic-ai/nomic-embed-text-v1.5"
      print "        embedding_dimension: 768"
      print "        vector_db_id: vs_727b6321-1ff4-47bf-a76b-1cc12426c954"
      print "        db_path: /tmp/vector_db/custom_docs/faiss_store.db"
      print "        score_multiplier: 1.0"
      next
    }
    /^        - okp$/ {
      print "        - okp"
      print "        - custom-org-docs"
      next
    }
    { print }
  '
}

echo "Generating lightspeed-stack ConfigMap..."
{
  cat << 'HEADER'
kind: ConfigMap
apiVersion: v1
metadata:
  name: lightspeed-stack-config
  namespace: {{ .Release.Namespace }}
data:
  lightspeed-stack.yaml: |
HEADER
  strip_license "${REPO_ROOT}/lightspeed-core-configs/lightspeed-stack.yaml" \
    | uncomment_inference_providers \
    | strip_comments \
    | add_inference_allowed_models \
    | inject_byok_rag \
    | indent
} > "${OUTPUT_DIR}/lightspeed-stack-config.yaml"

echo "Updating lightspeed-core sidecar image in values.yaml..."
LIGHTSPEED_CORE_IMAGE="$(get_image "lightspeed-core")"
VALUES_YAML="${GITOPS_REPO}/charts/rhdh/values.yaml"
if [[ ! -f "${VALUES_YAML}" ]]; then
  echo "Error: ${VALUES_YAML} not found." >&2
  exit 1
fi

# Newer RHDH charts split the Lightspeed Core image into registry, repository,
# and tag. Only update intelligentAssistant.core.image, not other chart images.
LIGHTSPEED_CORE_IMAGE_REGISTRY="${LIGHTSPEED_CORE_IMAGE%%/*}"
LIGHTSPEED_CORE_IMAGE_PATH="${LIGHTSPEED_CORE_IMAGE#*/}"
LIGHTSPEED_CORE_IMAGE_REPOSITORY="${LIGHTSPEED_CORE_IMAGE_PATH%:*}"
LIGHTSPEED_CORE_IMAGE_TAG="${LIGHTSPEED_CORE_IMAGE##*:}"
VALUES_YAML_TMP="${VALUES_YAML}.tmp"

if awk \
  -v registry="${LIGHTSPEED_CORE_IMAGE_REGISTRY}" \
  -v repository="${LIGHTSPEED_CORE_IMAGE_REPOSITORY}" \
  -v tag="${LIGHTSPEED_CORE_IMAGE_TAG}" '
    {
      if (/^[^[:space:]#]/) section = ($0 == "redhat-developer-hub:") ? 1 : 0
      if (/^  [^[:space:]#]/ && section >= 1) section = ($0 == "  intelligentAssistant:") ? 2 : 1
      if (/^    [^[:space:]#]/ && section >= 2) section = ($0 == "    core:") ? 3 : 2
      if (/^      [^[:space:]#]/ && section >= 3) section = ($0 == "      image:") ? 4 : 3
      if (section == 4 && /^      image:$/) image_found = 1

      if (section == 4 && /^        registry:/) {
        print "        registry: " registry
        registry_found = 1
        next
      }
      if (section == 4 && /^        repository:/) {
        print "        repository: " repository
        repository_found = 1
        next
      }
      if (section == 4 && /^        tag:/) {
        print "        tag: " tag
        tag_found = 1
        next
      }
      # A nonempty digest overrides the tag when the chart renders the image.
      if (section == 4 && /^        digest:/) {
        print "        digest: \"\""
        next
      }

      print
    }
    END {
      if (!(registry_found && repository_found && tag_found)) {
        exit image_found ? 2 : 1
      }
    }
  ' "${VALUES_YAML}" > "${VALUES_YAML_TMP}"; then
  mv "${VALUES_YAML_TMP}" "${VALUES_YAML}"
else
  awk_status=$?
  rm -f "${VALUES_YAML_TMP}"
  if [[ "${awk_status}" -ne 1 ]]; then
    echo "Error: incomplete Lightspeed Core image fields in ${VALUES_YAML}." >&2
    exit 1
  fi
  if ! grep -q "image: [^ ]*/lightspeed-stack[^ ]*" "${VALUES_YAML}"; then
    echo "Error: no Lightspeed Core image field found in ${VALUES_YAML}." >&2
    exit 1
  fi
  # Older chart values keep the sidecar image in one field.
  sed -i "s|image: [^ ]*/lightspeed-stack[^ ]*|image: ${LIGHTSPEED_CORE_IMAGE}|g" "${VALUES_YAML}"
fi

echo "Generated manifests:"
ls -1 "${OUTPUT_DIR}"

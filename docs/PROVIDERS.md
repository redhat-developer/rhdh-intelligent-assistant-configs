# Provider Configuration

Each inference has its own environment variables. You can include all of these in an env file and pass it to your container. Use [default-values.env](./env/default-values.env) as a template, and copy it to `values.env` for local edits.

> [!IMPORTANT]
> These are `.env` values, so avoid wrapping values in quotes unless required by the provider.
>
> `VLLM_API_KEY=token` (recommended)
>
> `VLLM_API_KEY="token"` (can cause parsing issues)
> 
> You will notice the `api_key_env` field is not wrapped in curly-braces `{}`. This is due to Lightspeed Core wrapping them internally to curate a proper `{env.xyz}` to pass through to Llama Stack so the keys are not exposed internally.

> [!NOTE]
> The tracked [lightspeed-stack.yaml](../lightspeed-core-configs/lightspeed-stack.yaml) comments out the entire `inference.providers` section, including provider stubs for `vllm`, `openai`, and `vertexai`. For local development, copy that file to `lightspeed-core-configs/lightspeed-stack.local.yaml` (gitignored, auto-mounted by `make local-up` when present — see [CONTRIBUTING.md](./CONTRIBUTING.md)), uncomment `inference:` and `providers:`, then uncomment the provider block(s) you need and set the required env vars. The `byo-llm` baseline means these providers belong at the top-level `inference.providers` section — do not add them to `ogx.config.native_override`.
>
> For GitOps/production, [scripts/generate-gitops-manifests.sh](../scripts/generate-gitops-manifests.sh) uncomments those three providers, then adds production `allowed_models` for `openai` and `vertexai`.
>

## vLLM

To add the `vLLM` inference provider, uncomment the corresponding block in [lightspeed-stack.yaml](../lightspeed-core-configs/lightspeed-stack.yaml) (via `lightspeed-core-configs/lightspeed-stack.local.yaml` for local development). The stub looks like:

```yaml
inference:
  providers:
    - type: vllm
      id: <your-unique-id>
      api_key_env: VLLM_API_KEY
      config:
        base_url: ${env.VLLM_URL:=}
        api_key: ${env.VLLM_API_KEY}
      extra:
        base_url: ${env.VLLM_URL:=}
        max_tokens: ${env.VLLM_MAX_TOKENS:=4096}
        network:
          tls:
            verify: ${env.VLLM_TLS_VERIFY:=true}
```

In order for `vLLM` to configure properly, you must include environment variables named `VLLM_API_KEY` and `VLLM_URL` to the Lightspeed Core container.

## OpenAI

To add the `openai` inference provider, uncomment the corresponding block in [lightspeed-stack.yaml](../lightspeed-core-configs/lightspeed-stack.yaml) (via `lightspeed-core-configs/lightspeed-stack.local.yaml` for local development). The stub looks like:

```yaml
inference:
  providers:
    - type: openai
      id: <your-unique-id>
      api_key_env: OPENAI_API_KEY
      config:
        base_url: ${env.OPENAI_API_BASE_URL:=https://api.openai.com/v1}
        api_key: ${env.OPENAI_API_KEY}
      extra:
        base_url: ${env.OPENAI_API_BASE_URL:=https://api.openai.com/v1}
```

You must pass the environment variable `OPENAI_API_KEY` to the Lightspeed Core container.

Get your API key from [platform.openai.com](https://platform.openai.com/settings/organization/api-keys).

## Vertex AI (Gemini)

To add the `vertexai` inference provider, uncomment the corresponding block in [lightspeed-stack.yaml](../lightspeed-core-configs/lightspeed-stack.yaml) (via `lightspeed-core-configs/lightspeed-stack.local.yaml` for local development). The stub looks like:

```yaml
inference:
  providers:
    - type: vertexai
      id: <your-unique-id>
      config:
        project: ${env.VERTEX_AI_PROJECT:=}
        location: ${env.VERTEX_AI_LOCATION:=global}
      extra:
        project: ${env.VERTEX_AI_PROJECT:=}
        location: ${env.VERTEX_AI_LOCATION:=global}
```

Additionally, you need to ensure your Google Application Credentials are mounted to the Lightspeed Core container and the `GOOGLE_APPLICATION_CREDENTIALS` environment variable is the path to the mount location.

To set this up with the provided `compose/compose.yaml`, set `GOOGLE_APPLICATION_CREDENTIALS_HOST_PATH` to the path on your host machine of a GCP service account JSON key (or your `gcloud auth application-default login` credentials file). The compose file mounts that file into the container and points `GOOGLE_APPLICATION_CREDENTIALS` at the mounted path for you — do not set `GOOGLE_APPLICATION_CREDENTIALS` to a host path yourself, since that path won't exist inside the container.

```env
VERTEX_AI_PROJECT=
VERTEX_AI_LOCATION=
GOOGLE_APPLICATION_CREDENTIALS_HOST_PATH=<path-on-your-host-to-a-gcp-service-account-json-key>
```

The service account (or `gcloud auth application-default login` credentials) needs the `Vertex AI User` role, and the Vertex AI API must be enabled on `VERTEX_AI_PROJECT`.

Provider details: [Llama Stack (OGX) Vertex AI docs](https://ogx-ai.github.io/docs/providers/inference/remote_vertexai).

For GitOps/production, [generate-gitops-manifests.sh](../scripts/generate-gitops-manifests.sh) uncomments this stub and adds `allowed_models`. If the production shape changes, update the tracked stub and/or `add_inference_allowed_models` in that script.

## Restricting Models (`allowed_models`)

Each of the providers above supports an `allowed_models` field to limit which models get registered with Llama Stack. This is most useful for `openai` and `vertexai`, since they auto-discover every model available to your account/project unless restricted.

To use it locally, add `allowed_models` directly under the provider entry in `lightspeed-core-configs/lightspeed-stack.local.yaml`, alongside `id`, `config`, and `extra`. For GitOps/production, [generate-gitops-manifests.sh](../scripts/generate-gitops-manifests.sh) overlays production `allowed_models` automatically for `openai` and `vertexai`.

Open AI example:
```yaml
inference:
  providers:
    - type: openai
      id: <your-unique-id>
      api_key_env: OPENAI_API_KEY
      allowed_models:
        - gpt-4o
        - gpt-4o-mini
```

If `allowed_models` is omitted, all models the provider can see are registered.

## Full Example

The example below illustrates a local `lightspeed-stack.local.yaml` with providers uncommented.

```yaml
name: lightspeed-core-stack
service:
  host: ${env.SERVICE_HOST:=127.0.0.1}
  port: 8080
  auth_enabled: false
  workers: 1
  color_log: true
  access_log: true
ogx:
  use_as_library_client: true
  config:
    baseline: byo-llm
inference:
  providers:
    - type: openai
      id: openai
      api_key_env: OPENAI_API_KEY
      config:
        base_url: ${env.OPENAI_API_BASE_URL:=https://api.openai.com/v1}
        api_key: ${env.OPENAI_API_KEY}
      allowed_models:
        - gpt-4o
        - gpt-4o-mini
      extra:
        base_url: ${env.OPENAI_API_BASE_URL:=https://api.openai.com/v1}
    - type: vllm
      id: vllm-team
      api_key_env: VLLM_API_KEY
      config:
        base_url: ${env.VLLM_URL:=}
        api_key: ${env.VLLM_API_KEY}
      extra:
        base_url: ${env.VLLM_URL:=}
        max_tokens: ${env.VLLM_MAX_TOKENS:=4096}
        network:
          tls:
            verify: ${env.VLLM_TLS_VERIFY:=true}
user_data_collection:
  feedback_enabled: true
  feedback_storage: '/tmp/data/feedback'
authentication:
  module: 'noop'
conversation_cache:
  type: 'sqlite'
  sqlite:
    db_path: '/tmp/cache.db'
customization:
  profile_path: '/app-root/rhdh-profile.py'
mcp_servers:
  - name: mcp-integration-tools
    provider_id: 'model-context-protocol'
    url: 'http://localhost:7007/api/mcp-actions/v1'
    authorization_headers:
      Authorization: 'client'
```

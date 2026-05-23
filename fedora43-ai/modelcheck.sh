set -a; source ./.env; set +a; \
  curl -sS -H "Authorization: Bearer ${LITELLM_API_KEY}" \
    "${LITELLM_URL%/}:${LITELLM_PORT}/v1/models" | jq -r '.data[].id'

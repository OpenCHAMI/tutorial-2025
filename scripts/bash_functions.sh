CURL_CONTAINER=cgr.dev/chainguard/curl
CURL_TAG=latest


container_curl() {
    local url=$1
    ${CONTAINER_CMD:-podman} run --rm "${CURL_CONTAINER}:${CURL_TAG}" -s $url
}

create_client_credentials() {
   ${CONTAINER_CMD:-podman} exec hydra hydra create client \
    --endpoint http://hydra:4445/ \
    --format json \
    --grant-type client_credentials \
    --scope openid \
    --scope smd.read
}

# CLIENT_CREDENTIALS=$(create_client_credentials)
# $(echo $CLIENT_CREDENTIALS | jq -r '"\(.client_id):\(.client_secret)"')

retrieve_access_token() {
    local CLIENT_ID=$1
    local CLIENT_SECRET=$2

    ${CONTAINER_CMD:-podman} run --rm --network openchami-jwt-internal "${CURL_CONTAINER}:${CURL_TAG}" -s -u "$CLIENT_ID:$CLIENT_SECRET" \
    -d grant_type=client_credentials \
    -d scope=openid+smd.read \
    http://hydra:4444/oauth2/token
}

# ACCESS_TOKEN=$(retrieve_access_token $CLIENT_ID $CLIENT_SECRET | jq -r .access_token)

gen_access_token() {
    local CLIENT_CREDENTIALS
    CLIENT_CREDENTIALS=$(create_client_credentials)
    local CLIENT_ID=`echo $CLIENT_CREDENTIALS | jq -r '.client_id'`
    local CLIENT_SECRET=`echo $CLIENT_CREDENTIALS | jq -r '.client_secret'`
    local ACCESS_TOKEN=$(retrieve_access_token $CLIENT_ID $CLIENT_SECRET | jq -r .access_token)
    echo $ACCESS_TOKEN
}

# export ACCESS_TOKEN=$(gen_access_token)
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

# Function to convert an OCI image to an NFS-mountable SquashFS
import_image() {
    local image="$1"
    local output_dir="$2"

    # Validate inputs
    if [[ -z "$image" || -z "$output_dir" ]]; then
        echo "Usage: import_image <container-image> <output-dir>"
        return 1
    fi

    if [[ "$output_dir" == "/" || "$output_dir" == "" ]]; then
        echo "ERROR: Invalid output directory."
        return 1
    fi

    # Ensure output directory exists and is empty
    if [[ -d "$output_dir" ]]; then
        if [[ -n "$(ls -A "$output_dir")" ]]; then
            echo "ERROR: Output directory '$output_dir' is not empty."
            return 1
        fi
    else
        mkdir -p "$output_dir"
    fi

    # Flag to detect if we're already in the unshare environment
if [ "${PODMAN_UNSHARE:-}" != "1" ]; then
    # Check if unshare is necessary
    if ! podman image mount busybox &>/dev/null; then
        echo "Entering podman unshare environment..."
        export PODMAN_UNSHARE=1
        exec podman unshare bash "$0" "$@"
    else
        podman image unmount busybox &>/dev/null
    fi
fi

    # Always unmount image on exit
    cleanup() {
        podman image unmount "$image" &>/dev/null || true
        if [[ "${PODMAN_UNSHARE:-}" == "1" ]]; then
            echo "Exiting unshare session..."
            exit 0
        fi
    }
    trap cleanup EXIT

    # Pull the container image
    echo "Pulling container image: $image"
    podman pull --tls-verify=false "$image"

    # Mount the container image
    echo "Mounting container image..."
    local mname
    mname=$(podman image mount "$image") || {
        echo "ERROR: Failed to mount image '$image'."
        return 1
    }

    # Ensure kernel modules exist
    local modules_dir="$mname/lib/modules"
    if [[ ! -d "$modules_dir" || -z "$(ls -A "$modules_dir")" ]]; then
        echo "ERROR: No kernel modules found in '$modules_dir'."
        return 1
    fi

    local kver
    kver=$(ls "$modules_dir" | sort -V | head -n 1)

    # Verify kernel/initramfs existence
    local initramfs="$mname/boot/initramfs-$kver.img"
    local vmlinuz="$mname/boot/vmlinuz-$kver"

    for file in "$initramfs" "$vmlinuz"; do
        if [[ ! -f "$file" ]]; then
            echo "ERROR: Missing required file: $file"
            return 1
        fi
    done

    # Copy kernel and initramfs
    echo "Copying kernel and initramfs..."
    cp "$initramfs" "$output_dir/"
    chmod o+r "$output_dir/initramfs-$kver.img"
    cp "$vmlinuz" "$output_dir/"

    # Create SquashFS
    echo "Creating SquashFS image..."
    mksquashfs "$mname" "$output_dir/rootfs-$kver.squashfs" -noappend -no-progress -no-exports -comp lzo -b 512K -Xdict-size 64K -no-fragments -no-xattrs || {
        echo "ERROR: SquashFS creation failed."
        return 1
    }

    echo "✅ Successfully created SquashFS image at '$output_dir/rootfs-$kver.squashfs'"
    return 0
}


# export ACCESS_TOKEN=$(gen_access_token)
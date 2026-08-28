#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
resource_dir="${NEKOBOX_CORE_RESOURCE_DIR:-${package_dir}/Resources}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/nekobox-cores.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

for required_command in curl jq shasum unzip tar install; do
    if ! command -v "${required_command}" >/dev/null 2>&1; then
        print -u2 "Required command is unavailable: ${required_command}"
        exit 1
    fi
done

mkdir -p "${resource_dir}"

download_core() {
    local core_name="$1"
    local repository="$2"
    local asset_pattern="$3"
    local archive_type="$4"
    local release_file="${work_dir}/${core_name}-release.json"
    local extraction_dir="${work_dir}/${core_name}-extract"

    curl --fail --location --retry 3 --retry-delay 2 \
        --header 'Accept: application/vnd.github+json' \
        --header 'User-Agent: NekoBox-macOS-build' \
        "https://api.github.com/repos/${repository}/releases/latest" \
        --output "${release_file}"

    local asset_name
    asset_name="$(jq -r --arg pattern "${asset_pattern}" '
        .assets[] | select(.name | test($pattern; "i")) | .name
    ' "${release_file}" | head -n 1)"
    if [[ -z "${asset_name}" || "${asset_name}" == "null" ]]; then
        print -u2 "No compatible ${core_name} Apple Silicon asset was found in ${repository}."
        exit 1
    fi

    local asset_url checksum archive_file
    asset_url="$(jq -r --arg name "${asset_name}" '
        .assets[] | select(.name == $name) | .browser_download_url
    ' "${release_file}")"
    checksum="$(jq -r --arg name "${asset_name}" '
        .assets[] | select(.name == $name) | .digest
    ' "${release_file}")"
    if [[ ! "${checksum}" =~ '^sha256:[0-9a-fA-F]{64}$' ]]; then
        print -u2 "The official ${core_name} release did not include a SHA-256 digest."
        exit 1
    fi

    archive_file="${work_dir}/${asset_name}"
    curl --fail --location --retry 3 --retry-delay 2 \
        --header 'User-Agent: NekoBox-macOS-build' \
        "${asset_url}" \
        --output "${archive_file}"
    print -r -- "${checksum#sha256:}  ${archive_file}" | shasum -a 256 --check --status -

    mkdir -p "${extraction_dir}"
    if [[ "${archive_type}" == "zip" ]]; then
        unzip -qq "${archive_file}" -d "${extraction_dir}"
    else
        tar -xzf "${archive_file}" -C "${extraction_dir}"
    fi

    local executable
    executable="$(find "${extraction_dir}" -type f -name "${core_name}" -print -quit)"
    if [[ -z "${executable}" ]]; then
        print -u2 "The ${asset_name} archive does not contain ${core_name}."
        exit 1
    fi

    install -m 755 "${executable}" "${resource_dir}/${core_name}"
    print "Embedded ${core_name} from ${asset_name}."
}

download_core xray XTLS/Xray-core '^Xray-macos-arm64.*\.zip$' zip
download_core sing-box SagerNet/sing-box '^sing-box-.*-darwin-arm64\.tar\.gz$' tar

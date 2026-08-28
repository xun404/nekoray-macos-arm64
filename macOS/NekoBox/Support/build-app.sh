#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
output_app="${1:-${package_dir}/.build/NekoBox.app}"
core_resource_dir="${NEKOBOX_CORE_RESOURCE_DIR:-${package_dir}/Resources}"
swift build --package-path "${package_dir}" -c release
binary_dir="$(swift build --package-path "${package_dir}" -c release --show-bin-path)"

mkdir -p "${output_app}/Contents/MacOS" "${output_app}/Contents/Resources"
cp "${binary_dir}/NekoBox" "${output_app}/Contents/MacOS/NekoBox"
cp "${package_dir}/Resources/Info.plist" "${output_app}/Contents/Info.plist"
for core_name in xray sing-box; do
    bundled_core="${core_resource_dir}/${core_name}"
    if [[ -x "${bundled_core}" ]]; then
        cp "${bundled_core}" "${output_app}/Contents/Resources/${core_name}"
        codesign --force --sign - "${output_app}/Contents/Resources/${core_name}"
    fi
done
codesign --force --sign - "${output_app}"

print "Built ${output_app}"

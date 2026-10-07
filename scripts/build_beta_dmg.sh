#!/bin/zsh

set -eu
export COPYFILE_DISABLE=1

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
version="0.7.0"
build_directory="${project_directory}/build"
dist_directory="${project_directory}/dist"
pkg_root_directory="${build_directory}/pkg-root"
pkg_scripts_directory="${build_directory}/pkg-scripts"
pkg_path="${build_directory}/RightClick Converter Installer.pkg"
dmg_source_directory="${build_directory}/dmg-source"
built_app="${build_directory}/Finder Audio Tools.app"
dmg_path="${dist_directory}/RightClick-Converter-${version}.dmg"

"${script_directory}/build_finder_extension.sh"

/bin/rm -rf "${pkg_root_directory}" "${pkg_scripts_directory}" "${dmg_source_directory}"
/bin/mkdir -p \
    "${pkg_root_directory}/Applications" \
    "${pkg_scripts_directory}" \
    "${dmg_source_directory}" \
    "${dist_directory}"

/usr/bin/ditto "${built_app}" "${pkg_root_directory}/Applications/RightClick Converter.app"
/bin/cp "${project_directory}/packaging/scripts/postinstall" "${pkg_scripts_directory}/postinstall"
/bin/chmod 755 "${pkg_scripts_directory}/postinstall"

/usr/bin/pkgbuild \
    --root "${pkg_root_directory}" \
    --component-plist "${project_directory}/packaging/Component.plist" \
    --scripts "${pkg_scripts_directory}" \
    --identifier "com.finderaudiotools.installer" \
    --version "${version}" \
    --install-location / \
    "${pkg_path}"

/usr/bin/ditto "${pkg_path}" "${dmg_source_directory}/RightClick Converter Installer.pkg"
/bin/cp "${project_directory}/packaging/Installation Guide.txt" "${dmg_source_directory}/Installation Guide.txt"

/usr/bin/xattr -cr "${dmg_source_directory}" 2>/dev/null || true

/bin/rm -f "${dmg_path}"
/usr/bin/hdiutil create \
    -volname "RightClick Converter ${version}" \
    -srcfolder "${dmg_source_directory}" \
    -ov \
    -format UDZO \
    "${dmg_path}"

(
    cd "${dist_directory}"
    LC_ALL=C /usr/bin/shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256"
)

print -r -- "安装镜像已生成：${dmg_path}"
/bin/cat "${dmg_path}.sha256"

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Don Selkirk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/qdm12/gluetun | https://www.qbittorrent.org/

if [[ -n "${GETSUITE_BUILD_FUNC_PATH:-}" ]]; then
  # The repository bootstrap supplies a temporary copy of the current upstream
  # helper with only its application-installer URL redirected to this project.
  source "$GETSUITE_BUILD_FUNC_PATH"
else
  source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
fi

APP="GetSuite"
var_tags="${var_tags:-download;vpn;torrent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-0}"
var_tun="${var_tun:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/local/bin/getsuite ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  /usr/local/bin/getsuite update
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Manage applications inside the LXC with:${CL} ${BGN}getsuite${CL}"
echo -e "${INFO}${YW}Add applications later with:${CL} ${BGN}getsuite add${CL}"
echo -e "${INFO}${YW}Update all installed applications with:${CL} ${BGN}update${CL}"
echo -e "${INFO}${YW}Application ports:${CL} ${BGN}qBittorrent 8090${CL}"
echo -e "${INFO}${YW}Check the VPN connection with:${CL} ${BGN}getsuite vpn status${CL}"

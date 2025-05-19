#!/bin/sh

# Copyright (C) 2022-2024 Thien Tran
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -eu -o pipefail

staging="sys-net"

unpriv(){
  sudo -u nobody "${@}"
}

download() {
  directory=$(dirname "${2}")
  sudo mkdir -p $directory
  unpriv curl -s --proxy http://127.0.0.1:8082 "${1}" | sudo tee "${2}" > /dev/null
}

stage() {
    # Clean previous files
  sudo rm -rf "./$staging"

  umask 022

  # Setup NTS
  download https://raw.githubusercontent.com/GrapheneOS/infrastructure/main/etc/chrony.conf $staging/etc/chrony.conf
  download https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysconfig/chronyd $staging/etc/sysconfig/chronyd

  # Theming
  download https://raw.githubusercontent.com/nxn/QubesOS-Scripts/main/etc/gtk-3.0/settings.ini $staging/etc/gtk-3.0/settings.ini
  download https://raw.githubusercontent.com/nxn/QubesOS-Scripts/main/etc/gtk-4.0/settings.ini $staging/etc/gtk-4.0/settings.ini

  # Networking
  download https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/NetworkManager/conf.d/00-macrandomize.conf $staging/etc/NetworkManager/conf.d/00-macrandomize.conf
  download https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/NetworkManager/conf.d/01-transient-hostname.conf $staging/etc/NetworkManager/conf.d/01-transient-hostname.conf

  download https://gitlab.com/divested/brace/-/raw/master/brace/usr/lib/systemd/system/NetworkManager.service.d/99-brace.conf $staging/etc/systemd/system/NetworkManager.service.d/99-brace.conf
  sudo sed -i 's@ReadOnlyPaths=/etc/NetworkManager@#ReadOnlyPaths=/etc/NetworkManager@' $staging/etc/systemd/system/NetworkManager.service.d/99-brace.conf
  sudo sed -i 's@ReadWritePaths=-/etc/NetworkManager/system-connections@#ReadWritePaths=-/etc/NetworkManager/system-connections@' $staging/etc/systemd/system/NetworkManager.service.d/99-brace.conf

  umask 077
}

install() {
  # Install necessary packages
  # sudo dnf install -y @hardware-support arc-theme chrony gnome-keyring fwupd-qubes-vm NetworkManager-wifi network-manager-applet qubes-core-agent-dom0-updates qubes-core-agent-networking qubes-core-agent-network-manager qubes-usb-proxy xfce4-notifyd

  sudo dnf install -y @hardware-support chrony gnome-keyring NetworkManager-wifi network-manager-applet qubes-core-agent-networking qubes-core-agent-network-manager xfce4-notifyd
}


backup() {
  sudo rm -rf "./$staging-backup"
  sudo mkdir -p "./$staging-backup"

  files=(`find $staging -type f | sed "s/$staging//g"`)
  for file in "${files[@]}"
  do
    if test -f ${file}; then
      sudo cp --parents ${file} "$staging-backup"
    fi
  done
}

deploy() {
  # Deploy configs/files
  cd $staging
  tar cf - * | sudo tar -C / -xf -
  cd ..

  sudo hostnamectl hostname 'localhost'
  sudo hostnamectl --transient hostname ''
}

case ${1-noop} in
  run)
    install
    stage
    backup
    deploy
    echo "Complete"
    ;;

  install)
    install
    echo "Packages installed"
    ;;

  stage)
    stage
    echo "Files staged"
    ;;

  backup)
    backup
    echo "Files backed up"
    ;;

  deploy)
    deploy
    echo "Deployment complete"
    ;;

  *)
    echo 'Specify operation: run, install, stage, backup'
    ;;

esac

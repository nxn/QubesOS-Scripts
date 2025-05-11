#!/bin/sh

# Copyright (C) 2022-2025 Thien Tran
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

staging="fedora-minimal"

unpriv(){
  sudo -u nobody "${@}"
}

download() {
  directory=$(dirname "${2}")
  sudo mkdir -p $directory
  unpriv curl -s --proxy http://127.0.0.1:8082 "${1}" | sudo tee "${2}" > /dev/null
}

stage_files() {
  # Clean previous files
  sudo rm -rf "./$staging"

  umask 022
  sudo mkdir -p $staging/etc
  cat /etc/login.defs | sed 's/^UMASK.*/UMASK 077/g' | sed 's/^HOME_MODE/#HOME_MODE/g' | sudo tee $staging/etc/login.defs > /dev/null
  cat /etc/bashrc | sed 's/umask 022/umask 077/g' | sudo tee $staging/etc/bashrc > /dev/null
  
  # Setup hardened_malloc
  echo 'libhardened_malloc.so' | sudo tee $staging/etc/ld.so.preload > /dev/null

  # Prepare for SELinux
  sudo touch $staging/.autorelabel

  # Harden SSH
  download https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/ssh/ssh_config.d/10-custom.conf $staging/etc/ssh/ssh_config.d/10-custom.conf

  # Security kernel settings
  download https://raw.githubusercontent.com/secureblue/secureblue/refs/heads/live/files/system/etc/modprobe.d/blacklist.conf $staging/etc/modprobe.d/workstation-blacklist.conf
  download https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysctl.d/99-workstation.conf $staging/etc/sysctl.d/99-workstation.conf
  
  # Setup ZRAM
  download https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/zram-generator.conf $staging/etc/systemd/zram-generator.conf
  
  download https://raw.githubusercontent.com/nxn/QubesOS-Scripts/main/etc/X11/Xresources $staging/etc/systemd/zram-generator.conf
  umask 077
}

backup_files() {
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

deploy_files() {
  cd $staging
  tar cf - * | sudo tar -C / -xf -
  cd ..

  # Make home directory private
  chmod 700 /home/*
}

install_packages() {
  # Install necessary packages
  sudo dnf install -y qubes-core-agent-selinux

  # Setup hardened_malloc
  sudo https_proxy=https://127.0.0.1:8082 dnf copr enable secureblue/hardened_malloc -y
  sudo dnf install -y hardened_malloc
}

#start_services() { }

stop_services() {
  # Compliance
  systemctl mask debug-shell.service
  systemctl mask kdump.service

  # Disable timesyncd
  systemctl disable --now systemd-timesyncd
  systemctl mask systemd-timesyncd
}

configure() {
  install_packages
  stop_services
  deploy_files
  #start_services

  # Dracut doesn't seem to work - need to investigate
  # dracut -f
  # sudo sysctl -p
}

case ${1-noop} in
  configure)
    configure
    echo "Configuration complete"
    ;;

  stage)
    stage_files
    echo "Files staged; review before proceeding"
    ;;

  backup)
    backup_files
    echo "Files backed up"
    ;;

  *)
    echo 'Specify operation. Run in following order: "stage", "backup", "configure"'
    ;;

esac
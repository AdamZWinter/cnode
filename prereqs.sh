#!/bin/bash

unset CNODE_HOME

##########################################
# User Variables - Change as desired     #
# command line flags override set values #
##########################################

#INTERACTIVE='N'        # Interactive mode (Default: silent mode)
#NETWORK='mainnet'      # Connect to specified network instead of public network (Default: connect to public cardano network)
WANT_BUILD_DEPS='N'    # Skip installing OS level dependencies (Default: will check and install any missing OS level prerequisites)
#FORCE_OVERWRITE='N'    # Force overwrite of all files including normally saved user config sections in env, cnode.sh and gLiveView.sh
                        # topology.json, config.json and genesis files normally saved will also be overwritten
#LIBSODIUM_FORK='N'     # Use IOG fork of libsodium - Recommended as per IOG instructions (Default: system build)
#INSTALL_CNCLI='N'      # Install/Upgrade and build CNCLI with RUST
CNODE_NAME='cnode'     # Alternate name for top level folder, non alpha-numeric chars will be replaced with underscore (Default: cnode)
#CURL_TIMEOUT=60        # Maximum time in seconds that you allow the file download operation to take before aborting (Default: 60s)
#UPDATE_CHECK='Y'       # Check if there is an updated version of prereqs.sh script to download
SUDO='N'               # Used by docker builds to disable sudo, leave unchanged if unsure.

######################################
# Do NOT modify code below           #
######################################

get_input() {
  printf "%s (default: %s): " "$1" "$2" >&2; read -r answer
  if [ -z "$answer" ]; then echo "$2"; else echo "$answer"; fi
}

get_answer() {

  printf "%s (yes/no): " "$*" >&2; read -r answer
  while : 
  do
    case $answer in
    [Yy]*)
      return 0;;
    [Nn]*)
      return 1;;
    *) printf "%s" "Please enter 'yes' or 'no' to continue: " >&2; read -r answer
    esac
  done
}

err_exit() {
  printf "%s\nExiting...\n" "$*" >&2
  pushd -0 >/dev/null && dirs -c
  exit 1
}

versionCheck() { printf '%s\n%s' "${1//v/}" "${2//v/}" | sort -C -V; } #$1=available_version, $2=installed_version

usage() {
  cat <<EOF >&2

Usage: $(basename "$0") [-f] [-s] [-i] [-l] [-c] [-b <branch>] [-n <testnet|guild>] [-t <name>] [-m <seconds>]
Install pre-requisites for building cardano node and using CNTools

-f    Force overwrite of all files including normally saved user config sections in env, cnode.sh and gLiveView.sh
      topology.json, config.json and genesis files normally saved will also be overwritten
-s    Skip installing OS level dependencies (Default: will check and install any missing OS level prerequisites)
-n    Connect to specified network instead of public network (Default: connect to public cardano network)
      eg: -n testnet
-t    Alternate name for top level folder, non alpha-numeric chars will be replaced with underscore (Default: cnode)
-m    Maximum time in seconds that you allow the file download operation to take before aborting (Default: 60s)
-l    Use IOG fork of libsodium - Recommended as per IOG instructions (Default: system build)
-c    Install/Upgrade and build CNCLI with RUST
-b    Use alternate branch of scripts to download - only recommended for testing/development (Default: master)
-i    Interactive mode (Default: silent mode)

EOF
  exit 1
}

while getopts :in:sflct:m:b: opt; do
  case ${opt} in
    i ) INTERACTIVE='Y' ;;
    n ) NETWORK=${OPTARG} ;;
    s ) WANT_BUILD_DEPS='N' ;;
    f ) FORCE_OVERWRITE='Y' ;;
    l ) LIBSODIUM_FORK='Y' ;;
    c ) INSTALL_CNCLI='Y' ;;
    t ) CNODE_NAME=${OPTARG//[^[:alnum:]]/_} ;;
    m ) CURL_TIMEOUT=${OPTARG} ;;
    b ) BRANCH=${OPTARG} ;;
    \? ) usage ;;
    esac
done
shift $((OPTIND -1))

[[ -z ${INTERACTIVE} ]] && INTERACTIVE='N'
[[ -z ${NETWORK} ]] && NETWORK='mainnet'
[[ -z ${WANT_BUILD_DEPS} ]] && WANT_BUILD_DEPS='Y'
[[ -z ${FORCE_OVERWRITE} ]] && FORCE_OVERWRITE='N'
[[ -z ${LIBSODIUM_FORK} ]] && LIBSODIUM_FORK='N'
[[ -z ${INSTALL_CNCLI} ]] && INSTALL_CNCLI='N'
[[ -z ${CNODE_NAME} ]] && CNODE_NAME='cnode'
[[ -z ${INTERACTIVE} ]] && INTERACTIVE='N'
[[ -z ${CURL_TIMEOUT} ]] && CURL_TIMEOUT=60
[[ -z ${UPDATE_CHECK} ]] && UPDATE_CHECK='Y'
[[ -z ${SUDO} ]] && SUDO='Y'
[[ "${SUDO}" = 'Y' ]] && sudo="sudo" || sudo=""
[[ "${SUDO}" = 'Y' && $(id -u) -eq 0 ]] && err_exit "Please run as non-root user."

# For who runs the script within containers and running it as root.
U_ID=$(id -u)
G_ID=$(id -g)

dirs -c # clear dir stack
CNODE_PATH="/root"
CNODE_HOME=${CNODE_PATH}/${CNODE_NAME}
CNODE_VNAME=$(echo "$CNODE_NAME" | awk '{print toupper($0)}')
if [[ -z "${BRANCH}" ]]; then
  BRANCH="master"
fi

REPO="https://github.com/cardano-community/guild-operators"
REPO_RAW="https://raw.githubusercontent.com/cardano-community/guild-operators"
URL_RAW="${REPO_RAW}/${BRANCH}"

if [ "${INTERACTIVE}" = 'Y' ]; then
  clear;
  CNODE_PATH=$(get_input "Please enter the project path" ${CNODE_PATH})
  CNODE_NAME=$(get_input "Please enter directory name" ${CNODE_NAME})
  CNODE_HOME=${CNODE_PATH}/${CNODE_NAME}
  CNODE_VNAME=$(echo "$CNODE_NAME" | awk '{print toupper($0)}')

  if [ -d "${CNODE_HOME}" ]; then
    err_exit "The \"${CNODE_HOME}\" directory exist, pls remove or choose an other one."
  fi

  if ! get_answer "Do you want to install build dependencies for cardano node?"; then
    WANT_BUILD_DEPS='N'
  fi
fi

#Guild list of dependencies is as follows:
#coreutils pkgconfig libffi-devel gmp-devel openssl-devel ncurses-libs ncurses-compat-libs systemd systemd-devel libsodium-devel zlib-devel make gcc-c++ tmux git jq gnupg libtool autoconf srm iproute bc tcptraceroute dialog sqlite util-linux xz
yum install -y jq iproute

if [ "$WANT_BUILD_DEPS" = 'Y' ]; then

  # Determine OS platform
  OS_ID=$(grep -i ^id_like= /etc/os-release | cut -d= -f 2)
  DISTRO=$(grep -i ^NAME= /etc/os-release | cut -d= -f 2)

  if [[ "${OS_ID}" =~ ebian ]] || [[ "${DISTRO}" =~ ebian ]]; then
    #Debian/Ubuntu
    echo "Using apt to prepare packages for ${DISTRO} system"
    echo "  Updating system packages..."
    $sudo apt-get -y install curl > /dev/null
    $sudo apt-get -y update > /dev/null
    echo "  Installing missing prerequisite packages, if any.."
    pkg_list="libpq-dev python3 build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev systemd libsystemd-dev libsodium-dev zlib1g-dev make g++ tmux git jq libncursesw5 gnupg aptitude libtool autoconf secure-delete iproute2 bc tcptraceroute dialog sqlite automake sqlite3 bsdmainutils"
    $sudo apt-get -y install ${pkg_list} > /dev/null;rc=$?
    if [ $rc != 0 ]; then
      echo "An error occurred while installing the prerequisite packages, please investigate by using the command below:"
      echo "sudo apt-get -y install ${pkg_list}"
      echo "It would be best if you could submit an issue at ${REPO} with the details to tackle in future, as some errors may be due to external/already present dependencies"
      err_exit
    fi
  elif [[ "${OS_ID}" =~ rhel ]] || [[ "${DISTRO}" =~ Fedora ]]; then
    #CentOS/RHEL/Fedora
    echo "Using yum to prepare packages for ${DISTRO} system"
    echo "  Updating system packages..."
    $sudo yum -y install curl > /dev/null
    $sudo yum -y update > /dev/null
    echo "  Installing missing prerequisite packages, if any.."
    pkg_list="python3 coreutils pkgconfig libffi-devel gmp-devel openssl-devel ncurses-libs ncurses-compat-libs systemd systemd-devel libsodium-devel zlib-devel make gcc-c++ tmux git jq gnupg libtool autoconf srm iproute bc tcptraceroute dialog sqlite util-linux xz"
    [[ ! "${DISTRO}" =~ Fedora ]] && $sudo yum -y install epel-release > /dev/null
    $sudo yum -y install ${pkg_list} > /dev/null;rc=$?
    if [ $rc != 0 ]; then
      echo "An error occurred while installing the prerequisite packages, please investigate by using the command below:"
      echo "sudo yum -y install ${pkg_list}"
      echo "It would be best if you could submit an issue at ${REPO} with the details to tackle in future, as some errors may be due to external/already present dependencies"
      err_exit
    fi
    if [ -f /usr/lib64/libtinfo.so ] && [ -f /usr/lib64/libtinfo.so.5 ]; then
      echo "  Symlink updates not required for ncurse libs, skipping.."
    else
      echo "  Updating symlinks for ncurse libs.."
      $sudo ln -s "$(find /usr/lib64/libtinfo.so* | tail -1)" /usr/lib64/libtinfo.so
      $sudo ln -s "$(find /usr/lib64/libtinfo.so* | tail -1)" /usr/lib64/libtinfo.so.5
    fi
  elif [[ $(uname) == Darwin ]]; then
    echo "MacOS detected";
    pkg_list="coreutils gnupg jq libsodium tcptraceroute"
    brew install "${pkg_list}" > /dev/null;rc=$?

    if [ $rc != 0 ]; then
      echo "An error occurred while installing the prerequisite packages, please investigate by using the command below:"
      echo "brew install ${pkg_list}"
      echo "It would be best if you could submit an issue at ${REPO} with the details to tackle in future, as some errors may be due to external/already present dependencies"
      err_exit
    fi
  else
    echo "We have no automated procedures for this ${DISTRO} system"
    echo "please manually install required packages."
    echo "Their relative names are:"
    echo "Debian: curl build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev libsystemd-dev zlib1g-dev tmux"
    echo "CentOS: curl pkgconfig libffi-devel gmp-devel openssl-devel ncurses-libs ncurses-compat-libs systemd-devel zlib-devel tmux"
    err_exit
  fi
  
  #Guild list of dependencies is as follows:
  #coreutils pkgconfig libffi-devel gmp-devel openssl-devel ncurses-libs ncurses-compat-libs systemd systemd-devel libsodium-devel zlib-devel make gcc-c++ tmux git jq gnupg libtool autoconf srm iproute bc tcptraceroute dialog sqlite util-linux xz
  #yum install -y jq iproute 
  
  if ! ghc --version | grep -q 8\.10\.2 || ! cabal --version | grep -q version\ 3; then
    echo "Install ghcup (The Haskell Toolchain installer) .."
    # TMP: Dirty hack to prevent ghcup interactive setup, yet allow profile set up
    unset BOOTSTRAP_HASKELL_NONINTERACTIVE
    export BOOTSTRAP_HASKELL_NO_UPGRADE=1
    curl -s -m ${CURL_TIMEOUT} --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sed -e 's#read.*#answer=Y;next_answer=Y;hls_answer=N#' | bash
    # shellcheck source=/dev/null
    . "${HOME}"/.ghcup/env

    ghcup install 8.10.2
    ghcup set 8.10.2
    ghc --version

    echo "Installing bundled Cabal .."
    ghcup install-cabal
  fi
fi

# END OF Install build deps.

echo "Creating Folder Structure .."

if grep -q "${CNODE_VNAME}_HOME" "${HOME}"/.bashrc; then
  echo "Environment Variable already set up!"
else
  echo "Setting up Environment Variable"
  echo "export PATH=/root/.local/bin:$PATH" >> "${HOME}"/.bashrc
  echo "export ${CNODE_VNAME}_HOME=${CNODE_HOME}" >> "${HOME}"/.bashrc
  echo "export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH" >> "${HOME}"/.bashrc
  echo "export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH" >> "${HOME}"/.bashrc
  # shellcheck source=/dev/null
  . "${HOME}/".bashrc
fi

mkdir -p "${HOME}"/git > /dev/null 2>&1 # To hold git repositories that will be used for building binaries

$sudo mkdir -p "${CNODE_HOME}"/db "${CNODE_HOME}"/logs "${CNODE_HOME}"/sockets "${CNODE_HOME}"/priv
$sudo chown -R "$U_ID":"$G_ID" "${CNODE_HOME}" 2>/dev/null

chmod -R 755 "${CNODE_HOME}" 2>/dev/null
chmod -R 700 "${CNODE_HOME}"/priv 2>/dev/null

#!/usr/bin/env bash
# Cloud Agent environment bootstrap for LayerStudio (Flutter mobile DAW).
#
# Installs the Flutter SDK and Android SDK/NDK required to analyze, test, and
# build the Android app, then fetches project dependencies. Designed to be
# idempotent: heavy toolchains are only downloaded when missing, so re-runs and
# environment-build caching stay fast.
set -euo pipefail

FLUTTER_VERSION="3.35.0"
FLUTTER_HOME="/opt/flutter"
ANDROID_SDK_ROOT="/opt/android-sdk"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-11076708_latest.zip"

log() { echo ">>> $*"; }

# --- System packages -------------------------------------------------------
# Flutter + the Android toolchain need a JDK, plus these unpack/download tools.
ensure_system_deps() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v unzip >/dev/null 2>&1 || missing+=("unzip")
  command -v xz >/dev/null 2>&1 || missing+=("xz-utils")
  command -v git >/dev/null 2>&1 || missing+=("git")
  command -v java >/dev/null 2>&1 || missing+=("openjdk-17-jdk")
  if ((${#missing[@]})); then
    log "Installing system packages: ${missing[*]}"
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  fi
}

# --- Flutter SDK -----------------------------------------------------------
ensure_flutter() {
  if [[ ! -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    log "Installing Flutter ${FLUTTER_VERSION} to ${FLUTTER_HOME}"
    sudo mkdir -p "$(dirname "${FLUTTER_HOME}")"
    curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    sudo rm -rf "${FLUTTER_HOME}"
    sudo tar -xJf /tmp/flutter.tar.xz -C "$(dirname "${FLUTTER_HOME}")"
    sudo chown -R "$(id -u):$(id -g)" "${FLUTTER_HOME}"
    rm -f /tmp/flutter.tar.xz
  fi
  git config --global --add safe.directory "${FLUTTER_HOME}" || true
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
  sudo ln -sf "${FLUTTER_HOME}/bin/flutter" /usr/local/bin/flutter
  sudo ln -sf "${FLUTTER_HOME}/bin/dart" /usr/local/bin/dart
  flutter --version
  flutter config --no-analytics >/dev/null 2>&1 || true
}

# --- Android SDK / NDK -----------------------------------------------------
ensure_android_sdk() {
  local sdkmanager="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "${sdkmanager}" ]]; then
    log "Installing Android command-line tools to ${ANDROID_SDK_ROOT}"
    sudo mkdir -p "${ANDROID_SDK_ROOT}"
    sudo chown -R "$(id -u):$(id -g)" "${ANDROID_SDK_ROOT}"
    curl -fsSL -o /tmp/cmdtools.zip \
      "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}"
    mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
    rm -rf "${ANDROID_SDK_ROOT}/cmdline-tools/latest" "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools"
    unzip -q /tmp/cmdtools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools"
    mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
    rm -f /tmp/cmdtools.zip
  fi
  export ANDROID_SDK_ROOT
  export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

  log "Accepting Android SDK licenses"
  yes | sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null 2>&1 || true

  # Versions match Flutter 3.35.0 defaults and the Gradle plugins used by the
  # app (android-35/36 + build-tools 35 + NDK 27 + CMake for native audio).
  log "Installing Android SDK packages"
  sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" \
    "platform-tools" \
    "platforms;android-35" \
    "platforms;android-36" \
    "build-tools;35.0.0" \
    "ndk;27.0.12077973" \
    "cmake;3.22.1" >/dev/null

  flutter config --android-sdk "${ANDROID_SDK_ROOT}" >/dev/null 2>&1 || true

  # Make the toolchain discoverable in interactive agent shells too.
  sudo tee /etc/profile.d/layerstudio-env.sh >/dev/null <<EOF
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
export PATH="${FLUTTER_HOME}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:\$PATH"
EOF
}

# --- Project dependencies --------------------------------------------------
ensure_project_deps() {
  log "Fetching Flutter package dependencies"
  flutter pub get
  # Warm Android engine artifacts so the first build is faster.
  flutter precache --android >/dev/null 2>&1 || true
}

ensure_system_deps
ensure_flutter
ensure_android_sdk
ensure_project_deps

log "LayerStudio Cloud Agent environment is ready."

#!/usr/bin/env bash

# Checksum-pinned release binaries used by CI scripts when the exact local
# version is unavailable. GitHub release assets avoid anonymous Docker Hub pulls
# in the required check, and the checksums make the fallback immutable.

verify_sha256() {
  local file="$1" expected="$2" actual

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for $file: expected $expected, got $actual" >&2
    return 1
  fi
}

platform_key() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os/$arch" in
    Darwin/arm64) printf '%s\n' darwin-arm64 ;;
    Darwin/x86_64) printf '%s\n' darwin-x86_64 ;;
    Linux/aarch64 | Linux/arm64) printf '%s\n' linux-arm64 ;;
    Linux/x86_64 | Linux/amd64) printf '%s\n' linux-x86_64 ;;
    *) echo "unsupported CI tool platform: $os/$arch" >&2; return 1 ;;
  esac
}

download_archive_binary() {
  local url="$1" checksum="$2" member="$3" destination="$4"
  local archive extract_dir
  archive="$(mktemp)"
  extract_dir="$(mktemp -d)"

  if ! curl --fail --location --silent --show-error "$url" --output "$archive"; then
    rm -f "$archive"
    rmdir "$extract_dir"
    return 1
  fi

  verify_sha256 "$archive" "$checksum"
  tar -xzf "$archive" -C "$extract_dir"
  install -m 0755 "$extract_dir/$member" "$destination"
  rm -f "$archive"
  rm -rf "$extract_dir"
}

install_actionlint() {
  local destination="$1" platform asset checksum
  platform="$(platform_key)"

  case "$platform" in
    darwin-arm64) asset="actionlint_1.7.12_darwin_arm64.tar.gz"; checksum="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f" ;;
    darwin-x86_64) asset="actionlint_1.7.12_darwin_amd64.tar.gz"; checksum="5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644" ;;
    linux-arm64) asset="actionlint_1.7.12_linux_arm64.tar.gz"; checksum="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6" ;;
    linux-x86_64) asset="actionlint_1.7.12_linux_amd64.tar.gz"; checksum="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8" ;;
  esac

  download_archive_binary \
    "https://github.com/rhysd/actionlint/releases/download/v1.7.12/$asset" \
    "$checksum" actionlint "$destination"
}

install_shellcheck() {
  local destination="$1" platform asset checksum directory
  platform="$(platform_key)"

  case "$platform" in
    darwin-arm64) asset="shellcheck-v0.11.0.darwin.aarch64.tar.gz"; checksum="339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f" ;;
    darwin-x86_64) asset="shellcheck-v0.11.0.darwin.x86_64.tar.gz"; checksum="c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51" ;;
    linux-arm64) asset="shellcheck-v0.11.0.linux.aarch64.tar.gz"; checksum="68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc" ;;
    linux-x86_64) asset="shellcheck-v0.11.0.linux.x86_64.tar.gz"; checksum="b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6" ;;
  esac
  directory="shellcheck-v0.11.0"

  download_archive_binary \
    "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/$asset" \
    "$checksum" "$directory/shellcheck" "$destination"
}

install_helm_docs() {
  local destination="$1" platform asset checksum
  platform="$(platform_key)"

  case "$platform" in
    darwin-arm64) asset="helm-docs_1.14.2_Darwin_arm64.tar.gz"; checksum="2d8399db5b33d240d5f8985241bcf5483563150b968e3229823822979f3e4b8b" ;;
    darwin-x86_64) asset="helm-docs_1.14.2_Darwin_x86_64.tar.gz"; checksum="b2f1ffd0feef8dc0901a38a2053481d1d67b63ca30da4ac774166c6b52fa2245" ;;
    linux-arm64) asset="helm-docs_1.14.2_Linux_arm64.tar.gz"; checksum="c3787212332386dcd122debef7848feb165aa701467ae3e3442df7638f3ac4e4" ;;
    linux-x86_64) asset="helm-docs_1.14.2_Linux_x86_64.tar.gz"; checksum="a8cf72ada34fad93285ba2a452b38bdc5bd52cc9a571236244ec31022928d6cc" ;;
  esac

  download_archive_binary \
    "https://github.com/norwoodj/helm-docs/releases/download/v1.14.2/$asset" \
    "$checksum" helm-docs "$destination"
}

#!/data/data/com.termux/files/usr/bin/sh
# Wrangler for Termux/Android.
#
# Installs the official Wrangler npm package, patches the local workerd
# bootstrap (there is no Android workerd binary), and replaces the broken
# npm shebang shim with a Termux-safe launcher.
set -eu

REPOSITORY="${WRANGLER_TERMUX_REPO:-samperez10/wrangler-termux}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
VERSION="${WRANGLER_TERMUX_VERSION:-}"

fail() { printf 'wrangler-termux: %s\n' "$*" >&2; exit 1; }
say()  { printf '%s\n' "$*"; }

case "$PREFIX" in
    /data/data/com.termux/files/usr) ;;
    *) fail "run this installer inside Termux (PREFIX=$PREFIX)" ;;
esac
[ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "x86_64" ] || \
    fail "only Termux aarch64/x86_64 is supported"
command -v pkg >/dev/null 2>&1 || fail "Termux package manager not found"

if ! command -v curl >/dev/null 2>&1; then
    say "Installing curl..."
    pkg install -y curl || fail "could not install curl"
fi

if ! command -v node >/dev/null 2>&1; then
    say "Installing Node.js..."
    pkg install -y nodejs || fail "could not install Node.js"
fi
command -v node >/dev/null 2>&1 || fail "node is not available after installation"
NODE_BIN="$(command -v node)"

# Recent Termux nodejs packages list npm as an optional dependency instead of
# bundling it, so install it separately when the command is missing. If the
# Termux package cannot be installed (for example a corrupted mirror package),
# fall back to the official npm tarball from the npm registry.
install_npm_from_registry() {
    tmp="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/wrangler-npm.XXXXXX")"
    url="$(curl -fsSL --retry 3 https://registry.npmjs.org/npm/latest |
        "$NODE_BIN" -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{process.stdout.write(JSON.parse(s).dist.tarball)})')"
    [ -n "$url" ] || return 1
    curl -fsSL --retry 3 "$url" -o "$tmp/npm.tgz" || return 1
    mkdir -p "$PREFIX/lib/node_modules/npm"
    rm -rf "${PREFIX:?}/lib/node_modules/npm"/*
    tar -xzf "$tmp/npm.tgz" -C "$PREFIX/lib/node_modules/npm" --strip-components=1 || return 1
    rm -rf "$tmp"

    cat > "$PREFIX/bin/npm" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec "$NODE_BIN" "$PREFIX/lib/node_modules/npm/bin/npm-cli.js" "\$@"
EOF
    cat > "$PREFIX/bin/npx" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec "$NODE_BIN" "$PREFIX/lib/node_modules/npm/bin/npx-cli.js" "\$@"
EOF
    chmod 755 "$PREFIX/bin/npm" "$PREFIX/bin/npx"
}

if ! command -v npm >/dev/null 2>&1; then
    say "Installing npm..."
    if ! pkg install -y npm; then
        say "Termux npm package failed; installing npm from the npm registry..."
        install_npm_from_registry || fail "could not install npm"
    fi
fi
command -v npm >/dev/null 2>&1 || fail "npm is not available after installation"

if [ -z "$VERSION" ]; then
    release_json="$(curl -fsSL --connect-timeout 5 --max-time 10 \
        "https://github.com/$REPOSITORY/releases/latest/download/release.json" \
        2>/dev/null || true)"
    VERSION="$(printf '%s' "$release_json" |
        sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)"
fi
if [ -z "$VERSION" ]; then
    VERSION="$(npm view wrangler version 2>/dev/null || true)"
fi
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$' || \
    fail "could not resolve a valid Wrangler version"

say "Installing Wrangler $VERSION for Termux..."
npm install -g "wrangler@$VERSION" --ignore-scripts --no-audit --no-fund || \
    fail "npm install failed"

ROOT="$(npm root -g)"
MAIN="$(find "$ROOT" -path '*/workerd/lib/main.js' -type f -print -quit)"
[ -n "$MAIN" ] || fail "workerd/lib/main.js was not found under $ROOT"

MAIN="$MAIN" node <<'NODE'
const fs = require("fs");
const path = process.env.MAIN;
const source = fs.readFileSync(path, "utf8");
const oldLine = "var { binPath } = generateBinPath();";
const newLine = "/* termux-patch: no workerd binary for Android; only `wrangler dev` uses it */ var binPath; try { binPath = generateBinPath().binPath; } catch { binPath = \"/dev/null\"; }";
if (source.includes("termux-patch")) {
    console.log("workerd is already patched");
    process.exit(0);
}
if (!source.includes(oldLine)) {
    console.error("wrangler-termux: workerd bootstrap changed; patch pattern is missing");
    process.exit(1);
}
fs.writeFileSync(path, source.replace(oldLine, newLine));
console.log("patched workerd bootstrap");
NODE

WRANGLER_JS="$ROOT/wrangler/bin/wrangler.js"
[ -f "$WRANGLER_JS" ] || fail "wrangler entry point is missing: $WRANGLER_JS"

NODE_BIN="$(command -v node)"
BIN="$PREFIX/bin"
mkdir -p "$BIN"

# npm creates a symlink to a script with `#!/usr/bin/env node`; Termux has no
# /usr/bin/env. Replace it with a launcher that invokes the Termux node directly.
LAUNCHER="$BIN/wrangler"
rm -f "$LAUNCHER"
cat > "$LAUNCHER" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
set -eu
# A CLOUDFLARE_API_TOKEN exported for other tools (for example Claude Code)
# would silently override the OAuth login. Ignore it unless the user opts in.
if [ "\${1:-}" = "login" ]; then
    unset CLOUDFLARE_API_TOKEN
elif [ -n "\${WRANGLER_CLOUDFLARE_API_TOKEN:-}" ]; then
    CLOUDFLARE_API_TOKEN="\$WRANGLER_CLOUDFLARE_API_TOKEN"
    export CLOUDFLARE_API_TOKEN
elif [ "\${WRANGLER_TERMUX_USE_API_TOKEN:-0}" != "1" ]; then
    unset CLOUDFLARE_API_TOKEN
fi
exec "$NODE_BIN" "$WRANGLER_JS" "\$@"
EOF
chmod 755 "$LAUNCHER"

LOGIN="$BIN/wrangler-login"
cat > "$LOGIN" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
# Device-code login: no localhost callback server, so it also works when
# switching accounts or approving from another device.
set -eu
unset CLOUDFLARE_API_TOKEN
exec "$LAUNCHER" login --device --browser false "\$@"
EOF
chmod 755 "$LOGIN"

"$LAUNCHER" --version >/dev/null || fail "wrangler did not start after installation"

say "Installed: $("$LAUNCHER" --version)"
say "OAuth login: wrangler-login (device code) or wrangler login (browser callback)"
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    say "Note: CLOUDFLARE_API_TOKEN is set but ignored by wrangler by default."
    say "      Use WRANGLER_TERMUX_USE_API_TOKEN=1 to use it, or WRANGLER_CLOUDFLARE_API_TOKEN for a wrangler-only token."
fi
say "wrangler dev is not supported on Termux; deploy/secret/whoami/tail work."

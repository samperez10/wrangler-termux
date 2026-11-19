# Wrangler for Termux

Run [`wrangler`](https://developers.cloudflare.com/workers/wrangler/) on
Termux/Android.

Wrangler normally imports `workerd`, whose npm package has no Android binary.
This installer installs the official npm package, patches the `workerd`
bootstrap for Termux, and replaces npm's broken `/usr/bin/env` launcher with a
Termux-safe `wrangler` command.

`wrangler deploy`, `wrangler secret`, `wrangler whoami`, and `wrangler tail`
work. `wrangler dev` does not, because it requires the native workerd runtime.

## Install

From Termux:

```sh
pkg install -y curl
curl -fsSL https://github.com/samperez10/wrangler-termux/releases/latest/download/install.sh | sh
```

Then:

```sh
wrangler --version
```

The installer:

- checks that it is running in Termux;
- installs Node.js/npm and curl when missing;
- installs Wrangler from npm at the published release version;
- patches `workerd/lib/main.js`;
- installs a Termux-safe `wrangler` launcher and `wrangler-login` helper;
- verifies that Wrangler starts before finishing.

To install a specific version:

```sh
WRANGLER_TERMUX_VERSION=4.165.0 sh install.sh
```

## Login and API tokens

Cloudflare supports two authentication modes. Do not mix them.

### OAuth login

```sh
wrangler login
```

The `wrangler` launcher automatically unsets `CLOUDFLARE_API_TOKEN` when the
subcommand is `login`, so this works even if you normally keep an API token in
your environment.

You can also use:

```sh
wrangler-login
```

If the browser does not open on Termux:

```sh
wrangler login --browser false
```

Open the printed URL in a browser on the same device. The callback listens on
localhost, so the browser and Termux must be on the same phone.

### API token

```sh
export CLOUDFLARE_API_TOKEN='...'
wrangler whoami
```

In API-token mode, do **not** run `wrangler login`; Wrangler will correctly
report:

```text
You are logged in with an API Token. Unset CLOUDFLARE_API_TOKEN to log in via OAuth.
```

That is not an error in this setup. The `wrangler-login` helper exists for the
case where you want OAuth instead.

A token needs the **Workers Scripts: Edit** permission; the "Edit Cloudflare
Workers" template includes it. A read-only token can still run `wrangler
whoami`, but `wrangler deploy` then fails with:

```text
A request to the Cloudflare API (.../deployments) failed.
No access to the specified resource.
```

### Which credential wins

Wrangler prefers `CLOUDFLARE_API_TOKEN` whenever it is set, even after a
successful OAuth login. If you switch to OAuth, unset the variable (and remove
it from `~/.bashrc` or `~/.profile`) or Wrangler will keep using the token:

```sh
unset CLOUDFLARE_API_TOKEN
wrangler whoami
```

> `npx wrangler login` bypasses the Termux launcher and does not unset the
> token. Use `wrangler login` or `wrangler-login`.

Avoid `npx wrangler@4` or `npx --yes wrangler`: those download a fresh,
unpatched copy and fail on the missing Android `workerd` binary. Plain
`wrangler` and `npx wrangler` use the installed Termux launcher.

## Updates

The installer follows the version in the latest release's `release.json`. If
that file cannot be fetched, it falls back to the latest npm version.

To update:

```sh
curl -fsSL https://github.com/samperez10/wrangler-termux/releases/latest/download/install.sh | sh
```

GitHub Actions checks npm every six hours. When a new Wrangler version appears,
it prepares the installer, smoke-tests it in Termux ARM64, and publishes a new
release.

Manual runs are available from the **Package Wrangler for Termux** workflow,
with an optional version input.

## Why the patch?

`wrangler` imports `workerd` even for commands that never start the local
runtime. The npm `workerd` package throws on Android before Wrangler can print
its help or run `deploy`. The installer replaces the first `workerd` platform
lookup with a guarded stub. `wrangler dev` still cannot work because it needs
the real workerd binary; all remote API commands do work.

The npm global shim also uses `#!/usr/bin/env node`, which does not exist under
Termux. The installed `$PREFIX/bin/wrangler` is a small `sh` launcher that calls
the Termux `node` directly.

Upstream references:

- [cloudflare/workers-sdk](https://github.com/cloudflare/workers-sdk)
- [Wrangler documentation](https://developers.cloudflare.com/workers/wrangler/)
- [wrangler on npm](https://www.npmjs.com/package/wrangler)

## Project layout

```text
install.sh                         Termux installer and workerd patch
.github/workflows/release.yml      scheduled npm check, Termux smoke test, release
```

## License

MIT.

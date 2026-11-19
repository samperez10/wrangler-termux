# Wrangler for Termux

Run [`wrangler`](https://developers.cloudflare.com/workers/wrangler/) on
Termux/Android. The installer patches `workerd` (no Android binary) and adds a
Termux-safe launcher.

`deploy`, `secret`, `whoami`, and `tail` work. `wrangler dev` does not.

## Install

```sh
pkg install -y curl
curl -fsSL https://github.com/samperez10/wrangler-termux/releases/latest/download/install.sh | sh
wrangler --version
```

## Log in

```sh
wrangler-login
```

Open the printed URL and enter the code. You have five minutes, and you can
approve from any device. No localhost callback is involved.

Prefer the browser callback?

```sh
wrangler login --browser false
```

The callback listens on `localhost:8976` and expires after two minutes.

`wrangler logout` clears the local credential only. To use another account,
pick it on the Cloudflare page, use a private window, or sign out of
dash.cloudflare.com first.

## Deploy

```sh
cd your-worker
wrangler deploy
```

## API tokens (optional)

The launcher ignores `CLOUDFLARE_API_TOKEN` by default, because other tools
(Claude Code, for example) often export it. Use your OAuth login instead.

To opt in for one command:

```sh
WRANGLER_TERMUX_USE_API_TOKEN=1 wrangler whoami
```

Or use a Wrangler-only token:

```sh
export WRANGLER_CLOUDFLARE_API_TOKEN='...'
wrangler whoami
```

The token needs **Workers Scripts: Edit** (the "Edit Cloudflare Workers"
template).

## Update

Run the install command again. GitHub Actions checks npm every six hours and
publishes new releases.

## Notes

- `npx wrangler` uses the installed launcher; avoid `npx wrangler@4` or
  `npx --yes wrangler`, which download an unpatched copy.
- OAuth credentials live in `~/.config/.wrangler/config/default.toml`.
- Upstream: [cloudflare/workers-sdk](https://github.com/cloudflare/workers-sdk)

## License

MIT.

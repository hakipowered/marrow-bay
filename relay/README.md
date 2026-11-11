# Co-op relay

Lets two phones on different networks play together without port forwarding.
Free to run on Cloudflare Workers (Durable Objects free tier).

Deploy: `npx wrangler deploy` from this folder, then put the `wss://...workers.dev`
URL into `RELAY_URL` in `scripts/autoload/net.gd`.

Local test: `npm i ws && node local_relay.js`, then point the game at `ws://<pc-ip>:8787`.

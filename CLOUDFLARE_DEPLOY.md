# Cloudflare deployment

1. Install Node.js 18+ and run `npm install -D wrangler@latest` in this folder.
2. Run `npx wrangler login` and complete Cloudflare login in the browser.
3. Set Supabase secrets (never put these in index.html):
   `npx wrangler secret put SUPABASE_URL`
   `npx wrangler secret put SUPABASE_ANON_KEY`
4. Deploy: `npx wrangler deploy`
5. Copy the resulting `https://...workers.dev` URL.
6. In index.html set `window.DQ_LIVE_WORKER_URL` to that URL.
7. Deploy the website again.

The Worker uses Durable Object WebSocket Hibernation. `acceptWebSocket()` keeps clients connected while allowing the object to hibernate; `setWebSocketAutoResponse('ping','pong')` handles heartbeats without waking the object.

# Find A Doctor Live Queue — Cloudflare

## What this does
- One Durable Object room per doctor.
- Patients watching that doctor's live queue connect with WebSocket.
- The Worker broadcasts a tiny `queue_refresh` signal; clients then read the authoritative queue from Supabase.
- Supabase remains the database/source of truth.
- Durable Object WebSocket connections can hibernate when idle between events.

## Deploy
1. Install Wrangler: `npm install -g wrangler`
2. Login: `wrangler login`
3. From this folder run: `wrangler deploy`
4. Copy the deployed `https://...workers.dev` URL.
5. Put that URL in `LIVE_WORKER_URL` in `index.html`.

## Routes
- `GET /health`
- `GET /ws?doctor_id=<doctor-id>` — WebSocket
- `POST /broadcast?doctor_id=<doctor-id>` — sends a refresh signal

The broadcast endpoint intentionally contains no patient data. It is a cache-refresh signal only; clients fetch the actual queue from Supabase. For production, put an authentication/rate-limit layer in front of `/broadcast` if untrusted clients can call it directly.

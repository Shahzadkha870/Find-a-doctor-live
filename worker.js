import { DurableObject, WebSocketRequestResponsePair } from 'cloudflare:workers';

function corsHeaders(origin = '*') {
  return {
    'Access-Control-Allow-Origin': origin === 'null' ? '*' : origin,
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  };
}

async function verifyDoctor(env, doctorId, request) {
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return false;
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return false;
  const token = auth.slice(7).trim();
  try {
    const userRes = await fetch(`${env.SUPABASE_URL.replace(/\/$/,'')}/auth/v1/user`, {
      headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` }
    });
    if (!userRes.ok) return false;
    const user = await userRes.json();
    if (!user?.id) return false;
    const q = new URL(`${env.SUPABASE_URL.replace(/\/$/,'')}/rest/v1/doctors`);
    q.searchParams.set('select', 'id');
    q.searchParams.set('id', `eq.${doctorId}`);
    q.searchParams.set('user_id', `eq.${user.id}`);
    q.searchParams.set('limit', '1');
    const doctorRes = await fetch(q, {
      headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` }
    });
    if (!doctorRes.ok) return false;
    const rows = await doctorRes.json();
    return Array.isArray(rows) && rows.length === 1;
  } catch { return false; }
}

export class QueueRoom extends DurableObject {
  constructor(state, env) {
    super(state, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/ws') {
      if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') return new Response('Expected WebSocket', { status: 426 });
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ connectedAt: Date.now() });
      return new Response(null, { status: 101, webSocket: client });
    }
    if (url.pathname === '/broadcast' && request.method === 'POST') {
      let body;
      try { body = await request.json(); } catch { return new Response('Bad JSON', { status: 400 }); }
      const doctorId = request.headers.get('X-Doctor-Id');
      const type = typeof body?.type === 'string' ? body.type : 'queue_refresh';
      const message = JSON.stringify({ type, doctor_id: doctorId, at: Date.now() });
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(message); } catch {} }
      return Response.json({ ok: true, clients: this.ctx.getWebSockets().length }, { headers: corsHeaders(request.headers.get('Origin') || '*') });
    }
    return new Response('Not found', { status: 404 });
  }

  async webSocketMessage(ws, message) {
    // Clients normally only receive broadcasts. Ping/pong is handled by Cloudflare
    // without waking this Durable Object because of setWebSocketAutoResponse().
    if (message === 'ping') return;
  }
  async webSocketClose(ws, code, reason) { try { ws.close(code, reason); } catch {} }
  async webSocketError(ws) { try { ws.close(); } catch {} }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '*';
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(origin) });
    if (url.pathname === '/health') return Response.json({ ok: true, service: 'find-a-doctor-live', hibernation: true });
    if (url.pathname === '/ws' || url.pathname === '/broadcast') {
      const doctorId = url.searchParams.get('doctor_id');
      if (!doctorId || !/^[0-9a-fA-F-]{20,80}$/.test(doctorId)) return new Response('doctor_id required', { status: 400 });
      if (url.pathname === '/broadcast') {
        if (!(await verifyDoctor(env, doctorId, request))) return new Response('Unauthorized', { status: 401, headers: corsHeaders(origin) });
      }
      const id = env.QUEUE_ROOM.idFromName(`doctor:${doctorId}`);
      const stub = env.QUEUE_ROOM.get(id);
      const headers = new Headers(request.headers);
      headers.set('X-Doctor-Id', doctorId);
      const target = new URL(request.url);
      target.pathname = url.pathname;
      return stub.fetch(new Request(target, { method: request.method, headers, body: request.method === 'GET' ? undefined : request.body }));
    }
    return new Response('Not found', { status: 404 });
  }
};

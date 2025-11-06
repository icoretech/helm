import os, json, time
import requests
import http.cookiejar as cookiejar
import socket
from urllib.parse import urlparse
import base64

def log(msg):
    print(f"[provision] {msg}", flush=True)

NS = os.environ.get('NAMESPACE','default')
SVC = os.environ['SVC']
FRONTEND_PORT = os.environ.get('FRONTEND_PORT','12008')
FRONTEND = f"http://{SVC}:{FRONTEND_PORT}"
BACKEND = f"http://{SVC}:12009"
ADMIN_EMAIL = os.environ.get('ADMIN_EMAIL','admin@example.com')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD','change-me')
UPDATE_EXISTING = (os.environ.get('UPDATE_EXISTING','true').lower() == 'true')

cfg = json.load(open('/cfg/provision.json','r')).get('provision',{})
servers = cfg.get('servers', [])
namespaces = cfg.get('namespaces', [])
endpoints = cfg.get('endpoints', [])

for _ in range(60):
    try:
        if requests.get(f"{BACKEND}/health", timeout=2).status_code == 200:
            break
    except Exception:
        pass
    time.sleep(2)

sess = requests.Session()
sess.headers.update({'Accept':'application/json'})
sess.headers.update({'Host': SVC})
# Persist cookies like curl does (some frameworks are picky about cookie jar semantics)
jar_path = '/tmp/metamcp_cookies.txt'
mozjar = cookiejar.MozillaCookieJar(jar_path)
try:
    if os.path.exists(jar_path):
        mozjar.load(ignore_discard=True, ignore_expires=True)
        # load into requests jar
        for c in mozjar:
            try:
                sess.cookies.set_cookie(c)  # type: ignore[attr-defined]
            except Exception:
                pass
except Exception:
    pass

def signin(retries=8, delay=1.5):
    tried_signup = False
    for i in range(retries):
        if not tried_signup:
            try:
                resp = sess.post(f"{BACKEND}/api/auth/sign-up/email", headers={'Content-Type':'application/json','Host': SVC}, json={'email': ADMIN_EMAIL,'password': ADMIN_PASSWORD,'name':'Admin'}, timeout=6)
                tried_signup = True
            except Exception:
                tried_signup = True
        r = sess.post(f"{BACKEND}/api/auth/sign-in/email", headers={'Content-Type':'application/json','Host': SVC}, json={'email': ADMIN_EMAIL,'password': ADMIN_PASSWORD}, timeout=6)
        if r.status_code == 200:
            try:
                # Accept token from JSON (multiple possible shapes) or fall back to session cookie
                host = SVC.split(':')[0]
                token = None
                try:
                    j = r.json()
                    token = (
                        j.get('token')
                        or j.get('sessionToken')
                        or (j.get('data') or {}).get('token')
                        or (j.get('data') or {}).get('sessionToken')
                    )
                except Exception:
                    token = None
                # Try to capture the raw cookie value from Set-Cookie header (preferred for signed cookies)
                raw_cookie = None
                try:
                    sch = r.headers.get('set-cookie') or r.headers.get('Set-Cookie')
                    if sch:
                        # pick either __Secure-better-auth.session_token or better-auth.session_token
                        for nm in ('__Secure-better-auth.session_token','better-auth.session_token'):
                            marker = nm + '='
                            if marker in sch:
                                seg = sch.split(marker,1)[1]
                                raw_cookie = seg.split(';',1)[0]
                                break
                except Exception:
                    raw_cookie = None
                # Prefer raw signed cookie value; otherwise fall back to token from JSON
                cookie_val = raw_cookie or token
                if cookie_val:
                    # set both cookie names to maximize compatibility with secure-cookie deployments
                    for cname in ('better-auth.session_token','__Secure-better-auth.session_token'):
                        try:
                            sess.cookies.set(cname, cookie_val, domain=host, path='/')
                        except Exception:
                            sess.cookies.set(cname, cookie_val)
                    if token:
                        sess.headers['Authorization'] = f"Bearer {token}"
                # Persist cookies to mozilla jar and reload next time
                try:
                    mozjar.clear()
                    for c in sess.cookies:
                        try:
                            mozjar.set_cookie(c)  # type: ignore[arg-type]
                        except Exception:
                            pass
                    mozjar.save(ignore_discard=True, ignore_expires=True)
                except Exception:
                    pass
                lr = sess.get(f"{BACKEND}/trpc/frontend/frontend.mcpServers.list", headers={'Host': SVC}, params={'input':'{}'}, timeout=6)
                if lr.status_code == 200:
                    return True
            except Exception:
                pass
        time.sleep(delay)
    return False

if not signin():
    log('WARN: signin failed; proceeding and expecting 401s')

def trpc_post(path, body):
    return sess.post(f"{BACKEND}{path}", headers={'Content-Type':'application/json','Host': SVC}, json=body, timeout=12)
def trpc_get(path):
    return sess.get(f"{BACKEND}{path}", headers={'Host': SVC}, timeout=12)
def trpc_post_batch(path, body):
    # Wrap body as {"0": body} and use ?batch=1 to match UI routes
    return sess.post(f"{BACKEND}{path}?batch=1", headers={'Content-Type':'application/json','Host': SVC}, json={"0": body}, timeout=12)

# K8s helpers (defined before usage)
def k8s_get_secret_val(name: str, key: str):
    try:
        token = open('/var/run/secrets/kubernetes.io/serviceaccount/token','r').read().strip()
        cacert = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
        ns = NS
        url = f"https://kubernetes.default.svc/api/v1/namespaces/{ns}/secrets/{name}"
        r = requests.get(url, headers={'Authorization': f'Bearer {token}'}, verify=cacert, timeout=5)
        if r.status_code == 200:
            data = r.json().get('data',{})
            b = data.get(key)
            if b:
                return base64.b64decode(b).decode()
    except Exception:
        pass
    return None

def k8s_get_secret_data(name: str):
    try:
        token = open('/var/run/secrets/kubernetes.io/serviceaccount/token','r').read().strip()
        cacert = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
        ns = NS
        url = f"https://kubernetes.default.svc/api/v1/namespaces/{ns}/secrets/{name}"
        r = requests.get(url, headers={'Authorization': f'Bearer {token}'}, verify=cacert, timeout=5)
        if r.status_code == 200:
            data = r.json().get('data',{})
            return {k: base64.b64decode(v).decode() for k,v in data.items()}
    except Exception:
        pass
    return {}

def k8s_get_configmap_data(name: str):
    try:
        token = open('/var/run/secrets/kubernetes.io/serviceaccount/token','r').read().strip()
        cacert = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
        ns = NS
        url = f"https://kubernetes.default.svc/api/v1/namespaces/{ns}/configmaps/{name}"
        r = requests.get(url, headers={'Authorization': f'Bearer {token}'}, verify=cacert, timeout=5)
        if r.status_code == 200:
            return r.json().get('data',{}) or {}
    except Exception:
        pass
    return {}

# Map existing servers (name -> uuid and full info)
srv_map = {}
srv_info = {}
try:
    lr = trpc_get('/trpc/frontend/frontend.mcpServers.list?input=%7B%7D')
    if lr.ok:
        for s in lr.json().get('result',{}).get('data',{}).get('data',[]):
            srv_map[s['name']] = s['uuid']
            srv_info[s['name']] = s
except Exception:
    pass

for s in servers:
    if not (s.get('enabled', True)):
        continue
    name = s.get('name'); st = (s.get('type','SSE') or 'SSE').upper()
    if not name:
        continue
    if st in ('SSE','STREAMABLE'):
        st = 'SSE' if st=='SSE' else 'STREAMABLE_HTTP'
    body = {'name': name, 'type': st}
    desired_url = None
    if st in ('SSE','STREAMABLE_HTTP'):
        desired_url = s.get('url')
        if not desired_url:
            base = s.get('serviceBase')
            if base:
                suffix = '/mcp' if st=='STREAMABLE_HTTP' else '/sse'
                # ensure scheme
                if base.startswith('http://') or base.startswith('https://'):
                    desired_url = base + suffix
                else:
                    desired_url = 'http://' + base + suffix
            # proactive readiness for deployed servers
            if base:
                try:
                    hostport = base.split('://')[-1]
                    host, port = hostport.split(':')[0], int(hostport.split(':')[1])
                except Exception:
                    host, port = None, None
                if host and port:
                    log(f"[ready] waiting tcp {host}:{port} …")
                    max_tries = 8
                    ok = False
                    for _ in range(max_tries):
                        try:
                            with socket.create_connection((host, port), timeout=1.5):
                                ok = True
                                break
                        except Exception:
                            time.sleep(1)
                    log(f"[ready] tcp {host}:{port} -> {'ok' if ok else 'timeout'}")
        if desired_url:
            body['url'] = desired_url
        if s.get('bearerToken'):
            body['bearerToken'] = s['bearerToken']
        if s.get('headers'):
            body['headers'] = s['headers']

    # If server exists and updates are allowed, patch safe fields for HTTP/SSE
    if name in srv_map:
        if UPDATE_EXISTING and st in ('SSE','STREAMABLE_HTTP'):
            try:
                current = srv_info.get(name, {})
                patch = {'uuid': current.get('uuid'), 'name': name, 'type': st}
                changed = False
                if desired_url and (current.get('url') or '') != desired_url:
                    patch['url'] = desired_url; changed = True
                if 'bearerToken' in body and (current.get('bearerToken') or '') != body.get('bearerToken'):
                    patch['bearerToken'] = body['bearerToken']; changed = True
                if 'headers' in body:
                    # best-effort compare
                    cur_headers = current.get('headers') or {}
                    if cur_headers != body['headers']:
                        patch['headers'] = body['headers']; changed = True
                if changed:
                    r = trpc_post('/trpc/frontend/frontend.mcpServers.update', patch)
                    if r.ok:
                        log(f"server updated: {name}")
                    else:
                        log(f"WARN server update {name} -> {r.status_code}: {r.text[:160]}")
            except Exception:
                pass
        continue
    if st == 'STDIO':
        cmd = s.get('command')
        args = s.get('args') or []
        if isinstance(cmd, list) and len(cmd) > 0:
            body['command'] = cmd[0]
            body['args'] = (args + cmd[1:]) if isinstance(args, list) else cmd[1:]
        elif isinstance(cmd, str):
            body['command'] = cmd
            if isinstance(args, list) and args:
                body['args'] = args
        env_map = {}
        if s.get('env') and isinstance(s['env'], dict):
            env_map.update({k:str(v) for k,v in s['env'].items()})
        # STDIO envFrom: resolve Secrets/ConfigMaps into env for MetaMCP-registered servers
        # Resolve envFrom (Secrets/ConfigMaps): pull all key=val pairs into env
        for src in (s.get('envFrom') or []):
            if not isinstance(src, dict):
                continue
            if 'secretRef' in src and isinstance(src['secretRef'], dict) and src['secretRef'].get('name'):
                env_map.update(k8s_get_secret_data(src['secretRef']['name']))
            if 'configMapRef' in src and isinstance(src['configMapRef'], dict) and src['configMapRef'].get('name'):
                env_map.update(k8s_get_configmap_data(src['configMapRef']['name']))
        if env_map:
            body['env'] = env_map
    r = trpc_post('/trpc/frontend/frontend.mcpServers.create', body)
    if r.ok:
        try:
            srv_map[name] = r.json()['result']['data']['data']['uuid']
            log(f"server created: {name}")
        except Exception:
            log(f"WARN cannot parse uuid for {name}")
    else:
        log(f"WARN server create {name} -> {r.status_code}: {r.text[:160]}")

def ensure_namespace(name, description=None):
    ns_uuid = None
    existed = False
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    if lr.ok:
        for ns in lr.json().get('result',{}).get('data',{}).get('data',[]):
            if ns.get('name') == name:
                ns_uuid = ns.get('uuid'); existed = True; break
    if not ns_uuid:
        payload = {'name': name}
        if description:
            payload['description'] = description
        r = trpc_post('/trpc/frontend/frontend.namespaces.create', payload)
        if r.ok:
            try:
                ns_uuid = r.json()['result']['data']['data']['uuid']
                log(f"namespace created: {name}")
            except Exception:
                pass
    else:
        # Update description if provided and allowed
        if description and UPDATE_EXISTING:
            try:
                trpc_post('/trpc/frontend/frontend.namespaces.update', {'uuid': ns_uuid,'name': name,'description': description})
            except Exception:
                pass
    return ns_uuid, existed

for ns in namespaces:
    name = ns.get('name'); nssrvs = ns.get('servers') or []
    if not name: continue
    desc = ns.get('description')
    nid, existed = ensure_namespace(name, desc)
    # Map server names to UUIDs if available
    srv_ids = []
    for nm in nssrvs:
        sid = srv_map.get(nm)
        if sid:
            srv_ids.append(sid)
    # Update namespace membership if allowed or if the namespace was just created
    if nid and srv_ids and (UPDATE_EXISTING or not existed):
        try:
            payload = {'uuid': nid, 'name': name, 'mcpServerUuids': srv_ids}
            if desc:
                payload['description'] = desc
            trpc_post_batch('/trpc/frontend/frontend.namespaces.update', payload)
        except Exception:
            pass

def create_endpoint(name, nsref, transport='SSE', extra=None, description=None, update_existing=True):
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    nid = None
    if lr.ok:
        for ns in lr.json().get('result',{}).get('data',{}).get('data',[]):
            if ns.get('uuid') == nsref or ns.get('name') == nsref:
                nid = ns.get('uuid'); break
    if not nid: return
    # normalize transport
    tr = (transport or 'SSE').upper()
    if tr in ('SSE','STREAMABLE'):
        tr = 'SSE' if tr=='SSE' else 'STREAMABLE_HTTP'
    # find existing endpoint by name
    el = trpc_get('/trpc/frontend/frontend.endpoints.list?input=%7B%7D')
    e_uuid = None
    if el.ok:
        try:
            for e in el.json().get('result',{}).get('data',{}).get('data',[]):
                if e.get('name') == name:
                    e_uuid = e.get('uuid'); break
        except Exception:
            e_uuid = None
    # build extra flags (camelCase as accepted by API)
    flags = {}
    if isinstance(extra, dict):
        for k in ('enableApiKeyAuth','enableOauth','useQueryParamAuth'):
            if k in extra:
                flags[k] = extra[k]
    if description:
        flags['description'] = description
    if e_uuid and update_existing:
        # update existing endpoint (use tRPC batch form as UI does)
        up = {'uuid': e_uuid, 'name': name, 'namespaceUuid': nid}
        up.update(flags)
        r = trpc_post_batch('/trpc/frontend/frontend.endpoints.update', up)
        if r.ok:
            log(f"endpoint updated: {name}")
    else:
        # create new endpoint
        body = {'name': name,'namespaceUuid': nid,'transport': tr}
        body.update(flags)
        r = trpc_post('/trpc/frontend/frontend.endpoints.create', body)
        if r.ok: log(f"endpoint created: {name} ({tr})")

for ep in endpoints:
    name = ep.get('name'); nsref = ep.get('namespace') or ep.get('namespaceUuid')
    if not (name and nsref): continue
    extra = {k: ep[k] for k in ('enableApiKeyAuth','enableOauth','useQueryParamAuth') if k in ep}
    create_endpoint(name, nsref, ep.get('transport'), extra, ep.get('description'), UPDATE_EXISTING)

# Post-fix auto-generated endpoint servers URLs when APP_URL pointed to 12008 at creation time.
# Newer MetaMCP creates a server named '<namespace>-endpoint' per endpoint and derives its URL from APP_URL.
# If APP_URL used the frontend port (12008), the server URL points to the wrong port.
# We normalize such servers to backend port 12009 so connections succeed in-cluster.
try:
    def list_servers():
        r = trpc_get('/trpc/frontend/frontend.mcpServers.list?input=%7B%7D')
        return r.json().get('result',{}).get('data',{}).get('data',[]) if r.ok else []
    svcs = list_servers()
    # Build namespace->server endpoint name mapping ("<ns>-endpoint")
    ns_names = [ns.get('name') for ns in namespaces if ns.get('name')]
    desired = []
    for ns in ns_names:
        sname = f"{ns}-endpoint"
        for s in svcs:
            if s.get('name') == sname and s.get('type') == 'STREAMABLE_HTTP':
                desired.append((s, ns))
    for s, ns in desired:
        url = s.get('url') or ''
        if ':12008/metamcp/' in url:
            # rewrite to backend port
            fixed = url.replace(':12008/metamcp/', ':12009/metamcp/')
            payload = {'uuid': s['uuid'], 'name': s['name'], 'type': s['type'], 'url': fixed}
            trpc_post('/trpc/frontend/frontend.mcpServers.update', payload)
except Exception:
    pass
 

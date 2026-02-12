import os, time, json, base64
import requests

def log(msg):
    print(f"[user-bootstrap] {msg}", flush=True)

NS = os.environ.get('NAMESPACE', 'default')
SVC = os.environ['SVC']
FRONTEND_PORT = os.environ.get('FRONTEND_PORT', '12008')
FRONTEND = f"http://{SVC}:{FRONTEND_PORT}"
BACKEND = f"http://{SVC}:12009"
SECRET_PREFIX = os.environ['SECRET_PREFIX']

cfg_path = '/cfg/config.json'
with open(cfg_path, 'r') as f:
    cfg = json.load(f)
users = cfg.get('users', [])
disable_public = bool(cfg.get('disablePublicSignup', False))

for i in range(90):
    try:
        r = requests.get(f"{BACKEND}/health", timeout=3)
        if r.status_code == 200:
            break
    except Exception:
        pass
    time.sleep(2)
else:
    log('WARN: frontend /health not ready after timeout, continuing')

def slug_email(email: str) -> str:
    return email.replace('@', '-at-').replace('.', '-').lower()

def b64(s: str) -> str:
    return base64.b64encode(s.encode()).decode()

def k8s_get_secret_val(name: str, key: str):
    try:
        token = open('/var/run/secrets/kubernetes.io/serviceaccount/token','r').read().strip()
        cacert = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
        url = f"https://kubernetes.default.svc/api/v1/namespaces/{NS}/secrets/{name}"
        r = requests.get(url, headers={'Authorization': f'Bearer {token}'}, verify=cacert, timeout=5)
        if r.status_code == 200:
            data = r.json().get('data',{})
            b = data.get(key)
            if b:
                return base64.b64decode(b).decode()
    except Exception:
        pass
    return None

def k8s_upsert_secret(name: str, email: str, api_key: str):
    token = open('/var/run/secrets/kubernetes.io/serviceaccount/token','r').read().strip()
    cacert = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
    base = f"https://kubernetes.default.svc/api/v1/namespaces/{NS}/secrets"
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    payload = {
        'apiVersion':'v1',
        'kind':'Secret',
        'metadata': {'name': name, 'labels': {'app.kubernetes.io/managed-by': 'Helm'}},
        'type':'Opaque',
        'data': {'apiKey': b64(api_key), 'email': b64(email)},
    }
    try:
        r = requests.post(base, json=payload, headers=headers, verify=cacert, timeout=5)
        if r.status_code == 201:
            return True
        if r.status_code == 409:
            r2 = requests.put(f"{base}/{name}", json=payload, headers=headers, verify=cacert, timeout=5)
            return r2.status_code in (200, 201)
        log(f"WARN: secret POST unexpected status {r.status_code}: {r.text[:180]}")
    except Exception as e:
        log(f"WARN: secret upsert exception: {e}")
    return False

sessions = []
for u in users:
    email = u.get('email'); password = u.get('password'); name = u.get('name')
    if not password and isinstance(u.get('passwordFrom'), dict):
        sk = (u.get('passwordFrom') or {}).get('secretKeyRef') or {}
        if isinstance(sk, dict) and sk.get('name') and sk.get('key'):
            password = k8s_get_secret_val(sk['name'], sk['key'])
    create_key = bool(u.get('createApiKey')); api_key_name = u.get('apiKeyName') or 'default'
    if not email or not password or not name:
        log(f"SKIP: incomplete user spec {u}")
        continue
    log(f"Seeding user {email}")
    s = requests.Session()
    s.headers.update({'Content-Type': 'application/json', 'Accept': 'application/json'})
    try:
        resp = s.post(f"{BACKEND}/api/auth/sign-up/email", json={'email': email, 'password': password, 'name': name}, timeout=8)
        if resp.status_code not in (200, 201, 409, 422):
            log(f"WARN: sign-up status {resp.status_code}: {resp.text[:160]}")
    except Exception as e:
        log(f"WARN: sign-up exception: {e}")
    try:
        resp = s.post(f"{BACKEND}/api/auth/sign-in/email", json={'email': email, 'password': password}, timeout=8)
        if resp.status_code != 200:
            log(f"WARN: sign-in status {resp.status_code}: {resp.text[:160]}")
        else:
            host = SVC.split(':')[0]
            token = None
            try:
                j = resp.json()
                token = j.get('token') or j.get('sessionToken') or (j.get('data') or {}).get('token') or (j.get('data') or {}).get('sessionToken')
            except Exception:
                token = None
            raw_cookie = None
            try:
                sch = resp.headers.get('set-cookie') or resp.headers.get('Set-Cookie')
                if sch:
                    for nm in ('__Secure-better-auth.session_token','better-auth.session_token'):
                        marker = nm + '='
                        if marker in sch:
                            seg = sch.split(marker,1)[1]
                            raw_cookie = seg.split(';',1)[0]
                            break
            except Exception:
                raw_cookie = None
            cookie_val = raw_cookie or token
            if cookie_val:
                for cname in ('better-auth.session_token','__Secure-better-auth.session_token'):
                    try:
                        s.cookies.set(cname, cookie_val, domain=host, path='/')
                    except Exception:
                        s.cookies.set(cname, cookie_val)
            if token:
                s.headers['Authorization'] = f"Bearer {token}"
    except Exception as e:
        log(f"WARN: sign-in exception: {e}")
    sessions.append(s)
    if create_key:
        try:
            r1 = s.post(f"{BACKEND}/trpc/frontend/frontend.apiKeys.create", json={'name': api_key_name}, timeout=8)
            key = None
            if r1.ok:
                try:
                    key = r1.json().get('result', {}).get('data', {}).get('key')
                except Exception:
                    key = None
            if not key:
                r2 = s.post(f"{BACKEND}/trpc/frontend/frontend.apiKeys.create", json={'input': {'name': api_key_name}}, timeout=8)
                if r2.ok:
                    try:
                        key = r2.json().get('result', {}).get('data', {}).get('key')
                    except Exception:
                        key = None
            if not key:
                try:
                    lr = s.get(f"{BACKEND}/trpc/frontend/frontend.apiKeys.list?input=%7B%7D", timeout=8)
                    if lr.ok:
                        data = lr.json().get('result', {}).get('data', {}).get('apiKeys', [])
                        for item in data:
                            if item.get('name') == api_key_name and item.get('key'):
                                key = item['key']
                                break
                except Exception:
                    key = None
            if key:
                sec_name = f"{SECRET_PREFIX}-apikey-{slug_email(email)}"
                if k8s_upsert_secret(sec_name, email, key):
                    log(f"Stored API key in Secret/{sec_name}")
                else:
                    log(f"WARN: failed to upsert Secret for {email}")
            else:
                log(f"WARN: could not obtain API key for {email}")
        except Exception as e:
            log(f"WARN: apiKeys.create exception: {e}")

if disable_public and sessions:
    try:
        r = sessions[0].post(f"{BACKEND}/trpc/frontend/frontend.config.setSignupDisabled", json={'disabled': True}, timeout=8)
        if not r.ok:
            log(f"WARN: disablePublicSignup status {r.status_code}: {r.text[:160]}")
    except Exception as e:
        log(f"WARN: disablePublicSignup exception: {e}")

log('Completed')

# TCC site

Private site for the undergraduate thesis in [mateuseap/tcc](https://github.com/mateuseap/tcc). It serves the thesis PDF, the latest advisor meeting slides, and the executed notebooks (converted to HTML, never re-run) at `https://tcc.lab.mateuseap.com`.

## How it is built

The content lives in the thesis repo. On every push to its `main`, the `Publish site image` workflow:

1. runs `site/build.py`, which copies `thesis/tcc.pdf`, the latest `meetings/*/slides/`, and converts the notebooks with `nbconvert`;
2. runs the server tests (`site/server/server.test.mjs`);
3. pushes `ghcr.io/mateuseap/tcc-site:latest` and `:<sha>` (private package).

The cluster pulls `:latest` with `imagePullPolicy: Always`. After a new image is published, roll it out:

```bash
kubectl -n tcc rollout restart deploy/site
```

## Access control

App-level login, the same model as Sotto (see [security](../security/security.md)). The server (`site/server/server.mjs`, Node with only `bcryptjs`) checks the password against the bcrypt hash in `LOGIN_PASSWORD_HASH` and sets an `httpOnly`, `SameSite=Strict`, `Secure` cookie valid for 7 days. Everything except `/login`, its stylesheet, and `/healthz` requires the cookie. Login attempts are rate limited per IP (5 per 15 minutes). Every response carries `X-Robots-Tag: noindex, nofollow`.

Sessions live in memory, so a restart only asks visitors to log in again.

## Secrets

- `apps/tcc/sealed-secrets.yaml`: `login-password-hash`, the bcrypt hash (cost 12) of the site password.
- `apps/tcc/sealed-pull-secret.yaml`: the GHCR pull credential, the same one Sotto uses, sealed for the `tcc` namespace.

To change the password, hash it locally and replace only that ciphertext line:

```bash
cd ../tcc/site/server
node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 12))" 'NEW-PASSWORD' \
  | tr -d '\n' \
  | kubeseal --raw --cert <sealed-secrets-cert.pem> --namespace tcc --name tcc-site-secrets --from-file=/dev/stdin
```

Then restart the Deployment, which invalidates every active session.

## Footprint

One pod, `requests: 10m CPU / 32Mi`, `limits: 96Mi`, read-only root filesystem, non-root, all capabilities dropped. The image is about 10 MB of content plus Node.

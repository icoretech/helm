# Chart Signing (Artifact Hub "Signed" badge)

This repository signs Helm chart packages (`.tgz`) with Helm provenance (`.prov`) so Artifact Hub can display the **Signed** badge and users can verify releases.

## How It Works
- GitHub Actions (`.github/workflows/release.yml`) runs `chart-releaser` with signing enabled.
- Signed releases produce `*.tgz` and `*.tgz.prov` in the GitHub Pages Helm repo and in GitHub Release assets.
- The public PGP key is published on GitHub Pages at:
  - `https://icoretech.github.io/helm/pgp-public-key.asc`
- Each chart `Chart.yaml` includes `artifacthub.io/signKey` pointing at that key and its fingerprint.

## GitHub Actions Secrets
The release workflow expects these repo secrets:
- `GPG_KEYRING_BASE64`: base64 of an exported GPG private key file (for example from `gpg --export-secret-keys`).
- `GPG_SIGNING_KEY`: the signing key identifier (recommended: full fingerprint).

If chart versions are bumped in a push to `main` and signing secrets are missing, the release workflow will fail intentionally to avoid publishing unsigned chart versions.

## Verify A Release Locally
Once a chart is published:
```bash
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
helm pull icoretech/<chart> --version <version> --prov

# Import the public key and verify provenance:
curl -fsSL https://icoretech.github.io/helm/pgp-public-key.asc | gpg --import
helm verify <chart>-<version>.tgz
```

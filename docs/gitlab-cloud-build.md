# GitLab + Google Cloud Build (second way to build and deploy)

Beside GitHub (`.github/workflows`, images in GHCR), the three repositories can live on GitLab.com (group
`premium-cars-import`) with CI on Google Cloud Build (free tier: 2,500 build-minutes a month on e2-standard-2) and
images in the GitLab registry. Both ways stay usable; the step-by-step plan is kept outside the repo.

| | GitHub | GitLab + Cloud Build |
|---|---|---|
| CI | `.github/workflows/ci.yml` | `cloudbuild.yaml` (triggers: merge request to main `_PUSH=false`, push to main `_PUSH=true`) |
| Images | `ghcr.io/ilutov90/premium-cars-*` | `registry.gitlab.com/premium-cars-import/premium-cars-*` |
| Deploy | Actions -> Deploy | Cloud Build trigger `deploy` (`cloudbuild-deploy.yaml`, `_BACKEND_TAG` / `_FRONTEND_TAG`) |

- `prod.sh deploy` takes the registry from `IMAGE_REGISTRY` in its environment (the Cloud Build deploy sets it) and
  writes it to `.env.tags`, so restarts keep it; the GitHub deploy does not set it, so its images come from GHCR.
  `IMAGE_REGISTRY` in `.env.prod` stays empty.
- The server pulls this repo from GitLab (`origin`); GitLab mirrors to GitHub when that account works.
- The server logs in to the GitLab registry once (`docker login registry.gitlab.com`, a deploy token with
  `read_registry`). Cloud Build pushes with another deploy token (`write_registry`), Secret Manager `gitlab-registry`
  = `<username>:<token>`.
- Secret Manager also holds `deploy-ssh-key` and `deploy-known-hosts` (the deploy trigger) and the GitLab connection's
  tokens (created by the console).

## The Vault tests

`.github/workflows/ci.yml` runs both Vault setups end to end; Cloud Build does not (its build steps cannot bind-mount
the workspace into containers they start). When `vault/` or `scripts/prod.sh` change and GitHub is not available,
run the same commands by hand on a machine with Docker (the laptop), from that workflow's `vault-setup` and
`production-vault` jobs, in a throwaway clone.

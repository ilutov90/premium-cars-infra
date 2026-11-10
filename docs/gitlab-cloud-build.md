# GitLab + Google Cloud Build (backup way to build and deploy)

GitHub (`.github/workflows`, images in GHCR) is the main way. The three repositories also have a copy on GitLab.com
(group `premium-cars-import`) with CI on Google Cloud Build (free tier: 2,500 build-minutes a month on e2-standard-2)
and images in the GitLab registry, as the backup way. Both ways stay usable; the step-by-step plan is kept outside
the repo.

GitLab is updated only from GitHub: each repo's `.github/workflows/mirror-gitlab.yml` pushes `main` to GitLab after
every push to GitHub's `main` (so the Cloud Build push-to-main trigger builds the same commit), never forced. The
token is the GitHub repository secret `GITLAB_MIRROR_TOKEN` (a GitLab access token with `write_repository` whose user
may push to the protected `main`), sent as `Authorization: Basic oauth2:<token>`, never in the URL. Pull requests on
GitHub are merged with a merge commit (not squash or rebase), so GitLab's `main` stays an ancestor and the push is a
fast-forward. No branches or merge requests are pushed to GitLab; if its `main` gets commits of its own anyway, the
mirror run fails until they come to GitHub through a pull request.

| | GitHub | GitLab + Cloud Build |
|---|---|---|
| CI | `.github/workflows/ci.yml` | `cloudbuild.yaml` (triggers: merge request to main `_PUSH=false`, push to main `_PUSH=true`) |
| Images | `ghcr.io/ilutov90/premium-cars-*` | `registry.gitlab.com/premium-cars-import/premium-cars-*` |
| Deploy | Actions -> Deploy | Cloud Build trigger `deploy` (`cloudbuild-deploy.yaml`, `_BACKEND_TAG` / `_FRONTEND_TAG`) |

- `prod.sh deploy` takes the registry from `IMAGE_REGISTRY` in its environment (the Cloud Build deploy sets it) and
  writes it to `.env.tags`, so restarts keep it; the GitHub deploy does not set it, so its images come from GHCR.
  `IMAGE_REGISTRY` in `.env.prod` stays empty.
- Each deploy pulls this repo on the server from its own side: the GitHub deploy `git pull --ff-only origin main`
  (`origin` = GitHub), the Cloud Build deploy `git pull --ff-only gitlab main` (remote `gitlab` = GitLab, read with a
  deploy key). So the GitHub deploy never depends on GitLab or on the mirror, and Cloud Build still deploys when GitHub
  is down. The server's remotes once:
  `git remote add gitlab git@gitlab.com:premium-cars-import/premium-cars-infra.git` (or rename it, if `origin` was
  GitLab), `git branch -u origin/main`.
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

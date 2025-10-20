# PR Preview Environments

ArgoCD automatically creates isolated preview environments for **every open PR**.

## How It Works

1. **Open a PR** → ArgoCD automatically detects it
2. **ArgoCD creates apps** → One Application per app (e.g., `pr-42-hello-world`)
3. **Deploy to namespace** → Each app in `pr-{number}-{app-name}` namespace
4. **Auto-sync on commits** → Changes in the PR branch trigger automatic sync
5. **Auto-cleanup** → All environments deleted when PR closes/merges

## Setup

### GitHub Token (Optional for Public Repos)

For **public repositories**, no token is needed! ArgoCD uses GitHub's public API.

However, if you hit rate limits (60 requests/hour), create a token:

```bash
# Create a GitHub Personal Access Token with NO scopes (for public repos)
# Then create the secret:
kubectl create secret generic github-token \
  --from-literal=token=ghp_your_token_here \
  --namespace=prod-argocd
```

And uncomment the `tokenRef` section in `apps/argocd/base/applicationset-pr-previews.yaml`:
```yaml
tokenRef:
  secretName: github-token
  key: token
```

**Note**: With a token, you get 5,000 requests/hour instead of 60.

## Usage

### Automatic Creation

Simply open a PR - no label needed! ArgoCD will:
- Scan for all apps with `overlays/staging/`
- Create preview app for each: `pr-{number}-{app-name}`
- Deploy using the PR's branch/commit

### View Preview Environments

```bash
# List all preview apps for PR #42
argocd app list -l pr-number=42

# List ALL preview apps
argocd app list -l preview=true

# Via kubectl
kubectl get applications -n prod-argocd -l preview=true
```

### Access Preview Application

```bash
# For PR #42, hello-world app
kubectl port-forward -n pr-42-hello-world svc/pr-42-podinfo 9898:9898

# Then visit http://localhost:9898
```

### Monitor Sync Status

```bash
# Watch specific preview app
argocd app get pr-42-hello-world --refresh

# Wait for it to become healthy
argocd app wait pr-42-hello-world --health
```

### Manual Cleanup (if needed)

ArgoCD auto-deletes when PR closes, but you can also:
```bash
# Delete specific PR preview
argocd app delete pr-42-hello-world

# Delete all previews for PR #42
argocd app list -l pr-number=42 -o name | xargs -n1 argocd app delete
```

## What Gets Deployed

For each PR, ArgoCD creates preview environments for all apps that have:
- Path: `apps/{app-name}/overlays/staging/`

Example structure:
```
apps/
  hello-world/
    overlays/
      staging/  ← Creates pr-{number}-hello-world
  my-api/
    overlays/
      staging/  ← Creates pr-{number}-my-api
  argocd/
    overlays/
      prod/     ← No staging overlay, skipped
```

## Customization

### Change Which Overlays are Used

Edit `apps/argocd/base/applicationset-pr-previews.yaml`:

```yaml
- git:
    repoURL: 'https://github.com/Ch4s3r/argocd-bootstrap-test'
    revision: '{{head_sha}}'
    directories:
      - path: 'apps/*/overlays/staging'  # Change this path
```

### Change Sync Frequency

Adjust `requeueAfterSeconds` (default: 60):
```yaml
- pullRequest:
    github:
      # ...
    requeueAfterSeconds: 30  # Check every 30 seconds
```

## Troubleshooting

### No preview apps created

1. Check ApplicationSet status:
   ```bash
   kubectl get applicationset pr-previews -n prod-argocd -o yaml
   ```

2. Verify GitHub token:
   ```bash
   kubectl get secret github-token -n prod-argocd
   ```

3. Check ArgoCD application controller logs:
   ```bash
   kubectl logs -n prod-argocd deploy/argocd-application-controller
   ```

### Preview app not syncing

```bash
# Force sync
argocd app sync pr-42-hello-world

# Check sync status
argocd app get pr-42-hello-world --show-operation
```

### Token permissions

GitHub token needs `repo` scope for private repos, or `public_repo` for public repos.

## Benefits

✅ **Automatic** - No manual intervention needed  
✅ **Isolated** - Each PR gets separate namespaces  
✅ **Complete** - All apps with staging overlays included  
✅ **Clean** - Auto-deleted when PR closes  
✅ **Fast** - Syncs within 60 seconds of changes  
✅ **Secure** - Uses PR branch, not main  

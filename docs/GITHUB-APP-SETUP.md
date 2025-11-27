# GitHub App Setup for ArgoCD Notifications

This guide explains how to set up a GitHub App to enable ArgoCD to send deployment status checks to your pull requests.

## Overview

The automated deployment validation workflow works as follows:

1. **Renovate creates PR** → Updates Docker image version
2. **PR Preview triggers** → ArgoCD creates staging environment
3. **ArgoCD deploys** → Application syncs to staging namespace
4. **Health check runs** → Waits for pods to be Ready and Healthy
5. **Status reported** → GitHub check shows success ✅ or failure ❌
6. **Auto-merge** → PR merges automatically if check passes

## Prerequisites

- Admin access to your GitHub repository
- Access to ArgoCD cluster with admin permissions
- SOPS and Age configured for secret encryption

## Step 1: Create GitHub App

1. Go to **GitHub Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
   - Or visit: https://github.com/settings/apps/new

2. **Configure the App:**
   - **GitHub App name**: `ArgoCD Notifications` (or your preferred name)
   - **Homepage URL**: Your ArgoCD URL (e.g., `https://argocd.example.com`)
   - **Webhook**:
     - **Option 1 (Recommended)**: Uncheck "Active" - ArgoCD Notifications pushes status checks directly to GitHub API (no webhook needed)
     - **Option 2 (Advanced)**: If you want bi-directional webhooks via Tailscale:
       - **Webhook URL**: `https://argocd.your-tailnet.ts.net/api/webhook` (your Tailscale hostname)
       - **Webhook secret**: Generate a random secret and save it
       - Note: This is optional and not required for commit status checks

3. **Set Permissions:**
   - **Repository permissions:**
     - **Checks**: Read & Write
     - **Commit statuses**: Read & Write
     - **Pull requests**: Read & Write (optional, for PR comments)
   - **Organization permissions:** None required

4. **Where can this GitHub App be installed?**
   - Select "Only on this account"

5. **Click "Create GitHub App"**

## Step 2: Generate Private Key

1. After creating the app, scroll down to **Private keys** section
2. Click **Generate a private key**
3. A `.pem` file will be downloaded - **save this securely**

## Step 3: Get App Credentials

You'll need two IDs from your GitHub App:

### App ID
- Found at the top of your GitHub App settings page
- Example: `123456`

### Installation ID
1. Click **Install App** in the left sidebar
2. Install the app to your repository
3. After installation, check the URL - it will be:
   ```
   https://github.com/settings/installations/{INSTALLATION_ID}
   ```
4. Copy the `INSTALLATION_ID` from the URL

## Step 4: Configure ArgoCD Notifications

### 4.1 Update ConfigMap with App IDs

Edit `apps/argocd/base/notifications-cm.yaml`:

```yaml
service.github: |
  appID: 123456  # Replace with your App ID
  installationID: 78910  # Replace with your Installation ID
  privateKey: $github-privateKey
```

### 4.2 Encrypt the Private Key

1. **Prepare the secret file:**
   ```bash
   # Edit the secret file with your private key
   vi apps/argocd/base/notifications-secret.enc.yaml
   ```

2. **Add your private key** (replace the placeholder):
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: argocd-notifications-secret
     namespace: argocd
   type: Opaque
   stringData:
     github-privateKey: |
       -----BEGIN RSA PRIVATE KEY-----
       [paste your private key content here]
       -----END RSA PRIVATE KEY-----
   ```

3. **Encrypt with SOPS:**
   ```bash
   sops -e -i apps/argocd/base/notifications-secret.enc.yaml
   ```

### 4.3 Update ArgoCD URL

Edit `apps/argocd/base/values.yaml`:

```yaml
notifications:
  enabled: true
  argocdUrl: https://your-argocd-domain.com  # Replace with actual URL
```

## Step 5: Configure Renovate Status Checks

The `requiredStatusChecks` in `renovate.json` must match your application names.

### For multiple applications:

Edit `renovate.json`:
```json
{
  "requiredStatusChecks": [
    "staging-deployment/hello-world",
    "staging-deployment/another-app",
    "staging-deployment/yet-another-app"
  ]
}
```

The format is: `staging-deployment/{app-name}` where `{app-name}` is the directory name in `apps/`.

## Step 6: Deploy the Configuration

1. **Commit the changes:**
   ```bash
   git add .
   git commit -m "feat: add ArgoCD notifications with GitHub App integration"
   git push
   ```

2. **ArgoCD will automatically sync** and apply the new notification configuration

## Step 7: Verify the Setup

### Test with a new PR:

1. Create a test PR that updates a Docker image
2. Wait for PR preview environment to be created
3. Check the PR "Checks" tab in GitHub
4. You should see: `staging-deployment/hello-world`
   - **In Progress** → while deploying
   - **Success** ✅ → if deployment is healthy
   - **Failure** ❌ → if deployment fails

### Debug if checks don't appear:

1. **Check ArgoCD Notifications logs:**
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller
   ```

2. **Verify the secret is mounted:**
   ```bash
   kubectl get secret -n argocd argocd-notifications-secret
   ```

3. **Check ConfigMap:**
   ```bash
   kubectl get configmap -n argocd argocd-notifications-cm -o yaml
   ```

## Troubleshooting

### Issue: "Bad credentials" error in logs

**Solution:** Verify:
- App ID is correct
- Installation ID is correct
- Private key is properly formatted (includes BEGIN/END lines)
- Secret is properly encrypted and decrypted by KSOPS

### Issue: Checks not appearing on PR

**Solution:**
- Ensure the GitHub App is installed on your repository
- Check that the PR creates a preview environment (look for `pr-{number}-{app}` application in ArgoCD)
- Verify annotations on the Application: `notifications.argoproj.io/subscribe.on-deployed.github`

### Issue: Check appears but always fails

**Solution:**
- Check ArgoCD Application health status
- Ensure `repoURLPath` and `revisionPath` in the template are correct
- Verify the application is actually syncing to the PR branch

## Security Notes

- **Never commit unencrypted private keys** to Git
- Always use SOPS to encrypt the notifications secret
- The private key has write access to your repository - protect it carefully
- Rotate the private key periodically via GitHub App settings

## Optional: Enable Instant Webhooks (Recommended)

**Note:** Webhooks are NOT required for the automated deployment validation workflow. ArgoCD Notifications pushes commit status checks directly to GitHub's API. However, webhooks enable **instant** PR preview environment creation instead of waiting up to 60 seconds.

### With Webhooks (Instant):
```
PR Opened → GitHub webhook → ArgoCD (0-2 seconds)
```

### Without Webhooks (Polling):
```
PR Opened → ArgoCD polls GitHub every 60s → Detected (0-60 seconds)
```

### The Challenge: Tailscale Private Networks

**Problem:** GitHub's webhook servers cannot reach your ArgoCD if it's only on Tailscale (private network). GitHub needs a publicly accessible HTTPS endpoint.

**Solution:** See the comprehensive guide: **[WEBHOOK-RELAY.md](./WEBHOOK-RELAY.md)**

The guide covers 5 solutions:

1. **Tailscale Funnel** (Recommended) - One command setup, exposes only webhook endpoint
2. **Webhook Relay Service** - Most secure, ArgoCD stays completely private
3. **Cloudflare Tunnel** - Good balance, free with Cloudflare
4. **GitHub Actions Forwarder** - GitHub-native solution
5. **Keep Polling** - Current setup, 60s delay acceptable

### Quick Start: Tailscale Funnel

For instant webhooks with minimal setup:

```bash
# On your ArgoCD server
tailscale funnel --bg --https=443 localhost:8080
```

Then configure GitHub App:
- **Webhook URL**: `https://your-argocd.your-tailnet.ts.net/api/webhook`
- **Events**: Pull request, Push, Check runs

**Full instructions:** See [WEBHOOK-RELAY.md](./WEBHOOK-RELAY.md)

## Additional Resources

- [ArgoCD Notifications Documentation](https://argocd-notifications.readthedocs.io/)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Renovate Auto-merge Documentation](https://docs.renovatebot.com/configuration-options/#automerge)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)

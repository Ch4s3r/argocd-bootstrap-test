# GitHub Webhooks with Tailscale Private Networks

## The Problem

GitHub's webhook servers cannot reach your ArgoCD instance if it's only exposed via Tailscale (private network). GitHub needs a **publicly accessible HTTPS endpoint** to send webhooks.

## Solutions

There are several approaches to receive GitHub webhooks when ArgoCD is on a private Tailscale network:

---

## Solution 1: Tailscale Funnel (Recommended - Simplest)

**What is it?** Tailscale Funnel allows you to expose specific services from your Tailscale network to the public internet via a `*.ts.net` URL.

### Pros:
✅ No additional infrastructure needed
✅ Free with Tailscale
✅ Automatic HTTPS certificates
✅ Easy to configure
✅ No code required

### Cons:
❌ Publicly exposes the webhook endpoint (but still requires authentication)
❌ Requires Tailscale Funnel feature

### Setup:

1. **Enable Funnel on your ArgoCD node:**
   ```bash
   # On the machine running ArgoCD
   tailscale funnel --bg --https=443 localhost:8080
   ```

2. **Your webhook URL becomes:**
   ```
   https://your-machine-name.your-tailnet.ts.net/api/webhook
   ```

3. **Configure GitHub App webhook:**
   - Use the public `*.ts.net` URL
   - ArgoCD webhook secret still protects the endpoint

### Security:
- Only the webhook endpoint is exposed (not the full ArgoCD UI)
- GitHub webhook secret validates all requests
- Rate limiting built into ArgoCD

---

## Solution 2: Webhook Relay Service (Most Secure)

**What is it?** A lightweight proxy that receives webhooks publicly and forwards them to your private Tailscale network.

### Recommended Services:

#### Option A: webhook.site (Quick Testing)
- **Free tier:** 30 days
- **Use case:** Testing only
- **Setup:** Copy the unique URL to GitHub webhook settings

#### Option B: Hookdeck (Production)
- **Free tier:** 100K requests/month
- **Features:** Retry, filtering, monitoring
- **URL:** https://hookdeck.com

#### Option C: Self-Hosted Webhook Relay

Deploy a simple relay on a public server:

```yaml
# webhook-relay.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webhook-relay
data:
  config.yaml: |
    listen: :8080
    forward:
      url: https://argocd.your-tailnet.ts.net/api/webhook
      headers:
        X-Forwarded-For: true
    verify:
      secret: ${WEBHOOK_SECRET}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-relay
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webhook-relay
  template:
    metadata:
      labels:
        app: webhook-relay
    spec:
      containers:
      - name: relay
        image: ghcr.io/webhookrelay/webhookrelayd:latest
        ports:
        - containerPort: 8080
        env:
        - name: WEBHOOK_SECRET
          valueFrom:
            secretKeyRef:
              name: github-webhook-secret
              key: secret
---
apiVersion: v1
kind: Service
metadata:
  name: webhook-relay
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8080
  selector:
    app: webhook-relay
```

### Pros:
✅ ArgoCD stays completely private
✅ Can add custom filtering/validation
✅ Audit trail of webhook calls
✅ Can handle webhook retries

### Cons:
❌ Additional infrastructure to maintain
❌ Single point of failure
❌ Costs for managed services

---

## Solution 3: Cloudflare Tunnel (Good Balance)

**What is it?** Cloudflare Tunnel creates a secure connection from your Tailscale network to Cloudflare's edge, exposing specific endpoints.

### Setup:

1. **Install cloudflared on your Tailscale network:**
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create argocd-webhooks
   ```

2. **Configure the tunnel:**
   ```yaml
   # config.yml
   tunnel: argocd-webhooks
   credentials-file: /path/to/credentials.json

   ingress:
     - hostname: argocd-webhooks.yourdomain.com
       service: https://argocd.your-tailnet.ts.net:443
       originRequest:
         noTLSVerify: false
     - service: http_status:404
   ```

3. **Run the tunnel:**
   ```bash
   cloudflared tunnel run argocd-webhooks
   ```

4. **GitHub webhook URL:**
   ```
   https://argocd-webhooks.yourdomain.com/api/webhook
   ```

### Pros:
✅ Free with Cloudflare
✅ DDoS protection
✅ Can expose only webhook endpoint
✅ Managed infrastructure

### Cons:
❌ Requires domain with Cloudflare DNS
❌ Additional service to manage
❌ Cloudflare sees your webhook traffic

---

## Solution 4: GitHub Actions Webhook Forwarder

**What is it?** Use GitHub Actions as a webhook receiver that forwards to your Tailscale network via a Tailscale GitHub Action.

### Setup:

1. **Create GitHub Action:**
   ```yaml
   # .github/workflows/forward-webhook.yml
   name: Forward Webhook to ArgoCD

   on:
     pull_request:
       types: [opened, synchronize, reopened, closed]

   jobs:
     forward:
       runs-on: ubuntu-latest
       steps:
         - name: Setup Tailscale
           uses: tailscale/github-action@v2
           with:
             oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
             oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
             tags: tag:ci

         - name: Forward to ArgoCD
           run: |
             curl -X POST https://argocd.your-tailnet.ts.net/api/webhook \
               -H "Content-Type: application/json" \
               -H "X-GitHub-Event: pull_request" \
               -d '${{ toJson(github.event) }}'
   ```

### Pros:
✅ No external infrastructure
✅ Free with GitHub
✅ Direct Tailscale connection from GitHub
✅ Native integration

### Cons:
❌ Limited to GitHub Actions events
❌ Slight delay (Action start time)
❌ More complex setup

---

## Solution 5: Simple Polling (Current Setup)

**What it is:** ArgoCD polls GitHub every 60 seconds instead of receiving webhooks.

### Current Configuration:
```yaml
# apps/argocd/base/applicationset-pr-previews.yaml
pullRequest:
  github:
    owner: Ch4s3r
    repo: argocd-bootstrap-test
  requeueAfterSeconds: 60  # Poll every 60 seconds
```

### Pros:
✅ No additional setup required
✅ Already working
✅ No publicly exposed endpoints
✅ Simple and reliable

### Cons:
❌ Up to 60 second delay for PR detection
❌ More API calls to GitHub

---

## Recommendation Matrix

| Priority | Solution | Best For |
|----------|----------|----------|
| **Simplest** | Keep polling | Small teams, 60s delay acceptable |
| **Easy + Instant** | Tailscale Funnel | Quick setup, don't mind public webhook endpoint |
| **Most Secure** | Webhook Relay | Production, maximum security |
| **Best Balance** | Cloudflare Tunnel | Have domain, want professional setup |
| **GitHub Native** | GitHub Actions | Already using Tailscale in CI/CD |

## My Recommendation for You

**Start with Tailscale Funnel** because:

1. ✅ Simplest to set up (one command)
2. ✅ No additional infrastructure
3. ✅ Free
4. ✅ Instant PR detection
5. ✅ Still secure (webhook secret validates requests)

The webhook endpoint is public, but:
- Only the `/api/webhook` path is exposed
- ArgoCD validates the GitHub webhook secret
- GitHub signs all webhooks
- ArgoCD has rate limiting

If you later decide you need more security, switch to Cloudflare Tunnel or a webhook relay.

---

## Implementation: Tailscale Funnel Setup

### Step 1: Enable Funnel

On your ArgoCD Kubernetes node or cluster:

```bash
# SSH to your Kubernetes node or use kubectl exec
kubectl exec -it -n argocd deployment/argocd-server -- sh

# Inside the container
tailscale funnel --bg --https=443 localhost:8080
```

Or if running Tailscale as an operator:

```yaml
# tailscale-funnel.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tailscale-funnel-config
  namespace: argocd
data:
  funnel.json: |
    {
      "https:443": {
        "path": "/api/webhook",
        "target": "http://argocd-server:80/api/webhook"
      }
    }
```

### Step 2: Get Your Public URL

```bash
tailscale status
# Look for your machine's .ts.net hostname
# Example: argocd-cluster.your-tailnet.ts.net
```

### Step 3: Configure GitHub App Webhook

1. Go to your GitHub App settings
2. **Webhook URL**: `https://argocd-cluster.your-tailnet.ts.net/api/webhook`
3. **Webhook secret**: Generate and save
4. **Events**: Subscribe to:
   - Pull requests
   - Push
   - Check runs

### Step 4: Add Webhook Secret to ArgoCD

```bash
# Create the webhook secret
kubectl create secret generic argocd-secret \
  -n argocd \
  --from-literal=webhook.github.secret=YOUR_WEBHOOK_SECRET \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 5: Test

1. Open a test PR
2. Check ArgoCD logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100 -f
   ```
3. Should see: `Received webhook from GitHub`

---

## Troubleshooting

### Webhook not reaching ArgoCD

1. **Check Funnel is running:**
   ```bash
   tailscale funnel status
   ```

2. **Verify webhook secret matches:**
   ```bash
   kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.webhook\.github\.secret}' | base64 -d
   ```

3. **Test manually:**
   ```bash
   curl -X POST https://argocd-cluster.your-tailnet.ts.net/api/webhook \
     -H "Content-Type: application/json" \
     -H "X-GitHub-Event: ping" \
     -d '{"zen":"test"}'
   ```

### GitHub says "We couldn't deliver this payload"

- Check ArgoCD server logs
- Verify Tailscale Funnel is active
- Ensure webhook secret is configured correctly

---

## Security Considerations

Even with a public webhook endpoint:

✅ **GitHub signs webhooks** - ArgoCD validates signature
✅ **Secret verification** - Invalid secrets are rejected
✅ **Rate limiting** - ArgoCD has built-in protection
✅ **Only webhook path exposed** - Not the full UI
✅ **HTTPS encryption** - All traffic encrypted
✅ **Audit logs** - All webhook calls logged

The risk is minimal - this is how most companies run webhooks.

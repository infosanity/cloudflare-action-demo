# cf-demo: Cloudflare WAF action demo

This project shows what each Cloudflare WAF action looks like from the client side. Each action has its own path on `https://cf-demo.<domain>/`, with one rule per path. It can be deployed to any Cloudflare zone you control.

The origin is a small Worker (`worker.js`) that echoes the request back as HTML: method, path and every request header it received. If the echo page loads, no rule stopped the request.

## Demo paths

| Path | Rule action | Expected result |
|------|-------------|-----------------|
| `/` | none | 200, echo page with links to every demo path |
| `/block` | `block` | 403, Cloudflare block page |
| `/block?bypass=1` | `skip` (remaining custom rules) | 200, echo page; shows that skip overrides block |
| `/managed-challenge` | `managed_challenge` | Cloudflare decides whether to show an interactive challenge |
| `/non-interactive-challenge` | `js_challenge` (Non-Interactive Challenge) | Interstitial page, then a `cf_clearance` cookie |
| `/interactive-challenge` | `challenge` | Always an interactive challenge |
| `/ratelimit` | rate limit → `block` | More than 5 requests in 10s per IP gets blocked for 10s |

Challenged requests should come back with a `cf-mitigated: challenge` response header. The expected results in this table come from the Cloudflare docs; check them against what you actually see.

Quick checks:

```bash
H=$(terraform output -raw url)
curl -si ${H}block | head -1
curl -si ${H}non-interactive-challenge | grep -i -E '^HTTP|cf-mitigated'
for i in $(seq 8); do curl -s -o /dev/null -w '%{http_code}\n' ${H}ratelimit; done
```

Open the challenge paths in a browser to see what a real visitor gets. Every rule hit shows up in the dashboard under the zone's Security events.

## Files

| File | Purpose |
|------|---------|
| `worker.js` | Echo Worker (origin) |
| `main.tf` | Worker, custom domain, WAF custom rules ruleset, rate-limit ruleset |
| `terraform.tfvars.example` | Template for `domain` |

`terraform.tfvars`, `tfplan`, state files and `.pipeline/` are gitignored.

## Setup

1. `cp terraform.tfvars.example terraform.tfvars` and set `domain` to a zone in your Cloudflare account. The zone and account IDs are looked up from it, and the demo is served at `cf-demo.<domain>`.
2. `terraform init`
3. Create a Cloudflare API token and export it: `export CLOUDFLARE_API_TOKEN=<token>`. These permissions are confirmed to work with an account-owned token:
   - Workers Admin / Workers Editor (account): the Worker script and custom domain
   - DNS Write (zone): the custom domain's DNS record
   - Account WAF Write (account): the WAF custom and rate-limit rulesets
   - Account API Tokens Read (account): optional, lets the token read its own permissions

   The token also needs to read the zone to look it up by name; the permissions above were enough for that.

### Before deploying to a new domain

- **Name clashes:** make sure nothing already exists called `cf-demo` (Worker script, custom domain or DNS record). Uploading a Worker script with an existing name overwrites it without warning.
- **Existing rules:** the zone must have no existing WAF custom rules or rate-limit rules. On the Free plan the demo needs all 5 custom-rule slots, and if a zone already has rules in those phases, creating new entry-point rulesets will clash.

## Usage

```bash
# plan
terraform plan -out=tfplan

# apply the reviewed plan
terraform apply tfplan

# tear down
terraform destroy
```

## Caveats (Free plan)

- **Custom rules:** the zone allows only 5, and this demo uses all of them. Any other custom rule means removing a demo rule or destroying the demo first.
- **Rate-limit scope:** rate-limit expressions can only match on the path, so the rule hits `/ratelimit` on **every host in the zone**, not just `cf-demo`.
- **Rate-limit values:** the counting characteristics (`ip.src` + mandatory `cf.colo.id`), the 10s period and the 10s mitigation timeout are fixed on Free. Only the threshold can change.
- **Log action:** not demoed; it's Enterprise only.
- **Ruleset ownership:** Terraform owns the zone's `http_request_firewall_custom` and `http_ratelimit` entry-point rulesets. Rules added in the dashboard are overwritten on the next apply.
- **Hostname:** it's `cf-demo`, not `cf_demo`, because underscores aren't valid in hostnames and certificates won't be issued for them.

## Not covered (ideas for later)

Transform, redirect, cache and origin rules. These aren't WAF actions, and cache and origin rules have little visible effect when a Worker is the origin.

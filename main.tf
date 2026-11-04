terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# Auth: export CLOUDFLARE_API_TOKEN. Permissions that worked: Workers Admin/Editor, DNS Write, Account WAF Write (see README).
provider "cloudflare" {}

variable "domain" {
  type        = string
  description = "Cloudflare zone to deploy into, e.g. example.com. The demo is served at cf-demo.<domain>."
}

# Looks up zone and account IDs from the domain name (token needs zone read access).
data "cloudflare_zone" "this" {
  filter = { name = var.domain }
}

locals {
  host       = "cf-demo.${var.domain}"
  on         = "http.host eq \"${local.host}\""
  zone_id    = data.cloudflare_zone.this.zone_id
  account_id = data.cloudflare_zone.this.account.id
}

resource "cloudflare_workers_script" "demo" {
  account_id         = local.account_id
  script_name        = "cf-demo"
  content            = file("${path.module}/worker.js")
  main_module        = "worker.js"
  compatibility_date = "2026-10-01"
}

# Creates the proxied DNS record and cert for the hostname.
resource "cloudflare_workers_custom_domain" "demo" {
  account_id = local.account_id
  zone_id    = local.zone_id
  hostname   = local.host
  service    = cloudflare_workers_script.demo.script_name
}

# Zone entry-point ruleset. Free plan: 5 rules max across this phase, so this uses all of them.
# If the zone already has custom rules, `terraform import` the existing ruleset instead.
resource "cloudflare_ruleset" "waf_custom" {
  zone_id = local.zone_id
  name    = "cf-demo actions"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      description       = "skip: /block?bypass=1 skips the rest of this ruleset"
      expression        = "${local.on} and http.request.uri.path eq \"/block\" and http.request.uri.query eq \"bypass=1\""
      action            = "skip"
      action_parameters = { ruleset = "current" }
      logging           = { enabled = true }
    },
    {
      description = "block"
      expression  = "${local.on} and http.request.uri.path eq \"/block\""
      action      = "block"
    },
    {
      description = "managed_challenge"
      expression  = "${local.on} and http.request.uri.path eq \"/managed-challenge\""
      action      = "managed_challenge"
    },
    {
      description = "js_challenge"
      expression  = "${local.on} and http.request.uri.path eq \"/js-challenge\""
      action      = "js_challenge"
    },
    {
      description = "challenge (interactive)"
      expression  = "${local.on} and http.request.uri.path eq \"/interactive-challenge\""
      action      = "challenge"
    },
  ]
}

# Free plan: 1 rule, path-only expression (no http.host, so it hits /ratelimit on every host in the zone),
# ip.src + mandatory cf.colo.id, 10s period, 10s mitigation timeout.
resource "cloudflare_ruleset" "ratelimit" {
  zone_id = local.zone_id
  name    = "cf-demo ratelimit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    description = "ratelimit: >5 req / 10s per IP"
    expression  = "http.request.uri.path eq \"/ratelimit\""
    action      = "block"
    ratelimit = {
      characteristics     = ["ip.src", "cf.colo.id"]
      period              = 10
      requests_per_period = 5
      mitigation_timeout  = 10
    }
  }]
}

output "url" { value = "https://${local.host}/" }


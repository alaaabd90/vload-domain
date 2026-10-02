# vload-domain

Fast, stable **passive subdomain reconnaissance** for Linux / WSL — one command to install, one command to run.

For each target domain it discovers subdomains from ~12 passive sources, resolves them, and builds a fully-populated table: **IP, reverse-DNS hostname, organization, ISP, country, ASN, open ports, HTTP status, page title, web server, tech, and ping** — one row per subdomain, every column filled (a clear `-` only when a value genuinely does not exist).

## Quick install (any Debian / Ubuntu / Kali, incl. WSL)

```bash
curl -fsSL https://raw.githubusercontent.com/alaaabd90/vload-domain/main/install.sh | sudo bash
```

This installs the system dependencies and the full toolchain at pinned versions (pulled from this repo's release assets, with an official-source fallback), then installs the `vload` command.

## Usage

```bash
vload example.com                      # single domain
vload facebook.com fb.com fbcdn.net    # multiple, space-separated
vload                                  # prompts for domain(s)
```

Results are written to:

```
~/recon/<domain>_<timestamp>/subdomains.txt
```

and, when run under **WSL**, auto-copied to your **Windows Documents** folder (OneDrive-aware).

### Output columns

```
maindomain | subdomain | ip | hostname | organization | isp | country | asn |
ports | http_code | title | webserver | tech | ping
```

## How it works

1. **Enumerate** — subfinder, amass (passive), assetfinder, findomain, crt.sh, AlienVault OTX, RapidDNS, Wayback, subdomain.center, urlscan.io — all domains and sources in parallel. All sources are free and require no API key. (`certspotter` and `hackertarget` were dropped: their anonymous quotas are exhausted globally and return nothing without a paid key; OTX now uses its still-open `url_list` endpoint instead of the auth-walled `passive_dns` one.)
2. **Resolve** — the public-resolver set is first **validated** (flaky/poisoned resolvers that silently drop valid CNAME-chained hosts are removed), then a **two-pass** resolve runs: a fast bulk pass, followed by a patient, time-budgeted retry of only the leftovers to recover transient failures and slow CNAME chains.
3. **Reverse-DNS expansion** — PTR-sweeps the /24 subnets of resolved IPs to find hosts no passive source lists (not a wordlist / brute-force).
4. **Enrich** — org / ISP / country / ASN for every IP in one shot via Team Cymru bulk (no rate limits).
5. **Probe** — ports (`naabu`), HTTP (`httpx`), reverse-DNS + ping — in parallel, deduplicated per unique IP.
6. **Assemble** — one fully-populated row per subdomain.

Every heavy stage is time-budgeted with partial-result flushing, so a run never hangs or crashes — even for many domains and tens of thousands of subdomains.

## Tuning (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `MAX_PARALLEL_DOMAINS` | 4 | domains enumerated at once (rest queue in batches) — raising this fans out more concurrent requests onto the same external APIs (crt.sh, OTX, hackertarget, urlscan...) and can trip their rate limits, silently zeroing those sources on large multi-domain runs |
| `DNS_THREADS` | 600 | dnsx resolution concurrency |
| `DNS_RETRY` | 2 | first-pass resolution retries (set `1` for a faster run) |
| `RESOLVE2_BUDGET` | 180 | time cap (s) for the patient 2nd resolve pass |
| `HTTP_THREADS` | 400 | httpx concurrency |
| `PTR_MAX_NETS` | 1200 | max /24 subnets for reverse-DNS sweep |
| `PTR_BUDGET` | 300 | hard time budget (s) for the sweep |
| `NAABU_RATE` | 5000 | port-scan packets/sec |
| `PORTS_TO_SCAN` | 80,443,8080,8443,8000,8888 | ports to scan |
| `OUTBASE` | `~/recon` | output directory |

Example: `DNS_RETRY=1 vload example.com`

## Optional: Telegram delivery

```bash
export TELEGRAM_TOKEN="<bot token>"
export TELEGRAM_CHAT_ID="<chat id>"
vload example.com
```

## Bundled toolchain versions

| Tool | Version |
|---|---|
| subfinder | v2.14.0 |
| dnsx | 1.2.3 |
| httpx | v1.9.0 |
| naabu | 2.5.0 |
| amass | v4.2.0 |
| findomain | 9.0.4 |
| assetfinder | latest |

Plus system tools: `jq`, `curl`, `fping`, `whois`, `dnsutils` (`dig`), `ncat`.

## License

MIT — see [LICENSE](LICENSE). For authorized security testing and research only.

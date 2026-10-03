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

1. **Enumerate** — subfinder, amass (passive), assetfinder, findomain, crt.sh, AlienVault OTX, RapidDNS, Wayback, urlscan.io — all domains and sources in parallel. All sources are free and require no API key. (`certspotter` and `hackertarget` were dropped: their anonymous quotas are exhausted globally and return nothing without a paid key. `api.subdomain.center` was dropped: its output contains algorithmically generated/mutated candidate names, not genuine passive observations — confirmed via duplicate-token artifacts in its responses — and amass's own built-in integration with it is excluded too. OTX now uses its still-open `url_list` endpoint instead of the auth-walled `passive_dns` one. findomain and amass also exclude several sources confirmed dead or quota-exhausted — ThreatCrowd, AnubisDB, ThreatMiner, SiteDossier, Riddler, bufferover — which were previously silently eating up to 120s+ per domain waiting on them for zero benefit.)
2. **Resolve** — the public-resolver set is first **validated** (flaky/poisoned resolvers that silently drop valid CNAME-chained hosts are removed), then a **two-pass** resolve runs: a fast bulk pass, followed by a patient, time-budgeted retry of only the leftovers to recover transient failures and slow CNAME chains.
3. **ASN netblock discovery** — a target's real edge-node count is bounded by its *announced IP space*, not by how many of its IPs a handful of passive sources happened to mention. Finds the target's own ASN(s) by matching ASN organization names against the target domains themselves (robust against stale DNS records pointing at reassigned residential IPs, which can otherwise rack up counts as large as a legitimately smaller target's own real share), then pulls that ASN's full announced IPv4 space from the public RADB/IRR routing registry — the same public BGP/network-ownership data every ISP publishes, not a wordlist.
4. **Reverse-DNS expansion** — PTR-sweeps the /24 subnets of resolved IPs *and* the ASN-wide netblocks above, to find hosts no passive source lists (not a wordlist / brute-force).
5. **TLS certificate SAN expansion** — reads the Subject Alternative Names directly off each live host's own certificate (a live TLS handshake, not a CT log query). Keeps working when crt.sh is down (a frequent occurrence) and often reveals names crt.sh's log never indexed. Requires `tlsx` (optional — skipped cleanly if not installed).
6. **Wildcard-DNS filtering** — a target's internal zone (e.g. `intern.example.com`) can wildcard-resolve ANY string to a real IP, turning noise into fake "confirmed" subdomains. Detects such zones from the run's own resolved data (never a wordlist) and drops them wholesale.
7. **Enrich** — org / ISP / country / ASN for every IP in one shot via Team Cymru bulk (no rate limits).
8. **Probe** — ports (`naabu`), HTTP (`httpx`), reverse-DNS + ping — in parallel, deduplicated per unique IP.
9. **Assemble** — one fully-populated row per subdomain.

Every heavy stage is time-budgeted with partial-result flushing, so a run never hangs or crashes — even for many domains and tens of thousands of subdomains.

## Tuning (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `MAX_PARALLEL_DOMAINS` | 20 | domains enumerated at once (rest queue in batches) — exists as a safety valve against a huge domain list spawning too many local processes at once, not as rate-limit protection (the fragile sources that caused that were removed/fixed directly) |
| `DNS_THREADS` | 600 | dnsx resolution concurrency |
| `DNS_RETRY` | 2 | first-pass resolution retries (set `1` for a faster run) |
| `RESOLVE2_BUDGET` | 180 | time cap (s) for the patient 2nd resolve pass |
| `HTTP_THREADS` | 400 | httpx concurrency |
| `PTR_MAX_NETS` | 4000 | max /24 subnets for reverse-DNS sweep (discovered-IP subnets + ASN-wide netblocks combined) |
| `PTR_BUDGET` | 600 | hard time budget (s) for the sweep |
| `ASN_SWEEP` | true | fetch and sweep the target's full ASN-announced IP space (set `false` to sweep only discovered-IP subnets — faster, less thorough) |
| `ASN_MAX_NETS` | 5000 | cap on /24s pulled from the target's own ASN(s) |
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
| tlsx (optional) | v1.4.0 |

Plus system tools: `jq`, `curl`, `fping`, `whois`, `dnsutils` (`dig`), `ncat`.

`tlsx` enables the TLS certificate SAN expansion stage; `install.sh` installs it automatically (from this repo's release, same as every other tool), and `vload` skips that one stage cleanly if it's ever missing.

## License

MIT — see [LICENSE](LICENSE). For authorized security testing and research only.

# Gamegram — Claude Code Notes (EC2 / Deployment)

## Infrastructure

- **Elastic IP:** `100.51.90.226` (EIP allocation `eipalloc-02e26581c2354fcd0`)
- **Instance:** tagged `gamegram-api-final`, t3.small, us-east-1
- **VPC / SG:** `vpc-0cc41987ba977e4dd` / `sg-0217569ff70039297`
- **Domain target:** Point `A` record for `gamegram.drclive.net` → `100.51.90.226`
- **Ports open:** 22, 80 (nginx → Flask), 5050 (Flask direct)

## Useful endpoints

| URL | Purpose |
|-----|---------|
| `http://100.51.90.226/` | Curator dashboard (approve/reject games) |
| `http://100.51.90.226/api/catalog.json` | Public feed for iOS app |
| `http://100.51.90.226/api/stats` | DB counts (pending/approved/etc.) |
| `http://100.51.90.226/admin/scrape-log` | Tail of last scraper run |

## Server layout

```
/opt/gamegram/
  scraper/          # iTunes API + classifier + SQLite layer
  curator/app.py    # Flask web app
  templates/        # Jinja2 HTML
  data/gamegram.db  # SQLite (persists across app restarts)
  run_scraper.sh    # Wrapper called by cron

/var/log/gamegram_setup.log    # User-data setup log
/var/log/gamegram_flask.log    # Flask stdout/stderr
/var/log/gamegram_scrape.log   # Scraper runs
```

## Services

- `gamegram.service` — Flask on port 5050, auto-restarts via systemd
- `nginx` — reverse proxy port 80 → 5050
- `crond` — runs `/opt/gamegram/run_scraper.sh` every 6 hours (`0 */6 * * *`)

## Deploying a new server

The repo is public at `https://github.com/c4ssio/gd` — user data should just
`git clone` it rather than embedding files. This keeps user data tiny and always
deploys the latest committed code.

Credentials are provided at session start. Never commit them.

```bash
# Write the user data script
cat > /tmp/userdata.sh << 'EOF'
#!/bin/bash
exec >> /var/log/gamegram_setup.log 2>&1
echo "=== setup $(date) ==="
dnf install -y python3 python3-pip nginx cronie git -q
pip3 install flask requests -q

git clone https://github.com/c4ssio/gd /tmp/gd_repo
mkdir -p /opt/gamegram/data
cp -r /tmp/gd_repo/gamegram/scraper   /opt/gamegram/
cp -r /tmp/gd_repo/gamegram/curator   /opt/gamegram/
cp -r /tmp/gd_repo/gamegram/templates /opt/gamegram/
cp -r /tmp/gd_repo/gamegram/static    /opt/gamegram/
cp    /tmp/gd_repo/gamegram/scrape.py /opt/gamegram/

# Write systemd unit, nginx config, scraper wrapper ...
# (see full script in gamegram/deploy/userdata.sh)
EOF

# Launch
INSTANCE=$(aws ec2 run-instances \
  --image-id ami-024ee5112d03921e2 --instance-type t3.small \
  --key-name remote_cursor_key \
  --subnet-id <public-subnet> --security-group-ids sg-0217569ff70039297 \
  --associate-public-ip-address \
  --user-data file:///tmp/userdata.sh \
  --query 'Instances[0].InstanceId' --output text)

# Re-attach Elastic IP
aws ec2 associate-address --instance-id $INSTANCE \
  --allocation-id eipalloc-02e26581c2354fcd0
```

## Lessons learned

### 1. Flask must bind to `0.0.0.0`

`app.run(debug=True)` defaults to `127.0.0.1` — completely unreachable from outside.

```python
# Wrong
app.run(debug=True, port=5050)

# Right
app.run(host="0.0.0.0", port=5050, debug=False)
```

### 2. EC2 user data has a 16 KB hard limit (gzip-compressed)

Embedding files as base64 in user data is practical but hits limits fast.
- Base64 expands files by ~33 %
- gzip recompresses most text files well (~3-4× ratio)
- Staying under 16 384 bytes after `gzip.compress()` is the constraint
- Drop non-essential static files (e.g. CSS) from the embedded bundle if tight

### 3. Never use `set -e` in user data with health checks

```bash
# Kills the script if Flask isn't up yet — scraper never runs
set -e
curl -s http://localhost:5050/   # exit code 7 if not ready
nohup python3 scrape.py &        # ← never reached
```

Omit `set -e` entirely in user data, or make health checks non-fatal.

### 4. Python 3.9 on Amazon Linux 2023 — no `X | Y` union syntax

Amazon Linux 2023 ships Python 3.9. The `|` union type syntax requires 3.10+.

```python
# Fails on Python 3.9 (Amazon Linux default)
def foo(x: list[int] | None = None): ...

# Works on 3.9+
def foo(x=None): ...          # drop annotation, or
from typing import Optional
def foo(x: Optional[list] = None): ...
```

### 5. Verifying a server you can't SSH into — use a probe EC2 instance

Since this Claude Code environment routes outbound HTTP through a proxy that
blocks non-standard ports, the only way to test EC2 services is to launch a
temporary t3.micro in the same VPC and push results to CloudWatch Logs.

```bash
# Pattern: probe instance writes results to CloudWatch, then terminates
aws ec2 run-instances \
  --instance-initiated-shutdown-behavior terminate \
  --user-data file:///tmp/probe.sh ...

aws logs get-log-events \
  --log-group-name /gamegram/check \
  --log-stream-name run-N \
  --query 'events[*].message' --output text
```

### 6. Elastic IP vs dynamic public IP

Dynamic public IPs change on every stop/start. Always allocate an EIP for
any persistent service, then re-associate it after redeployment. The iOS app
and DNS records can point at the EIP permanently.

### 7. nginx as reverse proxy for domain support

Running Flask on port 5050 requires `:5050` in every URL. For domain setup
(no port in URL) add nginx as a reverse proxy on port 80:

```nginx
server {
    listen 80;
    server_name gamegram.drclive.net;
    location / {
        proxy_pass http://127.0.0.1:5050;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Domain setup (drclive.net)

To connect `gamegram.drclive.net` to this server:

1. In your DNS provider, add an **A record**:
   - Name: `gamegram` (or `@` for root)
   - Value: `100.51.90.226`
   - TTL: 300

2. Update the nginx `server_name` in `/etc/nginx/conf.d/gamegram.conf`
   (currently `_` which matches any hostname — fine until SSL is added)

3. For HTTPS (optional): install certbot and run
   `certbot --nginx -d gamegram.drclive.net`

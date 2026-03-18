#!/bin/bash
# Gamegram EC2 user data — clones the public repo and starts all services.
# Repo: https://github.com/c4ssio/gd
exec >> /var/log/gamegram_setup.log 2>&1
echo "=== Gamegram setup $(date) ==="

dnf install -y python3 python3-pip nginx cronie git -q
pip3 install flask requests -q

# Pull latest code from public repo
git clone https://github.com/c4ssio/gd /tmp/gd_repo
mkdir -p /opt/gamegram/data
cp -r /tmp/gd_repo/gamegram/scraper   /opt/gamegram/
cp -r /tmp/gd_repo/gamegram/curator   /opt/gamegram/
cp -r /tmp/gd_repo/gamegram/templates /opt/gamegram/
cp -r /tmp/gd_repo/gamegram/static    /opt/gamegram/
cp    /tmp/gd_repo/gamegram/scrape.py /opt/gamegram/

# nginx reverse proxy: port 80 → Flask 5050
cat > /etc/nginx/conf.d/gamegram.conf << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:5050;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINXEOF
rm -f /etc/nginx/conf.d/default.conf

# systemd service for Flask
cat > /etc/systemd/system/gamegram.service << 'UNITEOF'
[Unit]
Description=Gamegram Flask API
After=network.target

[Service]
WorkingDirectory=/opt/gamegram
ExecStart=/usr/bin/python3 curator/app.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/gamegram_flask.log
StandardError=append:/var/log/gamegram_flask.log

[Install]
WantedBy=multi-user.target
UNITEOF

# Scraper wrapper (used by cron)
cat > /opt/gamegram/run_scraper.sh << 'SCRAPEREOF'
#!/bin/bash
cd /opt/gamegram
echo "=== Scrape $(date) ===" >> /var/log/gamegram_scrape.log
python3 scrape.py --genres arcade puzzle action family strategy --limit 200 \
  >> /var/log/gamegram_scrape.log 2>&1
SCRAPEREOF
chmod +x /opt/gamegram/run_scraper.sh

# Enable and start services
systemctl daemon-reload
systemctl enable --now gamegram nginx crond

# Cron: scrape every 6 hours
(crontab -l 2>/dev/null; echo "0 */6 * * * /opt/gamegram/run_scraper.sh") | crontab -

sleep 3
systemctl is-active gamegram nginx

# Kick off first scrape in background
nohup /opt/gamegram/run_scraper.sh &
echo "Scraper PID: $!"
echo "=== Setup complete $(date) ==="

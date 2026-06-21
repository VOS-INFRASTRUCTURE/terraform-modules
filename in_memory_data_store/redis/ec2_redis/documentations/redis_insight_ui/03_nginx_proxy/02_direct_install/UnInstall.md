🧹 FULL CLEAN RESET (safe, step-by-step)
1. Stop RedisInsight service
sudo systemctl stop redisinsight
sudo systemctl disable redisinsight
2. Remove systemd service file
sudo rm -f /etc/systemd/system/redisinsight.service
sudo systemctl daemon-reload
sudo systemctl reset-failed

Verify:

systemctl status redisinsight

Should now say:

Unit redisinsight.service could not be found

3. Remove RedisInsight application files
sudo rm -rf /opt/redisinsight
sudo rm -rf /var/lib/redisinsight
4. Remove RedisInsight nginx config (IMPORTANT)

Check first:

ls /etc/nginx/sites-enabled/

If you see:

redis-insight

Remove it:

sudo rm -f /etc/nginx/sites-enabled/redis-insight
sudo rm -f /etc/nginx/sites-available/redis-insight

Test nginx:

sudo nginx -t

Reload:

sudo systemctl reload nginx
5. Remove user (optional but clean)
sudo userdel redisinsight

If it complains:

sudo userdel -r redisinsight
6. Confirm nothing is left running
ps aux | grep redisinsight
ss -tlnp | grep 5540

Both should return NOTHING.

✅ What you should still have after cleanup

You should ONLY still have:

Redis server (6379)
Nginx
ALB
Terraform infra
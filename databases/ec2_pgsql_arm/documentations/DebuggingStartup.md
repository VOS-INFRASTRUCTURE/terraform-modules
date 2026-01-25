```shell
sudo tail -n 200 /var/log/cloud-init-output.log

# Check listening ports
sudo netstat -tulpn
sudo netstat -tulpn | grep LISTEN
sudo ss -tulpn

sudo -u postgres psql -c "SELECT 1;"
```
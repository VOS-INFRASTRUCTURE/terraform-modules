```shell
sudo tail -n 200 /var/log/cloud-init-output.log

# Check listening ports
sudo netstat -tulpn
sudo netstat -tulpn | grep LISTEN
sudo ss -tulpn

sudo -u postgres psql -c "SELECT 1;"

# Copy start up script from cloud init to /root and execute manually
sudo cp /var/lib/cloud/instance/scripts/part-001 /root/startup_script.sh
sudo chmod +x /root/startup_script.sh
sudo /root/startup_script.sh
```
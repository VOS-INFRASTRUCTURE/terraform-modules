pid=$(pidof qdrant)
sudo tr '\0' '\n' < /proc/$pid/environ | grep QDRANT


sudo su root
cat /etc/qdrant/qdrant.env


systemctl daemon-reload
systemctl restart qdrant

pid=$(pidof qdrant)
sudo tr '\0' '\n' < /proc/$pid/environ | grep QDRANT

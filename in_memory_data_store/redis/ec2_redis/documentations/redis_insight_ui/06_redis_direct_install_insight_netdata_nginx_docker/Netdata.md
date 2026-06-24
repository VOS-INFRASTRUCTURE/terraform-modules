Configure Redis

cat > /etc/netdata/go.d/redis.conf <<EOF
jobs:
  - name: redis_secure
    address: redis://:LwZnrDTfeD0q2OvDGdSWeT4CJcjcXctY@10.1.1.164:6379
EOF


restart container


multiple instances

jobs:
  - name: redis_app
    address: redis://:PASSWORD@10.1.1.164:6379

  - name: redis_queue
    address: redis://:PASSWORD@10.1.1.165:6379

  - name: redis_cache
    address: redis://:PASSWORD@10.1.1.166:6379
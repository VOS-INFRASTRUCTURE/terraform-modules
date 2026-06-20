Redis Insight UI auth
❌ Not directly
Protects access to http://localhost:5540
Redis Insight can connect to password-protected Redis instances, and it supports preconfigured Redis database connections via environment variables or JSON configuration [1]. But protecting the Redis Insight web UI itself is normally done with a reverse proxy such as Nginx Basic Auth. Redis also provides an example reverse-proxy setup for Redis Insight with Basic Auth [2].
For local development, exposing Redis Insight on localhost:5540 is usually acceptable. But if you want authentication even locally, the better setup is:

Browser
  ↓
Nginx Basic Auth :5540
  ↓
Redis Insight internal port :5540
  ↓
redis-app1 / redis-app2 with Redis passwords




you would keep Redis Insight internal and expose it through Nginx.
### Updated Compose idea

services:
  redis-app1:
    image: redis:7.4-alpine
    container_name: redis-app1
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - ./docker/redis/app1.conf:/usr/local/etc/redis/redis.conf:ro
      - redis-app1-data:/data
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]

  redis-app2:
    image: redis:7.4-alpine
    container_name: redis-app2
    restart: unless-stopped
    ports:
      - "6380:6379"
    volumes:
      - ./docker/redis/app2.conf:/usr/local/etc/redis/redis.conf:ro
      - redis-app2-data:/data
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]

  redis-insight:
    image: redis/redisinsight:latest
    container_name: redis-insight
    restart: unless-stopped
    expose:
      - "5540"
    volumes:
      - redis-insight-data:/data
    depends_on:
      - redis-app1
      - redis-app2

  redis-insight-proxy:
    image: nginx:1.27-alpine
    container_name: redis-insight-proxy
    restart: unless-stopped
    ports:
      - "5540:80"
    volumes:
      - ./docker/nginx/redis-insight.conf:/etc/nginx/conf.d/default.conf:ro
      - ./docker/nginx/.htpasswd:/etc/nginx/.htpasswd:ro
    depends_on:
      - redis-insight

volumes:
  redis-app1-data:
  redis-app2-data:
  redis-insight-data:


### `docker/nginx/redis-insight.conf`

server {
    listen 80;

    auth_basic "Redis Insight";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://redis-insight:5540;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

## Create the Basic Auth password file
For example, username: `admin`.``` bash
mkdir -p docker/nginx
```

Using Docker to generate the .htpasswd file:``` bash
docker run --rm httpd:2.4-alpine htpasswd -nbB admin 'RedisInsightStrongPass!' > docker/nginx/.htpasswd
```

Then start:
You should now get a browser Basic Auth prompt:``` text
Username: admin
Password: RedisInsightStrongPass!
```




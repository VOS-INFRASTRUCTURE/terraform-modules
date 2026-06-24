# Redis Insight — Direct Installation

Install Redis Insight as a native desktop application on your local machine. This is
the simplest approach for individual developers who need to inspect a remote EC2 Redis
instance without running Docker locally.

---

## Flow

```
  Your Laptop
  ┌──────────────────────────────────────────────┐
  │                                              │
  │   Redis Insight (desktop)                    │
  │        │                                     │
  │        │ connects to localhost:6379           │
  │        ▼                                     │
  │   SSH Local Port Forward                     │
  │   localhost:6379 ──────────────────────────► SSH tunnel (:22)
  │                                              │          │
  └──────────────────────────────────────────────┘          │
                                                            ▼
                                               EC2 Redis Server
                                               ┌────────────────┐
                                               │  Redis :6379   │
                                               │  (private IP)  │
                                               └────────────────┘
```

Redis Insight connects to `localhost:6379` on your machine. The SSH tunnel forwards
that port transparently to the Redis port on the remote EC2 instance.

---

## 1. Download and Install

Go to the official download page and pick your OS:

| OS | Package |
|----|---------|
| macOS | `.dmg` — drag to Applications |
| Windows | `.exe` installer |
| Linux | `.AppImage` (portable) or `.deb` / `.rpm` |

> Redis Insight 2.x is the current version. It uses port 5540 for its web UI
> (when running in headless mode) but as a desktop app it opens its own window.

After installing, launch **Redis Insight** from your Applications / Start Menu.

---

## 2. Open an SSH Tunnel to Your EC2 Redis

Your EC2 Redis runs on a private subnet and is not reachable directly. Open a tunnel
in a terminal before connecting Redis Insight.

**Single Redis instance (App 1, port 6379):**

```bash
ssh -N -L 6379:localhost:6379 ubuntu@<EC2_PUBLIC_IP_OR_BASTION>
```

**Multiple Redis instances on the same host:**

```bash
# Run each tunnel in a separate terminal, or combine with -L flags
ssh -N \
  -L 6379:localhost:6379 \
  -L 6380:localhost:6380 \
  ubuntu@<EC2_PUBLIC_IP_OR_BASTION>
```

Leave this terminal running. The tunnel stays open as long as the process is alive.

> **Tip:** If you go through a bastion host, chain the jump:
> ```bash
> ssh -N -L 6379:localhost:6379 -J ubuntu@<BASTION_IP> ubuntu@<REDIS_EC2_PRIVATE_IP>
> ```

---

## 3. Add a Database in Redis Insight

1. Open Redis Insight.
2. Click **+ Add Redis database**.
3. Fill in the form:

```
Host:     localhost
Port:     6379          ← the local end of your SSH tunnel
Name:     my-app-redis  ← any label you choose
Username: (leave blank)
Password: <your redis password>    ← set in var.redis_password
```

4. Click **Test Connection** — you should see a green success banner.
5. Click **Add Redis Database**.

Repeat for each app port (6380, 6381, …), giving each a distinct name.

---

## 4. Browsing Keys

After connecting, click the database name in the left sidebar.

| Panel | What it shows |
|-------|--------------|
| **Browser** | All keys with type, TTL, and size; searchable by pattern |
| **Workbench** | Interactive command editor — type any Redis command and see the result |
| **Profiler** | Live stream of commands hitting Redis (like `MONITOR`) |
| **Analysis Tools** | Memory usage breakdown by key type and pattern |

---

## 5. Running Commands

Click **Workbench** in the left nav. Type any Redis command:

```
PING
SET foo bar
GET foo
TTL foo
KEYS *
INFO server
```

The editor has auto-complete and shows command documentation inline.

---

## Closing the Connection Safely

Redis Insight stores connection profiles locally. Your passwords are persisted
encrypted in the app's local data directory. When you are done:

1. Close the SSH tunnel (`Ctrl+C` in the tunnel terminal).
2. Redis Insight will show the database as offline — that is expected.
3. Reopen the tunnel next time you need access.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Connection refused on localhost:6379 | SSH tunnel not running | Start the tunnel first |
| Authentication failed | Wrong password | Verify `var.redis_password` in Terraform outputs |
| Tunnel drops after idle | SSH server `ClientAliveInterval` too short | Add `-o ServerAliveInterval=60` to your SSH command |
| Can't reach bastion | Key not loaded | Run `ssh-add /path/to/key.pem` first |

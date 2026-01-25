1️⃣ Check if the agent binary exists (fastest signal)
which amazon-cloudwatch-agent


If installed, you’ll usually see:

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent


If nothing prints → likely not installed.

2️⃣ Check systemd service (most authoritative)
systemctl status amazon-cloudwatch-agent


Possible outcomes:

✅ Installed + running

✅ Installed + stopped

❌ Unit amazon-cloudwatch-agent.service could not be found

That last one means it’s not installed via deb/rpm.

3️⃣ Check snap (rare, but you asked)
snap list | grep -i cloudwatch


If installed via snap, you’ll see it here.

⚠️ AWS does not officially ship CloudWatch Agent as a snap — but some custom AMIs do.

4️⃣ Check dpkg (official Ubuntu install path)
dpkg -l | grep amazon-cloudwatch-agent


If you see:

ii  amazon-cloudwatch-agent  x.y.z


Then it’s installed via .deb.

5️⃣ Check running process (catches manual installs)
ps aux | grep amazon-cloudwatch-agent | grep -v grep


This catches:

manual installs

tarball-based installs

weird legacy setups

6️⃣ Check install directory directly (bulletproof)
ls -d /opt/aws/amazon-cloudwatch-agent 2>/dev/null


If that directory exists → the agent exists.
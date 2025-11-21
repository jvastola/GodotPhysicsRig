# Oracle Cloud Deployment Guide

This guide walks you through deploying the Godot Matchmaking Server to Oracle Cloud Infrastructure (OCI).

## Prerequisites

- Oracle Cloud account (free tier is sufficient)
- SSH key pair for server access
- Basic familiarity with command line

## Step 1: Create a Compute Instance

### 1.1 Create the Instance

1. Log in to [Oracle Cloud Console](https://cloud.oracle.com/)
2. Navigate to **Compute** > **Instances**
3. Click **Create Instance**
4. Configure the instance:
   - **Name**: `godot-matchmaking-server`
   - **Image**: Ubuntu 22.04 (or latest)
   - **Shape**: VM.Standard.E2.1.Micro (free tier eligible)
   - **VCN**: Use default or create new
   - **SSH Keys**: Upload your public key or generate new pair
5. Click **Create**

### 1.2 Note the Public IP

After creation, note the **Public IP Address** - you'll need this for:
- SSH access
- Godot client configuration

## Step 2: Configure Firewall Rules

### 2.1 Security List (OCI Firewall)

1. Go to **Networking** > **Virtual Cloud Networks**
2. Click on your VCN
3. Click on the subnet your instance is in
4. Click on the default **Security List**
5. Click **Add Ingress Rules**
6. Add the following rule:
   - **Source CIDR**: `0.0.0.0/0`
   - **IP Protocol**: TCP
   - **Destination Port Range**: `8080`
   - **Description**: Godot Matchmaking Server
7. Click **Add Ingress Rules**

### 2.2 Instance Firewall (Ubuntu)

SSH into your instance and configure the OS firewall:

```bash
# SSH into your instance
ssh ubuntu@<your-public-ip>

# Update system
sudo apt update && sudo apt upgrade -y

# Configure firewall
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 8080/tcp  # Matchmaking server
sudo ufw enable
sudo ufw status
```

## Step 3: Install Docker

### 3.1 Install Docker and Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose -y

# Log out and back in for group changes to take effect
exit
```

SSH back in:
```bash
ssh ubuntu@<your-public-ip>

# Verify Docker installation
docker --version
docker-compose --version
```

## Step 4: Deploy the Server

### 4.1 Transfer Files to Server

**Option A: Using Git (Recommended)**

```bash
# On the server
cd ~
git clone <your-repository-url>
cd GodotPhysicsRig/godotmatchmaking
```

**Option B: Using SCP**

```bash
# On your local machine
cd /path/to/GodotPhysicsRig
scp -r godotmatchmaking ubuntu@<your-public-ip>:~/
```

### 4.2 Start the Server

```bash
# On the server, in the godotmatchmaking directory
cd ~/godotmatchmaking  # or ~/GodotPhysicsRig/godotmatchmaking

# Build and start with docker-compose
docker-compose up -d

# Check if it's running
docker ps
docker logs godot-matchmaking
```

### 4.3 Verify the Server

```bash
# Test the health endpoint
curl http://localhost:8080/health

# Expected response:
# {"status":"ok","uptime":X,"rooms":0,"timestamp":XXXXX}
```

From your local machine:
```bash
curl http://<your-public-ip>:8080/health
```

## Step 5: Configure Auto-Start on Boot

Ensure the server restarts automatically if the instance reboots:

```bash
# Docker Compose will auto-restart containers
# Verify the restart policy in docker-compose.yml shows: restart: unless-stopped

# Enable Docker to start on boot
sudo systemctl enable docker
```

## Step 6: Update Godot Client

In your Godot project, update the matchmaking server URL:

```gdscript
# In a script that runs early (e.g., network_manager.gd or main menu)
var matchmaking = get_node("/root/MatchmakingServer")
matchmaking.matchmaking_url = "http://<your-public-ip>:8080"
```

Or set it in the NetworkUI:
1. Launch the game
2. Enter your server's public IP and port in the NetworkUI

## Step 7: Testing

### 7.1 Test Room Registration

From your local machine:

```bash
# Register a test room
curl -X POST http://<your-public-ip>:8080/room \
  -H "Content-Type: application/json" \
  -d '{"room_code":"TEST123","ip":"192.168.1.100","port":7777,"host_name":"TestHost"}'

# Lookup the room
curl http://<your-public-ip>:8080/room/TEST123

# List all rooms
curl http://<your-public-ip>:8080/rooms
```

### 7.2 Test with Godot

1. Launch two instances of your Godot game
2. Configure both to use your Oracle Cloud server
3. Host a game on instance 1
4. Join the game on instance 2

## Monitoring and Maintenance

### View Logs

```bash
# View real-time logs
docker logs -f godot-matchmaking

# View last 100 lines
docker logs --tail 100 godot-matchmaking
```

### Restart Server

```bash
cd ~/godotmatchmaking
docker-compose restart
```

### Stop Server

```bash
docker-compose down
```

### Update Server

```bash
# Pull latest changes (if using git)
git pull

# Rebuild and restart
docker-compose up -d --build
```

### Check Resource Usage

```bash
# View container stats
docker stats godot-matchmaking

# View instance resources
htop  # Install with: sudo apt install htop
```

## Optional: Set Up HTTPS with Domain

For production use, consider setting up a domain name and HTTPS:

### Prerequisites
- A domain name pointing to your server's IP
- Certbot for Let's Encrypt SSL

### Install Nginx and Certbot

```bash
sudo apt install nginx certbot python3-certbot-nginx -y
```

### Configure Nginx Reverse Proxy

```bash
sudo nano /etc/nginx/sites-available/matchmaking
```

Add:
```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/matchmaking /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Get SSL certificate
sudo certbot --nginx -d your-domain.com
```

Update your Godot client to use `https://your-domain.com`

## Troubleshooting

### Server Not Accessible

1. Check firewall rules (OCI Security List and Ubuntu UFW)
2. Verify Docker container is running: `docker ps`
3. Check logs: `docker logs godot-matchmaking`
4. Test locally on server: `curl http://localhost:8080/health`

### Container Won't Start

```bash
# Check logs for errors
docker logs godot-matchmaking

# Rebuild from scratch
docker-compose down
docker-compose up --build
```

### Port Already in Use

```bash
# Find what's using port 8080
sudo lsof -i :8080

# Kill the process or change PORT in .env
```

### Out of Memory

The free tier VM has limited memory. Monitor usage:
```bash
free -h
docker stats
```

Consider stopping other services or upgrading to a larger instance.

## Security Best Practices

1. **Keep system updated**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Change SSH port** (optional):
   Edit `/etc/ssh/sshd_config` and change port from 22

3. **Set up fail2ban**:
   ```bash
   sudo apt install fail2ban -y
   ```

4. **Regular backups**: Snapshot your instance periodically

5. **Monitor logs**: Set up log monitoring for unusual activity

## Cost Considerations

- **Free Tier**: Oracle Cloud offers always-free tier with sufficient resources
- **Network**: Egress (outbound) data may have limits
- **Keep monitoring**: Set up billing alerts in OCI console

## Support

If you encounter issues:
- Check server logs: `docker logs godot-matchmaking`
- Verify firewall configuration
- Test with curl commands
- Check Oracle Cloud service health dashboard

## Next Steps

- Set up monitoring (e.g., UptimeRobot, Prometheus)
- Configure automated backups
- Add authentication to API endpoints
- Implement Redis for persistent storage
- Set up CI/CD for automatic deployments

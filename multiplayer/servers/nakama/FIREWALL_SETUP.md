# Oracle Cloud Firewall Configuration - Step by Step

## ⚠️ IMPORTANT: Complete This Step to Enable Nakama Access

The Nakama server is running on Oracle Cloud but **external access is currently blocked** by the firewall. You need to add firewall rules in the Oracle Cloud Console.

## Step-by-Step Instructions

### 1. Sign in to Oracle Cloud Console

You already have the sign-in page open in your browser:
https://www.oracle.com/cloud/sign-in.html

1. Enter your Cloud Account Name
2. Sign in with your credentials

### 2. Navigate to Security List

1. From the main dashboard, click the **hamburger menu** (☰) in the top left
2. Navigate to: **Networking** → **Virtual Cloud Networks**
3. Click on your VCN (Virtual Cloud Network)
4. Click on the **Subnet** that your instance is using
5. Under "Security Lists", click **Default Security List**

### 3. Add Ingress Rules for Nakama

Click the **"Add Ingress Rules"** button and add these THREE rules:

#### Rule 1: Nakama WebSocket API (REQUIRED)
```
Source Type: CIDR
Source CIDR: 0.0.0.0/0
IP Protocol: TCP
Destination Port Range: 7350
Description: Nakama WebSocket API
```
Click **"Add Ingress Rules"**

#### Rule 2: Nakama Admin Console (Optional but recommended)
```
Source Type: CIDR
Source CIDR: 0.0.0.0/0
IP Protocol: TCP
Destination Port Range: 7351
Description: Nakama Admin Console
```
Click **"Add Ingress Rules"**

#### Rule 3: Nakama gRPC (Optional)
```
Source Type: CIDR
Source CIDR: 0.0.0.0/0
IP Protocol: TCP
Destination Port Range: 7349
Description: Nakama gRPC API
```
Click **"Add Ingress Rules"**

### 4. Verify the Rules

After adding all three rules, you should see them listed in the Ingress Rules table.

## Testing After Configuration

### Test 1: Check Healthcheck Endpoint

Open PowerShell on your local machine and run:

```powershell
Invoke-WebRequest -Uri "http://158.101.21.99:7350/healthcheck" -UseBasicParsing
```

Expected result: HTTP 200 with JSON response `{}`

### Test 2: Access Admin Console

Open your browser and go to:
```
http://158.101.21.99:7351
```

**Login credentials:**
- Username: `admin`
- Password: `password`

### Test 3: Test from Godot

Your Godot project is already configured to connect to the Oracle Cloud server (158.101.21.99:7350).

1. Open your Godot project
2. Run the nakama_test scene or main scene
3. Try to authenticate and create/join a room

## What Changed

✅ **Nakama Manager Updated**: Changed `nakama_host` from `"localhost"` to `"158.101.21.99"`

The configuration is at:
[nakama_manager.gd](file:///C:/Users/Admin/GodotPhysicsRig/multiplayer/nakama_manager.gd) (line 18)

## Troubleshooting

### Firewall rules added but still can't connect
- Wait 30-60 seconds for rules to propagate
- Verify the rules are in the correct Security List for your instance's subnet
- Check that Source CIDR is `0.0.0.0/0` (allows all IPs)

### Still timing out
- SSH into your server and check Nakama is running:
  ```bash
  docker ps
  docker logs nakama --tail 20
  ```

### Admin console login fails
- Default credentials are: admin / password
- If changed, check `nakama/data/local.yml` for the correct password

## Next Steps

1. ✅ Complete the Oracle Cloud firewall configuration above
2. ✅ Test endpoint from PowerShell
3. ✅ Test from Godot - try authenticating and creating a room
4. ✅ Verify in admin console that your room appears

Once the firewall is configured, everything should work!

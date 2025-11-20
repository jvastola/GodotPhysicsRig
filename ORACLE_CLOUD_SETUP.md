# Oracle Cloud VM Setup for Godot Matchmaking Server

This guide walks you through deploying your Godot matchmaking server on Oracle Cloud Free Tier, step by step.

---

## 1. Create Oracle Cloud VM (Always Free)
- Go to https://cloud.oracle.com/
- Navigate to **Compute > Instances**
- Click **Create Instance**
- Select **Always Free eligible shape** (e.g., AMD/Arm)
- Under **SSH keys**, paste your public key
- Under **Networking**, select or create a public subnet
- Make sure **Assign public IP address** is checked
- Finish and wait for VM to start

---

## 2. Find Your Public IP
- In the Oracle Console, go to your instance details
- Look for **Public IPv4 address** (e.g., `158.101.21.99`)

---

## 3. SSH Into Your VM
On your local machine (Windows PowerShell):

```powershell
ssh -i "ssh.key" ubuntu@158.101.21.99
```

On Linux/macOS:

```bash
ssh -i ~/Downloads/ssh-key-2025-11-20.key ubuntu@158.101.21.99
```

---

## 4. Install Godot Headless (Server)
Run these commands in your SSH session:

```bash
sudo apt update
sudo apt install -y wget unzip
wget https://downloads.tuxfamily.org/godotengine/4.2.1/Godot_v4.2.1-stable_linux.x86_64.zip
unzip Godot_v4.2.1-stable_linux.x86_64.zip
sudo mv Godot_v4.2.1-stable_linux.x86_64 /usr/local/bin/godot
sudo chmod +x /usr/local/bin/godot
```

---

## 5. Upload Your Project Files
On your local Windows PC, run:

```powershell
scp -i "C:\Users\Admin\Downloads\ssh-key-2025-11-20.key" -r "C:\Users\Admin\GodotPhysicsRig" ubuntu@158.101.21.99:~
```

On Linux/macOS:

```bash
scp -i ~/Downloads/ssh-key-2025-11-20.key -r ~/GodotPhysicsRig ubuntu@158.101.21.99:~
```

---

## 6. Open Firewall Port 8080
- In Oracle Console, go to **Networking > Virtual Cloud Networks (VCN)**
- Select your VCN, then **Security Lists**
- Edit the security list for your subnet
- Add an **Ingress Rule**:
  - Source CIDR: `0.0.0.0/0`
  - Destination Port Range: `8080`
  - Protocol: `TCP`
- Save changes

---

## 7. Run the Matchmaking Server
SSH into your VM and run:

```bash
cd ~/GodotPhysicsRig
/usr/local/bin/godot --headless --script server_standalone.gd
```

---

## 8. Update Your Game Client
- Set `MATCHMAKING_SERVER_URL` in your game to:
  ```
  http://158.101.21.99:8080
  ```

---

## 9. Test Global Connectivity
- Host a game and join from another network using room code
- Verify voice, voxel sync, and grabbable objects work globally

---

## 10. Billing Safety
- Use only **Always Free** resources
- Monitor the **Billing Dashboard** for unexpected charges
- Stop or terminate VM if not needed

---

## Troubleshooting
- If you can't connect, check:
  - Public IP is assigned
  - Port 8080 is open in security list
  - Godot server is running
  - Your client uses the correct IP and port

---

## Useful Links
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
- [Godot Headless Downloads](https://godotengine.org/download/server)
- [Oracle Networking Docs](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingVCNs.htm)

---

**You’re now ready to run your Godot matchmaking server globally!**

# HNG Stage 1 - Automated Deployment Script

## Overview

This project provides a robust, production-grade Bash script that automates the complete deployment pipeline of a Dockerized application on a remote Linux server, including Nginx reverse proxy configuration.

## Author

- **Name:** Aba Nicaisse
- **Slack Username:** @Aba Nicaisse
- **HNG Track:** DevOps
- **Stage:** 1

## Features

✅ **Fully Automated Deployment** - One command deploys everything  
✅ **Comprehensive Error Handling** - Graceful failures with detailed logging  
✅ **Idempotent Operations** - Safe to run multiple times  
✅ **Input Validation** - Validates all user inputs before proceeding  
✅ **Docker Support** - Works with both Dockerfile and docker-compose  
✅ **Nginx Configuration** - Automatic reverse proxy setup  
✅ **Detailed Logging** - Timestamped logs for debugging  
✅ **Color-Coded Output** - Easy-to-read terminal output

## Prerequisites

### Local Machine Requirements

- Bash shell (Linux/macOS/WSL)
- Git installed
- SSH client
- rsync installed
- SSH key for remote server access

### Remote Server Requirements

- Ubuntu/Debian-based Linux (20.04+ recommended)
- SSH access with sudo privileges
- Open port 80 (HTTP)
- At least 1GB RAM, 10GB disk space

## Quick Start

### 1. Clone This Repository

```bash
git clone https://github.com/abanicaisse/hng13-stage1-devops.git
cd hng3-stage1-devops
```

### 2. Make Script Executable

```bash
chmod +x deploy.sh
```

### 3. Prepare Your Application Repository

Ensure your application repository has:

- A `Dockerfile` OR `docker-compose.yml`
- Application that exposes a specific port

### 4. Run the Deployment Script

```bash
./deploy.sh
```

### 5. Follow the Prompts

The script will ask for:

- Git repository URL (e.g., `https://github.com/username/app.git`)
- Personal Access Token (for private repos)
- Branch name (default: `main`)
- Remote server username (e.g., `ubuntu`)
- Remote server IP address (e.g., `54.123.45.67`)
- SSH key path (default: `~/.ssh/id_rsa`)
- Application port (e.g., `3000`, `8080`)

## Usage Example

```bash
$ ./deploy.sh

[INFO] === Stage 1: Collecting Deployment Parameters ===
Enter Git Repository URL: https://github.com/username/my-app.git
Enter Personal Access Token (PAT): **********************
Enter branch name [default: main]: main
Enter remote server username: ubuntu
Enter remote server IP: 54.123.45.67
Enter SSH key path [default: ~/.ssh/id_rsa]: ~/.ssh/my-key.pem
Enter application port (container internal port): 3000

[SUCCESS] Parameters collected successfully
[INFO] Repository: https://github.com/username/my-app.git
[INFO] Branch: main
[INFO] Server: ubuntu@54.123.45.67
[INFO] Application Port: 3000
[INFO] Project Name: my-app

... (deployment continues) ...

[SUCCESS] ==========================================
[SUCCESS] DEPLOYMENT COMPLETED SUCCESSFULLY!
[SUCCESS] ==========================================
[SUCCESS] Access your application at: http://54.123.45.67
[SUCCESS] Logs saved to: logs/deploy_20251022_143025.log
```

## What the Script Does

### Stage 1: Parameter Collection

- Validates all user inputs
- Checks SSH key file exists
- Verifies URL and IP formats

### Stage 2: Repository Cloning

- Authenticates using Personal Access Token
- Clones or pulls latest changes
- Switches to specified branch

### Stage 3: Docker Verification

- Checks for Dockerfile or docker-compose.yml
- Determines deployment method

### Stage 4: SSH Connection Test

- Verifies remote server connectivity
- Tests SSH key authentication

### Stage 5: Remote Environment Setup

- Updates system packages
- Installs Docker and Docker Compose
- Installs and configures Nginx
- Enables and starts all services

### Stage 6: File Transfer

- Uses rsync for efficient file transfer
- Excludes unnecessary files (.git, node_modules, logs)
- Creates remote project directory

### Stage 7: Application Deployment

- Stops existing containers (idempotent)
- Builds Docker image
- Runs container with proper configuration
- Validates container health

### Stage 8: Nginx Configuration

- Creates reverse proxy configuration
- Forwards port 80 to application port
- Tests configuration before applying
- Reloads Nginx gracefully

### Stage 9: Validation

- Tests local access on remote server
- Tests external access from local machine
- Displays container status
- Verifies Nginx status

## Directory Structure

```
hng-stage1-devops/
├── deploy.sh           # Main deployment script
├── README.md           # This file
└── logs/               # Generated log files
    └── deploy_YYYYMMDD_HHMMSS.log
```

## Logging

All script actions are logged to timestamped files in the `logs/` directory:

```bash
logs/deploy_20251022_143025.log
```

Log format:

```
[2025-10-22 14:30:25] [INFO] Starting deployment...
[2025-10-22 14:30:26] [SUCCESS] Parameters collected successfully
[2025-10-22 14:30:30] [ERROR] Failed to connect to server
```

## Error Handling

The script includes comprehensive error handling:

- **Input Validation Errors** - Invalid URLs, IPs, ports, or file paths
- **SSH Connection Errors** - Unable to connect to remote server
- **Git Clone Errors** - Authentication failures or network issues
- **Docker Errors** - Container build or runtime failures
- **Nginx Errors** - Configuration syntax errors

All errors are logged with timestamps and exit codes.

## Idempotency

The script is designed to be idempotent - you can run it multiple times safely:

- Existing containers are stopped and removed before new deployment
- Git repositories are updated (not re-cloned)
- Nginx configurations are overwritten (not duplicated)
- Services are restarted gracefully

## Troubleshooting

### "SSH connection failed"

- Verify SSH key path is correct
- Check SSH key permissions: `chmod 400 ~/.ssh/your-key.pem`
- Ensure security group allows SSH (port 22)

### "Container failed to start"

- Check application Dockerfile for errors
- Verify application port is correct
- Review Docker logs: `docker logs <container-name>`

### "Cannot access application externally"

- Ensure security group allows HTTP (port 80)
- Check firewall rules: `sudo ufw status`
- Verify Nginx is running: `sudo systemctl status nginx`

### "File not found: Dockerfile"

- Ensure your repository has Dockerfile or docker-compose.yml
- Check you're in the correct branch

## Security Considerations

- Personal Access Token is hidden during input
- PAT is not stored or logged
- SSH key-based authentication only
- Minimal required permissions
- Regular security updates via `apt-get update`

## Testing the Script

### Test with a Sample Application

You can test with this simple Node.js app:

1. Create a test repository with:

**Dockerfile:**

```dockerfile
FROM node:18-alpine
WORKDIR /app
RUN echo 'const http = require("http"); http.createServer((req, res) => { res.writeHead(200); res.end("Hello from HNG Stage 1!"); }).listen(3000);' > server.js
CMD ["node", "server.js"]
EXPOSE 3000
```

2. Push to GitHub
3. Run the deployment script
4. Access `http://your-server-ip` in browser

## AWS/GCP Setup for Testing

### AWS EC2 Setup

1. Launch Ubuntu 22.04 t2.micro instance
2. Create security group:
   - Port 22 (SSH) - Your IP
   - Port 80 (HTTP) - 0.0.0.0/0
3. Download SSH key (.pem file)
4. Use EC2 public IP in script

### GCP Compute Engine Setup

1. Create Ubuntu 22.04 instance (e2-micro)
2. Add firewall rules:
   - `tcp:22` (SSH)
   - `tcp:80` (HTTP)
3. Use browser SSH or generate SSH key
4. Use GCP external IP in script

## Performance Optimization

The script includes several optimizations:

- **rsync** for efficient file transfer (only changed files)
- **Parallel operations** where possible
- **Minimal package installation** (only required packages)
- **Docker layer caching** for faster rebuilds
- **Silent apt-get** operations for cleaner output

## Contributing

This is a learning project for HNG internship. Feel free to:

- Report bugs
- Suggest improvements
- Fork and customize for your needs

## License

MIT License - Free to use and modify

## Resources

- [Docker Documentation](https://docs.docker.com/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [HNG Internship](https://hng.tech/)

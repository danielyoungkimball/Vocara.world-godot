# 🎮 Vocara.world - Development Guide

## 🚀 Quick Start

### Prerequisites
- **Backend**: Node.js server running
- **Frontend**: Godot 4.4+ project
- **Production**: Digital Ocean droplet with Docker

## 🔄 Environment Switching

### Development Environment (Local Testing)
```bash
# Switch Godot to local backend
cd godot_project
./scripts/build-dev.sh

# Start backend server
cd ../backend  
npm start

# Now run your Godot project - it will connect to localhost:8080
```

### Production Environment (Live Server)
```bash  
# Switch Godot to production backend
cd godot_project
./scripts/build-prod.sh

# Export web build using "Web (Production)" preset
# Deploy to production server
```

### Manual Environment Configuration
```bash
# Generate specific environment config
cd godot_project
godot --headless --script build-env.gd -- development
godot --headless --script build-env.gd -- production
godot --headless --script build-env.gd -- staging
```

## 🌐 Environment URLs

| Environment | Server URL | WebSocket | Assets | R2 CDN |
|-------------|------------|-----------|---------|--------|
| **Development** | `http://localhost:8080` | `ws://localhost:8080` | `http://localhost:8080/api/assets` | `https://assets.vocara-multiplayer.com` |
| **Staging** | `http://vocara-multiplayer.com` | `ws://vocara-multiplayer.com` | `http://vocara-multiplayer.com/api/assets` | `https://assets.vocara-multiplayer.com` |
| **Production** | `http://vocara-multiplayer.com` | `ws://vocara-multiplayer.com` | `http://vocara-multiplayer.com/api/assets` | `https://assets.vocara-multiplayer.com` |

## 🔧 Development Workflow

### 1. Local Development & Testing
```bash
# Backend setup
cd backend
npm install
cp .env.example .env  # Configure your environment variables
npm start

# Godot setup  
cd ../godot_project
./scripts/build-dev.sh
# Open Godot and run main.tscn
```

### 2. Making Code Changes

#### Backend Changes
```bash
cd backend
# Make your changes...
git add .
git commit -m "Your changes"
git push origin main

# Deploy to production
ssh root@138.197.46.130
cd ~/vocara-backend
git pull origin main
./deployment/deploy.sh production
```

#### Godot Changes
```bash
cd godot_project  
# Make your changes...

# Test locally
./scripts/build-dev.sh
# Run in Godot editor

# Deploy to production
./scripts/build-prod.sh
# Export using "Web (Production)" preset
# Upload to web server
```

### 3. Asset Management
- **Small assets**: Bundle with Godot project
- **Large assets** (>10MB): Upload to R2 CDN
- **Development**: Assets served from `localhost:8080/api/assets`
- **Production**: Assets served from `vocara-multiplayer.com/api/assets` (redirects to R2)

## 📡 Server Management

### Backend Server Commands
```bash
# SSH to production server
ssh root@138.197.46.130

# Deploy/restart server
cd ~/vocara-backend
./deployment/deploy.sh production

# Watch live logs
docker logs vocara-server -f

# Check server status
docker ps
curl http://vocara-multiplayer.com:8080/health

# Restart just the game server
docker-compose -f deployment/docker-compose.yml restart vocara-server
```

### Environment Variables
```bash
# Backend .env file
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_key  
R2_ACCOUNT_ID=your_r2_account_id
R2_ACCESS_KEY_ID=your_r2_access_key
R2_SECRET_ACCESS_KEY=your_r2_secret_key
R2_BUCKET_NAME=vocara-assets
R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
```

## 🧪 Testing

### Health Checks
```bash
# Backend health  
curl http://localhost:8080/health                    # Local
curl http://vocara-multiplayer.com:8080/health      # Production

# Asset serving
curl -I http://localhost:8080/api/assets/manifest.json        # Local
curl -I http://vocara-multiplayer.com/api/assets/manifest.json # Production

# R2 CDN direct
curl -I https://assets.vocara-multiplayer.com/manifest.json
```

### Godot Testing
1. **Environment Check**: Look for logs showing correct server URL
2. **Asset Loading**: Watch console for `[AssetStreamer]` messages  
3. **Multiplayer**: Test WebSocket connections
4. **Fallbacks**: Verify assets load when server is down

## 📦 Deployment

### Backend Deployment
```bash
# 1. Commit and push changes
git add .
git commit -m "Deploy changes"
git push origin main

# 2. Deploy to production
ssh root@138.197.46.130
cd ~/vocara-backend
git pull origin main
./deployment/deploy.sh production
# Choose 'N' for SSL if you don't need HTTPS
```

### Frontend Deployment  
```bash  
# 1. Switch to production environment
cd godot_project
./scripts/build-prod.sh

# 2. Export web build
# - Open Godot project
# - Project > Export
# - Select "Web (Production)" preset
# - Export to ../web/public/play/

# 3. Deploy web files
# Upload ../web/public/ contents to your web server
```

### Full Stack Deployment
```bash
# Complete deployment script
cd backend
git pull origin main
git push origin main
ssh root@138.197.46.130 "cd ~/vocara-backend && git pull origin main && ./deployment/deploy.sh production"

cd ../godot_project
./scripts/build-prod.sh
# Export in Godot, then upload web files
```

## 🛠️ Troubleshooting

### Common Issues

#### "AssetStreamer not found"
```bash
# Check environment config exists
ls godot_project/src/config/environment.gd

# Regenerate config
cd godot_project
./scripts/build-dev.sh
```

#### Connection Refused / Server Not Responding  
```bash
# Check backend is running
curl http://localhost:8080/health      # Local
curl http://vocara-multiplayer.com:8080/health  # Production

# Check backend logs
cd backend
npm start  # Look for startup messages

# Check production server
ssh root@138.197.46.130
docker logs vocara-server -f
```

#### Assets Not Loading
```bash
# Check asset manifest
curl http://localhost:8080/api/assets/manifest.json

# Check R2 CDN directly  
curl https://assets.vocara-multiplayer.com/manifest.json

# Clear Godot asset cache
# Delete ~/.local/share/godot/app_userdata/vocara.world/asset_cache/
```

#### Environment Config Issues
```bash
# Check which environment is active
cd godot_project
cat src/config/environment.gd

# Force regenerate
rm src/config/environment.gd
./scripts/build-dev.sh  # or build-prod.sh
```

### Debug Commands
```bash
# Backend debugging
cd backend
DEBUG=* npm start  # Verbose logging

# Production server debugging  
ssh root@138.197.46.130
docker logs vocara-server -f --timestamps
docker logs vocara-nginx -f

# Godot debugging
# Enable debug prints in GlobalAssetManager.gd:
# @export var debug_scene_tree: bool = true
```

## 🎯 Best Practices

### Development
1. **Always test locally** before deploying to production
2. **Use environment switching** instead of manual URL changes
3. **Watch logs** during development for early error detection
4. **Test asset loading** with empty cache regularly

### Deployment
1. **Commit changes** before deploying
2. **Test health endpoints** after deployment
3. **Monitor server logs** during deployment
4. **Keep backups** of working configurations

### Asset Management
1. **Small assets** (<10MB): Bundle with Godot
2. **Large assets** (>10MB): Upload to R2 CDN
3. **Test asset fallbacks** when server is unavailable
4. **Optimize assets** before uploading to reduce bandwidth

## 📚 File Structure Reference

```
Vocara.world/
├── backend/                   # Node.js multiplayer server
│   ├── src/server.js         # Main server entry
│   ├── .env                  # Environment config
│   ├── deployment/           # Docker deployment
│   └── SERVER-GUIDE.md       # Server management guide
├── godot_project/            # Godot 4 game client
│   ├── deployment.config.gd  # Environment configurations
│   ├── build-env.gd          # Environment builder script
│   ├── scripts/              # Build scripts
│   ├── src/config/           # Generated environment config
│   └── src/assets/           # Asset streaming system
└── web/                      # Web deployment
    └── public/play/          # Godot web build output
```

## 🔗 Quick Links

- **Backend Server Guide**: [backend/SERVER-GUIDE.md](backend/SERVER-GUIDE.md)
- **Asset Streaming Guide**: [godot_project/docs/ASSET_STREAMING_GUIDE.md](godot_project/docs/ASSET_STREAMING_GUIDE.md)
- **Production Server**: http://vocara-multiplayer.com:8080/health
- **R2 CDN**: https://assets.vocara-multiplayer.com
- **GitHub Repository**: https://github.com/danielyoungkimball/Vocara.world-backend

---

**💡 Pro Tip**: Bookmark this guide and the SERVER-GUIDE.md for complete development workflow reference! 
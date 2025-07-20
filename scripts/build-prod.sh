#!/bin/bash
# Build Production Environment
echo "🎮 Vocara.world - Building PRODUCTION environment"
echo "================================================="

# Navigate to godot project directory
cd "$(dirname "$0")/.."

# Generate production config
echo "🔧 Generating production environment config..."
godot --headless --script build-env.gd -- production

echo ""
echo "✅ Production environment ready!"
echo "🌐 Server: http://vocara-multiplayer.com"
echo "🎮 Multiplayer: ws://vocara-multiplayer.com"  
echo "📦 Assets: http://vocara-multiplayer.com/api/assets"
echo "☁️  R2 CDN: https://assets.vocara-multiplayer.com"
echo ""
echo "🚀 Next steps:"
echo "   1. Export using 'Web (Production)' preset"
echo "   2. Deploy to production server"
echo "" 
#!/bin/bash
# Build Development Environment
echo "🎮 Vocara.world - Building DEVELOPMENT environment"
echo "=================================================="

# Navigate to godot project directory
cd "$(dirname "$0")/.."

# Generate development config
echo "🔧 Generating development environment config..."
godot --headless --script build-env.gd -- development

echo ""
echo "✅ Development environment ready!"
echo "🌐 Server: http://localhost:8080"
echo "🎮 Multiplayer: ws://localhost:8080"  
echo "📦 Assets: http://localhost:8080/api/assets"
echo ""
echo "🚀 Next steps:"
echo "   1. Start backend server: cd ../backend && npm start"
echo "   2. Run Godot project for testing"
echo "" 
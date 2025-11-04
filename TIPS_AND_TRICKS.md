# 🌊 Wave Tips & Tricks

Advanced workflows and patterns for getting the most out of Wave.

## Table of Contents

- [Hook Examples](#hook-examples)
- [Traefik as a Front Controller](#traefik-as-a-front-controller)
- [Development Server Management](#development-server-management)
- [Database Per Worktree](#database-per-worktree)
- [Environment Variables](#environment-variables)
- [IDE Integration](#ide-integration)
- [Workflow Patterns](#workflow-patterns)

## Hook Examples

Wave provides five hooks for automation. Here are practical examples:

### Auto-fetch Before Creating Worktrees

`.wave/up.sh` - Always work from the latest remote code:

```bash
#!/bin/sh
echo "🌊 Fetching latest from origin..."
git fetch --all --prune
echo "✅ Ready to create worktree"
```

### Check for Uncommitted Changes Before Removing

`.wave/down.sh` - Prevent accidental data loss:

```bash
#!/bin/sh
echo "🌊 Checking for uncommitted work..."

# This runs before the specific worktree is identified
# You could add global checks here
```

### Display Running Processes in Status

`.wave/status.sh` - Show what's actually running:

```bash
#!/bin/sh
echo "🌊 Active development servers:"

# Check for running npm/node processes
ps aux | grep -E "node|npm" | grep -v grep | while read line; do
  echo "  • $line"
done

echo ""
```

### Auto-install Dependencies

`.wave/setup.sh` - Set up each worktree automatically:

```bash
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

echo "📦 Installing dependencies for $BRANCH_NAME..."
npm install

echo "⚙️  Copying environment..."
cp .env.example .env

echo "🗄️  Setting up database..."
php artisan migrate --seed

echo "✅ $BRANCH_NAME is ready!"
```

### Clean Up Docker Containers

`.wave/cleanup.sh` - Stop services before removing:

```bash
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

echo "🐳 Stopping Docker containers for $BRANCH_NAME..."
docker-compose down -v

echo "🗑️  Removing node_modules..."
rm -rf node_modules

echo "✅ Cleanup complete"
```

### Combined Status Hook with Health Checks

`.wave/status.sh` - Comprehensive status overview:

```bash
#!/bin/sh

echo "🌊 Wave Environment Health Check"
echo "================================"

# Check disk space
echo ""
echo "💾 Disk Space:"
df -h . | tail -1 | awk '{print "  Available: " $4 " (" $5 " used)"}'

# Check for running dev servers
echo ""
echo "🚀 Running Servers:"
lsof -i :3000-3010 2>/dev/null | grep LISTEN | awk '{print "  Port " $9 " - " $1}' || echo "  None detected"

# Check for uncommitted changes in worktrees
echo ""
echo "📝 Uncommitted Changes:"
for path in ../$(basename $(pwd))-wave/*; do
  if [ -d "$path" ]; then
    branch=$(basename "$path")
    cd "$path"
    if ! git diff-index --quiet HEAD 2>/dev/null; then
      echo "  ⚠️  $branch has uncommitted changes"
    fi
    cd - > /dev/null
  fi
done

echo ""
```

## Traefik as a Front Controller

One of the most powerful patterns with Wave is using Traefik to route different hostnames to different worktrees. This lets you access each branch via a unique URL.

### Setup

**1. Install Traefik (Docker)**

Create a `docker-compose.traefik.yml` in your project root:

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"  # Traefik dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - wave-network

networks:
  wave-network:
    external: true
```

Start Traefik:

```bash
docker network create wave-network
docker-compose -f docker-compose.traefik.yml up -d
```

**2. Configure Your Worktree Services**

In each worktree's `docker-compose.yml`, add Traefik labels:

```yaml
version: '3.8'

services:
  app:
    image: your-app:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${BRANCH_NAME}.rule=Host(`${BRANCH_NAME}.localhost`)"
      - "traefik.http.services.${BRANCH_NAME}.loadbalancer.server.port=3000"
    networks:
      - wave-network
    environment:
      - BRANCH_NAME=${BRANCH_NAME}

networks:
  wave-network:
    external: true
```

**3. Automate with Wave Hooks**

Update `.wave/setup.sh`:

```bash
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

# Set branch name for Traefik
export BRANCH_NAME="$BRANCH_NAME"
echo "BRANCH_NAME=$BRANCH_NAME" > .env.local

# Start services
docker-compose up -d

echo "✅ $BRANCH_NAME available at http://${BRANCH_NAME}.localhost"
```

Update `.wave/cleanup.sh`:

```bash
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

# Stop services
docker-compose down

echo "🧹 Cleaned up $BRANCH_NAME"
```

**4. Access Your Worktrees**

```bash
wave create feature-login
# → http://feature-login.localhost

wave create bugfix-123
# → http://bugfix-123.localhost

wave create main
# → http://main.localhost
```

### Benefits

- **Unique URLs**: Each branch gets its own hostname
- **No Port Conflicts**: All services run on port 80 via Traefik
- **Easy Testing**: Share URLs with teammates or test on mobile devices
- **Production-like**: Mimics multi-tenant or subdomain routing

## Development Server Management

### Running Multiple Dev Servers

Use different ports for each worktree:

```bash
# .wave/setup.sh
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

# Generate a unique port based on branch name
PORT=$((3000 + $(echo "$BRANCH_NAME" | cksum | cut -d' ' -f1) % 1000))

echo "PORT=$PORT" >> .env.local
npm install
npm run dev -- --port "$PORT" &

echo "✅ $BRANCH_NAME running on http://localhost:$PORT"
```

### Process Management with PM2

```bash
# .wave/setup.sh
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"
npm install
pm2 start npm --name "$BRANCH_NAME" -- run dev
pm2 save

echo "✅ $BRANCH_NAME started with PM2"
```

```bash
# .wave/cleanup.sh
#!/bin/sh
BRANCH_NAME="$2"

pm2 delete "$BRANCH_NAME"
pm2 save

echo "🧹 Stopped PM2 process for $BRANCH_NAME"
```

## Database Per Worktree

### SQLite (Simplest)

Each worktree gets its own database file automatically:

```bash
# .wave/setup.sh
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"
cp database.example.sqlite "database.$BRANCH_NAME.sqlite"
echo "DB_PATH=database.$BRANCH_NAME.sqlite" >> .env.local
```

### PostgreSQL with Docker

```bash
# .wave/setup.sh
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

# Start a dedicated PostgreSQL container
docker run -d \
  --name "db-$BRANCH_NAME" \
  -e POSTGRES_DB="$BRANCH_NAME" \
  -e POSTGRES_PASSWORD=secret \
  -p "$((5432 + $(echo "$BRANCH_NAME" | cksum | cut -d' ' -f1) % 1000)):5432" \
  postgres:15

echo "✅ Database for $BRANCH_NAME created"
```

## Environment Variables

### Branch-Specific Configuration

```bash
# .wave/setup.sh
#!/bin/sh
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"

# Copy base environment
cp .env.example .env

# Add branch-specific overrides
cat >> .env <<EOF
APP_NAME="MyApp - $BRANCH_NAME"
APP_URL="http://${BRANCH_NAME}.localhost"
DB_DATABASE="$BRANCH_NAME"
CACHE_PREFIX="${BRANCH_NAME}_"
EOF
```

## IDE Integration

### VS Code

Open multiple worktrees in separate windows:

```bash
wave exec feature-login code .
wave exec bugfix-123 code .
```

Or create a workspace file:

```bash
# Generate a VS Code workspace
cat > wave-workspace.code-workspace <<EOF
{
  "folders": [
    { "path": "." },
    { "path": "../$(basename $(pwd))-wave/feature-login" },
    { "path": "../$(basename $(pwd))-wave/bugfix-123" }
  ]
}
EOF
```

### PhpStorm / IntelliJ

Each worktree can have its own `.idea` directory with separate configurations.

## Workflow Patterns

### The Review Pattern

```bash
# Someone asks you to review their PR
wave create review/pr-456
wave exec review/pr-456 npm install
wave exec review/pr-456 npm run dev

# Review in browser, then clean up
wave remove review/pr-456
```

### The Hotfix Pattern

```bash
# Production is down, need a quick fix
wave create hotfix/critical-bug
wave exec hotfix/critical-bug npm run test
# Fix, commit, push
wave remove hotfix/critical-bug
```

### The Experiment Pattern

```bash
# Try something risky without affecting your main work
wave create experiment/new-architecture
# Experiment freely
# Keep it or throw it away
wave remove experiment/new-architecture
```

### The Comparison Pattern

```bash
# Compare two implementations side by side
wave create approach-a
wave create approach-b

# Run both
wave exec approach-a npm run dev -- --port 3001
wave exec approach-b npm run dev -- --port 3002

# Compare at http://localhost:3001 vs http://localhost:3002
```

## Advanced Tips

### Shared Cache Directory

Save time on dependencies:

```bash
# .wave/setup.sh
#!/bin/sh
WORKTREE_PATH="$1"

cd "$WORKTREE_PATH"

# Use a shared node_modules cache
mkdir -p ~/.wave-cache/node_modules
ln -s ~/.wave-cache/node_modules node_modules
npm install
```

### Git Aliases

Add to your `~/.gitconfig`:

```ini
[alias]
  w = !wave
  wc = !wave create
  wr = !wave remove
  wls = !wave ls
```

Now use: `git wc feature-x`

### Cleanup All Worktrees

```bash
# Remove all wave worktrees
for branch in $(wave ls | grep wave | awk '{print $NF}' | xargs basename); do
  wave remove "$branch"
done
```

---

Have a tip to share? Open a PR and add it here! 🌊


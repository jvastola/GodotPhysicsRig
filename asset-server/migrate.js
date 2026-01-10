/**
 * Database migration script for asset library.
 * Run with: node migrate.js
 */
const db = require('./db');

async function migrate() {
  console.log('Running asset library migrations...\n');

  try {
    // Create assets table
    await db.query(`
      CREATE TABLE IF NOT EXISTS assets (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL,
        username VARCHAR(255),
        
        -- Asset Info
        name VARCHAR(255) NOT NULL,
        description TEXT,
        category VARCHAR(50) NOT NULL,
        tags TEXT[],
        version INT DEFAULT 1,
        
        -- Storage
        storage_provider VARCHAR(32) DEFAULT 'local',
        file_key VARCHAR(500) NOT NULL,
        thumbnail_key VARCHAR(500),
        file_size BIGINT,
        
        -- Visibility
        visibility VARCHAR(16) DEFAULT 'public',
        
        -- Stats
        downloads INT DEFAULT 0,
        likes INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    console.log('✓ Created assets table');

    // Create likes table
    await db.query(`
      CREATE TABLE IF NOT EXISTS asset_likes (
        user_id UUID NOT NULL,
        asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT NOW(),
        PRIMARY KEY (user_id, asset_id)
      );
    `);
    console.log('✓ Created asset_likes table');

    // Create indexes
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_assets_category ON assets(category);
    `);
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_assets_user ON assets(user_id);
    `);
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_assets_visibility ON assets(visibility, created_at DESC);
    `);
    console.log('✓ Created indexes');

    console.log('\n✓ Migration complete!');
  } catch (error) {
    console.error('Migration error:', error.message);
    process.exit(1);
  }

  process.exit(0);
}

migrate();

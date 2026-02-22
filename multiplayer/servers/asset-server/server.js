const express = require('express');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const db = require('./db');
const { requireAuth, optionalAuth } = require('./auth');
const { createStorage } = require('./storage');

const app = express();
const PORT = process.env.PORT || 3001;
const storage = createStorage();

// Middleware
app.use(cors());
app.use(express.json());

// File upload config
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB
  fileFilter: (req, file, cb) => {
    const allowedMimes = [
      'model/gltf-binary',
      'model/gltf+json',
      'application/octet-stream', // .glb often comes as this
      'image/png',
      'image/jpeg'
    ];
    const ext = path.extname(file.originalname).toLowerCase();
    const allowedExts = ['.glb', '.gltf', '.png', '.jpg', '.jpeg'];
    
    if (allowedExts.includes(ext) || allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`Invalid file type: ${file.mimetype}`));
    }
  }
});

// Serve static files
app.use('/files', express.static(process.env.UPLOAD_DIR || './uploads'));

// ============================================================
// ROUTES
// ============================================================

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// List categories
app.get('/categories', (req, res) => {
  res.json([
    { id: 'scene', name: 'Scenes', icon: '🌍' },
    { id: 'avatar', name: 'Avatars', icon: '👤' },
    { id: 'model', name: 'Models', icon: '📦' }
  ]);
});

// Browse assets
app.get('/assets', optionalAuth, async (req, res) => {
  try {
    const {
      category,
      tags,
      search,
      sort = 'created_at',
      order = 'desc',
      page = 1,
      limit = 20
    } = req.query;

    // Validate sort field
    const allowedSorts = ['created_at', 'downloads', 'likes', 'name'];
    const sortField = allowedSorts.includes(sort) ? sort : 'created_at';
    const sortOrder = order === 'asc' ? 'ASC' : 'DESC';
    
    // Build query
    let whereClause = "visibility = 'public'";
    const params = [];
    let paramIndex = 1;

    if (category) {
      whereClause += ` AND category = $${paramIndex++}`;
      params.push(category);
    }

    if (search) {
      whereClause += ` AND (name ILIKE $${paramIndex} OR description ILIKE $${paramIndex})`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    if (tags) {
      const tagArray = tags.split(',').map(t => t.trim());
      whereClause += ` AND tags && $${paramIndex++}`;
      params.push(tagArray);
    }

    // Pagination
    const limitNum = Math.min(Math.max(1, parseInt(limit) || 20), 50);
    const pageNum = Math.max(1, parseInt(page) || 1);
    const offset = (pageNum - 1) * limitNum;

    // Get total count
    const countResult = await db.query(
      `SELECT COUNT(*) FROM assets WHERE ${whereClause}`,
      params
    );
    const total = parseInt(countResult.rows[0].count);

    // Get assets
    const result = await db.query(
      `SELECT id, user_id, username, name, description, category, tags,
              storage_provider, file_key, thumbnail_key, file_size,
              downloads, likes, version, created_at, updated_at
       FROM assets
       WHERE ${whereClause}
       ORDER BY ${sortField} ${sortOrder}
       LIMIT $${paramIndex++} OFFSET $${paramIndex}`,
      [...params, limitNum, offset]
    );

    // Transform results
    const assets = result.rows.map(row => ({
      id: row.id,
      name: row.name,
      description: row.description,
      category: row.category,
      tags: row.tags || [],
      username: row.username,
      user_id: row.user_id,
      thumbnail_url: row.thumbnail_key ? storage.getUrl(row.thumbnail_key) : null,
      file_size: row.file_size,
      downloads: row.downloads,
      likes: row.likes,
      version: row.version,
      created_at: row.created_at,
      updated_at: row.updated_at
    }));

    res.json({
      assets,
      total,
      page: pageNum,
      pages: Math.ceil(total / limitNum),
      limit: limitNum
    });
  } catch (error) {
    console.error('Browse error:', error);
    res.status(500).json({ error: 'Failed to fetch assets' });
  }
});

// Get single asset
app.get('/assets/:id', optionalAuth, async (req, res) => {
  try {
    const result = await db.query(
      `SELECT * FROM assets WHERE id = $1`,
      [req.params.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Asset not found' });
    }

    const row = result.rows[0];
    
    // Check visibility
    if (row.visibility !== 'public' && (!req.user || req.user.user_id !== row.user_id)) {
      return res.status(404).json({ error: 'Asset not found' });
    }

    res.json({
      id: row.id,
      name: row.name,
      description: row.description,
      category: row.category,
      tags: row.tags || [],
      username: row.username,
      user_id: row.user_id,
      file_url: storage.getUrl(row.file_key),
      thumbnail_url: row.thumbnail_key ? storage.getUrl(row.thumbnail_key) : null,
      file_size: row.file_size,
      downloads: row.downloads,
      likes: row.likes,
      version: row.version,
      visibility: row.visibility,
      created_at: row.created_at,
      updated_at: row.updated_at
    });
  } catch (error) {
    console.error('Get asset error:', error);
    res.status(500).json({ error: 'Failed to fetch asset' });
  }
});

// Download asset (increments counter)
app.get('/assets/:id/download', async (req, res) => {
  try {
    // Atomically increment download counter
    const result = await db.query(
      `UPDATE assets SET downloads = downloads + 1
       WHERE id = $1 AND visibility = 'public'
       RETURNING file_key, name, storage_provider`,
      [req.params.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Asset not found' });
    }

    const { file_key, name } = result.rows[0];
    const filePath = storage.getFilePath(file_key);
    
    res.download(filePath, `${name}.glb`);
  } catch (error) {
    console.error('Download error:', error);
    res.status(500).json({ error: 'Download failed' });
  }
});

// Upload asset
app.post('/assets', requireAuth, upload.fields([
  { name: 'file', maxCount: 1 },
  { name: 'thumbnail', maxCount: 1 }
]), async (req, res) => {
  try {
    const { name, description, category, tags, visibility } = req.body;

    // Validation
    if (!name || !category) {
      return res.status(400).json({ error: 'Name and category required' });
    }

    const allowedCategories = ['scene', 'avatar', 'model'];
    if (!allowedCategories.includes(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }

    if (!req.files || !req.files.file) {
      return res.status(400).json({ error: 'File required' });
    }

    const file = req.files.file[0];
    const thumbnail = req.files.thumbnail ? req.files.thumbnail[0] : null;

    // Generate storage keys
    const fileId = uuidv4();
    const ext = path.extname(file.originalname).toLowerCase() || '.glb';
    const fileKey = `${category}s/${fileId}${ext}`;
    
    let thumbnailKey = null;
    if (thumbnail) {
      const thumbExt = path.extname(thumbnail.originalname).toLowerCase() || '.png';
      thumbnailKey = `thumbnails/${fileId}${thumbExt}`;
    }

    // Save files
    await storage.save(fileKey, file.buffer);
    if (thumbnail) {
      await storage.save(thumbnailKey, thumbnail.buffer);
    }

    // Parse tags
    let tagArray = [];
    if (tags) {
      tagArray = typeof tags === 'string' 
        ? tags.split(',').map(t => t.trim()).filter(t => t)
        : tags;
    }

    // Insert into database
    const result = await db.query(
      `INSERT INTO assets (
        user_id, username, name, description, category, tags,
        storage_provider, file_key, thumbnail_key, file_size, visibility
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING id, created_at`,
      [
        req.user.user_id,
        req.user.username,
        name,
        description || null,
        category,
        tagArray,
        'local',
        fileKey,
        thumbnailKey,
        file.size,
        visibility === 'private' ? 'private' : 'public'
      ]
    );

    const asset = result.rows[0];
    
    console.log(`Asset uploaded: ${name} by ${req.user.username}`);

    res.status(201).json({
      success: true,
      id: asset.id,
      name,
      category,
      file_url: storage.getUrl(fileKey),
      thumbnail_url: thumbnailKey ? storage.getUrl(thumbnailKey) : null,
      created_at: asset.created_at
    });
  } catch (error) {
    console.error('Upload error:', error);
    res.status(500).json({ error: 'Upload failed' });
  }
});

// Update asset
app.put('/assets/:id', requireAuth, upload.fields([
  { name: 'file', maxCount: 1 },
  { name: 'thumbnail', maxCount: 1 }
]), async (req, res) => {
  try {
    // Check ownership
    const existing = await db.query(
      `SELECT * FROM assets WHERE id = $1`,
      [req.params.id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'Asset not found' });
    }

    if (existing.rows[0].user_id !== req.user.user_id) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    const current = existing.rows[0];
    const { name, description, tags, visibility } = req.body;

    let fileKey = current.file_key;
    let thumbnailKey = current.thumbnail_key;
    let fileSize = current.file_size;
    let newVersion = current.version;

    // Handle file replacement
    if (req.files && req.files.file) {
      const file = req.files.file[0];
      const fileId = uuidv4();
      const ext = path.extname(file.originalname).toLowerCase() || '.glb';
      fileKey = `${current.category}s/${fileId}${ext}`;
      fileSize = file.size;
      newVersion = current.version + 1;

      await storage.save(fileKey, file.buffer);
      // Optionally delete old file
      await storage.delete(current.file_key);
    }

    // Handle thumbnail replacement
    if (req.files && req.files.thumbnail) {
      const thumbnail = req.files.thumbnail[0];
      const fileId = uuidv4();
      const thumbExt = path.extname(thumbnail.originalname).toLowerCase() || '.png';
      thumbnailKey = `thumbnails/${fileId}${thumbExt}`;

      await storage.save(thumbnailKey, thumbnail.buffer);
      if (current.thumbnail_key) {
        await storage.delete(current.thumbnail_key);
      }
    }

    // Parse tags
    let tagArray = current.tags;
    if (tags !== undefined) {
      tagArray = typeof tags === 'string' 
        ? tags.split(',').map(t => t.trim()).filter(t => t)
        : tags;
    }

    // Update database
    await db.query(
      `UPDATE assets SET
        name = $1,
        description = $2,
        tags = $3,
        file_key = $4,
        thumbnail_key = $5,
        file_size = $6,
        version = $7,
        visibility = $8,
        updated_at = NOW()
       WHERE id = $9`,
      [
        name || current.name,
        description !== undefined ? description : current.description,
        tagArray,
        fileKey,
        thumbnailKey,
        fileSize,
        newVersion,
        visibility || current.visibility,
        req.params.id
      ]
    );

    res.json({ success: true, version: newVersion });
  } catch (error) {
    console.error('Update error:', error);
    res.status(500).json({ error: 'Update failed' });
  }
});

// Delete asset
app.delete('/assets/:id', requireAuth, async (req, res) => {
  try {
    // Check ownership
    const existing = await db.query(
      `SELECT user_id, file_key, thumbnail_key FROM assets WHERE id = $1`,
      [req.params.id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'Asset not found' });
    }

    if (existing.rows[0].user_id !== req.user.user_id) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    const { file_key, thumbnail_key } = existing.rows[0];

    // Delete from storage
    await storage.delete(file_key);
    if (thumbnail_key) {
      await storage.delete(thumbnail_key);
    }

    // Delete from database
    await db.query(`DELETE FROM assets WHERE id = $1`, [req.params.id]);

    res.json({ success: true });
  } catch (error) {
    console.error('Delete error:', error);
    res.status(500).json({ error: 'Delete failed' });
  }
});

// Like/unlike asset
app.post('/assets/:id/like', requireAuth, async (req, res) => {
  try {
    // Check if already liked
    const existing = await db.query(
      `SELECT 1 FROM asset_likes WHERE user_id = $1 AND asset_id = $2`,
      [req.user.user_id, req.params.id]
    );

    if (existing.rows.length > 0) {
      // Unlike
      await db.query(
        `DELETE FROM asset_likes WHERE user_id = $1 AND asset_id = $2`,
        [req.user.user_id, req.params.id]
      );
      await db.query(
        `UPDATE assets SET likes = likes - 1 WHERE id = $1`,
        [req.params.id]
      );
      res.json({ liked: false });
    } else {
      // Like
      await db.query(
        `INSERT INTO asset_likes (user_id, asset_id) VALUES ($1, $2)`,
        [req.user.user_id, req.params.id]
      );
      await db.query(
        `UPDATE assets SET likes = likes + 1 WHERE id = $1`,
        [req.params.id]
      );
      res.json({ liked: true });
    }
  } catch (error) {
    console.error('Like error:', error);
    res.status(500).json({ error: 'Like failed' });
  }
});

// Get user's assets
app.get('/users/:userId/assets', optionalAuth, async (req, res) => {
  try {
    const isOwner = req.user && req.user.user_id === req.params.userId;
    
    let whereClause = 'user_id = $1';
    if (!isOwner) {
      whereClause += " AND visibility = 'public'";
    }

    const result = await db.query(
      `SELECT id, name, category, thumbnail_key, downloads, likes, created_at
       FROM assets WHERE ${whereClause}
       ORDER BY created_at DESC`,
      [req.params.userId]
    );

    const assets = result.rows.map(row => ({
      id: row.id,
      name: row.name,
      category: row.category,
      thumbnail_url: row.thumbnail_key ? storage.getUrl(row.thumbnail_key) : null,
      downloads: row.downloads,
      likes: row.likes,
      created_at: row.created_at
    }));

    res.json({ assets });
  } catch (error) {
    console.error('User assets error:', error);
    res.status(500).json({ error: 'Failed to fetch user assets' });
  }
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({ error: err.message || 'Internal server error' });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔═══════════════════════════════════════════╗
║       Asset Library Server v1.0           ║
╠═══════════════════════════════════════════╣
║  Port:     ${PORT}                            ║
║  Upload:   POST /assets                   ║
║  Browse:   GET /assets                    ║
║  Download: GET /assets/:id/download       ║
╚═══════════════════════════════════════════╝
  `);
});

module.exports = app;

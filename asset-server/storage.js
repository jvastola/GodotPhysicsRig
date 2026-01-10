const fs = require('fs');
const path = require('path');

/**
 * Storage provider interface for abstracting file storage.
 * Start with local storage, migrate to S3 by implementing S3Storage.
 */
class StorageProvider {
  async save(key, buffer) { throw new Error('Not implemented'); }
  async get(key) { throw new Error('Not implemented'); }
  async delete(key) { throw new Error('Not implemented'); }
  getUrl(key) { throw new Error('Not implemented'); }
}

/**
 * Local filesystem storage provider.
 */
class LocalStorage extends StorageProvider {
  constructor(baseDir = './uploads') {
    super();
    this.baseDir = baseDir;
    
    // Ensure directories exist
    const dirs = ['models', 'scenes', 'avatars', 'thumbnails'];
    for (const dir of dirs) {
      const fullPath = path.join(baseDir, dir);
      if (!fs.existsSync(fullPath)) {
        fs.mkdirSync(fullPath, { recursive: true });
      }
    }
  }

  _getFullPath(key) {
    // Security: prevent directory traversal
    const sanitized = key.replace(/\.\./g, '').replace(/^\//, '');
    return path.join(this.baseDir, sanitized);
  }

  async save(key, buffer) {
    const fullPath = this._getFullPath(key);
    const dir = path.dirname(fullPath);
    
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    
    fs.writeFileSync(fullPath, buffer);
    return key;
  }

  async get(key) {
    const fullPath = this._getFullPath(key);
    if (!fs.existsSync(fullPath)) {
      return null;
    }
    return fs.readFileSync(fullPath);
  }

  async delete(key) {
    const fullPath = this._getFullPath(key);
    if (fs.existsSync(fullPath)) {
      fs.unlinkSync(fullPath);
      return true;
    }
    return false;
  }

  getUrl(key) {
    return `/files/${key}`;
  }

  getFilePath(key) {
    return this._getFullPath(key);
  }
}

/**
 * S3 storage provider (future implementation).
 * Uncomment and configure when ready to migrate.
 */
// class S3Storage extends StorageProvider {
//   constructor(bucket, region) {
//     super();
//     this.bucket = bucket;
//     this.region = region;
//     // Initialize AWS SDK client
//   }
//   
//   async save(key, buffer) { /* S3 putObject */ }
//   async get(key) { /* S3 getObject */ }
//   async delete(key) { /* S3 deleteObject */ }
//   getUrl(key) { return `https://${this.bucket}.s3.${this.region}.amazonaws.com/${key}`; }
// }

// Factory function
function createStorage() {
  const provider = process.env.STORAGE_PROVIDER || 'local';
  
  switch (provider) {
    case 's3':
      throw new Error('S3 storage not yet implemented');
    case 'local':
    default:
      return new LocalStorage(process.env.UPLOAD_DIR || './uploads');
  }
}

module.exports = { StorageProvider, LocalStorage, createStorage };

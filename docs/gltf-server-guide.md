# GLTF Server Setup Guide

This guide explains how to set up a server to host and serve GLTF files uploaded from the PolyTool.

## Quick Start Options

### Option 1: Node.js Express Server (Recommended)

```javascript
// server.js
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 3000;

// Enable CORS for Godot requests
app.use(cors());

// Create uploads directory
const uploadsDir = './uploads';
if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
}

// Configure multer for file uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, uploadsDir),
    filename: (req, file, cb) => {
        const timestamp = Date.now();
        const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
        cb(null, `${timestamp}_${safeName}`);
    }
});

const upload = multer({ 
    storage,
    limits: { fileSize: 50 * 1024 * 1024 }, // 50MB limit
    fileFilter: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase();
        if (ext === '.gltf' || ext === '.glb') {
            cb(null, true);
        } else {
            cb(new Error('Only .gltf and .glb files allowed'));
        }
    }
});

// Upload endpoint
app.post('/upload', upload.single('file'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    console.log(`Uploaded: ${req.file.filename}`);
    res.json({ 
        success: true, 
        filename: req.file.filename,
        url: `/files/${req.file.filename}`
    });
});

// List all files
app.get('/files', (req, res) => {
    const files = fs.readdirSync(uploadsDir)
        .filter(f => f.endsWith('.gltf') || f.endsWith('.glb'))
        .map(f => ({
            name: f,
            url: `/files/${f}`,
            size: fs.statSync(path.join(uploadsDir, f)).size
        }));
    res.json(files);
});

// Serve files with proper CORS headers
app.use('/files', express.static(uploadsDir, {
    setHeaders: (res) => {
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Content-Type', 'model/gltf+json');
    }
}));

// Delete file
app.delete('/files/:filename', (req, res) => {
    const filepath = path.join(uploadsDir, req.params.filename);
    if (fs.existsSync(filepath)) {
        fs.unlinkSync(filepath);
        res.json({ success: true });
    } else {
        res.status(404).json({ error: 'File not found' });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`GLTF Server running at http://localhost:${PORT}`);
    console.log(`Upload endpoint: POST http://localhost:${PORT}/upload`);
    console.log(`List files: GET http://localhost:${PORT}/files`);
});
```

**Setup:**
```bash
mkdir gltf-server && cd gltf-server
npm init -y
npm install express multer cors
node server.js
```

---

### Option 2: Python Flask Server

```python
# server.py
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from werkzeug.utils import secure_filename
import os
from datetime import datetime

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = './uploads'
ALLOWED_EXTENSIONS = {'gltf', 'glb'}
MAX_CONTENT_LENGTH = 50 * 1024 * 1024  # 50MB

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_CONTENT_LENGTH

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    
    if file and allowed_file(file.filename):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = secure_filename(f"{timestamp}_{file.filename}")
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file.save(filepath)
        print(f"Uploaded: {filename}")
        return jsonify({
            'success': True,
            'filename': filename,
            'url': f'/files/{filename}'
        })
    
    return jsonify({'error': 'Invalid file type'}), 400

@app.route('/files', methods=['GET'])
def list_files():
    files = []
    for f in os.listdir(UPLOAD_FOLDER):
        if f.endswith(('.gltf', '.glb')):
            filepath = os.path.join(UPLOAD_FOLDER, f)
            files.append({
                'name': f,
                'url': f'/files/{f}',
                'size': os.path.getsize(filepath)
            })
    return jsonify(sorted(files, key=lambda x: x['name']))

@app.route('/files/<filename>', methods=['GET'])
def get_file(filename):
    return send_from_directory(UPLOAD_FOLDER, filename)

@app.route('/files/<filename>', methods=['DELETE'])
def delete_file(filename):
    filepath = os.path.join(UPLOAD_FOLDER, secure_filename(filename))
    if os.path.exists(filepath):
        os.remove(filepath)
        return jsonify({'success': True})
    return jsonify({'error': 'File not found'}), 404

if __name__ == '__main__':
    print("GLTF Server running at http://localhost:3000")
    print("Upload endpoint: POST http://localhost:3000/upload")
    app.run(host='0.0.0.0', port=3000, debug=True)
```

**Setup:**
```bash
pip install flask flask-cors
python server.py
```

---

### Option 3: Docker Compose (Production Ready)

```yaml
# docker-compose.yml
version: '3.8'
services:
  gltf-server:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - ./uploads:/app/uploads
    restart: unless-stopped
```

```dockerfile
# Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY server.js .
RUN mkdir -p uploads
EXPOSE 3000
CMD ["node", "server.js"]
```

---

## API Reference

### Upload File
```
POST /upload
Content-Type: multipart/form-data

Form field: file (the GLTF/GLB file)

Response:
{
    "success": true,
    "filename": "1234567890_poly_2024-01-15.gltf",
    "url": "/files/1234567890_poly_2024-01-15.gltf"
}
```

### List Files
```
GET /files

Response:
[
    {
        "name": "1234567890_poly_2024-01-15.gltf",
        "url": "/files/1234567890_poly_2024-01-15.gltf",
        "size": 12345
    }
]
```

### Download File
```
GET /files/{filename}

Response: The GLTF/GLB file content
```

### Delete File
```
DELETE /files/{filename}

Response:
{ "success": true }
```

---

## Using with PolyTool

1. Start your server (locally or on a cloud provider)
2. In the PolyTool UI, enter your server URL in the upload field:
   - Local: `http://192.168.1.100:3000/upload` (use your computer's IP)
   - Cloud: `https://your-domain.com/upload`
3. Select a GLTF file and click "Upload"

**Note:** For Quest to reach a local server, both devices must be on the same network and you must use your computer's local IP address (not `localhost`).

---

## Cloud Deployment Options

### Render.com (Free Tier)
1. Push code to GitHub
2. Create new Web Service on Render
3. Connect your repo
4. Set build command: `npm install`
5. Set start command: `node server.js`

### Railway.app
1. Push code to GitHub
2. Create new project on Railway
3. Deploy from GitHub repo
4. Railway auto-detects Node.js

### DigitalOcean App Platform
1. Create new App
2. Connect GitHub repo
3. Configure as Web Service
4. Deploy

### AWS S3 + Lambda (Serverless)
For a serverless approach, use S3 for storage with Lambda for upload handling and presigned URLs.

---

## Security Considerations

For production use:
- Add authentication (API keys, JWT tokens)
- Rate limiting
- File size limits
- Virus scanning
- HTTPS only
- Input validation

Example with API key:
```javascript
// Add to server.js
const API_KEY = process.env.API_KEY || 'your-secret-key';

app.use('/upload', (req, res, next) => {
    const key = req.headers['x-api-key'];
    if (key !== API_KEY) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
});
```

Then in Godot, add the header:
```gdscript
var headers := [
    "Content-Type: multipart/form-data; boundary=%s" % boundary,
    "X-API-Key: your-secret-key"
]
```
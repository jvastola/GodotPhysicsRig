const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 8080;
const ROOM_EXPIRY_SECONDS = parseInt(process.env.ROOM_EXPIRY_SECONDS) || 3600; // 1 hour default

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// In-memory room storage
const rooms = new Map();
const serverStartTime = Date.now();

// Helper function to get current timestamp
function getCurrentTimestamp() {
  return Math.floor(Date.now() / 1000);
}

// Cleanup expired rooms periodically
function cleanupExpiredRooms() {
  const currentTime = getCurrentTimestamp();
  const expiredRooms = [];
  
  for (const [roomCode, roomData] of rooms.entries()) {
    if (currentTime - roomData.timestamp > ROOM_EXPIRY_SECONDS) {
      expiredRooms.push(roomCode);
    }
  }
  
  for (const roomCode of expiredRooms) {
    rooms.delete(roomCode);
  }
  
  if (expiredRooms.length > 0) {
    console.log(`Cleaned up ${expiredRooms.length} expired room(s):`, expiredRooms);
  }
}

// Run cleanup every 60 seconds
setInterval(cleanupExpiredRooms, 60000);

// Routes

// Health check endpoint
app.get('/health', (req, res) => {
  const uptime = Math.floor((Date.now() - serverStartTime) / 1000);
  res.json({
    status: 'ok',
    uptime: uptime,
    rooms: rooms.size,
    timestamp: getCurrentTimestamp()
  });
});

// Register a new room
app.post('/room', (req, res) => {
  const { room_code, ip, port, host_name, timestamp } = req.body;
  
  // Validate required fields
  if (!room_code || !ip || !port) {
    return res.status(400).json({
      error: 'Missing required fields: room_code, ip, port'
    });
  }
  
  // Store room data
  rooms.set(room_code, {
    ip,
    port: parseInt(port),  // Ensure it's an integer
    host_name: host_name || 'Host',
    player_count: 1,
    timestamp: timestamp || getCurrentTimestamp()
  });
  
  console.log(`Room registered: ${room_code} (${ip}:${port}) by ${host_name || 'Host'}`);
  
  res.json({
    success: true,
    room_code: room_code
  });
});

// Lookup a specific room
app.get('/room/:room_code', (req, res) => {
  const roomCode = req.params.room_code;
  
  if (!rooms.has(roomCode)) {
    return res.status(404).json({
      error: 'Room not found'
    });
  }
  
  const roomData = rooms.get(roomCode);
  console.log(`Room lookup: ${roomCode}`);
  
  res.json(roomData);
});

// List all active rooms
app.get('/rooms', (req, res) => {
  const roomList = [];
  
  for (const [roomCode, roomData] of rooms.entries()) {
    roomList.push({
      room_code: roomCode,
      ...roomData
    });
  }
  
  console.log(`Room list requested: ${roomList.length} active room(s)`);
  res.json(roomList);
});

// Unregister a room
app.delete('/room/:room_code', (req, res) => {
  const roomCode = req.params.room_code;
  
  if (!rooms.has(roomCode)) {
    return res.status(404).json({
      error: 'Room not found'
    });
  }
  
  rooms.delete(roomCode);
  console.log(`Room unregistered: ${roomCode}`);
  
  res.json({
    success: true
  });
});

// Start server
app.listen(PORT, () => {
  console.log('=================================');
  console.log('Godot Matchmaking Server');
  console.log('=================================');
  console.log(`Server running on port ${PORT}`);
  console.log(`Room expiry time: ${ROOM_EXPIRY_SECONDS} seconds`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log('=================================');
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully...');
  process.exit(0);
});

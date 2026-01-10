const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:localdb@localhost:5432/nakama'
});

// Test connection
pool.query('SELECT NOW()', (err) => {
  if (err) {
    console.error('Database connection error:', err.message);
  } else {
    console.log('✓ Database connected');
  }
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool
};

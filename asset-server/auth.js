const NAKAMA_URL = process.env.NAKAMA_URL || 'http://localhost:7350';

/**
 * Validates a Nakama session token and extracts user info.
 * Makes a lightweight call to Nakama's account endpoint.
 */
async function validateToken(token) {
  if (!token) {
    return null;
  }

  try {
    const response = await fetch(`${NAKAMA_URL}/v2/account`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      return null;
    }

    const account = await response.json();
    return {
      user_id: account.user.id,
      username: account.user.username || account.user.display_name || 'Anonymous'
    };
  } catch (error) {
    console.error('Auth validation error:', error.message);
    return null;
  }
}

/**
 * Express middleware for authentication.
 * Sets req.user if valid token, otherwise returns 401.
 */
function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization required' });
  }

  const token = authHeader.substring(7);
  
  validateToken(token)
    .then(user => {
      if (!user) {
        return res.status(401).json({ error: 'Invalid or expired token' });
      }
      req.user = user;
      next();
    })
    .catch(err => {
      console.error('Auth error:', err);
      res.status(500).json({ error: 'Authentication failed' });
    });
}

/**
 * Optional auth - sets req.user if present, but doesn't require it.
 */
function optionalAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    req.user = null;
    return next();
  }

  const token = authHeader.substring(7);
  
  validateToken(token)
    .then(user => {
      req.user = user;
      next();
    })
    .catch(() => {
      req.user = null;
      next();
    });
}

module.exports = { validateToken, requireAuth, optionalAuth };

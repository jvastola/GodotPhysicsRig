# Nakama Multiplayer Roadmap

## ✅ Phase 1: Foundation (COMPLETE)
- [x] Local Nakama server setup with Docker
- [x] NakamaManager singleton with WebSocket
- [x] Device authentication
- [x] Match creation and joining
- [x] Real-time state synchronization
- [x] Multi-user testing (3+ players verified)
- [x] Player presence tracking

---

## 🚀 Phase 2: Core Integration (IMMEDIATE - Parallel Tracks)

### Track A: Player Synchronization
**Owner:** VR/Player Team  
**Dependencies:** None  
**Estimated Time:** 2-3 days

- [ ] Update `xr_player.gd` to use Nakama when `NetworkManager.use_nakama = true`
- [ ] Send player transform via `PLAYER_TRANSFORM` op code
  - Position, rotation, velocity
  - Update rate: 20Hz for VR (50ms intervals)
- [ ] Receive and apply remote player transforms
- [ ] Test with 2-4 VR players
- [ ] Performance testing (latency, bandwidth)

**Files to modify:**
- `src/player/XRPlayer.gd` or equivalent
- `multiplayer/network_manager.gd`

---

### Track B: Grabbable Objects
**Owner:** Physics/Objects Team  
**Dependencies:** Track A (optional - can work standalone)  
**Estimated Time:** 2-3 days

- [ ] Update `grabbable_network_component.gd` for Nakama
- [ ] Implement `GRABBABLE_GRAB` op code
- [ ] Implement `GRABBABLE_RELEASE` op code  
- [ ] Implement `GRABBABLE_UPDATE` op code (position sync while held)
- [ ] Test object handoff between players
- [ ] Handle edge cases (simultaneous grab, network lag)

**Files to modify:**
- `src/objects/components/grabbable_network_component.gd`
- `src/objects/grabbable.gd`

---

### Track C: Voxel Building
**Owner:** Building/World Team  
**Dependencies:** None  
**Estimated Time:** 1-2 days

- [ ] Implement `VOXEL_PLACE` op code
- [ ] Implement `VOXEL_REMOVE` op code
- [ ] Sync voxel changes across all players
- [ ] Handle rapid building (debouncing/batching)
- [ ] Test with multiple simultaneous builders

**Files to modify:**
- Building system scripts (TBD based on architecture)

---

### Track D: Voice Chat
**Owner:** Audio Team  
**Dependencies:** None  
**Estimated Time:** 2-3 days

- [ ] Implement `VOICE_DATA` op code
- [ ] Encode/decode audio data
- [ ] Spatial audio for remote players
- [ ] Bandwidth optimization (compression, voice activity detection)
- [ ] Test audio quality and latency

**Files to modify:**
- `multiplayer/network_manager.gd` (voice chat section)

---

## 🧪 Phase 3: Testing & Optimization (Week 2)

### Track E: Load Testing
**Owner:** DevOps/Testing Team  
**Dependencies:** Tracks A, B, C complete  
**Estimated Time:** 3-4 days

- [ ] Synthetic player testing (8+ bots)
- [ ] Measure bandwidth per player
- [ ] Measure server CPU/memory usage
- [ ] Identify bottlenecks
- [ ] Optimize update rates
- [ ] Document performance metrics

---

### Track F: UI/UX Polish
**Owner:** UI Team  
**Dependencies:** Track A complete  
**Estimated Time:** 2-3 days

- [ ] Update main menu for Nakama matchmaking
- [ ] Show player list in-game
- [ ] Connection quality indicator
- [ ] Match browser (public matches)
- [ ] Friend system integration (future)

**Files to modify:**
- Main menu scenes
- NetworkUI components

---

## ☁️ Phase 4: Cloud Deployment (Week 3)

### Track G: Oracle Cloud Deployment
**Owner:** DevOps Team  
**Dependencies:** Phase 2 complete, testing passed  
**Estimated Time:** 2-3 days

- [ ] Deploy Nakama to Oracle Cloud
- [ ] Configure managed PostgreSQL
- [ ] Set up SSL/TLS certificates
- [ ] Change default passwords
- [ ] Configure auto-scaling
- [ ] Set up monitoring (Grafana/Prometheus)
- [ ] Document deployment process

**Reference:**
- `nakama/ORACLE_CLOUD_DEPLOY.md`

---

### Track H: Regional Deployment
**Owner:** DevOps Team  
**Dependencies:** Track G complete  
**Estimated Time:** 2-3 days

- [ ] Deploy to multiple regions (US, EU, Asia)
- [ ] Implement region selection in client
- [ ] Set up load balancing
- [ ] Monitor cross-region latency
- [ ] Document regional architecture

---

## 🎮 Phase 5: Advanced Features (Week 4+)

### Track I: Social Features
**Owner:** Backend/Social Team  
**Dependencies:** Cloud deployment  
**Estimated Time:** 1 week

- [ ] Friend lists
- [ ] Party system (invite friends)
- [ ] In-game chat
- [ ] Player profiles
- [ ] Recent players list

---

### Track J: Persistence & Progression
**Owner:** Backend Team  
**Dependencies:** Cloud deployment  
**Estimated Time:** 1 week

- [ ] Cloud save integration
- [ ] Player stats tracking
- [ ] Leaderboards
- [ ] Achievements
- [ ] Match history

---

### Track K: Security & Anti-Cheat
**Owner:** Security Team  
**Dependencies:** All core features  
**Estimated Time:** 1-2 weeks

- [ ] Server-side validation
- [ ] Rate limiting
- [ ] Player reporting system
- [ ] Admin tools (ban, kick, mute)
- [ ] Cheat detection

---

## 📊 Success Metrics

**Phase 2:**
- [ ] 8+ concurrent players with < 100ms latency
- [ ] < 100 KB/s per player bandwidth
- [ ] No desync issues

**Phase 3:**
- [ ] 50+ concurrent players tested
- [ ] 99% uptime over 1 week
- [ ] < 5% packet loss

**Phase 4:**
- [ ] Production deployment live
- [ ] Multi-region support
- [ ] Auto-scaling working

**Phase 5:**
- [ ] 100+ DAU (Daily Active Users)
- [ ] Social features used by 50%+ players
- [ ] Zero critical security issues

---

## Timeline Overview

```
Week 1: Phase 2 (Parallel Tracks A,B,C,D)
Week 2: Phase 3 (Testing & Optimization)
Week 3: Phase 4 (Cloud Deployment)
Week 4+: Phase 5 (Advanced Features)
```

## Current Status

✅ **DONE:** Phase 1 - Foundation complete  
🔄 **NEXT:** Phase 2 - Start parallel tracks
📋 **READY:** All documentation and guides complete

---

## Quick Start Next Steps

**For immediate work (pick any track):**

1. **Track A** - Player sync:
   ```gdscript
   # In xr_player.gd _physics_process
   if NetworkManager.use_nakama:
       NakamaManager.send_match_state(
           NakamaManager.MatchOpCode.PLAYER_TRANSFORM,
           {"pos": position, "rot": rotation}
       )
   ```

2. **Track B** - Grabbables:
   ```gdscript
   # In grabbable_network_component.gd
   func on_grabbed():
       NakamaManager.send_match_state(
           NakamaManager.MatchOpCode.GRABBABLE_GRAB,
           {"object_id": get_instance_id()}
       )
   ```

3. **Track C** - Voxels:
   ```gdscript
   # In building system
   func place_voxel(pos, type):
       NakamaManager.send_match_state(
           NakamaManager.MatchOpCode.VOXEL_PLACE,
           {"pos": pos, "type": type}
       )
   ```

**Each track can be worked on independently by different team members!**

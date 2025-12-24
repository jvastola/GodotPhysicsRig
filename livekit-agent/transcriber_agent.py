"""
LiveKit Transcriber Agent for LiveKit Cloud

Transcribes audio from all participants and broadcasts transcripts via data channel.
Saves all transcripts to persistent storage (text files or SQLite database).
Deploy to LiveKit Cloud using: livekit-cli cloud agent deploy
"""

import asyncio
import json
import logging
import os
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

# Load environment variables from .env file
from dotenv import load_dotenv
load_dotenv()

from livekit import rtc
from livekit.agents import (
    AutoSubscribe,
    JobContext,
    JobProcess,
    WorkerOptions,
    cli,
    stt,
)
from livekit.plugins import deepgram, silero

logger = logging.getLogger("transcriber")
logger.setLevel(logging.INFO)


# ============================================================================
# TRANSCRIPT PERSISTENCE
# ============================================================================

class TranscriptStorage:
    """Handles persistent storage of transcripts to text files and/or SQLite."""
    
    def __init__(self, room_name: str, storage_dir: str = "transcripts"):
        self.room_name = room_name
        self.storage_dir = Path(storage_dir)
        self.storage_dir.mkdir(parents=True, exist_ok=True)
        
        # Text file for this session
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.text_file = self.storage_dir / f"transcript_{room_name}_{timestamp}.txt"
        self.json_file = self.storage_dir / f"transcript_{room_name}_{timestamp}.json"
        
        # SQLite database (shared across all sessions)
        self.db_path = self.storage_dir / "transcripts.db"
        self._init_db()
        
        # In-memory buffer for JSON export
        self._entries: list[dict] = []
        
        # Write header to text file
        self._write_text_header()
        
        logger.info(f"TranscriptStorage initialized: {self.text_file}")
    
    def _init_db(self) -> None:
        """Initialize SQLite database with transcripts table."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS transcripts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                room_name TEXT NOT NULL,
                speaker_identity TEXT NOT NULL,
                speaker_name TEXT,
                text TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_room_timestamp 
            ON transcripts(room_name, timestamp)
        """)
        conn.commit()
        conn.close()
    
    def _write_text_header(self) -> None:
        """Write header to text file."""
        with open(self.text_file, "w", encoding="utf-8") as f:
            f.write(f"# World Transcript - {self.room_name}\n")
            f.write(f"# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("# " + "=" * 60 + "\n\n")
    
    def save_entry(self, speaker_identity: str, speaker_name: str, text: str, timestamp_ms: int) -> None:
        """Save a transcript entry to all storage backends."""
        # Format timestamp
        dt = datetime.fromtimestamp(timestamp_ms / 1000)
        time_str = dt.strftime("%H:%M:%S")
        display_name = speaker_name or speaker_identity
        
        # Save to text file (append)
        with open(self.text_file, "a", encoding="utf-8") as f:
            f.write(f"[{time_str}] {display_name}: {text}\n")
        
        # Save to SQLite
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO transcripts (room_name, speaker_identity, speaker_name, text, timestamp)
                VALUES (?, ?, ?, ?, ?)
            """, (self.room_name, speaker_identity, speaker_name, text, timestamp_ms))
            conn.commit()
            conn.close()
        except Exception as e:
            logger.error(f"Failed to save to database: {e}")
        
        # Add to in-memory buffer for JSON export
        self._entries.append({
            "speaker_identity": speaker_identity,
            "speaker_name": speaker_name,
            "text": text,
            "timestamp": timestamp_ms,
            "is_final": True
        })
    
    def save_json(self) -> None:
        """Save all entries to JSON file."""
        data = {
            "room_name": self.room_name,
            "export_timestamp": int(time.time() * 1000),
            "export_date": datetime.now().isoformat(),
            "entry_count": len(self._entries),
            "entries": self._entries
        }
        with open(self.json_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        logger.info(f"Saved JSON transcript: {self.json_file}")
    
    def finalize(self) -> None:
        """Finalize storage - write footer and save JSON."""
        # Write footer to text file
        with open(self.text_file, "a", encoding="utf-8") as f:
            f.write(f"\n# " + "=" * 60 + "\n")
            f.write(f"# Ended: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# Total entries: {len(self._entries)}\n")
        
        # Save JSON
        self.save_json()
        logger.info(f"Transcript finalized: {len(self._entries)} entries")


# Global storage instance (set per room)
_transcript_storage: Optional[TranscriptStorage] = None


class ParticipantTranscriber:
    """Handles transcription for a single participant."""
    
    def __init__(
        self,
        participant: rtc.RemoteParticipant,
        track: rtc.Track,
        room: rtc.Room,
        stt_stream: stt.SpeechStream,
    ):
        self.participant = participant
        self.track = track
        self.room = room
        self.stt_stream = stt_stream
        self._tasks: list[asyncio.Task] = []
        self._running = False
    
    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        
        self._tasks = [
            asyncio.create_task(self._process_audio()),
            asyncio.create_task(self._process_transcripts()),
        ]
        logger.info(f"Started transcription for {self.participant.identity}")
    
    async def stop(self) -> None:
        self._running = False
        for task in self._tasks:
            task.cancel()
        await asyncio.gather(*self._tasks, return_exceptions=True)
        self._tasks.clear()
        await self.stt_stream.aclose()
        logger.info(f"Stopped transcription for {self.participant.identity}")
    
    async def _process_audio(self) -> None:
        try:
            audio_stream = rtc.AudioStream(self.track)
            async for event in audio_stream:
                if not self._running:
                    break
                if isinstance(event, rtc.AudioFrameEvent):
                    self.stt_stream.push_frame(event.frame)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Audio processing error: {e}")
    
    async def _process_transcripts(self) -> None:
        try:
            async for event in self.stt_stream:
                if not self._running:
                    break
                if event.type == stt.SpeechEventType.FINAL_TRANSCRIPT:
                    text = event.alternatives[0].text if event.alternatives else ""
                    if text.strip():
                        await self._broadcast(text)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Transcript processing error: {e}")
    
    async def _broadcast(self, text: str) -> None:
        global _transcript_storage
        timestamp_ms = int(time.time() * 1000)
        
        message = {
            "type": "transcript",
            "speaker_identity": self.participant.identity,
            "speaker_name": self.participant.name or self.participant.identity,
            "text": text,
            "timestamp": timestamp_ms,
            "is_final": True,
        }
        
        # Save to persistent storage
        if _transcript_storage:
            _transcript_storage.save_entry(
                speaker_identity=self.participant.identity,
                speaker_name=self.participant.name or self.participant.identity,
                text=text,
                timestamp_ms=timestamp_ms
            )
        
        try:
            await self.room.local_participant.publish_data(
                json.dumps(message).encode("utf-8"),
                reliable=True,
            )
            logger.info(f"[{self.participant.identity}]: {text[:60]}")
        except Exception as e:
            logger.error(f"Broadcast error: {e}")


class RoomTranscriber:
    """Manages transcription for all participants in a room."""
    
    def __init__(self, room: rtc.Room):
        self.room = room
        self._transcribers: Dict[str, ParticipantTranscriber] = {}
        self._stt = deepgram.STT()
    
    async def start(self) -> None:
        self.room.on("track_subscribed", self._on_track_subscribed)
        self.room.on("track_unsubscribed", self._on_track_unsubscribed)
        self.room.on("participant_disconnected", self._on_participant_disconnected)
        
        # Handle existing participants
        for participant in self.room.remote_participants.values():
            for pub in participant.track_publications.values():
                if pub.track and pub.kind == rtc.TrackKind.KIND_AUDIO:
                    await self._add_transcriber(participant, pub.track)
        
        logger.info(f"RoomTranscriber started with {len(self._transcribers)} participants")
    
    def _on_track_subscribed(
        self, track: rtc.Track, pub: rtc.TrackPublication, participant: rtc.RemoteParticipant
    ) -> None:
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            asyncio.create_task(self._add_transcriber(participant, track))
    
    def _on_track_unsubscribed(
        self, track: rtc.Track, pub: rtc.TrackPublication, participant: rtc.RemoteParticipant
    ) -> None:
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            asyncio.create_task(self._remove_transcriber(participant.identity))
    
    def _on_participant_disconnected(self, participant: rtc.RemoteParticipant) -> None:
        asyncio.create_task(self._remove_transcriber(participant.identity))
    
    async def _add_transcriber(self, participant: rtc.RemoteParticipant, track: rtc.Track) -> None:
        if participant.identity in self._transcribers:
            return
        
        stt_stream = self._stt.stream()
        transcriber = ParticipantTranscriber(participant, track, self.room, stt_stream)
        self._transcribers[participant.identity] = transcriber
        await transcriber.start()
    
    async def _remove_transcriber(self, identity: str) -> None:
        transcriber = self._transcribers.pop(identity, None)
        if transcriber:
            await transcriber.stop()
    
    async def cleanup(self) -> None:
        for identity in list(self._transcribers.keys()):
            await self._remove_transcriber(identity)
        logger.info("RoomTranscriber cleaned up")


async def entrypoint(ctx: JobContext) -> None:
    """Main agent entrypoint."""
    global _transcript_storage
    
    logger.info(f"Agent joining room: {ctx.room.name}")
    
    # Initialize transcript storage for this room
    storage_dir = os.environ.get("TRANSCRIPT_STORAGE_DIR", "transcripts")
    _transcript_storage = TranscriptStorage(ctx.room.name, storage_dir)
    
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
    logger.info("Connected to room")
    
    transcriber = RoomTranscriber(ctx.room)
    await transcriber.start()
    
    async def cleanup_with_storage():
        await transcriber.cleanup()
        if _transcript_storage:
            _transcript_storage.finalize()
    
    ctx.add_shutdown_callback(cleanup_with_storage)
    logger.info("Transcriber agent running")


def prewarm(proc: JobProcess) -> None:
    """Prewarm models for faster startup."""
    logger.info("Prewarming...")
    proc.userdata["vad"] = silero.VAD.load()
    logger.info("Prewarm complete")


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            prewarm_fnc=prewarm,
        ),
    )

"""
LiveKit Transcriber Agent for LiveKit Cloud

Transcribes audio from all participants and broadcasts transcripts via data channel.
Deploy to LiveKit Cloud using: livekit-cli cloud agent deploy
"""

import asyncio
import json
import logging
import os
import time
from typing import Dict

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
        message = {
            "type": "transcript",
            "speaker_identity": self.participant.identity,
            "speaker_name": self.participant.name or self.participant.identity,
            "text": text,
            "timestamp": int(time.time() * 1000),
            "is_final": True,
        }
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
    logger.info(f"Agent joining room: {ctx.room.name}")
    
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
    logger.info("Connected to room")
    
    transcriber = RoomTranscriber(ctx.room)
    await transcriber.start()
    
    ctx.add_shutdown_callback(transcriber.cleanup)
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

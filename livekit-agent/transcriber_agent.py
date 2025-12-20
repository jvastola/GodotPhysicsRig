"""
LiveKit Agent for Multi-User Voice Transcription

This agent transcribes audio from all participants in a LiveKit room
and broadcasts the transcripts to all room participants via data channel.

Based on the LiveKit Agents SDK with Deepgram STT and Silero VAD.
"""

import asyncio
import json
import logging
import time
from typing import Dict

from dotenv import load_dotenv
from livekit import rtc
from livekit.agents import (
    Agent,
    AgentSession,
    JobContext,
    JobProcess,
    WorkerOptions,
    cli,
)
# from livekit.agents.voice import AgentTranscriptionOptions  # Removed in 1.x
from livekit.plugins import deepgram, silero

load_dotenv()

logger = logging.getLogger("transcriber-agent")
logger.setLevel(logging.INFO)


class TranscriberAgent(Agent):
    """
    Agent that transcribes a single participant's audio and broadcasts
    the transcript to all room participants.
    """

    def __init__(self, *, participant_identity: str, room: rtc.Room):
        super().__init__(
            instructions="Transcribe user speech. Do not respond, just transcribe.",
            stt=deepgram.STT(),
        )
        self.participant_identity = participant_identity
        self.room = room

    async def on_user_turn_completed(self, chat_ctx, new_message) -> None:
        """Called when the user finishes speaking. Broadcast the transcript."""
        transcript = new_message.text_content
        if not transcript or not transcript.strip():
            return

        # Build transcript message
        message = {
            "type": "transcript",
            "speaker_identity": self.participant_identity,
            "text": transcript.strip(),
            "timestamp": int(time.time() * 1000),
            "is_final": True,
        }

        # Broadcast to all participants
        try:
            await self.room.local_participant.publish_data(
                json.dumps(message).encode("utf-8"),
                reliable=True,
            )
            logger.info(f"Transcript from {self.participant_identity}: {transcript[:50]}...")
        except Exception as e:
            logger.error(f"Failed to publish transcript: {e}")

        # Don't generate a response - we're just transcribing
        from livekit.agents import StopResponse
        raise StopResponse()


class MultiUserTranscriber:
    """
    Manages transcription sessions for all participants in a room.
    Creates a separate AgentSession for each participant to transcribe
    their audio independently.
    """

    def __init__(self, ctx: JobContext):
        self.ctx = ctx
        self._sessions: Dict[str, AgentSession] = {}
        self._vad = silero.VAD.load()

    async def start(self) -> None:
        """Start listening for participant events."""
        self.ctx.room.on("participant_connected", self._on_participant_connected)
        self.ctx.room.on("participant_disconnected", self._on_participant_disconnected)

        # Start sessions for existing participants
        for participant in self.ctx.room.remote_participants.values():
            await self._start_session(participant)

        logger.info(f"MultiUserTranscriber started with {len(self._sessions)} participants")

    async def _on_participant_connected(self, participant: rtc.RemoteParticipant) -> None:
        """Handle new participant joining the room."""
        logger.info(f"Participant connected: {participant.identity}")
        await self._start_session(participant)

    async def _on_participant_disconnected(self, participant: rtc.RemoteParticipant) -> None:
        """Handle participant leaving the room."""
        logger.info(f"Participant disconnected: {participant.identity}")
        await self._stop_session(participant.identity)

    async def _start_session(self, participant: rtc.RemoteParticipant) -> None:
        """Start a transcription session for a participant."""
        if participant.identity in self._sessions:
            logger.warning(f"Session already exists for {participant.identity}")
            return

        try:
            agent = TranscriberAgent(
                participant_identity=participant.identity,
                room=self.ctx.room,
            )

            session = AgentSession(
                vad=self._vad,
                # Transcription options are now handled differently in 1.x
            )

            # Start the session for this specific participant
            session.start(
                room=self.ctx.room,
                agent=agent,
                participant=participant,
            )

            self._sessions[participant.identity] = session
            logger.info(f"Started transcription session for {participant.identity}")

        except Exception as e:
            logger.error(f"Failed to start session for {participant.identity}: {e}")

    async def _stop_session(self, identity: str) -> None:
        """Stop a transcription session for a participant."""
        session = self._sessions.pop(identity, None)
        if session:
            try:
                await session.aclose()
                logger.info(f"Stopped transcription session for {identity}")
            except Exception as e:
                logger.error(f"Error stopping session for {identity}: {e}")

    async def cleanup(self) -> None:
        """Clean up all sessions."""
        for identity in list(self._sessions.keys()):
            await self._stop_session(identity)
        logger.info("MultiUserTranscriber cleaned up")


async def entrypoint(ctx: JobContext) -> None:
    """
    Main entrypoint for the transcription agent.
    Called when a new room job is received.
    """
    logger.info(f"Connecting to room: {ctx.room.name}")

    # Wait for connection
    await ctx.connect()
    logger.info(f"Connected to room: {ctx.room.name}")

    # Create and start the multi-user transcriber
    transcriber = MultiUserTranscriber(ctx)
    await transcriber.start()

    # Register cleanup callback
    ctx.add_shutdown_callback(transcriber.cleanup)

    # Keep the agent running
    logger.info("Transcriber agent running...")


def prewarm(proc: JobProcess) -> None:
    """
    Prewarm function to load models before accepting jobs.
    This reduces latency when the first job arrives.
    """
    logger.info("Prewarming: Loading VAD model...")
    proc.userdata["vad"] = silero.VAD.load()
    logger.info("Prewarm complete")


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            prewarm_fnc=prewarm,
        ),
    )

# LiveKit Transcriber Agent

A LiveKit Agent that transcribes audio from all participants in a room and broadcasts transcripts via data channel.

## Features

- Multi-user transcription using Deepgram STT
- Voice Activity Detection using Silero VAD
- Real-time transcript broadcasting to all room participants
- Automatic session management for joining/leaving participants

## Requirements

- Python 3.9+
- LiveKit server
- Deepgram API key

## Setup

1. Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

## Running

### Development Mode

```bash
python transcriber_agent.py dev
```

### Production Mode

```bash
python transcriber_agent.py start
```

### Docker

```bash
docker-compose up -d
```

## Transcript Message Format

The agent broadcasts JSON messages via LiveKit data channel:

```json
{
    "type": "transcript",
    "speaker_identity": "user123",
    "text": "Hello everyone!",
    "timestamp": 1703001234567,
    "is_final": true
}
```

## Integration with Godot

The Godot client receives these messages via the `data_received` signal from `LiveKitWrapper`. The `TranscriptReceiverHandler` class parses these messages and creates `TranscriptEntry` objects for display in the `WorldTranscriptPanel`.

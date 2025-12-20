# Requirements Document

## Introduction

This feature adds voice-to-text transcription capabilities to the LLM Chat Terminal, enabling users to speak commands and have them transcribed and sent to the LLM. The system leverages the existing LiveKit infrastructure for audio capture and integrates with OpenAI's Whisper API (or compatible services) for speech-to-text transcription. Additionally, a World Transcript Panel displays a real-time transcript of all voice activity in the multiplayer room.

## Glossary

- **LLM Chat Terminal**: The existing chat interface for interacting with LLMs (Claude, OpenAI, etc.)
- **LiveKit**: Real-time audio/video communication platform already integrated in the project
- **Whisper**: OpenAI's speech-to-text model, available via API
- **World Transcript**: A shared transcript of all voice activity from participants in a LiveKit room
- **Voice-to-Text (VTT)**: The process of converting spoken audio into text
- **Push-to-Talk (PTT)**: A mode where audio is only captured while a button is held
- **Voice Activity Detection (VAD)**: Automatic detection of when a user is speaking
- **Transcript Entry**: A single transcribed utterance with speaker identity and timestamp

## Requirements

### Requirement 1

**User Story:** As a user, I want to speak into my microphone and have my speech transcribed to text, so that I can interact with the LLM without typing.

#### Acceptance Criteria

1. WHEN a user activates voice input mode THEN the LLM Chat Terminal SHALL begin capturing audio from the microphone
2. WHEN the user finishes speaking THEN the system SHALL send the captured audio to the Whisper API for transcription
3. WHEN the transcription is received THEN the system SHALL populate the message input field with the transcribed text
4. WHEN the transcription is complete THEN the system SHALL provide visual feedback indicating the transcription result
5. IF the Whisper API returns an error THEN the system SHALL display an error message and allow retry

### Requirement 2

**User Story:** As a user, I want to choose between push-to-talk and voice activity detection modes, so that I can control when my voice is captured.

#### Acceptance Criteria

1. WHEN push-to-talk mode is selected THEN the system SHALL capture audio only while the designated button is held
2. WHEN voice activity detection mode is selected THEN the system SHALL automatically detect speech start and end
3. WHEN switching between modes THEN the system SHALL immediately apply the new mode without requiring reconnection
4. WHERE the user has not configured a mode THEN the system SHALL default to push-to-talk mode

### Requirement 3

**User Story:** As a user, I want to see a visual indicator when my voice is being captured, so that I know the system is listening.

#### Acceptance Criteria

1. WHILE audio is being captured THEN the system SHALL display a recording indicator in the UI
2. WHILE audio is being captured THEN the system SHALL display a real-time audio level meter
3. WHEN transcription is in progress THEN the system SHALL display a processing indicator
4. WHEN the system transitions between states THEN the UI SHALL update within 100 milliseconds

### Requirement 4

**User Story:** As a user, I want to configure the Whisper API settings, so that I can use my preferred transcription service.

#### Acceptance Criteria

1. WHEN the user opens voice settings THEN the system SHALL display options for API endpoint and API key
2. WHEN the user saves voice settings THEN the system SHALL persist the configuration to local storage
3. WHERE a custom Whisper-compatible endpoint is configured THEN the system SHALL use that endpoint for transcription
4. WHEN testing the connection THEN the system SHALL verify the API key is valid and display the result

### Requirement 5

**User Story:** As a multiplayer user, I want to see a transcript of all voice activity in the room, so that I can follow conversations even if I missed something.

#### Acceptance Criteria

1. WHEN a participant speaks in the LiveKit room THEN the system SHALL capture and transcribe their audio
2. WHEN a transcription is received THEN the system SHALL add an entry to the World Transcript with speaker identity and timestamp
3. WHEN viewing the World Transcript Panel THEN the system SHALL display entries in chronological order with speaker names
4. WHEN a new transcript entry is added THEN the panel SHALL auto-scroll to show the latest entry
5. WHEN the transcript exceeds 500 entries THEN the system SHALL remove the oldest entries to maintain performance

### Requirement 6

**User Story:** As a user, I want to copy or export the World Transcript, so that I can save or share the conversation history.

#### Acceptance Criteria

1. WHEN the user clicks the copy button THEN the system SHALL copy the transcript to the clipboard in readable format
2. WHEN the user clicks the export button THEN the system SHALL save the transcript to a file with timestamps and speaker names
3. WHEN exporting THEN the system SHALL include metadata such as room name and date

### Requirement 7

**User Story:** As a user, I want the voice-to-text feature to work in VR, so that I can use voice commands while wearing a headset.

#### Acceptance Criteria

1. WHEN in VR mode THEN the system SHALL support controller button activation for push-to-talk
2. WHEN in VR mode THEN the World Transcript Panel SHALL be displayed as a 3D viewport panel
3. WHEN the user speaks in VR THEN the transcription workflow SHALL function identically to desktop mode

### Requirement 8

**User Story:** As a user, I want to send transcribed text directly to the LLM, so that I can have a hands-free conversation.

#### Acceptance Criteria

1. WHEN auto-send mode is enabled THEN the system SHALL automatically send transcribed text to the LLM after transcription completes
2. WHEN auto-send mode is disabled THEN the system SHALL populate the input field and wait for user confirmation
3. WHEN the user configures auto-send THEN the system SHALL persist this preference

### Requirement 9

**User Story:** As a developer, I want the voice-to-text system to be modular, so that different transcription backends can be used.

#### Acceptance Criteria

1. WHEN implementing the transcription service THEN the system SHALL use an abstract interface for the transcription backend
2. WHEN a new transcription backend is added THEN the system SHALL require only implementation of the interface without modifying core logic
3. WHEN the backend is unavailable THEN the system SHALL gracefully degrade and notify the user

# Requirements Document

## Introduction

This feature fixes the scrolling behavior in the WebView panel for VR. Currently, when users try to scroll web content by clicking the trigger and dragging, the scrolling doesn't work correctly - it scrolls a Godot UI element instead of the actual webpage content, causes blank regions, and scrolls in the wrong direction. The fix implements native drag-to-scroll behavior that feels like a 1:1 touch gesture on the webpage.

## Glossary

- **Webview_Panel**: The WebviewViewport3D component that displays web content in VR
- **Drag_Scroll**: A scrolling gesture where the user clicks/holds and drags to scroll content
- **Touch_Event**: Native Android touch events (ACTION_DOWN, ACTION_MOVE, ACTION_UP) sent to the WebView
- **Backend**: The platform-specific webview implementation (AndroidWebViewBackend)
- **Pointer**: The VR controller's laser pointer used for interaction
- **Scroll_Delta**: The difference in position between the current and previous pointer positions during a drag

## Requirements

### Requirement 1: Drag-to-Scroll Gesture

**User Story:** As a VR user, I want to scroll web content by clicking and dragging with my pointer, so that scrolling feels natural like touching a screen.

#### Acceptance Criteria

1. WHEN a user presses the trigger on web content and drags the pointer, THE Webview_Panel SHALL scroll the webpage content in the same direction as the drag
2. WHEN the user drags the pointer upward (positive Y direction in viewport space), THE webpage content SHALL move upward (scroll position decreases), creating a 1:1 touch-like feel
3. WHEN the user drags the pointer downward (negative Y direction in viewport space), THE webpage content SHALL move downward (scroll position increases)
4. THE scroll amount SHALL be proportional to the drag distance (1:1 pixel mapping)
5. WHEN the user releases the trigger, THE Webview_Panel SHALL stop scrolling

### Requirement 2: Remove Godot UI Scrollbar Interference

**User Story:** As a VR user, I want scrolling to only affect the webpage, so that I don't see blank regions or unexpected UI behavior.

#### Acceptance Criteria

1. THE Webview_Panel SHALL NOT use a Godot VScrollBar for controlling webpage scroll position
2. WHEN scrolling occurs, THE system SHALL send scroll commands directly to the webpage via the backend
3. THE system SHALL NOT cause blank regions or visual artifacts when scrolling

### Requirement 3: Error-Free Scroll Info Handling

**User Story:** As a developer, I want the scroll info signal handler to work without errors, so that the system is stable.

#### Acceptance Criteria

1. WHEN the scroll_info_received signal is emitted, THE AndroidWebViewBackend SHALL parse the JSON data without type errors
2. IF the scroll info JSON is null or invalid, THE system SHALL handle it gracefully without crashing
3. THE system SHALL log a warning for invalid scroll info data instead of throwing an error

### Requirement 4: Scroll State Tracking

**User Story:** As a VR user, I want smooth continuous scrolling while dragging, so that the experience feels responsive.

#### Acceptance Criteria

1. WHILE the user is dragging (trigger held), THE system SHALL track the pointer position continuously
2. THE system SHALL calculate scroll delta from the previous position to the current position each frame
3. THE system SHALL send scroll commands to the backend based on the accumulated delta


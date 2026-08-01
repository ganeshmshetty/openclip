# Popup Hover Tracking Design

## Goal

Ensure the blue hover highlight immediately follows the pointer when it moves
between popup buttons, including when the pointer stops immediately over its
new target.

## Design

`PopupView` will own one transparent AppKit tracking view over the visible
button bar. It will receive mouse-moved events and map the pointer position to
one stable button identifier. Leaving the bar clears the identifier.

Each action, completion, and chevron button will render its existing visual
hover treatment when its identifier is the bar's current hovered identifier.
The action and completion identifiers will be stable IDs; chevrons will use
fixed identifiers.

The tracker is the only source of hover truth. Per-button background
`HoverTrackingView`s will be removed, avoiding reliance on the unspecified
ordering of adjacent `mouseEntered` and `mouseExited` events.

## Scope and Validation

The popup's appearance, actions, paging, completion mode, and menu behavior
remain unchanged. The failed `PopupPanel` mouse-movement/key-window experiment
will be removed. Run the macOS build/tests and `./scripts/dev_run.sh`; manually
verify moving from one button to another and stopping immediately updates the
blue highlight without a second mouse movement.

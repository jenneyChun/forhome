# 2026-06-03 Session - Review, Proof, and Tomorrow Planning UI

## User Request

The user said the current screen felt too "AI-like" and asked for a more ordinary, practical UI. They also clarified the real product goal:

- Decide who did more household work.
- At the end of the day, show who did what.
- Share what should be done the next day.
- Let a person mark a chore as completed and notify the other person.
- Let the other person review and confirm the completed chore.
- Support photo proof so chores are easier to verify and less likely to become a source of misunderstanding.

## Implementation Notes

- Reworked the browser UI labels and layout toward a calmer household operations tool.
- Added pending, approved, and rejected verification states for chore history.
- Added a reviewer selection field when completing a chore.
- Added photo proof input, image preview, memo, and compressed local image storage metadata.
- Changed completion so chores are saved as pending until a reviewer approves them.
- Added a review screen for pending confirmations and recent review history.
- Added a tomorrow planning screen for assigning or reminding family members about next-day chores.
- Updated daily summary and backup export to include task status, reviewer, proof summary, and tomorrow plans.

## Verification Scope

- Added structure assertions for proof input, verification state, reviewer approval, and tomorrow plans.
- Updated Playwright flows for pending completion, mobile tomorrow navigation, shared mock storage, tomorrow-plan creation, and photo-proof input availability.

## Product Note

The current photo feature stores a compressed proof image and basic analysis text in the app state. A later production step should move full image storage to Firebase Storage and can add actual AI image analysis if needed.

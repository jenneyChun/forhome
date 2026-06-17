# 2026-06-17-01 Warm Card Household UI

## User Request

- Add a GUI for the current project.
- Design direction: family household chore verification app.
- Make it easy for children to use with large buttons, card-style UI, and warm colors.
- Implement first:
  - Home dashboard
  - Chore list cards
  - Photo upload proof screen
  - AI analysis result card
  - Parent approval screen
- Prefer Tailwind CSS and shadcn/ui style component structure.
- Preserve existing logic as much as possible and separate only the UI layer.

## Implementation Scope

- Updated `code/index.html`.
- Kept the existing single-file app structure.
- Did not add a Tailwind build pipeline.
- Added shadcn/ui-inspired CSS tokens and reusable card/button styles inside the existing stylesheet.
- Kept existing state, Firebase/localStorage, approval, proof upload, and save logic intact.

## UI Changes

### Home Dashboard

- Added a warm hero section that explains the daily household verification flow.
- Replaced simple metric blocks with larger `stat-card` dashboard cards.
- Kept existing data source:
  - today records
  - approved records
  - pending records
  - today plans

### Chore List Cards

- Updated chore selection rows into larger `chore-card` UI.
- Added `chore-icon` visual area for each chore.
- Preserved existing chore selection logic:
  - `selectChore(id)`
  - `setCategory(id)`
  - `selectedChoreId`

### Photo Upload Proof Screen

- Added `upload-zone` styling to the proof photo area.
- Made the submit button larger with `btn kid`.
- Preserved existing proof handling:
  - `handleProofSelected(event)`
  - `readProofImage(file)`
  - `completeTask()`

### AI Analysis Result Card

- Added an `ai-result-card` under the photo upload area.
- Connected photo analysis text to the card through `aiAnalysisText`.
- The current AI card uses the existing local image analysis summary:
  - resized image dimensions
  - original file size
  - file name

### Parent Approval Screen

- Added a warm approval hero to the review screen.
- Updated activity/review cards with `approval-card`.
- Highlighted pending approval items with `approval-card pending`.
- Made approval and rejection buttons larger.
- Preserved existing approval logic:
  - `approveTask(id)`
  - `rejectTask(id)`
  - `canReviewEntry(entry)`

## Design Notes

- Used warm cream, peach, amber, and green tones.
- Kept border radius at `8px` to match existing design constraints.
- Used large touch targets for child-friendly interaction.
- Avoided adding a new dependency or build system.
- Treated the work as UI-layer polish over the existing app logic.

## Verification

- Browser script syntax check passed with `node --check` on the extracted script block.
- `git diff --check` passed.
- `npm.cmd test` passed.

## Commit

`667f7e3 feat: add warm card-based household UI`

### Commit Summary

- Added warm family-oriented visual tokens.
- Added large card-based dashboard and chore selection UI.
- Added photo proof upload zone.
- Added AI analysis result card.
- Added parent approval hero and larger approval action buttons.
- Kept existing product logic intact.

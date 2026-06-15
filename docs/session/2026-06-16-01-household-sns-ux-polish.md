# 2026-06-16 Session - Household SNS UX Polish

## User Request

The user clarified that ForHome's product goal is a household chore sharing SNS, not a generic photo SNS. They asked to apply the frontend-owned UX recommendations while keeping a change log.

## UX Changes

- Changed the chore submission CTA from completion-oriented wording to `확인 요청 보내기` so users understand records are pending family review.
- Added person-based review progress text such as `아빠 확인 대기`, `엄마 확인 완료`, and `다시 확인 요청`.
- Changed review action wording to softer household language: `확인했어요` and `다시 확인 요청`.
- Split the home view into an approved `오늘 가족 피드` section and a separate `확인 대기 중` section.
- Reworded the daily contribution panel from direct competition to `오늘의 수고 균형`, and made fatigue/XP copy feel like shared appreciation rather than ranking.
- Replaced user-facing `부담` terminology with `포인트`/`수고 포인트` so contribution can feel like points being accumulated.

## Implementation Notes

- Updated the rendering logic in `code/index.html`.
- Reused the existing `history`, `approvalRequests`, `verificationStatus`, `proofImage`, and `proofCaption` data model.
- Added `reviewProgressText(entry)` for reviewer-by-reviewer status display without changing persisted data shape.
- Kept the existing Firebase/localStorage storage providers unchanged.

## Verification Scope

- Run the existing PowerShell structure tests.
- Run Playwright E2E if browser dependencies are available.
- Confirm that the current `poc` branch contains only intentional UX and session-log changes before committing.

## Follow-up Notes

- Future work can add quick appreciation reactions such as `고마워요`.
- Rejected records may deserve a dedicated home subsection if families use the rejection flow frequently.
- A later production step should move proof images out of the single Firestore state document and into Firebase Storage.

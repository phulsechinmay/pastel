# Labels settings UX

Date: 2026-10-18
Status: Core flows implemented in source; live interaction and accessibility QA pending

## Problem

Labels are useful for organizing clips, but Settings currently creates a persisted "New Label" immediately, lets unfinished or blank renames mutate SwiftData, hides Delete until pointer hover, and offers drag as the only way to reorder. The shared appearance picker uses gesture-only swatches. History shows an All History chip that is always styled active and cannot clear a label filter. These gaps make a keyboard-first Mac utility feel unpredictable in its slower, organizational surface.

## Design direction

Keep the native Settings list and quiet system colors. Each row gives the label's appearance, an editable name, a clip count that opens the corresponding History filter, and a persistent actions menu. A small drag handle and Move Up/Down actions explain and support ordering. The same appearance selector serves Settings and panel editing; it uses buttons, named choices, selected traits, and a visible non-color selection ring. New labels are drafts until Add or Return, and Escape cancels without writing a model. Renames normalize whitespace and commit only a valid name on Return or focus loss.

This is specific to Pastel's two speeds: the panel remains compact and immediate; Settings can explain organization and consequences. Avoid decorative cards, a second palette implementation, or a new sorting mode.

## Implementation sequence

1. **Shared controls and naming.** Make the style grid keyboard and VoiceOver accessible, grow targets to 28 pt, label Color and Emoji sections, respect reduced motion, and centralize whitespace/newline trimming. Keep a shared count-specific deletion message.
2. **Creation and editing.** Use an inline draft row with focus, explicit Add/Cancel, validation and duplicate-name guidance. Rename from a local draft; save only on commit and keep the draft when save fails. Panel editing uses a transactional draft.
3. **Management.** Show a persistent row actions menu, a drag cue, and Move Up/Down alternatives. Keep the existing native drag reorder. Confirm label deletion in the panel as Settings already does, leaving clips intact. Prune deleted labels from active filters.
4. **History handoff.** "Show N Clips" opens History with that label selected and clears the previous search/selection. A fresh request ID allows repeated use. All History clears the filter and reflects its actual active state.

## Verification

- Create, type, Return: exactly one named label. Repeated Add focuses the same draft; Cancel/Escape creates none. Whitespace-only names are rejected.
- Rename, Return/focus loss: saved once; Escape restores; invalid names do not reach the model. Duplicate names are warned about but remain allowed for existing data and sync compatibility.
- Navigate appearance choices, row actions, movement and deletion by keyboard. VoiceOver should announce option names and selected state.
- Reordering changes chip order in the panel; deleting a label keeps clips and clears any active filter that referenced it.
- Show Clips opens the right History filter on repeat requests; All History clears it.
- Inspect the running Settings screen at minimum window size, with long names and many labels, in light and dark appearances. Confirm actual focus, popover geometry, VoiceOver order, and drag interaction.
- Build and run the signed Debug-Sparkle app. A code build alone does not count as ready to test.

## Source-review limits and follow-ups

The Astra review used the Impeccable and Apple design skills plus the current SwiftUI source. Computer-use inspection timed out, so rendered layout and accessibility output still need live verification. Save failure feedback is now local for creation, renaming, panel edit, and reordering; direct appearance changes and deletion still use the existing logging path. A later persistence pass can make those transactional without rolling back the shared model context or affecting clipboard capture. A dedicated DESIGN.md could document established tokens but does not block this work.

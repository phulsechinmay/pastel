# Product

## Register

product

## Users

Mac users who copy and paste constantly and have decided that the system clipboard's
one-slot memory is a bug in their day: developers, designers, writers, support staff.
They are keyboard-first. They reach Pastel with a global hotkey mid-task, in another
app's context, and they want to be back in that app within two seconds. Many will use
it dozens of times an hour without ever opening Settings.

The job to be done: retrieve something I copied earlier and put it where my cursor is,
without losing my place.

Two distinct contexts, and they want opposite things:

- **The panel** is transit. Invoked by hotkey, used for one action, dismissed. Every
  pixel of chrome here is a tax paid on every invocation.
- **Settings and the History browser** are dwelling. Opened deliberately, occasionally,
  to organize and configure. Density and explanation are welcome here.

## Product Purpose

A native macOS clipboard manager that keeps everything you copy (text, images, URLs,
code, colors, files) and returns it through a screen-edge sliding panel. Local-first
by default: no accounts, no analytics, optional sync through the user's own iCloud.

Success is invisibility. The product has won when a user stops thinking about it and
their hands simply know the hotkey, and when nothing they ever copied feels lost.

## Brand Personality

Warm and crafted. Native to the point that it feels like it shipped with the OS, with
the small evidences of care that tell you a person made it: things that animate because
the state changed, controls that reveal themselves when relevant, counts and previews
that answer a question before it is asked.

Voice: plain, specific, calm. Explains consequences before destructive actions. Never
exclaims, never jokes, never apologizes at length. Copy is written the way Apple's own
utilities write, minus the legalese.

Personality is spent at moments, not spread across pages. Reliability carries the rest.

## Anti-references

Hard nos. Each of these is a way this specific product loses trust.

- **A web app in a window.** Custom controls where native ones exist, non-native
  toggles, hover states that feel like CSS, invented affordances for standard tasks.
  The fastest way for a Mac utility to feel untrustworthy.
- **Decorative glassmorphism.** Pastel uses Liquid Glass, which makes this the easiest
  trap to fall into. Glass is the panel's material because the panel floats over
  arbitrary desktop content. It is not a style to apply to cards, chips, and popovers.
  Glass on glass is always wrong here.
- **Consumer-app celebration.** Confetti, bouncy or elastic springs, mascots,
  exclamation marks. A clipboard paste is a routine act performed hundreds of times a
  day; anything that celebrates it becomes unbearable by the tenth repetition.
- **A dense developer tool.** Monospace as a default, gray-on-gray micro-type, terminal
  aesthetics, information packed at the expense of comfort. Pastel's users include
  developers but the product is not for developers specifically.

## Design Principles

1. **The tool disappears into the paste.** The panel is measured by how little of it
   the user has to look at. Chrome in the panel must justify its cost against every
   single invocation, not against the one time it is useful.

2. **Native first, invention last.** Reach for the platform control, the platform
   idiom, the platform material. Invent only where the platform has no answer, and
   then invent something that looks like it could have been the platform's answer.

3. **State is structural, not decorative.** A state a user navigates by must be
   signalled in a way content cannot counterfeit. Selection is an outset ring in the
   layout gutter precisely because content cannot paint outside its own frame; a colored
   fill was ambiguous with a color swatch. Prefer geometry over color for state.

4. **Answer before the user commits.** Show the count before the delete, the preview
   before the paste, the refusal before the drop completes. The interface should make
   the outcome knowable while it is still free to change course.

5. **Two speeds, one vocabulary.** The panel is fast and spare, Settings is calm and
   explanatory, and they share every token, chip, card, and control. A component that
   looks different in the two places means one of them is wrong.

## Accessibility & Inclusion

No requirements beyond platform defaults were specified. Follow them:

- Type on system text styles rather than fixed point sizes, so system text sizing works.
- Standard controls carry their own accessibility semantics; do not replace them with
  gesture-only affordances.
- Never make color the sole carrier of meaning. Selection and state pair color with
  geometry (see Principle 3).
- Keep motion short (under 250ms) and tied to state change, so the interface remains
  usable to anyone who finds animation distracting.

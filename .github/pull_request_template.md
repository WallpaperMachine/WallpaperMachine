<!-- Thanks for sending a change. CONTRIBUTING.md has the full working agreement. -->

## What and why

<!-- What changes for someone using or working on the app, and why. Link the issue: Fixes #123. -->

## Verification

<!-- The commands you ran and what they showed; what you checked by hand, and what you did not. -->

- [ ] `python3 scripts/test.py` passes
- [ ] Targeted checks for the area touched (`python3 scripts/check_renderer.py` for renderer or scene work)
- [ ] Visible changes: before and after screenshots below, or "not checked visually"

## Checklist

- [ ] One coherent change with a Conventional Commit subject (`fix(scene): …`, `feat(downloads): …`)
- [ ] Tests for behavior a plausible bug would break
- [ ] Generated files regenerated, not hand-edited (`project.yml` → Xcode project; bridge bindings through `scripts/build.py`)
- [ ] The document that owns the behavior updated
- [ ] No build output, secrets, private wallpapers or personal paths in the diff

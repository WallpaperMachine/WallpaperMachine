# Versioning and releases

Version numbers, the pipeline that publishes a build, the notes it writes, and how
the in-app updater consumes it. Build mechanics live in [build.md](build.md).

## Source of truth

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
[`project.yml`](../project.yml) are the version of both the app and the
lock-screen extension; the two targets carry identical values. The embedded
`MediaRemoteAdapter` framework declares the same `CURRENT_PROJECT_VERSION`,
because XcodeGen would otherwise generate its own default of 1 there.
`scripts/bump_version.py` also rewrites the same two keys in the committed
`WallpaperMachine.xcodeproj/project.pbxproj`, so the generated project stays
in sync without anyone running `xcodegen`, and running it produces no diff.
Change the version through the script or the Version workflow, never by editing
one of the two files alone. The panel reads the bundle's version, so Settings →
About and every GitHub report show the released number with no other edit.

`MARKETING_VERSION` is a strict `x.y.z` semantic version.
`CURRENT_PROJECT_VERSION` is an integer build number, incremented by one on every
bump.

## Release specs in commit messages

Push to `main` with a line of exactly this form — as the subject, a body line, or
a squash-merge title — to trigger a bump:

| Spec | Effect on `0.1.0` |
|---|---|
| `release: patch` | `0.1.1` |
| `release: minor` | `0.2.0` |
| `release: major` | `1.0.0` |
| `release: 1.2.3` or `release: v1.2.3` | sets `1.2.3` exactly |

Matching is case-insensitive and anchored to a whole line. An explicit `x.y.z`
must not move the version backwards.

If a single push contains several `release:` lines, an explicit `x.y.z` wins;
otherwise the highest of `major` > `minor` > `patch` is used. A push with no
`release:` line prints `No release: spec in commit message; skipping.` and does
nothing.

Bump the same way locally:

```sh
python3 scripts/bump_version.py --spec patch            # dry run, prints old -> new
python3 scripts/bump_version.py --spec patch --apply    # writes both files
```

`--message` / `--message-file` scan a commit message instead of taking a spec
directly; `--ci` reads `RELEASE_SPEC` or the GitHub event payload. With `--apply`
omitted nothing is written, which makes it safe to inspect a planned bump.
`scripts/bump_version.py` is covered by `scripts/tests/test_bump_version.py`,
which runs as part of `python3 scripts/test.py`.

## Release notes and the changelog

A version's notes are written once, when it is cut, into its
[`CHANGELOG.md`](../CHANGELOG.md) section. The app bundles that file. The
release page repeats the current section, so the history in the app and the
page cannot disagree. [`scripts/release_notes.py`](../scripts/release_notes.py)
does both halves. `gh release --generate-notes` is not used: with no pull
requests in the history it produces a bare compare link, which is all the
thirteen releases through `v0.5.0` ever said before they were deleted.

A published section is both languages, in this order, and nothing else at `###`:

```markdown
### English

One or two sentences on what the release means, omitted when the lists say it.

#### New

- One change, one line

### 简体中文

同样的一两句。

#### 新增

- 同一变更的简体中文

**Full changelog**: https://github.com/owner/repo/compare/v0.1.0...v0.2.0
```

Category headings inside a language are `####`. The compare link follows both
blocks; the app ignores it. The headings are:

| Section | `####` English | `####` 简体中文 |
|---|---|---|
| breaking | Breaking changes | 不兼容变更 |
| new | New | 新增 |
| improved | Improved | 改进 |
| fixed | Fixed | 修复 |

### Written by the release-notes model

With `--ai` the commits between two version tags go to a language model that
writes them up for users — what they can do now, what works better, what no
longer goes wrong — in English and in Simplified Chinese, the same changes in
both, merging commits that describe one change and leaving internal work out.
The release pipeline always passes `--ai`.

| Environment | Default | Meaning |
|---|---|---|
| `RELEASE_NOTES_API_KEY` | none; required | Key for the gateway. A secret: it lives in the environment of one command or in the repository secret of the same name, never in a file. |
| `RELEASE_NOTES_API_BASE` | `https://sub2api.moraxcheng.me` | Anthropic Messages API gateway; a base that already ends in `/v1` is accepted |
| `RELEASE_NOTES_MODEL` | `claude-opus-5-5` | The model that writes the notes |

The model reads every commit in the range, newest first, except CI's own
`chore: bump version to x.y.z`. Commits of the user-visible types below bring
their body, cut at 1,500 characters, until 120,000 characters of bodies are
spent; `docs`, `test`, `chore`, `ci`, `build` and `style` commits bring only their
subject. Commit messages are therefore the source of the notes: write them for
the reader [conventions.md](conventions.md#commits-and-pull-requests) describes.
The instructions also carry the project's rules on claims, because CI commits the
notes without review: no energy, battery or power-saving claims, nothing called
fully supported or fully compatible, and opt-in features (Native Metal, native
video, content pacing, on-demand scene idle, the animated lock screen) keep their
optional, experimental or off-by-default qualifier in both languages. Places in
the app are named the way the panel names them (`Settings` / `设置`, and the
same for General, Appearance, Performance, Playback, Library & Steam, Discover,
Installed, About and Lock screen).

It answers with JSON. `summary` is `{"english", "chinese"}`. Each of `breaking`,
`new`, `improved` and `fixed` is a list of the same pair, one object per change,
so the two languages cannot drift in length. The script checks that and renders
the shape above: `### English`, then `### 简体中文`, categories at `####`, then
the compare link. A Chinese string must contain Chinese characters and must not
be a copy of the English; an English string must contain Latin text. Whitespace
is collapsed and list or heading markers are stripped, so no entry can open a
changelog section of its own. A reply that is not that JSON, uses the old
English-only shape, omits a language, carries other fields or an HTML comment
(the boundary marker below), or was cut off at the output-token limit stops the
run. A range without commits is reported in both languages as having no
user-visible changes, without a request. The request streams, so a slow answer
never trips a proxy's time-to-first-byte limit, and names its own `User-Agent`,
because Cloudflare in front of the gateway refuses urllib's default one (error
1010). A connection that goes quiet for 120 seconds, or a reply still running
after 600, stops the run: the Version job holds its branch lock while it waits.
Nothing is retried; a failed run is re-run.

### Listed from the commits

Without `--ai` the commits are listed in English, read through the
`type(scope): subject` convention in [conventions.md](conventions.md). It is
offline and free, and it is a developer preview: for inspecting a range, for
tests, and it is how every section up to `0.5.0` was first written. It is not
published. `--release-body` and `--changelog --apply` refuse notes that are not
`### English` then `### 简体中文`.
Publication validates every bundled historical section, not just the current
release. Each `##` heading must be the `x.y.z` token `AppReleaseHistory` accepts
(optional `v`/`V`, three 64-bit integer components, no leading zeros), and each
section needs actual prose in both languages and matching bullet counts.
`## Unreleased`, duplicate versions, an overflow, a prerelease suffix, a leading
zero, or a non-version `##` line inside notes fails
`--release-body`, `--changelog --apply` and `--rebuild-changelog --apply`. Those
headings are not kept and not dropped. The app rejects the whole file when it
sees one, and publishing does not invent a placeholder release for them.
Headings and compare links do not count as translated content.
`--rebuild-changelog --apply` also refuses to replace the file if rebuilding
would introduce an English-only section; translate missing history before applying.

| Commit type | Section |
|---|---|
| `feat` | **New** |
| `fix` | **Fixed** |
| `perf` | **Performance** |
| `!` suffix or a `BREAKING CHANGE:` trailer | **Breaking changes** |
| `docs`, `test`, `chore`, `ci`, `build`, `style` | counted in one closing line |
| anything else, including non-conventional subjects | **Other changes** |

Nothing is dropped silently: a subject the convention does not recognise is
listed rather than hidden, and the only commit removed outright is CI's own
`chore: bump version to x.y.z`. A subject longer than 140 characters is cut at a
word boundary; the linked commit still carries every word.

### Commands

```sh
python3 scripts/release_notes.py                               # English listing, not for publish
python3 scripts/release_notes.py --ai --tag v0.6.0 --to HEAD   # bilingual notes, before the tag exists
python3 scripts/release_notes.py --tag v0.6.0 --release-body --ai --output notes.md
python3 scripts/release_notes.py --ai --changelog --apply      # write one bilingual section
python3 scripts/release_notes.py --rebuild-changelog --apply   # a section for every tag, recorded ones kept
```

A local `--ai` run needs `RELEASE_NOTES_API_KEY` exported for that command only.
`--previous` overrides the tag the range starts after; by default it is the
newest released version below the target that the range's end descends from, so a
gap in the numbering resolves correctly.

`--release-body` is the release page. It reuses the version's `CHANGELOG.md`
section when that section is already bilingual, and does not call the model
again. A hand-pushed tag with no section is written once, by the model when
`--ai` is set, into the working-tree `CHANGELOG.md` before anything is built, and
the release page is that stored text: one generation, so the bundled history and
the page cannot diverge. English-only or malformed current notes fail the run
instead of being published. Then `<!-- release-notes-end -->`, the install,
checksum and requirement footer, and every commit in the range folded into a
`<details>` list, so whatever the notes leave out is still on the page. The
marker is a contract: the updater shows everything above it and nothing below.
The What's New window reads the bundled changelog, not that footer. A launch
whose bundled history has no section for the installed version does not record
that version as announced, so a later bundle can still show the window. See
[After an update](features/control-panel.md#after-an-update).

Inserting a section is idempotent — rerunning replaces the section for that
version instead of duplicating it. `--rebuild-changelog` writes a section for every
version tag but keeps each section `CHANGELOG.md` already holds word for word, so
the model's notes survive; only missing ones are listed from the commits, in
English, and that listing is not a publishable section. It never calls the model,
and refuses `--ai`. `CHANGELOG.md` is written with `--apply`, and also when
`--release-body` has to generate the current section. With `--changelog`, nothing
is generated unless `--apply` or `--output` is given, so that dry run never calls
the model; a plain `--ai` run prints the model's notes and does make the request.
`scripts/tests/test_release_notes.py` covers classification, rendering, changelog
ordering, reuse and rebuilding, and range resolution against a real throwaway
repository; the model path against a fake gateway (what the model reads, how its
streamed reply is parsed and rendered, each reply that must stop a release,
including a missing language); publishing (recorded bilingual notes reused with
no second request, generated notes stored once and used unchanged, English-only
notes refused, and `## Unreleased`, a heading inside notes, a prerelease token
or a leading zero refused by the publish and rebuild paths rather than kept or
dropped); and the real HTTP request against a local server (headers, the
gateway's refusal message, the deadline).

## Workflows

Five workflows in `.github/workflows/`. Version, Build and Release grant
`contents: write`; Build's publish job also needs `id-token: write` and
`attestations: write` for its provenance attestation, and both callers pass those
through, together with the repository's secrets (`secrets: inherit`). Warm caches
only reads. Supporters writes only `README.md`, with `contents: write`, and reads
Version's runs with `actions: read`. The macOS setup Build and Warm caches share
lives in one composite action,
[`.github/actions/prepare-build`](../.github/actions/prepare-build/action.yml).

**The one secret.** `RELEASE_NOTES_API_KEY` is a repository secret, which only a
repository administrator can set or replace: `gh secret set RELEASE_NOTES_API_KEY`
in a checkout prompts for the value and writes it to the repository `origin`
points at. Version reads it for every bump; Build reads it only for a tag without
a `CHANGELOG.md` section.

### Version (`version.yml`)

Runs on every push to `main`, and on demand from **Actions -> Version -> Run
workflow** with a `spec` input. On an `ubuntu-latest` runner it:

1. checks out with full history;
2. runs `python3 scripts/bump_version.py --ci --apply`;
3. has the release-notes model write the new version's bilingual section into
   `CHANGELOG.md` with `scripts/release_notes.py --to HEAD --ai --changelog
   --apply` — `### English` then `### 简体中文`. The tag does not exist yet, so
   the range ends at `HEAD`. Without the secret, or when the model fails or omits
   a language, the job stops here: nothing is committed or tagged, and re-running
   the failed job retries the same bump;
4. if anything changed, refuses to continue when the target tag already exists on
   `origin`, then commits `project.yml`,
   `WallpaperMachine.xcodeproj/project.pbxproj` and `CHANGELOG.md` as
   `chore: bump version to x.y.z`, tags `vx.y.z`, and pushes branch and tag
   atomically as `github-actions[bot]`;
5. calls the Build workflow directly for the tag it just pushed.

Step 5 is not redundant. **A tag pushed with `GITHUB_TOKEN` never starts another
workflow**, so the tag-triggered Release workflow would never fire for a
CI-produced tag; without the direct call, a bumped version would be tagged but
never published.

The bump job holds a `version-<ref>` concurrency group only while the bump commit
is produced. A workflow-wide group would keep the lock through the macOS build,
and because GitHub retains only the newest pending run, a queued `release:` push
could be replaced by a later ordinary push and silently lost.

The workflow needs permission to push to `main`: `contents: write`, and branch
protection must allow GitHub Actions.

### Build (`build.yml`)

`workflow_call` only, with a required `tag` input. It is the single place a
publishable artifact is produced, called by Version for CI-produced tags and by
Release for hand-pushed ones.

The licensing gate that used to fail this workflow's first step was removed for
1.0.0 by maintainer decision; the questions in [../LICENSING.md](../LICENSING.md)
are still open. It runs four jobs. `app-icon` compiles the app icon on a
`macos-26` runner in about a minute. `build` then runs on `macos-15` (the oldest
runner that carries Xcode 26, whose Homebrew bottles set the published app's
minimum macOS) while `test` runs on `macos-26`, 150-minute timeout each, so the
test gate adds no time on top of the Release build. `publish` runs on
`ubuntu-latest` only after both succeed, so a published binary has passed the same
gate a change has to pass.

**Why the icon is compiled apart.** On macOS 15, Xcode 26's `actool` exits 255 on
most attempts to compile the Icon Composer `AppIcon.icon`: a probe on the
`macos-15` image ran it three times with each installed Xcode from 26.0.1 to 26.3
and 6 of 30 attempts succeeded, while the same runs on `macos-26` all succeeded
and the asset catalog alone compiled 8 of 8 times on `macos-15`. The 1.0.1 build
failed on exactly that step. `app-icon` runs `python3 scripts/build.py
--compile-app-icon DIR`, which calls `actool` with Xcode's own arguments for this
target, and hands `Assets.car`, `AppIcon.icns` and the partial Info.plist to
`build` as the `app-icon-<tag>` artifact.

**`build`**

1. checks out the tag with full history, which the notes need;
2. writes the release body with `scripts/release_notes.py --release-body --ai
   --built-from "$(git rev-parse HEAD)"` before anything is built. The current
   section must already be bilingual (`### English`, then `### 简体中文`); that
   text is reused and the model is not called again. A hand-pushed tag with no
   section is written once, into the working-tree `CHANGELOG.md`, and that same
   text is the release page, so the bundled history matches the page. English-only
   or malformed current notes fail here, in seconds, rather than after the macOS
   build;
3. runs `prepare-build` (below) and downloads the `app-icon-<tag>` artifact;
4. runs `python3 scripts/build.py --configuration Release --app-icon DIR`, which
   leaves `AppIcon.icon` out of the Xcode build, puts the compiled icon and catalog
   into the bundle with their Info.plist keys and re-signs it, then
   `python3 scripts/package.py --configuration Release --require-deployment-target`,
   which fails if a bundled library needs a newer macOS than the deployment target.
   Packaging proves the disk image, not the build tree: it mounts the image
   read-only and requires `app.wallpapermachine` at the bundle's version, a
   passing `codesign --verify --deep --strict`, the `Applications` link and the
   window layout, then writes the `.sha256` sidecar
   ([build.md](build.md#packaging-and-installing));
5. matches the image to the tag: it must be named
   `WallpaperMachine-<tag without v>-arm64.dmg`, and its checksum is echoed into the
   job summary;
6. hands the image, its sidecar and the notes to `publish` as the
   `release-<tag>` artifact.

**`test`** runs `prepare-build`, `python3 scripts/build.py --renderer-only` for the
renderer and the generated bridge, then `python3 scripts/test.py`, which builds the
Debug app, icon included, and its tests itself.

When either macOS job fails it uploads its full tool logs (`artifacts/build/`, and
for `test` also `artifacts/tests/*.log`) as `build-logs-<tag>` or `test-logs-<tag>`,
kept 14 days: the job output is only the scripts' filtered summary.

**`publish`**

1. downloads the artifact and checks the image against its `.sha256` sidecar;
2. attests build provenance for the image with
   `actions/attest-build-provenance`;
3. writes the update manifest `WallpaperMachine-update.json` from the tag, the
   notes and the image with `scripts/update_manifest.py`
   ([below](#what-the-in-app-updater-expects));
4. publishes the image, its sidecar and the manifest with
   `scripts/publish_release.py`.

Step 5 of `build` is the guard that the bump actually reached the build:
`scripts/package.py` names the image from the bundle's
`CFBundleShortVersionString`, so a mismatch means the published tag and the
built version disagree and the job fails instead of publishing the wrong binary.

**`prepare-build` and the caches.** The composite action selects the newest
non-beta `/Applications/Xcode_26*.app`, `brew install --quiet`s the
XcodeGen/CMake/renderer package set with `dav1d` and `ccache`, and restores three
`actions/cache` entries. Every key carries the runner's macOS (`<os>` below is
`macos-15` or `macos-26`), because bottles, the FFmpeg keg and compiled objects
differ between releases; `build` and `test` therefore keep separate entries.

| Cache | Path | Key | What a hit saves |
|---|---|---|---|
| LGPL FFmpeg | `/opt/homebrew/Cellar/mwe-ffmpeg` | `mwe-ffmpeg-<os>-<dav1d version>-<hash of Formula/mwe-ffmpeg.rb>` | the ~3 minute source build; the action restores the keg's `opt` link and `scripts/install_ffmpeg.py` finds the keg current |
| C++ objects | `~/.ccache` | `ccache-<os>-<run>`, restored by the `ccache-<os>-` prefix | recompiling the scene engine. A checkout gives every file a new mtime, so CMake rebuilds the whole engine even from a restored build tree; ccache hashes content and returns the previous objects |
| Renderer | `~/.cargo/registry`, `~/.cargo/git`, `upstream/renderer/target` | `renderer-ccache-<os>-<hash of Cargo.lock, rust-toolchain.toml, provenance.json>`, restored by prefix | crate downloads, and Rust compilation while the nightly toolchain is unchanged |

The `CMAKE_<LANG>_COMPILER_LAUNCHER=ccache` variables only take effect on a build
tree's first CMake configure, which is why the renderer key's prefix changed when
they were introduced: no tree configured without them is ever restored. Each
macOS job prints `ccache --show-stats` at the end; hits against misses there is
the evidence the cache worked. The toolchain is an unpinned `nightly`
(`upstream/renderer/rust-toolchain.toml`), and a new nightly invalidates every
compiled crate, so the Rust half of the renderer build is only reused between
builds on the same nightly.

**What the attestation does and does not say.** Its SLSA predicate is built from
the run's OIDC claims: `resolvedDependencies[0]` is `git+<repo>@<claims.ref>` with
`digest.gitCommit = claims.sha`
([`actions/toolkit`](https://github.com/actions/toolkit/blob/main/packages/attest/src/provenance.ts)).
For a Version-produced tag those claims describe the push to `main` that carried
the `release:` line — the revision *before* the bump commit the tag points at,
because Build runs as a `workflow_call` inside that same run. So the attestation
binds the image's digest to this repository, this workflow, this builder and
this run; it does **not** identify the revision the image was built from. That
revision is recorded separately in the release body as
``Built from `vx.y.z` at `<sha>` ``, and anyone can check it with
`git rev-parse vx.y.z^{commit}`. A hand-pushed tag going through Release does not
have the discrepancy, because there the triggering ref is the tag itself.

**How `scripts/publish_release.py` publishes.** It is a separate script rather
than inline shell because its two rules are the ones a release pipeline gets
wrong, and `scripts/tests/test_publish_release.py` exercises both, including a
failed upload and reversed completion order:

- **Drafts first, live releases refused.** No release for the tag: create a draft,
  upload, then clear the draft flag. A draft already there (an earlier attempt
  that died): finish it. A release already *published*: refuse and fail the job.
  `gh release upload --clobber` deletes an existing asset before writing its
  replacement, so re-running against a live release would take the download away
  and only restore it if the upload succeeded — reopening the exact window the
  draft-first order closes. A failure anywhere before the last command leaves a
  draft, which neither the API's `releases/latest` nor github.com's
  `releases/latest/download/…` returns.
- **Latest cannot go backwards.** Both callers hold a `publish-<tag>` concurrency
  group, which locks per tag, not per repository, so `v0.6.0` and `v0.7.0` can
  build at the same time and finish in whatever order their caches allow. The
  script therefore passes `--latest` only when no greater public, non-prerelease
  version exists, and `--latest=false` otherwise; an older build finishing last
  cannot take Latest and start offering users the wrong version. The residue is
  the interval between reading the published versions and writing the flag — two
  consecutive API calls, rather than a whole macOS build.

### Warm caches (`warm-caches.yml`)

GitHub evicts a cache entry nobody has read for seven days. Twice a week (and on
demand from **Actions -> Warm caches -> Run workflow**) this runs `prepare-build`
and `python3 scripts/build.py --renderer-only` on `main`, once on `macos-15` and
once on `macos-26`, which reads every entry Build uses and saves a fresh C++ object
cache for each, so a release after a quiet week still starts warm. Caches saved on
`main` are readable from every ref, including the tags Release builds. It
publishes nothing.

### Supporters (`supporters.yml`)

Keeps the [README's Supporter list](../README.md#thank-you-to-every-supporter) in
step with the website's [sponsor wall](https://www.wallpapermachine.app/#sponsors).
Every hour (and on demand from **Actions -> Supporters -> Run workflow**) it runs
`python3 scripts/update_sponsors.py` on `main`, which reads the wall's JSON from
`https://www.wallpapermachine.app/api/sponsors` (the website's
`src/worker/sponsors.ts`) and rewrites the block between the `supporters:start`
and `supporters:end` markers: the website's picture of the wall
(`/sponsors/wall`, drawn by its `src/worker/sponsor-card.ts`), linked to the wall,
with every listed name and the count in its alt text. The picture's address carries
the `version` the JSON gives (`?v=`), which changes whenever the wall does, names,
pictures and count alike, so GitHub's image proxy fetches it again then and only
then. When the block changed it commits `README.md` as
`docs(readme): update the Supporter list` and pushes to `main`, starting again from
the new `main` if that moved. It skips the hour while a Version run is queued or
running, because Version's push of its bump commit does not retry. A wall that
can't be read fails the run and leaves `README.md` as it was. Names are escaped, so
a Supporter's chosen name never becomes a link, an image or markup; edit the list's
wording in the script, not between the markers, where edits are overwritten.

### Release (`release.yml`)

Triggered by pushing a `v*.*.*` tag by hand. It only calls Build with
`github.ref_name`, sharing the `publish-<tag>` concurrency group with Version's
publish job so one tag is never built twice at once. A hand-pushed tag has no
`CHANGELOG.md` section unless one was committed before tagging. Build then asks
the model once, writes that exact section into the working tree before the app
is built, and publishes that same text. A section that is present but not
bilingual fails the build; it is not rewritten.

## What the in-app updater expects

**Settings -> About** is the in-app update surface. It checks the repository's
latest GitHub Release and, after confirmation, downloads the disk image and
restart-installs the app from it. **Check for Updates…** in the application menu
opens that section and starts the same check.

A check reads the release's update manifest, not the REST API. Anonymous API
requests are limited to 60 an hour per public IP, shared with every app and device
behind that address (a NAT, VPN or proxy exit can use it up without this app), and
a network that had used it up left the updater locked out.
`https://github.com/WallpaperMachine/WallpaperMachine/releases/latest/download/WallpaperMachine-update.json`
is a release asset download: github.com redirects it to the file on the release
marked Latest (drafts never resolve), and it does not count against that limit. The
manifest is the release object in the API's shape (`tag_name`, `html_url`,
`prerelease`, `body`, and one asset with `browser_download_url`, `size` and a
`sha256:` `digest`), written by `scripts/update_manifest.py` in Build's `publish`
job, so `GitHubReleaseParser` reads both. Its name is
`AppUpdateConfiguration.manifestName`; renaming it changes both sides at once.
The API is asked only when the Latest release has no manifest (404: every release
up to 1.0.2) or an unreadable one; a manifest that is rate-limited, fails or
redirects off the GitHub hosts below is an error, not a reason to spend an API
request.

The app also checks on its own, once the library has loaded (whether or not it
loaded cleanly) and every six hours after, since a menu-bar app can run for weeks.
When the copy can be replaced in place, a newer version is downloaded in the
background and one alert offers **Restart to Update** or **Later**; elsewhere the
alert offers **View Update**, which opens About, because a download there opens
the image in Finder. Each version prompts once per launch. After **Later**, the
status menu keeps **Restart to Update to x.y.z** (or **WallpaperMachine x.y.z
Available…**) until the app restarts. This path ships from 1.0.1; 1.0.0 only
checks silently at launch and shows the result in About. The install runs the
*running* version's code, so the staged replacement and the writability check below
apply from 1.0.2 on: 1.0.1 still deletes the old app before copying the new one and
offers in-place installs to any copy under an Applications folder. Up to 1.0.2,
**Restart to Update** (alert, status menu or About) also hangs: it quits from inside
a main-queue job, where AppKit's `.terminateLater` wait never runs the main-actor
shutdown task, so the window closes and nothing happens until the user quits from
the status menu, after which the new version installs and opens. Later versions
quit and show the alert from the main run loop (`AppUpdateStore.performOnMainRunLoop`).

The contract it relies on:

- the repository is `WallpaperMachine/WallpaperMachine`
  (`AppUpdateConfiguration.repository`). 1.0.0 and older still ask for
  `bobbyhuang-dev/WallpaperMachine` and reach it only through GitHub's rename
  redirect, so never create a repository at that old path;
- the release is not a draft or prerelease, and its tag parses as `vx.y.z` (no
  prerelease suffixes, no `nightly`);
- the asset named exactly `WallpaperMachine-<x.y.z>-arm64.dmg` — what
  `AppUpdateConfiguration.assetName(for:)` returns and what `scripts/package.py`
  produces — is preferred, then another product disk image naming `arm64`, then
  any product disk image. Only `.dmg` assets qualify: the `.sha256` sidecar, zips,
  feeds and blockmaps are never downloaded;
- downloads are restricted to HTTPS on `github.com`, `api.github.com` and the
  `objects`, `release-assets` and `github-releases` hosts under
  `githubusercontent.com` (GitHub now redirects assets to `release-assets`), for the
  manifest as for the image, and the image's `sha256:` digest (from the manifest,
  or from GitHub when the API is asked) is verified;
- the image is attached read-only and out of sight (`hdiutil attach -nobrowse
  -readonly -noautoopen`) at a private mount point, its single
  `WallpaperMachine.app` is copied out with `ditto` without following the
  `Applications` link, the image is detached whatever happens, and the copy must
  carry `app.wallpapermachine` and its executable before the restart-install
  replaces the running app;
- the restart-install waits for the app to exit, copies the new app beside the old
  one as a hidden `.WallpaperMachine.app.update-<pid>`, renames the old one aside,
  moves the new one in and only then deletes the old one. Any failed step puts the
  old app back, removes the partial copy and reopens whichever version is in place,
  so a failed install relaunches the previous version rather than leaving no app;
- the installed copy must live in `/Applications` or `~/Applications`, and this
  user must be able to write both the bundle and its folder. A copy anywhere else,
  or one a standard account cannot replace (for example installed by an
  administrator), opens the downloaded image after the download, so Finder shows its
  drag-to-Applications window for a manual install;
- releases are signed with the project certificate
  ([build.md](build.md#release-signing)), so the replacement keeps the designated
  requirement and macOS keeps the app's privacy permissions. Updating from an
  ad-hoc build (1.0.1 and older) asks for them once more;
- the release body is shown as **What's new** in the About card. Headings become
  section titles, bullets become lines, Markdown emphasis, code fences and commit
  links are reduced to their text, the compare link is dropped, and everything
  from `<!-- release-notes-end -->` onwards is ignored. A body with nothing to
  say produces no card rather than an empty one.

A completed check has two normal no-update outcomes: an existing latest release
at or below the running version is **Up to date**; a repository without an
eligible published release shows **No published update is available yet. You
can keep using this version.** Both offer **Check Again**, not an error-style
Retry or manual-install recovery. A fresh check clears any previous available
release and its notes.

GitHub also returns 404 for inaccessible repositories. When `/releases/latest`
returns 404, the client checks the repository endpoint and requires a successful,
valid repository response before treating the release as absent. Repository
404s, failed requests and malformed responses stay errors; they are never
reported as **Up to date**. These paths, and the manifest's, are covered with
isolated URLSession fixtures, without contacting GitHub.

Checks run at launch, every six hours and on **Check for Updates**. With a
manifest a check spends no API request; without one it spends one (two when
`/releases/latest` is 404). A 403 with `x-ratelimit-remaining: 0`, or a 429, from
either source is a distinct `rateLimited` error, not a network failure: About says
the hourly limit is used up and shows the reset time from `x-ratelimit-reset` (or
`retry-after`). Until that time every check, automatic or **Retry**, fails locally
without a request, so retrying can't keep the shared quota exhausted.

With no matching asset the app falls back to opening GitHub Releases for a manual
update. Renaming the image, publishing a prerelease, or attaching only a zip
silently breaks automatic updates; `Tests/Unit/GitHub/AppUpdateTests.swift`
pins this behavior, including the exact published image name and an install
from a real disk image.

## Checklist for a release

1. Land the change on `main` with a `release:` spec line, or run the Version
   workflow with a spec.
2. Confirm the Version run committed `chore: bump version to x.y.z` with the new
   `CHANGELOG.md` section and pushed `vx.y.z`. Read the section: it is `### English`
   then `### 简体中文`, the model wrote both, and it is what the bundled history
   and the release page will show.
3. Confirm the called Build run passed the test gate, verified the mounted
   image, and published `WallpaperMachine-x.y.z-arm64.dmg` with its `.sha256`
   sidecar, `WallpaperMachine-update.json` and a provenance attestation. The
   manifest's `digest` must equal the sidecar's checksum:
   `curl -sL https://github.com/WallpaperMachine/WallpaperMachine/releases/latest/download/WallpaperMachine-update.json`.
4. Read the release body on the page: it should be the current `CHANGELOG.md`
   section, both languages, with the folded commit list below the install footer,
   not a bare compare link, and the `Built from` line must match
   `git rev-parse vx.y.z^{commit}`. For a hand-pushed tag the section in the
   built app is the text Build wrote into the working tree; it is the same text
   as the page.
5. Confirm Latest points at the highest published version. Re-running Build for a
   tag that is already published fails by design; if a published release is
   genuinely wrong, delete it deliberately rather than re-running.
6. Open the published image on a Mac: the window shows the app beside
   Applications over the background, the drag installs it, and the first launch
   goes through System Settings → Privacy & Security. Then run the manual smoke
   pass in [testing/manual-smoke.md](testing/manual-smoke.md) against that copy
   and record it in [testing/verification-log.md](testing/verification-log.md).

CI publishes the disk image although the questions in
[../LICENSING.md](../LICENSING.md) remain unresolved. That file also records the intended Supporter
model (a free Developer ID signed and notarized download, and a one-time
Supporter purchase for a sponsor place and priority support, under the GPL
with corresponding source alongside). Neither Developer
ID signing nor notarization exists in this pipeline yet; `scripts/package.py`
signs with a self-signed certificate that only keeps the designated requirement
stable ([build.md](build.md#release-signing)), a provenance attestation records
who built an artifact rather than who vouches for it, and neither is license
clearance.

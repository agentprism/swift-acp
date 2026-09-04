# Repository Guidance

## Development Standards

- Use Swift 6.3 or newer for new and refactored implementation code. Prefer structured concurrency, actors, typed errors, and current standard-library APIs over compatibility shims.
- Follow `.swift-format` and the strict `.swiftlint.yml` configuration. Format changed Swift files with `swift format --in-place --configuration .swift-format <paths>`, then run `swift package --allow-writing-to-package-directory swiftlint --strict` before committing.
- Do not add entries to `.swiftlint-baseline.json`. New and changed code must pass the configured rules; remove inherited baseline entries when the corresponding code is refactored.
- Avoid deprecated APIs and do not introduce force unwraps, force tries, implicitly unwrapped optionals, or lint suppression comments.
- Treat the root `schema.json` as the ACP model source of truth. Refresh it from `https://github.com/agentclientprotocol/agent-client-protocol/releases/latest/download/schema.json` before protocol-model updates.
- Keep protocol extensions vendor-neutral: preserve `_meta` and support underscore-prefixed extension methods without embedding vendor-specific method names or payload semantics.
- Keep tests behavioral and meaningful. Do not add tautological tests that merely repeat implementation logic or assert language/library behavior.

## Release Workflow

- Before a release, refresh the branch state with `git status --short --branch`, confirm the target branch is `main`, and check existing tags/releases with `git tag --sort=-v:refname`, `git ls-remote --tags origin`, and `gh release list --repo agentprism/swift-acp --limit 20`.
- Validate the final tree before tagging. At minimum run `git diff --check` and `swift test`.
- Commit all release changes together when the user asks to release. Include source, tests, docs, and updated reference submodule pointers in the same release commit when they are part of the same upstream sync.
- Push the release commit to `origin main` before creating the release tag.
- Use semantic version tags prefixed with `v`. If there are no existing tags, start at `v0.1.0`; otherwise increment the most appropriate component for the release scope.
- Create an annotated git tag from the pushed commit, then push the tag:
  - `git tag -a vX.Y.Z -m "vX.Y.Z"`
  - `git push origin vX.Y.Z`
- Publish a GitHub release with `gh release create`, using the tag as both the tag and title.
- Include a changelog in the release notes. Summarize user-visible changes, compatibility notes, refreshed upstream references, and validation performed.
- After publishing, verify the release exists with `gh release view vX.Y.Z --repo agentprism/swift-acp`.

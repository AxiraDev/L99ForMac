# Maintainer guide

## See whether people find the app

- **Stars:** visible at the top of [the repository](https://github.com/AxiraDev/L99ForMac). Stars show interest, not active use.
- **Downloads:** each file in [Releases](https://github.com/AxiraDev/L99ForMac/releases) has a download count. The README badge totals release-asset downloads, including source archives and repeat downloads; it is not a unique-user counter.
- **Visitors and clones:** open [Insights → Traffic](https://github.com/AxiraDev/L99ForMac/graphs/traffic). GitHub shows traffic from the last 14 days to people with push access. [GitHub documentation](https://docs.github.com/en/repositories/viewing-activity-and-data-for-your-repository/viewing-traffic-to-a-repository).
- **Feedback:** use Issues and pull requests for user reports and contributions.

The application has no analytics SDK, heartbeat, usage reporting, or automatic network request for these statistics. The project website also has no analytics or tracking scripts.

## Publish an update

1. Update the app version, release notes, and download links on the website/READMEs.
2. Run the relevant checks and build the app, source archive, and DMG.
3. Audit the source and verify the release artifacts. Exclude user profiles and research material.
4. Create a GitHub release for the matching tag and commit. Keep unfinished releases marked as prereleases.
5. Attach the DMG, corresponding source ZIP, optional application ZIP, and `SHA256SUMS.txt`. GPLv3 requires corresponding-source availability.

The website is served by GitHub Pages from the root of `main`. English, Russian, and Simplified Chinese pages have descriptive titles, canonical URLs, language alternates, and a sitemap. Search engines decide when and whether to index them; rankings and indexing dates cannot be guaranteed.

## Optional automated checks

`.github/ci-examples/core.yml` contains an inactive example for Rust tests and the source audit. To enable it, move it to `.github/workflows/core.yml` and commit it with an account authorized to edit GitHub Actions workflows. It is kept inactive in the initial upload so publishing does not require granting the CLI additional workflow permissions.

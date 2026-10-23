# Contributing to TripLibre

Thanks for helping. The full guide is on the docs site: **<https://hhtdiary.org/triplibre/docs/contributing.html>**
(source: [`docs/triplibre/docs/contributing.html`](docs/triplibre/docs/contributing.html)). The short version:

1. **Set up**: `brew install xcodegen swiftlint swiftformat`, then `make test` (core tests, no simulator) and
   `make sim` (the app with demo data). Docs and linters need Node: `npm ci`.
2. **Follow the ground rules**: never modify raw observations, never overwrite user corrections, keep inference
   deterministic, no new network calls or third-party dependencies in `HHTCore` without discussion.
3. **Run what CI runs** before opening a pull request against `main`: `make ci`.
4. **Report inference problems without your location history.** Never attach an export, `travel.sqlite`, GPX file or
   map screenshot to a public issue. Describe what happened and what TripLibre recorded (durations, distances, speeds,
   silences), so it can be rebuilt as a synthetic test fixture. See
   [proposing an inference test case](https://hhtdiary.org/triplibre/docs/contributing.html#proposing-an-inference-test-case).
5. **Docs** are plain HTML in `docs/` (no Markdown build); label anything not built yet as
   Planned or Exploratory, and check field names against the code.

Use the [issue templates](https://github.com/zyang91/TripLibre/issues/new/choose) for bugs and feature requests, and
[SECURITY.md](SECURITY.md) for security problems. Everyone is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md). Contributions are accepted under the [Apache License 2.0](LICENSE).

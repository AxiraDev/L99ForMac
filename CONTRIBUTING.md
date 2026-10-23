# Contributing to L99 for Mac

Thank you for helping AULA L99 owners use their keyboard on macOS. Bug reports, translations, documentation, hardware test results, and code contributions are welcome.

## Report a bug

Use the issue template and include your Mac model, macOS version, wired USB connection details, keyboard firmware version if known, expected behavior, and observed behavior. Explain whether you verified the result on the keyboard screen or by typing. Redact personal data before sharing diagnostics; do not upload your profile or full captures unless you have reviewed them.

## Make a change

1. Fork the repository and create a branch.
2. Keep changes focused and describe the user-facing result.
3. Run `python3 scripts/check_localization.py` and `python3 scripts/audit_source.py`.
4. For protocol changes, run `cargo test --manifest-path core/Cargo.toml`.
5. On macOS, build with `bash scripts/build.sh` and run `bash scripts/test_configuration.sh`; run `bash scripts/test_audio.sh` for audio changes.
6. Open a pull request with verification results and any remaining hardware limits.

Do not bundle manufacturer binaries, firmware, artwork, disassembly, private captures, tokens, or user profiles. Preserve unknown keyboard configuration fields. Do not add firmware-write experiments to the normal configuration flow.

## Translations

Edit `resources/localization/en.json`, `ru.json`, or `zh-Hans.json`. Keep interpolation placeholders and format specifiers intact, and run the localization checker. Profile names and protocol values must stay unchanged by language selection.

## License

Contributions are provided under this project's GPL-3.0-only license. Contributors retain their authorship; no copyright assignment is requested.

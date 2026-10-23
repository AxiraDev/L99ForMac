# Languages and donations

The interface supports Russian, English, and Simplified Chinese. The selector at the bottom of the sidebar applies immediately and remembers its choice. “Follow macOS” chooses a supported preferred language, falling back to English. Traditional Chinese preferences use the Simplified Chinese translation.

App-owned labels, tooltips, accessibility descriptions, and connection/error messages are translated. Standard macOS menu titles, system error text, and file-dialog chrome may follow the operating system language. Profile names, macro names, physical key labels, and stored protocol values are not translated. No change to the keyboard display firmware language is made.

Translations live in `resources/localization/{ru,en,zh-Hans}.json`. Russian source messages are stable keys. `{0}`, `{1}`, etc. are interpolation slots; preserve each slot when editing a translation. Strings used with `String(format:)` also retain their printf specifiers. Permission prompts live in `macos/Localizations/*.lproj/InfoPlist.strings`.

Run `python3 scripts/check_localization.py` to check catalog coverage and placeholders. Localization tests also verify that language selection leaves profiles and hardware packets unchanged. Translations are authored for this application; no language files from the manufacturer's program are bundled.

## Configure the support button

The button is in the sidebar. Support is voluntary and does not gate any feature. Payment happens in the user's external browser; the app has no payment SDK or access to card details.

Before building a donation-enabled release, set your own public HTTPS page in `resources/support.json`:

```json
{
  "donationURL": "https://boosty.to/axira_dev/donate"
}
```

The current release uses the developer-supplied Boosty link above. An empty value disables the external action and shows an explanation instead. To change the destination, use your verified public donation link, then rebuild the app and distribution archives. Do not add bank details, API keys, access tokens, or another person's donation page.

This integration works with an external donation-page provider. It does not guarantee that the provider accepts a particular country, bank, card, or recipient. Eligibility and withdrawals must be verified directly with the chosen provider.

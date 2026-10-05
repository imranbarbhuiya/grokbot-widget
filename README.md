# Grokbot Widget

A local desktop companion for an existing Grok Bot. The first macOS prototype has a draggable floating character, expandable chat panel, hover feedback, a repeating pending animation, a loading indicator, and Grokbot handoff buttons. It connects to the existing bot through the official BDK extension.

<img src="docs/widget.png" alt="Floating Ciel widget with an expandable chat panel and a successful synthetic test reply" width="380" />

The screenshot uses a custom local avatar and a synthetic test conversation. Supply your own image with `GROKBOT_AVATAR_PATH`; otherwise, the launcher looks for that bot's uploaded avatar in Grok Bot's local cache and displays it with a circular crop. Custom images retain their original shape and transparency. If unavailable, it uses a simple blue dot.

## Install on macOS

Requires macOS 14 or newer and a Grok Bot account with an existing bot.

1. Download from [the latest release](https://github.com/imranbarbhuiya/grokbot-widget/releases/latest): [Apple silicon (arm64)](https://github.com/imranbarbhuiya/grokbot-widget/releases/latest/download/GrokbotWidget-macos-arm64.zip) or [Intel (x64)](https://github.com/imranbarbhuiya/grokbot-widget/releases/latest/download/GrokbotWidget-macos-x64.zip).
2. Unzip and drag **GrokbotWidget.app** to **Applications**.
3. Open **Grokbot Widget** from Finder or search for it in Raycast.
4. Enter the exact name of your existing bot. Optionally choose a custom image; leave it empty to use the bot's cached avatar.
5. Wait for first setup to download the pinned BDK dependencies. Complete the browser sign-in if prompted, using the account that owns the bot.

Node and npm are included. You do not need Terminal, Xcode, or a separate Node installation. Internet access is required for first setup and chat. The app starts its own local server and stops it when you quit. Open the app from Raycast again to bring the widget back.

Right-click the widget for **Settings…**, **Sign in…**, **Show runtime logs**, and **Quit widget**. Saving Settings quits the widget; reopen it to apply the changes. After switching accounts with Sign in, quit and reopen the widget. Desktop settings are stored in `~/Library/Application Support/Grokbot Widget/settings.json`; runtime files, logs, and private state stay in that folder. The development checkout's `.env` is separate and is not imported automatically.

These releases are ad-hoc signed, without an Apple Developer ID certificate or notarization. If macOS blocks the app, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway** for Grokbot Widget. Follow [Apple's guidance](https://support.apple.com/102445); do not disable Gatekeeper globally. Each release includes SHA-256 checksum files.

To update, quit the widget and replace the app in Applications with the latest release. Your settings remain in your user Library.

## Develop from source

Requires Node 22.13 or newer.

```sh
npm ci --ignore-scripts
cp .env.example .env
npm run bdk -- login
# Set GROKBOT_AGENT_NAME in .env to your existing bot’s exact name.
npm run check
npm run dev
```

In a second terminal, launch the native widget:

```sh
npm run widget
```

Requires macOS 14+ and Xcode command-line tools. Clicking the character or compose button opens chat. Drag the character or window background to move it anywhere on screen. A click still opens chat. The widget remembers its position after quitting. Chat opens below the character near the top edge and above it when there is room; closing chat restores the collapsed position. Right-click for Quit. The generated app bundle is in ignored `.local/GrokbotWidget.app`; launch via the npm script so its environment is supplied.

The launcher builds the Swift app, starts it independently, and returns to the terminal. “Building for debugging” is the build mode. Closing the launcher terminal or pressing Ctrl+C after launch does not quit the widget. Relaunch with `npm run widget` after quitting. Keep the separate `npm run dev` server running for chat. Native output goes to ignored `.local/widget.log`.

Avatar lookup happens at launch and reads only Grok Bot's local roster and avatar cache under `~/Library/Application Support/Grok Bot`. Custom images take priority. The cache must contain an exact match for `GROKBOT_AGENT_NAME` and an available uploaded image. Missing caches, unsupported formats, built-in dot avatars, or ambiguous matches fall back to the generic dot. No credentials or private endpoints are used. This cache format is internal to the desktop app and may change; restart the widget after changing the bot's avatar.

Set `GROKBOT_AGENT_NAME` in `.env` to the exact existing bot name. Use the account that owns that bot. The BDK can create an empty bot when a name does not exist; `grokbot__list` only lists configured names and previously contacted bots, so it cannot verify account ownership.

The server binds to loopback on port 4317. It keeps state in ignored `.local/state`. Use the private browser playground link printed by BDK; do not publish the local server or its authentication token.

## Connection test

With the server running:

```sh
npm run smoke:list
npm run bdk -- call grokbot__ask --url http://127.0.0.1:4317/grokbot-widget --input '{"message":"This is an integration test from my local widget. Reply only: GROKBOT_WIDGET_OK. Do not call tools or change any settings.","wait_seconds":20}'
```

If the result is still running, call `grokbot__check` with `{"wait_seconds":20}`. Never interrupt unrelated work for this test. A result containing `created: true` means it reached a newly created bot, not the expected existing one.

## Credentials and private data

Installed apps use BDK browser sign-in automatically when needed; source builds can use `bdk login`, `CURSOR_API_KEY`, or `CURSOR_API_KEY_FILE`. BDK login stores a dashboard-revocable credential outside this repository. `.env`, local session state, logs, and `memory/` are ignored. `.env.example` contains placeholders only. Do not put credentials in source code, shell arguments, browser assets, committed logs, or screenshots.

Before publishing, review both tracked files and Git history for private material. Bot names, IDs, and personal artwork should be supplied through local configuration rather than embedded in the shared project.

## Verified from BDK 0.2.18

The published `cursor-grokbot-agents` extension provides ask, check, list, and interrupt tools. It consults the authenticated account's Grok Bot using its existing conversation, memory, and tools. Only delivered replies are returned; the bot's internal work is not exposed. Busy bots are not sent another message. The extension requires the local runtime.

Live verification passed: the direct BDK test returned the requested marker from an existing bot (`created` was absent), and a second message sent through the native UI appeared as the expected reply in its chat panel. TypeScript checking and native compilation passed.

The open button launches Grokbot. Set `GROKBOT_OPEN_URL` to a verified `grokbot://` link to target a specific conversation. Voice uses the same handoff; start the call inside Grokbot. No native voice embedding or universal background event feed has been verified. Widget chat history is held in memory; BDK keeps private local session state.

Source: https://www.npmjs.com/package/@cursor/bdk (bundled docs/guides/grokbot-agents.md).

## Build a release

On macOS:

```sh
npm ci --ignore-scripts
npm run check
npm test
swift test --package-path native
npm run package
```

The packager downloads an official Node 24 distribution, checks its SHA-256, builds the Swift executable in release mode, and creates an ad-hoc-signed app and ZIP in ignored `dist/`. It copies only the bot source, package manifests, launcher scripts, and Node/npm runtime. Personal `.env`, images, credentials, state, and logs are excluded. BDK is installed from npm into the user's Library at first launch rather than redistributed inside the app.

The [release workflow](.github/workflows/release.yml) builds Apple silicon and Intel ZIPs and publishes them to GitHub Releases when a `v*` tag matching `package.json` is pushed. Manual workflow runs produce downloadable build artifacts without publishing. To release a new version, update `package.json` and `package-lock.json`, commit, then push the matching version tag.

## License

MIT. See [LICENSE](LICENSE).

# cmux Browser Command Reference

Use `cmux browser` against browser surfaces inside the current cmux workspace. Surface refs look like `surface:7`.

## Current Context

```bash
cmux identify --json
cmux browser identify
cmux browser identify --surface surface:2
```

## Open and Navigate

```bash
cmux browser open <url> --workspace "$CMUX_WORKSPACE_ID"
cmux browser open-split <url> --workspace "$CMUX_WORKSPACE_ID"
cmux browser new <url> --workspace "$CMUX_WORKSPACE_ID"
cmux browser <surface> open <url>
cmux browser <surface> navigate <url>
cmux browser <surface> goto <url>
cmux browser <surface> navigate <url> --snapshot-after
cmux browser <surface> back
cmux browser <surface> forward
cmux browser <surface> reload --snapshot-after
cmux browser <surface> url
cmux browser <surface> get url
cmux browser <surface> get title
cmux browser <surface> focus-webview
cmux browser <surface> is-webview-focused
```

`open`, `open-split`, and `new` accept `--workspace <id|ref>` and `--window <id|ref>`. Prefer `--workspace "$CMUX_WORKSPACE_ID"` unless the user explicitly names another target.

## Wait

```bash
cmux browser <surface> wait --load-state complete --timeout-ms 15000
cmux browser <surface> wait --selector "#checkout" --timeout-ms 10000
cmux browser <surface> wait --text "Order confirmed"
cmux browser <surface> wait --url-contains "/dashboard"
cmux browser <surface> wait --function "window.__appReady === true"
cmux browser <surface> wait "#checkout"
cmux browser <surface> wait --timeout 15 --selector "#ready"
```

## Snapshot and Screenshot

```bash
cmux browser <surface> snapshot
cmux browser <surface> snapshot --interactive
cmux browser <surface> snapshot --interactive --compact
cmux browser <surface> snapshot --selector "main" --max-depth 5
cmux browser <surface> snapshot --cursor
cmux browser <surface> screenshot
cmux browser <surface> screenshot --out /tmp/cmux-page.png
cmux browser <surface> screenshot --json
```

## DOM Actions

```bash
cmux browser <surface> click <selector-or-ref> --snapshot-after
cmux browser <surface> dblclick <selector-or-ref>
cmux browser <surface> hover <selector-or-ref>
cmux browser <surface> focus <selector-or-ref>
cmux browser <surface> check <selector-or-ref>
cmux browser <surface> uncheck <selector-or-ref>
cmux browser <surface> scroll-into-view <selector-or-ref>
cmux browser <surface> scrollintoview <selector-or-ref>
cmux browser <surface> fill <selector-or-ref> --text "value"
cmux browser <surface> fill <selector-or-ref> --text ""
cmux browser <surface> type <selector-or-ref> "text"
cmux browser <surface> press Enter
cmux browser <surface> keydown Shift
cmux browser <surface> keyup Shift
cmux browser <surface> select <selector-or-ref> "us-east"
cmux browser <surface> scroll --dy 800 --snapshot-after
cmux browser <surface> scroll --selector "#log-view" --dx 0 --dy 400
```

## Getters

```bash
cmux browser <surface> get url
cmux browser <surface> get title
cmux browser <surface> get text "h1"
cmux browser <surface> get html "main"
cmux browser <surface> get value "#email"
cmux browser <surface> get attr "a.primary" --attr href
cmux browser <surface> get count ".row"
cmux browser <surface> get box "#checkout"
cmux browser <surface> get styles "#total"
cmux browser <surface> get styles "#total" --property color
```

## State Checks

```bash
cmux browser <surface> is visible "#checkout"
cmux browser <surface> is enabled "button[type='submit']"
cmux browser <surface> is checked "#terms"
```

## Find Locators

```bash
cmux browser <surface> find role button --name "Continue"
cmux browser <surface> find role button --name "Continue" --exact
cmux browser <surface> find text "Order confirmed"
cmux browser <surface> find label "Email"
cmux browser <surface> find placeholder "Search"
cmux browser <surface> find alt "Product image"
cmux browser <surface> find title "Open settings"
cmux browser <surface> find testid "save-btn"
cmux browser <surface> find first ".row"
cmux browser <surface> find last ".row"
cmux browser <surface> find nth 2 ".row"
cmux browser <surface> highlight "#checkout"
```

## JavaScript and Injection

```bash
cmux browser <surface> eval "document.title"
cmux browser <surface> eval --script "window.location.href"
cmux browser <surface> addinitscript "window.__cmuxReady = true;"
cmux browser <surface> addscript "document.querySelector('#name')?.focus()"
cmux browser <surface> addstyle "#debug-banner { display: none !important; }"
```

## Frames

```bash
cmux browser <surface> frame "iframe[name='checkout']"
cmux browser <surface> frame --selector "iframe[name='checkout']"
cmux browser <surface> frame main
```

## Dialogs

```bash
cmux browser <surface> dialog accept
cmux browser <surface> dialog accept "Confirmed by automation"
cmux browser <surface> dialog dismiss
```

## Downloads

```bash
cmux browser <surface> click "a#download-report"
cmux browser <surface> download --path /tmp/report.csv --timeout-ms 30000
cmux browser <surface> download wait --path /tmp/report.csv --timeout 30
```

## Cookies, Storage, State

```bash
cmux browser <surface> cookies get
cmux browser <surface> cookies get --name session_id
cmux browser <surface> cookies set session_id abc123 --domain example.com --path /
cmux browser <surface> cookies set --name session_id --value abc123 --url https://example.com
cmux browser <surface> cookies clear --name session_id
cmux browser <surface> cookies clear --all

cmux browser <surface> storage local get
cmux browser <surface> storage local get theme
cmux browser <surface> storage local set theme dark
cmux browser <surface> storage local clear
cmux browser <surface> storage session get flow
cmux browser <surface> storage session set flow onboarding
cmux browser <surface> storage session clear

cmux browser <surface> state save /tmp/cmux-browser-state.json
cmux browser <surface> state load /tmp/cmux-browser-state.json
```

## Tabs

```bash
cmux browser <surface> tab list
cmux browser <surface> tab new https://example.com/pricing
cmux browser <surface> tab switch 1
cmux browser <surface> tab switch surface:7
cmux browser <surface> tab close
cmux browser <surface> tab close surface:7
```

## Console and Errors

```bash
cmux browser <surface> console list
cmux browser <surface> console clear
cmux browser <surface> errors list
cmux browser <surface> errors clear
```

## Environment and Lower-Level APIs

These commands exist in the CLI. Some may return `not_supported` on WKWebView depending on current app support.

```bash
cmux browser <surface> viewport 390 844
cmux browser <surface> geolocation 37.7749 -122.4194
cmux browser <surface> geo 37.7749 -122.4194
cmux browser <surface> offline true
cmux browser <surface> offline false
cmux browser <surface> trace start /tmp/cmux-trace.zip
cmux browser <surface> trace stop /tmp/cmux-trace.zip
cmux browser <surface> network route "**/api/*" --body '{}'
cmux browser <surface> network route "**/ads/*" --abort
cmux browser <surface> network unroute "**/api/*"
cmux browser <surface> network requests
cmux browser <surface> screencast start
cmux browser <surface> screencast stop
cmux browser <surface> input mouse move 100 200
cmux browser <surface> input keyboard press Enter
cmux browser <surface> input touch tap 100 200
```

## Output Options

```bash
cmux --json browser open https://example.com
cmux browser <surface> snapshot --interactive --json
cmux browser <surface> get text "h1" --json
cmux --json --id-format refs browser identify
cmux --json --id-format both browser identify
cmux --json --id-format uuids browser identify
```

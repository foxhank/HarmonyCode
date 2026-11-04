# Agent and model-layer tests

These tests run the app's own `core/llm` and `core/agent` sources under Node: esbuild bundles the
`.ets` files as TypeScript. Node implementations stand in for the platform pieces (HTTP transport,
file system, shell).

Run them with the Node that ships with DevEco Studio (or any Node 18+):

```bash
node tests/agent/build.mjs unit
```

```bash
node tests/agent/build.mjs tools
```

```bash
node tests/agent/build.mjs web
```

```bash
node tests/agent/build.mjs llm path/to/account.txt
```

```bash
node tests/agent/build.mjs agent path/to/account.txt anthropic
```

- `unit`: offline. Covers the OpenAI Responses adapter (request shape and stream decoding through
  a replaying transport), retries, the SSE parser, glob, diff, edit safety and compaction.
- `tools`: offline. multi_edit, move_path, full-access paths (remote machines, Windows drives),
  command approval rules, background jobs (run_command in the background, command_output,
  kill_command), ask_user, HTML to text, and the loop itself with a scripted model: parallel
  read-only calls, messages sent while the agent works, and sub-agents (task).
- `web`: live. Web search with the key-free provider and fetching a page.
- `llm`: live. Plain text, streaming, tool calls, a tool-result round trip, cancellation and a
  bad-key error, for each format the account offers.
- `agent`: live, end to end. The agent fixes a buggy project and verifies the fix by running its
  tests. The suite also covers a denied command and stopping mid-command. The last argument picks
  the wire format: `openai-chat` (default) or `anthropic`.

The account file is plain text. It contains the API key (`sk-...`) and lines
`base_url (OpenAI) <url>`, `base_url (Anthropic) <url>` and `model_name <id>`. The key is never
printed. Never commit the account file.

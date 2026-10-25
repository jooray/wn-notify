# wn-notify

wn-notify is a small command line tool that sends text messages and files to a White Noise group. It is one Python file that uses only the standard library. It talks to a local `wn-agent` over a Unix socket, so it never touches your keys.

This is an unofficial tool. It is not affiliated with or endorsed by the Marmot or White Noise projects.

## Why

I want agents and scripts to tell me things in an end-to-end encrypted messenger: a long job finished, a backup failed, a build produced a file. For SimpleX there is `simplex-msg`. wn-notify does the same for White Noise, with the same habit of use: `wn-msg "done"` from a shell, a cron job or a coding agent.

## How it works

wn-notify is a client of the local control protocol `marmot.agent-control.v2` (newline-delimited JSON over a Unix socket). The server side is `wn-agent`, which belongs to the Marmot Development Kit (MDK). It owns the Nostr account, the MLS group state, the relays and the encrypted sends.

- Marmot protocol: <https://github.com/marmot-protocol/marmot>
- MDK, which ships `wn-agent`: <https://github.com/marmot-protocol/mdk> (MIT license)
- Integrations overview and installers: <https://github.com/marmot-protocol/mdk/blob/master/integrations/README.md>
- Guide for writing your own client (notifier bots and scripts): <https://github.com/marmot-protocol/mdk/blob/master/integrations/custom-client.md>
- White Noise apps: <https://github.com/marmot-protocol>

I checked the protocol name and the `wn-agent` role against those upstream documents and against `wn-agent --help`. The version I run is `wn-agent 0.13.0`. I have not tested wn-notify against other versions.

## Requirements

- Python 3 (standard library only).
- macOS or Linux. I run it on macOS (Apple Silicon).
- A running `wn-agent` with its own identity, listening on a Unix socket. The upstream guide above covers installing it (`install-wn-agent.sh`, or the guided installers for the agent connectors) and creating the identity with `wn-agent bootstrap`.
- `wn-agent` must be started with `--media-allowed-root` pointing at the directory wn-notify stages files in (the `staging_root` below). The flag is repeatable and its default is to deny all outbound media. This only matters for `wn-file`.
- White Noise on your phone, or another White Noise client, to receive the messages.
- A config directory with `notify.json` and `bootstrap.json` (see below).

The notification identity should belong to this connector alone and should not be signed in on another client, as the upstream guide says.

## Install

```sh
git clone <this repository> wn-notify
cd wn-notify
./install.sh            # links into ~/.local/bin, or pass another directory
```

This creates `wn-notify` plus three symlinks to it: `wn-msg`, `wn-stdin` and `wn-file`. The script looks at the name it was called by. `wn-msg` and `wn-stdin` mean `wn-notify msg`, and `wn-file` means `wn-notify file`.

Make sure the target directory is on your `PATH`.

## Configuration

By default wn-notify reads `~/.marmot-agents/notify/`. Set `WN_NOTIFY_HOME` to use another directory. It needs two files, both owner-only (mode 0600) regular files:

- `bootstrap.json` is the JSON that `wn-agent bootstrap --json` prints. wn-notify only reads the `npub` and `nprofile` fields from it, for the `identity` command.
- `notify.json` has four keys:

```json
{
  "account_id_hex": "<ACCOUNT_ID_HEX>",
  "group_id_hex": "<GROUP_ID_HEX>",
  "socket": "/path/to/wn-agent.sock",
  "staging_root": "/path/to/owner-only/directory"
}
```

`account_id_hex` is the `account_id_hex` from `bootstrap.json` (64 hex characters). `socket` is the control socket of the running `wn-agent`. `staging_root` is an owner-only directory (mode 0700), for example `~/.marmot-agents/notify/outbound-media`, that is covered by the agent's `--media-allowed-root`. `group_id_hex` can be left out at first. `bind` or `create-group` fills it in.

You write `notify.json` yourself, and the tool does not create it. Keep it mode 0600.

## Setup flow

1. Print the notification identity and add it as a contact in White Noise:

   ```sh
   wn-notify identity       # prints the npub and the nprofile
   ```

2. Connect it to a group. There are two ways.

   Option A, the tool creates the group. Give it the npub of every member you want in it (your own account, at least). Run this once and do not retry blindly, because a timeout can be ambiguous and a retry can make a second group:

   ```sh
   wn-notify create-group --name "Notifications" --member <YOUR_NPUB>
   ```

   It binds the new group automatically. Accept the invite in White Noise. A member needs a published KeyPackage, which usually means they have opened White Noise at least once.

   Option B, you create or invite the group in White Noise. Start listening, then send a message from White Noise to the group:

   ```sh
   wn-notify listen         # prints group ids as events arrive, never message text
   wn-notify bind <GROUP_ID_HEX>
   ```

   `listen` stops after 300 seconds by default. Use `--timeout SECONDS` to change that. `bind` asks the connector to confirm that the group is known before it saves the id.

   Option B needs the agent to accept the invite. By default `wn-agent` refuses invites. Allow the inviter with `--allow-welcomer` when you bootstrap, as described in the upstream guide.

3. Check that it works:

   ```sh
   wn-notify status         # connector diagnostics and the bound destination
   wn-msg "hello from wn-notify"
   ```

## Usage

Text as arguments:

```sh
wn-msg "backup finished on $(hostname)"
```

Text from stdin, for pipes:

```sh
make test 2>&1 | tail -n 20 | wn-stdin
echo "disk is 91% full" | wn-msg
```

Files, with an optional caption:

```sh
wn-file ./report.pdf "Nightly report"
wn-file ./voice-note.m4a
```

The long forms work too: `wn-notify msg ...` and `wn-notify file PATH [CAPTION...]`.

### Environment variables

| Variable | Meaning |
| --- | --- |
| `WN_DESTINATION` | Group id (hex) to use instead of the bound one, for one command or one script. |
| `WN_NOTIFY_HOME` | Config directory. Default `~/.marmot-agents/notify`. |

```sh
WN_DESTINATION=<GROUP_ID_HEX> wn-msg "goes to another group"
```

## Idempotency keys and retries

Every send carries an idempotency key. If you do not pass one, wn-notify makes a random UUID. When a send cannot be confirmed (timeout, closed socket, unexpected reply), the tool fails with exit code 1 and prints the key:

```
wn-notify: send not confirmed; retry with --idempotency-key <KEY>: ...
```

Retry with the same key, and the connector can recognise the request as a repeat instead of posting a second copy. This is the contract in the upstream guide: a retry with the same `idempotency_key` returns the original message ids. For a send you want to be safe to repeat from a script, pick the key yourself:

```sh
wn-notify msg --idempotency-key nightly-backup-2026-10-25 "backup done"
wn-notify file --idempotency-key report-2026-10-25 ./report.pdf "Nightly report"
```

On success it prints `Published to group relays (not a recipient read receipt)` and the key. Ctrl-C exits with code 130 and a note that delivery may be uncertain.

## Limits

- Text: at most 60000 bytes of UTF-8. Longer text is refused, and the message tells you to use `wn-file`. Empty or whitespace-only text is refused.
- Files: regular files only, smaller than 512 MiB (the limit is 512 MiB minus 16 bytes, to match the connector's cap).
- File timeout: up to 46 minutes, because the connector may try three upload servers with fifteen-minute deadlines each.
- Other requests time out after 30 seconds, and `create-group` after 120 seconds.
- Control frames are limited to 1 MiB.

## Security notes

- Config files must be regular files owned by you and not readable by group or others. wn-notify refuses to read anything else. Config and the staged copy are opened without following symlinks.
- The config directory cannot be a symlink when wn-notify writes to it. Writes go through a temporary file and an atomic rename.
- For `wn-file`, the source must be a regular file and not a symlink. The tool copies it into `staging_root` (a private temporary directory there, mode 0600) and checks that the source did not change or grow while copying. The temporary copy is removed afterwards.
- `staging_root` must be an owner-only real directory, or the file send is refused.
- The control socket is a local, same-user channel. Anyone who can reach it can send as the notification identity, so keep the socket and `wn-agent`'s home owner-only.
- "Published to group relays" means the connector sent the encrypted message to the relays. It does not mean anyone read it.
- Error messages from the connector are reduced to a short code before they are printed.
- `listen` prints only group ids and event types, never message text.
- `identity` prints your notification identity's public `npub` and `nprofile`. Do not paste secret keys anywhere.

## Troubleshooting

- `configuration must be an owner-only regular file`: run `chmod 600` on the file.
- `no valid destination`: bind a group first, or set `WN_DESTINATION`.
- `connector rejected request (code)`: the code comes from `wn-agent`. Start with `wn-notify status`.
- Connection errors: check that `wn-agent` is running and that `socket` in `notify.json` is the right path.

## License

MIT. See [LICENSE](LICENSE).

# Slack helpers.
#
# Setup (one-off, see also project docs):
#   1. Create a Slack app at https://api.slack.com/apps (From scratch).
#   2. OAuth & Permissions → add User Token Scope `chat:write` (so messages
#      are sent AS you and appear in your existing DMs/channels).  A Bot
#      Token cannot post into a DM between two human users.
#   3. Install to workspace; copy the User OAuth Token (starts with `xoxp-`).
#   4. Add to ~/.secrets.local (already sourced by zshrc):
#        export SLACK_APP_PR_NOTIFY_TOKEN=xoxp-...
#
# Channel/conversation IDs (e.g. D0A73CUMPQE for a DM) can be found in Slack
# via the conversation's "View details" → "More" → "Copy member ID" /
# "Copy channel ID".

# Post a message to a Slack channel/DM/MPIM/user.
#
# Usage: slack_post_message <channel-id> <text> [--debug]
#
# Returns 0 on success, non-zero on failure.  Stderr carries any error.
slack_post_message() {
  local channel="" text="" DEBUG=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      if [[ -z "$channel" ]]; then
        channel="$1"
      elif [[ -z "$text" ]]; then
        text="$1"
      else
        error "slack_post_message: unexpected extra argument: $1"
        return 1
      fi
      shift
      ;;
    esac
  done

  if [[ -z "$channel" || -z "$text" ]]; then
    error "Usage: slack_post_message <channel-id> <text> [--debug]"
    return 1
  fi

  if [[ -z "$SLACK_APP_PR_NOTIFY_TOKEN" ]]; then
    error "SLACK_APP_PR_NOTIFY_TOKEN is not set.  See cp/slack.zsh header for setup."
    return 1
  fi

  local payload
  payload=$(jq -n --arg channel "$channel" --arg text "$text" \
    '{channel: $channel, text: $text}')

  [[ "$DEBUG" == "true" ]] && debug "slack payload: $payload"

  local response
  response=$(curl -sS -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer $SLACK_APP_PR_NOTIFY_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$payload")
  local curl_exit=$?

  if [[ $curl_exit -ne 0 ]]; then
    error "curl failed posting to Slack (exit $curl_exit)"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "slack response: $response"

  local ok
  ok=$(jq -r '.ok' <<<"$response")
  if [[ "$ok" != "true" ]]; then
    local slack_error
    slack_error=$(jq -r '.error // "unknown"' <<<"$response")
    error "Slack API error: $slack_error"
    return 1
  fi

  return 0
}

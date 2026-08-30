#!/usr/bin/env bash
# Claude Code statusLine wrapper around `ccusage statusline`.
#
# ccusage renders a fixed, un-configurable line:
#   model | cost | burn-rate | context
# `commands.statusline` in ccusage's config-schema.json exposes only
# thresholds/colours, costSource, visualBurnRate and modelLabelAliases - there
# is no knob to reorder, drop or trim a segment, and from v20 ccusage ships as a
# native binary (the npm package is just a launcher) so it can't be patched
# either.  Hence this wrapper, which post-processes the rendered line.
#
# It does two things, both configurable below:
#   1. Renders only the segments in KEEP_SEGMENTS, in that order.
#   2. Trims the cost segment to its "session" component.
#
# The default is the short form, because Claude Code truncates the statusline
# from the right - context-% is the segment worth keeping and was the first to
# vanish in a narrow pane:
#   🤖 Opus 5 (1M context) | 🧠 115,831 (58%) | 💰 $1.23 session
#
# Anything unrecognised is passed through untouched, so the statusline degrades
# to stock ccusage rather than going blank.  ANSI colour survives because
# ccusage keeps its escape codes self-contained within a segment.

set -uo pipefail

# ---- Configuration ---------------------------------------------------------

# Segments to render, in render order, identified by their leading emoji.  A
# segment whose marker is not listed here is DROPPED - including any segment a
# future ccusage version adds, so re-check this list after a major upgrade.
KEEP_SEGMENTS=(
	$'\U0001F916' # 🤖 model
	$'\U0001F9E0' # 🧠 context tokens + %
	$'\U0001F4B0' # 💰 cost
	# $'\U0001F525' # 🔥 burn rate - dropped; uncomment to restore
)

# Trim the cost segment down to its "session" component, dropping the
# "/ today / block (Nh Nm left)" tail.  Set to 0 to keep the full breakdown.
TRIM_COST_TO_SESSION=1

CCUSAGE_BIN="${CCUSAGE_BIN:-/usr/local/bin/ccusage}"

# ---- Render ----------------------------------------------------------------

# Claude Code pipes the session JSON on stdin; command substitution inherits it.
line=$("$CCUSAGE_BIN" statusline "$@")
status=$?

# On any ccusage failure emit whatever it managed to produce, verbatim.
if ((status != 0)) || [[ -z $line ]]; then
	printf '%s\n' "$line"
	exit 0
fi

sep=' | '

# Split the rendered line on the segment separator.
segments=()
rest=$line
while [[ $rest == *"$sep"* ]]; do
	segments+=("${rest%%"$sep"*}")
	rest=${rest#*"$sep"}
done
segments+=("$rest")

# Trim "💰 $1.23 session / $0.00 today / $0.00 block (2h 18m left)" down to
# "💰 $1.23 session".  Splitting on " / " and keeping through the component
# containing "session" (rather than simply taking the first) keeps this correct
# under `costSource: both`, where the leading component is the parenthesised
# "(<cc> / <ccusage>) session".
trim_cost() {
	local segment=$1 out= chunk rest=$1
	while :; do
		if [[ $rest == *' / '* ]]; then
			chunk=${rest%%' / '*}
			rest=${rest#*' / '}
		else
			chunk=$rest
			rest=
		fi
		out=${out:+$out / }$chunk
		[[ $chunk == *session* ]] && {
			printf '%s' "$out"
			return
		}
		# Format changed - no "session" component. Leave the segment alone.
		[[ -z $rest ]] && {
			printf '%s' "$segment"
			return
		}
	done
}

# Emit the kept segments in KEEP_SEGMENTS order.
out=
for marker in "${KEEP_SEGMENTS[@]}"; do
	for segment in "${segments[@]}"; do
		[[ $segment == *"$marker"* ]] || continue
		if ((TRIM_COST_TO_SESSION)) && [[ $marker == $'\U0001F4B0' ]]; then
			segment=$(trim_cost "$segment")
		fi
		out=${out:+$out$sep}$segment
		break
	done
done

# Matched nothing (marker set out of date?) - fall back to stock ccusage.
if [[ -z $out ]]; then
	printf '%s\n' "$line"
	exit 0
fi

printf '%s\n' "$out"

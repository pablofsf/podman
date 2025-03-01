#!/usr/bin/env bats
#
# Simplest set of podman tests. If any of these fail, we have serious problems.
#

load helpers

# Override standard setup! We don't yet trust podman-images or podman-rm
function setup() {
    :
}

@test "podman --context emits reasonable output" {
    run_podman 125 --context=swarm version
    is "$output" "Error: Podman does not support swarm, the only --context value allowed is \"default\"" "--context=default or fail"

    run_podman --context=default version
}

@test "podman version emits reasonable output" {
    run_podman version

    # First line of podman-remote is "Client:<blank>".
    # Just delete it (i.e. remove the first entry from the 'lines' array)
    if is_remote; then
        if expr "${lines[0]}" : "Client:" >/dev/null; then
            lines=("${lines[@]:1}")
        fi
    fi

    is "${lines[0]}" "Version:[ ]\+[1-9][0-9.]\+" "Version line 1"
    is "$output" ".*Go Version: \+"               "'Go Version' in output"
    is "$output" ".*API Version: \+"		  "API version in output"

    # Test that build date is reasonable, e.g. after 2019-01-01
    local built=$(expr "$output" : ".*Built: \+\(.*\)" | head -n1)
    local built_t=$(date --date="$built" +%s)
    if [ $built_t -lt 1546300800 ]; then
        die "Preposterous 'Built' time in podman version: '$built'"
    fi
}


@test "podman can pull an image" {
    run_podman pull $IMAGE
}

# PR #7212: allow --remote anywhere before subcommand, not just as 1st flag
@test "podman-remote : really is remote, works as --remote option" {
    if ! is_remote; then
        skip "only applicable on podman-remote"
    fi

    # First things first: make sure our podman-remote actually is remote!
    run_podman version
    is "$output" ".*Server:" "the given podman path really contacts a server"

    # $PODMAN may be a space-separated string, e.g. if we include a --url.
    # Split it into its components; remove "-remote" from the command path;
    # and preserve any other args if present.
    local -a podman_as_array=($PODMAN)
    local    podman_path=${podman_as_array[0]}
    local    podman_non_remote=${podman_path%%-remote}
    local -a podman_args=("${podman_as_array[@]:1}")

    # This always worked: running "podman --remote ..."
    PODMAN="${podman_non_remote} --remote ${podman_args[@]}" run_podman version
    is "$output" ".*Server:" "podman --remote: contacts server"

    # This was failing: "podman --foo --bar --remote".
    PODMAN="${podman_non_remote} --log-level=error ${podman_args[@]} --remote" run_podman version
    is "$output" ".*Server:" "podman [flags] --remote: contacts server"

    # ...but no matter what, --remote is never allowed after subcommand
    PODMAN="${podman_non_remote} ${podman_args[@]}" run_podman 125 version --remote
    is "$output" "Error: unknown flag: --remote" "podman version --remote"
}

# Check that just calling "podman-remote" prints the usage message even
# without a running endpoint. Use "podman --remote" for this as this works the same.
@test "podman-remote: check for command usage message without a running endpoint" {
    if is_remote; then
        skip "only applicable on a local run since this requires no endpoint"
    fi

    run_podman 125 --remote
    is "$output" "Error: missing command 'podman COMMAND'" "podman remote show usage message without running endpoint"
}

# This is for development only; it's intended to make sure our timeout
# in run_podman continues to work. This test should never run in production
# because it will, by definition, fail.
@test "timeout" {
    if [ -z "$PODMAN_RUN_TIMEOUT_TEST" ]; then
        skip "define \$PODMAN_RUN_TIMEOUT_TEST to enable this test"
    fi
    PODMAN_TIMEOUT=10 run_podman run $IMAGE sleep 90
    echo "*** SHOULD NEVER GET HERE"
}


# Too many tests rely on jq for parsing JSON.
#
# If absolutely necessary, one could establish a convention such as
# defining PODMAN_TEST_SKIP_JQ=1 and adding a skip_if_no_jq() helper.
# For now, let's assume this is not absolutely necessary.
@test "jq is installed and produces reasonable output" {
    type -path jq >/dev/null || die "FATAL: 'jq' tool not found."

    run jq -r .a.b < <(echo '{ "a": { "b" : "you found me" } }')
    is "$output" "you found me" "sample invocation of 'jq'"
}

# vim: filetype=sh

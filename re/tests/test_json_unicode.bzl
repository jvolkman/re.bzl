"""Test JSON Unicode trick."""

def _test_json_unicode_impl(ctx):
    u_escaped = '"\\uD83D\\uDE00"'
    u3 = json.decode(u_escaped)

    # print("uD83D\uDE00: " + u3 + " (len: " + str(len(u3)) + ")")
    print("Emoji: " + u3 + " (len: " + str(len(u3)) + ")")

    encoded_bytes = []
    for i in range(len(u3)):
        c = u3[i]
        encoded_bytes.append(c)

    print("Bytes: " + str(encoded_bytes))

    return []

test_json_unicode = rule(
    implementation = _test_json_unicode_impl,
)

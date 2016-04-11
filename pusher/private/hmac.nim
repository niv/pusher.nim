
{.compile: "hmac_sha2.c".}
{.compile: "sha2.c".}

proc hmac_sha224(key: cstring; key_size: cuint; message: cstring;
                 message_len: cuint; mac: cstring; mac_size: cuint) {.importc.}
proc hmac_sha256(key: cstring; key_size: cuint; message: cstring;
                 message_len: cuint; mac: cstring; mac_size: cuint) {.importc.}
proc hmac_sha384(key: cstring; key_size: cuint; message: cstring;
                 message_len: cuint; mac: cstring; mac_size: cuint) {.importc.}
proc hmac_sha512(key: cstring; key_size: cuint; message: cstring;
                 message_len: cuint; mac: cstring; mac_size: cuint) {.importc.}

proc sha224(message: cstring; len: cuint; digest: cstring) {.importc.}
proc sha256(message: cstring; len: cuint; digest: cstring) {.importc.}
proc sha384(message: cstring; len: cuint; digest: cstring) {.importc.}
proc sha512(message: cstring; len: cuint; digest: cstring) {.importc.}

import hex

proc hmac256*(signme: string, secret: string): string =
  var mac = newstring(256 div 8)

  hmac_sha256(
    secret.cstring, secret.len.cuint,
    signme.cstring, signme.len.cuint,
    mac.cstring, mac.len.cuint)

  result = mac.encodeHex

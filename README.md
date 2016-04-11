# pusher.com nim bindings

This is a fully async pusher.com nim library.

Some notes:

* You'll have to compile with -d:ssl if you want to use SSL (the default)
* Uses http-keepalive.
* Only the serverside parts (REST API) are implemented.
* Threading (-d:threads) is currently not supported and unlikely to be added
  unless someone motivates me.
* Uses a native hmac256 library, because nim stdlib doesn't support that yet.
  That library is Copyright (C) 2005 Olivier Gay <olivier.gay@a3.epfl.ch> under
  the 3-clause found in pusher/private/hmac_sha2.h.

Upcoming features (in order/on request):

* helpers to use webhooks with asynchttpserver
* client support (websockets), including channel/user state tracking

Please check the API docs for further details (linked in the github description).

## http component

```nim
require asyncdispatch
require pusher/http

let p = newAsyncPusherHttp(123, "key", "secret")

proc run() {.async} =
	await p.publish(@["a", "b"], "event", "message")

waitFor run()
```


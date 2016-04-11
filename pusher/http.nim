import json, strutils, sequtils, strtabs, times, md5, httpclient, cgi, tables,
  logging, asyncdispatch

import private/hmac

type
  PusherError* = object of Exception

  PusherHttpObj = object of RootObj
    appId*: int
    appKey*: string
    appSecret: string
    apiBase: string
    client: AsyncHttpClient

  PusherHttp = ref PusherHttpObj

proc newAsyncPusherHttp*(appId: int, appKey: string, appSecret: string,
    ssl = true): PusherHttp =

  ## Creates a new async pusher client.
  ## Pass in the pusher credentials you get from the dashboard.

  new result
  result.appId = appId
  result.appKey = appKey
  result.appSecret = appSecret
  result.client = newAsyncHttpClient("https://github.com/niv/pusher.nim")
  result.client.headers["Content-Type"] = "application/json"
  result.client.headers["Accept"] = "application/json"
  result.apiBase = if ssl: "https://api.pusherapp.com/" else: "http://api.pusherapp.com/"

# proc `$`*(p: PusherHttp): string = "PusherHttp: " & $p.appId

proc auth*(p: PusherHttp, socketId: string, channel: string,
      userId: string = "", userInfo: seq[(string, string)] = @[]):
    tuple[auth: string, channelData: string] =

  ## Generate a authentication token for the given socket/channel and user data.
  ## Note that presence channels will require at least userId to be filled.

  if channel.startsWith("presence-") and userId == "":
    raise newException(ValueError, "presence channels require a user id parameter (" &
      "while generating auth for channel " & channel & ")")

  let ud = newJObject()
  if userId != "":
    ud["user_id"] = %userId
    ud["user_info"] = newJObject()
    for k in userInfo: ud["user_info"][k[0]] = %(k[1])

  let sud = $ud
  let sig = p.appKey & ":" & hmac256(socketId & ":" & channel & ":" & sud, p.appSecret)
  result = (auth: sig, channelData: sud)

proc makeSignedUrl(p: PusherHttp, meth: string, path: string,
    queryParams: seq[(string, string)] = @[],
    bodySig: string = ""): string =

  var oqp = queryParams.toOrderedTable

  oqp["auth_key"] = p.appKey
  oqp["auth_timestamp"] = $(getTime().int)
  oqp["auth_version"] = "1.0"

  if bodySig != "": oqp["body_md5"] = bodySig

  oqp.sort(
    proc (x: (string, string), y: (string, string)): int =
      cmp(x[0], y[0])
  )

  var qp = ""
  for key, value in oqp.pairs: qp &= key & "=" & value & "&"
  qp = qp.strip(leading = false, chars = {'&'})

  let path = "/apps/$1/$2" % [ $p.appId, path ]

  let signme = "$1\n$2\n$3" % [ meth, path, qp ]
  # echo "signme: " & signme

  let sig = hmac256(signme, p.appSecret)

  if qp != "": qp &= "&"
  qp &= "auth_signature=" & sig

  result = p.apiBase & "$1?$2" % [ path, qp ]

proc doGet*(p: PusherHttp, path: string,
    queryParams: seq[(string, string)] = @[]): Future[string] {.async.} =

  ## Make a request to the pusher backend. Returns the body string
  ## on completion. Raises PusherError (with the error message) on any
  ## problems coming from pusher.
  ## This is exposed here for convenience in case the API changes without
  ## this lib being updated.

  let r = await p.client.get(p.makeSignedUrl("GET", path, queryParams))
  if not r.status.startsWith("200"):
    raise newException(PusherError, r.body)
  result = r.body

proc doPost*(p: PusherHttp, path: string, body: JsonNode,
    queryParams: seq[(string, string)] = @[]): Future[JsonNode] {.async.} =

  ## Make a request to the pusher backend. Returns the body string
  ## on completion. Raises PusherError (with the error message) on any
  ## problems coming from pusher.
  ## This is exposed here for convenience in case the API changes without
  ## this lib being updated.

  let strBody = $body
  let r = await p.client.post(p.makeSignedUrl(path, getMD5(strBody), queryParams),
    strBody)
  if not r.status.startsWith("200"):
    raise newException(PusherError, r.body)
  else: result = parseJson(r.body)

proc publish*(p: PusherHttp, channels: seq[string], event: string,
    data: string, socketId = ""): Future[void] {.async.} =

  ## Publishes a message through pusher.
  ## Will raise exceptions on error.

  let postBody = %*{
    "name": event,
    "data": data,
    "channels": channels.mapIt(%it),
  }
  if socketId != "": postBody["socket_id"] = %socketId

  discard await p.doPost("events", postBody)

proc occupiedChannels*(p: PusherHttp, filterByPrefix = ""):
    Future[seq[string]] {.async.} =

  ## Get all channels with members in them.
  ## Does not support custom attributes right now.

  let r = await p.doGet("channels", @[("filter_by_prefix", filterByPrefix)])
  result = parseJson(r)["channels"].getFields().mapIt(it.key)

proc occupiedPresenceChannels*(p: PusherHttp, filterByPrefix = ""):
    Future[seq[tuple[channel: string, userCount: int]]] {.async.} =

  ## Get all presence channels (optionally filtered by prefix)
  ## including their member counts.

  let pfx = if not filterByPrefix.startsWith("presence-"):
    "presence-" & filterByPrefix else: filterByPrefix

  let r = await p.doGet("channels", @[("info", "user_count"),
    ("filter_by_prefix", pfx)])

  result = parseJson(r)["channels"].getFields().
    mapIt((channel: it.key, userCount: it.val["user_count"].getNum.int))

proc presenceChannelUsers*(p: PusherHttp, channel: string):
    Future[seq[string]] {.async.} =

  ## Returns a list of user ids currently subscribed to a single presence channel.
  ## "presence-" will be prefixed for you if you leave it off.
  ## Will return a empty list if the channel does not exist.

  let ch = if channel.startsWith("presence-"): channel else: "presence-" & channel

  let r = await p.doGet("channels/" & ch.encodeUrl & "/users")
  result = parseJson(r)["users"].getElems().mapIt(it["id"].str)

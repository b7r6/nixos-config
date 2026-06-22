-- | Standalone smoke test: queue a URL against a running stub and log the
-- | classified result. Run with node after `spago build`:
-- |   node -e 'import("./output/QueueTest/index.js").then(m=>m.main())'
module QueueTest (main) where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class.Console (log)
import Queue (QueueResult(..), queueUrl)

main :: Effect Unit
main = launchAff_ do
  let cfg = { endpoint: "http://127.0.0.1:8946/queue", token: "" }
  result <- queueUrl cfg "https://soundcloud.com/notakermusic/sets/melting-bismuth"
  case result of
    Queued title -> log ("QUEUED ok: " <> title)
    Failed err -> log ("FAILED: " <> err)

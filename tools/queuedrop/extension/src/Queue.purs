-- | The queuedrop client: config (endpoint + token from storage) and the
-- | POST /queue call, with JSON decoding of the {ok,title,error} contract.
-- | Pure HTTP/JSON client for the queue endpoint — NO WebExtension deps, so it
-- | is testable under plain node. Config loading lives in Queue.Config.
module Queue
  ( Config
  , defaultEndpoint
  , QueueResult(..)
  , queueUrl
  ) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.Argonaut.Core (Json, toObject, toString, toBoolean)
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, attempt)
import Effect.Exception (message)
import Foreign.Object as FO

type Config =
  { endpoint :: String
  , token :: String
  }

defaultEndpoint :: String
defaultEndpoint = "http://guccimane:8946/queue"

foreign import postQueueImpl
  :: String -> String -> String -> Effect (Promise String)

data QueueResult
  = Queued String -- resolved title
  | Failed String -- error message

-- | POST the url to the configured endpoint and classify the response.
queueUrl :: Config -> String -> Aff QueueResult
queueUrl cfg url = do
  res <- attempt (toAffE (postQueueImpl cfg.endpoint cfg.token url))
  pure case res of
    Left err -> Failed (message err)
    Right body -> decodeBody body

decodeBody :: String -> QueueResult
decodeBody body =
  case jsonParser body of
    Left _ -> Failed "bad response (not json)"
    Right json -> fromJson json

fromJson :: Json -> QueueResult
fromJson json =
  case toObject json of
    Nothing -> Failed "bad response (not an object)"
    Just obj ->
      let
        ok = fromMaybe false (toBoolean =<< FO.lookup "ok" obj)
        title = fromMaybe "queued" (toString =<< FO.lookup "title" obj)
        err = fromMaybe "unknown error" (toString =<< FO.lookup "error" obj)
      in
        if ok then Queued title else Failed err

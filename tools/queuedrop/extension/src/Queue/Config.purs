-- | Config loading for the queue client — reads endpoint/token from extension
-- | sync storage (WebExtension-dependent, so split from the pure Queue module).
module Queue.Config (loadConfig) where

import Prelude

import Data.Maybe (fromMaybe)
import Effect.Aff (Aff)
import Queue (Config, defaultEndpoint)
import WebExt (storageGet)

-- | Read endpoint/token from sync storage, falling back to defaults.
loadConfig :: Aff Config
loadConfig = do
  ep <- storageGet "endpoint"
  tk <- storageGet "token"
  pure
    { endpoint: fromMaybe defaultEndpoint ep
    , token: fromMaybe "" tk
    }
